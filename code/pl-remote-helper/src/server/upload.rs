//! 上传的请求独占暂存区与原子发布。
//!
//! 暂存区由 [`cap_tempfile::TempDir`] 在目标 parent capability 内创建，与最终目标同一文件系统，
//! 因此 `hard_link`（create，原子拒绝已存在）与 `rename`（overwrite，原子替换）都是目录能力内
//! 的原子操作，不需要重新解析 ambient 路径。暂存区权限先设为私有，内部固定 leaf 用
//! `create_new` 独占创建；写入口只是普通文件句柄，增量 IO 不会长期占用阻塞线程。
//!
//! 暂存区的收束分两层。正常失败（准备后的 `Ready` 发送失败、非法 offset、超长正文、记录
//! 损坏、写错误、提前 EOF、长度不符、`sync` 失败）由 [`StagedUpload::discard`] 在阻塞上下文
//! **显式删除**，调用方在返回前 `await` 这次收束：操作流一直持有到删除真实结束，因此健康期
//! 不会累积「已部分写盘的暂存目录 + 删除闭包」。只有整条连接被 abort 或结果接收者已被取消时
//! 才会走 [`StagedUpload::drop`] 的兜底移交（O(1) 登记，无法在此做 IO），由连接收尾统一执行。
//!
//! 发布本身在 [`super::tasks::BlockingTasks`] 里执行；线性化点是「发布 job 被连接 owner 接纳」，
//! 不是之后的 `hard_link`/`rename` 开始——受理之后的取消仍由 owner 裁决到真实终态，受理之前的
//! 失败与取消只丢弃暂存区，不会产生发布。

use std::ffi::OsString;
use std::io;
use std::path::PathBuf;

use cap_fs_ext::{FollowSymlinks, OpenOptionsFollowExt};
use cap_std::fs::{Dir, OpenOptions, OpenOptionsExt, Permissions, PermissionsExt};
use cap_tempfile::TempDir;
use pl_protocol::remote::{RemoteError, RemoteErrorCode, RemoteWriteMode};

use super::fd::LeasedFd;
use super::path::{Target, io_error, remote_error, symbolic_link};
use super::tasks::BlockingTasks;

/// 暂存区内的固定单段文件名；暂存区本身由 [`TempDir`] 请求独占。
const STAGED_LEAF: &str = "upload";

/// 一次上传的暂存区与发布意图；暂存区由本类型显式收束，不依赖 `TempDir` 的静默 Drop。
pub(super) struct StagedUpload {
    /// 暂存目录本身也是一个 FD：声明在 parent 之前，先关闭再归还预算。
    stage: Option<TempDir>,
    /// 目标 parent 能力与本次上传的 FD 预算不可分。
    parent: LeasedFd<Dir>,
    leaf: OsString,
    mode: RemoteWriteMode,
    permissions: Option<Permissions>,
    tasks: BlockingTasks,
}

/// create/overwrite 的暂存准备：校验目标、创建请求独占暂存区并建固定内部 leaf。
pub(super) async fn stage(
    target: Target,
    mode: RemoteWriteMode,
) -> Result<(StagedUpload, LeasedFd<std::fs::File>), RemoteError> {
    // 预算随 Target 一起移交：暂存区、写句柄与发布/清理都在同一份 lease 内计费。
    let (parent, leaf, display, tasks) = target.into_parts();
    let worker = tasks.clone();
    tasks
        .run(move || begin(parent, leaf, display, mode, worker))
        .await
}

fn begin(
    parent: LeasedFd<Dir>,
    leaf: OsString,
    display: PathBuf,
    mode: RemoteWriteMode,
    tasks: BlockingTasks,
) -> Result<(StagedUpload, LeasedFd<std::fs::File>), RemoteError> {
    let existing = match parent.get().symlink_metadata(&leaf) {
        Ok(metadata) => Some(metadata),
        Err(error) if error.kind() == io::ErrorKind::NotFound => None,
        Err(error) => {
            return Err(io_error("failed to inspect upload target", error));
        }
    };
    if let Some(metadata) = &existing {
        if metadata.file_type().is_symlink() {
            return Err(symbolic_link(&leaf));
        }
        if metadata.is_dir() {
            return Err(remote_error(
                RemoteErrorCode::InvalidRequest,
                "upload target is a directory",
            ));
        }
        if !metadata.is_file() {
            return Err(remote_error(
                RemoteErrorCode::InvalidRequest,
                "upload target is not a regular file",
            ));
        }
    }
    if mode == RemoteWriteMode::Create && existing.is_some() {
        return Err(remote_error(
            RemoteErrorCode::Io,
            format!(
                "create mode requires an absent target: {}",
                display.display()
            ),
        ));
    }
    let permissions = existing.map(|metadata| metadata.permissions());
    // 暂存区在目标 parent 内，与最终目标同一文件系统，保证发布是原子的。
    let stage = TempDir::new_in(parent.get())
        .map_err(|error| io_error("failed to create upload staging area", error))?;
    let prepared = make_private(&stage).and_then(|()| create_staged(&stage, &parent));
    match prepared {
        Ok(file) => Ok((
            StagedUpload {
                stage: Some(stage),
                parent,
                leaf,
                mode,
                permissions,
                tasks,
            },
            file,
        )),
        Err(error) => {
            // 准备失败只清理本次暂存区；删除失败不覆盖原失败，但必须并入返回结果，
            // 让调用方看到「准备失败 + 暂存区残留」两个真实事实。
            match close_stage(&tasks, stage) {
                Some(cleanup) => Err(merge(error, cleanup)),
                None => Err(error),
            }
        }
    }
}

impl StagedUpload {
    /// 原子发布（只在阻塞池里调用）。
    ///
    /// 发布成功或失败都显式关闭暂存区。`TempDir::close` **消费**暂存区句柄：成功即无残留，
    /// 失败时目录可能仍然存在，而本类型已经不持有任何可用于重试的句柄。
    ///
    /// 因此清理失败有三个后果，全部真实表达、不互相掩盖：
    /// 1. 作为 helper 层面失败归档到连接 owner（[`BlockingTasks::report_failure`]），连接收尾
    ///    会看到这个异常，而不是留下一个「看起来健康」的连接；
    /// 2. 并入本方法的返回值，调用方据此发布该操作流的 typed error，不会发出成功终结；
    /// 3. 已发布的文件副作用不假回滚、不自动重放：`hard_link`/`rename` 已经生效时文件就在
    ///    目标上，残留的只是暂存目录本身，由归档失败触发的连接收尾/使用者清理负责。
    ///
    /// 本方法已经在阻塞上下文里执行：调用它的 job 一旦被连接 owner 受理，取消就不再撤销发布，
    /// 由 owner 等到真实终态（线性化点是「job 被受理」，不是 rename 系统调用开始）。
    pub(super) fn publish(mut self) -> Result<(), RemoteError> {
        let Some(stage) = self.stage.take() else {
            return Err(remote_error(
                RemoteErrorCode::Io,
                "upload staging area was already released",
            ));
        };
        let published = (|| -> Result<(), RemoteError> {
            if let Some(permissions) = self.permissions.clone() {
                stage
                    .set_permissions(STAGED_LEAF, permissions)
                    .map_err(|error| io_error("failed to preserve target permissions", error))?;
            }
            match self.mode {
                RemoteWriteMode::Create => stage
                    .hard_link(STAGED_LEAF, self.parent.get(), &self.leaf)
                    .map_err(|error| io_error("failed to publish uploaded file", error))?,
                RemoteWriteMode::Overwrite => stage
                    .rename(STAGED_LEAF, self.parent.get(), &self.leaf)
                    .map_err(|error| io_error("failed to replace uploaded file", error))?,
                RemoteWriteMode::Append => {
                    return Err(remote_error(
                        RemoteErrorCode::Io,
                        "append uploads never publish a staged file",
                    ));
                }
            }
            sync_directory(self.parent.get())
        })();
        match (published, close_stage(&self.tasks, stage)) {
            (published, None) => published,
            // 发布成功但暂存区没删掉：不能报成功，首因是清理异常。
            (Ok(()), Some(cleanup)) => Err(cleanup),
            // 已发布/发布失败的首因优先保留，清理异常追加在同一错误里。
            (Err(primary), Some(cleanup)) => Err(merge(primary, cleanup)),
        }
    }

    /// 显式删除尚未发布的暂存区（只在阻塞上下文调用）。
    ///
    /// 正常失败路径由调用方在返回前 `await` 这次收束：操作流一直持到删除真实结束，返回后不会
    /// 再留下任何暂存资源责任。`stage` 被取空，因此随后的 `Drop` 不会重复登记兜底清理。
    pub(super) fn discard(mut self) -> Result<(), RemoteError> {
        let Some(stage) = self.stage.take() else {
            return Ok(());
        };
        stage
            .close()
            .map_err(|error| io_error("failed to remove upload staging area", error))
    }
}

impl Drop for StagedUpload {
    fn drop(&mut self) {
        // 只有整条连接被 abort、或结果接收者已被取消时才走到这里，而且可能位于 tokio 工作
        // 线程：只登记兜底移交，不做 IO；删除由连接收尾在阻塞池里执行并 join（`retire`）。
        let Some(stage) = self.stage.take() else {
            return;
        };
        // 闭包保留同一份完整预算：被取消但尚未清理的暂存区继续计费，因此并行 drain 仍受预算
        // 约束，不需要把 drain 改成串行。
        let lease = self.parent.share();
        self.tasks.retire(Box::new(move || {
            let _lease = lease;
            stage
                .close()
                .map_err(|error| io_error("failed to remove upload staging area", error))
        }));
    }
}

/// 在阻塞上下文里显式删除暂存区；失败同时归档到连接 owner 并返回给调用方合并。
///
/// `TempDir::close(self)` 消费句柄，因此失败后本模块无法再重试删除：残留目录的责任在这里
/// 明确交给连接 owner（归档为 helper 层面失败）与调用方的错误回执，不假装仍然持有句柄。
fn close_stage(tasks: &BlockingTasks, stage: TempDir) -> Option<RemoteError> {
    let failure = match stage.close() {
        Ok(()) => return None,
        Err(error) => io_error("failed to remove upload staging area", error),
    };
    tasks.report_failure(failure.clone());
    Some(failure)
}

/// 保留首因的错误码与语义，把清理异常追加进同一条错误信息。
fn merge(primary: RemoteError, cleanup: RemoteError) -> RemoteError {
    RemoteError {
        code: primary.code,
        message: format!("{}; {}", primary.message, cleanup.message),
    }
}

fn create_staged(
    stage: &TempDir,
    parent: &LeasedFd<Dir>,
) -> Result<LeasedFd<std::fs::File>, RemoteError> {
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    options.follow(FollowSymlinks::No);
    options.custom_flags(libc::O_NONBLOCK);
    let file = stage
        .open_with(STAGED_LEAF, &options)
        .map_err(|error| io_error("failed to create staged upload", error))?;
    let metadata = file
        .metadata()
        .map_err(|error| io_error("failed to inspect staged upload", error))?;
    if !metadata.is_file() {
        return Err(remote_error(
            RemoteErrorCode::InvalidRequest,
            "staged upload is not a regular file",
        ));
    }
    // 新句柄与目标 parent 的同一份预算绑定：写句柄不存在脱离预算的窗口。
    Ok(LeasedFd::new(file.into_std(), parent.share()))
}

/// 暂存区权限先设为私有，避免同机其他用户在暂存窗口看到半写内容。
///
/// 只能用相对 `Dir` 能力的路径设置：`Dir::try_clone` 在 Linux 走 `reopen`，得到的是
/// **O_PATH** 句柄，对它 `fchmod`/`fsync` 都会 `EBADF`。`Dir::set_permissions` 会自己打开
/// 一个真实可读句柄再 `fchmod`，这里 `"."` 绑定的是暂存区自身，不重新解析 ambient 路径。
fn make_private(stage: &TempDir) -> Result<(), RemoteError> {
    stage
        .set_permissions(".", Permissions::from_mode(0o700))
        .map_err(|error| io_error("failed to restrict staging area", error))
}

/// 发布完成后同步目录项，避免 rename/link 结果只停留在缓存。
/// fsync 目标目录本体（在阻塞上下文调用）。
///
/// 不能把 `Dir::try_clone().into_std_file()` 当成 IO 句柄：Linux 上它是 O_PATH fd，`fsync`
/// 会 `EBADF`。`Dir::open_with(".")` 重新打开一个真实可读的目录句柄（`read(true)` + `O_DIRECTORY`，
/// `O_NOFOLLOW` 不变、路径绑定既有 `Dir` 能力），对它 `sync_all` 才是真正的目录 fsync。
fn sync_directory(dir: &Dir) -> Result<(), RemoteError> {
    let mut options = OpenOptions::new();
    options.read(true);
    options.follow(FollowSymlinks::No);
    options.custom_flags(libc::O_DIRECTORY);
    dir.open_with(".", &options)
        .map_err(|error| io_error("failed to reopen published directory", error))?
        .sync_all()
        .map_err(|error| io_error("failed to sync published directory", error))
}

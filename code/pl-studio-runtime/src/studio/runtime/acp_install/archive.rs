//! ZIP 内容校验、私有 staging 解压、版本化回执、复用校验与原子发布。
//!
//! 读取端使用 `rawzip` 的公开 lending central-directory 迭代器：固定大小解析缓冲、逐条读取原始
//! 记录，不先物化整张成员表、不按不可信声明预分配、也不做任何隐式去重。ZIP 格式细节（local
//! header、data descriptor、ZIP64、CRC 与实际大小）由库解析，本模块按官方 validation 规则追加
//! 产品政策：路径、重复/大小写、类型、加密/masked/reserved flags、压缩法、大小上限、不重叠的压缩
//! 区间、local/descriptor 一致性、权限归一化与入口资格。
//!
//! 全部是同步阻塞工作，只能由 owner 的 `spawn_blocking` 调用；取消在成员与缓冲块之间协作检查，
//! join 责任始终留在 owner。发布把"已提交"与"已确认持久化"分开报告（见 design/28 §28.6、§28.7）。
//!
//! 威胁边界是 [design/28 §28.7] 确认的标准桌面应用模型：防护不可信分发内容、预先存在的符号
//! 链接/reparse、路径越界与损坏安装，不承诺抵御能同时改写当前用户配置、安装管理树或进程权限的
//! 同权限恶意进程或管理员，也不是 OS 沙箱。实际链接、权限与完整性检查一项都不因此跳过。
//!
//! [design/28 §28.7]: ../../../../../../design/28-acp.md

mod extract;
mod verify;

pub(super) use extract::extract;
pub(super) use verify::verify_installed;

use std::fs::{File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Component, Path, PathBuf};

use crate::{AcpInstallFailure, AcpInstallFailureCode, AcpInstallRelease, AcpInstallStage};
use sha2::{Digest, Sha256};
use tokio_util::sync::CancellationToken;

use super::mapping::{failure, failure_with_message};
use super::paths;
use super::paths::ManagedRoot;

/// 成员数量上限。
pub(super) const MAX_MEMBERS: usize = 512;
/// 解压总量上限。
pub(super) const MAX_EXPANDED_BYTES: u64 = 4 * 1024 * 1024 * 1024;
/// 单成员上限。
pub(super) const MAX_MEMBER_BYTES: u64 = 2 * 1024 * 1024 * 1024;
/// 回执文件名；它是保留名，不能与包成员冲突。
pub(super) const RECEIPT_NAME: &str = "receipt.json";
/// 回执格式版本；同时记录目录集合（含 mode），供复用做完整内容比对。
const RECEIPT_FORMAT: u32 = 1;
/// 回执自身的大小上限：512 个成员与目录的清单远小于该值，超出即视为缓存损坏，不整块读入。
const MAX_RECEIPT_BYTES: u64 = 8 * 1024 * 1024;
/// 握手缓冲。
const COPY_CHUNK: usize = 64 * 1024;
/// 版本化安装回执：描述符、入口、本地 archive 摘要、完整成员与目录清单。
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct Receipt {
    pub(super) format: u32,
    pub(super) installation_id: String,
    pub(super) release: AcpInstallRelease,
    pub(super) command: String,
    pub(super) args: Vec<String>,
    pub(super) archive_sha256: String,
    pub(super) members: Vec<ReceiptMember>,
    /// 归档中的目录（相对路径 + 归一化 mode，含成员隐含的父目录）。
    pub(super) directories: Vec<ReceiptDirectory>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct ReceiptMember {
    pub(super) path: String,
    pub(super) size: u64,
    pub(super) sha256: String,
    /// 归一化后的 Unix 权限位；其它平台为 `None`。
    pub(super) mode: Option<u32>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct ReceiptDirectory {
    pub(super) path: String,
    pub(super) mode: Option<u32>,
}

/// 一次解压的输入：源包、私有 staging、冻结发行身份与入口。
#[derive(Debug, Clone, Copy)]
pub(super) struct ExtractInput<'a> {
    pub(super) archive: &'a Path,
    pub(super) staging: &'a Path,
    pub(super) installation_id: &'a str,
    pub(super) release: &'a AcpInstallRelease,
    pub(super) command: &'a str,
    pub(super) args: &'a [String],
    pub(super) archive_sha256: &'a str,
    pub(super) cancellation: &'a CancellationToken,
}

/// 复用时要求被验证安装与本次冻结身份完全一致。
#[derive(Debug, Clone, Copy)]
pub(super) struct ExpectedInstall<'a> {
    pub(super) installation_id: &'a str,
    pub(super) release: &'a AcpInstallRelease,
    pub(super) command: &'a str,
    pub(super) args: &'a [String],
}

/// 发布结果：`rename` 已生效，但目录项持久化可能尚未确认。
pub(super) enum PublishOutcome {
    Confirmed,
    /// 已提交（安装目录可见），但持久化屏障失败或平台保证未确认：不能报告为完整成功，也不能
    /// 谎称回滚。
    CommittedButUnconfirmed,
}

/// 流式摘要；`progress` 报告已处理的真实字节数与已知总量（文件长度）。
pub(super) fn sha256_file(
    path: &Path,
    cancellation: &CancellationToken,
    progress: &(dyn Fn(u64, Option<u64>) + Sync),
) -> Result<String, AcpInstallFailure> {
    let stage = AcpInstallStage::Verify;
    let mut file = File::open(path).map_err(|_| io(stage))?;
    let total = file.metadata().map(|metadata| metadata.len()).ok();
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; COPY_CHUNK];
    let mut processed = 0u64;
    loop {
        if cancellation.is_cancelled() {
            return Err(failure(AcpInstallFailureCode::Cancelled, stage, true));
        }
        let read = file.read(&mut buffer).map_err(|_| io(stage))?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
        processed = processed.saturating_add(read as u64);
        progress(processed, total);
    }
    Ok(hex::encode(hasher.finalize()))
}

/// 写入回执；Unix 上再同步 staging 根目录项（Windows 的落盘保证来自 move 的 write-through）。
pub(super) fn write_receipt(
    root: &ManagedRoot,
    staging: &Path,
    receipt: &Receipt,
) -> Result<(), AcpInstallFailure> {
    let stage = AcpInstallStage::Publish;
    let bytes = serde_json::to_vec(receipt).map_err(|_| io(stage))?;
    let path = staging.join(RECEIPT_NAME);
    root.validate_write(&path, stage)?;
    // 显式 0600：不依赖 umask（宿主机 umask=0002 时默认 0666 会变 0664）。只影响新建文件。
    let mut file = paths::create_new_file(&path, paths::PRIVATE_FILE_MODE, stage)?;
    #[cfg(unix)]
    super::permissions::verify(&path, false, stage)?;
    file.write_all(&bytes)
        .and_then(|()| file.sync_all())
        .map_err(|_| io(stage))?;
    #[cfg(unix)]
    {
        paths::sync_directory(staging, stage)
    }
    #[cfg(not(unix))]
    {
        Ok(())
    }
}

/// 读取已发布回执；缺失、链接、不可解析或格式不符都按缓存损坏处理，不静默替换。
pub(super) fn read_receipt(
    root: &ManagedRoot,
    installed: &Path,
) -> Result<Receipt, AcpInstallFailure> {
    let stage = AcpInstallStage::Verify;
    let corrupt = || failure(AcpInstallFailureCode::CacheCorrupt, stage, false);
    let path = installed.join(RECEIPT_NAME);
    root.validate_existing(&path, stage)
        .map_err(|_| corrupt())?;
    root.require_file(&path, stage).map_err(|_| corrupt())?;
    let length = std::fs::symlink_metadata(&path)
        .map_err(|_| corrupt())?
        .len();
    if length > MAX_RECEIPT_BYTES {
        return Err(corrupt());
    }
    let bytes = std::fs::read(&path).map_err(|_| corrupt())?;
    let receipt: Receipt = serde_json::from_slice(&bytes).map_err(|_| corrupt())?;
    if receipt.format != RECEIPT_FORMAT {
        return Err(corrupt());
    }
    Ok(receipt)
}

/// 复用前的持久化补齐。
///
/// 哈希只能证明"内容相同"，不能证明上一次写入真的落了盘，因此复用必须先对每个真实成员文件与
/// 回执各做一次真实 `sync_all`，再补平台适用的屏障：
/// - Unix：逐层同步嵌套目录、已发布目录自身与新建祖先目录项；
/// - Windows：不做也不声称 Unix 等价的目录 fsync，落盘保证来自文件 `sync_all` 与发布时的同卷
///   write-through 移动（design/28 §28.7）。
///
/// 任何一步失败都如实返回 `false`，由调用方按"已发布但未确认"处理，绝不报告就绪。
pub(super) fn confirm_durable(root: &ManagedRoot, installed: &Path, receipt: &Receipt) -> bool {
    let stage = AcpInstallStage::Verify;
    if root.validate_existing(installed, stage).is_err() {
        return false;
    }
    if !sync_member_files(installed, receipt) {
        return false;
    }
    #[cfg(unix)]
    {
        sync_tree(installed, &receipt.directories, stage).is_ok()
            && paths::sync_directory(installed, stage).is_ok()
            && installed.parent().is_some_and(|parent| {
                paths::sync_directory_chain(root.anchor(), parent, stage).is_ok()
            })
    }
    #[cfg(not(unix))]
    {
        true
    }
}

/// 对回执列出的每个成员文件与回执自身做一次真实 `sync_all`。
///
/// Windows 的 `FlushFileBuffers` 需要可写句柄，因此那里以读写方式打开；Unix 的 `fsync` 对只读
/// 句柄同样有效。这里不读内容，也不修改文件。
fn sync_member_files(installed: &Path, receipt: &Receipt) -> bool {
    let mut paths: Vec<PathBuf> = receipt
        .members
        .iter()
        .map(|member| installed.join(&member.path))
        .collect();
    paths.push(installed.join(RECEIPT_NAME));
    paths.iter().all(|path| sync_file(path).is_ok())
}

fn sync_file(path: &Path) -> std::io::Result<()> {
    let mut options = OpenOptions::new();
    options.read(true);
    #[cfg(windows)]
    options.write(true);
    options.open(path)?.sync_all()
}

/// 同文件系统原子发布：目标以任何形式存在都不覆盖（调用方必须先走复用校验）。
///
/// 移动本身复用 [`pl_tool::workspace::atomic_file::move_owned_path`] 的成熟实现：Unix 是 `rename`
/// 加两端父目录同步，Windows 是同卷 `MoveFileExW(MOVEFILE_WRITE_THROUGH, replace = false)`。
/// 它对"移动已生效但随后的同步失败"只能返回 `io::Error`，因此这里在 `Err` 分支核对
/// source/target 的实际事实：已提交就报告 [`PublishOutcome::CommittedButUnconfirmed`]，绝不谎称
/// 回滚、也不删除现场（design/28 §28.7）。
pub(super) fn publish(
    root: &ManagedRoot,
    staging: &Path,
    installed: &Path,
) -> Result<PublishOutcome, AcpInstallFailure> {
    let stage = AcpInstallStage::Publish;
    root.validate_existing(staging, stage)?;
    match std::fs::symlink_metadata(installed) {
        Ok(_) => return Err(failure(AcpInstallFailureCode::CacheCorrupt, stage, false)),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(_) => return Err(io(stage)),
    }
    if let Some(parent) = installed.parent() {
        root.validate_write(parent, stage)?;
        // 目标父目录链由调用方的受管 `ensure_dir` 建立；这里只复核它仍是真实目录。
        root.validate_existing(parent, stage)?;
    }
    if pl_tool::workspace::move_owned_path(staging, installed).is_err() {
        // 移动的失败可能发生在提交之后：只按现有事实表达结果。
        let installed_present = std::fs::symlink_metadata(installed).is_ok();
        let staging_present = std::fs::symlink_metadata(staging).is_ok();
        return match (installed_present, staging_present) {
            (true, false) => Ok(PublishOutcome::CommittedButUnconfirmed),
            // 未提交（staging 仍在）或两者并存（外部干预）：保留现场并如实失败。
            _ => Err(io(stage)),
        };
    }
    // Unix 追加：已发布目录自身的目录项与新建祖先目录项需要持久化屏障（`move_owned_path` 只同步
    // 移动两端父目录）。Windows 不做、也不声称执行目录同步。
    #[cfg(unix)]
    {
        let mut confirmed = paths::sync_directory(installed, stage).is_ok();
        if let Some(parent) = installed.parent() {
            confirmed &= paths::sync_directory_chain(root.anchor(), parent, stage).is_ok();
        }
        Ok(if confirmed {
            PublishOutcome::Confirmed
        } else {
            PublishOutcome::CommittedButUnconfirmed
        })
    }
    #[cfg(not(unix))]
    {
        Ok(PublishOutcome::Confirmed)
    }
}

/// 入口相对路径的规范形态：POSIX 分隔、无前导 `./`。
pub(super) fn normalize_relative(command: &str) -> String {
    let command = command.trim().replace('\\', "/");
    command.trim_start_matches("./").to_string()
}

/// Unix 专用：由深到浅同步嵌套目录项。
#[cfg(unix)]
fn sync_tree(
    base: &Path,
    directories: &[ReceiptDirectory],
    stage: AcpInstallStage,
) -> Result<(), AcpInstallFailure> {
    // 由深到浅：父目录项的持久化依赖子目录项已存在。
    let mut ordered: Vec<&ReceiptDirectory> = directories.iter().collect();
    ordered.sort_by_key(|directory| std::cmp::Reverse(directory.path.matches('/').count()));
    for directory in ordered {
        paths::sync_directory(&base.join(&directory.path), stage)?;
    }
    Ok(())
}

/// 成员路径安全校验：返回（相对路径, 是否为目录）。只允许一个尾部分隔符表示目录项。
fn sanitize_member(name: &str) -> Option<(PathBuf, bool)> {
    if name.is_empty() || name.contains('\\') || name.contains('\0') {
        return None;
    }
    let (body, is_directory) = match name.strip_suffix('/') {
        Some(body) => (body, true),
        None => (name, false),
    };
    if body.is_empty() || body.contains("//") {
        return None;
    }
    if body.starts_with('/') || body.as_bytes().get(1) == Some(&b':') {
        return None;
    }
    if body.len() > 1024 {
        return None;
    }
    let mut path = PathBuf::new();
    for segment in body.split('/') {
        if segment.is_empty() || segment == "." || segment == ".." {
            return None;
        }
        if segment.contains(':') || segment.ends_with('.') || segment.ends_with(' ') {
            return None;
        }
        if is_windows_reserved(segment) {
            return None;
        }
        if segment.chars().any(char::is_control) {
            return None;
        }
        path.push(segment);
    }
    match path.components().next() {
        Some(Component::Normal(_)) => Some((path, is_directory)),
        _ => None,
    }
}

fn is_windows_reserved(segment: &str) -> bool {
    let stem = segment
        .split('.')
        .next()
        .unwrap_or(segment)
        .trim_end()
        .to_uppercase();
    matches!(
        stem.as_str(),
        "CON"
            | "PRN"
            | "AUX"
            | "NUL"
            | "CONIN$"
            | "CONOUT$"
            | "COM1"
            | "COM2"
            | "COM3"
            | "COM4"
            | "COM5"
            | "COM6"
            | "COM7"
            | "COM8"
            | "COM9"
            | "COM¹"
            | "COM²"
            | "COM³"
            | "LPT1"
            | "LPT2"
            | "LPT3"
            | "LPT4"
            | "LPT5"
            | "LPT6"
            | "LPT7"
            | "LPT8"
            | "LPT9"
            | "LPT¹"
            | "LPT²"
            | "LPT³"
    )
}

/// 真实权限位（含禁用位），用于严格校验磁盘现状。
fn raw_mode(metadata: &std::fs::Metadata) -> Option<u32> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        Some(metadata.permissions().mode() & 0o7777)
    }
    #[cfg(not(unix))]
    {
        let _ = metadata;
        None
    }
}

/// 入口执行资格：Unix 要求包内入口本身带执行位；
/// 其它平台以"包内普通文件"为准。
fn has_exec_bit(mode: Option<u32>) -> bool {
    #[cfg(unix)]
    {
        mode.is_some_and(|mode| mode & 0o111 != 0)
    }
    #[cfg(not(unix))]
    {
        let _ = mode;
        true
    }
}

fn io(stage: AcpInstallStage) -> AcpInstallFailure {
    failure(AcpInstallFailureCode::Io, stage, true)
}

/// 发布未确认持久化时的固定安全摘要；不承诺"未提交"，也不谎称回滚。
pub(super) fn unconfirmed_publish_failure() -> AcpInstallFailure {
    failure_with_message(
        AcpInstallFailureCode::Io,
        AcpInstallStage::Publish,
        true,
        "官方 server 安装可能已发布但未确认持久化，请重试检查",
    )
}

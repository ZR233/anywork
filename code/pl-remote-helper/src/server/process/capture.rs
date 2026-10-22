//! 捕获文件的唯一写入者；预算、头部、块标签与终态计量位于同一生命周期。
//!
//! 文件由 workspace 目录能力在已持有的 parent 上创建（见 [`super::super::path`]），
//! 不把校验过的路径交回 ambient API。
//!
//! FD 责任：写入句柄是 [`LeasedFd<std::fs::File>`]，句柄与进程操作的预算属于同一个对象，
//! 每次写都整份移入连接 owner 的阻塞任务并交回。因此不存在 `tokio::fs::File` 那种隐藏在运行
//! 时内部、不携带预算也无法被 join 的 `spawn_blocking`，也不存在「闭包已返回、结果还停在
//! oneshot 里却不再计费」的空窗。终态只关闭句柄：所有写都已在阻塞任务里 await 完成，不需要
//! 额外 `fsync`，也不引入新的耐久承诺。

use std::io::Write;
use std::path::Path;

use pl_protocol::remote::{
    RemoteCapture, RemoteCaptureReceipt, RemoteError, RemoteErrorCode, RemoteOutputStream,
};

use super::super::fd::LeasedFd;
use super::super::path::{Target, io_error, remote_error};
use super::super::tasks::BlockingTasks;

pub(super) enum Capture {
    None,
    File {
        /// 句柄只在阻塞任务内部或「句柄已在闭包内关闭」时为 `None`。
        file: Option<LeasedFd<std::fs::File>>,
        receipt: RemoteCaptureReceipt,
        tasks: BlockingTasks,
    },
}

pub(super) enum Acceptance {
    Accepted,
    Refused,
}

impl Capture {
    pub(super) async fn prepare(
        policy: &RemoteCapture,
        target: Option<&Target>,
        command: &str,
        cwd: &Path,
        tasks: &BlockingTasks,
    ) -> Result<Self, RemoteError> {
        match (policy, target) {
            (RemoteCapture::None, None) => Ok(Self::None),
            (RemoteCapture::File { limit_bytes, .. }, Some(target)) => {
                let header = format!(
                    "=== COMMAND ===\n{command}\n\n=== CWD ===\n{}\n\n",
                    cwd.display()
                );
                if header.len() as u64 > *limit_bytes {
                    return Err(remote_error(
                        RemoteErrorCode::OutputLimitExceeded,
                        format!(
                            "capture header requires {} bytes, limit is {limit_bytes}; process was not started",
                            header.len()
                        ),
                    ));
                }
                let charged = header.len() as u64;
                // 句柄自带本次进程操作的预算：头部写入与之后的每段输出都在预算内完成。
                let file = target.create_regular().await?;
                let worker = tasks.clone();
                let file = worker
                    .run(move || {
                        let mut file = file;
                        file.get_mut()
                            .write_all(header.as_bytes())
                            .map_err(|error| io_error("write capture header", error))?;
                        Ok(file)
                    })
                    .await?;
                Ok(Self::File {
                    file: Some(file),
                    receipt: RemoteCaptureReceipt {
                        limit_bytes: *limit_bytes,
                        charged_bytes: charged,
                        refused_bytes: 0,
                    },
                    tasks: tasks.clone(),
                })
            }
            (RemoteCapture::None, Some(_)) | (RemoteCapture::File { .. }, None) => {
                Err(remote_error(
                    RemoteErrorCode::InvalidRequest,
                    "capture policy and resolved target disagree",
                ))
            }
        }
    }

    /// 追加一段标签化输出；超出预算后只累计拒绝字节，不再写盘。
    pub(super) async fn append(
        &mut self,
        stream: RemoteOutputStream,
        body: &[u8],
    ) -> Result<Acceptance, RemoteError> {
        let Self::File {
            file,
            receipt,
            tasks,
        } = self
        else {
            return Ok(Acceptance::Accepted);
        };
        let label = match stream {
            RemoteOutputStream::Stdout => b"=== STDOUT ===\n",
            RemoteOutputStream::Stderr => b"=== STDERR ===\n",
        };
        let newline = !body.ends_with(b"\n");
        let cost = label.len() as u64 + body.len() as u64 + u64::from(newline);
        if receipt.refused_bytes > 0 || cost > receipt.limit_bytes - receipt.charged_bytes {
            receipt.refused_bytes = receipt.refused_bytes.saturating_add(cost);
            return Ok(Acceptance::Refused);
        }
        // 标签、正文与补齐换行合成一次写入：一次阻塞提交对应一段真实输出，不拆成多次往返。
        let mut chunk = Vec::with_capacity(label.len() + body.len() + usize::from(newline));
        chunk.extend_from_slice(label);
        chunk.extend_from_slice(body);
        if newline {
            chunk.push(b'\n');
        }
        let Some(handle) = file.take() else {
            return Err(remote_error(
                RemoteErrorCode::Io,
                "capture file is no longer available",
            ));
        };
        let worker = tasks.clone();
        match worker
            .run(move || {
                let mut handle = handle;
                handle
                    .get_mut()
                    .write_all(&chunk)
                    .map_err(|error| io_error("capture process output", error))?;
                Ok(handle)
            })
            .await
        {
            Ok(handle) => {
                *file = Some(handle);
                receipt.charged_bytes += cost;
                Ok(Acceptance::Accepted)
            }
            // 写入失败后句柄已随闭包关闭：调用方停止继续 capture，原始失败保留。
            Err(error) => Err(error),
        }
    }

    /// 终态：关闭捕获句柄，让 FD 先于进程操作的预算归还。
    ///
    /// 正文都已在阻塞任务里 `await` 完成，因此这里不需要任何额外系统调用；`std::fs::File`
    /// 也没有用户态缓冲需要 flush。返回最终回执，供唯一的进程退出记录使用。
    pub(super) fn finish(&mut self) -> Option<RemoteCaptureReceipt> {
        let Self::File { file, receipt, .. } = self else {
            return None;
        };
        // 句柄在 `LeasedFd` 内先关闭、预算后归还。
        file.take();
        Some(*receipt)
    }
}

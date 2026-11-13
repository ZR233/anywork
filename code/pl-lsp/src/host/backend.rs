//! LSP 文件与进程宿主边界。
//!
//! LSP JSON-RPC、路由、诊断与 server driver 始终留在本地；宿主只提供读取
//! workspace 文件以及启动、观察、终止 language server 的原语。

use std::future::Future;
use std::path::{Path, PathBuf};
use std::pin::Pin;

use futures::future::BoxFuture;
use tokio::io::{AsyncRead, AsyncWrite};

/// 宿主文件元数据，只暴露 LSP 本地逻辑需要的事实。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LspHostFileStat {
    pub is_file: bool,
    pub byte_size: u64,
}

/// 启动 language server 所需的传输中立参数。
#[derive(Debug, Clone)]
pub struct LspHostSpawnRequest {
    pub process_id: String,
    pub program: String,
    pub args: Vec<String>,
    pub env: std::collections::BTreeMap<String, String>,
    pub cwd: PathBuf,
    /// The host must use this token and deadline through its existing supervised
    /// startup API, retaining ownership until cancellation is acknowledged.
    pub cancellation: tokio_util::sync::CancellationToken,
    pub deadline: tokio::time::Instant,
}

/// 宿主进程的最终退出状态。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LspHostProcessExit {
    pub exit_code: Option<i32>,
}

/// LSP 宿主原语失败。
#[derive(Debug, Clone, thiserror::Error)]
#[error("{message}")]
pub struct LspHostError {
    message: String,
    reclaimed_start_failure: bool,
}

impl LspHostError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            reclaimed_start_failure: false,
        }
    }

    /// A typed business-start failure observed only after the supervisor has
    /// actually exited, with no business process or cleanup failure remaining.
    /// This remains an error when observing startup, but is not a failed reclaim.
    /// Hosts must not use this constructor for transport or cleanup failures.
    pub fn reclaimed_start_failure(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
            reclaimed_start_failure: true,
        }
    }
}

pub(crate) type LspHostReader = Pin<Box<dyn AsyncRead + Send>>;
pub(crate) type LspHostWriter = Pin<Box<dyn AsyncWrite + Send>>;
type LspHostWait =
    Pin<Box<dyn Future<Output = Result<LspHostProcessExit, LspHostError>> + Send + 'static>>;
type LspHostTerminate = Box<dyn FnOnce() -> BoxFuture<'static, ()> + Send>;

enum ProcessWait {
    Pending(LspHostWait),
    Finished(Result<LspHostProcessExit, LspHostError>),
}

enum ProcessTermination {
    Unrequested(LspHostTerminate),
    Requested(BoxFuture<'static, ()>),
    Sent,
}

/// 一个由宿主维护、由本地 LSP client 消费 stdio 的可观察进程。
pub struct LspHostProcess {
    stdin: Option<LspHostWriter>,
    stdout: Option<LspHostReader>,
    stderr: Option<LspHostReader>,
    wait: ProcessWait,
    terminate: ProcessTermination,
}

impl std::fmt::Debug for LspHostProcess {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("LspHostProcess")
            .field("stdin", &self.stdin.is_some())
            .field("stdout", &self.stdout.is_some())
            .field("stderr", &self.stderr.is_some())
            .finish_non_exhaustive()
    }
}

impl LspHostProcess {
    /// 从宿主提供的 stdio、退出 future 和终止回调构造进程句柄。
    pub fn new(
        stdin: Option<LspHostWriter>,
        stdout: Option<LspHostReader>,
        stderr: Option<LspHostReader>,
        wait: impl Future<Output = Result<LspHostProcessExit, LspHostError>> + Send + 'static,
        terminate: impl FnOnce() -> BoxFuture<'static, ()> + Send + 'static,
    ) -> Self {
        Self {
            stdin,
            stdout,
            stderr,
            wait: ProcessWait::Pending(Box::pin(wait)),
            terminate: ProcessTermination::Unrequested(Box::new(terminate)),
        }
    }

    pub(crate) fn take_stdin(&mut self) -> Option<LspHostWriter> {
        self.stdin.take()
    }

    pub(crate) fn take_stdout(&mut self) -> Option<LspHostReader> {
        self.stdout.take()
    }

    pub(crate) fn take_stderr(&mut self) -> Option<LspHostReader> {
        self.stderr.take()
    }

    pub(crate) async fn wait(&mut self) -> Result<LspHostProcessExit, LspHostError> {
        let result = match &mut self.wait {
            ProcessWait::Pending(wait) => wait.await,
            ProcessWait::Finished(result) => return result.clone(),
        };
        self.wait = ProcessWait::Finished(result.clone());
        result
    }

    pub(crate) async fn terminate(&mut self) -> Result<(), LspHostError> {
        if self.startup_failure().is_some() {
            return Ok(());
        }
        if matches!(self.terminate, ProcessTermination::Unrequested(_)) {
            let previous = std::mem::replace(&mut self.terminate, ProcessTermination::Sent);
            self.terminate = match previous {
                ProcessTermination::Unrequested(terminate) => {
                    ProcessTermination::Requested(terminate())
                }
                ProcessTermination::Requested(pending) => ProcessTermination::Requested(pending),
                ProcessTermination::Sent => ProcessTermination::Sent,
            };
        }
        if let ProcessTermination::Requested(pending) = &mut self.terminate {
            pending.await;
            self.terminate = ProcessTermination::Sent;
        }
        match self.wait().await {
            Ok(_) => Ok(()),
            Err(error) if error.reclaimed_start_failure => Ok(()),
            Err(error) => Err(error),
        }
    }

    pub(crate) fn startup_failure(&self) -> Option<&str> {
        match &self.wait {
            ProcessWait::Finished(Err(error)) if error.reclaimed_start_failure => {
                Some(&error.message)
            }
            _ => None,
        }
    }
}

/// LSP 对 workspace 文件和 language server 进程的最小宿主依赖。
///
/// 实现不得承担 JSON-RPC、server schema、诊断、工具输出或持久化逻辑。
pub trait LspHostBackend: std::fmt::Debug + Send + Sync {
    /// Path semantics of the machine owning these files and the language server.
    fn path_style(&self) -> LspPathStyle;
    /// 标识逻辑执行会话与目录；传输重挂和临时句柄不改变身份，实际会话替换才改变。
    fn identity(&self) -> String;

    /// 读取一个 workspace 内文件的原始字节。
    fn read_file<'a>(
        &'a self,
        path: &'a Path,
        max_bytes: u64,
    ) -> BoxFuture<'a, Result<Vec<u8>, LspHostError>>;

    /// 查询一个 workspace 内路径，不存在返回 `None`。
    fn stat<'a>(
        &'a self,
        path: &'a Path,
    ) -> BoxFuture<'a, Result<Option<LspHostFileStat>, LspHostError>>;

    /// 列出 workspace 内目录第一层的文件名；超出上限返回可观察错误，
    /// 宿主不得先无界收集目录再截断。
    fn list_directory<'a>(
        &'a self,
        path: &'a Path,
        max_entries: usize,
    ) -> BoxFuture<'a, Result<Vec<String>, LspHostError>>;

    /// 启动一个 stdio language server；进程树生命周期由宿主维护。
    fn spawn<'a>(
        &'a self,
        request: LspHostSpawnRequest,
    ) -> BoxFuture<'a, Result<LspHostProcess, LspHostError>>;
}

/// File paths belong to the server host, independently of the client operating system.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LspPathStyle {
    Native,
    Posix,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    async fn terminal_start_failure_is_still_observable_but_is_already_reclaimed() {
        let mut process = LspHostProcess::new(
            None,
            None,
            None,
            async {
                Err(LspHostError::reclaimed_start_failure(
                    "business process launch failed (OS error Some(2))",
                ))
            },
            || {
                Box::pin(async {
                    panic!("an already-reclaimed process must not be terminated again");
                })
            },
        );
        assert!(
            process
                .wait()
                .await
                .unwrap_err()
                .to_string()
                .contains("OS error Some(2)")
        );
        process.terminate().await.unwrap();
        process.terminate().await.unwrap();
        assert!(
            process.wait().await.is_err(),
            "startup failure must not become a successful execution result"
        );
    }

    #[tokio::test]
    async fn unconfirmed_failure_is_not_reclassified_by_its_message() {
        let mut process = LspHostProcess::new(
            None,
            None,
            None,
            async {
                Err(LspHostError::new(
                    "business process launch failed (OS error Some(2))",
                ))
            },
            || Box::pin(async {}),
        );
        assert!(process.terminate().await.is_err());
        assert!(process.terminate().await.is_err());
    }
}

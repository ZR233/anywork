use std::future::Future;
use std::path::{Path, PathBuf};
use std::pin::Pin;

use serde_json::Value;
use tokio::io::{AsyncRead, AsyncWrite};

use crate::workspace::SessionFiles;

pub use pl_remote_helper::start_control::{CommandStartControl, CommandStartError};

/// 命令执行后端收到的启动请求。
#[derive(Clone)]
pub struct CommandSpawnRequest {
    pub start_control: CommandStartControl,
    pub process_id: String,
    pub command: String,
    /// Request a writable stdin pipe; otherwise spawn with the null device.
    pub interactive: bool,
    pub cwd: String,
    pub output_target: CommandOutputTarget,
    pub capture_limit_bytes: u64,
}

impl std::fmt::Debug for CommandSpawnRequest {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("CommandSpawnRequest")
            .field("process_id", &self.process_id)
            .field("interactive", &self.interactive)
            .field("cwd", &self.cwd)
            .field("capture_limit_bytes", &self.capture_limit_bytes)
            .finish_non_exhaustive()
    }
}

pub type CommandReader = Pin<Box<dyn AsyncRead + Send>>;
pub type CommandWriter = Pin<Box<dyn AsyncWrite + Send>>;

pub use pl_tool_command::process::StdinCloseState;

type CommandWaitFuture =
    Pin<Box<dyn Future<Output = std::result::Result<CommandExit, String>> + Send>>;

/// Request-only cancellation capability, independent of diagnostic process identifiers.
#[derive(Debug, Clone)]
pub struct CommandCancellation(tokio_util::sync::CancellationToken);

impl CommandCancellation {
    /// Requests cancellation. Physical completion must still be obtained from wait.
    pub fn cancel(&self) {
        self.0.cancel();
    }

    /// Whether the owner has already requested cancellation.
    pub fn is_cancelled(&self) -> bool {
        self.0.is_cancelled()
    }

    /// Suspends until cancellation is requested; cancelling this wait does not clear it.
    pub async fn cancelled(&self) {
        self.0.cancelled().await;
    }
}

/// Ownership transfer of business IO from a backend to the command runtime.
pub struct CommandIo {
    pub stdin: Option<CommandWriter>,
    pub stdout: Option<CommandReader>,
    pub stderr: Option<CommandReader>,
}

impl std::fmt::Debug for CommandIo {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("CommandIo")
            .field("stdin", &self.stdin.is_some())
            .field("stdout", &self.stdout.is_some())
            .field("stderr", &self.stderr.is_some())
            .finish()
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandExit {
    pub signal: Option<i32>,
    pub exit_code: Option<i32>,
}

pub use pl_tool_command::process::{
    CommandCaptureIoError, CommandCaptureResult, CommandCaptureState, CommandCapturedStream,
};

type CommandCaptureFuture = Pin<
    Box<
        dyn Future<Output = std::result::Result<Option<pl_remote_helper::CaptureResult>, String>>
            + Send,
    >,
>;

pub struct ManagedCommand {
    host_pid: Option<u32>,
    stdin: Option<CommandWriter>,
    stdout: Option<CommandReader>,
    stderr: Option<CommandReader>,
    wait: Option<CommandWaitFuture>,
    cancellation: CommandCancellation,
    capture_completion: Option<CommandCaptureFuture>,
}

impl std::fmt::Debug for ManagedCommand {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ManagedCommand")
            .field("host_pid", &self.host_pid)
            .field("stdin", &self.stdin.is_some())
            .field("stdout", &self.stdout.is_some())
            .field("stderr", &self.stderr.is_some())
            .finish_non_exhaustive()
    }
}

impl ManagedCommand {
    /// Transfers the process and its IO into one command lease. The supplied future owns
    /// physical cleanup and must observe cancellation while retaining its process handle.
    pub fn new<F>(
        host_pid: Option<u32>,
        io: CommandIo,
        wait: impl FnOnce(CommandCancellation) -> F,
    ) -> Self
    where
        F: Future<Output = std::result::Result<CommandExit, String>> + Send + 'static,
    {
        let cancellation = CommandCancellation(tokio_util::sync::CancellationToken::new());
        let wait = wait(cancellation.clone());
        Self {
            host_pid,
            stdin: io.stdin,
            stdout: io.stdout,
            stderr: io.stderr,
            wait: Some(Box::pin(wait)),
            cancellation,
            capture_completion: None,
        }
    }

    pub(crate) fn with_capture_completion(
        mut self,
        completion: impl Future<
            Output = std::result::Result<Option<pl_remote_helper::CaptureResult>, String>,
        > + Send
        + 'static,
    ) -> Self {
        self.capture_completion = Some(Box::pin(completion));
        self
    }
    pub(super) fn has_capture_completion(&self) -> bool {
        self.capture_completion.is_some()
    }
    pub(super) async fn finish_capture(
        &mut self,
    ) -> std::result::Result<Option<pl_remote_helper::CaptureResult>, String> {
        let result = match self.capture_completion.as_mut() {
            Some(completion) => completion.await,
            None => return Ok(None),
        };
        self.capture_completion = None;
        result
    }

    /// Returns request-only cancellation, never ownership or proof of physical exit.
    pub fn cancellation(&self) -> CommandCancellation {
        self.cancellation.clone()
    }

    pub fn host_pid(&self) -> Option<u32> {
        self.host_pid
    }

    pub fn take_stdin(&mut self) -> Option<CommandWriter> {
        self.stdin.take()
    }

    pub fn take_stdout(&mut self) -> Option<CommandReader> {
        self.stdout.take()
    }

    pub fn take_stderr(&mut self) -> Option<CommandReader> {
        self.stderr.take()
    }

    pub async fn wait(&mut self) -> std::result::Result<CommandExit, String> {
        let wait = self
            .wait
            .as_mut()
            .ok_or_else(|| "managed command was already awaited".to_string())?;
        let result = wait.await;
        self.wait = None;
        result
    }
}

impl Drop for ManagedCommand {
    fn drop(&mut self) {
        self.cancellation.cancel();
    }
}

pub use pl_tool_command::process::CommandCaptureStream;

/// 命令完整输出在宿主和模型 workspace 中的对应位置。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandOutputTarget {
    capture_file: PathBuf,
    model_file: PathBuf,
    stderr_capture_file: PathBuf,
    stderr_model_file: PathBuf,
}

impl CommandOutputTarget {
    /// All four paths are supplied in the selected target's spelling. Deriving a
    /// remote filename with the desktop's Path::with_file_name would insert native separators.
    pub fn new(
        capture_file: impl Into<PathBuf>,
        model_file: impl Into<PathBuf>,
        stderr_capture_file: impl Into<PathBuf>,
        stderr_model_file: impl Into<PathBuf>,
    ) -> Self {
        Self {
            capture_file: capture_file.into(),
            model_file: model_file.into(),
            stderr_capture_file: stderr_capture_file.into(),
            stderr_model_file: stderr_model_file.into(),
        }
    }
    pub fn capture_file(&self) -> &Path {
        &self.capture_file
    }
    pub fn model_file(&self) -> &Path {
        &self.model_file
    }
    pub fn stream_capture_file(&self, stream: CommandCaptureStream) -> &Path {
        match stream {
            CommandCaptureStream::Stdout => &self.capture_file,
            CommandCaptureStream::Stderr => &self.stderr_capture_file,
        }
    }
    pub fn stream_model_file(&self, stream: CommandCaptureStream) -> &Path {
        match stream {
            CommandCaptureStream::Stdout => &self.model_file,
            CommandCaptureStream::Stderr => &self.stderr_model_file,
        }
    }
}

/// 计算模型可读取的统一命令完整输出路径。
///
/// `session_id` 必须是原始 Thread 身份。`tool_id` 是该次调用的物理 call key
///（通常为 `task-{sha256}`）。路径由 [`SessionFiles`] 单点派生，不再写入 `target/pure/`。
pub fn command_output_model_path(session_id: &str, tool_id: &str) -> PathBuf {
    SessionFiles::new(session_id).command_output(tool_id)
}

/// stdout/stderr 的累计原始字节数。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CommandOutputSizes {
    pub stdout_bytes: u64,
    pub stderr_bytes: u64,
}

/// 为统一的 `exec_command` / `write_stdin` 工具提供环境相关能力。
///
/// PL 负责进程表、超时、stdin、输出截断和生命周期；实现只负责将命令映射到
/// 本地、容器或远程 workspace，并在结束时发布完整输出与 artifact 元数据。
pub trait CommandBackend: std::fmt::Debug + Send + Sync + 'static {
    type Error: std::fmt::Display + Send + 'static;

    fn resolve_cwd(
        &self,
        cwd: Option<&Path>,
        allow_workspace_escape: bool,
    ) -> impl std::future::Future<Output = std::result::Result<String, Self::Error>> + Send;

    fn output_target(
        &self,
        session_id: &str,
        tool_id: &str,
        call_id: &str,
        command: &str,
    ) -> impl std::future::Future<Output = std::result::Result<CommandOutputTarget, Self::Error>> + Send;

    fn spawn(
        &self,
        request: CommandSpawnRequest,
    ) -> impl std::future::Future<Output = std::result::Result<ManagedCommand, Self::Error>> + Send;

    /// Prepares only product-owned output directories. Executor opens the capture files at spawn.
    fn prepare_output(
        &self,
        target: &CommandOutputTarget,
        command: &str,
        working_directory: &str,
        capture_limit_bytes: u64,
    ) -> impl std::future::Future<Output = std::result::Result<(), Self::Error>> + Send;

    fn publish_output(
        &self,
        target: &CommandOutputTarget,
    ) -> impl std::future::Future<Output = std::result::Result<(), Self::Error>> + Send;

    fn collect_output_artifacts(
        &self,
        target: &CommandOutputTarget,
        sizes: CommandOutputSizes,
    ) -> impl std::future::Future<Output = std::result::Result<Vec<Value>, Self::Error>> + Send;

    /// 单条命令落盘捕获的硬上限（字节）；`None` 表示沿用 PL 默认
    /// [`MAX_CAPTURE_BYTES`](crate::command::MAX_CAPTURE_BYTES)。
    ///
    /// 生产者按自己的落盘策略声明这个上限：显式设置表示"这就是本后端可接受的单命令落盘总量"；
    /// 默认不设置，普通消费者因此保持 PL 既有语义。
    fn capture_limit_bytes(&self) -> Option<u64> {
        None
    }

    /// 本后端允许进入模型上下文的输出上限（**字节**）；`None` 表示沿用既有语义。
    ///
    /// 单位是字节而不是 Unicode 字符：多字节字符按它在 `String` 里的实际长度计入，因此
    /// 同样的上限不会因为正文语言不同而变成三倍上下文。上限覆盖**两个流的模型可见正文之和**，
    /// 工具结果自身的元数据（状态、进程/路径、artifact 说明）不计入。
    ///
    /// 默认不设置：普通消费者的截断行为与从前完全一致，只有显式声明字节上限的后端
    /// （例如把一份输出同时落进容器与宿主的宿主）才会额外收紧。
    fn model_output_bytes_cap(&self) -> Option<u64> {
        None
    }
}

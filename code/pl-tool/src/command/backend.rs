use std::future::Future;
use std::path::{Path, PathBuf};
use std::pin::Pin;
#[cfg(not(target_os = "linux"))]
use std::process::Stdio;

use pl_protocol::{PureError, Result};
use serde_json::Value;
use tokio::io::{AsyncRead, AsyncWrite, AsyncWriteExt};

#[cfg(not(target_os = "linux"))]
use super::termination::terminate_process_tree;
#[cfg(target_os = "linux")]
use super::worker::LocalWorkerExecutable;
use crate::workspace::{SessionFiles, ToolPathPolicy};
#[cfg(not(target_os = "linux"))]
use pl_remote_helper::process::wrap_background_command;

#[cfg(not(target_os = "linux"))]
use super::shell::command_for_environment;
use crate::environment::ExecutionEnvironment;
#[cfg(target_os = "linux")]
use pl_remote_helper::client::ProcessCommand;

pub use pl_remote_helper::start_control::{CommandStartControl, CommandStartError};

/// 命令执行后端收到的启动请求。
#[derive(Debug, Clone)]
pub struct CommandSpawnRequest {
    pub start_control: CommandStartControl,
    pub process_id: String,
    pub command: String,
    pub cwd: String,
    pub output_target: CommandOutputTarget,
    pub capture_limit_bytes: u64,
}

pub type CommandReader = Pin<Box<dyn AsyncRead + Send>>;
pub type CommandWriter = Pin<Box<dyn AsyncWrite + Send>>;

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum StdinCloseState {
    Open,
    Closing,
    Closed,
}

/// Cumulative helper acknowledgements, independent of local DuplexStream flush.
#[derive(Debug, Clone)]
pub struct CommandInputProgress {
    pub confirmed_bytes: u64,
    pub close_state: StdinCloseState,
    pub failure: Option<String>,
}
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
    pub supervision_failure: Option<String>,
    pub signal: Option<i32>,
    pub capture_failure: Option<super::process_manager::CommandCaptureFailure>,
    pub exit_code: Option<i32>,
    pub capture: Option<CommandCaptureReceipt>,
}

/// 实际捕获写入者交回的终态磁盘计量，拒绝量只包含实际观察到但未接纳的块。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct CommandCaptureReceipt {
    pub captured_bytes: u64,
    pub limit_bytes: u64,
    /// 主捕获文件的确认偏移，与包含所有副本的计费成本分开。
    pub confirmed: CommandCaptureOffsets,
    pub charged_bytes: u64,
    pub refused_bytes: u64,
}

/// Each raw stream advances only after its writer confirms the append.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CommandCaptureOffsets {
    pub stdout: u64,
    pub stderr: u64,
}

impl CommandCaptureOffsets {
    pub fn total(self) -> u64 {
        self.stdout.saturating_add(self.stderr)
    }
    pub fn get(self, stream: CommandCaptureStream) -> u64 {
        match stream {
            CommandCaptureStream::Stdout => self.stdout,
            CommandCaptureStream::Stderr => self.stderr,
        }
    }
    pub fn set(&mut self, stream: CommandCaptureStream, value: u64) {
        match stream {
            CommandCaptureStream::Stdout => self.stdout = value,
            CommandCaptureStream::Stderr => self.stderr = value,
        }
    }
}

/// 唯一负责在真实写盘前执行预算的边界。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CommandCaptureOwnership {
    Manager,
    Producer,
}

pub struct ManagedCommand {
    host_pid: Option<u32>,
    stdin: Option<CommandWriter>,
    stdout: Option<CommandReader>,
    stderr: Option<CommandReader>,
    wait: Option<CommandWaitFuture>,
    cancellation: CommandCancellation,
    input_progress: Option<tokio::sync::watch::Receiver<CommandInputProgress>>,
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
            input_progress: None,
        }
    }

    pub fn with_input_progress(
        mut self,
        progress: tokio::sync::watch::Receiver<CommandInputProgress>,
    ) -> Self {
        self.input_progress = Some(progress);
        self
    }
    pub fn take_input_progress(
        &mut self,
    ) -> Option<tokio::sync::watch::Receiver<CommandInputProgress>> {
        self.input_progress.take()
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CommandCaptureStream {
    Stdout,
    Stderr,
}

/// 命令完整输出在宿主和模型 workspace 中的对应位置。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CommandOutputTarget {
    capture_file: PathBuf,
    model_file: PathBuf,
    stderr_capture_file: PathBuf,
    stderr_model_file: PathBuf,
}

impl CommandOutputTarget {
    pub fn new(capture_file: impl Into<PathBuf>, model_file: impl Into<PathBuf>) -> Self {
        let capture_file = capture_file.into();
        let model_file = model_file.into();
        Self {
            stderr_capture_file: capture_file.with_file_name("stderr.log"),
            stderr_model_file: model_file.with_file_name("stderr.log"),
            capture_file,
            model_file,
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

/// 为统一的 `exec` / `write_stdin` 工具提供环境相关能力。
///
/// PL 负责进程表、超时、stdin、输出截断和生命周期；实现只负责将命令映射到
/// 本地、容器或远程 workspace，并在结束时发布完整输出与 artifact 元数据。
pub trait CommandBackend: std::fmt::Debug + Send + Sync + 'static {
    type Error: std::fmt::Display + Send + 'static;

    /// Current host allocation; None asks the manager to sample platform resources.
    fn process_capacity(&self) -> Option<usize> {
        None
    }

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

    /// 在写入任何头部前检查传入预算，并返回实际起始长度。
    ///
    /// Manager 写入者必须拒绝超预算头部，且不能创建文件或启动命令。Producer 只声明目标，
    /// 在物理 owner 准备文件时执行相同检查；客户端等待其真实终态回执，不代算磁盘用量。
    ///
    /// The returned length is the backend-confirmed committed offset every later repair truncates back
    /// to, so a repair never depends on a length read that could fail and be mistaken for "nothing
    /// written".
    fn prepare_output(
        &self,
        target: &CommandOutputTarget,
        command: &str,
        working_directory: &str,
        capture_limit_bytes: u64,
    ) -> impl std::future::Future<Output = std::result::Result<u64, Self::Error>> + Send;

    /// Appends one accepted chunk and returns the fragment's new confirmed length.
    ///
    /// The returned length is the committed offset the next chunk (or a repair) builds on, so the
    /// capture plan tracks exactly what the backend confirmed writing.
    fn append_output_chunk(
        &self,
        target: &CommandOutputTarget,
        stream: CommandCaptureStream,
        chunk: &[u8],
    ) -> impl std::future::Future<Output = std::result::Result<u64, Self::Error>> + Send;

    /// Re-materializes one accepted chunk a failed capture append could not write.
    ///
    /// The append may have left the capture fragment short of the bytes already accepted and
    /// published live. This truncates the fragment back to its last committed offset and re-appends
    /// `chunk` to the selected raw stream file, so the fragment holds
    /// exactly the accepted bytes under its stable identity. Truncating first makes it idempotent: a
    /// repeated repair reproduces the same bytes instead of duplicating the chunk, and the command is
    /// never re-run. It returns the fragment's new confirmed length, so a caller replaying the whole
    /// plan passes that length as the next chunk's `committed_len` and the truncation is a no-op.
    fn repair_output_chunk(
        &self,
        capture_file: &Path,
        stream: CommandCaptureStream,
        committed_len: u64,
        chunk: &[u8],
    ) -> impl std::future::Future<Output = std::result::Result<u64, Self::Error>> + Send;

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

    /// 谁实际持有捕获文件并在每次写入前执行预算。Producer 必须在退出时返回计量回执。
    fn capture_ownership(&self) -> CommandCaptureOwnership;

    /// Manager 捕获的实际落盘成本；Producer 模式计量的是传输字节以限制客户端缓冲。
    ///
    /// 必须包含所有副本、标签与补换行，不提供默认估计；内容可用于精确判断是否补换行。
    /// Manager 在共享接纳锁内调用，必须为廉价、无阻塞、无 I/O 的纯计算；Producer 不调用。
    fn capture_storage_cost(
        &self,
        target: &CommandOutputTarget,
        stream: CommandCaptureStream,
        chunk: &[u8],
    ) -> u64;

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

/// anywork 使用的本地 workspace 命令后端。
#[derive(Debug, Clone)]
pub struct LocalCommandBackend {
    workspace_root: PathBuf,
    execution_environment: ExecutionEnvironment,
    child_environment: std::collections::BTreeMap<String, String>,
    #[cfg(target_os = "linux")]
    worker: std::sync::Arc<dyn LocalWorkerExecutable>,
    #[cfg(target_os = "linux")]
    worker_failure: std::sync::Arc<
        std::sync::OnceLock<std::sync::Arc<pl_remote_helper::client::WorkerClientError>>,
    >,
}

impl LocalCommandBackend {
    pub fn new(workspace_root: impl Into<PathBuf>) -> Self {
        Self {
            workspace_root: workspace_root.into(),
            execution_environment: ExecutionEnvironment::detect_local(),
            child_environment: Default::default(),
            #[cfg(target_os = "linux")]
            worker: std::sync::Arc::new(PathBuf::from("pl-remote-helper")),
            #[cfg(target_os = "linux")]
            worker_failure: Default::default(),
        }
    }

    /// Configures and retains the host's worker executable resource. The default Linux
    /// backend requires pl-remote-helper on PATH and never falls back to an unmanaged shell.
    /// An owned temporary-path resource remains alive with every backend clone.
    #[cfg(target_os = "linux")]
    pub fn with_worker_executable<P>(mut self, executable: P) -> Self
    where
        P: AsRef<Path> + std::fmt::Debug + Send + Sync + 'static,
    {
        self.worker = std::sync::Arc::new(executable);
        self.worker_failure = Default::default();
        self
    }

    /// Adds host-owned environment variables to supervised command children only.
    /// Does not mutate the process or global environment.
    pub fn with_child_environment(
        mut self,
        environment: std::collections::BTreeMap<String, String>,
    ) -> Self {
        self.child_environment = environment;
        self
    }

    pub fn execution_environment(&self) -> &ExecutionEnvironment {
        &self.execution_environment
    }

    pub fn with_execution_environment(mut self, environment: ExecutionEnvironment) -> Self {
        self.execution_environment = environment;
        self
    }

    /// Spawns an exact program and argv through the same supervised worker as [`Self::spawn`].
    ///
    /// Arguments, working directory and the inherited environment are preserved verbatim:
    /// no shell is inserted and no argument is reinterpreted. Used by local hosts that need
    /// the worker's per-child tree supervision without a shell command string (for example LSP).
    ///
    /// # Errors
    /// Returns the stored worker bootstrap failure or a fresh supervisor error.
    #[cfg(target_os = "linux")]
    pub async fn spawn_argv(
        &self,
        program: &std::ffi::OsStr,
        args: &[String],
        cwd: &Path,
    ) -> Result<ManagedCommand> {
        let specification = ProcessCommand::new(program.to_os_string())
            .args(args.iter().cloned())
            .current_dir(cwd);
        self.spawn_supervised(specification, None).await
    }

    /// Starts one business process under a per-child supervisor that retains the whole tree.
    #[cfg(target_os = "linux")]
    async fn spawn_supervised(
        &self,
        specification: ProcessCommand,
        start: Option<&CommandStartControl>,
    ) -> Result<ManagedCommand> {
        use pl_remote_helper::client::{ManagedWorker, ProcessTermination};
        if let Some(error) = self.worker_failure.get() {
            return Err(command_error("exec", error));
        }
        let worker = match start {
            Some(start) => {
                ManagedWorker::spawn_controlled(self.worker.worker_path(), specification, start)
                    .await
            }
            None => ManagedWorker::spawn(self.worker.worker_path(), specification).await,
        };
        let mut worker = worker
            .map_err(|error| {
                let error = std::sync::Arc::new(error);
                if matches!(
                    error.as_ref(),
                    pl_remote_helper::client::WorkerClientError::Bootstrap { source, .. } if !matches!(source.as_ref(), pl_remote_helper::client::WorkerClientError::StartCancelled | pl_remote_helper::client::WorkerClientError::StartExpired)
                ) {
                    let _ = self.worker_failure.set(error.clone());
                }
                command_error("exec", error)
            })?;
        let io = CommandIo {
            stdin: worker
                .take_stdin()
                .map(|value| Box::pin(value) as CommandWriter),
            stdout: worker
                .take_stdout()
                .map(|value| Box::pin(value) as CommandReader),
            stderr: worker
                .take_stderr()
                .map(|value| Box::pin(value) as CommandReader),
        };
        let control = worker.control();
        Ok(ManagedCommand::new(
            worker.supervisor_pid(),
            io,
            move |cancellation| async move {
                let result = tokio::select! {
                    result = worker.wait() => result,
                    _ = cancellation.cancelled() => {
                        if control.cancel().await.is_err() { control.close(); }
                        worker.wait().await
                    }
                };
                result
                    .map(|termination| CommandExit {
                        supervision_failure: None,
                        signal: match termination {
                            ProcessTermination::Signal(signal) => Some(signal),
                            _ => None,
                        },
                        capture_failure: None,
                        capture: None,
                        exit_code: match termination {
                            ProcessTermination::ExitCode(code) => Some(code),
                            ProcessTermination::Signal(_) => None,
                        },
                    })
                    .map_err(|error| error.to_string())
            },
        ))
    }
}

impl CommandBackend for LocalCommandBackend {
    type Error = PureError;

    fn capture_ownership(&self) -> CommandCaptureOwnership {
        CommandCaptureOwnership::Manager
    }

    fn capture_storage_cost(
        &self,
        target: &CommandOutputTarget,
        stream: CommandCaptureStream,
        chunk: &[u8],
    ) -> u64 {
        let _ = (target, stream);
        chunk.len() as u64
    }

    async fn resolve_cwd(
        &self,
        cwd: Option<&Path>,
        allow_workspace_escape: bool,
    ) -> Result<String> {
        let policy =
            ToolPathPolicy::new(self.workspace_root.clone(), allow_workspace_escape, "exec")?;
        match cwd {
            Some(dir) => policy.resolve_existing_directory(dir, &dir.display().to_string()),
            None => Ok(policy.root().to_path_buf()),
        }
        .map(|path| path.to_string_lossy().into_owned())
    }

    async fn output_target(
        &self,
        session_id: &str,
        tool_id: &str,
        _call_id: &str,
        _command: &str,
    ) -> Result<CommandOutputTarget> {
        let model_file = command_output_model_path(session_id, tool_id);
        Ok(CommandOutputTarget::new(
            self.workspace_root.join(&model_file),
            model_file,
        ))
    }

    #[cfg(target_os = "linux")]
    async fn spawn(&self, request: CommandSpawnRequest) -> Result<ManagedCommand> {
        let argv =
            super::shell::argv_for_environment(&self.execution_environment, &request.command);
        let (program, arguments) = argv
            .split_first()
            .ok_or_else(|| command_error("exec", "shell argv is empty"))?;
        let mut specification = ProcessCommand::new(program)
            .args(arguments)
            .current_dir(&request.cwd);
        for (key, value) in &self.child_environment {
            specification = specification.env(key, value);
        }
        self.spawn_supervised(specification, Some(&request.start_control))
            .await
    }

    #[cfg(not(target_os = "linux"))]
    async fn spawn(&self, request: CommandSpawnRequest) -> Result<ManagedCommand> {
        let mut command = command_for_environment(&self.execution_environment, &request.command);
        command
            .current_dir(&request.cwd)
            .envs(&self.child_environment);
        command
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        let mut command = wrap_background_command(command);
        request
            .start_control
            .check()
            .map_err(|error| command_error("exec", error))?;
        request.start_control.mark_start_attempted();
        let mut child = command
            .spawn()
            .map_err(|error| command_error("exec", error))?;
        let host_pid = child.id();
        let stdin = child
            .stdin()
            .take()
            .map(|value| Box::pin(value) as CommandWriter);
        let stdout = child
            .stdout()
            .take()
            .map(|value| Box::pin(value) as CommandReader);
        let stderr = child
            .stderr()
            .take()
            .map(|value| Box::pin(value) as CommandReader);
        Ok(ManagedCommand::new(
            host_pid,
            CommandIo {
                stdin,
                stdout,
                stderr,
            },
            move |cancellation| async move {
                let result = tokio::select! {
                    result = child.wait() => result,
                    _ = cancellation.cancelled() => {
                        terminate_process_tree(child.id()).await;
                        child.wait().await
                    }
                };
                result
                    .map(|status| CommandExit {
                        supervision_failure: None,
                        signal: None,
                        capture_failure: None,
                        exit_code: status.code(),
                        capture: None,
                    })
                    .map_err(|error| format!("failed to wait for local process: {error}"))
            },
        ))
    }

    async fn prepare_output(
        &self,
        target: &CommandOutputTarget,
        command: &str,
        working_directory: &str,
        capture_limit_bytes: u64,
    ) -> Result<u64> {
        let _ = (command, working_directory, capture_limit_bytes);
        prepare_local_capture_layout(&self.workspace_root, target.model_file()).await?;
        for stream in [CommandCaptureStream::Stdout, CommandCaptureStream::Stderr] {
            tokio::fs::write(target.stream_capture_file(stream), b"")
                .await
                .map_err(|error| command_error("exec", error))?;
        }
        Ok(0)
    }

    async fn append_output_chunk(
        &self,
        target: &CommandOutputTarget,
        stream: CommandCaptureStream,
        chunk: &[u8],
    ) -> Result<u64> {
        let mut file = tokio::fs::OpenOptions::new()
            .append(true)
            .open(target.stream_capture_file(stream))
            .await
            .map_err(|error| command_error("exec", error))?;
        file.write_all(chunk)
            .await
            .map_err(|error| command_error("exec", error))?;
        file.flush()
            .await
            .map_err(|error| command_error("exec", error))?;
        confirmed_capture_len(&file).await
    }

    async fn repair_output_chunk(
        &self,
        capture_file: &Path,
        _stream: CommandCaptureStream,
        committed_len: u64,
        chunk: &[u8],
    ) -> Result<u64> {
        // Truncate any partially written bytes back to the last committed offset, then re-append the
        // exact accepted chunk to its raw stream file. Truncating
        // first makes the repair idempotent: a repeated repair reproduces the same bytes instead of
        // appending the same chunk twice, and the command is never re-run.
        let file = tokio::fs::OpenOptions::new()
            .write(true)
            .open(capture_file)
            .await
            .map_err(|error| {
                command_error(
                    "exec",
                    format!("failed to open output file for repair: {error}"),
                )
            })?;
        file.set_len(committed_len).await.map_err(|error| {
            command_error(
                "exec",
                format!("failed to truncate partial output: {error}"),
            )
        })?;
        drop(file);
        let mut file = tokio::fs::OpenOptions::new()
            .append(true)
            .open(capture_file)
            .await
            .map_err(|error| {
                command_error(
                    "exec",
                    format!("failed to reopen output file for repair: {error}"),
                )
            })?;
        file.write_all(chunk).await.map_err(|error| {
            command_error("exec", format!("failed to repair output chunk: {error}"))
        })?;
        file.flush().await.map_err(|error| {
            command_error("exec", format!("failed to flush command output: {error}"))
        })?;
        confirmed_capture_len(&file).await
    }

    async fn publish_output(&self, _target: &CommandOutputTarget) -> Result<()> {
        Ok(())
    }

    async fn collect_output_artifacts(
        &self,
        _target: &CommandOutputTarget,
        _sizes: CommandOutputSizes,
    ) -> Result<Vec<Value>> {
        Ok(Vec::new())
    }
}

fn command_error(tool: &str, error: impl std::fmt::Display) -> PureError {
    PureError::ToolExecutionFailed {
        tool: tool.to_string(),
        error: error.to_string(),
    }
}

/// The length an open capture fragment now has, as the backend's confirmed write fact.
///
/// A write that cannot report its result is a capture failure, not a length to guess: the caller keeps
/// the previous confirmed offset and owes a repair, so a fragment whose length cannot be read is never
/// archived as if it were whole.
async fn confirmed_capture_len(file: &tokio::fs::File) -> Result<u64> {
    let metadata = file
        .metadata()
        .await
        .map_err(|error| command_error("exec", format!("failed to read output length: {error}")))?;
    Ok(metadata.len())
}

async fn prepare_local_capture_layout(
    workspace_root: &std::path::Path,
    model_file: &std::path::Path,
) -> Result<()> {
    let backend =
        crate::workspace_file::LocalWorkspaceFileBackend::new(workspace_root.to_path_buf(), false)
            .await?;
    crate::workspace::prepare_command_capture(&backend, model_file).await
}

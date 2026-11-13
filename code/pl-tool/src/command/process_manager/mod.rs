use std::collections::{HashMap, HashSet};
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use pl_protocol::PureError;
use tokio::io::AsyncWriteExt;
use tokio::sync::{Mutex, Notify};
use tokio_util::sync::CancellationToken;

use super::backend::{
    CommandBackend, CommandOutputSizes, CommandOutputTarget, CommandSpawnRequest, CommandWriter,
};
use super::head_tail_buffer::HeadTailBuffer;
use crate::tool_error;

mod lifecycle;
mod snapshot;
mod start_error;
pub use start_error::{CommandRunError, CommandRunFailure};
mod state;
mod stdin;
mod stream_io;
use stdin::CommandInput;
pub use stdin::{CommandInputOutcome, CommandInputReceipt};

use lifecycle::{CommandLifecycle, spawn_lifecycle_task, wait_for_process_activity};
use snapshot::message_for_state;
use state::CommandProcessTransition;
pub use state::{
    CommandCaptureFailure, CommandProcessFailure, CommandProcessFinalResult,
    CommandProcessLifecycle, CommandTerminationReason, DrainingCommandProcess, FinalCommandProcess,
    RunningCommandProcess, TerminatingCommandProcess,
};
use stream_io::{read_stderr, read_stdout};

const INTERNAL_BUFFER_BYTES: usize = 64 * 1024;
/// Execution-side raw stdout/stderr share this per-command budget.
pub const MAX_CAPTURE_BYTES: u64 = 16 * 1024 * 1024;
static NEXT_PROCESS_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Debug)]
pub struct CommandProcessManager<B>
where
    B: CommandBackend,
{
    state: Arc<std::sync::Mutex<CommandProcessManagerState>>,
    backend: Arc<B>,
    lifetime: Arc<ManagerLifetime>,
}

impl<B> Clone for CommandProcessManager<B>
where
    B: CommandBackend,
{
    fn clone(&self) -> Self {
        Self {
            state: self.state.clone(),
            backend: self.backend.clone(),
            lifetime: self.lifetime.clone(),
        }
    }
}

#[derive(Debug)]
struct CommandProcessManagerState {
    entries: HashMap<String, Arc<CommandProcessEntry>>,
    task_reservations: HashSet<String>,
}

struct StartReservation {
    state: Arc<std::sync::Mutex<CommandProcessManagerState>>,
    id: String,
    active: bool,
}
impl Drop for StartReservation {
    fn drop(&mut self) {
        if self.active {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.task_reservations.remove(&self.id);
        }
    }
}

struct CommandProcessEntry {
    process_id: String,
    output_target: CommandOutputTarget,
    stdin: Mutex<CommandInput>,
    input_stopped: CancellationToken,
    state: Mutex<CommandProcessState>,
    notify: Notify,
    output_observer: Option<Arc<dyn CommandOutputObserver>>,
    /// Ends abandoned preview reads; each Drop settles its capture observation.
    drain_stopped: CancellationToken,
    /// Asks the lifecycle to terminate the process after a hard output failure.
    ///
    /// The read tasks hold a clone, so a capture that can no longer continue stops the process tree
    /// immediately instead of leaving it running while its output is silently dropped.
    output_failure: CancellationToken,
}

impl std::fmt::Debug for CommandProcessEntry {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("CommandProcessEntry")
            .field("process_id", &self.process_id)
            .field("output_file", &self.output_target.model_file())
            .field("state", &self.state)
            .finish_non_exhaustive()
    }
}

#[derive(Debug)]
struct CommandProcessState {
    lifecycle: CommandProcessLifecycle,
    stdout_open: bool,
    stderr_open: bool,
    stdout: HeadTailBuffer,
    stderr: HeadTailBuffer,
    pending_stdout: HeadTailBuffer,
    pending_stderr: HeadTailBuffer,
    output_revision: u64,
    exit: Option<crate::command::CommandExit>,
    /// 本 operation 的落盘上限（字节），启动时由 backend 声明或取 PL 默认值。
    capture_limit_bytes: u64,
    capture_result: Option<crate::command::CommandCaptureResult>,
    capture_completion_observed: bool,
    /// 本 operation 生效的模型可见输出字节上限；`None` 表示沿用既有截断语义。
    model_output_bytes_cap: Option<u64>,
    /// Exact reason a hard output capture failure terminated this operation, if any.
    output_failure: Option<CommandCaptureFailure>,
}

pub struct CommandStartRequest {
    pub command: String,
    pub cwd: Option<PathBuf>,
    pub allow_workspace_escape: bool,
    pub timeout: Duration,
    pub yield_time: Duration,
    pub max_output_chars: usize,
    pub session_id: String,
    pub tool_id: String,
    pub call_id: String,
    pub cancellation_token: Option<CancellationToken>,
    pub output_observer: Option<Arc<dyn CommandOutputObserver>>,
}

impl std::fmt::Debug for CommandStartRequest {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("CommandStartRequest")
            .field("cwd", &self.cwd)
            .field("allow_workspace_escape", &self.allow_workspace_escape)
            .field("timeout", &self.timeout)
            .field("yield_time", &self.yield_time)
            .field("max_output_chars", &self.max_output_chars)
            .field("session_id", &self.session_id)
            .field("tool_id", &self.tool_id)
            .field("call_id", &self.call_id)
            .field("cancellation_token", &self.cancellation_token.is_some())
            .finish_non_exhaustive()
    }
}

#[derive(Debug)]
pub struct CommandWriteRequest {
    pub cancellation: CancellationToken,
    pub close_stdin: bool,
    pub process_id: String,
    pub chars: String,
    pub yield_time: Duration,
    pub max_output_chars: usize,
}

pub use pl_tool_command::process::{CommandOutputLimit, CommandOutputSnapshot};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CommandOutputStream {
    Stdout,
    Stderr,
}

/// 命令输出实时观察者。
///
/// `CommandProcessManager` 在读取 stdout/stderr chunk 后调用实现者，
/// 用于把后台进程输出投影到上层 timeline 或其他 live 观察通道。
pub trait CommandOutputObserver: Send + Sync + 'static {
    fn output_chunk(&self, stream: CommandOutputStream, chunk: &[u8], revision: u64);
    fn output_closed(&self, _stream: CommandOutputStream) {}
    /// Reports a hard capture failure the moment the reader observes it.
    ///
    /// The reader calls this under the failing operation's own boundary, *before* the process tree
    /// finishes terminating and draining, so an observer that holds the running call's channel can
    /// latch the typed fault while the call is still in flight instead of only when `execute`
    /// unwinds. The default is a no-op so a preview-only observer need not care.
    fn output_failed(&self, _failure: &CommandCaptureFailure) {}
}

#[derive(Debug, Default)]
struct ManagerLifetime(CancellationToken);

impl Drop for ManagerLifetime {
    fn drop(&mut self) {
        self.0.cancel();
    }
}

impl<B> CommandProcessManager<B>
where
    B: CommandBackend,
{
    pub fn new(backend: Arc<B>) -> Self {
        Self {
            state: Arc::new(std::sync::Mutex::new(CommandProcessManagerState {
                entries: HashMap::new(),
                task_reservations: HashSet::new(),
            })),
            backend,
            lifetime: Arc::new(ManagerLifetime::default()),
        }
    }

    /// The immutable execution binding used by this product task table.
    pub fn backend(&self) -> Arc<B> {
        self.backend.clone()
    }

    pub async fn start(
        &self,
        request: CommandStartRequest,
    ) -> Result<CommandOutputSnapshot, PureError> {
        let yield_time = request.yield_time;
        let max_output_chars = request.max_output_chars;
        let control = self.start_control(&request)?;
        let entry = self.start_entry(request, None, control).await?;
        self.snapshot_after_wait(&entry.process_id, yield_time, max_output_chars)
            .await
    }

    /// Runs a command under its session task ID until process exit and output drain.
    ///
    /// # Errors
    /// Returns spawn, capture, identity, or output publication failures. Cancellation
    /// is passed to the process lifecycle and does not abandon the process waiter.
    pub async fn run_task(
        &self,
        task_id: &str,
        request: CommandStartRequest,
    ) -> Result<CommandOutputSnapshot, CommandRunError> {
        let max_output_chars = request.max_output_chars;
        let control = self
            .start_control(&request)
            .map_err(|source| CommandRunError {
                failure: CommandRunFailure::ArgumentOutOfRange,
                process_started: Some(false),
                source,
            })?;
        let entry = self
            .start_entry(request, Some(task_id), control.clone())
            .await
            .map_err(|source| {
                let stopped = control.check();
                let failure = if control.start_attempted() {
                    CommandRunFailure::StartUncertain
                } else {
                    match stopped {
                        Err(super::backend::CommandStartError::Cancelled) => {
                            CommandRunFailure::Cancelled
                        }
                        Err(super::backend::CommandStartError::Expired) => {
                            CommandRunFailure::TimedOut
                        }
                        _ => CommandRunFailure::StartFailed,
                    }
                };
                CommandRunError {
                    failure,
                    process_started: (!control.start_attempted()).then_some(false),
                    source,
                }
            })?;
        loop {
            let notified = entry.notify.notified();
            tokio::pin!(notified);
            notified.as_mut().enable();
            if entry.is_final().await {
                break;
            }
            notified.await;
        }
        self.snapshot_entry(&entry, max_output_chars)
            .await
            .map_err(|source| CommandRunError {
                failure: CommandRunFailure::OutputPublication,
                process_started: Some(true),
                source,
            })
    }

    fn start_control(
        &self,
        request: &CommandStartRequest,
    ) -> Result<super::backend::CommandStartControl, PureError> {
        let deadline = tokio::time::Instant::now()
            .checked_add(request.timeout)
            .ok_or_else(|| {
                tool_error(
                    "exec",
                    "timeoutSeconds cannot be represented by this platform",
                )
            })?;
        Ok(super::backend::CommandStartControl::new(
            deadline,
            request.cancellation_token.clone().unwrap_or_default(),
            self.lifetime.0.clone(),
        ))
    }

    async fn start_entry(
        &self,
        request: CommandStartRequest,
        task_id: Option<&str>,
        start_control: super::backend::CommandStartControl,
    ) -> Result<Arc<CommandProcessEntry>, PureError> {
        let admitted_at = tokio::time::Instant::now();
        if request
            .cancellation_token
            .as_ref()
            .is_some_and(CancellationToken::is_cancelled)
            || self.lifetime.0.is_cancelled()
        {
            return Err(tool_error("exec", "Task cancelled before admission"));
        }
        let working_directory = self
            .backend
            .resolve_cwd(request.cwd.as_deref(), request.allow_workspace_escape)
            .await
            .map_err(|error| tool_error("exec", error))?;
        let output_target = self
            .backend
            .output_target(
                &request.session_id,
                &request.tool_id,
                &request.call_id,
                &request.command,
            )
            .await
            .map_err(|error| tool_error("exec", error))?;
        let mut reservation = self.reserve_start(task_id)?;
        let process_id = reservation.id.clone();
        let capture_limit_bytes = self
            .backend
            .capture_limit_bytes()
            .unwrap_or(MAX_CAPTURE_BYTES);
        if request
            .cancellation_token
            .as_ref()
            .is_some_and(CancellationToken::is_cancelled)
            || self.lifetime.0.is_cancelled()
            || admitted_at.elapsed() >= request.timeout
        {
            return Err(tool_error(
                "exec",
                "Task cancelled or expired before capture preparation",
            ));
        }
        self.backend
            .prepare_output(
                &output_target,
                &request.command,
                &working_directory,
                capture_limit_bytes,
            )
            .await
            .map_err(|error| tool_error("exec", error))?;
        // 模型可见字节上限同样在启动时定一次；backend 没声明就是 `None`（既有语义）。
        let model_output_bytes_cap = self.backend.model_output_bytes_cap();

        start_control
            .check()
            .map_err(|error| tool_error("exec", error))?;
        let child = self
            .backend
            .spawn(CommandSpawnRequest {
                start_control: start_control.clone(),
                process_id: process_id.clone(),
                command: request.command,
                cwd: working_directory,
                output_target: output_target.clone(),
                capture_limit_bytes,
            })
            .await;
        let mut child = child.map_err(|error| tool_error("exec", error))?;
        let stdout = child.take_stdout();
        let stderr = child.take_stderr();
        let stdout_open = stdout.is_some();
        let stderr_open = stderr.is_some();
        let stdin = child.take_stdin();
        let output_failure = CancellationToken::new();
        let entry = Arc::new(CommandProcessEntry {
            process_id: process_id.clone(),
            output_target,
            stdin: Mutex::new(CommandInput {
                writer: stdin,
                accepted_bytes: 0,
                close_state: crate::command::StdinCloseState::Open,
            }),
            input_stopped: CancellationToken::new(),
            state: Mutex::new(CommandProcessState::new(
                stdout_open,
                stderr_open,
                capture_limit_bytes,
                model_output_bytes_cap,
            )),
            notify: Notify::new(),
            drain_stopped: CancellationToken::new(),
            output_observer: request.output_observer,
            output_failure: output_failure.clone(),
        });
        {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.task_reservations.remove(&process_id);
            state.entries.insert(process_id.clone(), entry.clone());
            reservation.active = false;
        }
        spawn_lifecycle_task(
            entry.clone(),
            child,
            CommandLifecycle {
                timeout: start_control
                    .deadline()
                    .saturating_duration_since(tokio::time::Instant::now()),
                task_cancellation: request.cancellation_token,
                manager_cancellation: self.lifetime.0.clone(),
                output_failure,
            },
        );

        if let Some(stdout) = stdout {
            tokio::spawn(read_stdout(entry.clone(), stdout));
        }
        if let Some(stderr) = stderr {
            tokio::spawn(read_stderr(entry.clone(), stderr));
        }
        Ok(entry)
    }

    fn reserve_start(&self, task_id: Option<&str>) -> Result<StartReservation, PureError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let id = match task_id {
            Some(id) => {
                if !id.starts_with("task-") || id.len() > 256 {
                    return Err(tool_error("exec", "invalid session task ID"));
                }
                if state.entries.contains_key(id) || state.task_reservations.contains(id) {
                    return Err(tool_error("exec", "session task already owns a process"));
                }
                state.task_reservations.insert(id.to_owned());
                id.to_owned()
            }
            None => {
                let id = NEXT_PROCESS_ID
                    .try_update(Ordering::Relaxed, Ordering::Relaxed, |id| id.checked_add(1))
                    .map_err(|_| tool_error("exec", "process identity exhausted"))?;
                format!("proc-{id}")
            }
        };
        Ok(StartReservation {
            state: self.state.clone(),
            id,
            active: true,
        })
    }

    async fn entry(&self, process_id: &str) -> Option<Arc<CommandProcessEntry>> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .entries
            .get(process_id)
            .cloned()
    }

    /// Reads current root and output observations without consuming the operation.
    pub async fn snapshot(
        &self,
        process_id: &str,
        max_output_chars: usize,
    ) -> Option<CommandOutputSnapshot> {
        let entry = self.entry(process_id).await?;
        self.snapshot_entry(&entry, max_output_chars).await.ok()
    }

    async fn snapshot_after_wait(
        &self,
        process_id: &str,
        yield_time: Duration,
        max_output_chars: usize,
    ) -> Result<CommandOutputSnapshot, PureError> {
        let Some(entry) = self.entry(process_id).await else {
            return Err(tool_error(
                "write_stdin",
                format!("processId '{process_id}' is not a live process"),
            ));
        };
        wait_for_process_activity(&entry, yield_time).await;
        self.snapshot_entry(&entry, max_output_chars).await
    }

    async fn snapshot_entry(
        &self,
        entry: &CommandProcessEntry,
        max_output_chars: usize,
    ) -> Result<CommandOutputSnapshot, PureError> {
        self.backend
            .publish_output(&entry.output_target)
            .await
            .map_err(|error| tool_error("exec", error))?;
        let (mut snapshot, sizes) = entry.snapshot(max_output_chars).await;
        if snapshot.process_id.is_none() {
            snapshot.output_artifacts = self
                .backend
                .collect_output_artifacts(&entry.output_target, sizes)
                .await
                .map_err(|error| tool_error("exec", error))?;
            self.state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .entries
                .remove(&entry.process_id);
        }
        Ok(snapshot)
    }
}

impl CommandProcessEntry {
    async fn can_accept_input(&self) -> bool {
        let state = self.state.lock().await;
        state.can_accept_input()
    }

    async fn is_final(&self) -> bool {
        self.state.lock().await.is_final()
    }

    async fn snapshot(
        &self,
        max_output_chars: usize,
    ) -> (CommandOutputSnapshot, CommandOutputSizes) {
        let mut state = self.state.lock().await;
        let process_id = (!state.lifecycle.is_final()).then(|| self.process_id.clone());
        let message = message_for_state(&state);
        let sizes = CommandOutputSizes {
            stdout_bytes: state.stdout.total_bytes() as u64,
            stderr_bytes: state.stderr.total_bytes() as u64,
        };
        let (stdout_excerpt, stderr_excerpt) = if state.lifecycle.is_final() {
            (state.stdout.excerpt(), state.stderr.excerpt())
        } else {
            (
                state.pending_stdout.take_excerpt(),
                state.pending_stderr.take_excerpt(),
            )
        };
        let mut stdout_budget = max_output_chars.min(stdout_excerpt.display_len());
        let mut stderr_budget = max_output_chars.min(stderr_excerpt.display_len());
        let model_output_bytes_cap = state.model_output_bytes_cap();
        {
            let cap_bytes = model_output_bytes_cap
                .map(|cap| usize::try_from(cap).unwrap_or(usize::MAX))
                .unwrap_or(max_output_chars)
                .min(max_output_chars);
            let total = stdout_budget.saturating_add(stderr_budget);
            if total > cap_bytes {
                // 乘法在 u128 中进行，不能因饱和乘法把大预算错误分配给某一流。
                stdout_budget =
                    ((cap_bytes as u128 * stdout_budget as u128) / total as u128) as usize;
                stderr_budget = cap_bytes - stdout_budget;
            }
        }
        let capture_limit_bytes = state.capture_limit_bytes;
        let capture = state.capture_result.clone();
        let stdout_text_lossy = state.stdout.text_lossy();
        let stderr_text_lossy = state.stderr.text_lossy();
        let state_exit_code = state.exit.as_ref().and_then(|exit| exit.exit_code);
        let state_signal = state.exit.as_ref().and_then(|exit| exit.signal);
        let lifecycle = state.lifecycle.clone();
        let output_revision = state.output_revision;
        let output_failure = state.output_failure.clone();
        drop(state);
        let (stdout, stdout_omission_marker) = stdout_excerpt.project_with_omission(stdout_budget);
        let (stderr, stderr_omission_marker) = stderr_excerpt.project_with_omission(stderr_budget);
        (
            CommandOutputSnapshot {
                state: lifecycle,
                process_id,
                stdout,
                stderr,
                stdout_omission_marker,
                stderr_omission_marker,
                output_file: self.output_target.model_file().to_path_buf(),
                capture_file: self.output_target.capture_file().to_path_buf(),
                stderr_capture_file: self
                    .output_target
                    .stream_capture_file(super::backend::CommandCaptureStream::Stderr)
                    .to_path_buf(),
                stderr_output_file: self
                    .output_target
                    .stream_model_file(super::backend::CommandCaptureStream::Stderr)
                    .to_path_buf(),
                message,
                output_revision,
                exit_code: state_exit_code,
                signal: state_signal,
                input_receipt: None,
                stdout_text_lossy,
                stderr_text_lossy,
                output_artifacts: Vec::new(),
                output_failure,
                capture,
                capture_limit_bytes,
                model_output_bytes_cap,
            },
            sizes,
        )
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StreamKind {
    Stdout,
    Stderr,
}

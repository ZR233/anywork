//! Command execution through the opaque Thread contract.
use std::{fmt, future::Future, sync::Arc, time::Duration};

use pl_core::context::{OpaquePayload, ResourceReference};
use pl_core::thread::cold::{
    ColdStoreError, OutputRepair, OutputRetryFuture, OutputRetryObligation, OutputRetryOutcome,
    OutputStorageFault, StorageFaultKind,
};
use pl_core::tool::{
    ToolOutput,
    opaque::{CallContext, Registration, ToolError},
};
use sha2::{Digest, Sha256};

use crate::command::{
    CommandBackend,
    process_manager::{
        CommandOutputSnapshot, CommandProcessFinalResult, CommandProcessManager,
        CommandStartRequest,
    },
};
use pl_tool_command::exec::ExecOutcome;
use pl_tool_command::process::{
    InputRequest, InputTarget, ProcessExecutor, ProcessInput, ProcessRequest,
};

/// Host-selected command scope. Dynamic input cannot grant workspace escape.
#[derive(Debug, Clone, Copy)]
pub enum CommandAccess {
    WorkspaceOnly,
    HostGranted,
    /// Host paths require an invocation capability from the registered policy.
    HostApproval,
}

/// Retains complete captured bytes under a stable, readable resource identity.
pub trait CommandOutputArchive: fmt::Debug + Send + Sync + 'static {
    /// Archives output after physical process exit and stream drain.
    ///
    /// # Errors
    /// On failure, keep the source capture intact so the host can retry archiving without
    /// re-executing the command. Never return a temporary path as a durable resource.
    fn retain(
        &self,
        thread_id: &str,
        snapshot: &CommandOutputSnapshot,
        stream: crate::command::CommandCaptureStream,
    ) -> impl Future<Output = Result<ResourceReference, ToolError>> + Send;
}

/// Thread-owned exec instance using a host-provided backend and output archive.
#[derive(Debug)]
pub struct ThreadExecTool<B: CommandBackend, A: CommandOutputArchive> {
    definition: pl_agent_tool::ToolDefinition,
    processes: Arc<CommandProcessManager<B>>,
    archive: Arc<A>,
    access: CommandAccess,
}

impl<B: CommandBackend, A: CommandOutputArchive> ThreadExecTool<B, A> {
    /// Binds services once; the returned tool must belong to only one Thread.
    pub fn new(
        backend: Arc<B>,
        archive: Arc<A>,
        access: CommandAccess,
        definition: pl_agent_tool::ToolDefinition,
    ) -> Self {
        Self {
            definition,
            processes: Arc::new(CommandProcessManager::new(backend)),
            archive,
            access,
        }
    }

    /// Binds a prepared definition while retaining this Thread's existing physical command manager.
    pub fn from_process_manager(
        processes: Arc<CommandProcessManager<B>>,
        archive: Arc<A>,
        access: CommandAccess,
        definition: pl_agent_tool::ToolDefinition,
    ) -> Self {
        Self {
            definition,
            processes,
            archive,
            access,
        }
    }

    /// Transfers paired instances over this Thread's one process manager.
    ///
    /// Both definitions have already been frozen and their registration identities validated.
    pub fn registrations(
        self,
        exec: pl_core::tool::opaque::PreparedRegistration,
        stdin: pl_core::tool::opaque::PreparedRegistration,
        stdin_definition: pl_agent_tool::ToolDefinition,
    ) -> Vec<Registration> {
        let input = ThreadWriteStdinTool {
            definition: stdin_definition,
            processes: self.processes.clone(),
        };
        vec![
            self.registration(exec),
            stdin
                .attach(pl_agent_tool::ToolHandle::new(input))
                .with_presentation_contract(pl_core::model::ToolPresentationContract::new(
                    "builtin.write_stdin@1",
                )),
        ]
    }

    /// Transfers this instance with the host's frozen model declaration.
    ///
    /// The supplied preparation has already validated the registration identity.
    pub fn registration(
        self,
        prepared: pl_core::tool::opaque::PreparedRegistration,
    ) -> Registration {
        prepared
            .attach(pl_agent_tool::ToolHandle::new(self))
            .with_presentation_contract(pl_core::model::ToolPresentationContract::new(
                "builtin.exec@2",
            ))
    }
}

/// Retry retaining the same confirmed prefix in desktop history. Never reconstruct
/// unknown capture bytes, append to the target file or execute the command again.
#[derive(Debug)]
struct ArchiveRetentionObligation<A: CommandOutputArchive> {
    archive: Arc<A>,
    thread_id: String,
    call_id: String,
    snapshot: CommandOutputSnapshot,
    kind: StorageFaultKind,
    stream: crate::command::CommandCaptureStream,
}

impl<A: CommandOutputArchive> ArchiveRetentionObligation<A> {
    fn new(
        archive: Arc<A>,
        thread_id: &str,
        call_id: &str,
        snapshot: CommandOutputSnapshot,
        kind: StorageFaultKind,
        stream: crate::command::CommandCaptureStream,
    ) -> Self {
        Self {
            archive,
            thread_id: thread_id.to_owned(),
            call_id: call_id.to_owned(),
            snapshot,
            kind,
            stream,
        }
    }
}

impl<A: CommandOutputArchive> ArchiveRetentionObligation<A> {
    fn capture_path(&self) -> &std::path::Path {
        match self.stream {
            crate::command::CommandCaptureStream::Stdout => &self.snapshot.capture_file,
            crate::command::CommandCaptureStream::Stderr => &self.snapshot.stderr_capture_file,
        }
    }
}

impl<A: CommandOutputArchive> OutputRetryObligation for ArchiveRetentionObligation<A> {
    fn identity(&self) -> String {
        // The capture path is the stable identity of one operation's accepted output: the live report
        // and the return path both name the same fragment, so the owner attaches one obligation even
        // when the failure is reported twice, and two parallel operations (different paths) keep
        // separate obligations instead of one overwriting the other.
        self.capture_path().display().to_string()
    }
    fn retry(&self) -> OutputRetryFuture<'_> {
        Box::pin(async move {
            let reference = super::capture_retention::retain(
                &*self.archive,
                &self.thread_id,
                &self.snapshot,
                self.stream,
            )
            .await
            .map_err(|error| ColdStoreError {
                source: Box::new(error),
            })?;
            // The stored reference belongs to the already-committed tool result of this same call:
            // name that identity so the owner attaches the reference to it instead of leaving an
            // orphan blob the UI and cold recovery can never locate.
            Ok(OutputRetryOutcome::StoredWithRepair(OutputRepair {
                call_id: self.call_id.clone(),
                reference,
            }))
        })
    }

    fn received_bytes(&self) -> u64 {
        self.snapshot
            .confirmed_bytes(self.stream)
            .expect("archive obligations require a confirmed prefix")
    }

    fn location(&self) -> String {
        self.capture_path().display().to_string()
    }

    fn kind(&self) -> StorageFaultKind {
        self.kind
    }
}

/// Input writer paired with an exec instance from the same Thread assembly.
#[derive(Debug)]
struct ThreadWriteStdinTool<B: CommandBackend> {
    definition: pl_agent_tool::ToolDefinition,
    processes: Arc<CommandProcessManager<B>>,
}

impl<B: CommandBackend> pl_agent_tool::Tool for ThreadWriteStdinTool<B> {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let tool = pl_tool_command::write_stdin::WriteStdinTool::new(self.definition.clone());
        let result = tool
            .execute(
                input.content().to_owned(),
                pl_tool_command::write_stdin::StdinContext {
                    processes: ThreadInputPort {
                        processes: self.processes.clone(),
                        tasks: context.tasks.clone(),
                    },
                    cancellation: context.cancellation.clone(),
                },
            )
            .await
            .map_err(|error| match error {
                pl_tool_command::write_stdin::StdinError::InvalidInput(error) => {
                    super::ExecInputError(error).into_tool_error()
                }
                pl_tool_command::write_stdin::StdinError::Process(error) => error,
                pl_tool_command::write_stdin::StdinError::Cancelled => {
                    ToolError::new(pl_core::thread::ThreadError::Cancelled)
                }
                pl_tool_command::write_stdin::StdinError::Encoding(error) => ToolError::new(error),
            })?;
        let outcome = match &result {
            pl_tool_command::write_stdin::StdinResult::Terminal { receipt_json } => {
                return super::output::receipt_output("pl.tool.stdin", receipt_json.clone());
            }
            pl_tool_command::write_stdin::StdinResult::Observed { outcome, .. } => *outcome,
        };
        let text = result
            .encode(super::output::current_receipt(&context))
            .map_err(ToolError::new)?;
        let output = super::output::receipt_output("pl.tool.exec", text)?;
        match outcome {
            pl_tool_command::write_stdin::InputOutcome::Complete => Ok(output),
            pl_tool_command::write_stdin::InputOutcome::Cancelled => Err(ToolError::new(pl_core::thread::ThreadError::Cancelled).with_output(output)),
            pl_tool_command::write_stdin::InputOutcome::Incomplete => Err(ToolError::new(ExecFailure::Process("stdin delivery incomplete; inspect accepted and confirmed offsets before continuing".into())).with_output(output)),
        }
    }
}

/// `exec`/`write_stdin` 在进程语义之外的结构化失败原因。
///
/// 生产者把结构化事实报成 typed 错误而不是只拼一段文本，调用方因此能把"命令按自己声明的输出
/// 上限被终止"与"退出码失败、超时、取消"分开处理，而不必解析诊断文本。
#[derive(Debug, thiserror::Error)]
pub enum ExecFailure {
    /// The process and capture completed; its nonzero status is business output.
    #[error("command did not complete successfully: Command exited with code {exit_code}")]
    NonzeroExit { exit_code: i32 },
    #[error(
        "stdin task {task_id} is not a running exec task: status={status:?}, cancelRequested={cancelled}"
    )]
    TaskUnavailable {
        task_id: String,
        status: pl_core::thread::task::TaskStatus,
        cancelled: bool,
    },
    #[error("write_stdin requires task access from its owning Thread")]
    InvalidInput,
    #[error("command did not complete successfully: {0}")]
    Process(String),
    /// 命令输出触及本 operation 的单命令落盘上限：命令已被终止，已写出的部分保留并照常归档。
    ///
    /// 这是预期内的容量终止，不是可靠保存故障：它不欠任何可靠保存义务，进程管理器也不会为它
    /// 挂 `OutputRetryObligation`，因此不会触发无限 repair。
    #[error(
        "command output exceeded the {limit_bytes}-byte per-command capture limit: confirmed stored bytes: {charged_bytes:?}, observed refused bytes: {refused_bytes:?}"
    )]
    OutputLimitExceeded {
        /// 本 operation 生效的落盘上限（字节）。
        limit_bytes: u64,
        /// 已接纳（因此已保留）的存储成本。
        charged_bytes: Option<u64>,
        /// 被拒绝接纳的存储成本。
        refused_bytes: Option<u64>,
    },
}

impl<B: CommandBackend, A: CommandOutputArchive> pl_agent_tool::Tool for ThreadExecTool<B, A> {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let task_id = safe_identity(&context.call_id);
        let (observer, previews) = super::progress::ExecOutputObserver::channel();
        let tool = pl_tool_command::exec::ExecTool::new(self.definition.clone());
        let execution = tool.execute(
            input.content().to_owned(),
            pl_tool_command::exec::ExecContext {
                process: ThreadCommandPort {
                    processes: self.processes.clone(),
                    task_id: task_id.clone(),
                    thread_id: context.thread_id.clone(),
                    observer,
                },
                allow_workspace_escape: match self.access {
                    CommandAccess::WorkspaceOnly => false,
                    CommandAccess::HostGranted => true,
                    CommandAccess::HostApproval => context
                        .grant
                        .contains(crate::approval::HOST_WORKSPACE_ACCESS),
                },
                cancellation: context.cancellation.clone(),
            },
        );
        let result = super::progress::drive(execution, previews, context.tasks.as_ref()).await;
        let mut result = result.map_err(|error| match error {
            pl_tool_command::exec::ExecError::InvalidInput(error) => {
                super::ExecInputError(error).into_tool_error()
            }
            pl_tool_command::exec::ExecError::Process(error) => {
                super::output::start_error(error, &context)
            }
        })?;
        let snapshot = &mut result.snapshot;
        let mut resources = Vec::new();
        let mut archive_error = None;
        for stream in [
            crate::command::CommandCaptureStream::Stdout,
            crate::command::CommandCaptureStream::Stderr,
        ] {
            // A disconnected or abandoned stream has no trustworthy prefix to retain.
            if snapshot.confirmed_bytes(stream).is_none() {
                continue;
            }
            match super::capture_retention::retain(
                &*self.archive,
                &context.thread_id,
                snapshot,
                stream,
            )
            .await
            {
                Ok(reference) => resources.push((stream, reference)),
                Err(error) => {
                    let error = attach_archive_obligation(
                        error,
                        self.archive.clone(),
                        &context.thread_id,
                        &context.call_id,
                        snapshot,
                        stream,
                    );
                    if let Some(fault) = error.source.downcast_ref::<OutputStorageFault>() {
                        report_output_storage_fault(
                            context.tasks.as_ref(),
                            &Arc::new(fault.clone()),
                        )
                        .await;
                    }
                    if archive_error.is_none() {
                        archive_error = Some(error);
                    }
                }
            }
        }
        let snapshot = &result.snapshot;
        let text = result
            .encode(&resources, super::output::current_receipt(&context))
            .map_err(ToolError::new)?;
        let output = super::output::archived_output(text, &resources)?;
        if let Some(error) = archive_error {
            if matches!(
                snapshot.state.final_result(),
                Some(CommandProcessFinalResult::Cancelled)
            ) {
                return Err(
                    ToolError::new(pl_core::thread::ThreadError::Cancelled).with_output(output)
                );
            }
            return Err(error.with_output(output));
        }
        match result.outcome() {
            ExecOutcome::Cancelled => {
                Err(ToolError::new(pl_core::thread::ThreadError::Cancelled).with_output(output))
            }
            ExecOutcome::CaptureFailed => Err(ToolError::new(ExecFailure::Process(
                snapshot.message.clone(),
            ))
            .with_output(output)),
            ExecOutcome::OutputLimit(limit) => {
                Err(ToolError::new(ExecFailure::OutputLimitExceeded {
                    limit_bytes: limit.limit_bytes,
                    charged_bytes: limit.charged_bytes,
                    refused_bytes: limit.refused_bytes,
                })
                .with_output(output))
            }
            ExecOutcome::Succeeded => Ok(output),
            ExecOutcome::Failed => {
                let failure = match snapshot.state.final_result() {
                    Some(CommandProcessFinalResult::Failed {
                        failure:
                            pl_tool_command::process::CommandProcessFailure::Exited {
                                exit_code: Some(exit_code),
                            },
                    }) if *exit_code != 0
                        && snapshot.supervision_failure.is_none()
                        && snapshot.output_failure.is_none()
                        && snapshot.signal.is_none() =>
                    {
                        ExecFailure::NonzeroExit {
                            exit_code: *exit_code,
                        }
                    }
                    _ => ExecFailure::Process(result.snapshot.message),
                };
                Err(ToolError::new(failure).with_output(output))
            }
        }
    }
}

/// Attaches the archive's retriable obligation to an archive failure that named it.
///
/// Only a failure that already arrived as a typed [`OutputStorageFault`] is rebuilt with the
/// obligation; any other archive error (invalid media, integrity, a plain policy refusal) is returned
/// unchanged, because it is not a reliable-output storage obligation the owner could retry.
fn attach_archive_obligation<A: CommandOutputArchive>(
    error: ToolError,
    archive: Arc<A>,
    thread_id: &str,
    call_id: &str,
    snapshot: &CommandOutputSnapshot,
    stream: crate::command::CommandCaptureStream,
) -> ToolError {
    let Some(fault) = error.source.downcast_ref::<OutputStorageFault>() else {
        return error;
    };
    let kind = fault.kind;
    let source = fault.source.clone();
    let obligation: Arc<dyn OutputRetryObligation> = Arc::new(ArchiveRetentionObligation::new(
        archive,
        thread_id,
        call_id,
        snapshot.clone(),
        kind,
        stream,
    ));
    ToolError::new(OutputStorageFault::new(kind, source).with_obligation(obligation))
}

/// Reports one typed output fault through the running call's reliable channel, if it has one.
async fn report_output_storage_fault(
    tasks: Option<&pl_core::thread::TaskAccess>,
    fault: &Arc<OutputStorageFault>,
) {
    if let Some(tasks) = tasks {
        // A closed owner or a revoked executor still blocks admission through the return path below,
        // so a refused notification is not the only report; but it must never be silently dropped, so
        // the exact reason is surfaced instead of being discarded.
        if let Err(error) = tasks.report_output_storage_fault(fault.clone()).await {
            tracing::warn!(%error, "the running call could not report its output storage fault early");
        }
    }
}

// Model-supplied call IDs are not filesystem components.
fn safe_identity(id: &str) -> String {
    let digest = Sha256::digest(id.as_bytes());
    format!("task-{}", hex::encode(digest))
}

// The capability only admits/drives one physical operation; validation, planning and
// result shaping live in the independent tools. No second manager is constructed.
struct ThreadCommandPort<B: CommandBackend> {
    processes: Arc<CommandProcessManager<B>>,
    task_id: String,
    thread_id: String,
    observer: Arc<dyn crate::command::CommandOutputObserver>,
}
impl<B: CommandBackend> ProcessExecutor for ThreadCommandPort<B> {
    type Error = crate::command::CommandRunError;
    async fn run(&self, request: ProcessRequest) -> Result<CommandOutputSnapshot, Self::Error> {
        self.processes
            .run_task(
                &self.task_id,
                CommandStartRequest {
                    command: request.command,
                    cwd: request.cwd,
                    allow_workspace_escape: request.allow_workspace_escape,
                    timeout: request.timeout,
                    yield_time: Duration::ZERO,
                    max_output_chars: request.max_output_bytes,
                    session_id: self.thread_id.clone(),
                    tool_id: self.task_id.clone(),
                    call_id: self.task_id.clone(),
                    cancellation_token: Some(request.cancellation),
                    output_observer: Some(self.observer.clone()),
                },
            )
            .await
    }
}
struct ThreadInputPort<B: CommandBackend> {
    processes: Arc<CommandProcessManager<B>>,
    tasks: Option<pl_core::thread::TaskAccess>,
}
impl<B: CommandBackend> ProcessInput for ThreadInputPort<B> {
    type Target = String;
    type Error = ToolError;
    fn resolve(&self, receipt: &str, terminal_eof: bool) -> Result<InputTarget<String>, ToolError> {
        let access = self
            .tasks
            .as_ref()
            .ok_or_else(|| ToolError::new(ExecFailure::InvalidInput))?;
        let target = access.get(receipt).map_err(ToolError::new)?;
        if target.tool_id == super::TOOL_EXEC
            && target.status != pl_core::thread::task::TaskStatus::Running
            && terminal_eof
        {
            let status = serde_json::to_value(target.status).map_err(ToolError::new)?;
            let status = status
                .as_str()
                .expect("task status serializes as a string")
                .to_owned();
            return Ok(InputTarget::Terminal { status });
        }
        if target.tool_id != super::TOOL_EXEC
            || target.status != pl_core::thread::task::TaskStatus::Running
            || target.cancel_requested
        {
            return Err(super::output::stdin_unavailable(&target));
        }
        Ok(InputTarget::Live(safe_identity(&target.call_id)))
    }
    async fn write(
        &self,
        request: InputRequest<String>,
    ) -> Result<CommandOutputSnapshot, ToolError> {
        self.processes
            .write_stdin(crate::command::CommandWriteRequest {
                process_id: request.target,
                chars: request.chars,
                close_stdin: request.close_stdin,
                cancellation: request.cancellation,
                yield_time: Duration::ZERO,
                max_output_chars: request.max_output_bytes,
            })
            .await
            .map_err(ToolError::new)
    }
}

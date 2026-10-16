//! Command execution through the opaque Thread contract.
use std::{fmt, future::Future, sync::Arc, time::Duration};

use pl_core::context::{ContextContent, OpaquePayload, ResourceReference};
use pl_core::thread::cold::{
    ColdStoreError, OutputRepair, OutputRetryFuture, OutputRetryObligation, OutputRetryOutcome,
    OutputStorageFault, StorageFaultKind,
};
use pl_core::tool::{
    ToolOutput,
    opaque::{CallContext, Registration, RegistryError, Tool, ToolError},
};
use serde::Serialize;
use sha2::{Digest, Sha256};

use super::{DEFAULT_TIMEOUT_SECS, ExecInput, MAX_MODEL_OUTPUT_BYTES};
use crate::command::{
    CommandBackend,
    process_manager::{
        CommandCaptureFailure, CommandOutputSnapshot, CommandProcessFinalResult,
        CommandProcessManager, CommandStartRequest,
    },
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
    ) -> impl Future<Output = Result<ResourceReference, ToolError>> + Send;
}

/// Thread-owned exec instance using a host-provided backend and output archive.
#[derive(Debug)]
pub struct ThreadExecTool<B: CommandBackend, A: CommandOutputArchive> {
    processes: Arc<CommandProcessManager<B>>,
    archive: Arc<A>,
    access: CommandAccess,
}

impl<B: CommandBackend, A: CommandOutputArchive> ThreadExecTool<B, A> {
    /// Binds services once; the returned tool must belong to only one Thread.
    pub fn new(backend: Arc<B>, archive: Arc<A>, access: CommandAccess) -> Self {
        Self {
            processes: Arc::new(CommandProcessManager::new(backend)),
            archive,
            access,
        }
    }

    /// Rebuilds declarations while retaining this Thread's existing physical command manager.
    pub fn from_process_manager(
        processes: Arc<CommandProcessManager<B>>,
        archive: Arc<A>,
        access: CommandAccess,
    ) -> Self {
        Self {
            processes,
            archive,
            access,
        }
    }

    /// Transfers paired instances over this Thread's one process manager.
    ///
    /// # Errors
    /// Returns invalid declaration identities before registration.
    pub fn registrations(
        self,
        exec: OpaquePayload,
        stdin: OpaquePayload,
    ) -> Result<Vec<Registration>, RegistryError> {
        let input = ThreadWriteStdinTool {
            processes: self.processes.clone(),
        };
        Ok(vec![
            self.registration(exec)?,
            Registration::new(super::TOOL_WRITE_STDIN.into(), stdin, input)?
                .foreground_coexisting(),
        ])
    }

    /// Transfers this instance with the host's frozen model declaration.
    ///
    /// # Errors
    /// Returns an invalid tool identity error before registration.
    pub fn registration(self, declaration: OpaquePayload) -> Result<Registration, RegistryError> {
        Registration::new(super::TOOL_EXEC.into(), declaration, self)
    }
}

/// Typed obligation that re-saves a command capture the archive could not store.
///
/// It first re-materializes any accepted bytes a failed capture append could not write — truncating
/// the fragment back to the offset it was at before the failed append and re-appending exactly that
/// chunk — so a retry never archives a short fragment as if it were whole. It then re-runs the *same*
/// archive call with the *same* capture snapshot, so retrying re-saves the exact accepted bytes under
/// their stable content-addressed identity: it never reruns the command, and a repeated retry
/// produces the same reference instead of a duplicate. A successful retry also names the committed
/// tool result — by the same call id it was committed under — so the durable reference reaches that
/// result instead of becoming an orphan the UI and cold recovery cannot locate.
#[derive(Debug)]
struct ArchiveRetentionObligation<A: CommandOutputArchive, B: CommandBackend> {
    archive: Arc<A>,
    backend: Arc<B>,
    thread_id: String,
    call_id: String,
    snapshot: CommandOutputSnapshot,
    kind: StorageFaultKind,
}

impl<A: CommandOutputArchive, B: CommandBackend> ArchiveRetentionObligation<A, B> {
    fn new(
        archive: Arc<A>,
        backend: Arc<B>,
        thread_id: &str,
        call_id: &str,
        snapshot: CommandOutputSnapshot,
        kind: StorageFaultKind,
    ) -> Self {
        Self {
            archive,
            backend,
            thread_id: thread_id.to_owned(),
            call_id: call_id.to_owned(),
            snapshot,
            kind,
        }
    }
}

impl<A: CommandOutputArchive, B: CommandBackend> OutputRetryObligation
    for ArchiveRetentionObligation<A, B>
{
    fn identity(&self) -> String {
        // The capture path is the stable identity of one operation's accepted output: the live report
        // and the return path both name the same fragment, so the owner attaches one obligation even
        // when the failure is reported twice, and two parallel operations (different paths) keep
        // separate obligations instead of one overwriting the other.
        self.snapshot.capture_file.display().to_string()
    }
    fn retry(&self) -> OutputRetryFuture<'_> {
        Box::pin(async move {
            let reference = super::capture_retention::retain(
                &*self.backend,
                &*self.archive,
                &self.thread_id,
                &self.snapshot,
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
        // The bytes this operation really accepted: the fragment the backend last confirmed writing,
        // plus every accepted chunk still owed. Both are facts the obligation already carries, so the
        // reported size never depends on a fragment-length read that could fail and understate it.
        let committed = self.snapshot.capture_committed_len;
        let pending: u64 = self
            .snapshot
            .capture_repair()
            .map(|repair| {
                repair
                    .chunks
                    .iter()
                    .map(|chunk| chunk.pending.len() as u64)
                    .sum()
            })
            .unwrap_or(0);
        committed.saturating_add(pending)
    }

    fn location(&self) -> String {
        self.snapshot.capture_file.display().to_string()
    }

    fn kind(&self) -> StorageFaultKind {
        self.kind
    }
}

/// Input writer paired with an exec instance from the same Thread assembly.
#[derive(Debug)]
struct ThreadWriteStdinTool<B: CommandBackend> {
    processes: Arc<CommandProcessManager<B>>,
}

impl<B: CommandBackend> Tool for ThreadWriteStdinTool<B> {
    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let input: super::WriteStdinInput =
            serde_json::from_str(input.content()).map_err(ToolError::new)?;
        if input.chars.is_empty() || input.max_output_chars == Some(0) {
            return Err(ToolError::new(ExecFailure::InvalidInput));
        }
        let access = context
            .tasks
            .as_ref()
            .ok_or_else(|| ToolError::new(ExecFailure::InvalidInput))?;
        let target = access.get(&input.task_id).map_err(ToolError::new)?;
        if target.tool_id != super::TOOL_EXEC
            || target.status != pl_core::thread::task::TaskStatus::Running
            || target.cancel_requested
        {
            return Err(ToolError::new(ExecFailure::TaskUnavailable {
                task_id: input.task_id,
                status: target.status,
                cancelled: target.cancel_requested,
            }));
        }
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        let snapshot = self
            .processes
            .write_stdin(crate::command::process_manager::CommandWriteRequest {
                process_id: safe_identity(&target.call_id),
                chars: input.chars,
                yield_time: Duration::ZERO,
                max_output_chars: input
                    .max_output_chars
                    .unwrap_or(MAX_MODEL_OUTPUT_BYTES)
                    .min(MAX_MODEL_OUTPUT_BYTES),
            })
            .await
            .map_err(ToolError::new)?;
        projection(&snapshot, None)
    }
}

/// `exec`/`write_stdin` 在进程语义之外的结构化失败原因。
///
/// 生产者把结构化事实报成 typed 错误而不是只拼一段文本，调用方因此能把"命令按自己声明的输出
/// 上限被终止"与"退出码失败、超时、取消"分开处理，而不必解析诊断文本。
#[derive(Debug, thiserror::Error)]
pub enum ExecFailure {
    #[error(
        "stdin task {task_id} is not a running exec task: status={status:?}, cancelRequested={cancelled}"
    )]
    TaskUnavailable {
        task_id: String,
        status: pl_core::thread::task::TaskStatus,
        cancelled: bool,
    },
    #[error("write_stdin requires nonempty input and an active exec task in this Thread")]
    InvalidInput,
    #[error("exec command must not be empty")]
    EmptyCommand,
    #[error("exec timeoutSeconds and maxOutputChars must be positive")]
    InvalidLimit,
    #[error("command did not complete successfully: {0}")]
    Process(String),
    /// 命令输出触及本 operation 的单命令落盘上限：命令已被终止，已写出的部分保留并照常归档。
    ///
    /// 这是预期内的容量终止，不是可靠保存故障：它不欠任何可靠保存义务，进程管理器也不会为它
    /// 挂 `OutputRetryObligation`，因此不会触发无限 repair。
    #[error(
        "command output exceeded the {limit_bytes}-byte per-command capture limit: {charged_bytes} bytes of capture were stored and {refused_bytes} bytes of observed storage cost were refused"
    )]
    OutputLimitExceeded {
        /// 本 operation 生效的落盘上限（字节）。
        limit_bytes: u64,
        /// 已接纳（因此已保留）的存储成本。
        charged_bytes: u64,
        /// 被拒绝接纳的存储成本。
        refused_bytes: u64,
    },
}

impl<B: CommandBackend, A: CommandOutputArchive> Tool for ThreadExecTool<B, A> {
    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let input: ExecInput = serde_json::from_str(input.content()).map_err(ToolError::new)?;
        if input.command.trim().is_empty() {
            return Err(ToolError::new(ExecFailure::EmptyCommand));
        }
        if input.timeout_seconds == Some(0) || input.max_output_chars == Some(0) {
            return Err(ToolError::new(ExecFailure::InvalidLimit));
        }
        let task_id = safe_identity(&context.call_id);
        let max_output_chars = input
            .max_output_chars
            .unwrap_or(MAX_MODEL_OUTPUT_BYTES)
            .min(MAX_MODEL_OUTPUT_BYTES);
        let (observer, previews, failures) = super::progress::ExecOutputObserver::channel();
        let execution = self.processes.run_task(
            &task_id,
            CommandStartRequest {
                command: input.command,
                cwd: input.cwd,
                allow_workspace_escape: match self.access {
                    CommandAccess::WorkspaceOnly => false,
                    CommandAccess::HostGranted => true,
                    CommandAccess::HostApproval => context
                        .grant
                        .contains(crate::approval::HOST_WORKSPACE_ACCESS),
                },
                timeout: Duration::from_secs(input.timeout_seconds.unwrap_or(DEFAULT_TIMEOUT_SECS)),
                yield_time: Duration::ZERO,
                max_output_chars,
                session_id: safe_identity(&context.thread_id),
                tool_id: task_id.clone(),
                call_id: task_id.clone(),
                cancellation_token: Some(context.cancellation.clone()),
                output_observer: Some(observer),
            },
        );
        // Report a capture failure through the running call's reliable channel the moment the reader
        // observes it — before the process tree finishes terminating and draining — so other
        // model/tool admission is blocked while this call is still in flight, not only when `drive`
        // returns. The same obligation is reported again on the return path below, so stopping this
        // task here can never lose the report.
        let reporter = tokio::spawn({
            let processes = self.processes.clone();
            let archive = self.archive.clone();
            let thread_id = context.thread_id.clone();
            let call_id = context.call_id.clone();
            let tasks = context.tasks.clone();
            // The reporter needs its own handle: `task_id` is still borrowed by the running
            // `execution` future below, so it cannot be moved into this task.
            let report_task_id = task_id.clone();
            async move {
                let mut failures = failures;
                while let Some(failure) = failures.recv().await {
                    let Some(snapshot) =
                        processes.snapshot(&report_task_id, max_output_chars).await
                    else {
                        continue;
                    };
                    if let Some(fault) = capture_output_fault(
                        &failure,
                        archive.clone(),
                        processes.backend(),
                        &thread_id,
                        &call_id,
                        &snapshot,
                    ) {
                        report_output_storage_fault(tasks.as_ref(), &fault).await;
                    }
                }
            }
        });
        let snapshot = super::progress::drive(execution, previews, context.tasks.as_ref())
            .await
            .map_err(ToolError::new)?;
        reporter.abort();
        // Build the typed output fault the moment the capture failed and report it through the running
        // call's reliable channel *before* the archive and projection, so other model/tool admission is
        // blocked immediately instead of only when this call unwinds. A write or read failure keeps its
        // retriable obligation (re-save the accepted capture). 命中声明的单命令捕获上限不算可靠保存
        // 故障，因此这里不产出存储故障：已接纳字节留在捕获里走正常归档，工具结果给出 typed 的容量
        // 终止，准入照常继续。
        let capture_fault = snapshot.output_failure.clone().and_then(|failure| {
            capture_output_fault(
                &failure,
                self.archive.clone(),
                self.processes.backend(),
                &context.thread_id,
                &context.call_id,
                &snapshot,
            )
        });
        if let Some(fault) = &capture_fault {
            report_output_storage_fault(context.tasks.as_ref(), fault).await;
        }
        let retained = super::capture_retention::retain(
            &*self.processes.backend(),
            &*self.archive,
            &context.thread_id,
            &snapshot,
        )
        .await;
        let output = projection(&snapshot, retained.as_ref().ok())?;
        if let Err(error) = retained {
            // The archive itself could not store the capture: keep the retriable obligation on the
            // typed fault and report it through the running call's reliable channel as well, so the
            // pause is in force before this call returns.
            let error = attach_archive_obligation(
                error,
                self.archive.clone(),
                self.processes.backend(),
                &context.thread_id,
                &context.call_id,
                &snapshot,
            );
            if let Some(fault) = error
                .source
                .downcast_ref::<OutputStorageFault>()
                .map(|fault| Arc::new(fault.clone()))
            {
                report_output_storage_fault(context.tasks.as_ref(), &fault).await;
            }
            return Err(error.with_output(output));
        }
        match snapshot.state.final_result() {
            // A user cancellation wins over a capture failure: the process was stopped on purpose, so
            // the result stays cancelled even if a concurrent capture write also failed.
            Some(CommandProcessFinalResult::Cancelled) => {
                Err(ToolError::new(pl_core::thread::ThreadError::Cancelled).with_output(output))
            }
            // A capture failure outranks a healthy exit. The process may have exited before its last
            // capture write or flush failed, so checking the typed reason (not only `Failed`) keeps a
            // truncated capture from being reported as success.
            _ if capture_fault.is_some() => {
                // The command's durable capture could not continue. Report it through the typed
                // storage boundary core owns instead of as a plain tool error, so the Thread latches
                // the exact category and pauses further admission; the bytes already captured ride
                // along as the observed output.
                let fault = capture_fault.expect("checked to be present");
                Err(ToolError::new((*fault).clone()).with_output(output))
            }
            // 命中单命令落盘上限是一条预期终止：命令是按自己声明的上限被停下的，已写出的部分照常
            // 保留并归档，但它有自己的 typed 结果，不与 timeout、退出码失败或模型输出截断共用分类，
            // 也不走可靠保存故障的那条暂停/义务路径。
            Some(CommandProcessFinalResult::Failed { .. })
                if snapshot.output_limit_exceeded().is_some() =>
            {
                let limit = snapshot
                    .output_limit_exceeded()
                    .expect("checked to be present");
                Err(ToolError::new(ExecFailure::OutputLimitExceeded {
                    limit_bytes: limit.limit_bytes,
                    charged_bytes: limit.charged_bytes,
                    refused_bytes: limit.refused_bytes,
                })
                .with_output(output))
            }
            Some(CommandProcessFinalResult::Succeeded { .. }) => Ok(output),
            Some(
                CommandProcessFinalResult::Failed { .. } | CommandProcessFinalResult::TimedOut,
            )
            | None => {
                Err(ToolError::new(ExecFailure::Process(snapshot.message)).with_output(output))
            }
        }
    }
}

/// Builds the typed storage fault for one capture failure, with its retriable obligation when owed.
///
/// The category travels as a value, so core never parses the diagnostic text to classify it. A write or
/// read failure carries the obligation that re-materializes the exact accepted plan, so the Thread's
/// pause is only released once those bytes are really stored.
///
/// 命中所声明的单命令落盘上限是**预期容量终止**，不是可靠保存故障：命令是按自己的上限被有意停下
/// 的，已接纳字节仍在捕获里由正常归档路径保存，因此这里不产出 `OutputStorageFault`，也就不挂
/// `OutputRetryObligation`、不暂停准入、不会因为同一条上限反复重试而 repair 不止。容量终止由
/// [`CommandCaptureFailure::OutputLimitExceeded`] 与 [`ExecFailure::OutputLimitExceeded`] 表达。
fn capture_output_fault<A: CommandOutputArchive, B: CommandBackend>(
    failure: &CommandCaptureFailure,
    archive: Arc<A>,
    backend: Arc<B>,
    thread_id: &str,
    call_id: &str,
    snapshot: &CommandOutputSnapshot,
) -> Option<Arc<OutputStorageFault>> {
    let kind = match failure {
        CommandCaptureFailure::OutputLimitExceeded { .. } => return None,
        CommandCaptureFailure::Write { .. } | CommandCaptureFailure::Read { .. } => {
            StorageFaultKind::WriteFailed
        }
    };
    let source = ColdStoreError {
        source: Box::new(std::io::Error::other(failure.message())),
    };
    let fault = OutputStorageFault::new(kind, Arc::new(source));
    Some(Arc::new(fault.with_obligation(Arc::new(
        ArchiveRetentionObligation::new(
            archive,
            backend,
            thread_id,
            call_id,
            snapshot.clone(),
            kind,
        ),
    ))))
}

/// Attaches the archive's retriable obligation to an archive failure that named it.
///
/// Only a failure that already arrived as a typed [`OutputStorageFault`] is rebuilt with the
/// obligation; any other archive error (invalid media, integrity, a plain policy refusal) is returned
/// unchanged, because it is not a reliable-output storage obligation the owner could retry.
fn attach_archive_obligation<A: CommandOutputArchive, B: CommandBackend>(
    error: ToolError,
    archive: Arc<A>,
    backend: Arc<B>,
    thread_id: &str,
    call_id: &str,
    snapshot: &CommandOutputSnapshot,
) -> ToolError {
    let Some(fault) = error.source.downcast_ref::<OutputStorageFault>() else {
        return error;
    };
    let kind = fault.kind;
    let source = fault.source.clone();
    let obligation: Arc<dyn OutputRetryObligation> = Arc::new(ArchiveRetentionObligation::new(
        archive,
        backend,
        thread_id,
        call_id,
        snapshot.clone(),
        kind,
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

fn projection(
    snapshot: &CommandOutputSnapshot,
    resource: Option<&ResourceReference>,
) -> Result<ToolOutput, ToolError> {
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct Record<'a> {
        state: &'a crate::command::process_manager::CommandProcessLifecycle,
        process_id: &'a Option<String>,
        stdout: &'a pl_output::TruncatedOutput,
        stderr: &'a pl_output::TruncatedOutput,
        capture_file: &'a std::path::Path,
        output_file: &'a std::path::Path,
        output_artifacts: &'a [serde_json::Value],
        resource: Option<&'a ResourceReference>,
        output_revision: u64,
        message: &'a str,
    }
    #[derive(Serialize)]
    #[serde(rename_all = "camelCase")]
    struct Preview<'a> {
        state: &'a crate::command::process_manager::CommandProcessLifecycle,
        stdout: &'a str,
        stderr: &'a str,
        archived: bool,
    }
    let payload = serde_json::to_string(&Record {
        state: &snapshot.state,
        process_id: &snapshot.process_id,
        stdout: &snapshot.stdout,
        stderr: &snapshot.stderr,
        capture_file: &snapshot.capture_file,
        output_file: &snapshot.output_file,
        output_artifacts: &snapshot.output_artifacts,
        resource,
        output_revision: snapshot.output_revision,
        message: &snapshot.message,
    })
    .map_err(ToolError::new)?;
    let preview = serde_json::to_string(&Preview {
        state: &snapshot.state,
        stdout: &snapshot.stdout.content,
        stderr: &snapshot.stderr.content,
        archived: resource.is_some(),
    })
    .map_err(ToolError::new)?;
    let mut content = vec![ContextContent::Text {
        text: Arc::from(preview),
    }];
    if let Some(resource) = resource {
        content.push(ContextContent::Resource {
            reference: resource.clone(),
        });
    }
    Ok(ToolOutput::new(
        OpaquePayload::new("pl.tool.exec", 1, payload).map_err(ToolError::new)?,
        content,
    ))
}

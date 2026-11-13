//! SSH workspace tools over the ordinary authors, process manager and shared execution owner.
use super::acp_host_mcp::{HostBinding, bind};
use crate::{studio::thread_factory::PreparedAcpWorkspace, thread_assembler::AgentHost};
use anyhow::Result;
use futures::future::BoxFuture;
use pl_agent_tool::{InputFormat, ToolDefinition, typed::decode_json};
use pl_core::{
    context::{OpaquePayload, ResourceReader, ResourceReference},
    thread::{
        cold::{OutputRepair, OutputRetryOutcome, OutputStorageFault},
        task::TaskStatus,
    },
    tool::{
        ToolOutput,
        opaque::ToolError,
        task::{ExecutionIdentity, ExecutionSnapshot, ExecutionTasks},
    },
};
use pl_studio_mcp::HostResult;
use pl_tool::{
    collaboration::control::{AgentCallContext, ControlError},
    invocation::{CommandTask, CommandTaskAccess, WorkspaceInvocation},
};
use std::{
    collections::BTreeMap,
    sync::{Arc, Mutex, Weak},
    time::Duration,
};
use tokio_util::sync::CancellationToken;

type Operation = dyn Fn(OpaquePayload, WorkspaceInvocation) -> BoxFuture<'static, Result<ToolOutput, ToolError>>
    + Send
    + Sync;

struct Completion {
    status: TaskStatus,
    retention: tokio::sync::Mutex<Retention>,
    archive_error: Option<String>,
}
struct Retention {
    reference: Option<ResourceReference>,
    pending: Option<Arc<[u8]>>,
}

pub(super) struct WorkspaceTools {
    thread_id: String,
    pub(super) binding: PreparedAcpWorkspace,
    capabilities: pl_tool::workspace::ToolCapabilityConfig,
    permission_mode: crate::approval::PermissionMode,
    tasks: ExecutionTasks<Completion>,
    closed: CancellationToken,
    faults: Mutex<Vec<Arc<OutputStorageFault>>>,
    repairs: Mutex<Vec<OutputRepair>>,
}
impl std::fmt::Debug for WorkspaceTools {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AcpWorkspaceTools")
            .field("tasks", &self.tasks)
            .finish_non_exhaustive()
    }
}

#[derive(serde::Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub(super) struct PatchInput {
    pub patch: String,
}

impl WorkspaceTools {
    pub(super) fn new(
        thread_id: String,
        binding: PreparedAcpWorkspace,
        config: &crate::config::StudioConfig,
    ) -> Arc<Self> {
        Arc::new(Self {
            thread_id,
            binding,
            capabilities: config.runtime.tool_capabilities.clone(),
            permission_mode: config.runtime.permission_mode,
            tasks: ExecutionTasks::default(),
            closed: CancellationToken::new(),
            faults: Mutex::new(Vec::new()),
            repairs: Mutex::new(Vec::new()),
        })
    }

    pub(super) fn stop(&self) {
        self.tasks.stop_admission();
        self.closed.cancel();
        self.tasks.cancel_all();
    }

    /// Runs under the original AcpResources cleanup join; a failed retry keeps this same owner.
    pub(super) async fn close(&self) -> Result<()> {
        self.stop();
        self.tasks.join().await;
        let faults = self
            .faults
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        for fault in faults {
            if let Some(obligation) = &fault.obligation {
                match obligation.retry().await? {
                    OutputRetryOutcome::Stored => {}
                    OutputRetryOutcome::StoredWithRepair(repair) => {
                        self.repairs
                            .lock()
                            .unwrap_or_else(std::sync::PoisonError::into_inner)
                            .push(repair);
                    }
                    OutputRetryOutcome::Unsupported => {
                        anyhow::bail!("command output retention is still pending")
                    }
                }
                let identity = obligation.identity();
                self.faults
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .retain(|fault| {
                        fault
                            .obligation
                            .as_ref()
                            .is_none_or(|owed| owed.identity() != identity)
                    });
            }
        }
        for task in self.tasks.list() {
            let (_, lease) = self.tasks.get(&task.identity.task_id)?;
            if let Some(Ok(completion)) = lease.result() {
                let mut retention = completion.retention.lock().await;
                if let Some(bytes) = &retention.pending {
                    retention.reference = Some(
                        self.binding
                            .store
                            .retain_bytes(bytes.clone(), "application/json")
                            .await?,
                    );
                    retention.pending = None;
                }
            }
        }
        Ok(())
    }

    pub(super) fn bind(self: &Arc<Self>, tools: &mut BTreeMap<String, HostBinding>) -> Result<()> {
        use pl_tool::{
            exec::{CommandAccess, ThreadExecTool, ThreadWriteStdinTool},
            thread_catalog::ThreadBuiltin,
            workspace_file::*,
        };
        let execution = &self.binding.remote.execution;
        let workspace = &self.binding.workspace;
        let files = Arc::new(execution.files().with_workspace(workspace.clone()));
        if self.capabilities.exec {
            let processes = Arc::new(pl_tool::command::CommandProcessManager::new(Arc::new(
                self.binding.remote.commands(),
            )));
            let definition = ThreadBuiltin::Exec.declaration();
            let tool = Arc::new(ThreadExecTool::from_process_manager(
                processes.clone(),
                Arc::new(
                    self.binding
                        .store
                        .command_archive(files.clone(), self.binding.host_scratch.clone()),
                ),
                CommandAccess::WorkspaceOnly,
                definition.clone(),
            ));
            self.bind_operation(tools, mcp_description(&definition, "Execute a command on this member's frozen SSH workspace. After one second a running receipt may be returned; use anywork_wait and anywork_get_tool_task to observe its actual result. MCP cancellation ends observation, not accepted execution.")?, move |input, context| {
                let tool = tool.clone(); Box::pin(async move { tool.execute_workspace(input, context).await })
            })?;
            let definition = ThreadBuiltin::WriteStdin.declaration();
            let tool = Arc::new(ThreadWriteStdinTool::new(processes, definition.clone()));
            self.bind_operation(tools, mcp_description(&definition, "Write standard input to an exact taskId returned by this instance's exec_command. Accepted input is not proof of consumption; inspect the original receipt and never resend accepted bytes after cancellation.")?, move |input, context| {
                let tool = tool.clone(); Box::pin(async move { tool.execute_workspace(input, context).await })
            })?;
        }
        if self.capabilities.workspace_files {
            let definition = ThreadBuiltin::StatPath.declaration();
            let tool = Arc::new(ThreadStatPathTool::new(files.clone()));
            self.bind_operation(tools, definition, move |input, context| {
                let tool = tool.clone();
                Box::pin(async move {
                    tool.execute_workspace(
                        decode_json(input.content()).map_err(ToolError::new)?,
                        context,
                    )
                    .await
                })
            })?;
            let definition = ThreadBuiltin::WriteFile.declaration();
            let tool = Arc::new(ThreadWriteFileTool::new(files.clone(), workspace.clone()));
            self.bind_operation(tools, definition, move |input, context| {
                let tool = tool.clone();
                Box::pin(async move {
                    tool.execute_workspace(
                        decode_json(input.content()).map_err(ToolError::new)?,
                        context,
                    )
                    .await
                })
            })?;
            for &kind in WorkspaceFileToolKind::all() {
                let definition = kind.definition();
                let tool = Arc::new(ThreadWorkspaceFileTool::new(
                    kind,
                    files.clone(),
                    workspace.clone(),
                    definition.clone(),
                ));
                self.bind_operation(tools, definition, move |input, context| {
                    let tool = tool.clone();
                    Box::pin(async move { tool.execute_workspace(input, context).await })
                })?;
            }
            for &kind in WorkspaceMutationKind::all() {
                let definition = kind.definition();
                let tool = Arc::new(WorkspaceMutationTool::new(
                    kind,
                    definition.clone(),
                    files.clone(),
                    workspace.clone(),
                ));
                self.bind_operation(tools, definition, move |input, context| {
                    let tool = tool.clone();
                    Box::pin(async move { tool.execute_workspace(input, context).await })
                })?;
            }
        }
        if self.capabilities.git {
            let authorization = workspace.authorization();
            for &kind in pl_tool::git::GitToolKind::all() {
                let definition = kind.definition();
                let tool = Arc::new(pl_tool::git::GitTool::new(
                    kind,
                    pl_tool::git::GitWorkspaceConfig::local(workspace.root().to_owned())
                        .with_native_credentials(),
                    Arc::new(execution.git()),
                    Arc::new(pl_tool::git::NoGitCredentialProvider),
                    definition.clone(),
                ));
                let authorization = authorization.clone();
                self.bind_operation(tools, definition, move |input, context| {
                    let tool = tool.clone();
                    let authorization = authorization.clone();
                    Box::pin(async move {
                        if !authorization.is_active() {
                            return Err(ToolError::new(
                                pl_core::thread::ThreadError::ToolPermissionRevoked,
                            ));
                        }
                        tool.execute_workspace(input, context).await
                    })
                })?;
            }
        }
        for (definition, operation) in [
            (ThreadBuiltin::ListTasks.declaration(), "list"),
            (pl_tool::task_control::wait_definition(), "wait"),
            (pl_tool::task_control::query_definition(), "get"),
            (pl_tool::task_control::cancel_definition(), "cancel"),
        ] {
            let owner = self.clone();
            let definition = mcp_description(
                &definition,
                "Observe or control tasks accepted by this ACP instance. Results are not injected into another prompt: retain exact taskId receipts and read them with anywork_wait / anywork_get_tool_task. Cancellation acknowledgement does not prove process exit. No cross-instance recovery is provided.",
            )?;
            bind(tools, definition, move |host, value, context| {
                let owner = owner.clone();
                Box::pin(async move {
                    host.authorize_workspace_call(&context).await?;
                    let result = owner
                        .control(operation, value, context.cancellation)
                        .await
                        .map_err(|error| ControlError::Service(error.into_boxed_dyn_error()))?;
                    Ok((result, false))
                })
            })?;
        }
        Ok(())
    }

    fn bind_operation(
        self: &Arc<Self>,
        tools: &mut BTreeMap<String, HostBinding>,
        definition: ToolDefinition,
        operation: impl Fn(
            OpaquePayload,
            WorkspaceInvocation,
        ) -> BoxFuture<'static, Result<ToolOutput, ToolError>>
        + Send
        + Sync
        + 'static,
    ) -> Result<()> {
        let owner = self.clone();
        let name = definition.name().to_owned();
        let raw = !matches!(definition.input(), InputFormat::JsonSchema(_));
        let operation: Arc<Operation> = Arc::new(operation);
        bind(tools, definition, move |host, value, context| {
            let owner = owner.clone();
            let name = name.clone();
            let operation = operation.clone();
            Box::pin(async move {
                host.authorize_workspace_call(&context).await?;
                let input = if raw {
                    let input: PatchInput =
                        serde_json::from_value(value).map_err(ControlError::service)?;
                    OpaquePayload::text(input.patch)
                } else {
                    OpaquePayload::new("application/json", 1, value.to_string())
                        .map_err(ControlError::service)?
                };
                owner.invoke(host, context, name, input, operation).await
            })
        })
    }

    async fn invoke(
        self: Arc<Self>,
        host: Arc<AgentHost>,
        context: AgentCallContext,
        name: String,
        input: OpaquePayload,
        operation: Arc<Operation>,
    ) -> Result<(serde_json::Value, bool), ControlError> {
        let identity = ExecutionIdentity::new(context.call_id.clone(), name.clone());
        let task_id = identity.task_id.clone();
        let cancellation = self.closed.child_token();
        let observer = context.cancellation;
        if observer.is_cancelled() {
            return Err(ControlError::Closed);
        }
        let business_context = AgentCallContext {
            caller: context.caller,
            call_id: context.call_id.clone(),
            cancellation: cancellation.clone(),
        };
        let owner = self.clone();
        let invocation = WorkspaceInvocation {
            owner_id: self.thread_id.clone(),
            call_id: context.call_id,
            cancellation: cancellation.clone(),
            grant: Default::default(),
            tasks: Some(Arc::new(TaskPort {
                owner: Arc::downgrade(&self),
                current: task_id.clone(),
            })),
        };
        let lease = self
            .tasks
            .start(identity, cancellation, async move {
                let output = async {
                    host.authorize_workspace_call(&business_context)
                        .await
                        .map_err(ToolError::new)?;
                    let mut invocation = invocation;
                    invocation.grant = crate::thread_assembler::authorize_remote_workspace(
                        &name,
                        &input,
                        owner.permission_mode,
                        owner.binding.workspace.root(),
                    )
                    .await?;
                    operation(input, invocation).await
                }
                .await;
                if let Err(error) = &output
                    && let Some(fault) = error.source.downcast_ref::<OutputStorageFault>()
                {
                    owner.record_fault(Arc::new(fault.clone()));
                }
                let status = match &output {
                    Ok(_) => TaskStatus::Succeeded,
                    Err(error)
                        if matches!(
                            error.source.downcast_ref::<pl_core::thread::ThreadError>(),
                            Some(pl_core::thread::ThreadError::Cancelled)
                        ) =>
                    {
                        TaskStatus::Cancelled
                    }
                    Err(_) => TaskStatus::Failed,
                };
                let observed = match &output {
                    Ok(output) => Some(output),
                    Err(error) => error.observed_output(),
                };
                let value = observed.map(|output| {
                    serde_json::from_str(output.payload().content()).unwrap_or_else(|_| {
                        serde_json::Value::String(output.payload().content().into())
                    })
                });
                let mut reply = HostResult {
                    value: value.unwrap_or(serde_json::Value::Null),
                    is_error: output.is_err(),
                };
                if let Err(error) = output {
                    reply.value =
                        serde_json::json!({"error":error.to_string(),"output":reply.value});
                }
                // Encoding these fixed JSON values is infallible; no operation can be replayed here.
                let bytes: Arc<[u8]> = serde_json::to_vec(&reply).expect("JSON host result").into();
                let (stored, archive_error) = match owner
                    .binding
                    .store
                    .retain_bytes(bytes.clone(), "application/json")
                    .await
                {
                    Ok(reference) => (Some(reference), None),
                    Err(error) => (None, Some(error.to_string())),
                };
                let pending = stored.is_none().then_some(bytes);
                Completion {
                    status: if archive_error.is_some() {
                        TaskStatus::Failed
                    } else {
                        status
                    },
                    retention: tokio::sync::Mutex::new(Retention {
                        reference: stored,
                        pending,
                    }),
                    archive_error,
                }
            })
            .map_err(ControlError::service)?;
        tokio::select! {
            output = lease.wait() => {
                let output = output.map_err(ControlError::service)?;
                let bytes = self.result_bytes(&output, observer.clone()).await.map_err(|error| ControlError::Service(error.into_boxed_dyn_error()))?;
                let reply: HostResult = serde_json::from_slice(&bytes).map_err(ControlError::service)?;
                if let Some(error) = &output.archive_error {
                    return Ok((serde_json::json!({"taskId":task_id,"output":reply.value,"resultArchiveError":error}), true));
                }
                Ok((reply.value, reply.is_error))
            },
            _ = observer.cancelled() => Err(ControlError::Closed),
            _ = tokio::time::sleep(Duration::from_secs(1)) => Ok((serde_json::json!({"taskId":task_id,"status":"running","message":"Execution is owned by this instance; observe with anywork_wait and anywork_get_tool_task."}), false)),
        }
    }

    fn status(&self, task: &ExecutionSnapshot) -> TaskStatus {
        if !task.finished {
            return TaskStatus::Running;
        }
        match self
            .tasks
            .get(&task.identity.task_id)
            .ok()
            .and_then(|(_, lease)| lease.result())
        {
            None => TaskStatus::Running,
            Some(Ok(result)) => result.status,
            Some(Err(_)) => TaskStatus::Failed,
        }
    }
    fn view(&self, task: &ExecutionSnapshot) -> serde_json::Value {
        serde_json::json!({"taskId":task.identity.task_id,"toolId":task.identity.tool_id,"status":self.status(task),"cancelRequested":task.cancel_requested})
    }
    async fn control(
        &self,
        operation: &str,
        value: serde_json::Value,
        cancellation: CancellationToken,
    ) -> Result<serde_json::Value> {
        use pl_tool::task_control::{
            CancelTaskInput, ListTasksInput, QueryTaskInput, WaitTasksInput,
        };
        match operation {
            "list" => {
                let _: ListTasksInput = serde_json::from_value(value)?;
                Ok(serde_json::Value::Array(
                    self.tasks
                        .list()
                        .iter()
                        .map(|task| self.view(task))
                        .collect(),
                ))
            }
            "wait" => {
                let input: WaitTasksInput = serde_json::from_value(value)?;
                let timeout = input.timeout_ms.unwrap_or(60_000);
                anyhow::ensure!(
                    (1..=300_000).contains(&timeout),
                    "wait timeout must be between 1 and 300000 milliseconds"
                );
                let (tasks, timed_out) = self
                    .tasks
                    .wait(
                        &input.task_ids,
                        Duration::from_millis(timeout),
                        cancellation,
                    )
                    .await?;
                Ok(
                    serde_json::json!({"tasks":tasks.iter().map(|task| self.view(task)).collect::<Vec<_>>(),"timedOut":timed_out}),
                )
            }
            "cancel" => {
                let input: CancelTaskInput = serde_json::from_value(value)?;
                Ok(
                    serde_json::json!({"taskId":input.task_id,"cancellation":self.tasks.cancel(&input.task_id)?}),
                )
            }
            "get" => {
                let input: QueryTaskInput = serde_json::from_value(value)?;
                let (mut task, lease) = self.tasks.get(&input.task_id)?;
                let result = lease.result();
                task.finished = result.is_some();
                let mut value = serde_json::json!({"task":self.view(&task)});
                if let Some(start) = input.result_cursor
                    && let Some(result) = result
                {
                    let result = result?;
                    let bytes = self.result_bytes(&result, cancellation).await?;
                    let text = std::str::from_utf8(&bytes)?;
                    anyhow::ensure!(
                        start <= text.len() && text.is_char_boundary(start),
                        "invalid UTF-8 result cursor"
                    );
                    let mut end = start.saturating_add(8192).min(text.len());
                    while !text.is_char_boundary(end) {
                        end -= 1;
                    }
                    value["result"] = serde_json::json!({"format":"pl.host.tool-result","version":1,"content":&text[start..end],"totalBytes":text.len(),"nextCursor":(end<text.len()).then_some(end)});
                    if let Some(error) = &result.archive_error {
                        value["archiveError"] = error.clone().into();
                    }
                }
                let repairs = self
                    .repairs
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .iter()
                    .filter(|repair| repair.call_id == task.identity.call_id)
                    .cloned()
                    .collect::<Vec<_>>();
                if !repairs.is_empty() {
                    value["outputRepairs"] = serde_json::to_value(repairs)?;
                }
                Ok(value)
            }
            _ => anyhow::bail!("unknown task control binding"),
        }
    }
    async fn result_bytes(
        &self,
        completion: &Completion,
        cancellation: CancellationToken,
    ) -> Result<Arc<[u8]>> {
        let retention = completion.retention.lock().await;
        match &retention.reference {
            Some(reference) => Ok(self
                .binding
                .store
                .read(reference.clone(), cancellation)
                .await?),
            None => retention
                .pending
                .clone()
                .ok_or_else(|| anyhow::anyhow!("original task result is unavailable")),
        }
    }
    fn record_fault(&self, fault: Arc<OutputStorageFault>) {
        if let Some(obligation) = &fault.obligation {
            let mut faults = self
                .faults
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if !faults.iter().any(|known| {
                known
                    .obligation
                    .as_ref()
                    .is_some_and(|known| known.identity() == obligation.identity())
            }) {
                faults.push(fault);
            }
        }
    }
}

fn mcp_description(definition: &ToolDefinition, description: &str) -> Result<ToolDefinition> {
    let InputFormat::JsonSchema(input) = definition.input() else {
        anyhow::bail!("JSON input required")
    };
    Ok(ToolDefinition::json(
        definition.name(),
        description,
        input.clone(),
    )?)
}

#[derive(Debug)]
struct TaskPort {
    owner: Weak<WorkspaceTools>,
    current: String,
}
impl CommandTaskAccess for TaskPort {
    fn current_receipt(&self) -> Option<String> {
        self.owner
            .upgrade()?
            .tasks
            .get(&self.current)
            .ok()
            .map(|_| self.current.clone())
    }
    fn get(&self, receipt: &str) -> Result<CommandTask, ToolError> {
        let owner = self
            .owner
            .upgrade()
            .ok_or_else(|| ToolError::new(pl_core::thread::ThreadError::Closed))?;
        let (task, _) = owner.tasks.get(receipt).map_err(ToolError::new)?;
        Ok(CommandTask {
            task_id: task.identity.task_id.clone(),
            call_id: task.identity.call_id.clone(),
            tool_id: task.identity.tool_id.clone(),
            status: owner.status(&task),
            cancel_requested: task.cancel_requested,
        })
    }
    fn report_output(
        &self,
        _: pl_core::model::ToolProgressUpdate,
    ) -> BoxFuture<'_, Result<(), ToolError>> {
        // MCP observes the original task result/capture, not a second Native live-preview stream.
        Box::pin(async { Ok(()) })
    }
    fn report_storage_fault(
        &self,
        fault: Arc<OutputStorageFault>,
    ) -> BoxFuture<'_, Result<(), ToolError>> {
        Box::pin(async move {
            let owner = self
                .owner
                .upgrade()
                .ok_or_else(|| ToolError::new(pl_core::thread::ThreadError::Closed))?;
            owner.record_fault(fault);
            Ok(())
        })
    }
}

//! Workspace and skill tools over ordinary authors and the original ACP execution owner.
use super::acp_host_mcp::{HostBinding, HostHandle, attach_binding, prepare_binding};
use crate::studio::thread_factory::PreparedAcpWorkspace;
use crate::tool_json::{JsonToolInput, json_output};
use anyhow::Result;
use futures::future::BoxFuture;
use pl_agent_tool::{Tool, ToolDefinition};
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

use crate::thread_assembler::host_workspace_tools::{
    HostJsonInput, HostToolDomain as OperationDomain, HostToolMetadata, HostWorkspaceSink,
};

#[derive(Clone)]
struct InvocationPolicy {
    domain: OperationDomain,
    authorization: Option<pl_core::tool::opaque::ToolAuthorization>,
}

#[derive(Debug, thiserror::Error)]
#[error("tool permission denied: {0}")]
struct WorkspacePermissionDenied(&'static str);

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
        let lsp_closed = match &self.binding.lsp {
            Some(lsp) => lsp.lease.close().await,
            None => Ok(()),
        };
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
        lsp_closed?;
        Ok(())
    }

    pub(super) async fn bind(
        self: &Arc<Self>,
        tools: &mut BTreeMap<String, HostBinding>,
    ) -> Result<()> {
        use crate::thread_assembler::{
            StudioCommandBinding, StudioGitBinding, host_workspace_tools as family,
        };
        use pl_tool::exec::CommandAccess;
        let workspace = &self.binding.workspace;
        let mut sink = McpWorkspaceSink {
            owner: self.clone(),
            tools,
        };
        let access = if self.binding.remote.is_none()
            && workspace.workspace().boundary().allows_host_paths()
        {
            CommandAccess::HostApproval
        } else {
            CommandAccess::WorkspaceOnly
        };
        family::workspace(
            &mut sink,
            StudioCommandBinding {
                commands: self
                    .binding
                    .execution
                    .commands(self.binding.environment.clone()),
                workspace: workspace.clone(),
                access,
            },
            &self.binding.store,
            self.binding.host_scratch.clone(),
            &self.capabilities,
            None,
        )?;
        family::git(
            &mut sink,
            self.capabilities.git,
            StudioGitBinding {
                config: pl_tool::git::GitWorkspaceConfig::local(workspace.root().to_owned())
                    .with_native_credentials(),
                backend: Arc::new(self.binding.execution.git()),
                credentials: Arc::new(pl_tool::git::NoGitCredentialProvider),
                kinds: pl_tool::git::GitToolKind::all().to_vec(),
                authorization: workspace.authorization(),
            },
        )?;
        if let Some((catalog, sources)) = &self.binding.skills {
            family::skills(&mut sink, self.capabilities.skills, sources.clone())?;
            family::local_skill_management(
                &mut sink,
                self.capabilities.skills,
                self.binding.remote.is_none(),
                catalog.clone(),
                workspace.clone(),
            )?;
        }
        if let Some(lsp) = &self.binding.lsp {
            family::lsp(
                &mut sink,
                self.capabilities.lsp,
                lsp.registry.clone(),
                lsp.paths.clone(),
                family::LspReadiness::IncludePending,
            )
            .await?;
        }
        self.bind_task_tools(sink.tools)?;
        Ok(())
    }

    fn bind_task_tools(self: &Arc<Self>, tools: &mut BTreeMap<String, HostBinding>) -> Result<()> {
        let mut sink = McpTaskTools { owner: self, tools };
        crate::thread_assembler::host_task_tools::list(&mut sink)?;
        crate::thread_assembler::host_task_tools::controls(&mut sink)?;
        Ok(())
    }

    async fn authorize(
        &self,
        name: &str,
        input: &OpaquePayload,
        domain: OperationDomain,
    ) -> Result<pl_core::tool::execution_policy::ExecutionGrant, ToolError> {
        use pl_core::tool::execution_policy::ExecutionGrant;
        if matches!(domain, OperationDomain::Skill) {
            // Skill sources and LocalSkillFiles enforce their own frozen domain boundaries.
            return Ok(ExecutionGrant::default());
        }
        if self.binding.remote.is_some() {
            return crate::thread_assembler::authorize_remote_workspace(
                name,
                input,
                self.permission_mode,
                self.binding.workspace.root(),
            )
            .await;
        }
        let exec = if name == pl_tool::exec::TOOL_EXEC {
            Some(
                pl_tool::exec::parse_and_validate_exec_input(input.content())
                    .map_err(pl_tool::exec::ExecInputError::into_tool_error)?,
            )
        } else {
            if name == pl_tool::exec::TOOL_WRITE_STDIN {
                pl_tool::exec::parse_and_validate_stdin_input(input.content())
                    .map_err(pl_tool::exec::ExecInputError::into_tool_error)?;
            }
            None
        };
        let may_escape = self
            .binding
            .workspace
            .workspace()
            .boundary()
            .allows_host_paths();
        if self.permission_mode == crate::approval::PermissionMode::FullAccess {
            return Ok(if may_escape {
                ExecutionGrant::default().with_capability(pl_tool::approval::HOST_WORKSPACE_ACCESS)
            } else {
                ExecutionGrant::default()
            });
        }
        let root = self.binding.workspace.root().to_owned();
        let tool_name = name.to_owned();
        let raw = input.content().to_owned();
        let assessment = tokio::task::spawn_blocking(move || match exec {
            Some(input) => pl_tool::approval::assess_exec(&input, &root),
            None => pl_tool::approval::assess(&tool_name, &raw, &root),
        })
        .await
        .map_err(ToolError::new)?;
        if !assessment.requested_access.allows_external() {
            return Ok(ExecutionGrant::default());
        }
        let error = WorkspacePermissionDenied(if may_escape {
            "ACP has no Native approval/review owner for external workspace access"
        } else {
            "the assigned workspace is confined"
        });
        Err(if name == pl_tool::exec::TOOL_EXEC {
            pl_tool::exec::permission_denied(error)
        } else {
            ToolError::new(error)
        })
    }

    async fn invoke(
        self: Arc<Self>,
        context: AgentCallContext,
        name: String,
        input: OpaquePayload,
        policy: InvocationPolicy,
        operation: Arc<HostHandle<WorkspaceInvocation>>,
    ) -> Result<(serde_json::Value, bool), ControlError> {
        let identity = ExecutionIdentity::new(context.call_id.clone(), name.clone());
        let task_id = identity.task_id.clone();
        let cancellation = self.closed.child_token();
        let observer = context.cancellation;
        if observer.is_cancelled() {
            return Err(ControlError::Closed);
        }
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
                    let mut invocation = invocation;
                    if policy
                        .authorization
                        .as_ref()
                        .is_some_and(|authorization| !authorization.is_active())
                    {
                        return Err(ToolError::new(
                            pl_core::thread::ThreadError::ToolPermissionRevoked,
                        ));
                    }
                    invocation.grant = owner.authorize(&name, &input, policy.domain).await?;
                    operation
                        .execute(input, invocation)
                        .await
                        .and_then(super::acp_host_mcp::data_output)
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
                let reply = super::acp_host_mcp::host_result(output);
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

struct McpWorkspaceSink<'a> {
    owner: Arc<WorkspaceTools>,
    tools: &'a mut BTreeMap<String, HostBinding>,
}

impl HostWorkspaceSink for McpWorkspaceSink<'_> {
    type Prepared = (pl_studio_mcp::ToolProjection, String, InvocationPolicy);
    type Error = anyhow::Error;

    fn prepare(
        &mut self,
        definition: &ToolDefinition,
        metadata: HostToolMetadata,
    ) -> Result<Self::Prepared> {
        let input = match metadata.json_input {
            HostJsonInput::Object => pl_studio_mcp::JsonInput::Object,
            HostJsonInput::Value => pl_studio_mcp::JsonInput::Value,
        };
        Ok((
            prepare_binding(self.tools, definition, input)?,
            definition.name().to_owned(),
            InvocationPolicy {
                domain: metadata.domain,
                authorization: metadata.authorization,
            },
        ))
    }

    fn attach<T>(&mut self, (projection, name, policy): Self::Prepared, author: T)
    where
        T: Tool<
                Input = OpaquePayload,
                Context = WorkspaceInvocation,
                Output = ToolOutput,
                Error = ToolError,
            >,
    {
        let owner = self.owner.clone();
        attach_binding(
            self.tools,
            projection,
            author,
            move |handle, host, input, context| {
                let owner = owner.clone();
                let name = name.clone();
                let policy = policy.clone();
                Box::pin(async move {
                    host.authorize_workspace_call(&context).await?;
                    owner.invoke(context, name, input, policy, handle).await
                })
            },
        );
    }
}

struct McpTaskTools<'a> {
    owner: &'a Arc<WorkspaceTools>,
    tools: &'a mut BTreeMap<String, HostBinding>,
}

impl McpTaskTools<'_> {
    fn add(&mut self, definition: ToolDefinition, operation: &'static str) -> Result<()> {
        let projection =
            prepare_binding(self.tools, &definition, pl_studio_mcp::JsonInput::Object)?;
        let author = WorkspaceTaskTool {
            definition,
            owner: Arc::downgrade(self.owner),
            operation,
        };
        super::acp_host_mcp::attach_direct(self.tools, projection, author);
        Ok(())
    }
}

impl crate::thread_assembler::host_task_tools::HostTaskSink for McpTaskTools<'_> {
    type Error = anyhow::Error;
    fn list(
        &mut self,
        prepared: pl_tool::binding::PreparedNativeTool<pl_tool::task_control::ListTasksTool>,
    ) -> Result<()> {
        self.add(prepared.definition().clone(), "list")
    }
    fn control(
        &mut self,
        definition: ToolDefinition,
        kind: pl_tool::task_control::TaskControlKind,
    ) -> Result<()> {
        let operation = match kind {
            pl_tool::task_control::TaskControlKind::Wait => "wait",
            pl_tool::task_control::TaskControlKind::Query => "get",
            pl_tool::task_control::TaskControlKind::Cancel => "cancel",
        };
        self.add(definition, operation)
    }
}

struct WorkspaceTaskTool {
    definition: ToolDefinition,
    owner: Weak<WorkspaceTools>,
    operation: &'static str,
}

impl Tool for WorkspaceTaskTool {
    type Input = OpaquePayload;
    type Context = AgentCallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: AgentCallContext,
    ) -> Result<ToolOutput, ToolError> {
        let input = JsonToolInput::new(&input)?;
        let owner = self
            .owner
            .upgrade()
            .ok_or_else(|| ToolError::new(pl_core::thread::ThreadError::Closed))?;
        let value = owner
            .control(self.operation, input.decode()?, context.cancellation)
            .await
            .map_err(|error| ToolError::new(ControlError::Service(error.into_boxed_dyn_error())))?;
        json_output("pl.host.tool-task", &value)
    }
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

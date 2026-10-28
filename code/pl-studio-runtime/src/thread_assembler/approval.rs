//! Studio permission modes and review policy over core's typed invocation grants.
use super::StudioThreadTools;
use crate::approval::{
    PermissionMode, ToolApprovalDecision, ToolApprovalRequest, ToolReviewCallback,
    ToolReviewRequest,
};
use pl_core::{
    context::OpaquePayload,
    tool::{
        execution_policy::{ExecutionGrant, ExecutionPolicy, ExecutionPolicyHandle},
        opaque::{CallContext, ToolError},
    },
};
use pl_tool::workspace::ToolWorkspace;
use std::sync::Arc;

#[derive(Debug, Clone, Copy)]
pub(crate) enum ApprovalHost {
    Local,
    Remote,
}

pub(crate) struct StudioApprovalOptions {
    pub mode: PermissionMode,
    pub host: ApprovalHost,
    pub workspace: ToolWorkspace,
    pub reviewer: Option<ToolReviewCallback>,
}
impl std::fmt::Debug for StudioApprovalOptions {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("StudioApprovalOptions")
            .field("mode", &self.mode)
            .field("host", &self.host)
            .field("workspace", &self.workspace)
            .field("reviewer", &self.reviewer.is_some())
            .finish()
    }
}

#[derive(Debug)]
struct StudioExecutionPolicy {
    tool_id: String,
    options: Arc<StudioApprovalOptions>,
}

#[derive(Debug, thiserror::Error)]
#[error("tool permission denied: {0}")]
struct PermissionDenied(String);

#[derive(serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct ApprovalPrompt {
    pub name: String,
    pub arguments: OpaquePayload,
    pub working_directory: Option<String>,
}

impl StudioExecutionPolicy {
    fn denied(&self, reason: impl Into<String>) -> ToolError {
        let error = PermissionDenied(reason.into());
        if self.tool_id == pl_tool::exec::TOOL_EXEC {
            pl_tool::exec::permission_denied(error)
        } else {
            ToolError::new(error)
        }
    }
}

impl ExecutionPolicy for StudioExecutionPolicy {
    async fn authorize(
        &self,
        input: &OpaquePayload,
        context: &CallContext,
    ) -> Result<ExecutionGrant, ToolError> {
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        let exec = if self.tool_id == pl_tool::exec::TOOL_EXEC {
            Some(
                pl_tool::exec::parse_and_validate_exec_input(input.content())
                    .map_err(pl_tool::exec::ExecInputError::into_tool_error)?,
            )
        } else {
            if self.tool_id == pl_tool::exec::TOOL_WRITE_STDIN {
                pl_tool::exec::parse_and_validate_stdin_input(input.content())
                    .map_err(pl_tool::exec::ExecInputError::into_tool_error)?;
            }
            None
        };
        let may_escape = matches!(self.options.host, ApprovalHost::Local)
            && self
                .options
                .workspace
                .workspace()
                .boundary()
                .allows_host_paths();
        let external_grant =
            || ExecutionGrant::default().with_capability(pl_tool::approval::HOST_WORKSPACE_ACCESS);
        if self.options.mode == PermissionMode::FullAccess {
            return Ok(if may_escape {
                external_grant()
            } else {
                ExecutionGrant::default()
            });
        }
        let name = self.tool_id.clone();
        let raw = input.content().to_owned();
        let root = self.options.workspace.root().to_owned();
        let host = self.options.host;
        let assessment = tokio::task::spawn_blocking(move || match (host, exec) {
            (ApprovalHost::Local, Some(input)) => pl_tool::approval::assess_exec(&input, &root),
            (ApprovalHost::Remote, Some(input)) => {
                pl_tool::approval::assess_exec_remote(&input, &root)
            }
            (ApprovalHost::Local, None) => pl_tool::approval::assess(&name, &raw, &root),
            (ApprovalHost::Remote, None) => pl_tool::approval::assess_remote(&name, &raw, &root),
        })
        .await
        .map_err(ToolError::new)?;
        if !assessment.requested_access.allows_external() {
            return Ok(ExecutionGrant::default());
        }
        if !may_escape {
            return Err(self.denied("the assigned workspace is confined"));
        }
        match self.options.mode {
            PermissionMode::FullAccess => Ok(external_grant()),
            PermissionMode::RequestApproval => {
                let prompt = ApprovalPrompt {
                    name: self.tool_id.clone(),
                    arguments: input.clone(),
                    working_directory: assessment.working_directory.clone(),
                };
                let payload = OpaquePayload::new(
                    "pl.studio.tool-approval",
                    1,
                    serde_json::to_string(&prompt).map_err(ToolError::new)?,
                )
                .map_err(ToolError::new)?;
                let access = context.tasks.as_ref().ok_or_else(|| {
                    ToolError::new(pl_core::thread::ThreadError::TaskAccessDenied)
                })?;
                match access
                    .request_execution_permission(payload, context.cancellation.clone())
                    .await
                    .map_err(ToolError::new)?
                {
                    pl_core::thread::permissions::PermissionDecision::Allow => Ok(external_grant()),
                    pl_core::thread::permissions::PermissionDecision::Deny => {
                        Err(self.denied("denied by user"))
                    }
                }
            }
            PermissionMode::AutoReview => {
                let reviewer = self
                    .options
                    .reviewer
                    .as_ref()
                    .ok_or_else(|| self.denied("automatic reviewer is not configured"))?;
                let decision = reviewer(ToolReviewRequest {
                    thread_id: context.thread_id.clone(),
                    turn_id: context.turn_id.clone(),
                    task: context.tasks.clone().ok_or_else(|| {
                        ToolError::new(pl_core::thread::ThreadError::TaskAccessDenied)
                    })?,
                    tool: ToolApprovalRequest {
                        id: context.call_id.clone(),
                        name: self.tool_id.clone(),
                        arguments: serde_json::Value::String(input.content().to_owned()),
                        working_directory: assessment.working_directory,
                        parent_agent_id: Some(context.thread_id.clone()),
                    },
                    permission_mode: self.options.mode,
                    workspace_access: assessment.requested_access,
                    workspace_root: self.options.workspace.root().to_owned(),
                    cancellation_token: Some(context.cancellation.clone()),
                })
                .await;
                match decision {
                    ToolApprovalDecision::Approved => Ok(external_grant()),
                    ToolApprovalDecision::Denied { reason } => Err(self.denied(reason)),
                }
            }
        }
    }
}

impl StudioThreadTools {
    pub(crate) fn with_approval(
        mut self,
        options: StudioApprovalOptions,
        previous: &std::collections::BTreeMap<String, ExecutionPolicyHandle>,
    ) -> Self {
        let options = Arc::new(options);
        self.registrations = self
            .registrations
            .into_iter()
            .map(|tool| {
                let policy = StudioExecutionPolicy {
                    tool_id: tool.tool_id().to_owned(),
                    options: options.clone(),
                };
                let handle = previous
                    .get(tool.tool_id())
                    .cloned()
                    .unwrap_or_else(|| ExecutionPolicyHandle::new(policy));
                self.approval_policies
                    .insert(tool.tool_id().to_owned(), handle.clone());
                tool.with_execution_policy(handle)
            })
            .collect();
        self
    }
}

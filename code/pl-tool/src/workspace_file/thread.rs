//! Opaque Thread tools over the existing workspace file and patch implementations.
use super::ops::execute_workspace_patch_tool;
use super::*;
use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{ToolOutput, opaque::ToolError},
};

/// One workspace operation; backend policy and resource leases are supplied by the host.
#[derive(Debug)]
pub struct ThreadWorkspaceFileTool<B: WorkspaceFileBackend> {
    definition: pl_agent_tool::ToolDefinition,
    kind: WorkspaceFileToolKind,
    backend: Arc<B>,
    workspace: ToolWorkspace,
}

impl<B: WorkspaceFileBackend + 'static> ThreadWorkspaceFileTool<B> {
    /// Creates a fresh operation instance over the host-selected backend lease.
    pub fn new(
        kind: WorkspaceFileToolKind,
        backend: Arc<B>,
        workspace: ToolWorkspace,
        definition: pl_agent_tool::ToolDefinition,
    ) -> Self {
        Self {
            definition,
            kind,
            backend,
            workspace,
        }
    }
}

impl<B: WorkspaceFileBackend + 'static> pl_agent_tool::Tool for ThreadWorkspaceFileTool<B> {
    type Input = pl_core::context::OpaquePayload;
    type Context = crate::invocation::WorkspaceInvocation;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: crate::invocation::WorkspaceInvocation,
    ) -> std::result::Result<ToolOutput, ToolError> {
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        if input.format() != "text/plain" {
            return Err(ToolError::new(tool_error(
                self.kind.name(),
                "apply_patch only accepts raw patch text",
            )));
        }
        self.workspace
            .ensure_workspace_writable()
            .map_err(ToolError::new)?;
        let _write_guard = self.workspace.write_lock().await;
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        let granted = self.backend.for_grant(&context.grant);
        let backend = granted.as_ref().unwrap_or(self.backend.as_ref());
        let result = execute_workspace_patch_tool(backend, input.content())
            .await
            .map_err(ToolError::new)?;
        let failure = result.failure;
        // Projection was produced at execution time. Historical readers never rerun it.
        let output = ToolOutput::from_data(
            result.data,
            vec![ContextContent::Text {
                text: Arc::from(result.model_output),
            }],
        );
        match failure {
            None => Ok(output),
            Some(failure) => Err(ToolError::new(failure).with_output(output)),
        }
    }
}

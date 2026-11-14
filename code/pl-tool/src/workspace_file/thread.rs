//! Opaque Thread tools over the existing workspace file and patch implementations.
use super::ops::execute_workspace_patch_tool;
use super::*;
use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, ToolError},
    },
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

    /// Transfers this tool with deterministic host-encoded declaration material.
    ///
    /// The supplied preparation has already validated the registration identity.
    pub fn registration(
        self,
        prepared: pl_core::tool::opaque::PreparedRegistration,
    ) -> Registration {
        let authorization = self.workspace.authorization();
        let registration = prepared
            .attach(pl_agent_tool::ToolHandle::new(self))
            .with_presentation_contract(pl_core::model::ToolPresentationContract::new(
                "builtin.apply_patch@1",
            ))
            .with_authorization(authorization);
        registration.foreground_coexisting()
    }
}

impl<B: WorkspaceFileBackend + 'static> pl_agent_tool::Tool for ThreadWorkspaceFileTool<B> {
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
    ) -> std::result::Result<ToolOutput, ToolError> {
        self.execute_workspace(input, context.into()).await
    }
}

impl<B: WorkspaceFileBackend + 'static> ThreadWorkspaceFileTool<B> {
    pub async fn execute_workspace(
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
        let output = ToolOutput::new(
            OpaquePayload::new("pl.tool.workspace-file", 1, result.output)
                .map_err(ToolError::new)?,
            vec![ContextContent::Text {
                text: Arc::from(result.model_output),
            }],
        );
        if result.success {
            Ok(output)
        } else {
            Err(ToolError::new(tool_error(
                self.kind.name(),
                failure
                    .map(|failure| failure.diagnostic)
                    .unwrap_or_else(|| "workspace operation failed".into()),
            ))
            .with_output(output))
        }
    }
}

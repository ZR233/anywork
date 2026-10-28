//! Opaque Thread tools over the existing workspace file and patch implementations.
use super::ops::execute_workspace_patch_tool;
use super::*;
use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, RegistryError, Tool, ToolError},
    },
};

/// One workspace operation; backend policy and resource leases are supplied by the host.
#[derive(Debug)]
pub struct ThreadWorkspaceFileTool<B: WorkspaceFileBackend> {
    kind: WorkspaceFileToolKind,
    backend: Arc<B>,
    workspace: ToolWorkspace,
}

impl<B: WorkspaceFileBackend + 'static> ThreadWorkspaceFileTool<B> {
    /// Creates a fresh operation instance over the host-selected backend lease.
    pub fn new(kind: WorkspaceFileToolKind, backend: Arc<B>, workspace: ToolWorkspace) -> Self {
        Self {
            kind,
            backend,
            workspace,
        }
    }

    /// Transfers this tool with deterministic host-encoded declaration material.
    ///
    /// # Errors
    /// Returns invalid registration identity.
    pub fn registration(
        self,
        declaration: OpaquePayload,
    ) -> std::result::Result<Registration, RegistryError> {
        let authorization = self.workspace.authorization();
        let registration = Registration::new(self.kind.name().into(), declaration, self)?
            .with_authorization(authorization);
        Ok(registration.foreground_coexisting())
    }
}

impl<B: WorkspaceFileBackend + 'static> Tool for ThreadWorkspaceFileTool<B> {
    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
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
            Err(
                ToolError::new(tool_error(self.kind.name(), "workspace operation failed"))
                    .with_output(output),
            )
        }
    }
}

//! One dynamic write-file contract across local and worker-backed workspaces.
use super::{
    WorkspaceFileBackend,
    independent::{FileCapability, granted_backend},
};
use crate::{file::WriteFileInput, workspace::ToolWorkspace};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError},
    },
};
use std::sync::Arc;

/// Thread-owned write operation; physical path validation and file mutation belong to its backend.
#[derive(Debug)]
pub struct ThreadWriteFileTool<B> {
    backend: Arc<B>,
    workspace: ToolWorkspace,
}

impl<B: WorkspaceFileBackend + 'static> ThreadWriteFileTool<B> {
    /// Binds a backend to its matching immutable workspace policy and write lease.
    /// The backend must enforce that policy, as the local confined and workspace-policy backends do.
    pub fn new(backend: Arc<B>, workspace: ToolWorkspace) -> Self {
        Self { backend, workspace }
    }
}

impl<B: WorkspaceFileBackend + 'static> pl_agent_tool::typed::TypedTool for ThreadWriteFileTool<B> {
    const NAME: &'static str = <pl_tool_write_file::WriteFileTool<FileCapability<B>> as pl_agent_tool::typed::TypedTool>::NAME;
    const DESCRIPTION: &'static str = <pl_tool_write_file::WriteFileTool<FileCapability<B>> as pl_agent_tool::typed::TypedTool>::DESCRIPTION;
    type Args = WriteFileInput;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    async fn execute(
        &self,
        input: Self::Args,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        self.workspace
            .ensure_workspace_writable()
            .map_err(ToolError::new)?;
        let _lease = tokio::select! {
            biased;
            _ = context.cancellation.cancelled() => return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled)),
            lease = self.workspace.write_lock() => lease,
        };
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        let backend = granted_backend(&self.backend, &context.grant);
        let receipt = pl_tool_write_file::WriteFileTool::new()
            .execute(input, FileCapability(backend))
            .await
            .map_err(ToolError::new)?;
        let payload = OpaquePayload::new(
            "pl.tool.file-write",
            1,
            serde_json::to_string(&receipt).map_err(ToolError::new)?,
        )
        .map_err(ToolError::new)?;
        Ok(ToolOutput::new(
            payload,
            vec![ContextContent::Text {
                text: Arc::from(format!(
                    "Wrote {} bytes to {}",
                    receipt.bytes_written, receipt.path
                )),
            }],
        ))
    }
}

pub fn thread_write_file_tool_definition() -> pl_agent_tool::ToolDefinition {
    pl_tool_write_file::definition::<FileCapability<super::LocalWorkspaceFileBackend>>()
}

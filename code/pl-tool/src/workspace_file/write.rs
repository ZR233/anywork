//! One dynamic write-file contract across local and worker-backed workspaces.
use super::{WorkspaceFileBackend, WorkspaceFileWriteRequest};
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

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct Receipt {
    path: String,
    mode: crate::workspace::WriteMode,
    bytes_written: usize,
}

impl<B: WorkspaceFileBackend + 'static> pl_agent_tool::typed::TypedTool for ThreadWriteFileTool<B> {
    const NAME: &'static str = THREAD_WRITE_FILE_TOOL_NAME;
    const DESCRIPTION: &'static str = THREAD_WRITE_FILE_TOOL_DESCRIPTION;
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
        let granted = self.backend.for_grant(&context.grant);
        let backend = granted.as_ref().unwrap_or(self.backend.as_ref());
        let receipt = Receipt {
            path: input.path.clone(),
            mode: input.mode,
            bytes_written: input.content.len(),
        };
        backend
            .write_text(WorkspaceFileWriteRequest {
                mode: input.mode,
                path: input.path,
                cwd: None,
                content: input.content,
            })
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
    pl_agent_tool::ToolDefinition::json(
        THREAD_WRITE_FILE_TOOL_NAME,
        THREAD_WRITE_FILE_TOOL_DESCRIPTION,
        pl_agent_tool::typed::input_schema_for::<WriteFileInput>(),
    )
    .expect("static tool definition")
}

const THREAD_WRITE_FILE_TOOL_NAME: &str = "write_file";
const THREAD_WRITE_FILE_TOOL_DESCRIPTION: &str =
    "Write exact UTF-8 text to a workspace file using create, overwrite, or append mode.";

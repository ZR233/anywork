//! Path metadata projection shared by local and remote Thread tools.
use super::{
    WorkspaceFileBackend,
    independent::{FileCapability, granted_backend},
};
use pl_core::tool::{ToolOutput, opaque::ToolError};
use std::sync::Arc;

/// A Thread-owned metadata reader with frozen backend access authority.
#[derive(Debug)]
pub struct ThreadStatPathTool<B> {
    backend: Arc<B>,
}

impl<B: WorkspaceFileBackend + 'static> ThreadStatPathTool<B> {
    /// Binds the operation to the host-selected workspace lease.
    pub fn new(backend: Arc<B>) -> Self {
        Self { backend }
    }
}

impl<B: WorkspaceFileBackend + 'static> pl_agent_tool::typed::TypedTool for ThreadStatPathTool<B> {
    const NAME: &'static str = <pl_tool_filesystem::stat_path::StatPathTool<FileCapability<B>> as pl_agent_tool::typed::TypedTool>::NAME;
    const DESCRIPTION: &'static str = <pl_tool_filesystem::stat_path::StatPathTool<
        FileCapability<B>,
    > as pl_agent_tool::typed::TypedTool>::DESCRIPTION;
    type Args = crate::file::PathInput;
    type Context = crate::invocation::WorkspaceInvocation;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    async fn execute(
        &self,
        input: Self::Args,
        context: crate::invocation::WorkspaceInvocation,
    ) -> Result<ToolOutput, ToolError> {
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }

        let backend = granted_backend(&self.backend, &context.grant);
        let receipt = pl_tool_filesystem::stat_path::StatPathTool::new()
            .execute(input, FileCapability(backend))
            .await
            .map_err(ToolError::new)?;
        serde_json::to_value(receipt)
            .map(ToolOutput::json)
            .map_err(ToolError::new)
    }
}

pub fn thread_stat_path_tool_definition() -> pl_agent_tool::ToolDefinition {
    pl_tool_filesystem::stat_path::definition::<FileCapability<super::ExecutorWorkspaceFileBackend>>(
    )
}

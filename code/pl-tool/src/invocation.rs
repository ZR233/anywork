//! Actual workspace invocation facts, independent of a Native Turn or ACP transport.
use futures::future::BoxFuture;
use pl_core::{
    thread::cold::OutputStorageFault,
    tool::{execution_policy::ExecutionGrant, opaque::ToolError},
};
use std::sync::Arc;
use tokio_util::sync::CancellationToken;

#[derive(Debug, Clone)]
pub struct WorkspaceInvocation {
    pub owner_id: String,
    pub call_id: String,
    pub cancellation: CancellationToken,
    pub grant: ExecutionGrant,
    pub tasks: Option<Arc<dyn CommandTaskAccess>>,
}

#[derive(Debug, Clone)]
pub struct CommandTask {
    pub task_id: String,
    pub call_id: String,
    pub tool_id: String,
    pub status: pl_core::thread::task::TaskStatus,
    pub cancel_requested: bool,
}

/// Receipt resolution and optional owner observation hooks, not a command scheduler.
pub trait CommandTaskAccess: std::fmt::Debug + Send + Sync {
    fn current_receipt(&self) -> Option<String>;
    fn get(&self, receipt: &str) -> Result<CommandTask, ToolError>;
    fn report_output(
        &self,
        update: pl_core::model::ToolProgressUpdate,
    ) -> BoxFuture<'_, Result<(), ToolError>>;
    fn report_storage_fault(
        &self,
        fault: Arc<OutputStorageFault>,
    ) -> BoxFuture<'_, Result<(), ToolError>>;
}

impl From<pl_core::tool::opaque::CallContext> for WorkspaceInvocation {
    fn from(context: pl_core::tool::opaque::CallContext) -> Self {
        Self {
            owner_id: context.thread_id,
            call_id: context.call_id,
            cancellation: context.cancellation,
            grant: context.grant,
            tasks: context
                .tasks
                .map(|tasks| Arc::new(tasks) as Arc<dyn CommandTaskAccess>),
        }
    }
}

impl CommandTaskAccess for pl_core::thread::TaskAccess {
    fn current_receipt(&self) -> Option<String> {
        self.list()
            .into_iter()
            .find(|task| task.id == self.current_task_id())
            .map(|task| task.id)
    }
    fn get(&self, receipt: &str) -> Result<CommandTask, ToolError> {
        let task = pl_core::thread::TaskAccess::get(self, receipt).map_err(ToolError::new)?;
        Ok(CommandTask {
            task_id: task.id,
            call_id: task.call_id,
            tool_id: task.tool_id,
            status: task.status,
            cancel_requested: task.cancel_requested,
        })
    }
    fn report_output(
        &self,
        update: pl_core::model::ToolProgressUpdate,
    ) -> BoxFuture<'_, Result<(), ToolError>> {
        Box::pin(async move {
            pl_core::thread::TaskAccess::report_output(self, update)
                .await
                .map_err(ToolError::new)
        })
    }
    fn report_storage_fault(
        &self,
        fault: Arc<OutputStorageFault>,
    ) -> BoxFuture<'_, Result<(), ToolError>> {
        Box::pin(async move {
            self.report_output_storage_fault(fault)
                .await
                .map_err(ToolError::new)
        })
    }
}

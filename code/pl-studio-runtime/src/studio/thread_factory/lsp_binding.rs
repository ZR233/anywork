//! One language-service host binding shared by Native and ACP members.
use super::StudioThreadFactory;
use anyhow::Result;
use pl_lsp::{
    host::LspHostBackend,
    runtime::{LspResult, LspRuntimeRegistry, LspWorkspaceLease},
};
use pl_tool::{command::WorkspaceExecutionBinding, workspace::ToolWorkspace};
use std::{path::PathBuf, sync::Arc};

/// The language-service host of one workspace execution. Local members inherit the host's
/// configuration defaults; remote members configure only their own workspace.
pub(super) struct LspHostBinding {
    host: Option<Arc<dyn LspHostBackend>>,
    defaults: Option<PathBuf>,
}

impl StudioThreadFactory {
    /// Fails only when the executor cannot address the workspace root.
    pub(super) fn lsp_host_binding(
        &self,
        execution: &WorkspaceExecutionBinding,
        remote: bool,
    ) -> Result<LspHostBinding> {
        let host =
            pl_lsp::host::ExecutorLspHost::new(execution.executor().clone(), execution.root())?;
        Ok(LspHostBinding {
            host: Some(Arc::new(host)),
            defaults: (!remote).then(|| self.services.store.paths().home().join("lsp/host")),
        })
    }
}

impl LspHostBinding {
    /// Acquires a new lease of `workspace` on `registry`.
    pub(super) async fn acquire(
        &self,
        registry: &LspRuntimeRegistry,
        workspace: &ToolWorkspace,
    ) -> LspResult<LspWorkspaceLease> {
        registry
            .acquire_workspace(workspace.root(), self.host.clone(), self.defaults.clone())
            .await
    }

    /// Reconfigures a retained lease of the same workspace.
    pub(super) async fn refresh(&self, lease: &LspWorkspaceLease) -> LspResult<()> {
        lease
            .refresh_configuration(self.host.clone(), self.defaults.clone())
            .await
    }
}

//! ACP leases the same physical language services as Native members.
use super::StudioThreadFactory;
use anyhow::Result;
use pl_tool::{command::WorkspaceExecutionBinding, lsp::LspPathBinding, workspace::ToolWorkspace};

#[derive(Clone)]
pub(in crate::studio) struct PreparedAcpLsp {
    pub registry: pl_lsp::runtime::LspRuntimeRegistry,
    pub paths: LspPathBinding,
    pub lease: pl_lsp::runtime::LspWorkspaceLease,
}

impl StudioThreadFactory {
    pub(in crate::studio) async fn prepare_acp_lsp(
        &self,
        workspace: &ToolWorkspace,
        execution: &WorkspaceExecutionBinding,
        remote: bool,
    ) -> Result<PreparedAcpLsp> {
        let registry = self.services.lsp_runtime.clone();
        let host = self.lsp_host_binding(execution, remote)?;
        let lease = host.acquire(&registry, workspace).await?;
        Ok(PreparedAcpLsp {
            registry,
            paths: LspPathBinding::new(workspace.clone(), execution.files()),
            lease,
        })
    }
}

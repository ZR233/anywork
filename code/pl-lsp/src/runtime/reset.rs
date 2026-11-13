//! Explicit retry invalidates only selected members and schedules background work.
use super::{LspResult, LspRuntimeError, LspRuntimeRegistry, LspScope};
impl LspRuntimeRegistry {
    pub async fn reset_lsp(&self, scope: LspScope) -> LspResult<()> {
        if self.is_global && scope == LspScope::All {
            for partition in self.partition_views() {
                partition.reset_partition(&scope).await?;
            }
            return Ok(());
        }
        self.reset_partition(&scope).await
    }

    async fn reset_partition(&self, scope: &LspScope) -> LspResult<()> {
        let roots = {
            let mut state = self.state.lock().await;
            if state.closed {
                return Err(LspRuntimeError::Unavailable(
                    "LSP runtime is stopped".into(),
                ));
            }
            let mut roots = Vec::new();
            for (root, workspace) in &mut state.workspaces {
                let selected = match scope {
                    LspScope::All => true,
                    LspScope::Workspace { workspace_root }
                    | LspScope::Server { workspace_root, .. } => workspace_root == root,
                };
                if !selected || !workspace.configured {
                    continue;
                }
                for (id, server) in &mut workspace.servers {
                    if matches!(scope, LspScope::Server { server_id, .. } if server_id != id) {
                        continue;
                    }
                    server.cancel.cancel();
                    if let Some(client) = &server.client {
                        client.cancel();
                    }
                }
                roots.push(root.clone());
            }
            roots
        };
        for root in roots {
            self.refresh_workspace_configuration(root).await;
        }
        Ok(())
    }
}

//! Snapshot reads only clone already-published owner state; no I/O or lifecycle work.
use super::{LspRuntimeRegistry, LspServerSnapshot, workspace_key};
use crate::client::LspClientRuntimeStatus;
use std::path::Path;
impl LspRuntimeRegistry {
    pub async fn snapshots_for_workspace(&self, root: impl AsRef<Path>) -> Vec<LspServerSnapshot> {
        let root = workspace_key(root.as_ref());
        let (members, errors) = {
            let state = self.state.lock().await;
            let Some(workspace) = state.workspaces.get(&root) else {
                return Vec::new();
            };
            (
                workspace
                    .servers
                    .values()
                    .map(|server| {
                        (
                            server.snapshot(0),
                            server.client.clone(),
                            server.healthy().then(|| server.diagnostics.clone()),
                        )
                    })
                    .collect::<Vec<_>>(),
                workspace.errors.clone(),
            )
        };
        let mut snapshots = Vec::with_capacity(members.len() + errors.len());
        for (mut snapshot, client, diagnostics) in members {
            if let Some(diagnostics) = diagnostics {
                snapshot.diagnostic_count = diagnostics.lock().await.values().map(Vec::len).sum();
            }
            if let Some(client) = client {
                apply_client_status(&mut snapshot, client.runtime_status().await);
            }
            snapshots.push(snapshot);
        }
        snapshots.extend(errors);
        snapshots
    }
    pub async fn snapshots(&self) -> Vec<LspServerSnapshot> {
        let mut snapshots = Vec::new();
        for partition in self.partition_views() {
            let roots: Vec<_> = partition
                .state
                .lock()
                .await
                .workspaces
                .keys()
                .cloned()
                .collect();
            for root in roots {
                snapshots.extend(partition.snapshots_for_workspace(root).await);
            }
        }
        snapshots
    }
}
fn apply_client_status(snapshot: &mut LspServerSnapshot, status: LspClientRuntimeStatus) {
    snapshot.activity_kind = status.activity_kind;
    snapshot.activity_title = status.activity_title;
    snapshot.activity_message = status.activity_message;
    snapshot.activity_percentage = status.activity_percentage;
    if status.last_error.is_some() {
        snapshot.last_error = status.last_error;
        snapshot.last_error_at = status.last_error_at;
    }
}

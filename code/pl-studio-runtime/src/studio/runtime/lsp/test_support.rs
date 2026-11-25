use std::{
    path::Path,
    sync::{Arc, Mutex},
    time::Duration,
};

use pl_lsp::runtime::{LspRuntimeRegistry, LspServerSnapshot};
use tokio::sync::oneshot;

use super::WorkspaceLspSnapshots;

pub(in crate::studio::runtime) struct HeldWorkspaceSnapshot {
    pub entered: oneshot::Sender<Vec<LspServerSnapshot>>,
    pub released: oneshot::Receiver<()>,
}

pub(in crate::studio::runtime) struct PausedWorkspaceSnapshots {
    pub registry: LspRuntimeRegistry,
    pub server: &'static str,
    pub gate: Arc<Mutex<Option<HeldWorkspaceSnapshot>>>,
}

impl WorkspaceLspSnapshots for PausedWorkspaceSnapshots {
    async fn read(&self, endpoint: &str, root: &Path) -> Vec<LspServerSnapshot> {
        let snapshots = self.registry.read(endpoint, root).await;
        if snapshots.iter().any(|server| server.id == self.server) {
            let gate = self.gate.lock().unwrap().take();
            if let Some(gate) = gate {
                let _ = gate.entered.send(snapshots.clone());
                tokio::time::timeout(Duration::from_secs(10), gate.released)
                    .await
                    .expect("workspace snapshot barrier was not released")
                    .expect("workspace snapshot barrier owner dropped");
            }
        }
        snapshots
    }
}

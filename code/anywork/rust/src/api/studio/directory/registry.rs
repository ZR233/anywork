use super::feed::BridgeDirectoryObservationInner;
use crate::api::studio::types::{BridgeError, BridgeShutdownIssue};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex, PoisonError},
    time::Instant,
};
use tokio_util::sync::CancellationToken;

#[flutter_rust_bridge::frb(ignore)]
#[derive(Default)]
pub(crate) struct DirectoryObservationRegistry {
    state: Mutex<RegistryState>,
}

#[flutter_rust_bridge::frb(ignore)]
#[derive(Default)]
struct RegistryState {
    sealed: bool,
    entries: HashMap<u64, Arc<BridgeDirectoryObservationInner>>,
}

pub(crate) struct PendingDirectoryObservations {
    owners: Vec<Arc<BridgeDirectoryObservationInner>>,
}

impl DirectoryObservationRegistry {
    pub(crate) fn register(
        &self,
        owner: &Arc<BridgeDirectoryObservationInner>,
        shutdown: &CancellationToken,
    ) -> Result<(), BridgeError> {
        let mut state = self.state.lock().unwrap_or_else(PoisonError::into_inner);
        if state.sealed || shutdown.is_cancelled() {
            owner.request_close();
            state.entries.insert(owner.id, Arc::clone(owner));
            return Err(BridgeError::runtime_stopped());
        }
        state.entries.retain(|_, owner| !owner.is_settled());
        state.entries.insert(owner.id, Arc::clone(owner));
        Ok(())
    }

    pub(crate) fn unregister(&self, id: u64) {
        let mut state = self.state.lock().unwrap_or_else(PoisonError::into_inner);
        if state
            .entries
            .get(&id)
            .is_some_and(|owner| owner.is_settled())
        {
            state.entries.remove(&id);
        }
    }

    pub(crate) fn broadcast_cancel(&self) -> PendingDirectoryObservations {
        let owners = {
            let mut state = self.state.lock().unwrap_or_else(PoisonError::into_inner);
            state.sealed = true;
            state.entries.values().cloned().collect::<Vec<_>>()
        };
        for owner in &owners {
            owner.request_close();
        }
        PendingDirectoryObservations { owners }
    }

    pub(crate) async fn join_cancelled(
        &self,
        pending: PendingDirectoryObservations,
        deadline: Instant,
    ) -> Vec<BridgeShutdownIssue> {
        let outcomes = futures::future::join_all(pending.owners.iter().map(|owner| async move {
            tokio::time::timeout(
                deadline.saturating_duration_since(Instant::now()),
                owner.close(),
            )
            .await
        }))
        .await;
        let mut issues = Vec::new();
        for (owner, outcome) in pending.owners.iter().zip(outcomes) {
            if matches!(outcome, Ok(Ok(()))) {
                self.unregister(owner.id);
            } else {
                issues.push(BridgeShutdownIssue {
                    stage: "directoryObservations".into(),
                    code: if outcome.is_err() {
                        "timeout"
                    } else {
                        "closeFailed"
                    }
                    .into(),
                    message: "Directory observation close was not confirmed; its owner is retained"
                        .into(),
                    retryable: true,
                    correlation_id: pl_protocol::studio::StudioError::internal().correlation_id,
                });
            }
        }
        issues
    }
}

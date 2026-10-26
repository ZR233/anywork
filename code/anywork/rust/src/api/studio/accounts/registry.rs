//! Account observation owners participate in the existing bridge broadcast/join shutdown.

use super::feed::BridgeAccountObservationInner;
use crate::api::studio::types::{BridgeError, BridgeShutdownIssue};
use std::{
    collections::HashMap,
    sync::{Arc, Mutex, PoisonError},
    time::Instant,
};
use tokio_util::sync::CancellationToken;

#[flutter_rust_bridge::frb(ignore)]
#[derive(Default)]
pub(crate) struct AccountObservationRegistry {
    state: Mutex<RegistryState>,
}
#[flutter_rust_bridge::frb(ignore)]
#[derive(Default)]
struct RegistryState {
    sealed: bool,
    entries: HashMap<u64, Arc<BridgeAccountObservationInner>>,
}

pub(crate) struct PendingAccountObservations {
    owners: Vec<Arc<BridgeAccountObservationInner>>,
}

impl AccountObservationRegistry {
    pub(crate) fn register(
        &self,
        owner: &Arc<BridgeAccountObservationInner>,
        shutdown: &CancellationToken,
    ) -> Result<(), BridgeError> {
        let mut state = self.state.lock().unwrap_or_else(PoisonError::into_inner);
        if state.sealed || shutdown.is_cancelled() {
            owner.request_close();
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

    pub(crate) fn broadcast_cancel(&self) -> PendingAccountObservations {
        let owners = {
            let mut state = self.state.lock().unwrap_or_else(PoisonError::into_inner);
            state.sealed = true;
            state.entries.values().cloned().collect::<Vec<_>>()
        };
        for owner in &owners {
            owner.request_close();
        }
        PendingAccountObservations { owners }
    }

    pub(crate) async fn join_cancelled(
        &self,
        pending: PendingAccountObservations,
        deadline: Instant,
    ) -> Vec<BridgeShutdownIssue> {
        let mut issues = Vec::new();
        let outcomes = futures::future::join_all(pending.owners.iter().map(|owner| async move {
            let remaining = deadline.saturating_duration_since(Instant::now());
            tokio::time::timeout(remaining, owner.close()).await
        }))
        .await;
        for (owner, outcome) in pending.owners.iter().zip(outcomes) {
            match outcome {
                Ok(Ok(())) => self.unregister(owner.id),
                outcome => issues.push(BridgeShutdownIssue { stage: "accountObservations".into(),
                    code: if outcome.is_err() { "timeout" } else { "closeFailed" }.into(),
                    message: "Account observation close was not confirmed; its original owner is retained".into(),
                    retryable: true, correlation_id: pl_protocol::studio::StudioError::internal().correlation_id }),
            }
        }
        issues
    }
}

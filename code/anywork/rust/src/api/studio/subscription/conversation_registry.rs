//! Strong conversation owners participate in the existing shared application exit deadline.
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Instant;

use tokio_util::sync::CancellationToken;

use crate::api::studio::handlers::chat::ConversationOwner;
use crate::api::studio::types::{BridgeError, BridgeShutdownIssue};

#[flutter_rust_bridge::frb(ignore)]
#[derive(Default)]
pub(super) struct ConversationRegistry {
    state: Mutex<RegistryState>,
}

#[flutter_rust_bridge::frb(ignore)]
#[derive(Default)]
struct RegistryState {
    sealed: bool,
    owners: HashMap<String, Arc<ConversationOwner>>,
}

pub(super) struct PendingConversations(Vec<Arc<ConversationOwner>>);

impl ConversationRegistry {
    pub(super) fn register(
        &'static self,
        owner: &Arc<ConversationOwner>,
        shutdown: &CancellationToken,
    ) -> Result<(), BridgeError> {
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        if state.sealed || shutdown.is_cancelled() {
            owner.request_close();
            return Err(pl_protocol::studio::StudioError::new(
                pl_protocol::studio::StudioErrorCode::Cancelled,
                "conversation registry is closed",
                false,
            )
            .into());
        }
        if state.owners.contains_key(&owner.subscription_id) {
            return Err(BridgeError::invalid_argument(
                "duplicate conversation subscription identity",
            ));
        }
        // Install cleanup while holding publication: an immediately cancelled lifecycle may already
        // run, but cannot unregister until insertion below finishes. No late register can resurrect
        // an owner after successful cleanup, and no await separates task creation from retention.
        owner.install_lifecycle(move |subscription_id| self.unregister(subscription_id))?;
        state
            .owners
            .insert(owner.subscription_id.clone(), Arc::clone(owner));
        Ok(())
    }

    pub(super) fn unregister(&self, subscription_id: &str) {
        let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
        if state
            .owners
            .get(subscription_id)
            .is_some_and(|owner| owner.is_settled())
        {
            state.owners.remove(subscription_id);
        }
    }

    pub(super) fn broadcast_cancel(&self) -> PendingConversations {
        let owners = {
            let mut state = self.state.lock().unwrap_or_else(|e| e.into_inner());
            state.sealed = true;
            state.owners.values().cloned().collect::<Vec<_>>()
        };
        for owner in &owners {
            owner.request_close();
        }
        PendingConversations(owners)
    }

    pub(super) async fn join_cancelled(
        &self,
        pending: PendingConversations,
        deadline: Instant,
    ) -> Vec<BridgeShutdownIssue> {
        let outcomes = futures::future::join_all(pending.0.iter().map(|owner| async move {
            tokio::time::timeout(
                deadline.saturating_duration_since(Instant::now()),
                owner.close(),
            )
            .await
        }))
        .await;
        let mut issues = Vec::new();
        for (owner, outcome) in pending.0.iter().zip(outcomes) {
            match outcome {
                Ok(Ok(())) => self.unregister(&owner.subscription_id),
                Ok(Err(error)) => issues.push(BridgeShutdownIssue {
                    stage: "conversations".to_owned(), code: "joinError".to_owned(),
                    message: error.message, retryable: error.retryable, correlation_id: error.correlation_id,
                }),
                Err(_) => issues.push(super::shutdown_issue("conversations", "timeout",
                    "a conversation feed did not close within the exit budget; its owner is retained")),
            }
        }
        issues
    }
}

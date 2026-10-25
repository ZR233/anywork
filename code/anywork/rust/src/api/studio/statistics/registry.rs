//! Strong bridge owners for open statistics feeds and shutdown joining.

use std::collections::HashMap;
use std::sync::Arc;
use std::time::Instant;

use tokio::sync::Mutex;
use tokio_util::sync::CancellationToken;

use super::feed::{BridgeStatisticsFeedInner, StatisticsFeedCloseError};
use crate::api::studio::types::{BridgeError, BridgeShutdownIssue};

/// Strong bridge-owned feed registry. Shutdown seals admission before signalling each feed and
/// retains any feed whose real close has not completed.
pub(crate) struct StatisticsFeedRegistry {
    state: Mutex<StatisticsFeedRegistryState>,
}

struct StatisticsFeedRegistryState {
    sealed: bool,
    entries: HashMap<u64, Arc<BridgeStatisticsFeedInner>>,
}

pub(crate) struct PendingStatisticsFeedCancellation {
    owners: Vec<Arc<BridgeStatisticsFeedInner>>,
    issues: Vec<BridgeShutdownIssue>,
}

impl StatisticsFeedRegistry {
    pub(crate) fn new() -> Self {
        Self {
            state: Mutex::new(StatisticsFeedRegistryState {
                sealed: false,
                entries: HashMap::new(),
            }),
        }
    }

    pub(crate) async fn register(
        &self,
        inner: &Arc<BridgeStatisticsFeedInner>,
        shutdown: &CancellationToken,
    ) -> Result<(), BridgeError> {
        let mut state = self.state.lock().await;
        if state.sealed || shutdown.is_cancelled() {
            return Err(BridgeError::runtime_stopped());
        }
        state.entries.retain(|_, owner| !owner.is_settled());
        state.entries.insert(inner.id, Arc::clone(inner));
        Ok(())
    }

    pub(crate) async fn unregister(&self, id: u64) {
        let mut state = self.state.lock().await;
        if state
            .entries
            .get(&id)
            .is_some_and(|owner| owner.is_settled())
        {
            state.entries.remove(&id);
        }
    }

    pub(crate) async fn broadcast_cancel(
        &self,
        deadline: Instant,
    ) -> PendingStatisticsFeedCancellation {
        let mut issues = Vec::new();
        let owners = {
            let remaining = deadline.saturating_duration_since(Instant::now());
            match tokio::time::timeout(remaining, self.state.lock()).await {
                Ok(mut state) => {
                    state.sealed = true;
                    state.entries.retain(|_, owner| !owner.is_settled());
                    state.entries.values().cloned().collect::<Vec<_>>()
                }
                Err(_) => {
                    issues.push(BridgeShutdownIssue {
                        stage: "statisticsFeeds".to_string(),
                        code: "timeout".to_string(),
                        message: "the statistics feed registry lock was not acquired within the exit budget".to_string(),
                        retryable: true,
                        correlation_id: pl_protocol::studio::StudioError::internal()
                            .correlation_id,
                    });
                    Vec::new()
                }
            }
        };
        for owner in &owners {
            owner.request_close();
        }
        PendingStatisticsFeedCancellation { owners, issues }
    }

    pub(crate) async fn join_cancelled(
        &self,
        pending: PendingStatisticsFeedCancellation,
        deadline: Instant,
    ) -> Vec<BridgeShutdownIssue> {
        let PendingStatisticsFeedCancellation { owners, mut issues } = pending;
        let outcomes = futures::future::join_all(owners.iter().map(|owner| async move {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return FeedStop::TimedOut;
            }
            match tokio::time::timeout(remaining, owner.close()).await {
                Ok(Ok(())) => FeedStop::Stopped,
                Ok(Err(error)) => FeedStop::Failed(error),
                Err(_) => FeedStop::TimedOut,
            }
        }))
        .await;

        let mut stopped = Vec::new();
        for (owner, outcome) in owners.iter().zip(outcomes) {
            match outcome {
                FeedStop::Stopped => stopped.push(owner.id),
                FeedStop::Failed(error) => issues.push(BridgeShutdownIssue {
                    stage: "statisticsFeeds".to_string(),
                    code: "closeFailed".to_string(),
                    message: format!("a statistics feed did not close cleanly: {error}"),
                    retryable: true,
                    correlation_id: pl_protocol::studio::StudioError::internal()
                        .correlation_id,
                }),
                FeedStop::TimedOut => issues.push(BridgeShutdownIssue {
                    stage: "statisticsFeeds".to_string(),
                    code: "timeout".to_string(),
                    message: "a statistics feed did not close within the exit budget; its owner is retained".to_string(),
                    retryable: true,
                    correlation_id: pl_protocol::studio::StudioError::internal()
                        .correlation_id,
                }),
            }
        }
        if !stopped.is_empty() {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if let Ok(mut state) = tokio::time::timeout(remaining, self.state.lock()).await {
                for id in stopped {
                    state.entries.remove(&id);
                }
            }
        }
        issues
    }
}

enum FeedStop {
    Stopped,
    Failed(StatisticsFeedCloseError),
    TimedOut,
}

//! Lifecycle-only supervision for concrete typed feeds; no business payload or second reducer.
use std::sync::{Arc, Mutex};
use std::sync::atomic::Ordering;

use tokio_util::sync::CancellationToken;

use crate::api::studio::types::{BridgeCleanupRecovery, BridgeError, BridgeFeedCloseIssue, BridgeShutdownIssue};
use super::{OWNED_PENDING, SubscriptionCompletion, SubscriptionCompletionFacts, SubscriptionOwner, owned_completion};

struct State {
    closing: bool,
    completion: Option<SubscriptionCompletion>,
    failures: Vec<BridgeError>,
    join_issue: Option<BridgeShutdownIssue>,
    cleanup_issues: Vec<BridgeFeedCloseIssue>,
}

/// Registered resources outlive a dropped opaque. Release is called only after the retained
/// producer completion is truly Clean, never merely after signalling cancellation.
#[flutter_rust_bridge::frb(ignore)]
pub(crate) trait TypedFeedResource: Send + Sync {
    fn release_after_join(&self);
}

#[flutter_rust_bridge::frb(ignore)]
pub(crate) struct TypedFeedRegistration {
    pub(crate) task: Arc<TypedFeedTask>,
    pub(crate) resource: Arc<dyn TypedFeedResource>,
}

#[flutter_rust_bridge::frb(ignore)]
pub(crate) struct TypedFeedTask {
    pub(crate) id: u64,
    cancel: CancellationToken,
    state: Mutex<State>,
    facts: Arc<SubscriptionCompletionFacts>,
}

impl TypedFeedTask {
    pub(crate) fn new(id: u64, cancel: CancellationToken) -> Arc<Self> {
        Arc::new(Self { id, cancel, state: Mutex::new(State { closing: false, completion: None,
            failures: Vec::new(), join_issue: None, cleanup_issues: Vec::new() }),
            facts: Arc::new(SubscriptionCompletionFacts::default()) })
    }

    pub(crate) fn cancel(&self) -> &CancellationToken { &self.cancel }

    /// Start and close linearize on the same guard. Once close observes NotStarted, start can
    /// no longer spawn work; once start wins, the real completion is installed before unlock.
    pub(crate) fn start(&self, work: impl std::future::Future<Output = ()> + Send + 'static) -> Result<(), BridgeError> {
        let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closing || self.cancel.is_cancelled() { return Err(closed()); }
        if state.completion.is_some() { return Err(conflict()); }
        self.facts.producer.store(OWNED_PENDING, Ordering::SeqCst);
        state.completion = Some(owned_completion(tokio::spawn(work), self.id, self.facts.clone(), SubscriptionOwner::Producer));
        Ok(())
    }

    /// Only bounded synchronous owner operations run here. Concrete producers use this for the
    /// actual non-awaiting FRB port send; ACK/stream admission and close share its publication edge.
    pub(crate) fn admit<T>(&self, operation: impl FnOnce() -> Result<T, BridgeError>) -> Result<T, BridgeError> {
        let state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closing || self.cancel.is_cancelled() { return Err(closed()); }
        operation()
    }

    pub(crate) fn admit_studio<T>(&self, operation: impl FnOnce() -> Result<T, pl_protocol::studio::StudioError>)
        -> Result<T, pl_protocol::studio::StudioError> {
        let state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closing || self.cancel.is_cancelled() { return Err(closing_error()); }
        operation()
    }

    pub(crate) fn signal_cancel(&self) {
        self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner).closing = true;
        self.cancel.cancel();
    }

    pub(crate) fn record_failure(&self, error: BridgeError) {
        let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        // A send admitted before closing keeps its failure even if close won the later race.
        state.failures.push(error);
    }

    pub(crate) fn record_cleanup_issue(&self, issue: BridgeFeedCloseIssue) {
        let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if !state.cleanup_issues.contains(&issue) { state.cleanup_issues.push(issue); }
    }

    pub(crate) fn is_settled(&self) -> bool {
        let state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        // A naturally ended producer still owes its delivered, unacknowledged sources. Actual
        // completion becomes releasable only after close, not merely after a typed terminal/EOF.
        state.closing && state.failures.is_empty() && state.join_issue.is_none() && state.cleanup_issues.is_empty()
            && (state.completion.is_none() || self.facts.is_settled())
    }

    pub(crate) async fn wait_stopped(&self) -> Result<(), Arc<String>> {
        self.signal_cancel();
        let completion = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner).completion.clone();
        if let Some(completion) = completion && let Err(error) = completion.await {
            let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            if state.join_issue.is_none() {
                state.join_issue = Some(BridgeShutdownIssue { stage: "typedFeed".into(), code: "joinError".into(),
                    message: error.to_string(), retryable: false,
                    correlation_id: pl_protocol::studio::StudioError::internal().correlation_id });
            }
        }
        let issues = self.issues();
        match issues.first() {
            Some(issue) => Err(Arc::new(issue.message.clone())),
            None => Ok(()),
        }
    }

    pub(crate) fn issues(&self) -> Vec<BridgeShutdownIssue> {
        self.close_issues().into_iter().map(|issue| issue.diagnostic).collect()
        }

    pub(crate) fn close_issues(&self) -> Vec<BridgeFeedCloseIssue> {
        let state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        let mut issues = Vec::with_capacity(state.failures.len() + state.cleanup_issues.len() + 1);
        for error in &state.failures {
            issues.push(BridgeFeedCloseIssue { diagnostic: BridgeShutdownIssue {
                stage: "typedFeed".into(), code: "deliveryFailed".into(), message: error.message.clone(),
                retryable: error.retryable, correlation_id: error.correlation_id.clone() },
                recovery: BridgeCleanupRecovery::Terminal });
        }
        if let Some(issue) = &state.join_issue {
            issues.push(BridgeFeedCloseIssue { diagnostic: issue.clone(), recovery: BridgeCleanupRecovery::Terminal });
        }
        issues.extend(state.cleanup_issues.iter().cloned());
        issues
    }
}

pub(crate) fn closed() -> BridgeError {
    closing_error().into()
}

fn closing_error() -> pl_protocol::studio::StudioError {
    pl_protocol::studio::StudioError::new(pl_protocol::studio::StudioErrorCode::Cancelled,
        "The typed feed is closing", false)
}

fn conflict() -> BridgeError {
    pl_protocol::studio::StudioError::new(pl_protocol::studio::StudioErrorCode::Conflict,
        "The typed feed already has a producer", false).into()
}

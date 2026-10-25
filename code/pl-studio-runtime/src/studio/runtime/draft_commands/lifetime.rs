//! Shared lifecycle only for the two concrete commands. No payloads or arbitrary task registry.
use std::future::Future;
use std::sync::{Arc, Mutex, Weak};

use pl_protocol::studio::{
    CleanupRecovery, FeedCloseIssue, FeedCloseOutcome, FeedCloseReport, StudioError,
    StudioErrorCode, StudioShutdownIssue,
};
use tokio_util::sync::CancellationToken;

use super::super::background_task::BackgroundTask;
use super::registry::Registry;

pub(super) struct Lifetime {
    pub(super) id: String,
    registry: Weak<Mutex<Registry>>,
    state: Mutex<State>,
    pub(super) cancel: CancellationToken,
}

struct State {
    closing: bool,
    work: Option<Arc<BackgroundTask>>,
    cleanup: Option<Arc<BackgroundTask>>,
    cleanup_joined: bool,
    cleanup_issues: Vec<FeedCloseIssue>,
    terminal_issues: Vec<FeedCloseIssue>,
    released: bool,
}

impl Lifetime {
    pub(super) fn new(id: String, registry: Weak<Mutex<Registry>>) -> Arc<Self> {
        Arc::new(Self {
            id,
            registry,
            cancel: CancellationToken::new(),
            state: Mutex::new(State {
                closing: false,
                work: None,
                cleanup: None,
                cleanup_joined: false,
                cleanup_issues: Vec::new(),
                terminal_issues: Vec::new(),
                released: false,
            }),
        })
    }

    pub(super) fn install(&self, task: Arc<BackgroundTask>) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .work = Some(task);
    }

    pub(super) fn admit<T>(
        &self,
        call: impl FnOnce() -> Result<T, StudioError>,
    ) -> Result<T, StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closing {
            return Err(super::closed());
        }
        call()
    }

    pub(super) fn request_close(&self) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .closing = true;
        self.cancel.cancel();
    }

    pub(super) fn is_closed(&self) -> bool {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .released
    }

    pub(super) fn issues(&self) -> Vec<FeedCloseIssue> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let mut issues = state.terminal_issues.clone();
        issues.extend(state.cleanup_issues.clone());
        issues
    }

    /// The accepted command is never aborted, including while closing and after a lost result.
    pub(super) async fn join_work(&self) -> bool {
        let task = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .work
            .clone();
        if let Some(task) = task
            && task.join().await.is_err()
        {
            self.record_terminal(
                "workerJoinError",
                "The original draft command worker did not join successfully",
            );
            return false;
        }
        true
    }

    pub(super) fn record_terminal(&self, code: &str, message: &str) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        terminal(&mut state, code, message);
    }

    pub(super) fn replace_cleanup(&self, issues: Vec<FeedCloseIssue>) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .cleanup_issues = issues;
    }

    pub(super) fn close_task(
        self: &Arc<Self>,
        retry: bool,
        cleanup: impl Future<Output = ()> + Send + 'static,
    ) -> Arc<BackgroundTask> {
        self.request_close();
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(task) = &state.cleanup
            && (!retry || !state.cleanup_joined || state.released)
        {
            return task.clone();
        }
        let joined = self.clone();
        let task = BackgroundTask::with_cleanup(tokio::spawn(cleanup), move || {
            // No retry can replace this slot until this callback records actual join. In
            // particular, a failed cleanup can be retried without forgetting its terminal issue.
            let release = {
                let mut state = joined
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                state.cleanup_joined = true;
                if !state.cleanup.as_ref().is_some_and(|task| task.succeeded()) {
                    terminal(
                        &mut state,
                        "cleanupJoinError",
                        "The original draft cleanup worker did not join successfully",
                    );
                }
                if !state.released
                    && state.cleanup_issues.is_empty()
                    && state.terminal_issues.is_empty()
                {
                    state.released = true;
                    true
                } else {
                    false
                }
            };
            if release && let Some(registry) = joined.registry.upgrade() {
                registry
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .jobs
                    .remove(&joined.id);
            }
        });
        state.cleanup_joined = false;
        state.cleanup = Some(task.clone());
        task
    }

    pub(super) async fn report(&self, mut cleanup: Arc<BackgroundTask>) -> FeedCloseReport {
        loop {
            if cleanup.join().await.is_err() {
                self.record_terminal(
                    "cleanupJoinError",
                    "The original draft cleanup worker did not join successfully",
                );
            }
            let next = {
                let state = self
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                if let Some(next) = state
                    .cleanup
                    .as_ref()
                    .filter(|task| !Arc::ptr_eq(task, &cleanup))
                {
                    next.clone()
                } else {
                    let mut issues = state.terminal_issues.clone();
                    issues.extend(state.cleanup_issues.clone());
                    return FeedCloseReport {
                        feed_id: self.id.clone(),
                        outcome: if issues.is_empty() {
                            FeedCloseOutcome::Clean
                        } else {
                            FeedCloseOutcome::Unresolved { issues }
                        },
                    };
                }
            };
            cleanup = next;
        }
    }
}

fn terminal(state: &mut State, code: &str, message: &str) {
    if !state
        .terminal_issues
        .iter()
        .any(|issue| issue.diagnostic.code == code)
    {
        state
            .terminal_issues
            .push(super::issue(code, message, CleanupRecovery::Terminal));
    }
}

pub(super) fn closed() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Draft command observation is closing",
        false,
    )
}

pub(super) fn issue(code: &str, message: &str, recovery: CleanupRecovery) -> FeedCloseIssue {
    FeedCloseIssue {
        diagnostic: StudioShutdownIssue {
            stage: "draftCommands".into(),
            code: code.into(),
            message: message.into(),
            retryable: recovery != CleanupRecovery::Terminal,
            correlation_id: StudioError::internal().correlation_id,
        },
        recovery,
    }
}

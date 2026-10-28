//! Original parent admission and native query ownership survive a cancelled HTTP waiter.
use std::sync::{Arc, Mutex, Weak};

use pl_protocol::products::identity::{ProductReadOrigin, ProductReadScopeIdentity};
use pl_protocol::studio::{CleanupRecovery, FeedCloseIssue, FeedCloseOutcome, StudioError};
use pl_studio_runtime::StudioRuntime;
use tokio::sync::oneshot;
use tokio_util::sync::CancellationToken;

use super::feed::Transport;
use super::native::{NativeRead, OpenReadKind};
use super::tasks::{self, Completion};

struct State {
    closing: bool,
    identity: Option<ProductReadScopeIdentity>,
    source: Option<Arc<NativeRead>>,
    task: Option<Completion>,
    issues: Vec<FeedCloseIssue>,
    join_issue: Option<FeedCloseIssue>,
    cleanup_completed: bool,
    unresolved: bool,
    cleanup_token: Arc<()>,
}

pub(super) struct ReadOwner {
    parent: Weak<Transport>,
    cancel: CancellationToken,
    state: Mutex<State>,
    cleanup: tokio::sync::Mutex<()>,
}

pub(super) struct ReadTicket {
    owner: Arc<ReadOwner>,
    ready: Option<oneshot::Receiver<Result<ProductReadScopeIdentity, StudioError>>>,
    adopted: bool,
}

impl ReadOwner {
    pub(super) fn new(parent: &Arc<Transport>) -> Arc<Self> {
        Arc::new(Self {
            parent: Arc::downgrade(parent),
            cancel: parent.cancel.child_token(),
            cleanup: tokio::sync::Mutex::new(()),
            state: Mutex::new(State {
                closing: false,
                identity: None,
                source: None,
                task: None,
                issues: Vec::new(),
                join_issue: None,
                cleanup_completed: false,
                unresolved: false,
                cleanup_token: Arc::new(()),
            }),
        })
    }

    /// The parent already retains this owner under the same gate that closes read admission.
    pub(super) fn start(
        self: &Arc<Self>,
        runtime: &StudioRuntime,
        kind: OpenReadKind,
        origin: ProductReadOrigin,
    ) -> ReadTicket {
        let expected_version = kind.version();
        let opening = kind.start(runtime, origin.clone());
        let (opened, ready) = oneshot::channel();
        let owner = self.clone();
        let task = tokio::spawn(async move {
            let source = match opening.await {
                Ok(source) => Arc::new(source),
                Err(error) => {
                    owner.request_close();
                    let _ = opened.send(Err(pl_studio_runtime::studio_error_from_anyhow(error)));
                    return;
                }
            };
            let result = {
                let mut state = owner
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                // Even a late or malformed result keeps its real native cleanup owner.
                state.identity = Some(source.identity());
                state.source = Some(source.clone());
                if state.closing || owner.cancel.is_cancelled() {
                    Err(tasks::cancelled())
                } else {
                    source
                        .validate(&origin, expected_version)
                        .map(|()| source.identity())
                }
            };
            if result.is_err() {
                owner.request_close();
            }
            if opened.send(result).is_err() {
                owner.request_close();
            }
            owner.cancel.cancelled().await;
            owner.close_source(None).await;
        });
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .task = Some(tasks::retain(task));
        ReadTicket {
            owner: self.clone(),
            ready: Some(ready),
            adopted: false,
        }
    }

    pub(super) fn matches(&self, id: &str) -> bool {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .identity
            .as_ref()
            .is_some_and(|identity| identity.scope_id == id)
    }

    pub(super) fn query<F>(
        &self,
        query: impl FnOnce(&NativeRead) -> Result<F, StudioError>,
    ) -> Result<F, StudioError> {
        self.parent
            .upgrade()
            .ok_or_else(tasks::cancelled)?
            .admit(|| {
                let state = self
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                if state.closing || self.cancel.is_cancelled() {
                    return Err(tasks::cancelled());
                }
                let source = state.source.as_ref().ok_or_else(tasks::cancelled)?;
                source.ensure_open()?;
                // Native query construction synchronously retains the actual ReadCalls task in
                // its scope. Dropping this waiter cannot abandon the original query's join.
                query(source)
            })
    }

    pub(super) fn request_close(&self) {
        let source = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.closing = true;
            state.source.clone()
        };
        self.cancel.cancel();
        if let Some(source) = source {
            source.request_close();
        }
    }

    async fn close_source(&self, retry_token: Option<Arc<()>>) {
        // Serialize native reports so a concurrent stale Unresolved cannot overwrite Clean.
        // This guard protects cleanup only, never query/open admission or a callback.
        let _cleanup = self.cleanup.lock().await;
        let source = {
            let state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if match &retry_token {
                None => state.cleanup_completed,
                Some(token) => !Arc::ptr_eq(token, &state.cleanup_token),
            } {
                return;
            }
            state.source.clone()
        };
        let Some(source) = source else {
            return;
        };
        // The original native handle retains its tasks if this waiter is cancelled. Never
        // cache a result until its real report arrives; retry does not start another open.
        let report = source.close(retry_token.is_some()).await;
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.cleanup_completed = true;
        state.cleanup_token = Arc::new(());
        match report.outcome {
            FeedCloseOutcome::Clean => {
                state.unresolved = false;
                state.issues.clear();
                if state.join_issue.is_none() {
                    state.source.take();
                }
            }
            FeedCloseOutcome::Unresolved { issues } => {
                state.unresolved = true;
                state.issues = issues;
            }
        }
    }

    pub(super) async fn close(&self, retry: bool) -> Vec<FeedCloseIssue> {
        self.request_close();
        let task = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .task
            .clone();
        if let Some(task) = task {
            let _ = task.await;
        }
        // Observe a failed worker before cleanup so the original handle is retained on failure.
        let _ = self.issues(false);
        let token = retry.then(|| {
            self.state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .cleanup_token
                .clone()
        });
        self.close_source(token).await;
        self.issues(false)
    }

    pub(super) fn issues(&self, pending: bool) -> Vec<FeedCloseIssue> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.task.as_ref().is_some_and(tasks::failed) && state.join_issue.is_none() {
            state.join_issue = Some(tasks::issue(
                "readJoinError",
                "The Recovery HTTP read/opening task did not join successfully",
                CleanupRecovery::Terminal,
            ));
        }
        let mut issues = state.issues.clone();
        issues.extend(state.join_issue.iter().cloned());
        if state.unresolved && state.issues.is_empty() {
            issues.push(tasks::issue(
                "nativeCloseUnresolved",
                "The original Recovery native read reported Unresolved without issues",
                CleanupRecovery::RetryClose,
            ));
        }
        if pending
            && (state
                .task
                .as_ref()
                .is_none_or(|task| !tasks::finished(task))
                || (state.source.is_some() && !state.cleanup_completed))
        {
            issues.push(tasks::issue(
                "completionPending",
                "The Recovery HTTP read/opening still owns unfinished work",
                CleanupRecovery::AwaitCompletion,
            ));
        }
        issues
    }

    pub(super) fn is_finished(&self) -> bool {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.closing
            && state.task.as_ref().is_some_and(tasks::finished)
            && (state.source.is_none() || state.cleanup_completed)
    }

    pub(super) fn is_clean(&self) -> bool {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.closing
            && state.source.is_none()
            && !state.unresolved
            && state.issues.is_empty()
            && state.join_issue.is_none()
            && state.task.as_ref().is_some_and(tasks::succeeded)
    }
}

impl ReadTicket {
    pub(super) async fn ready(&mut self) -> Result<ProductReadScopeIdentity, StudioError> {
        self.ready
            .take()
            .ok_or_else(StudioError::internal)?
            .await
            .map_err(|_| StudioError::internal())?
    }

    pub(super) fn adopt(&mut self) -> Result<(), StudioError> {
        self.owner.query(|_| Ok(()))?;
        self.adopted = true;
        Ok(())
    }
}

impl Drop for ReadTicket {
    fn drop(&mut self) {
        if !self.adopted {
            self.owner.request_close();
        }
    }
}

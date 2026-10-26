//! Independent original read ownership, not a child of an HTTP Catalog feed.
use super::{
    native::{Capability, NativeRead, OpenRead, ReadKind},
    tasks::{self, Completion},
    types::OpenReadReply,
};
use pl_protocol::{
    products::{
        identity::ProductReadScopeIdentity, read::delegation_models::DelegationModelReadTarget,
    },
    studio::{CleanupRecovery, FeedCloseIssue, FeedCloseOutcome, FeedCloseReport, StudioError},
};
use pl_studio_runtime::StudioRuntime;
use std::sync::{Arc, Mutex};
use tokio::sync::oneshot;
use tokio_util::sync::CancellationToken;

struct State {
    closing: bool,
    identity: Option<ProductReadScopeIdentity>,
    target: Option<DelegationModelReadTarget>,
    source: Option<Arc<NativeRead>>,
    task: Option<Completion>,
    issues: Vec<FeedCloseIssue>,
    join_issue: Option<FeedCloseIssue>,
    cleanup_completed: bool,
    cleanup_token: Arc<()>,
}
pub(super) struct ReadOwner {
    kind: ReadKind,
    cancel: CancellationToken,
    state: Mutex<State>,
    cleanup: tokio::sync::Mutex<()>,
}
pub(super) struct ReadTicket {
    pub(super) owner: Arc<ReadOwner>,
    ready: Option<oneshot::Receiver<Result<OpenReadReply, StudioError>>>,
    adopted: bool,
}
impl ReadOwner {
    pub(super) fn new(kind: ReadKind, shutdown: &CancellationToken) -> Arc<Self> {
        Arc::new(Self {
            kind,
            cancel: shutdown.child_token(),
            cleanup: tokio::sync::Mutex::new(()),
            state: Mutex::new(State {
                closing: false,
                identity: None,
                target: None,
                source: None,
                task: None,
                issues: Vec::new(),
                join_issue: None,
                cleanup_completed: false,
                cleanup_token: Arc::new(()),
            }),
        })
    }
    /// Called only after registry admission; original native open is registered synchronously.
    pub(super) fn start(
        self: &Arc<Self>,
        runtime: &StudioRuntime,
        request: OpenRead,
    ) -> ReadTicket {
        let opening = request.start(runtime);
        let (published, ready) = oneshot::channel();
        let owner = self.clone();
        let task = tokio::spawn(async move {
            let source = match opening.await {
                Ok(source) => Arc::new(source),
                Err(error) => {
                    owner.request_close();
                    let _ = published.send(Err(pl_studio_runtime::studio_error_from_anyhow(error)));
                    return;
                }
            };
            let result = {
                let mut state = owner
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                // Even a malformed native descriptor has an original cleanup owner. Store it
                // before validation so no conversion/reply error can abandon its real queries.
                state.identity = Some(source.identity());
                state.target = source.target();
                state.source = Some(source.clone());
                if state.closing || owner.cancel.is_cancelled() {
                    Err(tasks::cancelled())
                } else {
                    request.validate(&source).map(|()| OpenReadReply {
                        scope_id: source.identity().scope_id.clone(),
                        identity: source.identity(),
                        target: state.target.clone(),
                    })
                }
            };
            drop(request);
            if result.is_err() {
                owner.request_close();
            }
            if published.send(result).is_err() {
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
            .is_some_and(|v| v.scope_id == id)
    }
    pub(super) fn require(&self, capability: Capability) -> Result<(), StudioError> {
        if capability.accepts(self.kind) {
            Ok(())
        } else {
            Err(tasks::wrong())
        }
    }
    pub(super) fn query<F>(
        &self,
        query: impl FnOnce(&NativeRead) -> Result<F, StudioError>,
    ) -> Result<F, StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closing || self.cancel.is_cancelled() {
            return Err(tasks::cancelled());
        }
        let source = state.source.as_ref().ok_or_else(tasks::cancelled)?;
        source.ensure_open()?;
        // Closure creates the original owned native query while the same closing gate is held.
        query(source)
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
        if let Some(source) = source {
            source.request_close();
        }
        self.cancel.cancel();
    }
    async fn close_source(&self, retry_token: Option<Arc<()>>) {
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
        // A cancelled waiter cannot release this source or native in-flight task. Completion is
        // published only after the real native report; a later retry still owns the same handle.
        let report = source.close(retry_token.is_some()).await;
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.cleanup_completed = true;
        state.cleanup_token = Arc::new(());
        match report.outcome {
            FeedCloseOutcome::Clean => {
                if state.join_issue.is_none() {
                    state.source.take();
                }
                state.issues.clear();
            }
            FeedCloseOutcome::Unresolved { issues } => state.issues = issues,
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
        if let Some(task) = task
            && task.await.is_err()
        {
            self.state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .join_issue
                .get_or_insert_with(|| {
                    tasks::issue(
                        "readJoinError",
                        "The original Models HTTP opening task did not join successfully",
                        CleanupRecovery::Terminal,
                    )
                });
        }
        let token = if retry {
            Some(
                self.state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .cleanup_token
                    .clone(),
            )
        } else {
            None
        };
        self.close_source(token).await;
        self.issues(false)
    }
    pub(super) async fn close_report(&self, retry: bool) -> Result<FeedCloseReport, StudioError> {
        let issues = self.close(retry).await;
        let id = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .identity
            .as_ref()
            .map(|v| v.scope_id.clone())
            .ok_or_else(tasks::missing)?;
        Ok(tasks::report(id, issues))
    }
    pub(super) fn issues(&self, pending: bool) -> Vec<FeedCloseIssue> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let mut issues = state.issues.clone();
        issues.extend(state.join_issue.iter().cloned());
        if pending
            && (state.task.as_ref().is_none_or(|v| !tasks::succeeded(v))
                || (state.source.is_some() && !state.cleanup_completed))
        {
            issues.push(tasks::issue(
                "completionPending",
                "The original Models HTTP read/opening still owns work",
                CleanupRecovery::AwaitCompletion,
            ));
        }
        issues
    }
    pub(super) fn is_clean(&self) -> bool {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.closing
            && state.source.is_none()
            && state.issues.is_empty()
            && state.join_issue.is_none()
            && state.task.as_ref().is_some_and(tasks::succeeded)
    }
}
impl ReadTicket {
    pub(super) async fn ready(&mut self) -> Result<OpenReadReply, StudioError> {
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

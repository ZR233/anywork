//! One original Catalog feed and the actual Hyper body; no HTTP publication/ACK queue.
use super::{
    body::CatalogBody,
    tasks::{self, Completion},
};
use pl_protocol::{
    products::{
        feed::model_catalog::ModelCatalogFrame,
        identity::{ProductFeedIdentity, ProductResource},
    },
    studio::{CleanupRecovery, FeedCloseIssue, FeedCloseReport, StudioError},
};
use pl_studio_runtime::{StudioRuntime, models::StudioModelCatalogFeed};
use std::sync::{Arc, Mutex};
use tokio::sync::{Notify, OwnedSemaphorePermit, oneshot};
use tokio_util::sync::CancellationToken;

enum BodyPhase {
    Unclaimed,
    Active,
    Ended,
}
struct State {
    closing: bool,
    identity: Option<ProductFeedIdentity>,
    source: Option<Arc<StudioModelCatalogFeed>>,
    task: Option<Completion>,
    body: BodyPhase,
    issues: Vec<FeedCloseIssue>,
    join_issue: Option<FeedCloseIssue>,
    permit: Option<OwnedSemaphorePermit>,
}
pub(super) struct FeedOwner {
    pub(super) changed: Arc<Notify>,
    pub(super) cancel: CancellationToken,
    state: Mutex<State>,
}
pub(super) struct FeedTicket {
    pub(super) owner: Arc<FeedOwner>,
    ready: Option<oneshot::Receiver<Result<ProductFeedIdentity, StudioError>>>,
    adopted: bool,
}
impl FeedOwner {
    pub(super) fn new(shutdown: &CancellationToken, permit: OwnedSemaphorePermit) -> Arc<Self> {
        Arc::new(Self {
            changed: Arc::new(Notify::new()),
            cancel: shutdown.child_token(),
            state: Mutex::new(State {
                closing: false,
                identity: None,
                source: None,
                task: None,
                body: BodyPhase::Unclaimed,
                issues: Vec::new(),
                join_issue: None,
                permit: Some(permit),
            }),
        })
    }
    pub(super) fn start(self: &Arc<Self>, runtime: &StudioRuntime) -> FeedTicket {
        let opening = runtime.open_model_catalog();
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
            let identity = source.identity();
            let result = {
                let mut state = owner
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                state.identity = Some(identity.clone());
                state.source = Some(source.clone());
                if state.closing || owner.cancel.is_cancelled() {
                    Err(tasks::cancelled())
                } else if identity.feed_id.is_empty()
                    || identity.resource != ProductResource::ModelCatalog
                {
                    Err(StudioError::internal())
                } else {
                    source.ensure_open().map(|()| identity)
                }
            };
            if result.is_err() {
                owner.request_close();
            }
            if published.send(result).is_err() {
                owner.request_close();
            }
            owner.cancel.cancelled().await;
            owner.wait_body().await;
            // Do not release unresolved pins after a failed body delivery. Exit/close owns the
            // retained terminal issue and source until the original responsibility is resolved.
            owner.release_source();
        });
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .task = Some(tasks::retain(task));
        FeedTicket {
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
            .is_some_and(|v| v.feed_id == id)
    }
    pub(super) fn ack(&self, sequence: u64) -> Result<(), StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closing || self.cancel.is_cancelled() {
            return Err(tasks::cancelled());
        }
        state
            .source
            .as_ref()
            .ok_or_else(tasks::cancelled)?
            .ack_through(sequence)?;
        drop(state);
        self.changed.notify_waiters();
        Ok(())
    }
    pub(super) fn send_pending(
        &self,
        send: impl FnOnce(ModelCatalogFrame) -> Result<(), StudioError>,
    ) -> Result<bool, StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closing || self.cancel.is_cancelled() {
            return Err(tasks::cancelled());
        }
        state
            .source
            .as_ref()
            .ok_or_else(tasks::cancelled)?
            .send_pending(send)
    }
    pub(super) fn request_close(&self) {
        {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.closing = true;
            if let Some(source) = &state.source {
                source.request_close();
            }
        }
        self.cancel.cancel();
        self.changed.notify_waiters();
    }
    pub(super) fn record(&self, error: StudioError) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .issues
            .push(tasks::failure(error));
    }
    pub(super) fn body_ended(&self) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .body = BodyPhase::Ended;
        self.changed.notify_waiters();
    }
    async fn wait_body(&self) {
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if !matches!(
                self.state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .body,
                BodyPhase::Active
            ) {
                return;
            }
            changed.await;
        }
    }
    fn release_source(&self) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closing
            && !matches!(state.body, BodyPhase::Active)
            && state.issues.is_empty()
            && state.join_issue.is_none()
        {
            state.source.take();
        }
    }
    pub(super) async fn close(&self) -> Vec<FeedCloseIssue> {
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
                        "feedJoinError",
                        "The original Catalog HTTP opening/producer did not join successfully",
                        CleanupRecovery::Terminal,
                    )
                });
        }
        self.wait_body().await;
        self.release_source();
        self.release_if_clean();
        self.issues(false)
    }
    pub(super) async fn close_report(&self) -> Result<FeedCloseReport, StudioError> {
        let issues = self.close().await;
        let id = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .identity
            .as_ref()
            .map(|v| v.feed_id.clone())
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
                || matches!(state.body, BodyPhase::Active))
        {
            issues.push(tasks::issue(
                "completionPending",
                "Catalog HTTP opening/body has not joined",
                CleanupRecovery::AwaitCompletion,
            ));
        }
        issues
    }
    pub(super) fn release_if_clean(&self) -> bool {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let clean = state.closing
            && !matches!(state.body, BodyPhase::Active)
            && state.source.is_none()
            && state.issues.is_empty()
            && state.join_issue.is_none()
            && state.task.as_ref().is_some_and(tasks::succeeded);
        if clean {
            state.permit.take();
        }
        clean
    }
}
impl FeedTicket {
    pub(super) async fn ready(&mut self) -> Result<ProductFeedIdentity, StudioError> {
        self.ready
            .take()
            .ok_or_else(StudioError::internal)?
            .await
            .map_err(|_| StudioError::internal())?
    }
    pub(super) fn body(&mut self) -> Result<CatalogBody, StudioError> {
        let source = {
            let mut state = self
                .owner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if state.closing || self.owner.cancel.is_cancelled() {
                return Err(tasks::cancelled());
            }
            let source = state.source.as_ref().ok_or_else(tasks::cancelled)?.clone();
            source.claim()?;
            state.body = BodyPhase::Active;
            source
        };
        self.adopted = true;
        Ok(CatalogBody::new(self.owner.clone(), source))
    }
}
impl Drop for FeedTicket {
    fn drop(&mut self) {
        if !self.adopted {
            self.owner.request_close();
        }
    }
}

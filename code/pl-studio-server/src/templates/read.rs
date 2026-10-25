//! An HTTP read belongs to its exact original parent, including a reply lost during opening.
use std::sync::{Arc, Mutex, Weak};

use pl_protocol::products::identity::{ProductReadOrigin, ProductReadScopeIdentity};
use pl_protocol::products::references::AccountTemplatesReadRef;
use pl_protocol::studio::{CleanupRecovery, FeedCloseIssue, FeedCloseOutcome, StudioError};
use pl_studio_runtime::models::StudioAccountTemplatesRead;
use tokio::sync::oneshot;
use tokio_util::sync::CancellationToken;

use super::feed::Transport;
use super::tasks::{self, Completion};

struct State {
    closing: bool,
    identity: Option<ProductReadScopeIdentity>,
    source: Option<Arc<StudioAccountTemplatesRead>>,
    task: Option<Completion>,
    runtime_joined: bool,
    issues: Vec<FeedCloseIssue>,
    join_issue: Option<FeedCloseIssue>,
}

pub(super) struct ReadOwner {
    parent: Weak<Transport>,
    cancel: CancellationToken,
    state: Mutex<State>,
}

pub(super) struct ReadTicket {
    pub owner: Arc<ReadOwner>,
    ready: Option<oneshot::Receiver<Result<ProductReadScopeIdentity, StudioError>>>,
    adopted: bool,
}

impl ReadOwner {
    pub(super) fn new(parent: &Arc<Transport>) -> Arc<Self> {
        Arc::new(Self {
            parent: Arc::downgrade(parent),
            cancel: parent.cancel.child_token(),
            state: Mutex::new(State {
                closing: false,
                identity: None,
                source: None,
                task: None,
                runtime_joined: false,
                issues: Vec::new(),
                join_issue: None,
            }),
        })
    }

    /// Caller has already put this owner in the parent under its admission guard.
    pub(super) fn start(
        self: &Arc<Self>,
        runtime: pl_studio_runtime::StudioRuntime,
        reference: AccountTemplatesReadRef,
        origin: ProductReadOrigin,
    ) -> ReadTicket {
        let (opened, ready) = oneshot::channel();
        let opening = runtime.open_account_templates_read(reference, origin);
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
                } else {
                    source.ensure_open().map(|()| identity)
                }
            };
            if opened.send(result).is_err() {
                owner.request_close();
            }
            owner.cancel.cancelled().await;
            owner.close_source(&source).await;
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

    /// Parent admission and actual runtime query registration share one synchronous boundary.
    pub(super) fn query<F>(
        &self,
        read: impl FnOnce(&StudioAccountTemplatesRead) -> F,
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
                Ok(read(source))
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
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.join_issue.get_or_insert_with(|| {
                tasks::issue(
                    "readJoinError",
                    "A Templates HTTP read task did not join successfully",
                    CleanupRecovery::Terminal,
                )
            });
        }
        // A failed worker must not skip its original runtime queries' close/join.
        let source = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .source
            .clone();
        if let Some(source) = source {
            self.close_source(&source).await;
        }
        self.issues()
    }

    pub(super) fn issues(&self) -> Vec<FeedCloseIssue> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.task.as_ref().is_some_and(tasks::failed) && state.join_issue.is_none() {
            state.join_issue = Some(tasks::issue(
                "readJoinError",
                "A Templates HTTP read task did not join successfully",
                CleanupRecovery::Terminal,
            ));
        }
        let mut issues = state.issues.clone();
        issues.extend(state.join_issue.iter().cloned());
        issues
    }

    pub(super) fn is_finished(&self) -> bool {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.closing
            && state.task.as_ref().is_none_or(tasks::finished)
            && (state.source.is_none() || state.runtime_joined)
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
            && state.task.as_ref().is_none_or(tasks::succeeded)
    }

    async fn close_source(&self, source: &StudioAccountTemplatesRead) {
        let report = source.close().await;
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.runtime_joined = true;
        match report.outcome {
            FeedCloseOutcome::Clean => {
                state.source.take();
            }
            FeedCloseOutcome::Unresolved { issues } => {
                for issue in issues {
                    if !state.issues.contains(&issue) {
                        state.issues.push(issue);
                    }
                }
            }
        }
    }
}

impl ReadTicket {
    pub(super) async fn ready(&mut self) -> Result<ProductReadScopeIdentity, StudioError> {
        let ready = self.ready.take().ok_or_else(StudioError::internal)?;
        ready.await.map_err(|_| StudioError::internal())?
    }

    pub(super) fn adopt(&mut self) -> Result<(), StudioError> {
        self.owner.query(|_| ())?;
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

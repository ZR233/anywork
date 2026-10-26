//! HTTP routing/transport responsibility only. Native scope8/ReadCalls64 remain the sole budgets.
mod routes;

use std::sync::{Arc, Mutex};
use std::time::Instant;

use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use pl_protocol::studio::{
    AttachmentBinaryOpenReply, AttachmentBinaryTarget, CleanupRecovery, FeedCloseIssue,
    FeedCloseOutcome, FeedCloseReport, StudioError, StudioErrorCode, StudioShutdownIssue,
};
use pl_studio_runtime::StudioRuntime;
use pl_studio_runtime::attachment_binary::StudioAttachmentBinaryRead;
use tokio::sync::oneshot;
use tokio_util::sync::CancellationToken;

pub(crate) use routes::router;

type Completion = Shared<BoxFuture<'static, Result<(), Arc<tokio::task::JoinError>>>>;

#[derive(Default)]
struct Registry {
    sealed: bool,
    owners: Vec<Arc<ReadOwner>>,
}

/// Lookup/retention of HTTP handles, not another native registry, read pool or attachment ledger.
#[derive(Default)]
pub(crate) struct AttachmentReads(Mutex<Registry>);

struct ReadState {
    closing: bool,
    reply: Option<AttachmentBinaryOpenReply>,
    source: Option<Arc<StudioAttachmentBinaryRead>>,
    task: Option<Completion>,
    issues: Vec<FeedCloseIssue>,
    join_issue: Option<FeedCloseIssue>,
}

pub(super) struct ReadOwner {
    cancel: CancellationToken,
    state: Mutex<ReadState>,
    cleanup: tokio::sync::Mutex<()>,
}

pub(super) struct Opening {
    owner: Arc<ReadOwner>,
    ready: Option<oneshot::Receiver<Result<AttachmentBinaryOpenReply, StudioError>>>,
    adopted: bool,
}

impl AttachmentReads {
    pub(super) fn open(
        &self,
        runtime: StudioRuntime,
        target: AttachmentBinaryTarget,
    ) -> Result<Opening, StudioError> {
        let mut registry = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if registry.sealed {
            return Err(cancelled());
        }
        registry.owners.retain(|owner| !owner.is_clean());
        let owner = Arc::new(ReadOwner {
            cancel: CancellationToken::new(),
            cleanup: tokio::sync::Mutex::new(()),
            state: Mutex::new(ReadState {
                closing: false,
                reply: None,
                source: None,
                task: None,
                issues: Vec::new(),
                join_issue: None,
            }),
        });
        registry.owners.push(owner.clone());
        // The actual opening worker is installed before releasing the synchronous HTTP fence.
        // Its native opening is never cancelled by a lost response or disconnected handler.
        let (opened, ready) = oneshot::channel();
        let work = owner.clone();
        let task = tokio::spawn(async move {
            let source = match target {
                AttachmentBinaryTarget::Draft { draft_id } => {
                    runtime.open_draft_binary(draft_id).await
                }
                AttachmentBinaryTarget::Thread {
                    thread_id,
                    attachment_id,
                } => runtime.open_thread_binary(thread_id, attachment_id).await,
            };
            let source = match source {
                Ok(source) => Arc::new(source),
                Err(error) => {
                    work.request_close();
                    let _ = opened.send(Err(pl_studio_runtime::studio_error_from_anyhow(error)));
                    return;
                }
            };
            let reply = AttachmentBinaryOpenReply {
                identity: source.identity(),
                byte_length: source.byte_length(),
            };
            let result = {
                let mut state = work
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                state.reply = Some(reply.clone());
                state.source = Some(source.clone());
                if state.closing {
                    Err(cancelled())
                } else {
                    source.ensure_open().map(|()| reply)
                }
            };
            if result.is_err() {
                work.request_close();
            }
            if opened.send(result).is_err() {
                work.request_close();
            }
            work.cancel.cancelled().await;
            work.close_source().await;
        });
        owner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .task = Some(async move { task.await.map_err(Arc::new) }.boxed().shared());
        Ok(Opening {
            owner,
            ready: Some(ready),
            adopted: false,
        })
    }

    pub(super) fn read(&self, id: &str) -> Result<Arc<ReadOwner>, StudioError> {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .owners
            .iter()
            .find(|owner| {
                owner
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .reply
                    .as_ref()
                    .is_some_and(|reply| reply.identity.scope_id == id)
            })
            .cloned()
            .ok_or_else(|| StudioError::not_found("AttachmentRead"))
    }

    pub(crate) fn seal(&self) {
        let mut registry = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        registry.sealed = true;
        for owner in &registry.owners {
            owner.request_close();
        }
    }

    pub(crate) async fn close_for_exit(&self, deadline: Instant) -> Vec<StudioShutdownIssue> {
        self.seal();
        let owners = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .owners
            .clone();
        let reports = futures::future::join_all(owners.iter().map(|owner| async {
            match tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), owner.close())
                .await
            {
                Ok(issues) => issues,
                Err(_) => {
                    let mut issues = owner.issues();
                    issues.push(issue(
                        "readPending",
                        "An attachment HTTP opening/IO/close has not joined",
                        CleanupRecovery::AwaitCompletion,
                    ));
                    issues
                }
            }
        }))
        .await;
        reports
            .into_iter()
            .flatten()
            .map(|issue| issue.diagnostic)
            .collect()
    }
}

impl Opening {
    pub(super) async fn ready(&mut self) -> Result<AttachmentBinaryOpenReply, StudioError> {
        self.ready
            .take()
            .ok_or_else(StudioError::internal)?
            .await
            .map_err(|_| StudioError::internal())?
    }

    pub(super) fn adopt(&mut self) -> Result<(), StudioError> {
        self.owner.query(|_| ())?;
        self.adopted = true;
        Ok(())
    }
}

impl Drop for Opening {
    fn drop(&mut self) {
        if !self.adopted {
            self.owner.request_close();
        }
    }
}

impl ReadOwner {
    pub(super) fn query<F>(
        &self,
        query: impl FnOnce(&StudioAttachmentBinaryRead) -> F,
    ) -> Result<F, StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closing {
            return Err(cancelled());
        }
        let source = state.source.as_ref().ok_or_else(cancelled)?;
        source.ensure_open()?;
        Ok(query(source))
    }

    fn request_close(&self) {
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

    async fn close_source(&self) {
        let _cleanup = self.cleanup.lock().await;
        let source = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .source
            .clone();
        let Some(source) = source else {
            return;
        };
        let report = source.retry_close().await;
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        // A retry replaces recoverable native issues; terminal transport join evidence is separate.
        match report.outcome {
            FeedCloseOutcome::Clean => {
                state.source.take();
                state.issues.clear();
            }
            FeedCloseOutcome::Unresolved { issues } => {
                state.issues = issues;
            }
        }
    }

    async fn close(&self) -> Vec<FeedCloseIssue> {
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
                    issue(
                        "readJoinError",
                        "An attachment HTTP task did not join successfully",
                        CleanupRecovery::Terminal,
                    )
                });
        }
        // Even a failed transport task does not bypass close/join of its native scope.
        self.close_source().await;
        self.issues()
    }

    pub(super) async fn close_report(&self, id: String) -> FeedCloseReport {
        let issues = self.close().await;
        FeedCloseReport {
            feed_id: id,
            outcome: if issues.is_empty() {
                FeedCloseOutcome::Clean
            } else {
                FeedCloseOutcome::Unresolved { issues }
            },
        }
    }

    fn issues(&self) -> Vec<FeedCloseIssue> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state
            .task
            .as_ref()
            .is_some_and(|task| matches!(task.clone().now_or_never(), Some(Err(_))))
        {
            state.join_issue.get_or_insert_with(|| {
                issue(
                    "readJoinError",
                    "An attachment HTTP task did not join successfully",
                    CleanupRecovery::Terminal,
                )
            });
        }
        let mut issues = state.issues.clone();
        issues.extend(state.join_issue.iter().cloned());
        issues
    }

    fn is_clean(&self) -> bool {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.closing
            && state.source.is_none()
            && state.issues.is_empty()
            && state.join_issue.is_none()
            && state
                .task
                .as_ref()
                .is_some_and(|task| matches!(task.clone().now_or_never(), Some(Ok(()))))
    }
}

fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "The original attachment HTTP read is closing",
        false,
    )
}

fn issue(code: &str, message: &str, recovery: CleanupRecovery) -> FeedCloseIssue {
    FeedCloseIssue {
        diagnostic: StudioShutdownIssue {
            stage: "attachmentHttp".into(),
            code: code.into(),
            message: message.into(),
            retryable: recovery != CleanupRecovery::Terminal,
            correlation_id: StudioError::internal().correlation_id,
        },
        recovery,
    }
}

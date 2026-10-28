use std::sync::{Arc, Mutex};

use pl_protocol::products::identity::{ProductFeedIdentity, ProductReadOrigin, ProductResource};
use pl_protocol::studio::{CleanupRecovery, FeedCloseIssue, StudioError};
use pl_studio_runtime::{StudioRuntime, recovery::StudioRecoveryFeed};
use tokio::sync::{Notify, OwnedSemaphorePermit, oneshot};
use tokio_util::sync::CancellationToken;

use super::native::OpenReadKind;
use super::read::{ReadOwner, ReadTicket};
use super::stream::BodyStream;
use super::tasks::{self, Completion};

struct State {
    closing: bool,
    feed: Option<Arc<StudioRecoveryFeed>>,
    reads: Vec<Arc<ReadOwner>>,
    task: Option<Completion>,
    consumer_done: bool,
    issues: Vec<FeedCloseIssue>,
    join_issue: Option<FeedCloseIssue>,
    permit: Option<OwnedSemaphorePermit>,
}

pub(super) struct Transport {
    pub(super) cancel: CancellationToken,
    state: Mutex<State>,
    consumer_changed: Notify,
}

pub(super) struct OpenTicket {
    owner: Arc<Transport>,
    ready: Option<oneshot::Receiver<Result<ProductFeedIdentity, StudioError>>>,
    body: Option<BodyStream>,
    adopted: bool,
}

impl Transport {
    pub(super) fn new(shutdown: &CancellationToken, permit: OwnedSemaphorePermit) -> Arc<Self> {
        Arc::new(Self {
            cancel: shutdown.child_token(),
            consumer_changed: Notify::new(),
            state: Mutex::new(State {
                closing: false,
                feed: None,
                reads: Vec::new(),
                task: None,
                consumer_done: false,
                issues: Vec::new(),
                join_issue: None,
                permit: Some(permit),
            }),
        })
    }

    pub(super) fn install_task(&self, task: Completion) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .task = Some(task);
    }

    pub(super) fn matches(&self, id: &str) -> bool {
        self.runtime_feed()
            .is_some_and(|feed| feed.identity().feed_id == id)
    }

    pub(super) fn install(
        &self,
        feed: Arc<StudioRecoveryFeed>,
    ) -> Result<ProductFeedIdentity, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.feed = Some(feed.clone());
        if state.closing || self.cancel.is_cancelled() {
            return Err(tasks::cancelled());
        }
        feed.claim()?;
        Ok(feed.identity())
    }

    pub(super) fn runtime_feed(&self) -> Option<Arc<StudioRecoveryFeed>> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .feed
            .clone()
    }

    pub(super) fn admit<T>(
        &self,
        work: impl FnOnce() -> Result<T, StudioError>,
    ) -> Result<T, StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closing || self.cancel.is_cancelled() {
            return Err(tasks::cancelled());
        }
        state
            .feed
            .as_ref()
            .ok_or_else(tasks::cancelled)?
            .ensure_open()?;
        work()
    }

    pub(super) fn open_read(
        self: &Arc<Self>,
        runtime: &StudioRuntime,
        kind: OpenReadKind,
    ) -> Result<ReadTicket, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closing || self.cancel.is_cancelled() {
            return Err(tasks::cancelled());
        }
        let feed = state.feed.as_ref().ok_or_else(tasks::cancelled)?;
        feed.ensure_open()?;
        let identity = feed.identity();
        if identity.resource != ProductResource::Recovery {
            return Err(tasks::wrong_scope());
        }
        let origin = ProductReadOrigin {
            owner_epoch: identity.owner_epoch,
            incarnation: identity.incarnation,
        };
        state.reads.retain(|owner| !owner.is_clean());
        let owner = ReadOwner::new(self);
        state.reads.push(owner.clone());
        // Native admission and completion installation happen before this parent guard releases.
        Ok(owner.start(runtime, kind, origin))
    }

    pub(super) fn find_read(&self, id: &str) -> Option<Arc<ReadOwner>> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .reads
            .iter()
            .find(|owner| owner.matches(id))
            .cloned()
    }

    pub(super) fn request_close(&self) {
        let (feed, reads) = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.closing = true;
            (state.feed.clone(), state.reads.clone())
        };
        self.cancel.cancel();
        if let Some(feed) = feed {
            feed.request_close();
        }
        for read in reads {
            read.request_close();
        }
    }

    pub(super) fn consumer_done(&self) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .consumer_done = true;
        self.consumer_changed.notify_waiters();
    }

    pub(super) async fn wait_consumer(&self) {
        loop {
            let changed = self.consumer_changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .consumer_done
            {
                return;
            }
            changed.await;
        }
    }

    pub(super) fn record(&self, issue: FeedCloseIssue) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if !state.issues.contains(&issue) {
            state.issues.push(issue);
        }
    }

    pub(super) async fn close_reads(&self, retry: bool) {
        let reads = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .reads
            .clone();
        for read in &reads {
            read.request_close();
        }
        futures::future::join_all(reads.iter().map(|read| read.close(retry))).await;
    }

    pub(super) async fn close_issues(&self, retry: bool) -> Vec<FeedCloseIssue> {
        self.request_close();
        let task = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .task
            .clone();
        if let Some(task) = task {
            // The registry retains the shared completion and original JoinHandle on cancellation.
            let _ = task.await;
        }
        self.close_reads(retry).await;
        self.wait_consumer().await;
        self.snapshot_issues(false)
    }

    pub(super) fn snapshot_issues(&self, timed_out: bool) -> Vec<FeedCloseIssue> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.task.as_ref().is_some_and(tasks::failed) && state.join_issue.is_none() {
            state.join_issue = Some(tasks::issue(
                "pumpJoinError",
                "The Recovery HTTP producer did not join successfully",
                CleanupRecovery::Terminal,
            ));
        }
        let mut issues = state.issues.clone();
        issues.extend(state.join_issue.iter().cloned());
        for read in &state.reads {
            issues.extend(read.issues(timed_out));
        }
        if !state.consumer_done
            || state
                .task
                .as_ref()
                .is_none_or(|task| !tasks::finished(task))
            || state.reads.iter().any(|read| !read.is_finished())
        {
            issues.push(tasks::issue(
                if timed_out {
                    "deadlineExceeded"
                } else {
                    "completionPending"
                },
                "The Recovery HTTP owner still has unfinished work",
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
        if !state.closing
            || !state.consumer_done
            || !state.issues.is_empty()
            || state.join_issue.is_some()
            || !state.task.as_ref().is_some_and(tasks::succeeded)
            || state.reads.iter().any(|read| !read.is_clean())
        {
            return false;
        }
        // Native feed operations are synchronous; after its seal, the actual producer, all scope
        // queries and the local consumer have joined. Drop is resource release, not join evidence.
        state.feed.take();
        state.reads.clear();
        state.permit.take();
        true
    }
}

impl OpenTicket {
    pub(super) fn new(
        owner: Arc<Transport>,
        ready: oneshot::Receiver<Result<ProductFeedIdentity, StudioError>>,
        body: BodyStream,
    ) -> Self {
        Self {
            owner,
            ready: Some(ready),
            body: Some(body),
            adopted: false,
        }
    }

    pub(super) async fn ready(&mut self) -> Result<ProductFeedIdentity, StudioError> {
        self.ready
            .take()
            .ok_or_else(StudioError::internal)?
            .await
            .map_err(|_| StudioError::internal())?
    }

    pub(super) fn take_body(&mut self) -> Result<BodyStream, StudioError> {
        self.owner.admit(|| Ok(()))?;
        let body = self.body.take().ok_or_else(StudioError::internal)?;
        self.adopted = true;
        Ok(body)
    }
}

impl Drop for OpenTicket {
    fn drop(&mut self) {
        if !self.adopted {
            self.owner.request_close();
        }
    }
}

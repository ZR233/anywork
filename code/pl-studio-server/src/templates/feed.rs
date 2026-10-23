use std::sync::{Arc, Mutex};
use std::time::Instant;

use pl_protocol::products::identity::{ProductFeedIdentity, ProductReadOrigin};
use pl_protocol::products::references::AccountTemplatesReadRef;
use pl_protocol::studio::{CleanupRecovery, FeedCloseIssue, StudioError};
use pl_studio_runtime::StudioRuntime;
use pl_studio_runtime::models::StudioAccountTemplatesFeed;
use tokio::sync::{Notify, OwnedSemaphorePermit, mpsc, oneshot};
use tokio_util::sync::CancellationToken;

use super::read::{ReadOwner, ReadTicket};
use super::stream::{self, BodyStream};
use super::tasks::{self, Completion};

#[derive(Default)]
struct Index { sealed: bool, owners: Vec<Arc<Transport>> }

/// Only HTTP-owned transport/opening indices; no business payload, source history or ACK window.
#[derive(Default)]
pub(crate) struct TemplatesTransports(Mutex<Index>);

struct State {
    closing: bool,
    feed: Option<Arc<StudioAccountTemplatesFeed>>,
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
    pub owner: Arc<Transport>,
    ready: Option<oneshot::Receiver<Result<ProductFeedIdentity, StudioError>>>,
    body: Option<BodyStream>,
    adopted: bool,
}

impl TemplatesTransports {
    pub(super) fn open(&self, runtime: StudioRuntime, shutdown: &CancellationToken,
        permit: OwnedSemaphorePermit) -> Result<OpenTicket, StudioError> {
        let mut index = self.0.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if index.sealed || shutdown.is_cancelled() { return Err(tasks::cancelled()); }
        index.owners.retain(|owner| !owner.release_if_clean());
        let owner = Arc::new(Transport { cancel: shutdown.child_token(),
            state: Mutex::new(State { closing: false, feed: None, reads: Vec::new(), task: None,
                consumer_done: false, issues: Vec::new(), join_issue: None, permit: Some(permit) }),
            consumer_changed: Notify::new() });
        // Admission precedes the runtime opening, pump spawn and any HTTP await.
        index.owners.push(owner.clone());
        let (sender, receiver) = mpsc::channel(3);
        let body = BodyStream::new(receiver, owner.clone());
        let (opened, ready) = oneshot::channel();
        let producer = owner.clone();
        let task = tokio::spawn(async move { stream::run(producer, runtime, sender, opened).await; });
        owner.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner).task = Some(tasks::retain(task));
        Ok(OpenTicket { owner, ready: Some(ready), body: Some(body), adopted: false })
    }

    pub(super) fn feed(&self, id: &str) -> Result<Arc<Transport>, StudioError> {
        self.0.lock().unwrap_or_else(std::sync::PoisonError::into_inner).owners.iter()
            .find(|owner| owner.matches(id)).cloned().ok_or_else(tasks::not_found)
    }

    pub(super) fn read(&self, id: &str) -> Result<Arc<ReadOwner>, StudioError> {
        self.0.lock().unwrap_or_else(std::sync::PoisonError::into_inner).owners.iter()
            .find_map(|owner| owner.find_read(id)).ok_or_else(tasks::not_found)
    }

    pub(super) fn reap(&self) {
        self.0.lock().unwrap_or_else(std::sync::PoisonError::into_inner).owners.retain(|owner| !owner.release_if_clean());
    }

    pub(crate) fn seal(&self) {
        let owners = {
            let mut index = self.0.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            index.sealed = true;
            index.owners.clone()
        };
        for owner in owners { owner.request_close(); }
    }

    pub(crate) async fn close_for_exit(&self, deadline: Instant) -> Vec<pl_protocol::studio::StudioShutdownIssue> {
        self.seal();
        let owners = self.0.lock().unwrap_or_else(std::sync::PoisonError::into_inner).owners.clone();
        let closed = futures::future::join_all(owners.iter().map(|owner| owner.close_issues()));
        let result = tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), closed).await;
        let issues = match result {
            Ok(issues) => issues,
            Err(_) => owners.iter().map(|owner| owner.snapshot_issues(true)).collect(),
        };
        self.reap();
        issues.into_iter().flatten().map(|issue| issue.diagnostic).collect()
    }
}

impl Transport {
    fn matches(&self, id: &str) -> bool {
        self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner).feed.as_ref()
            .is_some_and(|feed| feed.identity().feed_id == id)
    }

    pub(super) fn admit<T>(&self, work: impl FnOnce() -> Result<T, StudioError>) -> Result<T, StudioError> {
        let state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closing || self.cancel.is_cancelled() { return Err(tasks::cancelled()); }
        state.feed.as_ref().ok_or_else(tasks::cancelled)?.ensure_open()?;
        work()
    }

    pub(super) fn install(&self, feed: Arc<StudioAccountTemplatesFeed>) -> Result<ProductFeedIdentity, StudioError> {
        let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        state.feed = Some(feed.clone());
        if state.closing || self.cancel.is_cancelled() { return Err(tasks::cancelled()); }
        // A POST opens and actually claims this one response stream, never an events getter.
        feed.claim()?;
        Ok(feed.identity())
    }

    pub(super) fn runtime_feed(&self) -> Option<Arc<StudioAccountTemplatesFeed>> {
        self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner).feed.clone()
    }

    pub(super) fn open_read(self: &Arc<Self>, runtime: StudioRuntime, reference: AccountTemplatesReadRef)
        -> Result<ReadTicket, StudioError> {
        let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closing || self.cancel.is_cancelled() { return Err(tasks::cancelled()); }
        let feed = state.feed.as_ref().ok_or_else(tasks::cancelled)?;
        feed.ensure_open()?;
        let identity = feed.identity();
        let origin = ProductReadOrigin { owner_epoch: identity.owner_epoch, incarnation: identity.incarnation };
        state.reads.retain(|read| !read.is_clean());
        let owner = ReadOwner::new(self);
        state.reads.push(owner.clone());
        Ok(owner.start(runtime, reference, origin))
    }

    fn find_read(&self, id: &str) -> Option<Arc<ReadOwner>> {
        self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner).reads.iter()
            .find(|read| read.matches(id)).cloned()
    }

    pub(super) fn request_close(&self) {
        let (feed, reads) = {
            let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            state.closing = true;
            (state.feed.clone(), state.reads.clone())
        };
        self.cancel.cancel();
        if let Some(feed) = feed { feed.request_close(); }
        for read in reads { read.request_close(); }
    }

    pub(super) fn consumer_done(&self) {
        self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner).consumer_done = true;
        self.consumer_changed.notify_waiters();
    }

    pub(super) async fn wait_consumer(&self) {
        loop {
            let changed = self.consumer_changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner).consumer_done { return; }
            changed.await;
        }
    }

    pub(super) fn record(&self, issue: FeedCloseIssue) {
        let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if !state.issues.contains(&issue) { state.issues.push(issue); }
    }

    pub(super) async fn close_reads(&self) {
        let reads = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner).reads.clone();
        for read in &reads { read.request_close(); }
        for issues in futures::future::join_all(reads.iter().map(|read| read.close())).await {
                for issue in issues { self.record(issue); }
        }
    }

    pub(super) async fn close_issues(&self) -> Vec<FeedCloseIssue> {
        self.request_close();
        let task = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner).task.clone();
        if let Some(task) = task && task.await.is_err() {
            self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner).join_issue.get_or_insert_with(||
                tasks::issue("pumpJoinError", "The Templates HTTP pump did not join successfully", CleanupRecovery::Terminal));
        }
        self.close_reads().await;
        self.wait_consumer().await;
        self.snapshot_issues(false)
    }

    fn snapshot_issues(&self, timed_out: bool) -> Vec<FeedCloseIssue> {
        let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.task.as_ref().is_some_and(tasks::failed) && state.join_issue.is_none() {
            state.join_issue = Some(tasks::issue("pumpJoinError",
                "The Templates HTTP pump did not join successfully", CleanupRecovery::Terminal));
        }
        let mut issues = state.issues.clone();
        issues.extend(state.join_issue.iter().cloned());
        for read in &state.reads {
            for issue in read.issues() { if !issues.contains(&issue) { issues.push(issue); } }
        }
        let joined = state.task.as_ref().is_none_or(tasks::finished) && state.consumer_done
            && state.reads.iter().all(|read| read.is_finished());
        if !joined {
            issues.push(tasks::issue(if timed_out { "deadlineExceeded" } else { "completionPending" },
                "Templates HTTP transport still owns unfinished work", CleanupRecovery::AwaitCompletion));
        }
        issues
    }

    fn release_if_clean(&self) -> bool {
        let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if !state.closing || !state.consumer_done || !state.issues.is_empty() || state.join_issue.is_some()
            || state.task.as_ref().is_some_and(|task| !tasks::succeeded(task))
            || state.reads.iter().any(|read| !read.is_clean()) { return false; }
        state.feed.take();
        state.reads.clear();
        state.permit.take();
        true
    }
}

impl OpenTicket {
    pub(super) async fn ready(&mut self) -> Result<ProductFeedIdentity, StudioError> {
        self.ready.take().ok_or_else(StudioError::internal)?.await.map_err(|_| StudioError::internal())?
    }

    pub(super) fn take_body(&mut self) -> Result<BodyStream, StudioError> {
        self.owner.admit(|| Ok(()))?;
        let body = self.body.take().ok_or_else(StudioError::internal)?;
        self.adopted = true;
        Ok(body)
    }
}

impl Drop for OpenTicket {
    fn drop(&mut self) { if !self.adopted { self.owner.request_close(); } }
}

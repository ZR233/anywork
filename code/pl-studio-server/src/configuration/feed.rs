use pl_protocol::products::identity::{ProductFeedIdentity, ProductReadOrigin};
use pl_protocol::studio::{CleanupRecovery, FeedCloseIssue, StudioError, StudioShutdownIssue};
use pl_studio_runtime::StudioRuntime;
use std::sync::{Arc, Mutex};
use std::time::Instant;
use tokio::sync::{Notify, OwnedSemaphorePermit, Semaphore, mpsc, oneshot};
use tokio_util::sync::CancellationToken;

use super::command::CommandOwner;
use super::product::{FeedKind, NativeFeed};
use super::read::{OpenReadKind, ReadOwner, ReadTicket};
use super::stream::{self, BodyStream};
use super::tasks::{self, Completion};
use pl_protocol::products::configuration_calls::{ConfigurationCallKind, ConfigurationCallRequest};

#[derive(Default)]
struct Index {
    sealed: bool,
    feeds: Vec<Arc<Transport>>,
    commands: Vec<Arc<CommandOwner>>,
    next_call: u64,
}
#[derive(Default)]
pub(crate) struct ConfigurationTransports(Mutex<Index>);

struct State {
    closing: bool,
    feed: Option<Arc<NativeFeed>>,
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
    pub(super) owner: Arc<Transport>,
    ready: Option<oneshot::Receiver<Result<ProductFeedIdentity, StudioError>>>,
    body: Option<BodyStream>,
    adopted: bool,
}

impl ConfigurationTransports {
    pub(super) fn open(
        &self,
        runtime: StudioRuntime,
        shutdown: &CancellationToken,
        permit: OwnedSemaphorePermit,
    ) -> Result<OpenTicket, StudioError> {
        self.open_product(runtime, shutdown, permit, FeedKind::Configuration)
    }
    pub(super) fn open_profiles(
        &self,
        runtime: StudioRuntime,
        shutdown: &CancellationToken,
        permit: OwnedSemaphorePermit,
    ) -> Result<OpenTicket, StudioError> {
        self.open_product(runtime, shutdown, permit, FeedKind::AgentProfiles)
    }
    fn open_product(
        &self,
        runtime: StudioRuntime,
        shutdown: &CancellationToken,
        permit: OwnedSemaphorePermit,
        kind: FeedKind,
    ) -> Result<OpenTicket, StudioError> {
        let mut index = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if index.sealed || shutdown.is_cancelled() {
            return Err(tasks::cancelled());
        }
        index.feeds.retain(|owner| !owner.release_if_clean());
        let owner = Arc::new(Transport {
            cancel: shutdown.child_token(),
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
            consumer_changed: Notify::new(),
        });
        index.feeds.push(owner.clone());
        // Exactly two Data envelopes plus the unique control. Data pins still occupy native ACK
        // credit, so this transport buffer cannot create a second queue of domain publications.
        let (sender, receiver) = mpsc::channel(3);
        let body = BodyStream::new(receiver, owner.clone());
        let (opened, ready) = oneshot::channel();
        let producer = owner.clone();
        let task = tokio::spawn(async move {
            stream::run(producer, runtime, kind, sender, opened).await;
        });
        owner
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .task = Some(tasks::retain(task));
        Ok(OpenTicket {
            owner,
            ready: Some(ready),
            body: Some(body),
            adopted: false,
        })
    }
    pub(super) fn feed(&self, id: &str) -> Result<Arc<Transport>, StudioError> {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .feeds
            .iter()
            .find(|owner| owner.matches(id))
            .cloned()
            .ok_or_else(tasks::not_found)
    }
    pub(super) fn read(&self, id: &str) -> Result<Arc<ReadOwner>, StudioError> {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .feeds
            .iter()
            .find_map(|owner| owner.find_read(id))
            .ok_or_else(tasks::not_found)
    }
    pub(super) fn begin_command(
        &self,
        runtime: StudioRuntime,
        shutdown: &CancellationToken,
        normal_requests: &Arc<Semaphore>,
        request: ConfigurationCallRequest,
    ) -> Result<Arc<CommandOwner>, StudioError> {
        let mut index = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        // Request lookup, full comparison, acquisition from the original pool, registration and
        // task installation share this guard. Same-request joins work even at full normal credit.
        index.commands.retain(|owner| !owner.is_released());
        if let Some(owner) = index
            .commands
            .iter()
            .find(|owner| owner.operation_id() == request.operation_id())
        {
            if !owner.same_request(&request) {
                return Err(StudioError::new(
                    pl_protocol::studio::StudioErrorCode::Conflict,
                    "This Configuration operation already owns a different frozen request",
                    false,
                ));
            }
            return Ok(owner.clone());
        }
        if index.sealed || shutdown.is_cancelled() {
            return Err(tasks::cancelled());
        }
        let permit = normal_requests
            .clone()
            .try_acquire_owned()
            .map_err(|_| crate::error::ApiError::overloaded().0)?;
        let next_call = index.next_call.checked_add(1).ok_or_else(|| {
            StudioError::new(
                pl_protocol::studio::StudioErrorCode::Overloaded,
                "Configuration call identity space is exhausted",
                false,
            )
        })?;
        let identity =
            pl_protocol::products::configuration_commands::ConfigurationCommandCallIdentity {
                call_id: format!(
                    "configuration-http-call:{}:{next_call}",
                    runtime.owner_epoch()
                ),
                operation_id: request.operation_id().to_owned(),
            };
        index.next_call = next_call;
        let owner = CommandOwner::new(request, identity, permit);
        index.commands.push(owner.clone());
        owner.start(runtime);
        Ok(owner)
    }
    pub(super) fn command(
        &self,
        id: &str,
        kind: ConfigurationCallKind,
    ) -> Result<Arc<CommandOwner>, StudioError> {
        let owner = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .commands
            .iter()
            .find(|owner| owner.call_id() == id)
            .cloned()
            .ok_or_else(tasks::not_found)?;
        owner.require_kind(kind)?;
        Ok(owner)
    }
    pub(super) fn find_command(
        &self,
        operation_id: &str,
        kind: ConfigurationCallKind,
    ) -> Result<Option<Arc<CommandOwner>>, StudioError> {
        let owner = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .commands
            .iter()
            .find(|owner| owner.operation_id() == operation_id && !owner.is_released())
            .cloned();
        if let Some(owner) = &owner {
            owner.require_kind(kind)?;
        }
        Ok(owner)
    }
    pub(super) fn reap(&self) {
        let mut index = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        index.feeds.retain(|owner| !owner.release_if_clean());
        index.commands.retain(|owner| !owner.is_released());
    }
    pub(crate) fn seal(&self) {
        let (feeds, commands) = {
            let mut index = self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            index.sealed = true;
            (index.feeds.clone(), index.commands.clone())
        };
        for feed in feeds {
            feed.request_close();
        }
        for command in commands {
            command.request_close();
        }
    }
    pub(crate) async fn close_for_exit(&self, deadline: Instant) -> Vec<StudioShutdownIssue> {
        self.seal();
        let (feeds, commands) = {
            let index = self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            (index.feeds.clone(), index.commands.clone())
        };
        let closed = async {
            let (feeds, commands) = futures::join!(
                futures::future::join_all(feeds.iter().map(|owner| owner.close_issues())),
                futures::future::join_all(commands.iter().map(|owner| owner.close()))
            );
            feeds
                .into_iter()
                .chain(commands)
                .flatten()
                .map(|issue| issue.diagnostic)
                .collect()
        };
        let issues =
            match tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), closed).await {
                Ok(issues) => issues,
                Err(_) => feeds
                    .iter()
                    .flat_map(|owner| owner.snapshot_issues(true))
                    .chain(commands.iter().flat_map(|owner| owner.issues(true)))
                    .map(|issue| issue.diagnostic)
                    .collect(),
            };
        self.reap();
        issues
    }
}

impl Transport {
    fn matches(&self, id: &str) -> bool {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .feed
            .as_ref()
            .is_some_and(|feed| feed.identity().feed_id == id)
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
    pub(super) fn install(
        &self,
        feed: Arc<NativeFeed>,
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
    pub(super) fn runtime_feed(&self) -> Option<Arc<NativeFeed>> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .feed
            .clone()
    }
    pub(super) fn open_read(
        self: &Arc<Self>,
        runtime: StudioRuntime,
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
        let origin = ProductReadOrigin {
            owner_epoch: identity.owner_epoch,
            incarnation: identity.incarnation,
        };
        kind.check_origin(&origin, identity.resource)?;
        state.reads.retain(|owner| !owner.is_clean());
        let owner = ReadOwner::new(self);
        state.reads.push(owner.clone());
        Ok(owner.start(runtime, kind, origin))
    }
    fn find_read(&self, id: &str) -> Option<Arc<ReadOwner>> {
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
    pub(super) async fn close_reads(&self) {
        let reads = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .reads
            .clone();
        for read in &reads {
            read.request_close();
        }
        // Each original read retains and replaces its own retryable cleanup issues.
        futures::future::join_all(reads.iter().map(|read| read.close())).await;
    }
    pub(super) async fn close_issues(&self) -> Vec<FeedCloseIssue> {
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
                        "pumpJoinError",
                        "Configuration HTTP pump did not join",
                        CleanupRecovery::Terminal,
                    )
                });
        }
        self.close_reads().await;
        self.wait_consumer().await;
        self.snapshot_issues(false)
    }
    fn snapshot_issues(&self, timed_out: bool) -> Vec<FeedCloseIssue> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.task.as_ref().is_some_and(tasks::failed) && state.join_issue.is_none() {
            state.join_issue = Some(tasks::issue(
                "pumpJoinError",
                "Configuration HTTP pump did not join",
                CleanupRecovery::Terminal,
            ));
        }
        let mut issues = state.issues.clone();
        issues.extend(state.join_issue.iter().cloned());
        for read in &state.reads {
            issues.extend(read.issues());
        }
        if !state.consumer_done
            || state
                .task
                .as_ref()
                .is_some_and(|task| !tasks::finished(task))
            || state.reads.iter().any(|read| !read.is_finished())
        {
            issues.push(tasks::issue(
                if timed_out {
                    "deadlineExceeded"
                } else {
                    "completionPending"
                },
                "Configuration HTTP owner still has unfinished work",
                CleanupRecovery::AwaitCompletion,
            ));
        }
        issues
    }
    fn release_if_clean(&self) -> bool {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if !state.closing
            || !state.consumer_done
            || !state.issues.is_empty()
            || state.join_issue.is_some()
            || state
                .task
                .as_ref()
                .is_some_and(|task| !tasks::succeeded(task))
            || state.reads.iter().any(|read| !read.is_clean())
        {
            return false;
        }
        state.feed.take();
        state.reads.clear();
        state.permit.take();
        true
    }
}
impl OpenTicket {
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

//! Transport indices, including opens whose HTTP reply was cancelled. No Recovery values live here.
use std::sync::{Arc, Mutex};
use std::time::Instant;

use pl_protocol::studio::{StudioError, StudioShutdownIssue};
use pl_studio_runtime::StudioRuntime;
use tokio::sync::{OwnedSemaphorePermit, mpsc, oneshot};
use tokio_util::sync::CancellationToken;

use super::feed::{OpenTicket, Transport};
use super::read::ReadOwner;
use super::stream::{self, BodyStream};
use super::tasks;

#[derive(Default)]
struct Index {
    sealed: bool,
    feeds: Vec<Arc<Transport>>,
}

#[derive(Default)]
pub(crate) struct RecoveryTransports(Mutex<Index>);

impl RecoveryTransports {
    pub(super) fn open(
        &self,
        runtime: &StudioRuntime,
        shutdown: &CancellationToken,
        permit: OwnedSemaphorePermit,
    ) -> Result<OpenTicket, StudioError> {
        let mut index = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if index.sealed || shutdown.is_cancelled() {
            return Err(tasks::cancelled());
        }
        index.feeds.retain(|owner| !owner.release_if_clean());
        let owner = Transport::new(shutdown, permit);
        // The same gate seals admission and retains the owner before native open or pump spawn.
        index.feeds.push(owner.clone());
        let opening = runtime.open_recovery();
        // Two Data frames plus the unique control, not a second queue of domain publications.
        let (sender, receiver) = mpsc::channel(3);
        let body = BodyStream::new(receiver, owner.clone());
        let (opened, ready) = oneshot::channel();
        let producer = owner.clone();
        let task = tokio::spawn(async move {
            stream::run(producer, opening, sender, opened).await;
        });
        owner.install_task(tasks::retain(task));
        Ok(OpenTicket::new(owner, ready, body))
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

    pub(super) fn reap(&self) {
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .feeds
            .retain(|owner| !owner.release_if_clean());
    }

    pub(crate) fn seal(&self) {
        let feeds = {
            let mut index = self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            index.sealed = true;
            index.feeds.clone()
        };
        for owner in feeds {
            owner.request_close();
        }
    }

    pub(crate) async fn close_for_exit(&self, deadline: Instant) -> Vec<StudioShutdownIssue> {
        self.seal();
        let feeds = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .feeds
            .clone();
        let closed = futures::future::join_all(feeds.iter().map(|owner| owner.close_issues(false)));
        let issues =
            match tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), closed).await {
                Ok(issues) => issues.into_iter().flatten().collect::<Vec<_>>(),
                Err(_) => feeds
                    .iter()
                    .flat_map(|owner| owner.snapshot_issues(true))
                    .collect(),
            };
        self.reap();
        issues.into_iter().map(|issue| issue.diagnostic).collect()
    }
}

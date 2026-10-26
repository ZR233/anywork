//! The one Models HTTP handle index. It owns no native scope/call pool or business history.
use super::{
    feed::{FeedOwner, FeedTicket},
    native::{Capability, OpenRead},
    read::{ReadOwner, ReadTicket},
    tasks,
};
use pl_protocol::studio::{StudioError, StudioShutdownIssue};
use pl_studio_runtime::StudioRuntime;
use std::{
    sync::{Arc, Mutex},
    time::Instant,
};
use tokio::sync::OwnedSemaphorePermit;
use tokio_util::sync::CancellationToken;

#[derive(Default)]
struct Index {
    sealed: bool,
    feeds: Vec<Arc<FeedOwner>>,
    reads: Vec<Arc<ReadOwner>>,
}
#[derive(Default)]
pub(crate) struct ModelsTransports(Mutex<Index>);
impl ModelsTransports {
    pub(super) fn reap(&self) {
        reap(
            &mut self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner),
        );
    }
    pub(super) fn open_feed(
        &self,
        runtime: &StudioRuntime,
        shutdown: &CancellationToken,
        permit: OwnedSemaphorePermit,
    ) -> Result<FeedTicket, StudioError> {
        let mut index = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if index.sealed || shutdown.is_cancelled() {
            return Err(tasks::cancelled());
        }
        reap(&mut index);
        let owner = FeedOwner::new(shutdown, permit);
        index.feeds.push(owner.clone());
        Ok(owner.start(runtime))
    }
    pub(super) fn open_read(
        &self,
        runtime: &StudioRuntime,
        shutdown: &CancellationToken,
        request: OpenRead,
    ) -> Result<ReadTicket, StudioError> {
        let mut index = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if index.sealed || shutdown.is_cancelled() {
            return Err(tasks::cancelled());
        }
        reap(&mut index);
        let owner = ReadOwner::new(request.kind(), shutdown);
        index.reads.push(owner.clone());
        Ok(owner.start(runtime, request))
    }
    pub(super) fn feed(&self, id: &str) -> Result<Arc<FeedOwner>, StudioError> {
        let index = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(owner) = index.feeds.iter().find(|v| v.matches(id)) {
            return Ok(owner.clone());
        }
        if index.reads.iter().any(|v| v.matches(id)) {
            return Err(tasks::wrong());
        }
        Err(tasks::missing())
    }
    pub(super) fn read(
        &self,
        id: &str,
        capability: Option<Capability>,
    ) -> Result<Arc<ReadOwner>, StudioError> {
        let index = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(owner) = index.reads.iter().find(|v| v.matches(id)) {
            if let Some(capability) = capability {
                owner.require(capability)?;
            }
            return Ok(owner.clone());
        }
        if index.feeds.iter().any(|v| v.matches(id)) {
            return Err(tasks::wrong());
        }
        Err(tasks::missing())
    }
    pub(crate) fn seal(&self) {
        let mut index = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        index.sealed = true;
        for owner in &index.feeds {
            owner.request_close();
        }
        for owner in &index.reads {
            owner.request_close();
        }
    }
    pub(crate) async fn close_for_exit(&self, deadline: Instant) -> Vec<StudioShutdownIssue> {
        self.seal();
        let (feeds, reads) = {
            let index = self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            (index.feeds.clone(), index.reads.clone())
        };
        let cleanup = async {
            let (feeds, reads) = futures::join!(
                futures::future::join_all(feeds.iter().map(|v| v.close())),
                futures::future::join_all(reads.iter().map(|v| v.close(false)))
            );
            feeds.into_iter().chain(reads).flatten().collect::<Vec<_>>()
        };
        let issues = match tokio::time::timeout_at(
            tokio::time::Instant::from_std(deadline),
            cleanup,
        )
        .await
        {
            Ok(issues) => issues,
            Err(_) => feeds
                .iter()
                .flat_map(|v| v.issues(true))
                .chain(reads.iter().flat_map(|v| v.issues(true)))
                .collect(),
        };
        reap(
            &mut self
                .0
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner),
        );
        issues.into_iter().map(|v| v.diagnostic).collect()
    }
}
fn reap(index: &mut Index) {
    // Retire genuinely joined resources, not tombstones of every identity ever issued. A
    // concurrent control may still own its Arc and finish idempotently; a retired ID is NotFound.
    index.feeds.retain(|v| !v.release_if_clean());
    index.reads.retain(|v| !v.is_clean());
}

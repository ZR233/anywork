//! Thread identity/material adapter over the runtime's one scope lifecycle registry.
use std::future::Future;
use std::sync::Arc;

use anyhow::Result;
use pl_protocol::studio::{FeedCloseIssue, FeedCloseReport, StudioError};
use pl_protocol::thread_facets::identity::ReadScopeIdentity;

use super::super::read_calls::ReadCalls;
use super::super::read_scopes::{self, ReadScopeBudgetKey, ReadScopeGroup, ReadScopeOwner, ReadScopeRegistry};
use super::super::residency::ThreadResidencyPins;
use super::super::thread_observation::ThreadFacetLease;

#[derive(Clone)]
pub(in crate::studio::runtime) struct ThreadReadRegistry(ReadScopeRegistry);

impl ThreadReadRegistry {
    pub(in crate::studio::runtime) fn new(registry: ReadScopeRegistry) -> Self { Self(registry) }

    pub(in crate::studio::runtime) fn group(&self, thread_id: &str, epoch: &str, incarnation: u64) -> ThreadReadGroup {
        ThreadReadGroup { group: self.0.group(ReadScopeBudgetKey::Thread(thread_id.to_owned()), incarnation),
            epoch: epoch.to_owned(), incarnation }
    }

    pub(in crate::studio::runtime) async fn close(&self) -> Vec<FeedCloseIssue> {
        self.0.close_threads().await
    }
}

pub(in crate::studio::runtime) struct ThreadReadGroup {
    group: ReadScopeGroup,
    epoch: String,
    incarnation: u64,
}

impl ThreadReadGroup {
    pub(in crate::studio::runtime) fn open<M: Send + Sync + 'static>(&self, revision: u64,
        material: impl FnOnce(ReadScopeIdentity) -> M, lease: ThreadFacetLease, residency: ThreadResidencyPins,
    ) -> Result<(Arc<ThreadReadOwner>, Arc<PinnedMaterial<M>>), StudioError> {
        let identity = ReadScopeIdentity { scope_id: crate::studio::new_id("thread-read"),
            runtime_epoch: self.epoch.clone(), incarnation: self.incarnation, source_revision: revision };
        // Construct the domain value before common admission locks. A failure or panic cannot
        // drop the actual Cold lease under a registry/group guard that its rollback re-enters.
        let source = PinnedSource { material: material(identity.clone()), _lease: lease, _residency: residency };
        let (owner, source) = self.group.open(identity.scope_id.clone(), source)?;
        Ok((Arc::new(ThreadReadOwner { identity, owner }), Arc::new(PinnedMaterial(source))))
    }

    pub(in crate::studio::runtime) fn request_close(&self) { self.group.request_close(); }
    pub(in crate::studio::runtime) async fn close(&self) -> Vec<FeedCloseIssue> { self.group.close().await }
}

struct PinnedSource<M> {
    material: M,
    _lease: ThreadFacetLease,
    _residency: ThreadResidencyPins,
}

pub(in crate::studio::runtime) struct PinnedMaterial<M>(Arc<read_scopes::PinnedMaterial<PinnedSource<M>>>);

impl<M> PinnedMaterial<M> {
    pub(in crate::studio::runtime) fn read<T>(&self, read: impl FnOnce(&M) -> Result<T, StudioError>) -> Result<T> {
        self.0.read(|source| read(&source.material))
    }
}

pub(in crate::studio::runtime) struct ThreadReadOwner {
    identity: ReadScopeIdentity,
    owner: Arc<ReadScopeOwner>,
}

impl ThreadReadOwner {
    pub(in crate::studio::runtime) fn identity(&self) -> ReadScopeIdentity { self.identity.clone() }
    pub(in crate::studio::runtime) fn request_close(&self) { self.owner.request_close(); }
    pub(in crate::studio::runtime) fn ensure_open(&self) -> Result<(), StudioError> { self.owner.ensure_open() }

    pub(in crate::studio::runtime) fn run<T, F>(self: &Arc<Self>, calls: &ReadCalls, read: F)
        -> impl Future<Output = Result<T>> + Send + 'static + use<T, F>
    where T: Send + 'static, F: Future<Output = Result<T>> + Send + 'static {
        self.owner.run(calls, read)
    }

    pub(in crate::studio::runtime) fn release_if_joined(&self) { self.owner.release_if_joined(); }
    pub(in crate::studio::runtime) async fn close(&self) -> FeedCloseReport { self.owner.close().await }
}

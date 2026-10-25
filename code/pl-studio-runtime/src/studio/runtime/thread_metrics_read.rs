//! The concrete immutable metrics identity scope; numeric samples are never copied into it.
use std::future::Future;
use std::sync::Arc;

use anyhow::Result;
pub use pl_protocol::studio::{FeedCloseReport, TextChunk};
use pl_protocol::studio::{StudioError, StudioErrorCode};
pub use pl_protocol::thread_facets::identity::{
    MetricsIdentityRef, ReadScopeIdentity, ThreadFacetStamp,
};
pub use pl_protocol::thread_facets::read::values::MetricsIdentityReadHeader;

use super::StudioRuntime;
use super::read_calls::ReadCalls;
use super::thread_reads::lifetime::{PinnedMaterial, ThreadReadOwner};
use super::thread_reads::scalar::MetricsIdentityMaterial;

/// Owns only the exact immutable identity, original incarnation lease and actual query joins.
/// Closing it does not close the Thread, its metrics listener or another read scope.
pub struct StudioMetricsIdentityRead {
    owner: Arc<ThreadReadOwner>,
    source: Arc<PinnedMaterial<MetricsIdentityMaterial>>,
    calls: ReadCalls,
}

impl StudioMetricsIdentityRead {
    pub fn identity(&self) -> ReadScopeIdentity {
        self.owner.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.owner.ensure_open()
    }

    pub fn header(
        &self,
    ) -> impl Future<Output = Result<MetricsIdentityReadHeader>> + Send + 'static + use<> {
        let source = self.source.clone();
        self.owner.run(&self.calls, async move {
            source.read(MetricsIdentityMaterial::header)
        })
    }

    pub fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> impl Future<Output = Result<TextChunk>> + Send + 'static + use<> {
        let source = self.source.clone();
        self.owner.run(&self.calls, async move {
            source.read(|material| material.text(field_id, offset, max_bytes))
        })
    }

    pub fn request_close(&self) {
        self.owner.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.owner.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.owner.close().await
    }
}

impl Drop for StudioMetricsIdentityRead {
    fn drop(&mut self) {
        self.request_close();
        self.owner.release_if_joined();
    }
}

impl StudioRuntime {
    /// Resolve only the original observation registry. No activation, checkpoint read or latest
    /// origin substitution is permitted. The entire opening is in ReadCalls before this returns.
    pub fn open_metrics_identity_read(
        &self,
        thread_id: String,
        reference: MetricsIdentityRef,
        origin: ThreadFacetStamp,
    ) -> impl Future<Output = Result<StudioMetricsIdentityRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            if runtime.shutdown_committed() {
                return Err(cancelled().into());
            }
            let lease = runtime
                .thread_observations
                .metrics_sources_at(&thread_id, &origin)?
                .ok_or_else(cancelled)?;
            // This admission is already a registered borrow before identity validation can fail.
            let source = lease.source().metrics.identity_at(reference, &origin)?;
            let residency = runtime.residency.pin_many([thread_id]);
            let (owner, source) = lease.open_read(
                origin.revision,
                |identity| MetricsIdentityMaterial::new(identity, source),
                residency,
            )?;
            Ok(StudioMetricsIdentityRead {
                owner,
                source,
                calls: runtime.read_calls.clone(),
            })
        })
    }
}

fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "The original Thread observation is closed or replaced",
        false,
    )
}

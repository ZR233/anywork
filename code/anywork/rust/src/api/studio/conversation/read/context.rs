//! Thread Context scopes use the original typed native read/transport lifecycle.
use super::super::identity::{
    BridgeContextReadRef, BridgeReadScopeIdentity, BridgeThreadFacetStamp,
};
use super::owner::{ExecutionRead, ReadHandle, open_read};
use super::values::{BridgeContextReadHeader, BridgeCostPage};
use crate::api::studio::observation::BridgeTextChunk;
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_studio_runtime::thread_context_read::StudioThreadContextRead;

impl ExecutionRead for StudioThreadContextRead {
    fn identity(&self) -> pl_protocol::thread_facets::identity::ReadScopeIdentity {
        self.identity()
    }
    fn ensure_open(&self) -> Result<(), pl_protocol::studio::StudioError> {
        self.ensure_open()
    }
    fn request_close(&self) {
        self.request_close();
    }
    fn close(
        &self,
    ) -> impl std::future::Future<Output = pl_protocol::studio::FeedCloseReport> + Send {
        self.close()
    }
}

#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeThreadContextRead {
    read: ReadHandle<StudioThreadContextRead>,
}

pub async fn open_thread_context_read(
    thread_id: String,
    reference: BridgeContextReadRef,
    origin: BridgeThreadFacetStamp,
) -> Result<BridgeThreadContextRead, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeThreadContextRead {
        read: open_read(move |runtime| {
            runtime.open_thread_context_read(thread_id, reference, origin)
        })
        .await?,
    })
}

impl BridgeThreadContextRead {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeContextReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioThreadContextRead::header)?
            .await?
            .into())
    }
    pub async fn costs(&self, offset: u64, limit: u32) -> Result<BridgeCostPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.costs(offset, limit))?
            .await?
            .into())
    }
    pub async fn cache_savings(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeCostPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.cache_savings(offset, limit))?
            .await?
            .into())
    }
    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.text(field_id, offset, max_bytes))?
            .await?
            .into())
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.read.request_close();
    }
    pub async fn close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
    pub async fn retry_close(&self) -> Result<BridgeFeedCloseReport, BridgeError> {
        self.read.close().await
    }
}

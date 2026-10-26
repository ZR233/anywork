//! Concrete FRB execution readers: only typed native queries and mechanical DTO conversion.
use super::super::identity::*;
use super::execution::*;
use super::interaction::*;
use super::owner::{ExecutionRead, ReadHandle, open_read};
use crate::api::studio::observation::BridgeTextChunk;
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_studio_runtime::thread_execution_read::{
    StudioActivityRead, StudioInteractionIndexRead, StudioInteractionRead, StudioStorageRead,
    StudioTurnRead,
};

impl ExecutionRead for StudioTurnRead {
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
impl ExecutionRead for StudioInteractionIndexRead {
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
impl ExecutionRead for StudioInteractionRead {
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
impl ExecutionRead for StudioActivityRead {
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
impl ExecutionRead for StudioStorageRead {
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
pub struct BridgeTurnRead {
    read: ReadHandle<StudioTurnRead>,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeInteractionIndexRead {
    read: ReadHandle<StudioInteractionIndexRead>,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeInteractionRead {
    read: ReadHandle<StudioInteractionRead>,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeActivityRead {
    read: ReadHandle<StudioActivityRead>,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeStorageRead {
    read: ReadHandle<StudioStorageRead>,
}

pub async fn open_turn_read(
    thread_id: String,
    reference: BridgeTurnReadRef,
    origin: BridgeThreadFacetStamp,
) -> Result<BridgeTurnRead, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeTurnRead {
        read: open_read(move |runtime| runtime.open_turn_read(thread_id, reference, origin))
            .await?,
    })
}
pub async fn open_interaction_index_read(
    thread_id: String,
    reference: BridgeInteractionIndexRef,
    origin: BridgeThreadFacetStamp,
) -> Result<BridgeInteractionIndexRead, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeInteractionIndexRead {
        read: open_read(move |runtime| {
            runtime.open_interaction_index_read(thread_id, reference, origin)
        })
        .await?,
    })
}
pub async fn open_interaction_read(
    thread_id: String,
    reference: BridgeInteractionReadRef,
    origin: BridgeThreadFacetStamp,
) -> Result<BridgeInteractionRead, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeInteractionRead {
        read: open_read(move |runtime| runtime.open_interaction_read(thread_id, reference, origin))
            .await?,
    })
}
pub async fn open_activity_read(
    thread_id: String,
    reference: BridgeActivityReadRef,
    origin: BridgeThreadFacetStamp,
) -> Result<BridgeActivityRead, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeActivityRead {
        read: open_read(move |runtime| runtime.open_activity_read(thread_id, reference, origin))
            .await?,
    })
}
pub async fn open_storage_read(
    thread_id: String,
    reference: BridgeStorageReadRef,
    origin: BridgeThreadFacetStamp,
) -> Result<BridgeStorageRead, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeStorageRead {
        read: open_read(move |runtime| runtime.open_storage_read(thread_id, reference, origin))
            .await?,
    })
}
pub async fn resolve_interaction_read_ref(
    thread_id: String,
    interaction_id: String,
    revision: u64,
    origin: BridgeThreadFacetStamp,
) -> Result<BridgeInteractionReadRef, BridgeError> {
    let bridge = crate::api::studio::bridge_runtime::installed_bridge()?;
    Ok(bridge
        .studio
        .resolve_interaction_read_ref(thread_id, interaction_id, revision, origin.into())
        .await?
        .into())
}

impl BridgeTurnRead {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeTurnReadHeader, BridgeError> {
        Ok(self.read.query(StudioTurnRead::header)?.await?.into())
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
impl BridgeInteractionIndexRead {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeInteractionIndexReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioInteractionIndexRead::header)?
            .await?
            .into())
    }
    pub async fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeInteractionBriefPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.entries(offset, limit))?
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
impl BridgeInteractionRead {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeInteractionReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioInteractionRead::header)?
            .await?
            .into())
    }
    pub async fn questions(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeQuestionPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.questions(offset, limit))?
            .await?
            .into())
    }
    pub async fn options(
        &self,
        question_index: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeOptionPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.options(question_index, offset, limit))?
            .await?
            .into())
    }
    pub async fn answer_entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeAnswerEntryPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.answer_entries(offset, limit))?
            .await?
            .into())
    }
    pub async fn answer_values(
        &self,
        entry_index: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeAnswerValuePage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.answer_values(entry_index, offset, limit))?
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
impl BridgeActivityRead {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeActivityReadHeader, BridgeError> {
        Ok(self.read.query(StudioActivityRead::header)?.await?.into())
    }
    pub async fn tools(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeActivityToolPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.tools(offset, limit))?
            .await?
            .into())
    }
    pub async fn wait_targets(
        &self,
        tool_index: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeWaitTargetPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.wait_targets(tool_index, offset, limit))?
            .await?
            .into())
    }
    pub async fn latest_wait_targets(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeWaitTargetPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.latest_wait_targets(offset, limit))?
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
impl BridgeStorageRead {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeStorageReadHeader, BridgeError> {
        Ok(self.read.query(StudioStorageRead::header)?.await?.into())
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

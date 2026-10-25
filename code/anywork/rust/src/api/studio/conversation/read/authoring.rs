//! Authoring scopes use the existing typed native read/transport lifecycle and conversions.
use super::super::authoring::BridgePlanDocumentRef;
use super::super::identity::{
    BridgeReadScopeIdentity, BridgeThreadFacetStamp, BridgeTodoReadRef, BridgeWorkflowReadRef,
};
use super::owner::{ExecutionRead, ReadHandle, open_read};
use super::values::*;
use crate::api::studio::observation::BridgeTextChunk;
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_studio_runtime::thread_authoring_read::{
    StudioPlanDocumentRead, StudioTodoRead, StudioWorkflowRead,
};

impl ExecutionRead for StudioTodoRead {
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
impl ExecutionRead for StudioWorkflowRead {
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
impl ExecutionRead for StudioPlanDocumentRead {
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
pub struct BridgeTodoRead {
    read: ReadHandle<StudioTodoRead>,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeWorkflowRead {
    read: ReadHandle<StudioWorkflowRead>,
}
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgePlanDocumentRead {
    read: ReadHandle<StudioPlanDocumentRead>,
}

pub async fn open_todo_read(
    thread_id: String,
    reference: BridgeTodoReadRef,
    origin: BridgeThreadFacetStamp,
) -> Result<BridgeTodoRead, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeTodoRead {
        read: open_read(move |runtime| runtime.open_todo_read(thread_id, reference, origin))
            .await?,
    })
}
pub async fn open_workflow_read(
    thread_id: String,
    reference: BridgeWorkflowReadRef,
    origin: BridgeThreadFacetStamp,
) -> Result<BridgeWorkflowRead, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeWorkflowRead {
        read: open_read(move |runtime| runtime.open_workflow_read(thread_id, reference, origin))
            .await?,
    })
}
pub async fn open_plan_document_read(
    thread_id: String,
    reference: BridgePlanDocumentRef,
    origin: BridgeThreadFacetStamp,
) -> Result<BridgePlanDocumentRead, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgePlanDocumentRead {
        read: open_read(move |runtime| {
            runtime.open_plan_document_read(thread_id, reference, origin)
        })
        .await?,
    })
}
impl BridgeTodoRead {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeTodoReadHeader, BridgeError> {
        Ok(self.read.query(StudioTodoRead::header)?.await?.into())
    }
    pub async fn items(&self, offset: u64, limit: u32) -> Result<BridgeTodoItemPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.items(offset, limit))?
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
impl BridgeWorkflowRead {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeWorkflowReadHeader, BridgeError> {
        Ok(self.read.query(StudioWorkflowRead::header)?.await?.into())
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
impl BridgePlanDocumentRead {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgePlanDocumentReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioPlanDocumentRead::header)?
            .await?
            .into())
    }
    pub async fn document(&self) -> Result<BridgePlanDocumentValue, BridgeError> {
        Ok(self
            .read
            .query(StudioPlanDocumentRead::document)?
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

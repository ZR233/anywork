//! Thread Configuration scopes use the original typed native read/transport lifecycle.
use super::super::identity::{
    BridgeReadScopeIdentity, BridgeThreadConfigurationReadRef, BridgeThreadFacetStamp,
};
use super::owner::{ExecutionRead, ReadHandle, open_read};
use super::values::{BridgeSkillNamePage, BridgeThreadConfigurationReadHeader};
use crate::api::studio::observation::BridgeTextChunk;
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_studio_runtime::thread_configuration_read::StudioThreadConfigurationRead;

impl ExecutionRead for StudioThreadConfigurationRead {
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
pub struct BridgeThreadConfigurationRead {
    read: ReadHandle<StudioThreadConfigurationRead>,
}

pub async fn open_thread_configuration_read(
    thread_id: String,
    reference: BridgeThreadConfigurationReadRef,
    origin: BridgeThreadFacetStamp,
) -> Result<BridgeThreadConfigurationRead, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeThreadConfigurationRead {
        read: open_read(move |runtime| {
            runtime.open_thread_configuration_read(thread_id, reference, origin)
        })
        .await?,
    })
}

impl BridgeThreadConfigurationRead {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeThreadConfigurationReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioThreadConfigurationRead::header)?
            .await?
            .into())
    }
    pub async fn active_skills(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeSkillNamePage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.active_skills(offset, limit))?
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

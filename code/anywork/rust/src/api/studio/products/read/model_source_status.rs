//! The original Catalog status pin, not current metadata or a reconstructed Ready wrapper.
use super::super::identity::{
    BridgeProductReadOrigin, BridgeProductReadScopeIdentity, BridgeProductSourceStatusRef,
};
use super::super::source::BridgeProductSourceStatusReadHeader;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use crate::api::studio::observation::BridgeTextChunk;
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_studio_runtime::models::StudioModelCatalogSourceStatusRead;

impl ModelsRead for StudioModelCatalogSourceStatusRead {
    fn identity(&self) -> pl_protocol::products::identity::ProductReadScopeIdentity {
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
pub struct BridgeModelCatalogSourceStatusReadConnection {
    read: ModelsReadHandle<StudioModelCatalogSourceStatusRead>,
}

pub async fn open_model_catalog_source_status_read(
    reference: BridgeProductSourceStatusRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeModelCatalogSourceStatusReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    Ok(BridgeModelCatalogSourceStatusReadConnection {
        read: open_read(move |runtime| {
            runtime.open_model_catalog_source_status_read(reference, origin)
        })
        .await?,
    })
}
impl BridgeModelCatalogSourceStatusReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    pub async fn header(&self) -> Result<BridgeProductSourceStatusReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioModelCatalogSourceStatusRead::header)?
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
            .query(move |source| source.text(field_id, offset, max_bytes))?
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
        self.read.retry_close().await
    }
}

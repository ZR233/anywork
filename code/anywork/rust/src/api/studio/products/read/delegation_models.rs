//! Exact native pair and immutable local window; no aggregate/current detail fallback.
use super::super::identity::BridgeProductReadScopeIdentity;
use super::delegation_model_values::*;
use super::owner::{ModelsRead, ModelsReadHandle, open_read};
use super::pages::*;
use super::primitives::BridgeTextReadPage;
use crate::api::studio::observation::BridgeTextChunk;
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};
use pl_studio_runtime::models::StudioDelegationModelRead;

impl ModelsRead for StudioDelegationModelRead {
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
pub struct BridgeDelegationModelReadConnection {
    read: ModelsReadHandle<StudioDelegationModelRead>,
    target: BridgeDelegationModelReadTarget,
}
pub async fn open_delegation_model_read(
    target: BridgeDelegationModelReadTarget,
) -> Result<BridgeDelegationModelReadConnection, BridgeError> {
    let target = target.into();
    let read = open_read(move |runtime| runtime.open_delegation_model_read(target)).await?;
    // Capture the native-issued, verified target. Errors/drop still leave the registered owner
    // responsible for a late scope and its real queries; no requested identity is substituted.
    let target = read.query(StudioDelegationModelRead::target)?.into();
    Ok(BridgeDelegationModelReadConnection { read, target })
}
impl BridgeDelegationModelReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }
    #[flutter_rust_bridge::frb(sync)]
    pub fn target(&self) -> BridgeDelegationModelReadTarget {
        self.target.clone()
    }
    pub async fn header(&self) -> Result<BridgeDelegationModelReadHeader, BridgeError> {
        Ok(self
            .read
            .query(StudioDelegationModelRead::header)?
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
    pub async fn strings(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeTextReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.strings(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn type_support(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelTypeSupportReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.type_support(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn type_exclusions(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelTypeExclusionReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.type_exclusions(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn connection_modes(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeConnectionModeReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.connection_modes(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn input_capabilities(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelInputCapabilityReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.input_capabilities(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn input_sources(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelInputSourceReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.input_sources(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn modalities(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelModalityReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.modalities(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn price_tiers(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelPriceTierReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.price_tiers(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn selection_sources(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelSelectionSourceReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.selection_sources(list_id, offset, limit))?
            .await?
            .into())
    }
    pub async fn evaluations(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeAgentEvaluationReadPage, BridgeError> {
        Ok(self
            .read
            .query(move |read| read.evaluations(list_id, offset, limit))?
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

//! Native Catalog reads never fetch current Settings or recreate a lost original reference.
use pl_studio_runtime::models::StudioModelCatalogRead;

use super::super::identity::{
    BridgeProductEntityRef, BridgeProductReadOrigin, BridgeProductReadScopeIdentity,
};
use super::super::references::BridgeModelCatalogReadRef;
use super::model_values::BridgeModelCatalogReadHeader;
use super::owner::{ModelsReadHandle, open_read};
use super::pages::*;
use super::primitives::{BridgeModelSelection, BridgeTextReadPage};
use crate::api::studio::observation::BridgeTextChunk;
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};

/// The registered native owner retains late openings and every actual runtime query until join.
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeModelCatalogReadConnection {
    read: ModelsReadHandle<StudioModelCatalogRead>,
}

/// Open the exact immutable origin/ref without a current-value or old aggregate fallback.
///
/// # Errors
/// Returns typed Cancelled, Unavailable, Superseded or the original shared admission error.
pub async fn open_model_catalog_read(
    reference: BridgeModelCatalogReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeModelCatalogReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    let read = open_read(move |runtime| runtime.open_model_catalog_read(reference, origin)).await?;
    Ok(BridgeModelCatalogReadConnection { read })
}

impl BridgeModelCatalogReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }

    pub async fn header(&self) -> Result<BridgeModelCatalogReadHeader, BridgeError> {
        let query = self.read.query(StudioModelCatalogRead::header)?;
        Ok(query.await?.into())
    }

    pub async fn effort_after_model_selection(
        &self,
        account_id: String,
        model_id: String,
        candidate: Option<String>,
    ) -> Result<Option<String>, BridgeError> {
        let query = self.read.query(move |source| {
            source.effort_after_model_selection(account_id, model_id, candidate)
        })?;
        Ok(query.await?)
    }

    pub async fn first_text_model(&self) -> Result<Option<BridgeModelSelection>, BridgeError> {
        let query = self.read.query(StudioModelCatalogRead::first_text_model)?;
        Ok(query.await?.map(Into::into))
    }

    pub async fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeTextChunk, BridgeError> {
        let query = self
            .read
            .query(move |source| source.text(field_id, offset, max_bytes))?;
        Ok(query.await?.into())
    }

    pub async fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelCatalogEntryPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.entries(offset, limit))?;
        Ok(query.await?.into())
    }

    pub async fn entity(
        &self,
        reference: BridgeProductEntityRef,
    ) -> Result<BridgeModelCatalogEntityRead, BridgeError> {
        let query = self
            .read
            .query(move |source| source.entity(reference.into()))?;
        Ok(query.await?.into())
    }

    pub async fn lookup_account(
        &self,
        account_id: String,
    ) -> Result<Option<BridgeProductEntityRef>, BridgeError> {
        let query = self
            .read
            .query(move |source| source.lookup_account(account_id))?;
        Ok(query.await?.map(Into::into))
    }

    pub async fn accounts(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeAccountCatalogEntryReadPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.accounts(list_id, offset, limit))?;
        Ok(query.await?.into())
    }

    pub async fn models(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelDescriptorReadPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.models(list_id, offset, limit))?;
        Ok(query.await?.into())
    }

    pub async fn type_support(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelTypeSupportReadPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.type_support(list_id, offset, limit))?;
        Ok(query.await?.into())
    }

    pub async fn type_exclusions(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelTypeExclusionReadPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.type_exclusions(list_id, offset, limit))?;
        Ok(query.await?.into())
    }

    pub async fn connection_modes(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeConnectionModeReadPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.connection_modes(list_id, offset, limit))?;
        Ok(query.await?.into())
    }

    pub async fn input_capabilities(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelInputCapabilityReadPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.input_capabilities(list_id, offset, limit))?;
        Ok(query.await?.into())
    }

    pub async fn input_sources(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelInputSourceReadPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.input_sources(list_id, offset, limit))?;
        Ok(query.await?.into())
    }

    pub async fn modalities(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelModalityReadPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.modalities(list_id, offset, limit))?;
        Ok(query.await?.into())
    }

    pub async fn price_tiers(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeModelPriceTierReadPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.price_tiers(list_id, offset, limit))?;
        Ok(query.await?.into())
    }

    pub async fn strings(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeTextReadPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.strings(list_id, offset, limit))?;
        Ok(query.await?.into())
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

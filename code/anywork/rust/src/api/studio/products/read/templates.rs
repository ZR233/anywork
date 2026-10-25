//! Native Templates reads pin the original builtin material; there is no sourceStatus facade.
use pl_studio_runtime::models::StudioAccountTemplatesRead;

use super::super::identity::{
    BridgeProductEntityRef, BridgeProductReadOrigin, BridgeProductReadScopeIdentity,
};
use super::super::references::BridgeAccountTemplatesReadRef;
use super::owner::{ModelsReadHandle, open_read};
use super::pages::*;
use super::primitives::BridgeTextReadPage;
use super::template_values::BridgeAccountTemplatesReadHeader;
use crate::api::studio::observation::BridgeTextChunk;
use crate::api::studio::types::{BridgeError, BridgeFeedCloseReport};

/// The opaque owns the same registered completion from opening through actual query cleanup.
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeAccountTemplatesReadConnection {
    read: ModelsReadHandle<StudioAccountTemplatesRead>,
}

/// Pin the exact original Templates origin/ref, with shared scope/call admission and typed errors.
///
/// # Errors
/// Returns typed Cancelled, Unavailable or the original shared scope/call admission error.
pub async fn open_account_templates_read(
    reference: BridgeAccountTemplatesReadRef,
    origin: BridgeProductReadOrigin,
) -> Result<BridgeAccountTemplatesReadConnection, BridgeError> {
    let reference = reference.into();
    let origin = origin.into();
    let read =
        open_read(move |runtime| runtime.open_account_templates_read(reference, origin)).await?;
    Ok(BridgeAccountTemplatesReadConnection { read })
}

impl BridgeAccountTemplatesReadConnection {
    #[flutter_rust_bridge::frb(sync)]
    pub fn identity(&self) -> BridgeProductReadScopeIdentity {
        self.read.identity()
    }

    pub async fn header(&self) -> Result<BridgeAccountTemplatesReadHeader, BridgeError> {
        let query = self.read.query(StudioAccountTemplatesRead::header)?;
        Ok(query.await?.into())
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
    ) -> Result<BridgeAccountTemplatesEntryPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.entries(offset, limit))?;
        Ok(query.await?.into())
    }

    pub async fn entity(
        &self,
        reference: BridgeProductEntityRef,
    ) -> Result<BridgeAccountTemplatesEntityRead, BridgeError> {
        let query = self
            .read
            .query(move |source| source.entity(reference.into()))?;
        Ok(query.await?.into())
    }

    pub async fn lookup_template(
        &self,
        template_id: String,
    ) -> Result<Option<BridgeProductEntityRef>, BridgeError> {
        let query = self
            .read
            .query(move |source| source.lookup_template(template_id))?;
        Ok(query.await?.map(Into::into))
    }

    pub async fn templates(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeAccountTemplateReadPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.templates(list_id, offset, limit))?;
        Ok(query.await?.into())
    }

    pub async fn catalogs(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BridgeNamedModelCatalogReadPage, BridgeError> {
        let query = self
            .read
            .query(move |source| source.catalogs(list_id, offset, limit))?;
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
        self.read.close().await
    }
}

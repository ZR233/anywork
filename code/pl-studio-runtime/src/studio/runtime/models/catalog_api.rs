use anyhow::Result;
use std::future::Future;

use super::material::ModelReadMaterial;
use super::{
    AccountCatalogEntryReadPage, ConnectionModeReadPage, ModelCatalogEntityRead,
    ModelCatalogEntryPage, ModelDescriptorReadPage, ModelInputCapabilityReadPage,
    ModelInputSourceReadPage, ModelModalityReadPage, ModelPriceTierReadPage,
    ModelTypeExclusionReadPage, ModelTypeSupportReadPage, TextReadPage,
};
use super::{
    FeedCloseReport, ModelCatalogReadHeader, ModelSelection, ProductEntityRef,
    ProductReadScopeIdentity, StudioError, StudioModelCatalogRead, TextChunk,
};

impl StudioModelCatalogRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<ModelCatalogReadHeader>> + Send + 'static + use<> {
        self.scope.query(ModelReadMaterial::catalog_header)
    }
    pub fn effort_after_model_selection(
        &self,
        account_id: String,
        model_id: String,
        candidate: Option<String>,
    ) -> impl Future<Output = Result<Option<String>>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.effort(&account_id, &model_id, candidate.as_deref()))
    }
    pub fn first_text_model(
        &self,
    ) -> impl Future<Output = Result<Option<ModelSelection>>> + Send + 'static + use<> {
        self.scope.query(ModelReadMaterial::first_text_model)
    }
    pub fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> impl Future<Output = Result<TextChunk>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.text(field_id, offset, max_bytes))
    }
    pub fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ModelCatalogEntryPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.catalog_entries(offset, limit))
    }
    pub fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> impl Future<Output = Result<ModelCatalogEntityRead>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.catalog_entity(reference))
    }
    pub fn lookup_account(
        &self,
        account_id: String,
    ) -> impl Future<Output = Result<Option<ProductEntityRef>>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.lookup_account(&account_id))
    }
    pub fn accounts(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<AccountCatalogEntryReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.accounts_page(list_id, offset, limit))
    }
    pub fn models(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ModelDescriptorReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.models_page(list_id, offset, limit))
    }
    pub fn type_support(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ModelTypeSupportReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.type_support_page(list_id, offset, limit))
    }
    pub fn type_exclusions(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ModelTypeExclusionReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.exclusions_page(list_id, offset, limit))
    }
    pub fn connection_modes(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ConnectionModeReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.connections_page(list_id, offset, limit))
    }
    pub fn input_capabilities(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ModelInputCapabilityReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.inputs_page(list_id, offset, limit))
    }
    pub fn input_sources(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ModelInputSourceReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.input_sources_page(list_id, offset, limit))
    }
    pub fn modalities(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ModelModalityReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.modalities_page(list_id, offset, limit))
    }
    pub fn price_tiers(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ModelPriceTierReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.tiers_page(list_id, offset, limit))
    }
    pub fn strings(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<TextReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.strings_page(list_id, offset, limit))
    }
    pub fn request_close(&self) {
        self.scope.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.scope.close().await
    }
}

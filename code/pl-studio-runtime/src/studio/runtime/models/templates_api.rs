use std::future::Future;
use anyhow::Result;

use super::{StudioAccountTemplatesRead, FeedCloseReport, AccountTemplatesReadHeader,
    ProductReadScopeIdentity, ProductEntityRef, StudioError, TextChunk};
use super::{AccountTemplateReadPage, AccountTemplatesEntryPage, AccountTemplatesEntityRead, NamedModelCatalogReadPage,
    ModelDescriptorReadPage, ModelTypeSupportReadPage, ModelTypeExclusionReadPage, ConnectionModeReadPage,
    ModelInputCapabilityReadPage, ModelInputSourceReadPage, ModelModalityReadPage, ModelPriceTierReadPage, TextReadPage};
use super::material::ModelReadMaterial;

impl StudioAccountTemplatesRead {
    pub fn identity(&self) -> ProductReadScopeIdentity { self.scope.identity() }
    pub fn ensure_open(&self) -> Result<(), StudioError> { self.scope.ensure_open() }
    pub fn header(&self) -> impl Future<Output = Result<AccountTemplatesReadHeader>> + Send + 'static + use<> {
        self.scope.query(ModelReadMaterial::templates_header)
    }
    pub fn text(&self, field_id: u64, offset: u64, max_bytes: u32)
        -> impl Future<Output = Result<TextChunk>> + Send + 'static + use<> {
        self.scope.query(move |material| material.text(field_id, offset, max_bytes))
    }
    pub fn entries(&self, offset: u64, limit: u32)
        -> impl Future<Output = Result<AccountTemplatesEntryPage>> + Send + 'static + use<> {
        self.scope.query(move |material| material.template_entries(offset, limit))
    }
    pub fn entity(&self, reference: ProductEntityRef)
        -> impl Future<Output = Result<AccountTemplatesEntityRead>> + Send + 'static + use<> {
        self.scope.query(move |material| material.template_entity(reference))
    }
    pub fn lookup_template(&self, template_id: String)
        -> impl Future<Output = Result<Option<ProductEntityRef>>> + Send + 'static + use<> {
        self.scope.query(move |material| material.lookup_template(&template_id))
    }
    pub fn templates(&self, list_id: u64, offset: u64, limit: u32)
        -> impl Future<Output = Result<AccountTemplateReadPage>> + Send + 'static + use<> {
        self.scope.query(move |material| material.templates_page(list_id, offset, limit))
    }
    pub fn catalogs(&self, list_id: u64, offset: u64, limit: u32)
        -> impl Future<Output = Result<NamedModelCatalogReadPage>> + Send + 'static + use<> {
        self.scope.query(move |material| material.catalogs_page(list_id, offset, limit))
    }
    pub fn models(&self, list_id: u64, offset: u64, limit: u32)
        -> impl Future<Output = Result<ModelDescriptorReadPage>> + Send + 'static + use<> {
        self.scope.query(move |material| material.models_page(list_id, offset, limit))
    }
    pub fn type_support(&self, list_id: u64, offset: u64, limit: u32)
        -> impl Future<Output = Result<ModelTypeSupportReadPage>> + Send + 'static + use<> {
        self.scope.query(move |material| material.type_support_page(list_id, offset, limit))
    }
    pub fn type_exclusions(&self, list_id: u64, offset: u64, limit: u32)
        -> impl Future<Output = Result<ModelTypeExclusionReadPage>> + Send + 'static + use<> {
        self.scope.query(move |material| material.exclusions_page(list_id, offset, limit))
    }
    pub fn connection_modes(&self, list_id: u64, offset: u64, limit: u32)
        -> impl Future<Output = Result<ConnectionModeReadPage>> + Send + 'static + use<> {
        self.scope.query(move |material| material.connections_page(list_id, offset, limit))
    }
    pub fn input_capabilities(&self, list_id: u64, offset: u64, limit: u32)
        -> impl Future<Output = Result<ModelInputCapabilityReadPage>> + Send + 'static + use<> {
        self.scope.query(move |material| material.inputs_page(list_id, offset, limit))
    }
    pub fn input_sources(&self, list_id: u64, offset: u64, limit: u32)
        -> impl Future<Output = Result<ModelInputSourceReadPage>> + Send + 'static + use<> {
        self.scope.query(move |material| material.input_sources_page(list_id, offset, limit))
    }
    pub fn modalities(&self, list_id: u64, offset: u64, limit: u32)
        -> impl Future<Output = Result<ModelModalityReadPage>> + Send + 'static + use<> {
        self.scope.query(move |material| material.modalities_page(list_id, offset, limit))
    }
    pub fn price_tiers(&self, list_id: u64, offset: u64, limit: u32)
        -> impl Future<Output = Result<ModelPriceTierReadPage>> + Send + 'static + use<> {
        self.scope.query(move |material| material.tiers_page(list_id, offset, limit))
    }
    pub fn strings(&self, list_id: u64, offset: u64, limit: u32)
        -> impl Future<Output = Result<TextReadPage>> + Send + 'static + use<> {
        self.scope.query(move |material| material.strings_page(list_id, offset, limit))
    }
    pub fn request_close(&self) { self.scope.request_close(); }
    pub async fn close(&self) -> FeedCloseReport { self.scope.close().await }
    pub async fn retry_close(&self) -> FeedCloseReport { self.scope.close().await }
}

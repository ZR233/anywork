use std::future::Future;

use anyhow::Result;

use super::{
    AgentEvaluationReadPage, ConnectionModeReadPage, DelegationModelReadHeader,
    DelegationModelReadTarget, FeedCloseReport, ModelInputCapabilityReadPage,
    ModelInputSourceReadPage, ModelModalityReadPage, ModelPriceTierReadPage,
    ModelSelectionSourceReadPage, ModelTypeExclusionReadPage, ModelTypeSupportReadPage,
    ProductReadScopeIdentity, StudioDelegationModelRead, StudioError, TextChunk, TextReadPage,
};

impl StudioDelegationModelRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn target(&self) -> DelegationModelReadTarget {
        self.target.clone()
    }

    /// # Errors
    /// Returns Cancelled once this original scope/runtime has been sealed.
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }

    /// # Errors
    /// Returns the original typed field, budget or supervised read error, not partial metadata.
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<DelegationModelReadHeader>> + Send + 'static + use<> {
        let identity = self.scope.identity();
        self.scope
            .query(move |material| material.delegation_header(identity))
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
    pub fn strings(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<TextReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.strings_page(list_id, offset, limit))
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
    pub fn selection_sources(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<ModelSelectionSourceReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.selection_sources_page(list_id, offset, limit))
    }
    pub fn evaluations(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<AgentEvaluationReadPage>> + Send + 'static + use<> {
        self.scope
            .query(move |material| material.evaluations_page(list_id, offset, limit))
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

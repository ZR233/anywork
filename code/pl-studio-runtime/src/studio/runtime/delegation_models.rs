//! Shared typed read boundary for GUI, HTTP and the root's local query tools.
use super::StudioRuntime;
use crate::{
    DelegationModelDetail, DelegationModelDetails, DelegationModelList, GetDelegationModelRequest,
    GetDelegationModelsRequest, ListDelegationModelsRequest,
};
use anyhow::Result;

impl StudioRuntime {
    fn delegation_models(&self) -> crate::thread_assembler::delegation_models::DelegationModels {
        crate::thread_assembler::delegation_models::DelegationModels {
            config: self.config_runtime.clone(),
            store: self.store.clone(),
            performance: self.model_performance.clone(),
        }
    }

    /// Reads the complete qualified candidate inventory without network I/O or settings mutations.
    pub async fn list_delegation_models(
        &self,
        request: ListDelegationModelsRequest,
    ) -> Result<DelegationModelList> {
        self.delegation_models()
            .list_delegation_models(request)
            .await
    }

    /// Reads one exact current account member, including unavailability and recent evaluations.
    pub async fn get_delegation_model(
        &self,
        request: GetDelegationModelRequest,
    ) -> Result<DelegationModelDetail> {
        self.delegation_models().get_delegation_model(request).await
    }
    /// Reads candidate details and recent feedback together, preserving each item's failure.
    pub async fn get_delegation_models(
        &self,
        request: GetDelegationModelsRequest,
    ) -> Result<DelegationModelDetails> {
        self.delegation_models()
            .get_delegation_models(request)
            .await
    }
}

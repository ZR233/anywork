//! Shared typed read boundary for GUI, HTTP and the root's local query tools.
use super::StudioRuntime;
use anyhow::Result;
use pl_protocol::{
    DelegationModelDetail, DelegationModelList, GetDelegationModelRequest,
    ListDelegationModelsRequest,
};

impl StudioRuntime {
    fn delegation_models(&self) -> crate::thread_assembler::delegation_models::DelegationModels {
        crate::thread_assembler::delegation_models::DelegationModels {
            config: self.config_runtime.clone(),
            store: self.store.clone(),
            performance: self.model_performance.clone(),
        }
    }

    /// Reads a bounded qualified candidate page without network I/O or settings mutations.
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
}

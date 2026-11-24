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

#[cfg(test)]
mod projection {
    use crate::config::{ConfigPaths, ConfigRuntime, ConfigStore, StudioConfig};
    use crate::studio::worktree::ThreadWriteBehindWriter;
    use crate::studio::{ProductEventBus, StudioStore};
    use crate::thread_assembler::delegation_models::DelegationModels;
    use crate::{
        DelegationModelResult, GetDelegationModelRequest, GetDelegationModelsRequest,
        ListDelegationModelsRequest, StudioError, StudioErrorCode,
    };
    use pl_model::{
        config::{AccountConfig, AccountId, ModelRouteConfig},
        model::ModelDefinition,
    };

    fn identity(account: &str, model: &str) -> GetDelegationModelRequest {
        GetDelegationModelRequest {
            account_id: account.into(),
            model_id: model.into(),
        }
    }

    struct Projection {
        models: DelegationModels,
        _home: tempfile::TempDir,
    }

    async fn projection() -> anyhow::Result<Projection> {
        let home = tempfile::tempdir()?;
        let mut config = StudioConfig::default_config()?;
        config.models.accounts.clear();
        let account_id = AccountId::new("inventory")?;
        let mut models: Vec<_> = (0..13)
            .map(|index| {
                let mut model = ModelDefinition::compatible(&format!("model-{index:02}"));
                model.base.description = Some(if index == 12 {
                    "界".repeat(300)
                } else {
                    "Synthetic candidate description".into()
                });
                model
            })
            .collect();
        models.push(ModelDefinition::compatible("disabled"));
        let mut account = AccountConfig::from_explicit_models(
            pl_model::protocol::providers::openai::compatible_endpoint(
                "Inventory",
                "http://127.0.0.1:1",
            ),
            models,
        );
        account.set_model_enabled("disabled", false)?;
        config.models.accounts.insert(account_id.clone(), account);
        let mut second = ModelDefinition::compatible("model-00");
        second.base.description = Some("Other account description".into());
        config.models.accounts.insert(
            AccountId::new("second")?,
            AccountConfig::from_explicit_models(
                pl_model::protocol::providers::openai::compatible_endpoint(
                    "Second",
                    "http://127.0.0.1:1",
                ),
                vec![second],
            ),
        );
        for route in config
            .models
            .routes
            .values_mut()
            .chain(config.mode_model_routes.values_mut())
        {
            *route = ModelRouteConfig {
                account_id: account_id.clone(),
                model_id: "model-00".into(),
                effort: None,
            };
        }
        let paths = ConfigPaths::from_config_dir(home.path());
        ConfigStore::new(paths.clone()).save(&config)?;
        let config = ConfigRuntime::initialize(ConfigStore::new(paths))
            .expect("projection config initializes");
        let store = StudioStore::open_memory().await?;
        let events =
            ProductEventBus::new(store.clone(), ThreadWriteBehindWriter::new(store.clone()));
        let performance =
            super::ModelPerformanceOwner::new(store.clone(), events, "projection-test".into());
        Ok(Projection {
            models: DelegationModels {
                config,
                store,
                performance,
            },
            _home: home,
        })
    }

    #[tokio::test]
    async fn inventory_and_batch_projection_keep_identity_order_and_reject_invalid_batches() {
        let projection = projection().await.unwrap();
        let models = &projection.models;
        let inventory = models
            .list_delegation_models(ListDelegationModelsRequest::default())
            .await
            .unwrap();
        assert_eq!(inventory.models.len(), 14);
        assert_eq!(inventory.models[12].model_id, "model-12");
        assert_eq!(
            inventory.models[12]
                .summary
                .as_ref()
                .unwrap()
                .chars()
                .count(),
            240
        );
        assert_eq!(inventory.models[13].account_id, "second");
        assert!(
            inventory
                .models
                .iter()
                .all(|model| model.model_id != "disabled")
        );
        let wire = serde_json::to_value(&inventory).unwrap();
        assert!(wire.get("nextCursor").is_none());
        assert!(wire["models"][0].get("pricing").is_none());
        assert!(wire["models"][0].get("evaluations").is_none());

        let batch = models
            .get_delegation_models(GetDelegationModelsRequest {
                models: vec![
                    identity("second", "model-00"),
                    identity("inventory", "withdrawn"),
                    identity("inventory", "model-00"),
                    identity("inventory", "disabled"),
                    identity("missing", "model-00"),
                ],
            })
            .await
            .unwrap();
        assert_eq!(batch.results.len(), 5);
        for (index, account, available) in [
            (0, "second", true),
            (2, "inventory", true),
            (3, "inventory", false),
        ] {
            let DelegationModelResult::Found {
                account_id,
                model_id,
                detail,
            } = &batch.results[index]
            else {
                panic!("expected detail at {index}")
            };
            assert_eq!(account_id, account);
            assert_eq!(detail.account_id, *account_id);
            assert_eq!(detail.descriptor.model_id, *model_id);
            assert_eq!(detail.available, available);
            assert_eq!(detail.unavailable_reason.is_none(), available);
            assert!(detail.recent_evaluations.is_empty());
            assert_eq!(detail.evaluations.rated_samples, 0);
            assert_eq!(detail.performance.sample_count, 0);
        }
        for index in [1, 4] {
            let DelegationModelResult::Error { error, .. } = &batch.results[index] else {
                panic!("expected missing identity at {index}")
            };
            assert_eq!(error.code, StudioErrorCode::NotFound);
        }

        let rejected = models
            .get_delegation_models(GetDelegationModelsRequest { models: Vec::new() })
            .await
            .unwrap_err();
        assert_eq!(
            rejected.downcast_ref::<StudioError>().unwrap().code,
            StudioErrorCode::InvalidArgument
        );
    }
}

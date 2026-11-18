use anyhow::Result;
use pl_model::{
    config::{AccountConfig, AccountId, ModelRouteConfig},
    model::ModelInfo,
};
use pl_studio_runtime::{
    DelegationModelResult, GetDelegationModelRequest, GetDelegationModelsRequest,
    ListDelegationModelsRequest, StudioErrorCode, StudioHostKind, StudioRuntime,
    StudioRuntimeOptions,
    config::{ConfigPaths, ConfigStore, StudioConfig},
};

async fn environment() -> Result<(tempfile::TempDir, StudioRuntime)> {
    let home = tempfile::tempdir()?;
    let mut config = StudioConfig::default_config()?;
    config.models.accounts.clear();
    let account_id = AccountId::new("inventory")?;
    let mut models: Vec<_> = (0..13)
        .map(|index| {
            let mut model = ModelInfo::compatible(&format!("model-{index:02}"));
            model.description = Some(if index == 12 {
                "界".repeat(300)
            } else {
                "Synthetic candidate description".into()
            });
            model
        })
        .collect();
    models.push(ModelInfo::compatible("disabled"));
    let mut account = AccountConfig::from_explicit_models(
        pl_model::protocol::providers::openai::compatible_endpoint(
            "Inventory",
            "http://127.0.0.1:1",
        ),
        models,
    );
    account.set_model_enabled("disabled", false)?;
    config.models.accounts.insert(account_id.clone(), account);
    let mut second = ModelInfo::compatible("model-00");
    second.description = Some("Other account description".into());
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
    ConfigStore::new(ConfigPaths::from_config_dir(home.path())).save(&config)?;
    let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
        studio_home: Some(home.path().to_path_buf()),
        host: StudioHostKind::Test,
        skill_search: pl_studio_runtime::SkillSearchOptions {
            include_default_user_dir: false,
            additional_dirs: Vec::new(),
        },
        ..StudioRuntimeOptions::desktop()
    })
    .await?;
    Ok((home, runtime))
}

#[tokio::test]
async fn candidate_inventory_returns_every_qualified_model() -> Result<()> {
    let (_home, runtime) = environment().await?;
    let result = runtime
        .list_delegation_models(ListDelegationModelsRequest::default())
        .await;
    runtime.shutdown_runtime().await?;
    let inventory = result?;
    assert_eq!(
        inventory.models.len(),
        14,
        "{:?}",
        inventory
            .models
            .iter()
            .map(|model| (&model.account_id, &model.model_id))
            .collect::<Vec<_>>()
    );
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
    let wire = serde_json::to_value(inventory)?;
    assert!(wire.get("nextCursor").is_none());
    assert!(wire["models"][0].get("pricing").is_none());
    assert!(wire["models"][0].get("evaluations").is_none());
    Ok(())
}

fn identity(account: &str, model: &str) -> GetDelegationModelRequest {
    GetDelegationModelRequest {
        account_id: account.into(),
        model_id: model.into(),
    }
}

#[tokio::test]
async fn batch_details_preserve_identity_order_failures_and_unknown_samples() -> Result<()> {
    let (_home, runtime) = environment().await?;
    let result = runtime
        .get_delegation_models(GetDelegationModelsRequest {
            models: vec![
                identity("second", "model-00"),
                identity("inventory", "withdrawn"),
                identity("inventory", "model-00"),
                identity("inventory", "disabled"),
                identity("missing", "model-00"),
            ],
        })
        .await;
    runtime.shutdown_runtime().await?;
    let batch = result?;
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
        assert_eq!(detail.evaluations.average_quality, None);
        assert_eq!(detail.performance.sample_count, 0);
        assert_eq!(detail.performance.tokens_per_second, None);
        assert_eq!(detail.performance.average_ttft_millis, None);
    }
    for index in [1, 4] {
        let DelegationModelResult::Error { error, .. } = &batch.results[index] else {
            panic!("expected missing identity at {index}")
        };
        assert_eq!(error.code, StudioErrorCode::NotFound);
    }
    Ok(())
}

#[tokio::test]
async fn batch_details_reject_invalid_whole_requests() -> Result<()> {
    let (_home, runtime) = environment().await?;
    for models in [
        vec![],
        vec![identity("inventory", "model-00"); 2],
        (0..11)
            .map(|index| identity("inventory", &format!("model-{index:02}")))
            .collect(),
        vec![identity("", "model-00")],
    ] {
        let error = runtime
            .get_delegation_models(GetDelegationModelsRequest { models })
            .await
            .unwrap_err();
        assert_eq!(
            error
                .downcast_ref::<pl_studio_runtime::StudioError>()
                .unwrap()
                .code,
            StudioErrorCode::InvalidArgument
        );
    }
    let single = runtime
        .get_delegation_models(GetDelegationModelsRequest {
            models: vec![identity("inventory", "model-00")],
        })
        .await;
    runtime.shutdown_runtime().await?;
    assert_eq!(single?.results.len(), 1);
    Ok(())
}

#[expect(
    dead_code,
    reason = "shared production fixtures also serve other integration binaries"
)]
mod support;

#[tokio::test]
async fn profile_tool_reports_frozen_mode_without_automatic_preset_routes() -> Result<()> {
    use pl_studio_runtime::{
        CreateThreadRequest, DelegationMode, NewThreadModelRoute, StudioPromptInput,
        ThreadWorkspaceMode,
    };
    use serde_json::json;
    use support::{Environment, completed_prompt, prompt_step, receipt, text_reply, tool_reply};
    let cases = [
        ("automatic", DelegationMode::Automatic),
        ("profile", DelegationMode::Profile),
    ];
    for (label, mode) in cases {
        let env = Environment::new(
            vec![
                prompt_step(
                    label,
                    0,
                    tool_reply("list_agent_profiles", label, json!({})),
                ),
                prompt_step(
                    label,
                    1,
                    text_reply("catalog received", &format!("done-{label}")),
                ),
            ],
            vec![],
        )
        .await?;
        let result = async {
            let started = env
                .runtime
                .create_thread_command(
                    env.project.id.clone(),
                    CreateThreadRequest {
                        title: Some(label.into()),
                        input: StudioPromptInput {
                            input_id: format!("input-{label}"),
                            text: label.into(),
                            attachment_draft_ids: vec![],
                        },
                        mode: "mode.simple".into(),
                        route: NewThreadModelRoute {
                            account_id: "root-fixture".into(),
                            model_id: support::MODEL.into(),
                            effort: None,
                        },
                        delegation_mode: Some(mode),
                        delegation_preference: None,
                        workspace_mode: ThreadWorkspaceMode::Local,
                    },
                    None,
                )
                .await?;
            completed_prompt(&env.runtime, &started.thread.id, label).await?;
            let catalog = receipt(&env.root_provider, label)?;
            assert_eq!(catalog["delegationMode"], label);
            let profiles = catalog["profiles"].as_array().unwrap();
            assert!(!profiles.is_empty());
            for profile in profiles {
                if profile["binding"]["kind"] == "native" {
                    assert_eq!(
                        profile["binding"].get("route").is_none(),
                        mode == DelegationMode::Automatic
                    );
                }
            }
            Ok(())
        }
        .await;
        env.finish(result).await?;
    }
    Ok(())
}

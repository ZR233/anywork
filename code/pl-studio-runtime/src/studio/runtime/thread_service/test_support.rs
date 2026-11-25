use std::path::Path;

use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
use crate::{StudioHostKind, StudioRuntimeOptions};
use anyhow::Result;
use pl_model::config::{AccountConfig, AccountId, ModelRouteConfig};
use pl_model::model::ModelDefinition;

pub(in crate::studio::runtime) fn options(home: &Path) -> StudioRuntimeOptions {
    StudioRuntimeOptions {
        studio_home: Some(home.to_owned()),
        host: StudioHostKind::Test,
        ..StudioRuntimeOptions::desktop()
    }
}

pub(in crate::studio::runtime) async fn configure(
    home: &Path,
) -> Result<pl_provider_fixture::FixtureServer> {
    // Discovery uses the fixture catalog. The empty inference script rejects any model call.
    let endpoint = pl_provider_fixture::FixtureServer::start(Vec::new()).await?;
    let config = standalone_config(
        endpoint.base_url(),
        ModelDefinition::compatible("standalone-model"),
    )?;
    ConfigStore::new(ConfigPaths::from_config_dir(home)).save(&config)?;
    Ok(endpoint)
}

pub(in crate::studio::runtime) fn standalone_config(
    endpoint: String,
    model: ModelDefinition,
) -> Result<StudioConfig> {
    let model_id = model.base.slug.clone();
    let account_id = AccountId::new("standalone-fixture")?;
    let route = ModelRouteConfig {
        account_id: account_id.clone(),
        model_id,
        effort: None,
    };
    let mut config = StudioConfig::default_config()?;
    config.models.accounts.clear();
    config.models.accounts.insert(
        account_id,
        AccountConfig::from_explicit_models(
            pl_model::protocol::providers::openai::compatible_endpoint(
                "Standalone fixture",
                endpoint,
            ),
            vec![model],
        ),
    );
    for selected in config
        .models
        .routes
        .values_mut()
        .chain(config.mode_model_routes.values_mut())
    {
        *selected = route.clone();
    }
    Ok(config)
}

pub(in crate::studio::runtime) fn request(
    workspace_mode: crate::ThreadWorkspaceMode,
) -> crate::CreateThreadRequest {
    crate::CreateThreadRequest {
        title: Some("standalone".into()),
        input: crate::StudioPromptInput {
            input_id: "standalone-start".into(),
            text: "hello".into(),
            attachment_draft_ids: vec![],
        },
        mode: crate::mode::ThreadModeId::auto().label().into(),
        route: crate::NewThreadModelRoute {
            account_id: "standalone-fixture".into(),
            model_id: "standalone-model".into(),
            effort: None,
        },
        service_tier: None,
        delegation_mode: None,
        delegation_preference: None,
        workspace_mode,
    }
}

pub(super) async fn git_fixture(root: &Path, args: &[&str]) -> Result<String> {
    let output = tokio::process::Command::new("git")
        .args(args)
        .current_dir(root)
        .output()
        .await?;
    anyhow::ensure!(
        output.status.success(),
        "Git fixture {args:?}: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    Ok(String::from_utf8(output.stdout)?)
}

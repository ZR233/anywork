//! Only canonical configuration under the Session-owned synthetic home.
use anyhow::{Context, Result, ensure};
use pl_model::{
    config::{AccountConfig, AccountId, AgentRoleId, ModelRouteConfig},
    model::{ModelInfo, ModelTransportProfile},
    protocol::ProtocolEndpoint,
};
use pl_protocol::studio::{
    AccountModelConnectionUpdate, AccountModelUpdate, AccountSecretUpdate, AccountSettingsUpdate,
};
use pl_protocol::{AgentWorkspaceMode, ThreadModeId};
use pl_provider_fixture::agent_definitions::{
    CHILD_MODEL, COMPACT_MODEL, DISABLED_PROFILE, FUTURE_MODEL, ROOT_MODEL, UNAVAILABLE_MODEL,
    UNAVAILABLE_PROFILE, USER_MODEL_NEW, USER_MODEL_OLD, USER_PROFILE,
};
use pl_studio_runtime::config::{
    ConfigPaths, StudioConfig, UserAgentProfile, save_user_agent_profile,
};
use std::{fs, path::Path};

pub(super) const ROOT_ACCOUNT: &str = "agent-observe-root";
pub(super) const CHILD_ACCOUNT: &str = "agent-observe-child";
pub(super) const EXPLICIT_SYSTEM_AGENT: &str = "reviewer";
const SPARE_MODEL: &str = "agent-unreferenced-anchor";
pub(super) const OLD_ROLE: &str = "Synthetic frozen user Agent role: USER_ROLE_BEFORE_RESTART.";
pub(super) const NEW_ROLE: &str = "Synthetic future user Agent role: USER_ROLE_AFTER_RESTART.";

pub(super) enum ChildAccountUpdate {
    InitializeCredential,
    ExecutableCatalog,
    EmptyCatalog,
}

/// Called once after the shared model fixture starts, before Studio starts.
pub(crate) fn prepare(home: &Path, base_url: &str) -> Result<()> {
    let mut config = StudioConfig::default_config()?;
    let root = AccountId::new(ROOT_ACCOUNT)?;
    let child = AccountId::new(CHILD_ACCOUNT)?;
    let mut compact = model(COMPACT_MODEL);
    compact.auto_compact_token_limit = Some(1);
    let future = model(FUTURE_MODEL);
    config.models.accounts.clear();
    let mut root_model = model(ROOT_MODEL);
    root_model.base_instructions =
        "Synthetic model-owned base: MODEL_BASE_MUST_NOT_REPLACE_AGENT.".into();
    config.models.accounts.insert(
        root.clone(),
        AccountConfig::from_explicit_models(
            ProtocolEndpoint::compatible("Agent observation root", base_url),
            vec![root_model, compact, future],
        ),
    );
    let mut child_config = pl_model::config::builtin_account_catalog()?
        .templates
        .into_iter()
        .find(|template| template.id.as_str() == "openai")
        .context("built-in discovery account missing")?
        .account;
    child_config.name = "Agent observation child".into();
    child_config.base_url = child_base_url(base_url);
    child_config.bearer_token_env = None;
    child_config.bearer_token = None;
    match &mut child_config.catalog {
        pl_model::config::AccountModelCatalogConfig::Bundled {
            additional_models, ..
        } => *additional_models = child_models(true),
        _ => anyhow::bail!("built-in discovery account is not bundled"),
    }
    config.models.accounts.insert(child.clone(), child_config);
    // Leave other system child routes absent to exercise inheritance from mode.simple. Keep one
    // explicit role route so withdrawing its model proves an invalid override never falls back.
    config.models.routes.insert(
        AgentRoleId::new(EXPLICIT_SYSTEM_AGENT.to_string())?,
        ModelRouteConfig {
            account_id: child.clone(),
            model_id: CHILD_MODEL.into(),
            effort: None,
        },
    );
    for (mode, route) in &mut config.mode_model_routes {
        *route = ModelRouteConfig {
            account_id: root.clone(),
            model_id: if mode == &ThreadModeId::task() {
                COMPACT_MODEL
            } else {
                ROOT_MODEL
            }
            .into(),
            effort: None,
        };
    }
    config.runtime.openai_compaction_mode = pl_model::completion::OpenAiCompactionMode::Local;
    config.skills.enabled = false;
    config.skills.user_dir = home.join("skills").to_string_lossy().into_owned();
    config.instructions.developer =
        "Synthetic shared developer context: AGENT_GLOBAL_SOURCE.".into();
    config.validate()?;
    write(home, &config)?;
    let paths = ConfigPaths::from_config_dir(home);
    save_user_agent_profile(
        &paths,
        USER_PROFILE,
        &user(true, OLD_ROLE, USER_MODEL_OLD)?,
        &config,
    )?;
    save_user_agent_profile(
        &paths,
        DISABLED_PROFILE,
        &user(false, "Disabled synthetic role.", USER_MODEL_OLD)?,
        &config,
    )?;
    save_user_agent_profile(
        &paths,
        UNAVAILABLE_PROFILE,
        &user(true, "Withdrawn-model synthetic role.", UNAVAILABLE_MODEL)?,
        &config,
    )?;
    fs::create_dir_all(home.join("skills"))?;
    read(home)?
        .validate()
        .context("round-trip isolated Agent configuration")?;
    Ok(())
}

/// Runs only inside the stopped-server window of the shared restart helper.
/// It changes future configuration, never saved Thread instructions/history.
pub(crate) fn change_future_profiles(home: &Path) -> Result<()> {
    let mut config = read(home)?;
    config.disabled_system_agents.insert("explorer".into());
    for role in ["explorer", "executor", "worktree_executor"] {
        config
            .models
            .routes
            .remove(&AgentRoleId::new(role.to_owned())?);
    }
    let simple = config
        .mode_model_routes
        .get_mut(&ThreadModeId::simple())
        .context("mode.simple route missing during future default update")?;
    simple.model_id = FUTURE_MODEL.into();
    config.validate_declarations()?;
    write(home, &config)?;
    let changed = save_user_agent_profile(
        &ConfigPaths::from_config_dir(home),
        USER_PROFILE,
        &user(true, NEW_ROLE, USER_MODEL_NEW)?,
        &config,
    )?;
    ensure!(changed, "future user Profile did not change");
    Ok(())
}

pub(super) fn has_explicit_system_route(home: &Path, profile_id: &str) -> Result<bool> {
    let config = read(home)?;
    let role = AgentRoleId::new(profile_id.to_string())?;
    Ok(config.models.routes.contains_key(&role))
}

/// Edits the real child account through the public account command. The
/// unreferenced anchor keeps that account valid when no Profile is executable.
pub(super) fn account_update(base_url: &str, update: ChildAccountUpdate) -> AccountSettingsUpdate {
    let (models, secret) = match update {
        // The server's private Secret Service owns this synthetic credential.
        // Keep the initial catalog intact until the explicit withdrawal below.
        ChildAccountUpdate::InitializeCredential => (
            child_models(true),
            AccountSecretUpdate::Replace {
                value: "agent-observe-synthetic-key".into(),
            },
        ),
        ChildAccountUpdate::ExecutableCatalog => {
            (child_models(false), AccountSecretUpdate::Preserve)
        }
        ChildAccountUpdate::EmptyCatalog => {
            (vec![model(SPARE_MODEL)], AccountSecretUpdate::Preserve)
        }
    };
    AccountSettingsUpdate {
        account_id: CHILD_ACCOUNT.into(),
        template_id: Some("openai".into()),
        protocol: pl_model::protocol::ProtocolKind::OpenAi.as_str().into(),
        name: "Agent observation child".into(),
        base_url: child_base_url(base_url),
        secret,
        initial_billing_kind: None,
        model_connection_modes: models
            .iter()
            .map(|model| AccountModelConnectionUpdate {
                model_id: model.model_id.clone(),
                connection_mode: "http".into(),
            })
            .collect(),
        custom_models: models
            .into_iter()
            .map(|model| AccountModelUpdate {
                model_id: model.model_id,
                display_name: model.display_name,
                wire_api: "responses".into(),
                context_window: model.context_window,
                max_output_tokens: model.max_output_tokens,
            })
            .collect(),
        model_auto_compact_limits: Vec::new(),
    }
}

fn child_base_url(base_url: &str) -> String {
    format!("{}/openai", base_url.trim_end_matches('/'))
}

fn model(id: &str) -> ModelInfo {
    let mut model = ModelInfo::compatible(id);
    model.capabilities.tools.function_calling = true;
    model.context_window = Some(256_000);
    model.max_context_window = Some(256_000);
    // The real list_agent_profiles result includes full system role bodies.
    // Keep that real tool result intact rather than accepting a truncated JSON
    // preview as an executable-catalog observation.
    model.truncation_policy.limit = 512_000;
    model
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    model.binding.request.api_model = None;
    model
}

fn child_models(include_withdrawn: bool) -> Vec<ModelInfo> {
    let mut models = [CHILD_MODEL, USER_MODEL_OLD, USER_MODEL_NEW, SPARE_MODEL]
        .into_iter()
        .map(model)
        .collect::<Vec<_>>();
    if include_withdrawn {
        models.push(model(UNAVAILABLE_MODEL));
    }
    models
}

fn user(enabled: bool, role: &str, model: &str) -> Result<UserAgentProfile> {
    Ok(UserAgentProfile {
        enabled,
        display_name: "Observation user Agent".into(),
        description: "Synthetic Agent assembly observation".into(),
        when_to_use: "Explicit opt-in Agent observation only".into(),
        system_instructions: role.into(),
        account_id: AccountId::new(CHILD_ACCOUNT)?,
        model_id: model.into(),
        effort: None,
        workspace_mode: AgentWorkspaceMode::Directory,
    })
}

fn read(home: &Path) -> Result<StudioConfig> {
    let path = home.join("config.toml");
    toml::from_str(&fs::read_to_string(&path).with_context(|| format!("read {}", path.display()))?)
        .context("decode isolated Agent config")
}

fn write(home: &Path, config: &StudioConfig) -> Result<()> {
    fs::write(home.join("config.toml"), toml::to_string_pretty(config)?)
        .context("write isolated Agent config")
}

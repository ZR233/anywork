//! Synthetic account inventory only; selection is left to production queries.

use super::super::*;
use pl_model::config::{AgentRoleId, ModelRouteConfig};
use pl_model::model::{
    ModelParameter, ModelPricing, ParameterWire, TokenPriceTier, WireAssignment,
};
use pl_protocol::{BillingKind, DelegationSettings};
use pl_provider_fixture::delegation::{OTHER_MODEL, SHARED_MODEL};
use pl_studio_runtime::config::UserAgentProfile;

pub(super) fn write(home: &Path, ready: &FixtureReady) -> Result<()> {
    let mut config = fixture_config(ready, ModelTransportProfile::responses_http())?;
    let environment_id = home
        .parent()
        .and_then(Path::file_name)
        .and_then(|name| name.to_str())
        .context("synthetic environment has no stable UTF-8 identity")?;
    let prefix = format!("delegation-{}-{environment_id}", std::process::id());
    let a_id = AccountId::new(format!("{prefix}-a"))?;
    let b_id = AccountId::new(format!("{prefix}-b"))?;
    let mut a_models = vec![model(SHARED_MODEL), model(OTHER_MODEL)];
    for index in 0..10 {
        a_models.push(model(&format!("delegation-candidate-{index:02}")));
    }
    let disabled = model("delegation-disabled");
    let mut no_text = model("delegation-no-text");
    no_text.capabilities.output = vec![ModelModality::Image];
    let mut unknown = model("delegation-unknown-context");
    unknown.context_window = None;
    unknown.max_context_window = None;
    let mut no_tools = model("delegation-no-tools");
    no_tools.capabilities.tools.function_calling = false;
    a_models.extend([disabled, no_text, unknown, no_tools]);
    let mut a = AccountConfig::from_explicit_models(
        ProtocolEndpoint::compatible(
            "Delegation synthetic account A",
            format!("{}/delegation-a", ready.base_url),
        ),
        a_models,
    );
    a.billing_kind = Some(BillingKind::Subscription);
    a.set_model_enabled("delegation-disabled", false)?;
    let mut b = AccountConfig::from_explicit_models(
        ProtocolEndpoint::compatible(
            "Delegation synthetic account B — identical model ID, independent endpoint",
            format!("{}/delegation-b", ready.base_url),
        ),
        vec![model(SHARED_MODEL)],
    );
    b.billing_kind = Some(BillingKind::NoCharge);
    // Official-protocol account without a key is deliberately not admitted.
    // It is loopback-only and must never reach a completion endpoint.
    let mut no_credentials = AccountConfig::from_explicit_models(
        ProtocolEndpoint::openai(Some(format!("{}/delegation-b", ready.base_url))),
        vec![model("delegation-no-credentials")],
    );
    no_credentials.name = "Delegation missing credentials (must stay unavailable)".into();
    config.models.accounts.clear();
    config.models.accounts.insert(a_id.clone(), a);
    config.models.accounts.insert(b_id.clone(), b);
    config
        .models
        .accounts
        .insert(AccountId::new(format!("{prefix}-missing"))?, no_credentials);
    config.models.routes.insert(
        AgentRoleId::new("explorer")?,
        ModelRouteConfig {
            account_id: a_id.clone(),
            model_id: OTHER_MODEL.into(),
            effort: Some(pl_model::config::ReasoningEffort::new("high")),
        },
    );
    config.models.routes.insert(
        AgentRoleId::new("reviewer")?,
        ModelRouteConfig {
            account_id: b_id,
            model_id: SHARED_MODEL.into(),
            effort: None,
        },
    );
    for route in config.mode_model_routes.values_mut() {
        route.account_id = a_id.clone();
        route.model_id = SHARED_MODEL.into();
        route.effort = None;
    }
    config.delegation = DelegationSettings::default();
    // A disabled *old fixed route* must not erase an otherwise enabled role
    // from automatic dispatch. This is a real Profile config, not a new router.
    let profile = UserAgentProfile {
        enabled: true,
        display_name: "Delegation role with unavailable fixed route".into(),
        description: "Synthetic manual observation role".into(),
        when_to_use: "Automatic mode only; its fixed route is intentionally disabled".into(),
        system_instructions:
            "Read-only synthetic delivery. Do not change files or invoke external services.".into(),
        account_id: a_id,
        model_id: "delegation-disabled".into(),
        effort: None,
        workspace_mode: pl_protocol::AgentWorkspaceMode::Unrestricted,
    };
    let agents = home.join("agents");
    fs::create_dir_all(&agents)?;
    fs::write(
        agents.join("obsolete_route.toml"),
        toml::to_string_pretty(&profile)?,
    )?;
    persist_config(home, &config)
}

fn model(id: &str) -> ModelInfo {
    let mut model = ModelInfo::compatible(id);
    model.display_name = if id == SHARED_MODEL {
        "Delegation same-name model · 长名称用于窄窗口身份核对".into()
    } else {
        id.into()
    };
    model.description = Some("DELEGATION_INVENTORY_ONLY: custom synthetic model; price, suitability and external benchmarks are unverified.".into());
    model.context_window = Some(1_000_000);
    model.max_context_window = Some(1_000_000);
    model.pricing = ModelPricing::Unknown;
    if matches!(id, SHARED_MODEL | OTHER_MODEL) {
        // Synthetic reference prices, never an inferred quota or real supplier tariff.
        model.pricing = ModelPricing::published_at(
            "USD",
            vec![TokenPriceTier::flat(2.0, 8.0, Some(0.5), Some(3.0))],
            "https://example.invalid/synthetic-reference-prices",
            1,
        );
    }
    model
        .binding
        .set_transport(ModelTransportProfile::responses_http());
    if id == OTHER_MODEL {
        model.context_window = None;
        model.auto_compact_token_limit = Some(700_000);
        model.capabilities.reasoning = true;
        model.parameters.push(ModelParameter {
            name: "effort".into(),
            label: None,
            default: Some("low".into()),
            candidates: vec!["low".into(), "high".into()],
            wire: ["low", "high"]
                .into_iter()
                .map(|effort| {
                    (
                        effort.into(),
                        ParameterWire {
                            set: vec![WireAssignment {
                                path: "reasoning.effort".into(),
                                value: effort.into(),
                            }],
                            remove: Vec::new(),
                        },
                    )
                })
                .collect(),
        });
    }
    model
}

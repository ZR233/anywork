//! Immutable dispatch provenance. The selected child route belongs only to its saved Profile.
use anyhow::{Result, ensure};
use pl_core::{
    context::OpaquePayload,
    thread::{ThreadSnapshot, extensions::ExtensionRecord},
};
use pl_protocol::{DelegationMode, DelegationPreference, DelegationSettings};

pub(crate) const EXTENSION: &str = "studio.delegation";
const FORMAT: &str = "pl.studio.delegation";

pub(crate) fn encode(selection: DelegationSettings) -> Result<OpaquePayload> {
    Ok(OpaquePayload::new(
        FORMAT,
        1,
        serde_json::to_string(&selection)?,
    )?)
}

pub(crate) fn saved(state: &ThreadSnapshot) -> Result<Option<DelegationSettings>> {
    state
        .extensions
        .get(EXTENSION)
        .map(|record| decode(&record.payload))
        .transpose()
}

pub(crate) fn decode(payload: &OpaquePayload) -> Result<DelegationSettings> {
    ensure!(
        payload.format() == FORMAT && payload.version() == 1,
        "unsupported saved delegation encoding"
    );
    Ok(serde_json::from_str(payload.content())?)
}

/// Invoked only by the versioned history recovery writer, never by default inheritance.
pub(crate) fn migrate(state: &mut ThreadSnapshot) -> Result<()> {
    if saved(state)?.is_none() {
        state.extension_sequence = state
            .extension_sequence
            .checked_add(1)
            .ok_or_else(|| anyhow::anyhow!("delegation extension sequence overflow"))?;
        state.extensions.insert(
            EXTENSION.into(),
            ExtensionRecord {
                revision: state.extension_sequence,
                payload: encode(DelegationSettings::default())?,
            },
        );
    }
    Ok(())
}

pub(crate) fn profile_model(
    profile: &pl_protocol::AgentProfileSnapshot,
) -> pl_protocol::studio::NewThreadModelRoute {
    pl_protocol::studio::NewThreadModelRoute {
        account_id: profile.account_id.clone(),
        model_id: profile.model_id.clone(),
        effort: profile.effort.clone(),
    }
}

/// Product admission uses the model owner's canonical selection, effort and connection rules.
/// Credentials are checked without a network probe; OpenAI-compatible accounts explicitly allow
/// credential-free local endpoints. All child query/spawn/continuation paths use this result.
pub(crate) fn resolve_child_route(
    config: &crate::StudioConfig,
    profile: &pl_protocol::AgentProfileSnapshot,
) -> crate::Result<pl_model::config::ResolvedModelRoute> {
    resolve_child_selection(
        config,
        pl_model::config::AgentRoleId::new(profile.profile_id.clone())?,
        &crate::studio::model_route::profile_route(profile)
            .map_err(|error| crate::PureError::ConfigError(error.to_string()))?,
    )
}

pub(crate) fn resolve_child_selection(
    config: &crate::StudioConfig,
    role: pl_model::config::AgentRoleId,
    selector: &pl_model::config::ModelRouteConfig,
) -> crate::Result<pl_model::config::ResolvedModelRoute> {
    let route = config.models.resolve_route(role, selector)?;
    validate_credential(&route)?;
    if !route.model.capabilities.tools.function_calling {
        return Err(crate::PureError::ConfigError(
            "child model requires tool calling".into(),
        ));
    }
    Ok(route)
}

/// Catalog queries and immutable Models capture use the same original candidate admission.
/// A captured catalog retains only its qualification outcome, never this resolved route.
pub(crate) fn resolve_catalog_selection(
    config: &crate::StudioConfig,
    account_id: &pl_model::config::AccountId,
    entry: &pl_model::config::AccountModelEntry,
) -> crate::Result<pl_model::config::ResolvedModelRoute> {
    let effort = entry
        .model
        .default_effort()
        .or_else(|| entry.model.supported_efforts().first().cloned());
    resolve_child_selection(
        config,
        crate::StudioRole::Executor.id(),
        &pl_model::config::ModelRouteConfig {
            account_id: account_id.clone(),
            model_id: entry.model.model_id.clone(),
            effort: effort.map(pl_model::config::ReasoningEffort::new),
        },
    )
}

pub(crate) fn validate_credential(
    route: &pl_model::config::ResolvedModelRoute,
) -> crate::Result<()> {
    if route.endpoint.protocol != pl_model::protocol::ProtocolKind::OpenAiCompatible
        && route
            .endpoint
            .bearer_token
            .as_deref()
            .is_none_or(|token| token.trim().is_empty())
    {
        return Err(crate::PureError::ConfigError(
            "model account credential is unavailable".into(),
        ));
    }
    Ok(())
}

pub(crate) fn preference_prompt(selection: DelegationSettings) -> Option<&'static str> {
    if selection.mode == DelegationMode::Profile {
        return None;
    }
    Some(match selection.preference {
        DelegationPreference::Economy => {
            "自动分发偏好：经济。在满足能力与交付质量的前提下，降低整项任务的预计边际成本；综合价格、缓存、套餐及返修风险。未知价格不等于免费，订阅不等于无限使用。先查询候选，再按需查看详情，派发时显式选择模型；不得改变主代理模型、权限、预算或验收要求。"
        }
        DelegationPreference::Balanced => {
            "自动分发偏好：平衡。综合任务适配、交付质量、边际成本与总耗时选择模型，并考虑返修风险。未知资料保持未知。先查询候选，再按需查看详情，派发时显式选择模型；不得改变主代理模型、权限、预算或验收要求。"
        }
        DelegationPreference::Fast => {
            "自动分发偏好：快速。在满足交付质量的前提下缩短整项任务的总完成时间，综合首字延迟、吞吐、任务复杂度及返修风险，而非只看最高吞吐。先查询候选，再按需查看详情，派发时显式选择模型；不得跳过独立审查或改变主代理模型、权限、预算与验收要求。"
        }
    })
}

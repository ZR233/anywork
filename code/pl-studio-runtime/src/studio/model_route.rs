//! Durable model selectors are separate from the physical provider binding resolved at runtime.

use anyhow::{Context, Result, bail};
use pl_core::{
    context::OpaquePayload,
    thread::{ThreadSnapshot, extensions::ExtensionRecord},
};
use pl_model::config::{AccountId, ModelRouteConfig, ReasoningEffort};

pub(crate) const MODEL_ROUTE_EXTENSION: &str = "studio.model-route";
pub(crate) const BOT_OWNER_EXTENSION: &str = "studio.bot-owner";

pub(crate) fn encode_bot_owner(bot_id: &str) -> Result<OpaquePayload> {
    Ok(OpaquePayload::new(
        "pl.studio.bot-owner",
        1,
        serde_json::to_string(bot_id)?,
    )?)
}

pub(crate) fn bot_owner(state: &ThreadSnapshot) -> Result<Option<String>> {
    state
        .extensions
        .get(BOT_OWNER_EXTENSION)
        .map(|value| {
            anyhow::ensure!(
                value.payload.format() == "pl.studio.bot-owner" && value.payload.version() == 1,
                "unsupported bot owner encoding"
            );
            Ok(serde_json::from_str(value.payload.content())?)
        })
        .transpose()
}

/// 合并运行期绑定与该会话已冻结的 owner 事实。
///
/// 两个来源都按当前格式版本解码，并用 bot 模块的 canonical 校验器验证 bot ID；两者同时
/// 存在时必须指向同一个 bot。读取失败、ID 非法或冲突都返回错误，绝不以“扩展存在”或
/// “没有绑定”推断渠道。
pub(crate) fn verified_bot_owner(
    live: Option<&str>,
    saved: Option<&ThreadSnapshot>,
) -> Result<Option<String>> {
    let frozen = saved.map(bot_owner).transpose()?.flatten();
    if let Some(bot_id) = &frozen {
        crate::bots::validate_bot_id(bot_id)
            .map_err(|error| anyhow::anyhow!("invalid saved bot ownership `{bot_id}`: {error}"))?;
    }
    if let Some(bot_id) = live {
        crate::bots::validate_bot_id(bot_id)
            .map_err(|error| anyhow::anyhow!("invalid active bot binding `{bot_id}`: {error}"))?;
    }
    match (live, frozen) {
        (Some(live), Some(frozen)) if live != frozen => {
            bail!("saved bot ownership conflicts with the active bot binding")
        }
        (Some(live), _) => Ok(Some(live.to_owned())),
        (None, frozen) => Ok(frozen),
    }
}
pub(crate) const MODEL_ROUTE_FORMAT: &str = "pl.studio.model-route";
pub(crate) const AGENT_PROFILE_EXTENSION: &str = "studio.agent-profile";
pub(crate) const AGENT_PROFILE_FORMAT: &str = "pl.studio.agent-profile";
const FORMAT_VERSION: u32 = 2;
pub(crate) mod migration;

#[derive(Debug, Clone)]
pub(crate) struct SavedModelRoute {
    pub route: ModelRouteConfig,
}

pub(crate) fn encode(route: &ModelRouteConfig) -> Result<OpaquePayload> {
    Ok(OpaquePayload::new(
        MODEL_ROUTE_FORMAT,
        FORMAT_VERSION,
        serde_json::to_string(route)?,
    )?)
}

pub(crate) fn decode(payload: &OpaquePayload) -> Result<ModelRouteConfig> {
    decode_route_payload(payload, MODEL_ROUTE_FORMAT, "model route")
}

pub(crate) fn saved(state: &ThreadSnapshot) -> Result<Option<SavedModelRoute>> {
    state
        .extensions
        .get(MODEL_ROUTE_EXTENSION)
        .map(|record| {
            Ok(SavedModelRoute {
                route: decode(&record.payload)?,
            })
        })
        .transpose()
}

pub(crate) fn encode_profile(profile: &pl_protocol::AgentProfileSnapshot) -> Result<OpaquePayload> {
    Ok(OpaquePayload::new(
        AGENT_PROFILE_FORMAT,
        FORMAT_VERSION,
        serde_json::to_string(profile)?,
    )?)
}

pub(crate) fn saved_profile(
    state: &ThreadSnapshot,
) -> Result<Option<(pl_protocol::AgentProfileSnapshot, u64)>> {
    state
        .extensions
        .get(AGENT_PROFILE_EXTENSION)
        .map(|record| {
            Ok((
                decode_profile_payload(&record.payload, AGENT_PROFILE_FORMAT, "Agent Profile")?,
                record.revision,
            ))
        })
        .transpose()
}

/// The Profile frozen at creation is the only Agent identity a restored child may consume.
///
/// A missing snapshot fails with the original checkpoint preserved: rebuilding it from the
/// current catalog, an empty instruction body or a synthesized revision would fabricate an
/// executable Agent that the session never had.
pub(crate) fn required_saved_profile(
    state: &ThreadSnapshot,
    child_id: &str,
) -> Result<pl_protocol::AgentProfileSnapshot> {
    saved_profile(state)?
        .map(|(profile, _)| profile)
        .ok_or_else(|| {
            anyhow::anyhow!(
                "child {child_id} has no frozen Agent Profile; checkpoint and history preserved"
            )
        })
}

pub(crate) fn profile_route(
    profile: &pl_protocol::AgentProfileSnapshot,
) -> Result<ModelRouteConfig> {
    Ok(ModelRouteConfig {
        account_id: AccountId::new(profile.account_id.clone())?,
        model_id: profile.model_id.clone(),
        effort: profile.effort.clone().map(ReasoningEffort::new),
    })
}

/// Structural placeholder for history-only restoration. It is never installed as an executable
/// model and is never a directory/query identity; saved selectors/Profile remain authoritative.
/// In particular, withdrawal must not re-import an identically named bundled model.
pub(crate) fn unavailable_placeholder(
    config: &crate::StudioConfig,
    role: pl_model::config::AgentRoleId,
    selector: &ModelRouteConfig,
) -> Result<pl_model::config::ResolvedModelRoute> {
    let account = config
        .models
        .accounts
        .get(&selector.account_id)
        .context("saved route account is missing")?;
    let entry = account
        .effective_catalog(None)?
        .into_iter()
        .find(|entry| entry.model.model_id == selector.model_id);
    let (model, context) = match entry {
        Some(entry) => (entry.model, entry.context),
        None => {
            let model = pl_model::model::ModelInfo::compatible(&selector.model_id);
            let context = model.resolve_context(None);
            (model, context)
        }
    };
    let effort = model.default_effort().map(ReasoningEffort::new);
    Ok(pl_model::config::ResolvedModelRoute {
        pricing_mode: account.billing_kind()?.into(),
        role,
        account_id: selector.account_id.clone(),
        endpoint: account.to_endpoint()?,
        model,
        context,
        effort,
    })
}

pub(crate) fn route_record(
    state: &ThreadSnapshot,
    child: bool,
) -> Result<Option<(&ExtensionRecord, ModelRouteConfig)>> {
    if child {
        let Some(record) = state.extensions.get(AGENT_PROFILE_EXTENSION) else {
            return Ok(None);
        };
        let profile: pl_protocol::AgentProfileSnapshot =
            decode_profile_payload(&record.payload, AGENT_PROFILE_FORMAT, "Agent Profile")?;
        Ok(Some((record, profile_route(&profile)?)))
    } else {
        let Some(record) = state.extensions.get(MODEL_ROUTE_EXTENSION) else {
            return Ok(None);
        };
        Ok(Some((record, decode(&record.payload)?)))
    }
}

/// Availability describes next admission, not whether an old in-flight session is still resident.
/// This never changes the saved selector or tears down a running model.
pub(crate) fn annotate_availability(
    runtime: &mut pl_protocol::ThreadRuntimeSnapshot,
    thread: &pl_protocol::Thread,
    config: &crate::StudioConfig,
) -> Result<()> {
    let Some(route) = runtime.model_route.as_mut() else {
        return Ok(());
    };
    let selector = ModelRouteConfig {
        account_id: AccountId::new(route.account_id.clone())?,
        model_id: route.model_id.clone(),
        effort: route.effort.clone().map(ReasoningEffort::new),
    };
    let resolved = if thread.parent_thread_id.is_some() {
        crate::studio::delegation::resolve_child_selection(
            config,
            pl_model::config::AgentRoleId::new(thread.role.clone())?,
            &selector,
        )
    } else {
        config
            .models
            .resolve_route(crate::config::root_agent_route_id(), &selector)
            .and_then(|route| {
                crate::studio::delegation::validate_credential(&route)?;
                Ok(route)
            })
    };
    match resolved {
        Ok(_) => {
            route.available = true;
            route.unavailable_reason = None;
        }
        Err(error) => {
            route.available = false;
            route.unavailable_reason = Some(error.to_string());
        }
    }
    Ok(())
}

fn decode_route_payload(
    payload: &OpaquePayload,
    expected_format: &str,
    label: &str,
) -> Result<ModelRouteConfig> {
    if payload.format() != expected_format || payload.version() != FORMAT_VERSION {
        bail!(
            "unsupported saved {label} codec {} version {}; explicit recovery migration required",
            payload.format(),
            payload.version()
        );
    }
    serde_json::from_str(payload.content()).with_context(|| format!("decode saved {label}"))
}
fn decode_profile_payload(
    payload: &OpaquePayload,
    expected_format: &str,
    label: &str,
) -> Result<pl_protocol::AgentProfileSnapshot> {
    if payload.format() != expected_format || payload.version() != FORMAT_VERSION {
        bail!(
            "unsupported saved {label} codec {} version {}; explicit recovery migration required",
            payload.format(),
            payload.version()
        );
    }
    serde_json::from_str(payload.content()).with_context(|| format!("decode saved {label}"))
}

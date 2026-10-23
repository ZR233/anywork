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
pub(crate) const MODEL_ROUTE_FORMAT: &str = "pl.studio.model-route";
pub(crate) const AGENT_PROFILE_EXTENSION: &str = "studio.agent-profile";
pub(crate) const AGENT_PROFILE_FORMAT: &str = "pl.studio.agent-profile";
/// 当前写入版本；v1 是 Provider/Preset 时代的账号接入身份。
const FORMAT_VERSION: u32 = 2;
/// 读取仍支持的最后一个旧版本。
const LEGACY_FORMAT_VERSION: u32 = 1;

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
        pricing_mode: account.pricing_mode,
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
            .resolve_route(crate::StudioRole::Planner.id(), &selector)
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

/// 把模型接入相关的旧版本扩展表示升级为当前编码版本。
///
/// 只替换已保存载荷的版本与账号/模型键，保留 [`ExtensionRecord::revision`]、
/// `ThreadSnapshot::extension_sequence` 以及其它产品扩展；它不是业务 mutation，不激活模型、不
/// 调用工具，也不把旧字段当成新的在线事实。未知版本或不安全来源在此显式失败，由调用方在发布
/// owner 之前中止恢复。
pub(crate) fn migrate_saved_representation(state: &mut ThreadSnapshot) -> Result<()> {
    if let Some(record) = state.extensions.get_mut(MODEL_ROUTE_EXTENSION) {
        let route = decode(&record.payload)?;
        if record.payload.version() < FORMAT_VERSION {
            record.payload = encode(&route)?;
        }
    }
    if let Some(record) = state.extensions.get_mut(AGENT_PROFILE_EXTENSION) {
        let profile =
            decode_profile_payload(&record.payload, AGENT_PROFILE_FORMAT, "Agent Profile")?;
        if record.payload.version() < FORMAT_VERSION {
            record.payload = encode_profile(&profile)?;
        }
    }
    Ok(())
}

/// 读取模型路由：v1 载荷在边界把 `provider`/`model` 转成当前键。
fn decode_route_payload(
    payload: &OpaquePayload,
    expected_format: &str,
    label: &str,
) -> Result<ModelRouteConfig> {
    if payload.format() != expected_format
        || !(LEGACY_FORMAT_VERSION..=FORMAT_VERSION).contains(&payload.version())
    {
        bail!(
            "unsupported saved {label} codec {} version {}",
            payload.format(),
            payload.version()
        );
    }
    let mut value: serde_json::Value =
        serde_json::from_str(payload.content()).with_context(|| format!("decode saved {label}"))?;
    if payload.version() < FORMAT_VERSION {
        let object = value
            .as_object_mut()
            .context("saved model route is not an object")?;
        super::payload_alias::rename_key(object, "provider", "account_id")?;
        super::payload_alias::rename_key(object, "model", "model_id")?;
    }
    serde_json::from_value(value).with_context(|| format!("decode saved {label}"))
}

/// 读取冻结的 Agent Profile：v1 载荷在边界转换账号/模型接入身份。
fn decode_profile_payload(
    payload: &OpaquePayload,
    expected_format: &str,
    label: &str,
) -> Result<pl_protocol::AgentProfileSnapshot> {
    if payload.format() != expected_format
        || !(LEGACY_FORMAT_VERSION..=FORMAT_VERSION).contains(&payload.version())
    {
        bail!(
            "unsupported saved {label} codec {} version {}",
            payload.format(),
            payload.version()
        );
    }
    let mut value: serde_json::Value =
        serde_json::from_str(payload.content()).with_context(|| format!("decode saved {label}"))?;
    if payload.version() < FORMAT_VERSION {
        let object = value
            .as_object_mut()
            .context("saved Agent Profile is not an object")?;
        // 冻结 Profile 的 provider_id 按 camelCase 写成 providerId，与模型路由不同。
        super::payload_alias::rename_key(object, "providerId", "accountId")?;
        super::payload_alias::rename_key(object, "model", "modelId")?;
    }
    serde_json::from_value(value).with_context(|| format!("decode saved {label}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn payload(version: u32, body: serde_json::Value) -> OpaquePayload {
        OpaquePayload::new(MODEL_ROUTE_FORMAT, version, body.to_string()).unwrap()
    }

    #[test]
    fn v1_model_route_payload_converts_identity_without_touching_v2() {
        let legacy = payload(
            1,
            serde_json::json!({ "provider": "deepseek", "model": "deepseek-flash", "effort": "high" }),
        );
        let route = decode(&legacy).expect("v1 route decodes");
        assert_eq!(route.account_id.as_str(), "deepseek");
        assert_eq!(route.model_id, "deepseek-flash");
        assert_eq!(
            route.effort.as_ref().map(|value| value.as_str()),
            Some("high")
        );

        let current = payload(
            2,
            serde_json::json!({ "account_id": "second", "model_id": "m", "effort": null }),
        );
        let route = decode(&current).expect("v2 route decodes");
        assert_eq!(route.account_id.as_str(), "second");
        assert_eq!(route.model_id, "m");
    }

    #[test]
    fn conflicting_v1_and_v2_identity_keys_fail_without_guessing() {
        let conflicting = payload(
            1,
            serde_json::json!({ "provider": "a", "account_id": "b", "model": "m" }),
        );
        assert!(decode(&conflicting).is_err());
    }

    #[test]
    fn v1_frozen_profile_payload_converts_identity() {
        let legacy = OpaquePayload::new(
            AGENT_PROFILE_FORMAT,
            1,
            serde_json::json!({
                "profileId": "reviewer",
                "displayName": "Reviewer",
                "description": "",
                "whenToUse": "",
                "systemInstructions": "",
                "providerId": "deepseek",
                "model": "deepseek-flash",
                "effort": "high",
                "source": "config",
                "revision": "1",
                "contentHash": "",
                "system": true,
                "enabled": true,
                "workspaceMode": "unrestricted"
            })
            .to_string(),
        )
        .unwrap();
        let profile = decode_profile_payload(&legacy, AGENT_PROFILE_FORMAT, "Agent Profile")
            .expect("v1 profile decodes");
        assert_eq!(profile.account_id, "deepseek");
        assert_eq!(profile.model_id, "deepseek-flash");
        assert_eq!(profile.effort.as_deref(), Some("high"));
    }
}

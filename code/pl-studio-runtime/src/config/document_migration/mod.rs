//! Typed, frozen TOML formats. The resource owner retains all IO and commit state.
mod main;
mod profile;
pub(super) mod wire;

pub(super) use main::{
    MainV35, extract_historical_acp_accounts, extract_legacy_acp_from_main,
    extract_legacy_lsp_from_main, extract_legacy_mcp_from_main, load_current_main, load_main,
};
pub(super) use profile::load_current as load_current_profile;
pub(super) use profile::{ProfileV3, load_profile};

use anyhow::{Result, ensure};
use serde::{Deserialize, Serialize};

pub(super) const VERSION_KEY: &str = "schema_version";

/// An alias pair is resolved during DTO decoding, before an infallible migration runs.
fn identity<T: PartialEq>(old: Option<T>, new: Option<T>, field: &str) -> Result<T> {
    match (old, new) {
        (Some(old), Some(new)) => {
            ensure!(old == new, "conflicting historical {field} identities");
            Ok(new)
        }
        (Some(value), None) | (None, Some(value)) => Ok(value),
        (None, None) => anyhow::bail!("missing {field} identity"),
    }
}

fn optional_identity<T: PartialEq>(
    old: Option<T>,
    new: Option<T>,
    field: &str,
) -> Result<Option<T>> {
    if old.is_none() && new.is_none() {
        return Ok(None);
    }
    identity(old, new, field).map(Some)
}

/// Only the final, current wire shape crosses into a mutable domain type.
fn into_current<W: Serialize, D: for<'de> Deserialize<'de>>(wire: &W) -> Result<D> {
    toml::Value::try_from(wire)?.try_into().map_err(Into::into)
}

pub(super) fn migrate_cached_model(value: serde_json::Value) -> anyhow::Result<serde_json::Value> {
    let legacy: wire::ModelInfo = serde_json::from_value(value)?;
    let observation = legacy.observation.clone();
    let binding = serde_json::to_value(&legacy.binding)?;
    let mut next = serde_json::to_value(wire::ModelDeclaration34::from(legacy))?;
    next["extra"]["binding"] = binding;
    if let Some(observation) = observation {
        next["observation"] = serde_json::to_value(observation)?;
    }
    Ok(next)
}

/// Encode test inputs with the historical schema itself before exercising its forward migration.
#[cfg(test)]
pub(super) fn historical_model(model: &pl_model::model::ModelDefinition) -> wire::ModelInfo {
    let mut capabilities = serde_json::json!(model.extra.capabilities);
    capabilities["tools"]["parallel_tool_calls"] = model
        .base
        .supports_parallel_tool_calls
        .unwrap_or_default()
        .into();
    serde_json::from_value(serde_json::json!({
        "model_id": model.base.slug, "display_name": model.base.display_name,
        "description": model.base.description, "context_window":model.base.context_window,
        "max_context_window": model.base.max_context_window, "auto_compact_token_limit":model.base.auto_compact_token_limit,
        "base_instructions":model.base.model_messages.instructions_template, "truncation_policy":model.base.truncation_policy,
        "max_output_tokens":model.extra.max_output_tokens, "default_temperature":model.extra.default_temperature,
        "pricing":model.extra.pricing,"parameters":model.parameters().collect::<Vec<_>>(),"binding":model.extra.binding,
        "capabilities":capabilities,"observation":model.observation,
    })).unwrap()
}

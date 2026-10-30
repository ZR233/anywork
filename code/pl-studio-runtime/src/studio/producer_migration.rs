//! Pure producer normalization shared by named history migrations and TOML import.
use super::thread_projection::AuxiliaryBillingReceipt;
use crate::compaction::CompactionReceipt;
use anyhow::{Context, Result, ensure};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    thread::ThreadCheckpoint,
};
use serde_json::value::{RawValue, to_raw_value};

// Open producer envelopes retain unknown fields and exact numeric tokens. Serde owns JSON parsing;
// only schema-known object paths are edited, never recursive key/string discovery.
pub(crate) type RawObject = std::collections::BTreeMap<String, Box<RawValue>>;
pub(crate) fn field<'a>(object: &'a RawObject, key: &str) -> Result<&'a RawValue> {
    object
        .get(key)
        .map(Box::as_ref)
        .with_context(|| format!("missing producer field {key}"))
}
pub(crate) fn edit(
    object: &mut RawObject,
    key: &str,
    change: impl FnOnce(&mut RawObject) -> Result<()>,
) -> Result<()> {
    let mut nested = serde_json::from_str(field(object, key)?.get())?;
    change(&mut nested)?;
    object.insert(key.into(), to_raw_value(&nested)?);
    Ok(())
}
fn put(object: &mut RawObject, key: &str, value: Box<RawValue>) -> Result<()> {
    if let Some(existing) = object.get(key) {
        ensure!(
            serde_json::from_str::<serde_json::Value>(existing.get())?
                == serde_json::from_str::<serde_json::Value>(value.get())?,
            "conflicting persisted field {key}"
        );
    }
    object.insert(key.into(), value);
    Ok(())
}
fn rename(object: &mut RawObject, old: &str, new: &str) -> Result<()> {
    if let Some(value) = object.remove(old) {
        put(object, new, value)?;
    }
    Ok(())
}
pub(crate) fn replace_payload(saved: &mut RawObject, payload: &OpaquePayload) -> Result<()> {
    saved.insert("format".into(), to_raw_value(payload.format())?);
    saved.insert("version".into(), to_raw_value(&payload.version())?);
    saved.insert("content".into(), to_raw_value(payload.content())?);
    Ok(())
}

pub(crate) fn normalize(payload: &OpaquePayload) -> Result<Option<OpaquePayload>> {
    let (content, current) = match payload.format() {
        "pl.studio.auxiliary-billing" => (
            migrate_auxiliary(payload.version(), payload.content())?,
            AuxiliaryBillingReceipt::VERSION,
        ),
        "pl.studio.compaction" => (
            migrate_compaction(payload.version(), payload.content())?,
            CompactionReceipt::VERSION,
        ),
        _ => return pl_model::runtime::migration::migrate_payload(payload).map_err(Into::into),
    };
    if payload.version() == current {
        return Ok(None);
    }
    Ok(Some(OpaquePayload::new(
        payload.format(),
        current,
        content,
    )?))
}

/// Source evidence must be decoded before the v1 receipt is upgraded.
pub(crate) fn compaction_receipt(version: u32, content: &str) -> Result<CompactionReceipt> {
    Ok(serde_json::from_str(&migrate_compaction(
        version, content,
    )?)?)
}

pub(crate) fn checkpoint(checkpoint: &mut ThreadCheckpoint) -> Result<()> {
    project_kind(checkpoint)?;
    crate::compaction::migrate_checkpoint_sources(checkpoint)?;
    for record in checkpoint.state.extensions.values_mut() {
        if let Some(current) = normalize(&record.payload)? {
            record.payload = current;
        }
    }
    for record in std::sync::Arc::make_mut(&mut checkpoint.state.context.records) {
        for content in &mut record.content {
            if let ContextContent::Opaque { payload } = content
                && let Some(current) = normalize(payload)?
            {
                *payload = current;
            }
        }
    }
    Ok(())
}

/// The pre-kind Project binding is upgraded only during explicit checkpoint import/migration.
pub(crate) fn project_kind(checkpoint: &mut ThreadCheckpoint) -> Result<()> {
    let Some(record) = checkpoint.state.extensions.get_mut("studio.project") else {
        return Ok(());
    };
    ensure!(
        record.payload.format() == "pl.studio.project" && record.payload.version() == 1,
        "unsupported saved project binding"
    );
    let mut project: RawObject = serde_json::from_str(record.payload.content())?;
    if !project.contains_key("kind") {
        project.insert("kind".into(), to_raw_value("project")?);
        let content = serde_json::to_string(&project)?;
        let _: crate::studio::WorkspaceRecord = serde_json::from_str(&content)?;
        record.payload = OpaquePayload::new("pl.studio.project", 1, content)?;
    } else {
        let _: crate::studio::WorkspaceRecord = serde_json::from_str(record.payload.content())?;
    }
    Ok(())
}

/// Exact physical relocation after stable bot ownership has been proved by the layout operation.
pub(crate) fn relocate_bot_checkpoint(
    checkpoint: &mut ThreadCheckpoint,
    mapping: &crate::studio::startup::storage_layout::bot_roots::BotRootMove,
) -> Result<()> {
    mapping.require_convertible(&checkpoint.thread_id)?;
    ensure!(
        crate::studio::model_route::bot_owner(&checkpoint.state)?.as_deref()
            == Some(mapping.bot_id.as_str()),
        "saved bot owner conflicts with the layout operation"
    );
    project_kind(checkpoint)?;
    if let Some(record) = checkpoint.state.extensions.get_mut("studio.project") {
        let project: crate::studio::WorkspaceRecord =
            serde_json::from_str(record.payload.content())?;
        ensure!(
            project.id == mapping.workspace_id && project.ssh_alias.is_none(),
            "bot effective Workspace identity conflicts with the layout operation"
        );
        let mut path = project.path;
        mapping.exact_path(&mut path)?;
        let mut object: RawObject = serde_json::from_str(record.payload.content())?;
        object.insert("path".into(), to_raw_value(&path)?);
        record.payload = OpaquePayload::new(
            record.payload.format(),
            record.payload.version(),
            serde_json::to_string(&object)?,
        )?;
    }
    crate::studio::workspace_receipt::migration::relocate_bot_root(&mut checkpoint.state, mapping)
}

fn migrate_auxiliary(version: u32, content: &str) -> Result<String> {
    ensure!(
        (1..=AuxiliaryBillingReceipt::VERSION).contains(&version),
        "unsupported auxiliary billing version"
    );
    let mut object: RawObject = serde_json::from_str(content)?;
    if version == 1 {
        edit(&mut object, "billing", |billing| {
            rename(billing, "providerInstanceId", "accountId")?;
            rename(billing, "provider", "accountDisplayName")?;
            rename(billing, "reasoningEffort", "effort")?;
            // Old `model` may be a sent name; only the frozen observation proves catalog identity.
            billing.remove("model");
            if let Some(observation) = billing
                .get("modelObservation")
                .filter(|raw| raw.get() != "null")
            {
                let observation: RawObject = serde_json::from_str(observation.get())?;
                if let Some(configured) = observation.get("configuredModel") {
                    put(billing, "modelId", configured.clone())?;
                }
            }
            if billing
                .get("prefixChangedReason")
                .map(|raw| serde_json::from_str::<Option<String>>(raw.get()))
                .transpose()?
                .flatten()
                .as_deref()
                == Some("providerChanged")
            {
                billing.insert(
                    "prefixChangedReason".into(),
                    to_raw_value("accountChanged")?,
                );
            }
            Ok(())
        })?;
    }
    if version < 4 {
        edit(&mut object, "billing", migrate_timing)?;
    }
    let encoded = serde_json::to_string(&object)?;
    let receipt: AuxiliaryBillingReceipt = serde_json::from_str(&encoded)?;
    ensure!(
        version >= 3 || receipt.billing.accounting.pricing != pl_protocol::PricingOutcome::NoCharge,
        "no-charge accounting requires auxiliary billing version 3"
    );
    Ok(encoded)
}

fn migrate_compaction(version: u32, content: &str) -> Result<String> {
    ensure!(
        (1..=CompactionReceipt::VERSION).contains(&version),
        "unsupported auxiliary accounting receipt"
    );
    let mut object: RawObject = serde_json::from_str(content)?;
    if version == 1 {
        let binding =
            pl_model::runtime::migration::migrate_call_binding(field(&object, "binding")?.get())?;
        object.insert("binding".into(), RawValue::from_string(binding)?);
    }
    if version < 4 {
        object.insert(
            "timing".into(),
            to_raw_value(&Option::<pl_protocol::InferenceTiming>::None)?,
        );
    }
    let encoded = serde_json::to_string(&object)?;
    let receipt: CompactionReceipt = serde_json::from_str(&encoded)?;
    ensure!(
        version >= 3 || receipt.accounting.pricing != pl_protocol::PricingOutcome::NoCharge,
        "no-charge accounting requires compaction receipt version 3"
    );
    Ok(encoded)
}

fn migrate_timing(object: &mut RawObject) -> Result<()> {
    if object
        .get("timing")
        .is_some_and(|timing| timing.get() != "null")
    {
        edit(object, "timing", |timing| {
            put(
                timing,
                "firstOutputSource",
                to_raw_value(&pl_protocol::FirstOutputSource::LegacyUnknown)?,
            )
        })?;
    }
    Ok(())
}

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
    let content = match payload.format() {
        "pl.studio.auxiliary-billing" => migrate_auxiliary(payload.version(), payload.content())?,
        "pl.studio.compaction" => migrate_compaction(payload.version(), payload.content())?,
        _ => return pl_model::runtime::migration::migrate_payload(payload).map_err(Into::into),
    };
    if payload.version() == 3 {
        return Ok(None);
    }
    Ok(Some(OpaquePayload::new(payload.format(), 3, content)?))
}

/// Source evidence must be decoded before the v1 receipt is upgraded.
pub(crate) fn compaction_receipt(version: u32, content: &str) -> Result<CompactionReceipt> {
    Ok(serde_json::from_str(&migrate_compaction(
        version, content,
    )?)?)
}

pub(crate) fn checkpoint(checkpoint: &mut ThreadCheckpoint) -> Result<()> {
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
    let encoded = serde_json::to_string(&object)?;
    let receipt: AuxiliaryBillingReceipt = serde_json::from_str(&encoded)?;
    ensure!(
        version == AuxiliaryBillingReceipt::VERSION
            || receipt.billing.accounting.pricing != pl_protocol::PricingOutcome::NoCharge,
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
    let encoded = serde_json::to_string(&object)?;
    let receipt: CompactionReceipt = serde_json::from_str(&encoded)?;
    ensure!(
        version == CompactionReceipt::VERSION
            || receipt.accounting.pricing != pl_protocol::PricingOutcome::NoCharge,
        "no-charge accounting requires compaction receipt version 3"
    );
    Ok(encoded)
}

//! Frozen pre-ToolResult encoding. Only the storage upgrade paths call this decoder.

use anyhow::{Context, Result, ensure};
use pl_core::{
    context::{AgentMessageKind, ContextContent, OpaquePayload},
    thread::{ToolDelivery, ToolDeliveryTarget, current::ThreadCurrentState, inbox::ThreadMessage},
};
use serde_json::{Map, Value, json};

pub(super) const MODEL_ATTACHMENT_FORMAT: &str = "pl.model.attachment";
pub(super) const LEGACY_PAYLOAD_FIELD: &str = "legacyPayload";
pub(crate) const OUTPUT_ARTIFACTS_KEY: &str = "tool.output-artifacts";

/// Converts only the two known producer artifacts. The archived query page has a different
/// contract from today's author data, so retain its complete original envelope.
pub(crate) fn upgrade_artifacts(tool_id: &str, encoded: &[u8]) -> Result<Option<Vec<u8>>> {
    let mut parts: Vec<Value> = serde_json::from_slice(encoded)?;
    let mut changed = false;
    for part in &mut parts {
        if part.get("kind").and_then(Value::as_str) != Some("opaque") {
            continue;
        }
        let Some(payload) = part.get("payload") else {
            continue;
        };
        let format = payload.get("format").and_then(Value::as_str);
        let replacement = match (tool_id, format) {
            (
                pl_tool::file_display::TOOL_SHOW_FILES,
                Some(pl_tool::file_display::FILE_DISPLAY_FORMAT),
            ) => {
                let payload: OpaquePayload = serde_json::from_value(payload.clone())?;
                file_display_details(&payload)?
            }
            ("get_tool_task", Some("pl.tool.task")) => {
                let payload: OpaquePayload = serde_json::from_value(payload.clone())?;
                ensure!(
                    payload.version() == 1,
                    "unsupported legacy query artifact version"
                );
                json!({"legacyToolTask": payload})
            }
            _ => continue,
        };
        ensure!(!changed, "duplicate result artifacts for {tool_id}");
        *part = replacement;
        changed = true;
    }
    changed
        .then(|| serde_json::to_vec(&parts).map_err(anyhow::Error::from))
        .transpose()
}

fn file_display_details(payload: &OpaquePayload) -> Result<Value> {
    use pl_tool::file_display::{
        FileDisplayReceipt, FileDisplayResult, saved_file_display_receipt,
    };
    ensure!(
        matches!(payload.version(), 1 | 2),
        "unsupported legacy file display version"
    );
    let receipt: FileDisplayReceipt = serde_json::from_str(payload.content())?;
    if payload.version() == 1 {
        ensure!(
            !receipt.files.iter().any(|item| matches!(
                item,
                FileDisplayResult::Deferred { .. } | FileDisplayResult::NetworkImage { .. }
            )),
            "a v1 file display has a later receipt kind"
        );
    }
    let details = json!({"fileDisplay": receipt});
    saved_file_display_receipt(Some(&details))?
        .context("legacy file display receipt is missing")?;
    Ok(details)
}

pub(crate) fn decode_delivery(encoded: &[u8]) -> Result<ToolDelivery> {
    let mut value: Value = serde_json::from_slice(encoded)?;
    upgrade_delivery(&mut value)?;
    Ok(serde_json::from_value(value)?)
}

/// Schema 24 is also a staging format for importing a v2 TOML-only session. Its staging writer
/// already emits current results, while rows from a prior installation encode the original shape.
pub(crate) fn decode_schema24_delivery(encoded: &str) -> Result<ToolDelivery> {
    let mut value: Value = serde_json::from_str(encoded)?;
    if let Some(output) = value.get("output").and_then(Value::as_object)
        && output.contains_key("result")
    {
        ensure!(
            !output.contains_key("payload") && !output.contains_key("context"),
            "saved delivery has mixed result formats"
        );
    } else {
        upgrade_delivery(&mut value)?;
    }
    Ok(serde_json::from_value(value)?)
}

fn upgrade_delivery(delivery: &mut Value) -> Result<()> {
    let tool_id = delivery
        .get("toolId")
        .and_then(Value::as_str)
        .context("saved delivery has no tool identity")?
        .to_owned();
    let output = delivery
        .get_mut("output")
        .and_then(Value::as_object_mut)
        .context("saved delivery has no output")?;
    ensure!(
        !output.contains_key("result"),
        "saved delivery has mixed result formats"
    );
    let saved_payload = output
        .remove("payload")
        .context("old delivery has no payload")?;
    let payload: OpaquePayload = serde_json::from_value(saved_payload)?;
    ensure!(
        !payload.format().is_empty() && payload.version() != 0,
        "invalid old payload identity"
    );
    let mut content = output
        .remove("context")
        .context("old delivery has no context")?;
    upgrade_content(&mut content)?;
    // The old opaque envelope did not declare program data. Preserving its bytes is independent
    // of declaring a new program value, including when the bytes happen to parse as JSON.
    let details = legacy_details(&tool_id, payload)?;
    output.insert(
        "result".into(),
        json!({ "content": content, "details": details }),
    );
    upgrade_content(
        delivery
            .get_mut("deliveredContext")
            .context("old delivery has no delivered context")?,
    )?;
    Ok(())
}

/// The old inbox copied the entire result payload into the notification. Verify its association
/// with the delivery before changing it to the Core's reference to that same original.
pub(crate) fn upgrade_pending_tool_messages(state: &mut ThreadCurrentState) -> Result<()> {
    for delivery in state.deliveries.iter() {
        let ToolDeliveryTarget::Inbox { message_id } = &delivery.target else {
            continue;
        };
        let Some(legacy_payload) = delivery
            .output
            .details()
            .and_then(|details| details.get(LEGACY_PAYLOAD_FIELD))
        else {
            continue;
        };
        let payload: OpaquePayload = serde_json::from_value(legacy_payload.clone())?;
        let context = if delivery.delivered_context.is_empty() {
            delivery.output.content().to_vec()
        } else {
            delivery.delivered_context.clone()
        };
        let reference = OpaquePayload::new(
            "pl.core.tool-result-reference",
            1,
            delivery.call_id.as_str(),
        )?;
        let source_id = state
            .tasks
            .values()
            .find(|task| task.call_id == delivery.call_id)
            .map_or_else(
                || format!("task:{}", delivery.call_id),
                |task| task.id.clone(),
            );
        let legacy = ThreadMessage {
            id: message_id.clone(),
            source_id,
            kind: AgentMessageKind::Report,
            payload,
            context,
        };
        if let Some(stored) = std::sync::Arc::make_mut(&mut state.inbox)
            .iter_mut()
            .find(|record| record.message.id == *message_id)
        {
            let mut expected = legacy.clone();
            expected.payload = stored.message.payload.clone();
            ensure!(
                stored.message == expected
                    && (expected.payload == legacy.payload || expected.payload == reference),
                "legacy Inbox delivery {message_id} differs from its saved notification"
            );
            stored.message.payload = reference.clone();
        }
        if let Some(consumed) = std::sync::Arc::make_mut(&mut state.consumed_message_identities)
            .iter_mut()
            .find(|record| record.id == *message_id)
        {
            let mut converted = legacy.clone();
            converted.payload = reference;
            let new_digest = converted.digest();
            let mut original = legacy;
            restore_opaque_for_digest(&mut original.context);
            let old_digest = original.digest();
            ensure!(
                consumed.digest == old_digest || consumed.digest == new_digest,
                "legacy Inbox delivery {message_id} differs from its consumed notification"
            );
            consumed.digest = new_digest;
        }
    }
    Ok(())
}

/// Schema 24 verified the identities of pending input/inbox bytes before external migration.
/// The old hash included the serialized variant tags, so recompute it with that old media tag.
pub(crate) fn restore_opaque_for_digest(content: &mut [ContextContent]) {
    for item in content {
        if let ContextContent::Media { payload } = item
            && payload.format() == MODEL_ATTACHMENT_FORMAT
        {
            *item = ContextContent::Opaque {
                payload: payload.clone(),
            };
        }
    }
}

pub(super) fn legacy_details(tool_id: &str, payload: OpaquePayload) -> Result<Value> {
    use pl_tool::{file_display, image, image_card};
    let mut details = match (tool_id, payload.format(), payload.content().is_empty()) {
        (file_display::TOOL_SHOW_FILES, file_display::FILE_DISPLAY_FORMAT, false) => {
            file_display_details(&payload)?
        }
        (
            "exec" | pl_tool::exec::TOOL_EXEC | pl_tool::exec::TOOL_WRITE_STDIN,
            "pl.tool.exec",
            false,
        ) if payload.version() == 2 => legacy_command_details(&payload)?,
        (image::TOOL_VIEW_IMAGE, image::VIEW_IMAGE_RECEIPT_FORMAT, false) => {
            ensure!(
                payload.version() == image::VIEW_IMAGE_RECEIPT_VERSION,
                "unsupported legacy image receipt version"
            );
            let receipt: image::ViewImageReceipt = serde_json::from_str(payload.content())?;
            let details = json!({"viewImage": receipt});
            image::saved_view_image_receipt(Some(&details))?
                .context("legacy image receipt is missing")?;
            details
        }
        (_, image_card::IMAGE_CARD_FORMAT, false) => {
            ensure!(
                payload.version() == image_card::IMAGE_CARD_VERSION,
                "unsupported legacy image card version"
            );
            let receipt: image_card::ImageCardReceipt = serde_json::from_str(payload.content())?;
            let details = json!({"imageCard": receipt});
            image_card::saved_image_card_receipt(Some(&details))?
                .context("legacy image card is missing")?;
            details
        }
        _ => json!({}),
    };
    details[LEGACY_PAYLOAD_FIELD] = serde_json::to_value(payload)?;
    Ok(details)
}

fn legacy_command_details(payload: &OpaquePayload) -> Result<Value> {
    #[derive(serde::Serialize, serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Receipt {
        #[serde(skip_serializing_if = "Option::is_none")]
        exit_code: Option<i32>,
        #[serde(skip_serializing_if = "Option::is_none")]
        stdout_resource: Option<pl_core::context::ResourceReference>,
        #[serde(skip_serializing_if = "Option::is_none")]
        stderr_resource: Option<pl_core::context::ResourceReference>,
    }
    // These fields come only from the known producer's original archive envelope. Historical
    // model-text blocks remain untouched, including those that happen to contain a JSON receipt.
    let receipt: Receipt = serde_json::from_str(payload.content())?;
    let details = json!({"command": receipt});
    pl_tool::exec::saved_command_resources(Some(&details))?;
    Ok(details)
}

pub(crate) fn upgrade_record(record: &mut Value) -> Result<()> {
    ensure!(
        record.get("toolData").is_none(),
        "old context record has toolData"
    );
    if let Some(content) = record.get_mut("content") {
        upgrade_content(content)?;
    }
    Ok(())
}

pub(super) fn upgrade_state(root: &mut Value) -> Result<()> {
    let state = root
        .get_mut("state")
        .and_then(Value::as_object_mut)
        .context("saved state is missing")?;
    if let Some(records) = state
        .get_mut("context")
        .and_then(|value| value.get_mut("records"))
    {
        upgrade_list(records, upgrade_record)?;
    }
    if let Some(deliveries) = state.get_mut("deliveries") {
        upgrade_list(deliveries, upgrade_delivery)?;
    }
    upgrade_slot_list(state, "inputs", &["input", "context"])?;
    upgrade_slot_list(state, "inbox", &["message", "context"])?;
    upgrade_slot_list(state, "runtimeFacts", &["content"])?;
    if let Some(interactions) = state.get_mut("interactions").and_then(Value::as_object_mut) {
        for interaction in interactions.values_mut() {
            if let Some(content) = lookup(interaction, &["response", "content"]) {
                upgrade_content(content)?;
            }
        }
    }
    if let Some(content) = lookup(root, &["modelCall", "phase", "pendingStepInput", "content"]) {
        upgrade_content(content)?;
    }
    Ok(())
}

fn upgrade_slot_list(state: &mut Map<String, Value>, key: &str, slot: &[&str]) -> Result<()> {
    if let Some(records) = state.get_mut(key) {
        upgrade_list(records, |record| {
            if let Some(content) = lookup(record, slot) {
                upgrade_content(content)?;
            }
            Ok(())
        })?;
    }
    Ok(())
}

fn lookup<'a>(value: &'a mut Value, keys: &[&str]) -> Option<&'a mut Value> {
    keys.iter().try_fold(value, |value, key| value.get_mut(key))
}

fn upgrade_list(
    value: &mut Value,
    mut upgrade: impl FnMut(&mut Value) -> Result<()>,
) -> Result<()> {
    for item in value.as_array_mut().context("saved list is not an array")? {
        upgrade(item)?;
    }
    Ok(())
}

fn upgrade_content(content: &mut Value) -> Result<()> {
    upgrade_list(content, |item| {
        let item = item
            .as_object_mut()
            .context("saved context item is not an object")?;
        if item.get("kind").and_then(Value::as_str) == Some("opaque")
            && item
                .get("payload")
                .and_then(|payload| payload.get("format"))
                .and_then(Value::as_str)
                == Some(MODEL_ATTACHMENT_FORMAT)
        {
            item.insert("kind".into(), Value::String("media".into()));
        }
        Ok(())
    })
}

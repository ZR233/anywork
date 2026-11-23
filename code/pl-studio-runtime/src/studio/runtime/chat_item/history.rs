//! Producer envelopes acquire Schema 26 atomic event serialization and 16 KiB hybrid bodies.
use super::*;
use crate::history::{
    EventPayloadEnvelope, HistoryBodyRole, HistoryEntityState, HistoryEvent, HistoryEventMeta,
    HistorySingleVisibility, HistoryTimelineRole, HistoryWaitHead, PendingBody,
    milliseconds_from_seconds, pack_bodies,
};
use anyhow::Context as _;

fn role(key: &str) -> HistoryBodyRole {
    match atom_content_role_by_key(key) {
        Some(crate::ChatContentRole::Body) => HistoryBodyRole::Body,
        Some(crate::ChatContentRole::ReasoningSummary) => HistoryBodyRole::ReasoningSummary,
        Some(crate::ChatContentRole::ToolArguments) => HistoryBodyRole::ToolArguments,
        Some(crate::ChatContentRole::ToolOutput) => HistoryBodyRole::ToolOutput,
        None if key == "tool.output-artifacts" => HistoryBodyRole::Attachment,
        None => HistoryBodyRole::Other {
            name: "producer_detail".into(),
        },
    }
}

fn content_bytes(content: &ChatContent) -> Result<Arc<[u8]>> {
    Ok(match &content.data {
        ContentData::Bytes(bytes) => bytes.clone(),
        ContentData::Text(_) => content
            .data
            .range(0, content.data.len())?
            .as_bytes()
            .to_vec()
            .into(),
    })
}

fn block_bytes(block: Arc<ContentBlock>) -> Result<Vec<u8>> {
    let data = ContentData::text(block);
    Ok(data.range(0, data.len())?.as_bytes().to_vec())
}

fn event_meta(
    atom: &crate::ChatAtom,
    presentation_contract: Option<String>,
    single_visibility: Option<HistorySingleVisibility>,
) -> Result<HistoryEventMeta> {
    let state = match atom.lifecycle {
        crate::ChatAtomLifecycle::Active { status, .. } => {
            HistoryEntityState::KnownActive { status }
        }
        crate::ChatAtomLifecycle::Terminal { outcome, .. } => {
            HistoryEntityState::KnownTerminal { outcome }
        }
    };
    Ok(HistoryEventMeta {
        entity_id: atom.id.clone(),
        entity_kind: atom.kind,
        delivery: atom.delivery,
        state,
        started_at: atom.started_at.map(milliseconds_from_seconds).transpose()?,
        finished_at: atom
            .finished_at
            .map(milliseconds_from_seconds)
            .transpose()?,
        text_channel: atom.text_channel,
        single_visibility,
        presentation_contract,
        source_order: atom.source_order,
        content_present: atom.content_present,
        wait: atom
            .wait
            .clone()
            .map(|presentation| HistoryWaitHead::Inline { presentation }),
        tool: atom.tool.clone(),
    })
}

fn extract_presentation_contract(data: &serde_json::Value) -> Option<String> {
    data.get("invocation")
        .and_then(|invocation| invocation.get("presentationContract"))
        .and_then(serde_json::Value::as_str)
        .map(str::to_owned)
}

pub(in crate::studio) fn build_event_from_draft(
    event: &mut HistoryEvent,
    atom: &crate::ChatAtom,
    draft: &ChatDraft,
    database_id: &str,
) -> Result<()> {
    let payload: serde_json::Value = serde_json::from_slice(&draft.payload)?;
    let obj = payload
        .as_object()
        .context("canonical producer payload is not a JSON object")?;
    let contract = obj
        .get("contract")
        .and_then(serde_json::Value::as_str)
        .context("canonical producer contract is missing")?;
    ensure!(
        contract == "anywork.chat/1",
        "unsupported canonical producer contract"
    );
    let item_type = obj
        .get("type")
        .and_then(serde_json::Value::as_str)
        .context("canonical producer type is missing")?
        .to_owned();
    let data = obj
        .get("data")
        .cloned()
        .context("canonical producer data is missing")?;
    let declarations = obj
        .get("bodies")
        .and_then(serde_json::Value::as_array)
        .context("canonical body declarations are missing")?;

    let mut ordered = Vec::with_capacity(declarations.len());
    for declaration in declarations {
        let key = declaration["key"]
            .as_str()
            .context("declared body key is missing")?;
        let mut matches = draft
            .contents
            .values()
            .filter(|content| content.descriptor.key.key == key);
        let content = matches
            .next()
            .context("declared canonical body is missing")?
            .clone();
        ensure!(
            matches.next().is_none(),
            "canonical body key has multiple owners"
        );
        ensure!(
            declaration["byteLength"].as_u64() == Some(content.descriptor.byte_length),
            "canonical body declaration differs from its bytes"
        );
        ordered.push(content);
    }
    ensure!(
        ordered.len() == draft.contents.len(),
        "canonical content is not declared by its producer"
    );

    let mut pending = Vec::with_capacity(ordered.len());
    for content in ordered {
        let key = content.descriptor.key.key.clone();
        pending.push(PendingBody::new(
            key.clone(),
            role(&key),
            content.descriptor.media_type.clone(),
            content_bytes(&content)?,
        ));
    }
    let manifest = pack_bodies(event, pending, database_id)?;
    let presentation_contract = extract_presentation_contract(&data);
    let single_visibility = if atom.kind == crate::ChatAtomKind::Text
        && event.timeline_role == HistoryTimelineRole::Divider
    {
        Some(HistorySingleVisibility::Content)
    } else {
        None
    };
    let turn_id = obj
        .get("turnId")
        .and_then(serde_json::Value::as_str)
        .map(str::to_owned)
        .or_else(|| atom.turn_id.clone());

    let envelope = EventPayloadEnvelope {
        contract: "anywork.event/1".into(),
        item_type,
        meta: event_meta(atom, presentation_contract, single_visibility)?,
        data,
        bodies: manifest,
        source_order: atom.source_order,
        turn_id,
        captured_at: None,
    };
    event.payload_schema = "anywork.event/1".into();
    event.payload_json = serde_json::to_string(&envelope)?;
    Ok(())
}

pub(in crate::studio) fn build_active_tool_event(
    event: &mut HistoryEvent,
    atom: &crate::ChatAtom,
    item: &ExecutionItem,
    cancel_requested: bool,
    database_id: &str,
) -> Result<()> {
    let descriptor = serde_json::to_value(descriptor::observation_descriptor(
        item.state(),
        &item.thread_id,
    )?)?;
    let envelope_val = payload_envelope(item.state(), descriptor, Vec::new(), 0)?;
    let item_type = envelope_val
        .get("type")
        .and_then(serde_json::Value::as_str)
        .context("active tool envelope has no type")?
        .to_owned();
    let mut data = envelope_val
        .get("data")
        .cloned()
        .context("active tool envelope has no data")?;
    if cancel_requested {
        if let Some(state_obj) = data
            .get_mut("state")
            .and_then(serde_json::Value::as_object_mut)
        {
            state_obj.insert("cancelRequested".into(), serde_json::Value::Bool(true));
        }
        if let Some(data_obj) = data.as_object_mut() {
            data_obj.insert("cancelRequested".into(), serde_json::Value::Bool(true));
        }
    }

    let mut fields = content_fields(item.state())?;
    fields.retain(|key, _| atom_content_role(key).is_some());
    let mut pending = Vec::with_capacity(fields.len());
    for (key, block) in fields {
        let key_str = key.as_key();
        pending.push(PendingBody::new(
            key_str.clone(),
            role(&key_str),
            Some("text/plain; charset=utf-8".into()),
            block_bytes(block)?,
        ));
    }
    let manifest = pack_bodies(event, pending, database_id)?;
    let presentation_contract = extract_presentation_contract(&data);
    let envelope = EventPayloadEnvelope {
        contract: "anywork.event/1".into(),
        item_type,
        meta: event_meta(atom, presentation_contract, None)?,
        data,
        bodies: manifest,
        source_order: atom.source_order,
        turn_id: atom.turn_id.clone(),
        captured_at: event.occurred_at,
    };
    event.payload_schema = "anywork.event/1".into();
    event.payload_json = serde_json::to_string(&envelope)?;
    Ok(())
}

pub(in crate::studio) fn build_active_state_event(
    event: &mut HistoryEvent,
    atom: &crate::ChatAtom,
    item_type: &str,
    data: serde_json::Value,
) -> Result<()> {
    let envelope = EventPayloadEnvelope {
        contract: "anywork.event/1".into(),
        item_type: item_type.to_owned(),
        meta: event_meta(atom, None, None)?,
        data,
        bodies: Vec::new(),
        source_order: atom.source_order,
        turn_id: atom.turn_id.clone(),
        captured_at: event.occurred_at,
    };
    event.payload_schema = "anywork.event/1".into();
    event.payload_json = serde_json::to_string(&envelope)?;
    Ok(())
}

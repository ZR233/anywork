//! Producer envelopes acquire immutable body references at the History freeze boundary.
use super::*;
use crate::history::{
    HistoryBody, HistoryBodyRole, HistoryEntityHead, HistoryEvent, HistoryEventBodyRef,
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

fn freeze_contents(
    event: &mut HistoryEvent,
    contents: impl IntoIterator<Item = Arc<ChatContent>>,
    database_id: &str,
) -> Result<Vec<serde_json::Value>> {
    let mut manifest = Vec::new();
    for content in contents {
        let key = &content.descriptor.key.key;
        let mut body = HistoryBody::new(key, role(key), content_bytes(&content)?);
        body.media_type = content.descriptor.media_type.clone();
        let reference = HistoryEventBodyRef {
            database_id: database_id.into(),
            owner_event_id: event.header.event_id.clone(),
            body_key: body.body_key.clone(),
            body_id: body.body_id.clone(),
            byte_start: 0,
            byte_length: body.bytes.len() as u64,
        };
        manifest.push(
            serde_json::json!({"key":key,"byteLength":reference.byte_length,"reference":reference}),
        );
        event.bodies.push(body);
    }
    Ok(manifest)
}

fn finish(
    event: &mut HistoryEvent,
    entity: &mut HistoryEntityHead,
    payload: Vec<u8>,
    database_id: &str,
) -> Result<()> {
    entity.detail_event_id = Some(event.header.event_id.clone());
    entity.input_manifest_event_id = Some(event.header.event_id.clone());
    entity.body_manifest_event_id = Some(event.header.event_id.clone());
    let mut body = HistoryBody::new(
        "canonical_payload",
        HistoryBodyRole::CanonicalPayload,
        payload,
    );
    body.media_type = Some("application/json".into());
    event.payload_body_id = Some(body.body_id.clone());
    event.bodies.insert(0, body);
    crate::history::prepare_entity_content(event, entity, database_id)?;
    event.bodies.sort_by_key(|body| match body.role {
        HistoryBodyRole::CanonicalPayload => 0,
        HistoryBodyRole::CanonicalMetadata => 1,
        _ => 2,
    });
    Ok(())
}

pub(in crate::studio) fn freeze_history_original(
    event: &mut HistoryEvent,
    entity: &mut HistoryEntityHead,
    draft: &ChatDraft,
    database_id: &str,
) -> Result<()> {
    // Only the producer's declared envelope fields are rewritten. Opaque data stays untouched.
    let mut envelope: BTreeMap<String, Box<serde_json::value::RawValue>> =
        serde_json::from_slice(&draft.payload)?;
    let contract = envelope
        .get("contract")
        .context("canonical producer contract is missing")?;
    ensure!(
        serde_json::from_str::<String>(contract.get())? == "anywork.chat/1",
        "unsupported canonical producer contract"
    );
    let declarations: Vec<serde_json::Value> = serde_json::from_str(
        envelope
            .get("bodies")
            .context("canonical body declarations are missing")?
            .get(),
    )?;
    let mut ordered = Vec::with_capacity(declarations.len());
    for declaration in &declarations {
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
    let atom: crate::ChatAtom = serde_json::from_slice(&draft.metadata)?;
    if let Some(order) = atom.source_order {
        envelope.insert(
            "sourceOrder".into(),
            serde_json::value::to_raw_value(&order)?,
        );
    }
    let manifest = freeze_contents(event, ordered, database_id)?;
    envelope.insert("bodies".into(), serde_json::value::to_raw_value(&manifest)?);
    finish(event, entity, serde_json::to_vec(&envelope)?, database_id)
}

pub(in crate::studio) fn freeze_history_observation(
    event: &mut HistoryEvent,
    entity: &mut HistoryEntityHead,
    state: &ExecutionShape,
    atom: &crate::ChatAtom,
    thread_id: &str,
    contents: Vec<Arc<ChatContent>>,
    database_id: &str,
) -> Result<()> {
    validate_observation(state, atom, thread_id)?;
    let manifest = freeze_contents(event, contents, database_id)?;
    let descriptor = serde_json::to_value(descriptor::observation_descriptor(state, thread_id)?)?;
    let mut payload = payload_envelope(state, descriptor, manifest, 0)?;
    payload
        .as_object_mut()
        .context("observation envelope is not an object")?
        .remove("sourceEffectSeq");
    payload["capturedAt"] = serde_json::to_value(event.header.occurred_at)?;
    if let Some(turn) = &atom.turn_id {
        payload["turnId"] = turn.clone().into();
    }
    finish(event, entity, serde_json::to_vec(&payload)?, database_id)
}

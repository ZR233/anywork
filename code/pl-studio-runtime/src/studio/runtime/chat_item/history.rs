//! Producer envelopes acquire immutable body references at the History freeze boundary.
use super::*;
use crate::history::{
    HistoryBody, HistoryBodyRole, HistoryEntityHead, HistoryEntityState, HistoryEvent,
    HistoryEventBodyRef,
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

/// Materializes a specifically requested canonical execution value. Transport/UI body reads remain
/// windows; only business consumers that require the complete typed value take this explicit path.
pub(crate) async fn read_execution_item(
    reader: &crate::history::HistoryReader,
    detail: crate::history::HistoryEventDetail,
    thread_id: &str,
) -> Result<crate::ExecutionItem> {
    use crate::history::*;
    use tokio::io::{AsyncSeekExt, AsyncWriteExt};
    let payload = detail
        .payload_ref
        .clone()
        .context("canonical payload is missing")?;
    // serde ignores the possibly huge manifest while reading from a bounded disk spool. It never
    // allocates the full JSON body or traverses producer opaque data looking for references.
    let file = tempfile::tempfile()?;
    let mut file = tokio::fs::File::from_std(file);
    let mut offset = 0;
    while offset < payload.byte_length {
        let window = reader.read_body(payload.clone(), offset, 64 * 1024).await?;
        ensure!(
            !window.bytes.is_empty(),
            "canonical payload did not advance"
        );
        file.write_all(&window.bytes).await?;
        offset += window.bytes.len() as u64;
    }
    file.seek(std::io::SeekFrom::Start(0)).await?;
    let file = file.into_std().await;
    let envelope: ExecutionEnvelope =
        tokio::task::spawn_blocking(move || serde_json::from_reader(std::io::BufReader::new(file)))
            .await??;
    ensure!(
        envelope.contract == "anywork.chat/1",
        "unsupported canonical contract"
    );
    let mut cursor = None;
    let mut bodies = BTreeMap::new();
    let mut head = None;
    loop {
        let page = reader
            .list_bodies(
                detail.header.event_id.clone(),
                cursor,
                HistoryDemand {
                    max_rows: 128,
                    max_bytes: 64 * 1024,
                },
            )
            .await?;
        for entry in page.entries {
            if entry.role == HistoryBodyRole::CanonicalMetadata {
                let bytes = read_complete_body(reader, &entry.reference).await?;
                ensure!(head.is_none(), "duplicate canonical metadata");
                head = Some(serde_json::from_slice::<HistoryEntityHead>(&bytes)?);
            } else if execution_body(&entry.body_key) {
                let bytes = read_complete_body(reader, &entry.reference).await?;
                ensure!(
                    bodies
                        .insert(entry.body_key, String::from_utf8(bytes)?)
                        .is_none(),
                    "duplicate execution body key"
                );
            }
        }
        let Some(next) = page.next else {
            break;
        };
        cursor = Some(next);
    }
    execution_from_parts(
        detail.header,
        head.context("canonical metadata is missing")?,
        envelope,
        bodies,
        thread_id,
    )
}

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct ExecutionEnvelope {
    contract: String,
    #[serde(rename = "type")]
    kind: String,
    data: serde_json::Value,
    source_order: Option<u64>,
    source_effect_seq: Option<u64>,
}

/// Only fields declared by this producer's execution decoder are text. An unrelated host body
/// remains opaque and can be read independently; opening an execution value must not decode it.
fn execution_body(key: &str) -> bool {
    matches!(
        key,
        "body"
            | super::TOOL_ARGUMENTS_FIELD
            | super::TOOL_RESULT_FIELD
            | super::TOOL_OUTPUT_ARTIFACTS_FIELD
            | super::PLAN_DOCUMENT_FIELD
            | super::PLAN_FEEDBACK_FIELD
    ) || key.starts_with("part.outputText.")
        || key.starts_with("part.reasoningText.")
        || key.starts_with("part.summaryText.")
        || key.starts_with(super::TOOL_USER_INPUT_FIELD)
        || key.starts_with(super::RAW_PAYLOAD_FIELD)
}

fn execution_from_parts(
    header: crate::history::HistoryEventHeader,
    head: HistoryEntityHead,
    envelope: ExecutionEnvelope,
    bodies: BTreeMap<String, String>,
    thread_id: &str,
) -> Result<crate::ExecutionItem> {
    ensure!(
        header.entity_id.as_deref() == Some(head.entity_id.as_str()),
        "canonical entity identity differs"
    );
    let order = envelope
        .source_order
        .context("canonical execution order is unknown")?;
    let revision = envelope
        .source_effect_seq
        .context("canonical producer revision is unknown")?;
    let atom = crate::ChatAtom {
        id: head.entity_id.clone(),
        source: head.source,
        source_state: None,
        source_order: Some(order),
        kind: head.kind,
        delivery: head.delivery,
        lifecycle: match head.state {
            HistoryEntityState::KnownTerminal { outcome } => crate::ChatAtomLifecycle::Terminal {
                outcome,
                started: None,
                ended: None,
            },
            _ => anyhow::bail!("canonical execution has no terminal evidence"),
        },
        turn_id: header.turn_id.clone(),
        attempt_id: head.attempt_id,
        tool: head.tool,
        wait: None,
        text_channel: head.text_channel,
        content_present: head.content_present,
        started_at: head.started_at.map(|at| at / 1000),
        finished_at: head.finished_at.map(|at| at / 1000),
        contents: Vec::new(),
        completion_item_id: Some(header.event_id),
        completion_seq: None,
        payload: None,
    };
    let data = serde_json::json!({ "type": envelope.kind, "data": envelope.data });
    let state = super::restore::decode_state(&bodies, &atom, &data, thread_id)?;
    let updated = atom
        .finished_at
        .context("canonical completion time is unknown")?;
    Ok(crate::ExecutionItem::new(
        atom.id,
        thread_id.into(),
        atom.turn_id
            .context("canonical execution Turn is unknown")?,
        order,
        revision,
        atom.started_at.unwrap_or(updated),
        updated,
        state,
    ))
}
pub(crate) fn frozen_execution_item(
    event: &crate::history::HistoryEvent,
    thread_id: &str,
) -> Result<crate::ExecutionItem> {
    use crate::history::HistoryBodyRole;
    let payload = event
        .bodies
        .iter()
        .find(|body| Some(&body.body_id) == event.payload_body_id.as_ref())
        .context("frozen payload is missing")?;
    let envelope: ExecutionEnvelope = serde_json::from_reader(payload.bytes.as_ref())?;
    ensure!(
        envelope.contract == "anywork.chat/1",
        "unsupported frozen producer contract"
    );
    let metadata = event
        .bodies
        .iter()
        .find(|body| body.role == HistoryBodyRole::CanonicalMetadata)
        .context("frozen metadata is missing")?;
    let head = serde_json::from_slice(&metadata.bytes)?;
    let mut bodies = BTreeMap::new();
    for body in &event.bodies {
        if execution_body(&body.body_key) {
            ensure!(
                bodies
                    .insert(
                        body.body_key.clone(),
                        String::from_utf8(body.bytes.to_vec())?
                    )
                    .is_none(),
                "duplicate producer body"
            );
        }
    }
    execution_from_parts(event.header.clone(), head, envelope, bodies, thread_id)
}

async fn read_complete_body(
    reader: &crate::history::HistoryReader,
    reference: &crate::history::HistoryEventBodyRef,
) -> Result<Vec<u8>> {
    let mut bytes = Vec::new();
    let mut offset = 0;
    while offset < reference.byte_length {
        let window = reader
            .read_body(reference.clone(), offset, 64 * 1024)
            .await?;
        ensure!(!window.bytes.is_empty(), "execution body did not advance");
        offset += window.bytes.len() as u64;
        bytes.extend(window.bytes);
    }
    Ok(bytes)
}

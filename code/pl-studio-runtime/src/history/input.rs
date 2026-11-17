//! Durable input-admission facts used for idempotent submission receipts.
//!
//! The event payload keeps only admission identity and routing metadata. User content remains in
//! the canonical input original; this fact records its digest and the immutable receipt fields.

use std::sync::Arc;

use pl_core::thread::input::{
    InputChange, InputContinuation, InputDelivery, InputPurpose, InputRecord, InputState,
};
use sha2::{Digest, Sha256};

use super::*;

const INPUT_FACT_FORMAT: &str = "pl.studio.input-fact";
const INPUT_FACT_VERSION: u32 = 1;
pub(crate) const INPUT_FACT_BODY_KEY: &str = "input_fact";
const INPUT_FACT_MAX_BYTES: u64 = 16 * 1024;
const INPUT_FACT_PAGE_ROWS: u32 = 64;
const INPUT_FACT_PAGE_BYTES: u32 = 256 * 1024;
const INPUT_FACT_MAX_EVENTS: usize = 1024;

/// The complete immutable admission receipt, with the latest input-state fact folded in.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct InputAdmission {
    pub(crate) id: String,
    pub(crate) digest: String,
    /// Hash of the host request and presentation when the payload is a Studio prompt.
    pub(crate) request_digest: Option<String>,
    pub(crate) continuation: Option<InputContinuation>,
    pub(crate) delivery: InputDelivery,
    pub(crate) purpose: InputPurpose,
    pub(crate) ordinal: u64,
    pub(crate) accepted_sequence: u64,
    /// Revision of the original admission, never a later state transition.
    pub(crate) admission_revision: Option<u64>,
    pub(crate) expected_model_route_revision: Option<u64>,
    /// Latest committed state revision represented by this event sequence.
    pub(crate) revision: u64,
    pub(crate) state: InputState,
}

impl InputAdmission {
    pub(crate) fn from_record(
        record: &InputRecord,
        expected_model_route_revision: Option<u64>,
    ) -> Self {
        let request_digest = record_request_digest(record);
        Self {
            id: record.input.id.clone(),
            digest: record.input.digest(),
            request_digest,
            continuation: record.continuation.clone(),
            delivery: record.delivery.clone(),
            purpose: record.input.purpose,
            ordinal: record.ordinal,
            accepted_sequence: record.accepted_sequence,
            admission_revision: Some(record.revision),
            expected_model_route_revision,
            revision: record.revision,
            state: record.state.clone(),
        }
    }
}

/// Hashes the host-authored prompt request and presentation without retaining their content.
pub(crate) fn prompt_request_digest(
    request: &crate::StudioPromptInput,
    presentation: &crate::MessagePresentation,
) -> Result<String> {
    let mut hasher = Sha256::new();
    hasher.update(b"pl.studio.prompt-request\0");
    // Keep the original host identity algorithm: typed request field order, separator, and
    // presentation bytes. Migrated v24 digests must still recognise the same request.
    hasher.update(serde_json::to_vec(request)?);
    hasher.update([0]);
    hasher.update(match presentation {
        crate::MessagePresentation::Visible => b"visible".as_slice(),
        crate::MessagePresentation::Hidden => b"hidden".as_slice(),
    });
    Ok(format!("sha256:{}", hex::encode(hasher.finalize())))
}

/// One immutable transition away from the admission state.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct InputTransition {
    pub(crate) id: String,
    pub(crate) revision: u64,
    pub(crate) state: InputState,
}

/// The typed payload carried by an `input_accepted`, `input_consumed` or `input_discarded` event.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(
    tag = "kind",
    content = "value",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub(crate) enum InputFact {
    Admission(InputAdmission),
    Transition(InputTransition),
}

/// One input fact whose body identity is frozen before the writer's first attempt.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
pub(crate) struct PreparedInputFact {
    pub(crate) fact: InputFact,
    pub(crate) body_id: String,
}

impl InputFact {
    pub(crate) fn from_change(
        change: &InputChange,
        expected_model_route_revision: Option<u64>,
    ) -> Self {
        match change {
            InputChange::Accepted(record) => Self::Admission(InputAdmission::from_record(
                record,
                expected_model_route_revision,
            )),
            InputChange::Transition {
                id,
                revision,
                state,
            } => Self::Transition(InputTransition {
                id: id.clone(),
                revision: *revision,
                state: state.clone(),
            }),
        }
    }

    fn input_id(&self) -> &str {
        match self {
            Self::Admission(admission) => &admission.id,
            Self::Transition(transition) => &transition.id,
        }
    }

    fn event_kind(&self) -> HistoryEventKind {
        match self {
            Self::Admission(_) => HistoryEventKind::InputAccepted,
            Self::Transition(transition) => match &transition.state {
                InputState::Pending => HistoryEventKind::Other("input_pending".into()),
                InputState::Consumed { .. } => HistoryEventKind::InputConsumed,
                InputState::Discarded => HistoryEventKind::InputDiscarded,
            },
        }
    }
}

/// Encodes already-frozen input facts as immutable History events.
pub(crate) fn input_events(
    facts: &[PreparedInputFact],
    run_id: &str,
    effect_sequence: u64,
    recorded_at: i64,
) -> Result<Vec<HistoryEvent>> {
    let mut events = Vec::with_capacity(facts.len());
    for (index, prepared) in facts.iter().enumerate() {
        let event_id = format!(
            "input:{run_id}:{effect_sequence}:{index}:{}",
            prepared.fact.event_kind().as_str()
        );
        let (mut event, _) = input_event(
            event_id,
            Some(run_id.to_owned()),
            recorded_at,
            &prepared.fact,
            prepared.body_id.clone(),
        )?;
        event.header.occurred_at = Some(recorded_at);
        events.push(event);
    }
    Ok(events)
}

/// Builds one encoded input event and its canonical metadata body.
pub(crate) fn input_event(
    event_id: String,
    run_id: Option<String>,
    recorded_at: i64,
    fact: &InputFact,
    body_id: String,
) -> Result<(HistoryEvent, HistoryBody)> {
    if event_id.is_empty() || body_id.is_empty() || fact.input_id().is_empty() {
        return Err(HistoryError::InvalidEvent(
            "input event, body and entity identities must not be empty".into(),
        ));
    }
    let kind = fact.event_kind();
    if matches!(&kind, HistoryEventKind::Other(_)) {
        return Err(HistoryError::InvalidEvent(
            "a pending state is not an input event kind".into(),
        ));
    }
    let payload = pl_core::context::OpaquePayload::new(
        INPUT_FACT_FORMAT,
        INPUT_FACT_VERSION,
        serde_json::to_string(fact)?,
    )
    .map_err(|error| HistoryError::InvalidEvent(error.to_string()))?;
    let bytes: Arc<[u8]> = serde_json::to_vec(&payload)?.into();
    if bytes.len() as u64 > INPUT_FACT_MAX_BYTES {
        return Err(HistoryError::InvalidEvent(
            "input receipt exceeds its metadata budget".into(),
        ));
    }
    let body = HistoryBody {
        body_id,
        body_key: INPUT_FACT_BODY_KEY.into(),
        role: HistoryBodyRole::CanonicalPayload,
        media_type: Some("application/json".into()),
        bytes,
    };
    let mut event = HistoryEvent::new(event_id, kind, recorded_at);
    let has_run_id = run_id.is_some();
    event.header.run_id = run_id;
    event.header.entity_id = Some(fact.input_id().to_owned());
    event.header.source = Some(HistorySource::Input {
        input_id: fact.input_id().to_owned(),
    });
    match fact {
        InputFact::Admission(admission) => {
            if admission.accepted_sequence == 0 {
                return Err(HistoryError::InvalidEvent(
                    "input admission sequence must be positive".into(),
                ));
            }
        }
        InputFact::Transition(_) => {}
    }
    if let Some((turn_id, attempt_id)) = fact_state_context(fact) {
        event.header.turn_id = Some(turn_id.to_owned());
        if has_run_id {
            event.header.attempt_id = Some(attempt_id.to_owned());
        }
    }
    event.payload_body_id = Some(body.body_id.clone());
    event.bodies.push(body.clone());
    Ok((event, body))
}

/// Reads one admission at a fixed cut through the existing entity-event index.
///
/// Pages are bounded and merged in ascending sequence order. Input events never create a head or
/// timeline anchor, so unrelated canonical input originals on the same entity are ignored by body
/// key and cannot make this query walk the timeline.
pub(crate) async fn read_input_admission(
    reader: &HistoryReader,
    input_id: &str,
) -> Result<Option<InputAdmission>> {
    if input_id.is_empty() {
        return Ok(None);
    }
    let (_, through) = reader.capture_committed_position().await?;
    let query = HistoryEventsQuery::Entity {
        entity_id: input_id.to_owned(),
    };
    let demand = HistoryDemand {
        max_rows: INPUT_FACT_PAGE_ROWS,
        max_bytes: INPUT_FACT_PAGE_BYTES,
    };
    let mut pivot = None;
    let mut admission = None;
    let mut event_count = 0usize;
    loop {
        let (_, entries, has_more) = reader
            .events_window(query.clone(), Some(through), pivot, true, demand)
            .await?;
        if entries.is_empty() {
            if has_more {
                return Err(HistoryError::Integrity(
                    "input fact page reported more rows without progress".into(),
                ));
            }
            break;
        }
        for event in &entries {
            if event.header.entity_id.as_deref() != Some(input_id) {
                return Err(HistoryError::Integrity(
                    "input event entity differs from its query".into(),
                ));
            }
            let Some(fact) = read_input_fact(reader, event).await? else {
                continue;
            };
            apply_input_fact(input_id, fact, &mut admission)?;
            event_count += 1;
            if event_count > INPUT_FACT_MAX_EVENTS {
                return Err(HistoryError::Capacity);
            }
        }
        let last = entries
            .last()
            .ok_or_else(|| HistoryError::Integrity("input fact page lost its tail".into()))?;
        if pivot == Some(last.header.seq) {
            return Err(HistoryError::Integrity(
                "input fact pagination did not advance".into(),
            ));
        }
        pivot = Some(last.header.seq);
        if !has_more {
            break;
        }
    }
    Ok(admission)
}

async fn read_input_fact(
    reader: &HistoryReader,
    event: &HistoryEventDetail,
) -> Result<Option<InputFact>> {
    let Some(reference) = event.payload_ref.clone() else {
        return Ok(None);
    };
    if reference.body_key != INPUT_FACT_BODY_KEY {
        return Ok(None);
    }
    if reference.byte_length == 0 || reference.byte_length > INPUT_FACT_MAX_BYTES {
        return Err(HistoryError::Integrity(
            "input fact payload has an invalid bounded length".into(),
        ));
    }
    let max_bytes = u32::try_from(reference.byte_length)
        .map_err(|_| HistoryError::Integrity("input fact payload exceeds u32".into()))?;
    let window = reader.read_body(reference, 0, max_bytes).await?;
    if window.bytes.len() as u64 != window.total_length {
        return Err(HistoryError::Integrity(
            "input fact payload was not read completely".into(),
        ));
    }
    let payload: pl_core::context::OpaquePayload = serde_json::from_slice(&window.bytes)?;
    if payload.format() != INPUT_FACT_FORMAT || payload.version() != INPUT_FACT_VERSION {
        return Err(HistoryError::Integrity(
            "input fact payload format differs".into(),
        ));
    }
    let fact: InputFact = serde_json::from_str(payload.content())?;
    if event.header.kind != fact.event_kind() {
        return Err(HistoryError::Integrity(
            "input fact payload differs from its event kind".into(),
        ));
    }
    Ok(Some(fact))
}

fn apply_input_fact(
    input_id: &str,
    fact: InputFact,
    admission: &mut Option<InputAdmission>,
) -> Result<()> {
    match fact {
        InputFact::Admission(value) => {
            if value.id != input_id || value.accepted_sequence == 0 {
                return Err(HistoryError::Integrity(
                    "input admission identity is invalid".into(),
                ));
            }
            if let Some(existing) = admission
                && existing != &value
            {
                return Err(HistoryError::Integrity(
                    "input identity has conflicting admissions".into(),
                ));
            }
            *admission = Some(value);
        }
        InputFact::Transition(value) => {
            if value.id != input_id {
                return Err(HistoryError::Integrity(
                    "input transition identity differs".into(),
                ));
            }
            let Some(current) = admission.as_mut() else {
                return Err(HistoryError::Integrity(
                    "input transition precedes its admission".into(),
                ));
            };
            if value.revision < current.revision {
                return Err(HistoryError::Integrity(
                    "input transition revision moved backwards".into(),
                ));
            }
            if value.revision == current.revision && value.state != current.state {
                return Err(HistoryError::Integrity(
                    "input transition changed state without a revision".into(),
                ));
            }
            current.revision = value.revision;
            current.state = value.state;
        }
    }
    Ok(())
}

fn fact_state_context(fact: &InputFact) -> Option<(&str, &str)> {
    let state = match fact {
        InputFact::Admission(admission) => &admission.state,
        InputFact::Transition(transition) => &transition.state,
    };
    match state {
        InputState::Consumed {
            turn_id,
            attempt_id,
        } => Some((turn_id, attempt_id)),
        InputState::Pending | InputState::Discarded => None,
    }
}

fn record_request_digest(record: &InputRecord) -> Option<String> {
    if record.input.purpose != InputPurpose::Message
        || record.input.payload.format() != "pl.studio.prompt"
    {
        return None;
    }
    #[derive(serde::Deserialize)]
    struct SavedPrompt {
        request: crate::StudioPromptInput,
        presentation: crate::MessagePresentation,
    }
    let payload: SavedPrompt = serde_json::from_str(record.input.payload.content()).ok()?;
    prompt_request_digest(&payload.request, &payload.presentation).ok()
}

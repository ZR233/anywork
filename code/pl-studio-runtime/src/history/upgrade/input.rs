//! Frozen encoding of imported schema-24 admission metadata. Execution never reads it.
use super::super::*;
use pl_core::thread::input::{InputContinuation, InputDelivery, InputPurpose, InputState};
use std::sync::Arc;
const INPUT_FACT_FORMAT: &str = "pl.studio.input-fact";
const INPUT_FACT_VERSION: u32 = 1;
pub(super) const INPUT_FACT_BODY_KEY: &str = "input_fact";
const INPUT_FACT_MAX_BYTES: u64 = 16 * 1024;

/// The complete immutable admission receipt, with the latest input-state fact folded in.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct InputAdmission {
    pub(super) id: String,
    pub(super) digest: String,
    /// Hash of the host request and presentation when the payload is a Studio prompt.
    pub(super) request_digest: Option<String>,
    pub(super) continuation: Option<InputContinuation>,
    pub(super) delivery: InputDelivery,
    pub(super) purpose: InputPurpose,
    pub(super) ordinal: u64,
    pub(super) accepted_sequence: u64,
    /// Revision of the original admission, never a later state transition.
    pub(super) admission_revision: Option<u64>,
    pub(super) expected_model_route_revision: Option<u64>,
    /// Latest committed state revision represented by this event sequence.
    pub(super) revision: u64,
    pub(super) state: InputState,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(
    tag = "kind",
    content = "value",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub(super) enum InputFact {
    Admission(InputAdmission),
}
impl InputFact {
    fn admission(&self) -> &InputAdmission {
        match self {
            Self::Admission(value) => value,
        }
    }
}

pub(super) fn input_event(
    event_id: String,
    run_id: Option<String>,
    recorded_at: i64,
    fact: &InputFact,
    body_id: String,
) -> Result<(HistoryEvent, HistoryBody)> {
    if event_id.is_empty() || body_id.is_empty() || fact.admission().id.is_empty() {
        return Err(HistoryError::InvalidEvent(
            "input event, body and entity identities must not be empty".into(),
        ));
    }
    let kind = HistoryEventKind::InputAccepted;
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
    event.header.entity_id = Some(fact.admission().id.as_str().to_owned());
    event.header.source = Some(HistorySource::Input {
        input_id: fact.admission().id.as_str().to_owned(),
    });
    if fact.admission().accepted_sequence == 0 {
        return Err(HistoryError::InvalidEvent(
            "input admission sequence must be positive".into(),
        ));
    }
    if let Some((turn_id, attempt_id)) = match &fact.admission().state {
        InputState::Consumed {
            turn_id,
            attempt_id,
        } => Some((turn_id.as_str(), attempt_id.as_str())),
        InputState::Pending | InputState::Discarded => None,
    } {
        event.header.turn_id = Some(turn_id.to_owned());
        if has_run_id {
            event.header.attempt_id = Some(attempt_id.to_owned());
        }
    }
    event.payload_body_id = Some(body.body_id.clone());
    event.bodies.push(body.clone());
    Ok((event, body))
}

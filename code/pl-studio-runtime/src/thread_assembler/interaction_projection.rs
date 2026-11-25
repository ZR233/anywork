//! Shared opaque decoding and replay of the product interaction state machine.
use crate::{InteractionCommand, InteractionRequest, InteractionTransitionError};
use pl_core::context::OpaquePayload;

pub(super) enum DecodeError {
    Unsupported { format: String, version: u32 },
    Json(serde_json::Error),
}

pub(super) fn require_format(payload: &OpaquePayload, expected: &str) -> Result<(), DecodeError> {
    if payload.format() != expected || payload.version() != 1 {
        return Err(DecodeError::Unsupported {
            format: payload.format().into(),
            version: payload.version(),
        });
    }
    Ok(())
}

pub(super) fn decode<T: serde::de::DeserializeOwned>(
    payload: &OpaquePayload,
    expected: &str,
) -> Result<T, DecodeError> {
    require_format(payload, expected)?;
    serde_json::from_str(payload.content()).map_err(DecodeError::Json)
}

pub(super) enum ReplayError {
    Transition(InteractionTransitionError),
    Revision,
}

pub(super) fn replay(
    mut projected: InteractionRequest,
    command: Option<InteractionCommand>,
    revision: u64,
    updated_at: i64,
) -> Result<InteractionRequest, ReplayError> {
    projected.revision = 1;
    if let Some(command) = command {
        let decision = projected.decide(command).map_err(ReplayError::Transition)?;
        projected.apply(decision, updated_at);
    }
    if projected.revision != revision {
        return Err(ReplayError::Revision);
    }
    Ok(projected)
}

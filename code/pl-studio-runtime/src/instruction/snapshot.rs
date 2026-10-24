use pl_core::context::OpaquePayload;
use pl_protocol::{PureError, Result};

use super::{InstructionSnapshot, SNAPSHOT_FORMAT, SNAPSHOT_VERSION, structure};

/// Decodes the current instruction snapshot.
///
/// Obsolete versions are rejected here; only the recovery migration interprets them, so normal
/// model preparation never runs two decoders for the same source of truth. The decoded snapshot
/// must also have the structure its frozen identity implies.
pub(crate) fn decode_snapshot(payload: &OpaquePayload) -> Result<InstructionSnapshot> {
    if payload.format() != SNAPSHOT_FORMAT || payload.version() != SNAPSHOT_VERSION {
        return Err(PureError::ConfigError(format!(
            "unsupported saved instruction snapshot {} version {}; recovery migration required",
            payload.format(),
            payload.version()
        )));
    }
    let snapshot: InstructionSnapshot =
        serde_json::from_str(payload.content()).map_err(|error| {
            PureError::ConfigError(format!("decode saved instruction snapshot: {error}"))
        })?;
    structure::validate(&snapshot)?;
    Ok(snapshot)
}

/// Encodes the current instruction snapshot; the format, version and structure stay owned here.
pub(crate) fn encode_snapshot(snapshot: &InstructionSnapshot) -> Result<OpaquePayload> {
    structure::validate(snapshot)?;
    let content = serde_json::to_string(snapshot)
        .map_err(|error| PureError::ConfigError(format!("encode instruction snapshot: {error}")))?;
    OpaquePayload::new(SNAPSHOT_FORMAT, SNAPSHOT_VERSION, content)
        .map_err(|error| PureError::ConfigError(error.to_string()))
}

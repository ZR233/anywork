//! Committed context reductions are distinct from auxiliary inference accounting.
use super::ProjectionError;

pub(super) fn receipt(
    payload: &pl_core::context::OpaquePayload,
) -> Result<Option<crate::compaction::CompactionReceipt>, ProjectionError> {
    if payload.format() != "pl.studio.compaction" {
        return Ok(None);
    }
    crate::compaction::decode_receipt(payload.version(), payload.content())
        .map(Some)
        .map_err(|error| ProjectionError::UnsupportedOutput(error.to_string()))
}

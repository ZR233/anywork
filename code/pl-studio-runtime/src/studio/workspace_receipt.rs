//! Decoding of a Thread's frozen `studio.workspace` assignment receipt.
//!
//! 创建回执、spawn 返回值与 review 目标解析都消费同一编码；不存在第二套解释。
use crate::AgentWorkspaceAssignmentSnapshot;
use crate::studio::session_data_error::SessionDataError;
use anyhow::{Result, ensure};
use pl_core::context::OpaquePayload;

pub(crate) mod migration;

pub(crate) const EXTENSION: &str = "studio.workspace";
const FORMAT: &str = "pl.studio.workspace";

/// Decodes a snapshot's frozen workspace receipt; `Ok(None)` means the Thread has none.
pub(crate) fn from_snapshot(
    snapshot: &pl_core::thread::ThreadSnapshot,
) -> Result<Option<AgentWorkspaceAssignmentSnapshot>> {
    match snapshot.extensions.get(EXTENSION) {
        Some(record) => from_payload(&record.payload).map(Some),
        None => Ok(None),
    }
}

/// Decodes one `pl.studio.workspace` payload as received from a saved extension record.
pub(crate) fn from_payload(payload: &OpaquePayload) -> Result<AgentWorkspaceAssignmentSnapshot> {
    let binding_error = |source| SessionDataError::WorkspaceBinding {
        format: FORMAT,
        revision: payload.version(),
        source,
    };
    ensure!(
        payload.format() == FORMAT && payload.version() == 3,
        binding_error(anyhow::anyhow!(
            "unsupported workspace receipt encoding; explicit recovery migration is required"
        ))
    );
    serde_json::from_str(payload.content()).map_err(|source| binding_error(source.into()).into())
}

/// Encodes an assignment into the durable `pl.studio.workspace` payload form.
pub(crate) fn to_payload(assignment: &AgentWorkspaceAssignmentSnapshot) -> Result<OpaquePayload> {
    let content = serde_json::to_string(assignment)?;
    Ok(OpaquePayload::new(FORMAT, 3, content)?)
}

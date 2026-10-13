//! Decoding of a Thread's frozen `studio.workspace` assignment receipt.
//!
//! 创建回执、spawn 返回值与 review 目标解析都消费同一编码；不存在第二套解释。
use pl_core::context::OpaquePayload;
use pl_protocol::AgentWorkspaceAssignmentSnapshot;

pub(crate) const EXTENSION: &str = "studio.workspace";
const FORMAT: &str = "pl.studio.workspace";

/// Decodes a snapshot's frozen workspace receipt; `Ok(None)` means the Thread has none.
pub(crate) fn from_snapshot(
    snapshot: &pl_core::thread::ThreadSnapshot,
) -> Result<Option<AgentWorkspaceAssignmentSnapshot>, String> {
    match snapshot.extensions.get(EXTENSION) {
        Some(record) => from_payload(&record.payload).map(Some),
        None => Ok(None),
    }
}

/// Decodes one `pl.studio.workspace` payload as received from a saved extension record.
pub(crate) fn from_payload(
    payload: &OpaquePayload,
) -> Result<AgentWorkspaceAssignmentSnapshot, String> {
    if payload.format() != FORMAT || payload.version() != 1 {
        return Err(format!(
            "unsupported workspace codec {} version {}",
            payload.format(),
            payload.version()
        ));
    }
    serde_json::from_str(payload.content()).map_err(|error| error.to_string())
}

/// Encodes an assignment into the durable `pl.studio.workspace` payload form.
pub(crate) fn to_payload(
    assignment: &AgentWorkspaceAssignmentSnapshot,
) -> Result<OpaquePayload, String> {
    let content = serde_json::to_string(assignment).map_err(|error| error.to_string())?;
    OpaquePayload::new(FORMAT, 1, content).map_err(|error| error.to_string())
}

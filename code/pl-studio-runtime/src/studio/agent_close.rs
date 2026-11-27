//! Durable, monotonic child execution closure; owner shutdown alone never writes this record.
use anyhow::{Result, ensure};
use pl_core::{context::OpaquePayload, thread::ThreadSnapshot};

pub(crate) const EXTENSION: &str = "studio.agent-close";
const FORMAT: &str = "pl.studio.agent-close";

pub(crate) fn state_error(error: &anyhow::Error) -> crate::StateError {
    // The original typed transport error remains the internal cause. Serializing its entire
    // source chain would bypass the worktree boundary's safe SSH/Git diagnostic vocabulary.
    let message = match error
        .chain()
        .find_map(|cause| cause.downcast_ref::<crate::agent::worktree::WorktreeError>())
    {
        Some(worktree @ crate::agent::worktree::WorktreeError::InvalidResource(_)) => {
            worktree.to_string()
        }
        Some(worktree) => worktree.safe_diagnostic(),
        None => format!("{error:#}"),
    };
    crate::StateError {
        code: "agentCloseIncomplete".into(),
        message: message.chars().take(2048).collect(),
        retryable: true,
    }
}

/// Identity of the original terminal effect, never the later close/checkpoint watermark.
pub(crate) fn terminal_report_id(child_id: &str, terminal_sequence: u64) -> String {
    format!(
        "studio.child.{}:{child_id}:{terminal_sequence}",
        child_id.len()
    )
}

#[derive(serde::Serialize, serde::Deserialize)]
#[serde(deny_unknown_fields)]
struct ExplicitClose {}

/// Missing records, including old Closed checkpoints, carry no provable explicit-close intent.
/// Unknown formats and malformed records are errors, never an inferred open or closed state.
pub(crate) fn is_explicitly_closed(snapshot: &ThreadSnapshot) -> Result<bool> {
    let Some(record) = snapshot.extensions.get(EXTENSION) else {
        return Ok(false);
    };
    ensure!(
        record.payload.format() == FORMAT && record.payload.version() == 1,
        "unsupported explicit child close encoding"
    );
    serde_json::from_str::<ExplicitClose>(record.payload.content())?;
    Ok(true)
}

pub(crate) fn encode() -> Result<OpaquePayload> {
    Ok(OpaquePayload::new(
        FORMAT,
        1,
        serde_json::to_string(&ExplicitClose {})?,
    )?)
}

/// The Session has sealed the child's admission. Pause the existing queue before saving
/// the durable close marker, leaving already admitted execution to the normal close path.
pub(crate) async fn commit(thread: &pl_core::thread::ThreadHandle) -> Result<()> {
    thread.drain_execution().await?;
    if !is_explicitly_closed(&thread.snapshot())? {
        thread
            .mutate_extensions(vec![pl_core::thread::extensions::ExtensionMutation::Put {
                id: EXTENSION.into(),
                expected_revision: None,
                payload: encode()?,
            }])
            .await?;
    }
    thread.flush().await?;
    Ok(())
}

/// Cold projections expose resumability, not the previous process owner's resource lifecycle.
pub(in crate::studio) fn directory_status(
    status: crate::ThreadStatus,
    explicit: bool,
) -> crate::ThreadStatus {
    use crate::ThreadStatus;
    if explicit {
        match status {
            ThreadStatus::Closed | ThreadStatus::CloseFailed => status,
            _ => ThreadStatus::Closing,
        }
    } else if matches!(
        status,
        ThreadStatus::Closed | ThreadStatus::Closing | ThreadStatus::CloseFailed
    ) {
        ThreadStatus::Idle
    } else {
        status
    }
}

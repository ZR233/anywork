//! Durable, monotonic child execution closure; owner shutdown alone never writes this record.
use anyhow::{Result, ensure};
use pl_core::{context::OpaquePayload, thread::ThreadSnapshot};

pub(crate) const EXTENSION: &str = "studio.agent-close";
const FORMAT: &str = "pl.studio.agent-close";

#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct AgentCloseOutcome {
    pub target: String,
    pub agents: Vec<AgentCloseResult>,
    pub error: Option<pl_protocol::StateError>,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct AgentCloseResult {
    pub agent_id: String,
    pub execution_closed: bool,
    pub worktree_cleanup: AgentWorktreeCleanup,
}

#[derive(Debug, Clone, PartialEq, serde::Serialize, serde::Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub(crate) enum AgentWorktreeCleanup {
    Pending,
    NotApplicable,
    NotPresent {
        path: String,
        registration_present: bool,
    },
    Removed {
        path: String,
    },
    Failed {
        path: Option<String>,
        error: pl_protocol::StateError,
    },
}

impl AgentWorktreeCleanup {
    pub(crate) fn is_terminal(&self) -> bool {
        matches!(
            self,
            Self::NotApplicable | Self::NotPresent { .. } | Self::Removed { .. }
        )
    }
}

pub(crate) fn state_error(error: &anyhow::Error) -> pl_protocol::StateError {
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
    pl_protocol::StateError {
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

/// The existing model-update mailbox can commit host extensions while a Turn is running.
/// Its unavailable pending binding prevents another paid Turn, without touching the frozen route
/// or interrupting the admitted Turn before the close record actually becomes durable.
pub(crate) async fn commit(thread: &pl_core::thread::ThreadHandle) -> Result<()> {
    if !is_explicitly_closed(&thread.snapshot())? {
        thread
            .queue_deferred_model_update(
                pl_core::thread::DeferredModelUpdate::new(
                    EXTENSION.into(),
                    pl_core::model::ModelFactory::new(ClosedAdmission),
                    None,
                ),
                vec![pl_core::thread::extensions::ExtensionMutation::Put {
                    id: EXTENSION.into(),
                    expected_revision: None,
                    payload: encode()?,
                }],
            )
            .await?;
    }
    thread.flush().await?;
    Ok(())
}

struct ClosedAdmission;
impl pl_core::model::Model for ClosedAdmission {
    async fn open_session(
        &self,
    ) -> Result<pl_core::model::DynModelSession, pl_core::model::ModelError> {
        Err(pl_core::model::ModelError {
            kind: pl_core::model::ModelFailureKind::Unavailable,
            details: None,
            usage: Default::default(),
            source: None,
        })
    }
}

/// Cold projections expose resumability, not the previous process owner's resource lifecycle.
pub(in crate::studio) fn directory_status(
    status: pl_protocol::ThreadStatus,
    explicit: bool,
) -> pl_protocol::ThreadStatus {
    use pl_protocol::ThreadStatus;
    if explicit {
        if status == ThreadStatus::Closed {
            status
        } else {
            ThreadStatus::Closing
        }
    } else if matches!(status, ThreadStatus::Closed | ThreadStatus::Closing) {
        ThreadStatus::Idle
    } else {
        status
    }
}

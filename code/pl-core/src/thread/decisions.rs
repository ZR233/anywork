//! Bounded reads of resident decision identities, without their host-owned content.
//!
//! These values describe current in-memory facts, not execution authority or durable history.
//! A decision retired from resident state must be looked up through the host's reliable history.

/// Maximum resident records and owned identity bytes admitted by one decision read.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DecisionReadLimits {
    /// Maximum combined number of interaction and permission records, regardless of state.
    pub rows: usize,
    /// Maximum sum of UTF-8 identity bytes and `size_of::<DecisionSummary>()` per record.
    pub identity_bytes: usize,
}

/// Interaction state without the response content carried by a resolved interaction.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InteractionDecisionState {
    Pending,
    Resolved,
    Cancelled,
}

/// Typed decision state; a saved permission decision does not grant an execution lease.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DecisionState {
    Interaction(InteractionDecisionState),
    Permission(super::permissions::PermissionState),
}

/// Original decision identity, owning Turn and revision, without prompts or responses.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DecisionSummary {
    pub id: String,
    pub turn_id: String,
    pub revision: u64,
    pub state: DecisionState,
}

/// Complete resident decisions and the budget actually used to inspect and own them.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DecisionSummaries {
    /// Interaction map key order, followed by permission map key order.
    pub decisions: Vec<DecisionSummary>,
    /// Number of distinct resident records checked, not the number of traversal passes.
    pub rows_read: usize,
    /// Sum of each summary's object size and its two owned strings' UTF-8 lengths.
    pub identity_bytes: usize,
}

/// Either the entire resident decision set or an exceeded row/identity-byte limit.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum DecisionRead {
    Complete(DecisionSummaries),
    /// No partial summaries are returned or identities copied when a limit is exceeded.
    LimitExceeded,
}

/// Presence in the pending input queue or the bounded terminal input identity window.
///
/// `Known` proves only resident admission, not durability. `Absent` describes only the fully
/// inspected resident range, not absence from the host's reliable input identity index.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum InputPresenceRead {
    Known {
        rows_read: usize,
    },
    Absent {
        rows_read: usize,
    },
    /// Unchecked resident records remain; absence cannot be inferred from a checked prefix.
    LimitExceeded,
}

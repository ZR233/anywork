//! Synchronous, budgeted resident fact reads; no opaque content leaves the snapshot borrow.

use super::ThreadHandle;
use crate::thread::{
    decisions::{
        DecisionRead, DecisionReadLimits, DecisionState, DecisionSummaries, DecisionSummary,
        InputPresenceRead, InteractionDecisionState,
    },
    interactions::InteractionState,
};

impl ThreadHandle {
    /// Reads all resident decision identities and states within both supplied limits.
    ///
    /// The same short, immutable snapshot borrow covers preflight and copying. Row counts and
    /// UTF-8 identity sizes are checked before any output allocation or identity clone; opaque
    /// prompts, responses, context, continuations and extension mutations are never inspected.
    /// Interactions precede permissions, each in its map's key order. Exceeding either limit (or
    /// overflowing its calculation) returns no prefix. Empty state fits two zero limits.
    ///
    /// This does not wait for the execution owner, change state or prove durable history or
    /// execution authority. Retired decisions remain the host's history responsibility.
    pub fn decision_summaries(&self, limits: DecisionReadLimits) -> DecisionRead {
        let snapshot = self.snapshots.borrow();
        let Some(rows_read) = snapshot
            .interactions
            .len()
            .checked_add(snapshot.permissions.len())
        else {
            return DecisionRead::LimitExceeded;
        };
        if rows_read > limits.rows {
            return DecisionRead::LimitExceeded;
        }

        let identities = snapshot
            .interactions
            .values()
            .map(|record| (record.request.id.as_str(), record.request.turn_id.as_str()))
            .chain(
                snapshot
                    .permissions
                    .values()
                    .map(|record| (record.id.as_str(), record.turn_id.as_str())),
            );
        let mut identity_bytes = 0_usize;
        for (id, turn_id) in identities {
            let Some(total) = identity_bytes
                .checked_add(std::mem::size_of::<DecisionSummary>())
                .and_then(|bytes| bytes.checked_add(id.len()))
                .and_then(|bytes| bytes.checked_add(turn_id.len()))
            else {
                return DecisionRead::LimitExceeded;
            };
            if total > limits.identity_bytes {
                return DecisionRead::LimitExceeded;
            }
            identity_bytes = total;
        }

        let mut decisions = Vec::with_capacity(rows_read);
        for record in snapshot.interactions.values() {
            let state = match &record.state {
                InteractionState::Pending => InteractionDecisionState::Pending,
                InteractionState::Resolved(_) => InteractionDecisionState::Resolved,
                InteractionState::Cancelled => InteractionDecisionState::Cancelled,
            };
            decisions.push(DecisionSummary {
                id: record.request.id.clone(),
                turn_id: record.request.turn_id.clone(),
                revision: record.revision,
                state: DecisionState::Interaction(state),
            });
        }
        for record in snapshot.permissions.values() {
            decisions.push(DecisionSummary {
                id: record.id.clone(),
                turn_id: record.turn_id.clone(),
                revision: record.revision,
                state: DecisionState::Permission(record.state),
            });
        }
        DecisionRead::Complete(DecisionSummaries {
            decisions,
            rows_read,
            identity_bytes,
        })
    }

    /// Checks an input identity without copying its record or inspecting its payload.
    ///
    /// Checks queued input identities first, then terminal identities, charging one row before
    /// each comparison. A match returns the rows checked so far; absence requires full coverage.
    /// Zero rows allow only truly empty resident input state. An empty identity is an ordinary
    /// lookup, not a separate error. The immutable borrow never crosses an asynchronous wait.
    ///
    /// `Known` does not prove durability, and `Absent` does not exclude durable history outside
    /// the resident window; callers must combine this result with their reliable identity index.
    pub fn read_input_presence(&self, input_id: &str, max_rows: usize) -> InputPresenceRead {
        let snapshot = self.snapshots.borrow();
        let identities = snapshot
            .inputs
            .iter()
            .map(|record| record.input.id.as_str())
            .chain(
                snapshot
                    .terminal_inputs
                    .iter()
                    .map(|identity| identity.id.as_str()),
            );
        let mut rows_read = 0_usize;
        for id in identities {
            let Some(next_rows) = rows_read.checked_add(1) else {
                return InputPresenceRead::LimitExceeded;
            };
            if next_rows > max_rows {
                return InputPresenceRead::LimitExceeded;
            }
            rows_read = next_rows;
            if id == input_id {
                return InputPresenceRead::Known { rows_read };
            }
        }
        InputPresenceRead::Absent { rows_read }
    }
}

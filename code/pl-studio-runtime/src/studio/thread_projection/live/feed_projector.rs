//! Lifecycle and interaction status feed.
use super::ProjectionError;
use super::memory_budget::{
    RETAINED_ENTRY_OVERHEAD, RetainedBytes, interaction_request_bytes, optional_bytes,
    turn_state_bytes,
};
use crate::{InteractionRequest, Turn, TurnPhase};
use pl_core::thread::{ThreadEffectBatch, ThreadSnapshot, TurnState};
use std::collections::{BTreeMap, BTreeSet};

/// Which lifecycle notification a projected Turn produces.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::studio) enum TurnEvent {
    Started,
    Updated,
    Completed,
}

/// One non-content change projected from a single committed effect.
///
/// Content is deliberately not part of this vocabulary. The single projection owner writes every
/// committed body and streaming preview into the shared chat session, and the GUI reads them from
/// that one content window; a second content frame on the status feed would be the same bytes on a
/// parallel carrier. The status feed therefore only carries the facts the window does not own —
/// Turn lifecycle and interactions — and no subscriber ever projects content.
#[derive(Debug, Clone)]
pub(in crate::studio) enum LiveEvent {
    Turn { turn: Turn, event: TurnEvent },
    Interaction(Box<InteractionRequest>),
}

impl RetainedBytes for LiveEvent {
    /// Conservative retained-memory estimate of this one status-feed event.
    ///
    /// The estimate covers the event's own shell (`size_of::<LiveEvent>()`, an interaction's `Box`
    /// pointer included) plus the independently owned variable-length bodies it carries: a Turn's
    /// identities and its state's diagnostics, an interaction's scope, purpose, questions,
    /// accepted answers, approval request, continuation and lifecycle reasons. It follows the same
    /// style as the placement estimate: every body is walked in place,
    /// nothing is serialized or cloned into a `ExecutionItem`, every keyed entry pays a fixed
    /// [`RETAINED_ENTRY_OVERHEAD`] shell, and all arithmetic saturates. Content bodies are
    /// deliberately absent from this vocabulary (see [`LiveEvent`]), so no event charges bytes the
    /// content window owns, and the items a commit also produced are charged by
    /// `PreparedEffect::retained_bytes` — a status-feed event is a separate resident fact, never
    /// the shared `Arc` of a prepared batch.
    ///
    /// Shell contract: the value includes the element's own shell, so a caller holding a
    /// `Vec<LiveEvent>` charges only its spare capacity on top — `(capacity - len) *
    /// size_of::<LiveEvent>()` — instead of re-charging the shells of the elements it already
    /// holds; an empty list therefore adds no dynamic budget.
    fn retained_bytes(&self) -> u64 {
        match self {
            Self::Turn { turn, .. } => (std::mem::size_of::<Self>() as u64)
                .saturating_add(turn.id.len() as u64)
                .saturating_add(turn.thread_id.len() as u64)
                .saturating_add(optional_bytes(turn.input_id.as_deref()))
                .saturating_add(turn_state_bytes(&turn.state)),
            Self::Interaction(interaction) => (std::mem::size_of::<Self>() as u64)
                .saturating_add(std::mem::size_of::<InteractionRequest>() as u64)
                .saturating_add(interaction_request_bytes(interaction)),
        }
    }
}

impl LiveEvent {
    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        RetainedBytes::retained_bytes(self)
    }
}

#[derive(Default)]
pub(super) struct FeedProjector {
    hidden_inputs: BTreeSet<String>,
    turns_seen: BTreeSet<String>,
    turn_phases: BTreeMap<String, TurnPhase>,
    turn_failures: BTreeMap<String, crate::TurnFailure>,
}

impl RetainedBytes for FeedProjector {
    fn retained_bytes(&self) -> u64 {
        let mut bytes = 0_u64;
        for identity in &self.hidden_inputs {
            bytes = bytes
                .saturating_add(identity.len() as u64)
                .saturating_add(RETAINED_ENTRY_OVERHEAD);
        }
        for turn_id in &self.turns_seen {
            bytes = bytes
                .saturating_add(turn_id.len() as u64)
                .saturating_add(RETAINED_ENTRY_OVERHEAD);
        }
        for (turn_id, failure) in &self.turn_failures {
            bytes = bytes
                .saturating_add(turn_id.len() as u64)
                .saturating_add(serde_json::to_vec(failure).map_or(0, |bytes| bytes.len() as u64));
        }
        for turn_id in self.turn_phases.keys() {
            bytes = bytes
                .saturating_add(turn_id.len() as u64)
                .saturating_add(RETAINED_ENTRY_OVERHEAD);
        }
        bytes
    }
}

impl FeedProjector {
    pub(super) fn projection_facts(
        &self,
        effect: &ThreadEffectBatch,
        state: &ThreadSnapshot,
    ) -> (BTreeMap<String, crate::TurnFailure>, BTreeSet<String>) {
        let mut turn_failures = self.turn_failures.clone();
        turn_failures.retain(|turn, _| state.turns.iter().any(|record| &record.turn_id == turn));
        if let Some(attempt) = &effect.attempt {
            if let pl_core::thread::AttemptOutcome::Failed(error) = &attempt.outcome {
                turn_failures.insert(
                    attempt.turn_id.clone(),
                    super::super::turns::model_failure(error),
                );
            } else if matches!(attempt.outcome, pl_core::thread::AttemptOutcome::Running) {
                turn_failures.remove(&attempt.turn_id);
            }
        }
        let mut hidden_inputs = self.hidden_inputs.clone();
        for change in effect.inputs.iter() {
            if let pl_core::thread::input::InputChange::Accepted(record) = change
                && super::super::input_presentation(record) == crate::MessagePresentation::Hidden
            {
                hidden_inputs.insert(record.input.id.clone());
            }
        }
        (turn_failures, hidden_inputs)
    }

    pub(super) fn remember_projection(
        &mut self,
        turn_failures: BTreeMap<String, crate::TurnFailure>,
        hidden_inputs: BTreeSet<String>,
    ) {
        self.turn_failures = turn_failures;
        self.hidden_inputs = hidden_inputs;
    }

    pub(super) fn retain(&mut self, live: &BTreeSet<String>) {
        self.turn_phases.retain(|turn_id, _| live.contains(turn_id));
        self.turns_seen.retain(|turn_id| live.contains(turn_id));
    }

    /// Maintains lifecycle continuity and optionally emits this effect's Turn and interaction frames.
    ///
    /// The frames are derived from the same effect-matched state the content was projected from, so
    /// a live subscriber and durable history describe one commit rather than two drifting views.
    pub(super) fn prepare_turn_frames(
        &self,
        thread: &crate::Thread,
        effect: &ThreadEffectBatch,
        state: &ThreadSnapshot,
        deliver: bool,
    ) -> Result<BTreeMap<String, Turn>, ProjectionError> {
        let mut turns = BTreeMap::new();
        if deliver {
            for record in effect
                .turn
                .iter()
                .chain(state.turns.iter().filter(|record| {
                    record.state == TurnState::Running
                        && self.turn_phases.get(&record.turn_id)
                            != Some(&super::super::turns::phase(state, &record.turn_id))
                }))
            {
                let turn = super::super::turns::project_turn(
                    &thread.id,
                    state,
                    record,
                    effect.committed_at,
                    effect.committed_at,
                    effect.sequence,
                )?;
                turns.insert(record.turn_id.clone(), turn);
            }
        }
        Ok(turns)
    }

    pub(super) fn emit_frames(
        &mut self,
        thread: &crate::Thread,
        effect: &ThreadEffectBatch,
        state: &ThreadSnapshot,
        mut turns: BTreeMap<String, Turn>,
        events: &mut Option<Vec<LiveEvent>>,
    ) {
        if let Some(record) = &effect.turn {
            let event = if record.state == TurnState::Running {
                if self.turns_seen.insert(record.turn_id.clone()) {
                    TurnEvent::Started
                } else {
                    TurnEvent::Updated
                }
            } else {
                self.turns_seen.insert(record.turn_id.clone());
                TurnEvent::Completed
            };
            if record.state == TurnState::Running {
                self.turn_phases.insert(
                    record.turn_id.clone(),
                    super::super::turns::phase(state, &record.turn_id),
                );
            } else {
                self.turn_phases.remove(&record.turn_id);
            }
            if let Some(events) = events.as_mut() {
                let turn = turns
                    .remove(&record.turn_id)
                    .expect("effect Turn frame was validated before projection");
                events.push(LiveEvent::Turn { turn, event });
            }
        }
        // A Turn record is only committed when a Turn starts or finishes, but a task start, a tool
        // completion or a model attempt commit changes the running Turn's derived phase. Publishing
        // each real phase transition keeps the activity row on the canonical phase instead of the
        // phase captured at Turn start. The frame carries the same revision as the item updates of
        // this effect, so a late busy frame can never outrank the terminal Turn.
        for record in state.turns.iter() {
            if record.state != TurnState::Running {
                continue;
            }
            let phase = super::super::turns::phase(state, &record.turn_id);
            if self.turn_phases.get(&record.turn_id) == Some(&phase) {
                continue;
            }
            self.turn_phases.insert(record.turn_id.clone(), phase);
            let event = if self.turns_seen.insert(record.turn_id.clone()) {
                TurnEvent::Started
            } else {
                TurnEvent::Updated
            };
            if let Some(events) = events.as_mut() {
                let turn = turns
                    .remove(&record.turn_id)
                    .expect("phase Turn frame was validated before projection");
                events.push(LiveEvent::Turn { turn, event });
            }
        }
        if let Some(events) = events.as_mut() {
            for record in effect.interactions.iter() {
                if let Ok(Some(interaction)) = crate::thread_assembler::project_thread_interaction(
                    &thread.id,
                    &record.request.id,
                    state,
                ) {
                    events.push(LiveEvent::Interaction(Box::new(interaction)));
                }
            }
            for permission in effect.permissions.iter() {
                if let Ok(Some(interaction)) = crate::thread_assembler::project_thread_interaction(
                    &thread.id,
                    &permission.id,
                    state,
                ) {
                    events.push(LiveEvent::Interaction(Box::new(interaction)));
                }
            }
        }
        let mut active_inputs = state
            .turns
            .iter()
            .filter_map(|turn| {
                (turn.state == TurnState::Running)
                    .then_some(turn.input_id.as_deref())
                    .flatten()
            })
            .collect::<BTreeSet<_>>();
        active_inputs.extend(state.inputs.iter().map(|record| record.input.id.as_str()));
        self.hidden_inputs
            .retain(|id| active_inputs.contains(id.as_str()));
    }
}

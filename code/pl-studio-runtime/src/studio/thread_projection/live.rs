//! Current RAM projection and immutable History facts owned by the Thread observation worker.
//!
//! Current is derived directly from the latest Core snapshot and never reads History for previews.
//! Each admitted HistoryExport produces stateless atomic Schema 26 events, and the archive writer
//! consumes the same prepared immutable batch. Current publication and JSON saving do not wait
//! for its commit.
//!
//! Bounded Runtime tables retain active identities, report facts and original bodies still needed
//! for reliable handoff. Every effect resolves from those RAM facts and its own snapshot; neither
//! Current streaming nor restart reads or replays History into a new runtime epoch.

use super::ProjectionError;
use crate::studio::storage::thread_writer::RuntimeOrderIndex;
use crate::{ExecutionItem, ExecutionShape};
use pl_core::{
    chat::ChatDraft,
    thread::{ThreadEffectBatch, ThreadSnapshot, current::RuntimeEpoch},
};
use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

pub(super) fn history_millis(at: i64) -> Result<i64, ProjectionError> {
    crate::history::milliseconds_from_seconds(at)
        .map_err(|error| ProjectionError::History(error.to_string()))
}

fn completion_ready(item: &ExecutionItem) -> bool {
    item.is_terminal()
        && !matches!(
            item.state(),
            ExecutionShape::Tool(tool) if tool.user_input().is_some_and(|input| matches!(
                input.state(), crate::ThreadToolUserInputState::Pending
            ))
        )
}

/// Upper bounds for the short replay window a live projection retains.
///
/// The projection is a bounded observation owner, not a second history: the committed facts it
/// keeps are the ones a running Turn can still reference, and anything older is read from durable
/// history on reconnect. These windows never grow with the Thread's history.
pub(in crate::studio) const LIVE_ITEM_WINDOW: usize = 1024;

/// Commentary parts kept as the fallback text of a Turn that committed no final summary.
///
/// The report's result is the committed final text, which is kept in full. A Turn that stopped
/// without one is described by the tail of its visible commentary; this bound keeps that diagnostic
/// from turning the report accumulator into the Turn's whole process log.
pub(in crate::studio) const TURN_COMMENTARY_PARTS: usize = 16;

mod history_effect;
use history_effect::ProjectedContent;
pub(super) mod memory_budget;
mod placement_window;
pub(crate) mod prepared;
mod preview_cache;
mod turn_result;
use placement_window::PlacementWindow;
use preview_cache::PreviewCache;
use provenance::{ProvenanceLedger, ProvenanceWindow};

use memory_budget::RetainedBytes;
pub(in crate::studio) use prepared::PreparedEffect;
use prepared::{history_sources, prepared_turns, retained_resources};
pub(in crate::studio) use turn_result::TurnResult;
pub(super) mod provenance;

/// Folds admitted writes for internal report/accounting/archive handoff.
/// Timeline & live status projections live in `crate::timeline`.
pub(in crate::studio) struct LiveProjection {
    provenance: ProvenanceLedger,
    placement: PlacementWindow,
    previews: PreviewCache,
    /// Report facts of the newest Turn.
    results: BTreeMap<String, TurnResult>,
    turn_failures: BTreeMap<String, crate::TurnFailure>,
    hidden_inputs: BTreeSet<String>,
    run: Option<RuntimeEpoch>,
    database_id: Option<String>,
    owner_id: Option<String>,
    bus_admitted: bool,
}

impl LiveProjection {
    pub(in crate::studio) fn new() -> Self {
        Self {
            provenance: Default::default(),
            placement: Default::default(),
            previews: Default::default(),
            results: BTreeMap::new(),
            turn_failures: BTreeMap::new(),
            hidden_inputs: BTreeSet::new(),
            run: None,
            database_id: None,
            owner_id: None,
            bus_admitted: false,
        }
    }

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
                    super::turns::model_failure(error),
                );
            } else if matches!(attempt.outcome, pl_core::thread::AttemptOutcome::Running) {
                turn_failures.remove(&attempt.turn_id);
            }
        }
        let mut hidden_inputs = self.hidden_inputs.clone();
        for change in effect.inputs.iter() {
            if let pl_core::thread::input::InputChange::Accepted(record) = change
                && super::content::input_presentation(record) == crate::MessagePresentation::Hidden
            {
                hidden_inputs.insert(record.input.id.clone());
            }
        }
        (turn_failures, hidden_inputs)
    }

    pub(super) fn remember_projection(
        &mut self,
        turn_failures: BTreeMap<String, crate::TurnFailure>,
        mut hidden_inputs: BTreeSet<String>,
    ) {
        for turn_id in turn_failures.keys() {
            hidden_inputs.remove(turn_id);
        }
        self.turn_failures = turn_failures;
        self.hidden_inputs = hidden_inputs;
    }

    pub(in crate::studio) fn bind_execution(
        &mut self,
        index: Arc<RuntimeOrderIndex>,
        run: RuntimeEpoch,
        database_id: String,
    ) -> Result<(), ProjectionError> {
        if self.run.is_some() {
            return Err(ProjectionError::History(
                "execution history is already bound".into(),
            ));
        }
        self.placement.bind(index);
        self.run = Some(run);
        self.database_id = Some(database_id);
        self.owner_id = Some(run.to_string());
        Ok(())
    }

    pub(in crate::studio) fn mark_bus_admitted(&mut self) {
        self.bus_admitted = true;
    }

    pub(in crate::studio) fn owner_id(&self) -> Option<&str> {
        self.owner_id.as_deref()
    }

    pub(in crate::studio) fn turn_result(&self, turn_id: &str) -> Option<&TurnResult> {
        self.results.get(turn_id)
    }

    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        let mut bytes = self
            .placement
            .retained_bytes()
            .saturating_add(self.previews.retained_bytes())
            .saturating_add(self.provenance.retained_bytes());
        for (turn_id, result) in &self.results {
            bytes = bytes
                .saturating_add(turn_id.len() as u64)
                .saturating_add(result.retained_bytes());
        }
        bytes
    }

    pub(in crate::studio) fn restore_current(
        &mut self,
        _thread: &crate::Thread,
        _state: &ThreadSnapshot,
    ) -> Result<(), ProjectionError> {
        if self.provenance.restored {
            return Err(ProjectionError::History(
                "current provenance was already restored".into(),
            ));
        }
        self.provenance.restored = true;
        Ok(())
    }

    pub(in crate::studio) fn confirm_sources(&mut self, through: u64) {
        self.provenance.confirm_sources(through);
    }

    pub(in crate::studio) fn prepare_committed(
        &mut self,
        thread: &crate::Thread,
        effect: &ThreadEffectBatch,
        state: &ThreadSnapshot,
    ) -> Result<Arc<PreparedEffect>, ProjectionError> {
        let run = self
            .run
            .ok_or_else(|| ProjectionError::History("runtime epoch is not bound".into()))?;
        self.previews.stage_history_model_previews(
            &mut self.placement,
            state,
            effect.committed_at,
            &self.provenance,
        )?;
        self.previews.stage_history_tool_previews(
            &mut self.placement,
            thread,
            state,
            effect.committed_at,
        )?;
        let provenance = self.provenance.begin_provenance(
            effect,
            ProvenanceWindow {
                run,
                placement: &mut self.placement,
                previews: &mut self.previews,
                current_owner_id: self.owner_id.as_deref(),
                history_database_id: self.database_id.as_deref(),
            },
        )?;
        let accounting = super::PreparedAccounting::shared(effect)?;
        let ProjectedContent {
            items,
            review_delivery,
            completion_drafts,
        } = self.project(thread, effect, state)?;
        let (history_events, history_sources_raw) = self.provenance.complete_provenance(
            effect,
            state,
            &items,
            &completion_drafts,
            provenance,
            ProvenanceWindow {
                run,
                placement: &mut self.placement,
                previews: &mut self.previews,
                current_owner_id: self.owner_id.as_deref(),
                history_database_id: self.database_id.as_deref(),
            },
        )?;
        self.retire_effect_source(effect)?;
        let (history_turns, history_turn_details) = prepared_turns(&items, run, effect.sequence)?;
        let terminal_turn_id = effect
            .turn
            .as_ref()
            .filter(|record| record.state != pl_core::thread::TurnState::Running)
            .map(|record| record.turn_id.clone());
        let prepared = Arc::new(PreparedEffect {
            sequence: effect.sequence,
            committed_at: effect.committed_at,
            run_id: run,
            accounting,
            history_events: history_events.into(),
            history_turns: history_turns.into(),
            history_turn_details: Arc::new(history_turn_details),
            history_sources: history_sources(&history_sources_raw).into(),
            retained_resources: retained_resources(effect)?.into(),
            terminal_turn_id,
            parent_report: None,
            parent_finish: None,
            terminal_retention: None,
            review_delivery: review_delivery.into(),
            bus_admitted: self.bus_admitted,
        });
        self.mark_completed_drafts(&completion_drafts);
        self.retain(state);
        Ok(prepared)
    }

    fn mark_completed_drafts(&self, drafts: &[ChatDraft]) {
        if let Ok(index) = self.placement.order_index_of() {
            for draft in drafts {
                index.mark_completion(&draft.item_id, true);
            }
        }
    }

    fn retire_effect_source(&self, effect: &ThreadEffectBatch) -> Result<(), ProjectionError> {
        if let Some(attempt) = &effect.attempt
            && !matches!(attempt.outcome, pl_core::thread::AttemptOutcome::Running)
        {
            self.placement
                .order_index_of()?
                .finish_source(&attempt.attempt_id);
        }
        Ok(())
    }

    fn retain(&mut self, state: &ThreadSnapshot) {
        let (live, referenced) = placement_window::retained_identities(state);
        self.placement
            .retain(&live, &referenced, &mut self.previews);
        self.results.retain(|turn_id, _| live.contains(turn_id));
        self.provenance.retain(state, &self.placement, &referenced);
    }
}

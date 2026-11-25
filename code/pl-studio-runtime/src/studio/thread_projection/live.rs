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
use std::{collections::BTreeMap, sync::Arc};

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

mod current;
mod feed_projector;
mod history_effect;
use history_effect::ProjectedContent;
pub(super) mod memory_budget;
mod placement_window;
mod prepared;
mod preview_cache;
mod turn_result;
use feed_projector::FeedProjector;
pub(in crate::studio) use feed_projector::{LiveEvent, TurnEvent};
use placement_window::PlacementWindow;
use preview_cache::PreviewCache;
use provenance::{ProvenanceLedger, ProvenanceWindow};

use memory_budget::RetainedBytes;
pub(in crate::studio) use prepared::PreparedEffect;
use prepared::{history_sources, prepared_turns, retained_resources};
pub(in crate::studio) use turn_result::TurnResult;
pub(super) mod provenance;

/// Folds admitted writes into the live product facts and yields the changes each one made.
pub(in crate::studio) struct LiveProjection {
    provenance: ProvenanceLedger,
    placement: PlacementWindow,
    previews: PreviewCache,
    feed: FeedProjector,
    /// Report facts of the newest Turn.
    results: BTreeMap<String, TurnResult>,
    run: Option<RuntimeEpoch>,
    database_id: Option<String>,
    current: super::current::CurrentOwner,
}

impl LiveProjection {
    /// Creates an empty projection owner.
    ///
    /// Installation binds the channel index and seeds provenance from the current Core owner.
    /// No historical payload is loaded into this projection.
    pub(in crate::studio) fn new() -> Self {
        Self {
            provenance: Default::default(),
            placement: Default::default(),
            previews: Default::default(),
            feed: Default::default(),
            results: BTreeMap::new(),
            run: None,
            database_id: None,
            current: Default::default(),
        }
    }

    /// Bind the channel's RAM allocation authority, runtime epoch and database identity once.
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
        self.current
            .bind(run.to_string())
            .map_err(|error| ProjectionError::History(error.to_string()))?;
        Ok(())
    }
    pub(in crate::studio) fn current_state(&self) -> Option<Arc<super::CurrentState>> {
        self.current.snapshot()
    }

    pub(in crate::studio) fn current_activity(&self) -> Option<crate::ThreadActivity> {
        self.current.activity()
    }

    fn observe_current(
        &mut self,
        thread: &crate::Thread,
        state: &ThreadSnapshot,
        sequence: u64,
    ) -> Result<(), ProjectionError> {
        let owner_id = self
            .current
            .owner_id()
            .ok_or_else(|| ProjectionError::History("current owner is not bound".into()))?
            .to_owned();
        let current = current::project(thread, state, &owner_id)?;
        // Effects own terminal source transitions that are no longer present in Core's live
        // snapshot. Merge the new snapshot into that monotonic owner history instead of replacing it.
        self.current.provenance(
            self.provenance.merge_current_sources(current.sources),
            current.atoms,
        );
        self.current
            .observe(thread, state, sequence, current.active)
            .map_err(|error| ProjectionError::History(error.to_string()))?;
        Ok(())
    }

    /// Report facts of one Turn, if the projection still holds them.
    pub(in crate::studio) fn turn_result(&self, turn_id: &str) -> Option<&TurnResult> {
        self.results.get(turn_id)
    }

    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        let mut bytes = self
            .placement
            .retained_bytes()
            .saturating_add(self.previews.retained_bytes())
            .saturating_add(self.current.retained_bytes())
            .saturating_add(self.provenance.retained_bytes())
            .saturating_add(self.feed.retained_bytes());
        for (turn_id, result) in &self.results {
            bytes = bytes
                .saturating_add(turn_id.len() as u64)
                .saturating_add(result.retained_bytes());
        }
        bytes
    }

    /// Execution activation only. Passive conversation opens never create this owner or scan history.
    pub(in crate::studio) fn restore_current(
        &mut self,
        thread: &crate::Thread,
        state: &ThreadSnapshot,
    ) -> Result<(), ProjectionError> {
        if self.provenance.restored {
            return Err(ProjectionError::History(
                "current provenance was already restored".into(),
            ));
        }
        let sequence = state.commit_sequence;
        self.provenance.restored = true;
        self.observe_current(thread, state, sequence)
    }

    pub(in crate::studio) fn confirm_sources(&mut self, through: u64) {
        self.provenance.confirm_sources(through);
    }

    /// Projects one admitted write and freezes its publication work without awaiting publication.
    ///
    /// The owner must retain and charge this batch before calling `publish_prepared`. A history
    /// error or cancellation then resumes the same frozen drafts, never the projection.
    ///
    /// `deliver` controls only outward frame materialization. Phase, hidden-input and Turn identity
    /// session publication and the reliable prepared batch never depend on demand.
    ///
    /// # Errors
    /// Returns a projection failure when the effect references facts this projection cannot resolve
    /// from memory. The caller reports it, so the durable barrier fails closed with the real reason
    /// instead of writing a timeline with a hole.
    pub(in crate::studio) fn prepare(
        &mut self,
        thread: &crate::Thread,
        effect: &ThreadEffectBatch,
        state: &ThreadSnapshot,
        deliver: bool,
    ) -> Result<(Option<Vec<LiveEvent>>, Arc<PreparedEffect>), ProjectionError> {
        self.prepare_inner(thread, effect, state, deliver)
    }

    fn prepare_inner(
        &mut self,
        thread: &crate::Thread,
        effect: &ThreadEffectBatch,
        state: &ThreadSnapshot,
        emit_feed: bool,
    ) -> Result<(Option<Vec<LiveEvent>>, Arc<PreparedEffect>), ProjectionError> {
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
                current_owner_id: self.current.owner_id(),
                history_database_id: self.database_id.as_deref(),
            },
        )?;
        let accounting = Arc::new(super::PreparedAccounting::prepare(effect)?);
        let turns = self
            .feed
            .prepare_turn_frames(thread, effect, state, emit_feed)?;
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
                current_owner_id: self.current.owner_id(),
                history_database_id: self.database_id.as_deref(),
            },
        )?;
        let mut events = emit_feed.then(Vec::new);
        self.feed
            .emit_frames(thread, effect, state, turns, &mut events);
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
        });
        self.mark_completed_drafts(&completion_drafts);
        if let Some(events) = events.as_mut()
            && let Some(canonical) = super::prepared_terminal_turn(&prepared)
        {
            for event in events {
                if let LiveEvent::Turn { turn, .. } = event
                    && turn.id == canonical.id
                {
                    *turn = canonical.clone();
                }
            }
        }
        self.retain(state);
        Ok((events, prepared))
    }

    /// Projects one admitted write this owner installed *behind*: it folds the fact into memory and
    /// returns the frozen publication work, but emits no live status frames.
    ///
    /// A commit the owner had already folded into the snapshot this projection was seeded from is
    /// never replayed as a live frame — the subscriber's baseline already carries it — yet the
    /// durable writer still owes it a row, so the same single projection produces its content here.
    ///
    /// # Errors
    /// Same as [`LiveProjection::prepare`].
    pub(in crate::studio) fn prepare_committed(
        &mut self,
        thread: &crate::Thread,
        effect: &ThreadEffectBatch,
        state: &ThreadSnapshot,
    ) -> Result<Arc<PreparedEffect>, ProjectionError> {
        self.prepare_inner(thread, effect, state, false)
            .map(|(_, prepared)| prepared)
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

    /// Publishes Current exclusively from the newest Core owner snapshot.
    ///
    /// The pure Current projector reads running model parts, running task invocations and progress,
    /// pending inputs and unconsumed inbox messages. It never consults History placement, archive
    /// completion, or a canonical final, so a History projection failure cannot hold Current behind.
    pub(in crate::studio) fn stream(
        &mut self,
        thread: &crate::Thread,
        state: &ThreadSnapshot,
    ) -> Result<(), ProjectionError> {
        self.observe_current(thread, state, state.commit_sequence)
    }

    fn retain(&mut self, state: &ThreadSnapshot) {
        let (live, referenced) = placement_window::retained_identities(state);
        self.placement
            .retain(&live, &referenced, &mut self.previews);
        self.results.retain(|turn_id, _| live.contains(turn_id));
        self.feed.retain(&live);
        self.provenance.retain(state, &self.placement, &referenced);
    }
}

#[cfg(test)]
mod append_only_history_tests;

//! Unified conversation feed & session metadata API for Native & cold threads.
//!
//! Live threads attach directly to the resident `MetaEventBus` (pure RAM deltas + 16ms coalesced
//! live status); cold threads read exclusively from `HistoryReader` and `Thread` directory state
//! without touching `current.json` or activating execution.

use anyhow::Result;
use pl_core::thread::UsageSummary;

use crate::history::{HistoryBusinessRowHead, HistoryDemand, HistoryReader};
use crate::studio::StudioRuntime;
use crate::timeline::{ConversationFeed, SessionMetaLayer, SessionMetaSnapshot};

impl StudioRuntime {
    /// Opens a unified `ConversationFeed` for `thread_id` (live `MetaEventBus` if resident +
    /// bounded `HistoryReader` stitching `history.sqlite ∪ Pending` on cold open & paging).
    pub async fn open_conversation_feed(
        &self,
        thread_id: &str,
        initial_limit: u32,
    ) -> Result<ConversationFeed> {
        let thread = self.read_protocol_thread(thread_id).await?;
        self.check_thread_read_access(&thread)?;
        let reader = self.store.open_history_reader(thread_id).await?;
        let slot = self.thread_observations.observation_slot(thread_id);
        let bus_rx = slot.subscribe_bus();
        let bus = slot.meta_bus();
        let initial_meta = self
            .build_session_meta_snapshot(&thread, Some(&reader), bus.as_ref())
            .await?;
        let feed = ConversationFeed::open(
            thread_id,
            reader,
            bus_rx,
            initial_meta,
            initial_limit.max(1),
        )
        .await?;
        slot.register_feed(feed.close_handle());
        Ok(feed)
    }

    /// Reads the latest `SessionMetaSnapshot` (pure RAM from resident `MetaEventBus` / `ThreadHandle`
    /// if open, otherwise cold metadata + latest durable turn/usage from `HistoryReader`).
    pub async fn thread_session_meta(&self, thread_id: &str) -> Result<SessionMetaSnapshot> {
        let thread = self.read_protocol_thread(thread_id).await?;
        self.check_thread_read_access(&thread)?;
        let bus = self.thread_observations.meta_bus(thread_id);
        if let Some(meta) = bus.as_ref().and_then(|bus| bus.latest_meta()) {
            return Ok((*meta).clone());
        }
        let reader = self.store.open_history_reader(thread_id).await.ok();
        let snapshot = self
            .build_session_meta_snapshot(&thread, reader.as_ref(), bus.as_ref())
            .await?;
        if let Some(reader) = reader {
            reader.close().await;
        }
        Ok(snapshot)
    }

    async fn build_session_meta_snapshot(
        &self,
        thread: &crate::Thread,
        reader: Option<&HistoryReader>,
        bus: Option<&crate::timeline::MetaEventBus>,
    ) -> Result<SessionMetaSnapshot> {
        if let Some(meta) = bus.and_then(|bus| bus.latest_meta()) {
            return Ok((*meta).clone());
        }

        if let Some(handle) = self
            .session_of(&thread.id)
            .and_then(|session| session.observed_thread(&thread.id))
        {
            let snapshot = handle.snapshot();
            let persistence = self
                .store
                .thread_persistence()
                .snapshot()
                .threads
                .into_iter()
                .find(|detail| detail.thread_id == thread.id);
            let runtime = crate::studio::thread_projection::project_runtime(
                &thread.id,
                &snapshot,
                thread.updated_at,
                &snapshot.usage_summary,
            )?;
            let mut model_route = crate::studio::model_route::projected(&snapshot)?;
            if let Ok((config, _)) = self.config_runtime.read_with_catalog() {
                let _ = crate::studio::model_route::annotate_availability(
                    model_route.as_mut(),
                    thread,
                    &config.config,
                );
            }
            let active_turn = crate::studio::thread_projection::project_active_turn(
                &thread.id,
                &snapshot,
                thread.updated_at,
            )?;
            let last_turn = self
                .thread_observations
                .observation_slot(&thread.id)
                .last_turn()
                .map(|turn| (*turn).clone());
            let activity =
                crate::studio::thread_projection::project_activity(&thread.id, &snapshot, None);
            let storage_state = persistence
                .as_ref()
                .map(|detail| crate::studio::thread_projection::storage_state(&snapshot, detail));
            let interactions =
                crate::studio::thread_projection::project_interactions(&thread.id, &snapshot)?;
            let pending_interaction_count = u32::try_from(interactions.len()).unwrap_or(u32::MAX);
            let plan = runtime.plan.clone();
            let context_metrics = Some(runtime.usage.clone());
            return Ok(SessionMetaSnapshot {
                thread_id: thread.id.clone(),
                status: crate::studio::thread_projection::status(&snapshot),
                title: Some(thread.title.clone()),
                parent_thread_id: thread.parent_thread_id.clone(),
                root_thread_id: thread.root_thread_id.clone(),
                owner_epoch: handle.runtime_epoch().to_string(),
                revision: snapshot.commit_sequence,
                active_turn,
                last_turn,
                activity,
                usage: snapshot.usage_summary,
                context_metrics,
                model_route,
                runtime: Some(runtime),
                storage_state,
                interactions,
                pending_interaction_count,
                plan,
                mode: thread.mode.clone(),
                execution_present: snapshot.execution.is_some(),
            });
        }

        // Cold thread: synthesize from Thread directory record, read-only cold checkpoint, and
        // HistoryReader only (never mutates current.json or activates execution).
        let mut meta = SessionMetaLayer::empty(&thread.id).snapshot();
        meta.status = thread.status;
        meta.title = Some(thread.title.clone());
        meta.parent_thread_id = thread.parent_thread_id.clone();
        meta.root_thread_id = thread.root_thread_id.clone();
        meta.mode = thread.mode.clone();
        meta.usage = UsageSummary::default();

        if let Some(current) = self.store.load_current_read_only(thread).await? {
            let paused = current.state.to_paused_snapshot();
            let runtime = crate::studio::thread_projection::project_runtime(
                &thread.id,
                &paused,
                thread.updated_at,
                &paused.usage_summary,
            )?;
            let mut model_route = crate::studio::model_route::projected(&paused)?;
            if let Ok((config, _)) = self.config_runtime.read_with_catalog() {
                let _ = crate::studio::model_route::annotate_availability(
                    model_route.as_mut(),
                    thread,
                    &config.config,
                );
            }
            let interactions =
                crate::studio::thread_projection::project_interactions(&thread.id, &paused)?;
            let pending_interaction_count = u32::try_from(interactions.len()).unwrap_or(u32::MAX);
            let plan = runtime.plan.clone();
            let context_metrics = Some(runtime.usage.clone());
            meta.owner_epoch = current.saved_runtime_epoch.to_string();
            meta.revision = paused.commit_sequence;
            meta.status = crate::studio::thread_projection::status(&paused);
            meta.mode = crate::studio::thread_projection::saved_mode(&paused)
                .ok()
                .flatten()
                .or_else(|| thread.mode.clone());
            meta.usage = paused.usage_summary.clone();
            meta.context_metrics = context_metrics;
            meta.model_route = model_route;
            meta.runtime = Some(runtime);
            meta.interactions = interactions;
            meta.pending_interaction_count = pending_interaction_count;
            meta.plan = plan;
            meta.active_turn = None;
            meta.activity = None;
            meta.storage_state = None;
            meta.execution_present = false;
        }

        if let Some(reader) = reader {
            let cut = reader.capture().await?;
            let turns_page = reader
                .turns_page(
                    Some(cut.clone()),
                    None,
                    HistoryDemand {
                        max_rows: 1,
                        max_bytes: 256 * 1024,
                    },
                )
                .await?;
            if let Some(entry) = turns_page.entries.first()
                && let HistoryBusinessRowHead::Turn(head) = &entry.head
                && head.detail_event_id.is_some()
                && let Ok(turn) = crate::studio::runtime::history_turn(reader, head.clone()).await
            {
                meta.last_turn = Some(turn);
            }
        }
        Ok(meta)
    }
}

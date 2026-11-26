//! Unified conversation feed & session metadata API for Native & cold threads.
//!
//! Live threads borrow the resident observation owner's prepared source. Cold threads read saved
//! pause information and history without preparing storage or activating execution.

use anyhow::Result;
use pl_core::thread::UsageSummary;

use crate::history::{HistoryBusinessRowHead, HistoryDemand, HistoryReader};
use crate::studio::StudioRuntime;
use crate::timeline::{ConversationFeed, SessionMetaLayer, SessionMetaSnapshot};

#[cfg(test)]
mod tests;

impl StudioRuntime {
    /// Opens a product conversation and first runs storage maintenance for saved history when
    /// needed. This can upgrade an existing database without starting Thread execution.
    pub async fn open_conversation_feed_with_maintenance(
        &self,
        thread_id: &str,
        initial_limit: u32,
    ) -> Result<ConversationFeed> {
        let thread = self.read_protocol_thread(thread_id).await?;
        self.check_thread_read_access(&thread)?;
        self.open_conversation_feed_for(&thread, initial_limit, true)
            .await
    }

    /// Opens a unified `ConversationFeed` for `thread_id` (live `MetaEventBus` if resident +
    /// bounded `HistoryReader` stitching `history.sqlite ∪ Pending` on cold open & paging).
    pub async fn open_conversation_feed(
        &self,
        thread_id: &str,
        initial_limit: u32,
    ) -> Result<ConversationFeed> {
        let thread = self.read_protocol_thread(thread_id).await?;
        self.check_thread_read_access(&thread)?;
        self.open_conversation_feed_for(&thread, initial_limit, false)
            .await
    }

    async fn open_conversation_feed_for(
        &self,
        thread: &crate::Thread,
        initial_limit: u32,
        prepare_saved_history: bool,
    ) -> Result<ConversationFeed> {
        let thread_id = thread.id.as_str();
        let slot = self.thread_observations.observation_slot(thread_id);
        let mut bus_rx = slot.subscribe_bus();
        let bus = self
            .thread_observations
            .ready_bus(thread_id, &mut bus_rx)
            .await?;
        let (reader, initial_meta) = if let Some(bus) = bus {
            (
                bus.history().reader(),
                (*bus.latest_meta().expect("published observation metadata")).clone(),
            )
        } else {
            if prepare_saved_history {
                self.store.prepare_conversation_history(thread_id).await?;
            }
            let reader = self.store.open_history_reader(thread_id).await?;
            match self.build_cold_session_meta(thread, Some(&reader)).await {
                Ok(meta) => (reader, meta),
                Err(error) => {
                    reader.close().await;
                    return Err(error);
                }
            }
        };
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

    /// Reads the prepared observation's metadata, or saved pause information when not running.
    pub async fn thread_session_meta(&self, thread_id: &str) -> Result<SessionMetaSnapshot> {
        let thread = self.read_protocol_thread(thread_id).await?;
        self.check_thread_read_access(&thread)?;
        let slot = self.thread_observations.observation_slot(thread_id);
        let mut bus_rx = slot.subscribe_bus();
        if let Some(bus) = self
            .thread_observations
            .ready_bus(thread_id, &mut bus_rx)
            .await?
        {
            return Ok((*bus.latest_meta().expect("published observation metadata")).clone());
        }
        let reader = match self.store.open_history_reader(thread_id).await {
            Ok(reader) => Some(reader),
            Err(error)
                if error
                    .downcast_ref::<crate::StudioError>()
                    .is_some_and(|error| error.code == crate::StudioErrorCode::NotFound) =>
            {
                None
            }
            Err(error) => return Err(error),
        };
        let snapshot = self.build_cold_session_meta(&thread, reader.as_ref()).await;
        if let Some(reader) = reader {
            reader.close().await;
        }
        if let Some(bus) = self
            .thread_observations
            .ready_bus(thread_id, &mut bus_rx)
            .await?
        {
            return Ok((*bus.latest_meta().expect("published observation metadata")).clone());
        }
        snapshot
    }

    async fn build_cold_session_meta(
        &self,
        thread: &crate::Thread,
        reader: Option<&HistoryReader>,
    ) -> Result<SessionMetaSnapshot> {
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

//! Point-in-time Thread snapshots and usage folds. Continuous State delivery lives in
//! `conversation_state_feed` and does not activate execution.
use super::StudioRuntime;
use anyhow::{Context, Result};
use pl_core::thread::{ThreadHandle, ThreadSnapshot};
use pl_protocol::ThreadBusinessRefs;
use std::num::NonZeroUsize;

impl StudioRuntime {
    /// Reads live or cold facts without executing a model, tool or recovery continuation.
    pub async fn thread_snapshot(&self, thread_id: &str) -> Result<pl_protocol::ThreadSnapshot> {
        let thread = self.read_protocol_thread(thread_id).await?;
        self.check_thread_read_access(&thread)?;
        let slot = self.thread_observations.observation_slot(thread_id);
        let (position, _) = slot.capture();
        // Choose the read source once. In particular, an execution owner installed during cold IO
        // must not supply usage for the independently captured durable State.
        let handle = self
            .session_of(thread_id)
            .and_then(|session| session.observed_thread(thread_id));
        let (state, business_refs) = match handle.as_ref() {
            Some(handle) => {
                let state = handle.snapshot();
                let references = self.thread_business_refs_at(thread_id, &state)?;
                (state, references)
            }
            None => self
                .store
                .history(thread_id)
                .await?
                .read_state_with_business_refs()
                .await?
                .context("Thread has no saved checkpoint")?,
        };
        self.store
            .thread_persistence()
            .seed_usage(thread_id, state.usage_summary.clone());
        let usage = match handle {
            Some(handle) => self.usage_through_owner(thread_id, &state, &handle).await?,
            None => self.usage_summary(thread_id, &state),
        };
        let persistence = self.thread_persistence_snapshot(thread_id);
        let mut snapshot = crate::studio::thread_projection::project_snapshot(
            thread,
            &state,
            &usage,
            persistence.as_ref(),
            business_refs,
        )?;
        if let Some(close) = self.store.agent_close(thread_id).await? {
            snapshot.thread.status = if close.execution_closed {
                pl_protocol::ThreadStatus::Closed
            } else {
                pl_protocol::ThreadStatus::Closing
            };
        }
        self.annotate_model_route(&mut snapshot)?;
        self.annotate_mode_availability(&mut snapshot);
        anyhow::ensure!(
            slot.is_current(position.epoch),
            pl_core::chat::ChatError::StaleContent
        );
        Ok(snapshot)
    }

    /// Qualify an existing hot resource owner against the captured Core business slice.
    /// Missing or replaced live resources are stale; cold State uses the storage transaction pair.
    fn thread_business_refs_at(
        &self,
        thread_id: &str,
        state: &ThreadSnapshot,
    ) -> Result<ThreadBusinessRefs> {
        let current = self
            .thread_observations
            .live_feed(thread_id)
            .and_then(|feed| feed.current_conversation())
            .map(|source| source.current.clone())
            .ok_or(pl_core::chat::ChatError::StaleContent)?;
        current.business_refs_at(thread_id, state)
    }

    fn annotate_mode_availability(&self, snapshot: &mut pl_protocol::ThreadSnapshot) {
        if let Some(runtime) = snapshot.runtime.as_mut() {
            self.annotate_runtime_mode_availability(runtime);
        }
    }

    fn annotate_runtime_mode_availability(&self, runtime: &mut pl_protocol::ThreadRuntimeSnapshot) {
        if let Some(run) = runtime
            .workflow
            .as_mut()
            .and_then(|workflow| workflow.current_run.as_mut())
        {
            run.mode_deleted = self.thread_modes.snapshot().mode(&run.mode_id).is_none();
        }
    }

    /// 该 Thread 的 typed 持久化快照；没有登记过持久化的 Thread 为 `None`（未知不等于健康）。
    ///
    /// 这是 [`pl_protocol::ThreadStorageState`] 的 typed 来源：故障类别、代数与水位都来自协调器
    /// 的类型化值，不是错误文本的解析结果。
    pub(in crate::studio) fn thread_persistence_snapshot(
        &self,
        thread_id: &str,
    ) -> Option<pl_protocol::ThreadPersistenceSnapshot> {
        self.store
            .thread_persistence()
            .queue_snapshot()
            .threads
            .into_iter()
            .find(|snapshot| snapshot.thread_id == thread_id)
    }

    /// Cumulative usage summary the projection must consume for one Thread.
    ///
    /// The writer is the single folder of committed effects, so its reported summary is the value a
    /// hot increment, a reconnect and a cold restore must agree on. A checkpoint that was loaded
    /// before the writer reported seeds the same value, never a re-aggregation of resident attempts.
    pub(in crate::studio) fn usage_summary(
        &self,
        thread_id: &str,
        state: &ThreadSnapshot,
    ) -> pl_core::thread::UsageSummary {
        let coordinator = self.store.thread_persistence();
        if let Some(summary) = coordinator.usage(thread_id) {
            return summary;
        }
        coordinator.seed_usage(thread_id, state.usage_summary.clone());
        state.usage_summary.clone()
    }

    /// Include committed owner facts that the asynchronous history writer has not folded yet.
    /// This is only a presentation snapshot; it never advances the writer's durable watermark.
    async fn usage_through_owner(
        &self,
        thread_id: &str,
        state: &ThreadSnapshot,
        handle: &ThreadHandle,
    ) -> Result<pl_core::thread::UsageSummary> {
        let mut summary = self.usage_summary(thread_id, state);
        while summary.applied_sequence < state.commit_sequence {
            let page = handle
                .effect_page(summary.applied_sequence, NonZeroUsize::new(128).unwrap())
                .await
                .context("committed usage effect is no longer available")?;
            let mut progressed = false;
            for effect in page {
                if effect.sequence > state.commit_sequence {
                    break;
                }
                anyhow::ensure!(
                    effect.sequence == summary.applied_sequence + 1,
                    "committed usage effect has a gap"
                );
                crate::studio::thread_projection::fold_effect_accounting(&mut summary, &effect)?;
                progressed = true;
            }
            anyhow::ensure!(progressed, "committed usage effect has no progress");
        }
        Ok(summary)
    }

    pub(in crate::studio) async fn read_thread_state(
        &self,
        thread_id: &str,
    ) -> Result<ThreadSnapshot> {
        if let Some((_, handle)) = self
            .sessions
            .observed_threads()
            .into_iter()
            .find(|(id, _)| id == thread_id)
        {
            let snapshot = handle.snapshot();
            self.store
                .thread_persistence()
                .seed_usage(thread_id, snapshot.usage_summary.clone());
            return Ok(snapshot);
        }
        let thread = self.read_protocol_thread(thread_id).await?;
        // A read-only projection never prepares storage: it reports only already-durable facts, so a
        // legacy checkpoint that still needs import stays invisible until an explicit activation
        // migrates it (design/17).
        let checkpoint = crate::studio::thread_factory::recovery::load_checkpoint_read_only(
            &self.store,
            &thread,
        )
        .await?
        .ok_or_else(|| anyhow::anyhow!("Thread has no saved checkpoint"))?;
        self.store
            .thread_persistence()
            .seed_usage(thread_id, checkpoint.state.usage_summary.clone());
        Ok(checkpoint.state)
    }

    fn annotate_model_route(&self, snapshot: &mut pl_protocol::ThreadSnapshot) -> Result<u64> {
        let (config, catalog) = self.config_runtime.read_with_catalog()?;
        crate::studio::model_route::annotate_availability(
            snapshot.model_route.as_mut(),
            &snapshot.thread,
            &config.config,
        )?;
        Ok(catalog.revision)
    }
}

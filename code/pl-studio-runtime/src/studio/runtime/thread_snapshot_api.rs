//! Point-in-time Thread snapshots and usage folds. Continuous State delivery lives in
//! `conversation_state_feed` and does not activate execution.
use super::StudioRuntime;
use anyhow::Result;
use pl_core::thread::ThreadSnapshot;

impl StudioRuntime {
    /// Reads a point-in-time `ThreadSnapshot` derived from live `MetaEventBus` / `ThreadHandle`
    /// state (pure RAM) or cold `Thread` directory + `HistoryReader` metadata.
    pub async fn thread_snapshot(&self, thread_id: &str) -> Result<crate::ThreadSnapshot> {
        let mut thread = self.read_protocol_thread(thread_id).await?;
        let meta = self.thread_session_meta(thread_id).await?;
        thread.status = meta.status;
        thread.title = meta.title.clone().unwrap_or_default();
        thread.mode = meta.mode;
        Ok(crate::ThreadSnapshot {
            schema_version: crate::THREAD_SCHEMA_VERSION,
            revision: meta.revision,
            thread,
            business_refs: crate::ThreadBusinessRefs::empty(),
            active_turn: meta.active_turn,
            interactions: meta.interactions,
            model_route: meta.model_route,
            runtime: meta.runtime,
            activity: meta.activity,
            storage: meta.storage_state,
        })
    }

    pub(in crate::studio) async fn read_thread_state(
        &self,
        thread_id: &str,
    ) -> Result<ThreadSnapshot> {
        if let Some(handle) = self
            .session_of(thread_id)
            .and_then(|session| session.observed_thread(thread_id))
        {
            let snapshot = handle.snapshot();
            self.store
                .thread_persistence()
                .seed_usage(thread_id, snapshot.usage_summary.clone());
            return Ok(snapshot);
        }
        let thread = self.read_protocol_thread(thread_id).await?;
        // A read-only projection never prepares storage: it reports only an already-complete
        // current document, so a legacy checkpoint stays invisible until explicit activation.
        let current = self
            .store
            .load_current_read_only(&thread)
            .await?
            .ok_or_else(|| anyhow::anyhow!("Thread has no saved current"))?;
        let state = current.state.to_paused_snapshot();
        self.store
            .thread_persistence()
            .seed_usage(thread_id, state.usage_summary.clone());
        Ok(state)
    }

    /// Reads the thread's frozen workflow graph on demand (live, saved cold `current.json`, or
    /// catalog fallback) without bloating high-frequency `ThreadRuntimeSnapshot` frames.
    pub async fn thread_workflow_graph(
        &self,
        thread_id: &str,
    ) -> Result<Option<crate::workflow_tool::WorkflowRuntimeGraphSnapshot>> {
        if let Some((session, agent)) = self
            .agent_facility
            .product_events
            .directory_facts(thread_id)
            && matches!(agent.backend, crate::AgentBackend::Acp { .. })
        {
            if let Ok(session_id) = crate::SessionId::new(session.session_id.clone())
                && let Some(owner) = self.sessions.get(&session_id)
                && let Some(acp) = owner.resident_acp(thread_id)?
            {
                return Ok(acp.workflow_snapshot().and_then(|s| s.graph));
            }
            if !agent.is_root_agent() {
                return Ok(None);
            }
            let resources_dir = self
                .store
                .session_resources_dir_for(&session.workspace_id, thread_id)?;
            return super::acp_business::AcpWorkflowPlanOwner::read_cold_graph(
                &resources_dir,
                &self.thread_modes,
            )
            .await;
        }
        let live_mode = self
            .session_of(thread_id)
            .and_then(|session| session.observed_thread(thread_id))
            .and_then(|handle| {
                handle
                    .snapshot()
                    .extensions
                    .get("studio.mode")
                    .and_then(|record| {
                        crate::mode::presentation_mode(&record.payload)
                            .ok()
                            .flatten()
                    })
            });
        let modes = self.thread_modes.snapshot();
        if let Some(saved) = live_mode {
            let deleted = modes.mode(&saved.definition.id).is_none();
            return Ok(
                crate::studio::thread_projection::workflow_graph_from_saved_mode(&saved, deleted),
            );
        }
        let thread = self.read_protocol_thread(thread_id).await?;
        if let Some(current) = self.store.load_current_read_only(&thread).await?
            && let Some(record) = current.state.extensions.get("studio.mode")
            && let Some(saved) = crate::mode::presentation_mode(&record.payload)?
        {
            let deleted = modes.mode(&saved.definition.id).is_none();
            return Ok(
                crate::studio::thread_projection::workflow_graph_from_saved_mode(&saved, deleted),
            );
        }
        if let Some(mode_id) = thread.mode
            && let Some(registered) = modes.mode(&mode_id)
        {
            return Ok(
                crate::studio::thread_projection::workflow_graph_from_definition(
                    &registered.definition(),
                    false,
                ),
            );
        }
        Ok(None)
    }
}

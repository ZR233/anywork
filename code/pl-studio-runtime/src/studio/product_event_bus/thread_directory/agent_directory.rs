//! 成员投影差异与 Native observation 的身份／修订裁决。

use super::*;

pub(super) fn cold_native_activity(agent: &AgentDirectoryRecord) -> StudioAgentActivity {
    let state = match agent.projected_backend().native_status() {
        Some(ThreadStatus::Closed) => crate::AgentState::Closed(crate::ClosedAgentState::new()),
        Some(ThreadStatus::Closing) => crate::AgentState::Closing(crate::ClosingAgentState::new()),
        _ => crate::AgentState::idle(),
    };
    StudioAgentActivity::Native {
        state,
        execution: None,
        can_stop: false,
        awaiting_scheduling: false,
    }
}

impl ProductEventBus {
    /// Membership, runtime projection and revision belong to this same published RAM slice.
    pub async fn read_agent_directory(&self) -> StudioAgentDirectoryState {
        let index = self
            .thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.agent_directory_state_locked(index.agent_directory_entries())
    }

    pub(super) fn agent_directory_state_locked(
        &self,
        agents: Vec<StudioAgentDirectoryEntry>,
    ) -> StudioAgentDirectoryState {
        StudioAgentDirectoryState {
            state: self.resource(&self.revisions.agent, StudioAgentDirectoryData { agents }),
        }
    }

    pub(super) fn publish_agent_directory_locked(
        &self,
        index: &ThreadDirectoryIndex,
        before: BTreeMap<String, Option<StudioAgentDirectoryEntry>>,
    ) {
        let changes = index.agent_directory_changes(before);
        tracing::trace!(
            compared = changes.compared,
            upserted = changes.upserted.len(),
            removed = changes.removed.len(),
            "compare agent directory members"
        );
        if !changes.upserted.is_empty() || !changes.removed.is_empty() {
            let emit_value = || {
                let agents = index.agent_directory_entries();
                self.emit(StudioProductEventKind::AgentDirectoryChanged(
                    self.agent_directory_state_locked(agents),
                ));
            };
            // Existing full internal observers receive their exact envelope before typed
            // dispatch. Keep that ordering even while another thread holds the topic registry.
            if self.internal.receiver_count() > 0 {
                self.bump(&self.revisions.agent);
                emit_value();
                return;
            }
            let topic = crate::StudioProductTopic::AgentDirectory;
            let mut topics = self
                .topics
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            self.bump(&self.revisions.agent);
            if topics.has_value_receivers(&topic) || self.internal.receiver_count() > 0 {
                // Exact value consumers retain the frozen collection, revision and dispatch
                // order. Release the registry before emit; the index still freezes this cut.
                drop(topics);
                emit_value();
            } else {
                // Registration, revision and wake commit together. No receiver can register in
                // the gap and miss both a value and its baseline. No full collection is built.
                self.sequence
                    .fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                topics.notify(&topic);
            }
        }
    }

    pub(in crate::studio) fn begin_native_observation(
        &self,
        thread_id: &str,
    ) -> Option<NativeAgentObservation> {
        let mut index = self
            .thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let (session, agent) = index.directory_facts(thread_id)?;
        if session.archived || !matches!(agent.backend, crate::AgentBackend::Native { .. }) {
            return None;
        }
        let before = index.agent_directory_members([agent.agent_id.clone()]);
        let mut observation = NativeAgentObservation {
            session_id: agent.session_id.clone(),
            agent_id: agent.agent_id.clone(),
            thread_id: agent.thread_id.clone(),
            generation: 0,
        };
        // Replacing an execution observer revokes runtime facts, not the same member's
        // confirmed summary. Backend changes and removals invalidate this Native projection.
        let summary = index
            .native_activity
            .get(&observation.agent_id)
            .filter(|projection| {
                projection.observation.session_id == observation.session_id
                    && projection.observation.agent_id == observation.agent_id
                    && projection.observation.thread_id == observation.thread_id
            })
            .and_then(|projection| projection.summary.clone());
        index.observation_generation = index
            .observation_generation
            .checked_add(1)
            .expect("Native observation generation exhausted");
        observation.generation = index.observation_generation;
        index.native_activity.insert(
            observation.agent_id.clone(),
            NativeAgentProjection {
                observation: observation.clone(),
                revision: None,
                activity: None,
                summary,
            },
        );
        self.publish_agent_directory_locked(&index, before);
        Some(observation)
    }

    /// Cold continuation reconciliation cannot take over a live observation incarnation.
    pub(in crate::studio) fn publish_cold_agent_scheduling(
        &self,
        session_id: &str,
        agent_id: &str,
        thread_id: &str,
        snapshot: &pl_core::thread::ThreadSnapshot,
    ) -> Result<()> {
        let scheduling = crate::studio::thread_projection::awaiting_scheduling(snapshot)?;
        let mut index = self
            .thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let Some((session, agent)) = index.directory_facts(thread_id) else {
            return Ok(());
        };
        if session.session_id != session_id
            || agent.agent_id != agent_id
            || session.archived
            || !matches!(agent.backend, crate::AgentBackend::Native { .. })
            || index
                .native_activity
                .get(&agent.agent_id)
                .is_some_and(|projection| projection.observation.generation != 0)
        {
            return Ok(());
        }
        let before = index.agent_directory_members([agent.agent_id.clone()]);
        let observation = NativeAgentObservation {
            session_id: agent.session_id.clone(),
            agent_id: agent.agent_id.clone(),
            thread_id: agent.thread_id.clone(),
            generation: 0,
        };
        let mut activity = cold_native_activity(agent);
        if let StudioAgentActivity::Native {
            awaiting_scheduling,
            ..
        } = &mut activity
        {
            *awaiting_scheduling = scheduling;
        }
        index.native_activity.insert(
            observation.agent_id.clone(),
            NativeAgentProjection {
                observation,
                revision: None,
                activity: Some(activity),
                summary: None,
            },
        );
        self.publish_agent_directory_locked(&index, before);
        Ok(())
    }

    /// Distinguishes an older cut already covered by this same valid observation from revocation.
    /// The membership/identity check is shared with the patch; revisions from other generations,
    /// removed or archived resources and non-Native backends never establish terminal coverage.
    pub(in crate::studio) fn native_observation_covers(
        &self,
        observation: Option<&NativeAgentObservation>,
        snapshot: &pl_core::thread::ThreadSnapshot,
    ) -> bool {
        let Some(observation) = observation else {
            return false;
        };
        let index = self
            .thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        index
            .native_observation_facts(observation)
            .is_some_and(|(_, _, projection)| {
                projection
                    .revision
                    .is_some_and(|revision| revision >= snapshot.observation_revision)
            })
    }

    /// Applies only runtime-owned fields to the current directory summary.
    /// Missing or archived entries are never reinserted by a delayed observation.
    pub(in crate::studio) fn patch_thread_runtime(
        &self,
        observation: Option<&NativeAgentObservation>,
        status: crate::ThreadStatus,
        committed_at: i64,
        snapshot: &pl_core::thread::ThreadSnapshot,
        summary: Option<Option<String>>,
    ) -> Result<Option<SessionDirectoryRow>> {
        let Some(observation) = observation else {
            return Ok(None);
        };
        let activity = crate::studio::thread_projection::native_activity(snapshot)?;
        let mut index = self
            .thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let Some((session_record, agent, projection)) = index.native_observation_facts(observation)
        else {
            return Ok(None);
        };
        if projection
            .revision
            .is_some_and(|revision| snapshot.observation_revision < revision)
        {
            return Ok(None);
        }
        let (session_record, mut agent) = (session_record.clone(), agent.clone());
        let before_agents = index.agent_directory_members([agent.agent_id.clone()]);
        let previous_row = row_projection(&session_record, &agent);
        let mut session_next = session_record.clone();
        // Runtime observations own no title, ancestry, delegation or frozen model metadata.
        agent.set_native_status(status);
        Self::apply_explicit_close_agent(&index, &mut agent);
        agent.updated_at = agent.updated_at.max(committed_at);
        session_next.updated_at = session_next.updated_at.max(committed_at);
        index.insert_agent(agent.clone());
        index.insert_session(session_next.clone());
        // Early runtime publication has no new summary. Only the complete product projection
        // explicitly replaces or clears it; repeated terminal handoffs must not erase it briefly.
        let summary = summary.unwrap_or_else(|| {
            index
                .native_activity
                .get(&agent.agent_id)
                .and_then(|projection| projection.summary.clone())
        });
        index.native_activity.insert(
            agent.agent_id.clone(),
            NativeAgentProjection {
                observation: observation.clone(),
                revision: Some(snapshot.observation_revision),
                activity: Some(activity),
                summary,
            },
        );
        // 状态观察是目录事实：只把有界摘要并入 write-behind 目录队列，不在观察热路径做文件 I/O。
        // 同一成员的连续 delta 由队列合并；write-behind 批次经 `apply_directory_delta` 把摘要
        // 幂等写入 catalog/workspaces TOML。调用方在发布后用固定目标 ticket（`flush_through`）
        // 建立保存屏障；状态错误不回滚已提交的内存目录事实。
        let row = row_projection(&session_next, &agent);
        if row != previous_row {
            self.writer.record_directory(DirectoryDelta {
                session_upserts: vec![session_next],
                agent_upserts: vec![agent],
                ..Default::default()
            });
            self.emit_thread_delta_locked(&index, vec![row.clone()], Vec::new());
        }
        self.publish_agent_directory_locked(&index, before_agents);
        Ok(Some(row))
    }
}

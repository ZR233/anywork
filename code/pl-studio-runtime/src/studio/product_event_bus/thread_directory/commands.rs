//! 耐久目录命令：保存成功后提交 RAM 切面及发布。

use super::*;

fn rebase_command_session(
    mut current: SessionDirectoryRecord,
    requested: &SessionDirectoryRecord,
    baseline: &SessionDirectoryRecord,
) -> SessionDirectoryRecord {
    debug_assert_eq!(current.session_id, requested.session_id);
    macro_rules! command_field {
        ($field:ident) => {
            if requested.$field != baseline.$field {
                current.$field = requested.$field.clone();
            }
        };
    }
    command_field!(root_agent_id);
    command_field!(workspace_id);
    command_field!(title);
    command_field!(acp_title);
    command_field!(native_mode);
    command_field!(workspace_mode);
    command_field!(delegation_mode);
    command_field!(delegation_preference);
    command_field!(workspace_path);
    command_field!(created_at);
    command_field!(archived);
    current.updated_at = current.updated_at.max(requested.updated_at);
    current.last_user_message_at = current
        .last_user_message_at
        .max(requested.last_user_message_at);
    current
}

fn rebase_command_agent(
    mut current: AgentDirectoryRecord,
    requested: &AgentDirectoryRecord,
    baseline: &AgentDirectoryRecord,
) -> AgentDirectoryRecord {
    debug_assert_eq!(current.agent_id, requested.agent_id);
    macro_rules! command_field {
        ($field:ident) => {
            if requested.$field != baseline.$field {
                current.$field = requested.$field.clone();
            }
        };
    }
    command_field!(session_id);
    command_field!(parent_agent_id);
    command_field!(thread_id);
    command_field!(role);
    command_field!(title);
    command_field!(backend);
    command_field!(created_at);
    current.explicitly_closed |= requested.explicitly_closed;
    current.updated_at = current.updated_at.max(requested.updated_at);
    current
}

impl ProductEventBus {
    pub(super) fn apply_explicit_close_agent(
        index: &ThreadDirectoryIndex,
        agent: &mut AgentDirectoryRecord,
    ) {
        if index.explicitly_closed.contains(&agent.agent_id) {
            // 把关闭意图写回成员事实：`projected_status` 以该标志区分 Closed 与 Idle，
            // 缺失时已确认关闭的成员会被目录投影降级回 Idle。
            agent.explicitly_closed = true;
            let existing = index
                .get_agent(&agent.agent_id)
                .expect("explicit close retains its directory agent");
            if let Some(status) = existing.native_status() {
                agent.set_native_status(crate::studio::agent_close::directory_status(status, true));
            }
        }
    }

    /// Publish progress already saved by the close owner into the original metadata boundary.
    /// Ordinary Core observations cannot advance this progress.
    pub(in crate::studio) async fn commit_explicit_close(&self, thread_id: &str) -> Result<()> {
        let _command = self.directory_commands.lock().await;
        // Read inside the publication boundary: a restore waiting on this lock
        // cannot carry an old false past a newer execution-close ACK.
        let execution_closed = self
            .store
            .agent_close(thread_id)
            .await?
            .context("close progress requires its durable intent")?
            .execution_closed;
        let catalog = self.store.catalog();
        let agent = catalog
            .agent_by_thread(thread_id)
            .ok_or_else(|| StudioError::not_found("session"))?;
        catalog
            .project_explicit_close(&agent.agent_id, execution_closed)
            .await?;
        let recovered_session = catalog.get_session(&agent.session_id);
        let recovered_agent = catalog.agent_by_thread(thread_id);
        let mut index = self
            .thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let before_agents = index.agent_directory_members([agent.agent_id.clone()]);
        let recovered_member = index.agent_by_thread(thread_id).is_none();
        if recovered_member {
            if index.deleted.contains(thread_id)
                || index.deleted_sessions.contains(&agent.session_id)
            {
                return Err(StudioError::not_found("session").into());
            }
            let session = recovered_session.ok_or_else(|| StudioError::not_found("session"))?;
            let current = recovered_agent.ok_or_else(|| StudioError::not_found("session"))?;
            // Recovery supplies missing membership, not a replacement for already-published
            // common metadata. Catalog persistence may lag the current RAM title/delegation.
            if index.get_session(&session.session_id).is_none() {
                index.insert_session(session);
            }
            index.insert_agent(current);
        }
        let Some((session_record, mut agent)) = index
            .directory_facts(thread_id)
            .map(|(session, agent)| (session.clone(), agent.clone()))
        else {
            return Err(StudioError::not_found("session").into());
        };
        let newly_closed = index.explicitly_closed.insert(agent.agent_id.clone());
        let previous_status = agent.native_status();
        agent.explicitly_closed = true;
        agent.set_native_status(if execution_closed {
            ThreadStatus::Closed
        } else {
            ThreadStatus::Closing
        });
        if !recovered_member && !newly_closed && previous_status == agent.native_status() {
            return Ok(());
        }
        index.insert_agent(agent.clone());
        let row = row_projection(&session_record, &agent);
        self.writer.record_directory(DirectoryDelta {
            agent_upserts: vec![agent],
            ..Default::default()
        });
        self.publish_agent_directory_locked(&index, before_agents);
        self.emit_thread_delta_locked(&index, vec![row], vec![]);
        Ok(())
    }

    /// Records only the Mode fact already committed by core, not an earlier whole-row copy.
    /// A failed/cancelled wait cannot reject that fact: write-behind retains the exact delta and
    /// exposes its normal PersistenceState/retry path. No core operation is replayed on retry.
    pub(in crate::studio) async fn commit_observed_thread_mode(
        &self,
        thread_id: &str,
        mode: crate::mode::ThreadModeId,
        committed_at: i64,
    ) -> Result<StudioProductEventEnvelope> {
        let (ticket, event) = {
            let mut index = self
                .thread_index
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let (mut session, mut agent) = index
                .directory_facts(thread_id)
                .map(|(session, agent)| (session.clone(), agent.clone()))
                .ok_or_else(|| StudioError::not_found("session"))?;
            anyhow::ensure!(
                agent.is_root_agent()
                    && matches!(agent.backend, crate::AgentBackend::Native { .. }),
                "only a Native root owns workflow mode"
            );
            session.native_mode = Some(mode);
            session.updated_at = session.updated_at.max(committed_at);
            agent.updated_at = agent.updated_at.max(committed_at);
            self.writer.record_directory(DirectoryDelta {
                session_upserts: vec![session.clone()],
                agent_upserts: vec![agent.clone()],
                ..Default::default()
            });
            let ticket = self.writer.admitted_ticket();
            let before_agents = index.agent_directory_members([agent.agent_id.clone()]);
            Self::apply_explicit_close_agent(&index, &mut agent);
            let row = row_projection(&session, &agent);
            index.insert_session(session);
            index.insert_agent(agent);
            self.publish_agent_directory_locked(&index, before_agents);
            let event = self.emit_thread_delta_locked(&index, vec![row], Vec::new());
            (ticket, event)
        };
        self.writer.flush_through(ticket).await?;
        Ok(event)
    }

    /// 提交一次目录事实：持久化成功后更新唯一内存摘要并广播。
    ///
    /// 这是会话/成员/Project 目录 mutation 的唯一命令通道；后台保存不能拒绝目录事实。
    pub(in crate::studio) async fn commit_directory(
        &self,
        delta: DirectoryDelta,
    ) -> Result<StudioProductEventEnvelope> {
        self.commit_directory_with_bases(delta, DirectoryBaselines::default())
            .await
    }

    /// The caller freezes this baseline when deriving its update, before any await.
    pub(in crate::studio) async fn commit_session_update(
        &self,
        baseline: SessionDirectoryRecord,
        updated: SessionDirectoryRecord,
    ) -> Result<StudioProductEventEnvelope> {
        anyhow::ensure!(
            baseline.session_id == updated.session_id,
            "session update identity mismatch"
        );
        let mut bases = DirectoryBaselines::default();
        bases.sessions.insert(baseline.session_id.clone(), baseline);
        self.commit_directory_with_bases(
            DirectoryDelta {
                session_upserts: vec![updated],
                ..Default::default()
            },
            bases,
        )
        .await
    }

    /// The caller freezes the member baseline before deriving an ACP association update.
    pub(in crate::studio) async fn commit_agent_update(
        &self,
        baseline: AgentDirectoryRecord,
        updated: AgentDirectoryRecord,
    ) -> Result<StudioProductEventEnvelope> {
        anyhow::ensure!(
            baseline.agent_id == updated.agent_id,
            "agent update identity mismatch"
        );
        let mut bases = DirectoryBaselines::default();
        bases.agents.insert(baseline.agent_id.clone(), baseline);
        self.commit_directory_with_bases(
            DirectoryDelta {
                agent_upserts: vec![updated],
                ..Default::default()
            },
            bases,
        )
        .await
    }

    pub(super) async fn commit_directory_with_bases(
        &self,
        delta: DirectoryDelta,
        bases: DirectoryBaselines,
    ) -> Result<StudioProductEventEnvelope> {
        let _command = self.directory_commands.lock().await;
        self.commit_directory_locked(delta, bases).await
    }

    pub(super) async fn commit_directory_locked(
        &self,
        delta: DirectoryDelta,
        bases: DirectoryBaselines,
    ) -> Result<StudioProductEventEnvelope> {
        let saved = self.persist_directory_commit(delta, bases).await?;
        self.publish_directory_commit(saved)
    }

    /// Capture the saved command without holding the RAM publication lock.
    /// The caller keeps directory_commands until publication completes.
    pub(super) async fn persist_directory_commit(
        &self,
        delta: DirectoryDelta,
        bases: DirectoryBaselines,
    ) -> Result<DurableDirectoryCommit> {
        if delta.is_empty() {
            return Err(anyhow::anyhow!("directory delta is empty"));
        }
        // Persist without holding the metadata lock. Readers continue to see the previous
        // committed RAM slice until this durable operation succeeds.
        self.store.persist_directory_summaries(&delta).await?;
        Ok(DurableDirectoryCommit { delta, bases })
    }

    pub(super) fn publish_directory_commit(
        &self,
        saved: DurableDirectoryCommit,
    ) -> Result<StudioProductEventEnvelope> {
        let DurableDirectoryCommit { delta, bases } = saved;
        let archived_sessions = delta
            .session_removals
            .iter()
            .flat_map(|removal| removal.session_ids.iter())
            .chain(
                delta
                    .project_removals
                    .iter()
                    .flat_map(|removal| removal.session_ids.iter()),
            )
            .collect::<HashSet<_>>();
        let project_upserts = delta
            .project_upserts
            .iter()
            .map(crate::WorkspaceRecord::from)
            .collect::<Vec<_>>();
        let project_changed = !project_upserts.is_empty() || !delta.project_removals.is_empty();
        let mut envelope = {
            let mut index = self
                .thread_index
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let before_agents = index.agent_directory_members(index.delta_agent_ids(&delta));
            let removed_agent_ids = archived_sessions
                .iter()
                .filter_map(|id| index.sessions.get(*id))
                .flat_map(|entry| entry.agents.values().map(|agent| agent.thread_id.clone()))
                .chain(delta.thread_deletions.iter().cloned())
                .collect::<BTreeSet<_>>()
                .into_iter()
                .collect::<Vec<_>>();
            let mut published_rows = Vec::new();
            let mut frozen_sessions = BTreeMap::new();
            for requested in &delta.session_upserts {
                if index.deleted_sessions.contains(&requested.session_id) {
                    continue;
                }
                let mut merged = match bases.sessions.get(&requested.session_id) {
                    None => requested.clone(),
                    Some(baseline) => {
                        let Some(current) = index.get_session(&requested.session_id).cloned()
                        else {
                            // A later removal remains authoritative; this older command cannot
                            // resurrect the identity.
                            continue;
                        };
                        rebase_command_session(current, requested, baseline)
                    }
                };
                // Preserve the monotonic user-message watermark over the command copy.
                if let Some(existing) = index.get_session(&merged.session_id) {
                    merged.last_user_message_at = existing
                        .last_user_message_at
                        .max(merged.last_user_message_at);
                }
                index.insert_session(merged.clone());
                frozen_sessions.insert(merged.session_id.clone(), merged);
            }
            let mut frozen_agents = BTreeMap::new();
            for requested in &delta.agent_upserts {
                if index.deleted.contains(&requested.thread_id)
                    || index.deleted_sessions.contains(&requested.session_id)
                {
                    continue;
                }
                let mut merged = match bases.agents.get(&requested.agent_id) {
                    None => requested.clone(),
                    Some(baseline) => {
                        let Some(current) = index.get_agent(&requested.agent_id).cloned() else {
                            continue;
                        };
                        rebase_command_agent(current, requested, baseline)
                    }
                };
                Self::apply_explicit_close_agent(&index, &mut merged);
                index.insert_agent(merged.clone());
                frozen_agents.insert(merged.agent_id.clone(), merged);
            }

            let removals = delta
                .session_removals
                .iter()
                .flat_map(|removal| {
                    removal
                        .session_ids
                        .iter()
                        .map(move |id| (id.clone(), removal.archived_at))
                })
                .chain(delta.project_removals.iter().flat_map(|removal| {
                    removal
                        .session_ids
                        .iter()
                        .map(move |id| (id.clone(), removal.closed_at))
                }));
            for (session_id, archived_at) in removals {
                if let Some(mut current) = index.get_session(&session_id).cloned() {
                    current.archived = true;
                    current.updated_at = current.updated_at.max(archived_at);
                    index.insert_session(current.clone());
                    frozen_sessions.insert(current.session_id.clone(), current);
                }
            }
            for id in &delta.thread_deletions {
                index.delete_thread(id);
            }
            let project_search_changed =
                project_changed && index.update_projects(&project_upserts, &delta.project_removals);
            let mut writer_delta = delta.clone();
            writer_delta.session_upserts = frozen_sessions.into_values().collect();
            writer_delta.agent_upserts = frozen_agents.values().cloned().collect();
            let mut published_sessions = writer_delta.session_upserts.clone();
            self.writer.record_directory(writer_delta);
            // 本提交直接冻结的成员行先入发布切面：没有它，register_session、
            // register_child_agent 这类携带成员事实的提交
            // 不会产生任何可观察行，命令通道会误报 "no observable changes"。
            for agent in frozen_agents.values() {
                if let Some(session) = index.get_session(&agent.session_id) {
                    published_rows.push(row_projection(session, agent));
                }
            }
            // 会话事实变化连带改变同会话其余成员行（行携带会话级事实）。
            published_sessions.sort_by(|left, right| left.session_id.cmp(&right.session_id));
            for session in &published_sessions {
                for agent in index.agents_of(&session.session_id) {
                    if frozen_agents.contains_key(&agent.agent_id) {
                        continue;
                    }
                    published_rows.push(row_projection(session, &agent));
                }
            }

            self.prepare_child_interaction_directory(&published_rows);
            self.remove_child_interaction_directory(&removed_agent_ids);
            self.publish_agent_directory_locked(&index, before_agents);
            let thread_changed = !published_rows.is_empty() || !removed_agent_ids.is_empty();
            if thread_changed {
                Some(self.emit_thread_delta_locked(&index, published_rows, removed_agent_ids))
            } else if project_search_changed {
                self.bump(&self.revisions.thread);
                self.topics
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .notify(&crate::StudioProductTopic::ThreadDirectory);
                None
            } else {
                None
            }
        };
        if let Some(project_event) =
            self.apply_project_snapshot_delta(&project_upserts, &delta.project_removals)?
        {
            envelope = Some(project_event);
        }
        envelope.ok_or_else(|| anyhow::anyhow!("directory delta has no observable changes"))
    }

    /// 注册一个 child 成员：typed delta 与摘要集合共同形成内存提交。
    pub(in crate::studio) async fn register_child_agent(
        &self,
        spec: crate::studio::store::directory::RegisteredChildAgent,
    ) -> Result<()> {
        let delta = DirectoryDelta::register_child_agent(spec);
        self.commit_directory(delta).await?;
        Ok(())
    }

    pub(in crate::studio) async fn fault_unregistered_child(
        &self,
        id: &str,
        message: &str,
    ) -> Result<()> {
        let mut agent = self
            .store
            .catalog()
            .get_agent(id)
            .ok_or_else(|| anyhow::anyhow!("unregistered child is not resident: {id}"))?;
        let baseline = agent.clone();
        let state = crate::studio::records::DirectoryState {
            kind: crate::ThreadStatus::Faulted,
            error: Some(message.into()),
        };
        agent.set_native_status(crate::ThreadStatus::Faulted);
        agent.updated_at = crate::studio::unix_seconds();
        let delta = DirectoryDelta {
            unregistered_faults: vec![crate::studio::store::directory::UnregisteredChildFault {
                agent_id: id.into(),
                state,
            }],
            agent_upserts: vec![agent],
            ..Default::default()
        };
        let mut bases = DirectoryBaselines::default();
        bases.agents.insert(id.to_owned(), baseline);
        self.commit_directory_with_bases(delta, bases).await?;
        Ok(())
    }
}

/// 命令通道提交时携带的冻结基线：调用方在任意 await 之前读取。
#[derive(Default)]
pub(in crate::studio) struct DirectoryBaselines {
    pub(super) sessions: HashMap<String, SessionDirectoryRecord>,
    pub(super) agents: HashMap<String, AgentDirectoryRecord>,
}

/// Only successful persistence creates a command eligible for RAM publication.
pub(super) struct DurableDirectoryCommit {
    delta: DirectoryDelta,
    bases: DirectoryBaselines,
}

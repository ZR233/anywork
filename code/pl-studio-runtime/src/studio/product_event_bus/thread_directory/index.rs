//! 会话与成员的唯一目录切面、反向索引及有界查询。

use super::*;

/// 一个会话在内存目录中的完整事实：会话记录 + 其全部成员。
pub(super) struct SessionDirectoryEntry {
    pub(super) session: SessionDirectoryRecord,
    pub(super) agents: BTreeMap<String, AgentDirectoryRecord>,
    /// 成员默认 Thread → 成员 ID；首版一一同字节映射。
    pub(super) agents_by_thread: HashMap<String, String>,
}

impl SessionDirectoryEntry {
    pub(super) fn new(session: SessionDirectoryRecord) -> Self {
        Self {
            session,
            agents: BTreeMap::new(),
            agents_by_thread: HashMap::new(),
        }
    }

    pub(super) fn insert_agent(&mut self, agent: AgentDirectoryRecord) {
        if let Some(previous) = self.agents.get(&agent.agent_id) {
            self.agents_by_thread.remove(&previous.thread_id);
        }
        self.agents_by_thread
            .insert(agent.thread_id.clone(), agent.agent_id.clone());
        self.agents.insert(agent.agent_id.clone(), agent);
    }

    pub(super) fn root_agent(&self) -> Option<&AgentDirectoryRecord> {
        self.agents.get(&self.session.root_agent_id)
    }

    pub(super) fn agent_by_thread(&self, thread_id: &str) -> Option<&AgentDirectoryRecord> {
        let agent_id = self.agents_by_thread.get(thread_id)?;
        self.agents.get(agent_id)
    }

    /// 主成员行投影；会话没有已注册主成员时返回 `None`。
    pub(super) fn root_row(&self) -> Option<SessionDirectoryRow> {
        self.root_agent()
            .map(|agent| row_projection(&self.session, agent))
    }
}

pub(in crate::studio::product_event_bus) struct ThreadDirectoryIndex {
    pub(super) sessions: HashMap<String, SessionDirectoryEntry>,
    pub(super) order: BTreeSet<(i64, String)>,
    pub(super) thread_to_session: HashMap<String, String>,
    pub(super) agent_to_session: HashMap<String, String>,
    agent_order: BTreeSet<String>,
    pub(super) projects: HashMap<String, String>,
    pub(super) explicitly_closed: HashSet<String>,
    pub(super) deleted: HashSet<String>,
    pub(super) deleted_sessions: HashSet<String>,
    pub(super) metadata_signals: TopicMap<watch::Sender<()>, String>,
    /// Only Native runtime facts. Membership and common metadata remain in `sessions`.
    pub(super) native_activity: HashMap<String, NativeAgentProjection>,
    pub(super) observation_generation: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(in crate::studio) struct NativeAgentObservation {
    pub(super) session_id: String,
    pub(super) agent_id: String,
    pub(super) thread_id: String,
    pub(super) generation: u64,
}

pub(super) struct NativeAgentProjection {
    pub(super) observation: NativeAgentObservation,
    pub(super) revision: Option<u64>,
    pub(super) activity: Option<StudioAgentActivity>,
    pub(super) summary: Option<String>,
}

/// A local comparison result. The public event still carries the existing complete baseline.
pub(super) struct AgentDirectoryChanges {
    pub(super) upserted: Vec<StudioAgentDirectoryEntry>,
    pub(super) removed: Vec<String>,
    pub(super) compared: usize,
}

impl ThreadDirectoryIndex {
    pub(in crate::studio::product_event_bus) fn new(
        sessions: Vec<SessionDirectoryRecord>,
        agents: Vec<AgentDirectoryRecord>,
        projects: &[crate::WorkspaceRecord],
    ) -> ThreadDirectoryIndex {
        let mut index = Self {
            sessions: HashMap::new(),
            order: BTreeSet::new(),
            thread_to_session: HashMap::new(),
            agent_to_session: HashMap::new(),
            agent_order: BTreeSet::new(),
            projects: HashMap::new(),
            explicitly_closed: HashSet::new(),
            deleted: HashSet::new(),
            deleted_sessions: HashSet::new(),
            metadata_signals: TopicMap::default(),
            native_activity: HashMap::new(),
            observation_generation: 0,
        };
        for session in sessions {
            index.insert_session(session);
        }
        for agent in agents {
            index.insert_agent(agent);
        }
        index.update_projects(projects, &[]);
        index
    }

    pub(super) fn insert_session(&mut self, session: SessionDirectoryRecord) {
        if self.deleted_sessions.contains(&session.session_id) {
            return;
        }
        if session.archived
            && let Some(entry) = self.sessions.get(&session.session_id)
        {
            for id in entry.agents.keys() {
                self.native_activity.remove(id);
            }
        }
        let key = (session.directory_sort_time(), session.session_id.clone());
        let mut changed_members = Vec::new();
        if let Some(previous) = self.sessions.get_mut(&session.session_id) {
            // Session updated_at is a persistence fact, not row metadata. The root row
            // includes every common visible field; unchanged root metadata cannot affect
            // a child's row. Avoid visiting all siblings on a runtime-only timestamp patch.
            let metadata_changed = previous.root_agent().is_none_or(|root| {
                row_projection(&previous.session, root) != row_projection(&session, root)
            });
            if metadata_changed {
                for agent in previous.agents.values() {
                    if self.metadata_signals.contains(&agent.thread_id)
                        && row_projection(&previous.session, agent)
                            != row_projection(&session, agent)
                    {
                        changed_members.push(agent.thread_id.clone());
                    }
                }
            }
            self.order.remove(&(
                previous.session.directory_sort_time(),
                session.session_id.clone(),
            ));
            previous.session = session;
        } else {
            self.sessions.insert(
                session.session_id.clone(),
                SessionDirectoryEntry::new(session),
            );
        }
        self.order.insert(key);
        for id in changed_members {
            self.metadata_signals.wake(&id);
        }
    }

    pub(super) fn insert_agent(&mut self, agent: AgentDirectoryRecord) -> Option<()> {
        // Validate before touching either the canonical membership or its reverse indexes.
        if self.deleted.contains(&agent.thread_id)
            || self.deleted_sessions.contains(&agent.session_id)
            || !self.sessions.contains_key(&agent.session_id)
        {
            return None;
        }
        let previous = self.get_agent(&agent.agent_id).cloned();
        let changed = self
            .directory_facts(&agent.thread_id)
            .map(|(session, member)| row_projection(session, member))
            != self
                .sessions
                .get(&agent.session_id)
                .map(|entry| row_projection(&entry.session, &agent));
        // A thread has exactly one owner, including when a batch replaces its member ID.
        if let Some(other) = self.agent_by_thread(&agent.thread_id)
            && other.agent_id != agent.agent_id
        {
            let id = other.agent_id.clone();
            self.remove_agent(&id);
        }
        if let Some(previous) = previous.as_ref() {
            if previous.session_id != agent.session_id || previous.thread_id != agent.thread_id {
                self.remove_agent(&previous.agent_id);
            }
        }
        if agent.explicitly_closed {
            self.explicitly_closed.insert(agent.agent_id.clone());
        }
        if self
            .native_activity
            .get(&agent.agent_id)
            .is_some_and(|projection| {
                projection.observation.session_id != agent.session_id
                    || projection.observation.thread_id != agent.thread_id
                    || !matches!(agent.backend, crate::AgentBackend::Native { .. })
            })
        {
            self.native_activity.remove(&agent.agent_id);
        }
        self.agent_order.insert(agent.agent_id.clone());
        self.thread_to_session
            .insert(agent.thread_id.clone(), agent.session_id.clone());
        self.agent_to_session
            .insert(agent.agent_id.clone(), agent.session_id.clone());
        let thread_id = agent.thread_id.clone();
        self.sessions
            .get_mut(&agent.session_id)?
            .insert_agent(agent);
        if changed {
            self.metadata_signals.wake(&thread_id);
        }
        Some(())
    }

    pub(super) fn remove_agent(&mut self, agent_id: &str) {
        if let Some(session_id) = self.agent_to_session.remove(agent_id)
            && let Some(entry) = self.sessions.get_mut(&session_id)
            && let Some(agent) = entry.agents.remove(agent_id)
        {
            entry.agents_by_thread.remove(&agent.thread_id);
            self.thread_to_session.remove(&agent.thread_id);
            self.metadata_signals.wake(&agent.thread_id);
        }
        self.agent_order.remove(agent_id);
        self.explicitly_closed.remove(agent_id);
        self.native_activity.remove(agent_id);
    }

    pub(super) fn delete_thread(&mut self, thread_id: &str) {
        if let Some(agent) = self.agent_by_thread(thread_id).cloned() {
            if agent.is_root_agent() {
                if let Some(entry) = self.sessions.remove(&agent.session_id) {
                    self.order.remove(&(
                        entry.session.directory_sort_time(),
                        agent.session_id.clone(),
                    ));
                    for member in entry.agents.values() {
                        self.thread_to_session.remove(&member.thread_id);
                        self.agent_to_session.remove(&member.agent_id);
                        self.agent_order.remove(&member.agent_id);
                        self.metadata_signals.wake(&member.thread_id);
                        self.explicitly_closed.remove(&member.agent_id);
                        self.native_activity.remove(&member.agent_id);
                        self.deleted.insert(member.thread_id.clone());
                    }
                }
                self.deleted_sessions.insert(agent.session_id);
            } else {
                self.remove_agent(&agent.agent_id);
            }
        }
        self.deleted.insert(thread_id.to_owned());
    }

    pub(super) fn get_session(&self, session_id: &str) -> Option<&SessionDirectoryRecord> {
        self.sessions.get(session_id).map(|entry| &entry.session)
    }

    pub(super) fn agent_directory_entry(
        &self,
        agent_id: &str,
    ) -> Option<StudioAgentDirectoryEntry> {
        let agent = self.get_agent(agent_id)?;
        let session = self.get_session(&agent.session_id)?;
        Some({
            let native = self.native_activity.get(&agent.agent_id);
            let mut activity = match agent.backend {
                crate::AgentBackend::Native { .. } => native
                    .and_then(|projection| projection.activity.clone())
                    .unwrap_or_else(|| cold_native_activity(agent)),
                crate::AgentBackend::Acp { .. } => StudioAgentActivity::Acp {
                    explicitly_closed: agent.explicitly_closed,
                },
            };
            if agent.explicitly_closed
                && let StudioAgentActivity::Native {
                    state,
                    can_stop,
                    awaiting_scheduling,
                    ..
                } = &mut activity
            {
                *state = if agent.native_status() == Some(ThreadStatus::Closed) {
                    crate::AgentState::Closed(crate::ClosedAgentState::new())
                } else {
                    crate::AgentState::Closing(crate::ClosingAgentState::new())
                };
                *can_stop = false;
                *awaiting_scheduling = false;
            }
            StudioAgentDirectoryEntry {
                agent_id: agent.agent_id.clone(),
                session_id: agent.session_id.clone(),
                parent_agent_id: agent.parent_agent_id.clone(),
                thread_id: agent.thread_id.clone(),
                role: agent.role.clone(),
                delegation_mode: session.delegation_mode,
                delegation_preference: session.delegation_preference,
                frozen_model: agent.frozen_model(),
                task: agent
                    .title
                    .clone()
                    .unwrap_or_else(|| session.display_title().to_owned()),
                summary: native.and_then(|projection| projection.summary.clone()),
                activity,
                updated_at: agent.updated_at,
            }
        })
    }

    pub(super) fn agent_directory_members(
        &self,
        ids: impl IntoIterator<Item = String>,
    ) -> BTreeMap<String, Option<StudioAgentDirectoryEntry>> {
        ids.into_iter()
            .map(|id| {
                let entry = self.agent_directory_entry(&id);
                (id, entry)
            })
            .collect()
    }

    pub(super) fn agent_directory_entries(&self) -> Vec<StudioAgentDirectoryEntry> {
        tracing::trace!(
            materialized_agents = self.agent_order.len(),
            "materialize agent directory snapshot"
        );
        self.agent_order
            .iter()
            .filter_map(|id| self.agent_directory_entry(id))
            .collect()
    }

    pub(super) fn agent_directory_changes(
        &self,
        before: BTreeMap<String, Option<StudioAgentDirectoryEntry>>,
    ) -> AgentDirectoryChanges {
        let mut changes = AgentDirectoryChanges {
            upserted: Vec::new(),
            removed: Vec::new(),
            compared: 0,
        };
        for (id, previous) in before {
            changes.compared += 1;
            let current = self.agent_directory_entry(&id);
            if current != previous {
                match current {
                    Some(entry) => changes.upserted.push(entry),
                    None => changes.removed.push(id),
                }
            }
        }
        changes
    }

    /// Enumerate only members whose row can be affected by this command.
    pub(super) fn delta_agent_ids(&self, delta: &DirectoryDelta) -> BTreeSet<String> {
        let mut ids = BTreeSet::new();
        for session_id in delta
            .session_upserts
            .iter()
            .map(|session| &session.session_id)
            .chain(
                delta
                    .session_removals
                    .iter()
                    .flat_map(|removal| &removal.session_ids),
            )
            .chain(
                delta
                    .project_removals
                    .iter()
                    .flat_map(|removal| &removal.session_ids),
            )
        {
            if let Some(entry) = self.sessions.get(session_id) {
                ids.extend(entry.agents.keys().cloned());
            }
        }
        for agent in &delta.agent_upserts {
            ids.insert(agent.agent_id.clone());
            if let Some(previous) = self.agent_by_thread(&agent.thread_id) {
                ids.insert(previous.agent_id.clone());
            }
        }
        for thread_id in &delta.thread_deletions {
            if let Some(agent) = self.agent_by_thread(thread_id) {
                if agent.is_root_agent() {
                    if let Some(entry) = self.sessions.get(&agent.session_id) {
                        ids.extend(entry.agents.keys().cloned());
                    }
                } else {
                    ids.insert(agent.agent_id.clone());
                }
            }
        }
        ids
    }

    pub(super) fn get_agent(&self, agent_id: &str) -> Option<&AgentDirectoryRecord> {
        self.sessions
            .get(self.agent_to_session.get(agent_id)?)?
            .agents
            .get(agent_id)
    }

    pub(super) fn agent_by_thread(&self, thread_id: &str) -> Option<&AgentDirectoryRecord> {
        self.sessions
            .get(self.thread_to_session.get(thread_id)?)?
            .agent_by_thread(thread_id)
    }

    pub(super) fn directory_facts(
        &self,
        thread_id: &str,
    ) -> Option<(&SessionDirectoryRecord, &AgentDirectoryRecord)> {
        let entry = self.sessions.get(self.thread_to_session.get(thread_id)?)?;
        let agent = entry.agent_by_thread(thread_id)?;
        Some((&entry.session, agent))
    }

    pub(super) fn native_observation_facts(
        &self,
        observation: &NativeAgentObservation,
    ) -> Option<(
        &SessionDirectoryRecord,
        &AgentDirectoryRecord,
        &NativeAgentProjection,
    )> {
        let (session, agent) = self.directory_facts(&observation.thread_id)?;
        let projection = self.native_activity.get(&agent.agent_id)?;
        if session.archived
            || agent.session_id != observation.session_id
            || agent.agent_id != observation.agent_id
            || !matches!(agent.backend, crate::AgentBackend::Native { .. })
            || projection.observation != *observation
        {
            return None;
        }
        Some((session, agent, projection))
    }

    /// 从 owner 的已提交目录切面读取成员身份、绑定及父成员默认 Thread。
    pub(super) fn execution_identity(
        &self,
        thread_id: &str,
    ) -> Option<(
        crate::AgentThreadIdentity,
        crate::AgentBinding,
        Option<crate::ThreadId>,
    )> {
        let (session, agent) = self.directory_facts(thread_id)?;
        let parent_thread_id = agent
            .parent_agent_id
            .as_deref()
            .and_then(|parent| self.sessions.get(&session.session_id)?.agents.get(parent))
            .map(|parent| crate::ThreadId::new(parent.thread_id.clone()))
            .transpose()
            .ok()?;
        Some((
            crate::AgentThreadIdentity {
                session_id: crate::SessionId::new(session.session_id.clone()).ok()?,
                agent_id: crate::AgentId::new(agent.agent_id.clone()).ok()?,
                parent_agent_id: agent
                    .parent_agent_id
                    .clone()
                    .map(crate::AgentId::new)
                    .transpose()
                    .ok()?,
                thread_id: crate::ThreadId::new(agent.thread_id.clone()).ok()?,
            },
            agent.backend.binding(),
            parent_thread_id,
        ))
    }

    /// 从目录事实投影 Native 执行域 Thread（既有 Native 消费方使用）。
    pub(super) fn thread_snapshot(&self, thread_id: &str) -> Result<Option<crate::Thread>> {
        self.directory_facts(thread_id)
            .map(|(session, agent)| {
                thread_projection(session, agent, |id| {
                    self.sessions
                        .get(&session.session_id)?
                        .agents
                        .get(id)
                        .map(|agent| agent.thread_id.clone())
                })
            })
            .transpose()
    }

    pub(in crate::studio::product_event_bus) fn update_projects(
        &mut self,
        upserted: &[crate::WorkspaceRecord],
        _removed: &[crate::studio::store::directory::ProjectRemoval],
    ) -> bool {
        let mut changed = false;
        for project in upserted {
            let projection = format!("{} {}", project.name, project.path).to_lowercase();
            if self.projects.get(&project.id) != Some(&projection) {
                self.projects.insert(project.id.clone(), projection);
                changed = true;
            }
        }
        changed
    }

    pub(super) fn sorted_active_root_rows(&self) -> Vec<SessionDirectoryRow> {
        self.order
            .iter()
            .rev()
            .filter_map(|(_, id)| self.sessions.get(id))
            .filter(|entry| !entry.session.archived)
            .filter_map(|entry| entry.root_row())
            .filter(|row| row.is_root_row())
            .collect()
    }

    pub(super) fn query(
        &self,
        query: &ThreadDirectoryQuery,
        before: Option<&ThreadDirectoryCursor>,
        limit: usize,
    ) -> (
        Vec<SessionDirectoryRow>,
        Option<String>,
        DirectoryReadMetrics,
    ) {
        let boundary = before.map(|cursor| (cursor.sort_time, cursor.id.clone()));
        let search = query
            .search
            .as_deref()
            .map(str::trim)
            .unwrap_or_default()
            .to_lowercase();
        let mut rows = Vec::with_capacity(limit.saturating_add(1));
        let mut scanned = 0;
        let mut visit = |(_, id): &(i64, String)| {
            let Some(entry) = self.sessions.get(id) else {
                return true;
            };
            scanned += 1;
            let Some(row) = entry.root_row() else {
                return true;
            };
            let project_matches = query.search.is_some()
                && self
                    .projects
                    .get(&row.workspace_id)
                    .is_some_and(|project| project.contains(&search));
            if query.matches(&row, project_matches) {
                rows.push(row);
                if rows.len() > limit {
                    return false;
                }
            }
            true
        };
        // A fixed ID group has at most the configured pin budget. Sort only its
        // ID keys instead of scanning the whole directory to find those rows.
        let included = query.thread_ids.as_ref().map(|ids| {
            ids.iter()
                .filter_map(|id| self.agent_by_thread(id))
                .filter(|agent| agent.is_root_agent())
                .filter_map(|agent| {
                    let entry = self.sessions.get(&agent.session_id)?;
                    Some((
                        entry.session.directory_sort_time(),
                        entry.session.session_id.clone(),
                    ))
                })
                .collect::<BTreeSet<_>>()
        });
        let order = included.as_ref().unwrap_or(&self.order);
        if let Some(boundary) = boundary.as_ref() {
            for key in order.range(..boundary.clone()).rev() {
                if !visit(key) {
                    break;
                }
            }
        } else {
            for key in order.iter().rev() {
                if !visit(key) {
                    break;
                }
            }
        }
        let materialized = rows.len();
        let has_more = materialized > limit;
        rows.truncate(limit);
        let next_cursor = has_more
            .then(|| rows.last())
            .flatten()
            .map(|row| ThreadDirectoryCursor {
                sort_time: row.directory_sort_time(),
                id: row.session_id.clone(),
            })
            .map(|cursor| cursor.encode());
        (
            rows,
            next_cursor,
            DirectoryReadMetrics {
                scanned,
                materialized,
            },
        )
    }
}

impl ThreadDirectoryIndex {
    pub(super) fn agents_of(&self, session_id: &str) -> Vec<AgentDirectoryRecord> {
        self.sessions
            .get(session_id)
            .map(|entry| entry.agents.values().cloned().collect())
            .unwrap_or_default()
    }
}

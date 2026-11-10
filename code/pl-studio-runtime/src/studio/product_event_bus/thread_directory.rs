//! 会话/成员目录：唯一内存摘要、查询窗口与目录事实提交。
//!
//! 目录身份是 typed 四元组（SessionId/AgentId/parent AgentId/ThreadId）；查询只
//! 从本 owner 的提交切面投影 [`SessionDirectoryRow`]，不从 Native 执行快照反推
//! 成员归属。会话级事实（标题、排序时间、归档、Mode、工作区、分发设置）唯一归属
//! 会话记录；成员关系唯一归属成员记录的 `parent_agent_id`。

use anyhow::Result;
use pl_protocol::studio::{
    ResourceStamp, StudioError, StudioErrorCode, ThreadDirectoryFrame, ThreadDirectoryQuery,
    ThreadDirectoryWindow, ThreadMetadataFrame,
};
use pl_protocol::{SessionDirectoryRow, ThreadStatus};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};

#[cfg(test)]
pub(super) mod tests;

use crate::studio::records::{
    AgentDirectoryRecord, SessionDirectoryRecord, row_projection, thread_projection,
};
use crate::studio::store::directory::{DirectoryDelta, ThreadDirectoryCursor};
use crate::{
    StudioProductEventEnvelope, StudioProductEventKind, StudioThreadDirectoryData,
    StudioThreadDirectoryDelta, StudioThreadDirectoryPage, StudioThreadDirectoryPageData,
    StudioThreadDirectoryState,
};

use super::ProductEventBus;

const THREAD_DIRECTORY_RESOURCE_KEY: &str = "thread-directory";

/// 一个会话在内存目录中的完整事实：会话记录 + 其全部成员。
struct SessionDirectoryEntry {
    session: SessionDirectoryRecord,
    agents: BTreeMap<String, AgentDirectoryRecord>,
    /// 成员默认 Thread → 成员 ID；首版一一同字节映射。
    agents_by_thread: HashMap<String, String>,
}

impl SessionDirectoryEntry {
    fn new(session: SessionDirectoryRecord) -> Self {
        Self {
            session,
            agents: BTreeMap::new(),
            agents_by_thread: HashMap::new(),
        }
    }

    fn insert_agent(&mut self, agent: AgentDirectoryRecord) {
        self.agents_by_thread
            .insert(agent.thread_id.clone(), agent.agent_id.clone());
        self.agents.insert(agent.agent_id.clone(), agent);
    }

    fn root_agent(&self) -> Option<&AgentDirectoryRecord> {
        self.agents.get(&self.session.root_agent_id)
    }

    fn agent_by_thread(&self, thread_id: &str) -> Option<&AgentDirectoryRecord> {
        let agent_id = self.agents_by_thread.get(thread_id)?;
        self.agents.get(agent_id)
    }

    /// 主成员行投影；会话没有已注册主成员时返回 `None`。
    fn root_row(&self) -> Option<SessionDirectoryRow> {
        self.root_agent()
            .map(|agent| row_projection(&self.session, agent))
    }
}

pub(super) struct ThreadDirectoryIndex {
    sessions: HashMap<String, SessionDirectoryEntry>,
    order: BTreeSet<(i64, String)>,
    projects: HashMap<String, String>,
    explicitly_closed: HashSet<String>,
    deleted: HashSet<String>,
    deleted_sessions: HashSet<String>,
}

impl ThreadDirectoryIndex {
    pub(super) fn new(
        sessions: Vec<SessionDirectoryRecord>,
        agents: Vec<AgentDirectoryRecord>,
        projects: &[crate::WorkspaceRecord],
    ) -> ThreadDirectoryIndex {
        let mut index = Self {
            sessions: HashMap::new(),
            order: BTreeSet::new(),
            projects: HashMap::new(),
            explicitly_closed: HashSet::new(),
            deleted: HashSet::new(),
            deleted_sessions: HashSet::new(),
        };
        for session in sessions {
            let key = (session.directory_sort_time(), session.session_id.clone());
            index.sessions.insert(
                session.session_id.clone(),
                SessionDirectoryEntry::new(session),
            );
            index.order.insert(key);
        }
        for agent in agents {
            if agent.explicitly_closed {
                index.explicitly_closed.insert(agent.agent_id.clone());
            }
            index.insert_agent(agent);
        }
        index.update_projects(projects, &[]);
        index
    }

    fn insert_session(&mut self, session: SessionDirectoryRecord) {
        if self.deleted_sessions.contains(&session.session_id) {
            return;
        }
        let key = (session.directory_sort_time(), session.session_id.clone());
        if let Some(previous) = self.sessions.get_mut(&session.session_id) {
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
    }

    fn insert_agent(&mut self, agent: AgentDirectoryRecord) -> Option<()> {
        if self.deleted.contains(&agent.thread_id) {
            return None;
        }
        self.sessions
            .get_mut(&agent.session_id)?
            .insert_agent(agent);
        Some(())
    }

    fn remove_agent(&mut self, agent_id: &str) {
        if let Some(entry) = self
            .sessions
            .values_mut()
            .find(|entry| entry.agents.contains_key(agent_id))
            && let Some(agent) = entry.agents.remove(agent_id)
        {
            entry.agents_by_thread.remove(&agent.thread_id);
        }
        self.explicitly_closed.remove(agent_id);
    }

    fn delete_thread(&mut self, thread_id: &str) {
        if let Some(agent) = self.agent_by_thread(thread_id).cloned() {
            if agent.is_root_agent() {
                if let Some(entry) = self.sessions.remove(&agent.session_id) {
                    self.order.remove(&(
                        entry.session.directory_sort_time(),
                        agent.session_id.clone(),
                    ));
                    for member in entry.agents.values() {
                        self.explicitly_closed.remove(&member.agent_id);
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

    fn get_session(&self, session_id: &str) -> Option<&SessionDirectoryRecord> {
        self.sessions.get(session_id).map(|entry| &entry.session)
    }

    fn get_agent(&self, agent_id: &str) -> Option<&AgentDirectoryRecord> {
        self.sessions
            .values()
            .find_map(|entry| entry.agents.get(agent_id))
    }

    fn agent_by_thread(&self, thread_id: &str) -> Option<&AgentDirectoryRecord> {
        self.sessions
            .values()
            .find_map(|entry| entry.agent_by_thread(thread_id))
    }

    fn directory_facts(
        &self,
        thread_id: &str,
    ) -> Option<(&SessionDirectoryRecord, &AgentDirectoryRecord)> {
        let entry = self
            .sessions
            .values()
            .find(|entry| entry.agent_by_thread(thread_id).is_some())?;
        let agent = entry.agent_by_thread(thread_id)?;
        Some((&entry.session, agent))
    }

    /// 从 owner 的已提交目录切面读取成员身份、绑定及父成员默认 Thread。
    fn execution_identity(
        &self,
        thread_id: &str,
    ) -> Option<(
        pl_protocol::AgentThreadIdentity,
        pl_protocol::AgentBinding,
        Option<pl_protocol::ThreadId>,
    )> {
        let (session, agent) = self.directory_facts(thread_id)?;
        let parent_thread_id = agent
            .parent_agent_id
            .as_deref()
            .and_then(|parent| self.sessions.get(&session.session_id)?.agents.get(parent))
            .map(|parent| pl_protocol::ThreadId::new(parent.thread_id.clone()))
            .transpose()
            .ok()?;
        Some((
            pl_protocol::AgentThreadIdentity {
                session_id: pl_protocol::SessionId::new(session.session_id.clone()).ok()?,
                agent_id: pl_protocol::AgentId::new(agent.agent_id.clone()).ok()?,
                parent_agent_id: agent
                    .parent_agent_id
                    .clone()
                    .map(pl_protocol::AgentId::new)
                    .transpose()
                    .ok()?,
                thread_id: pl_protocol::ThreadId::new(agent.thread_id.clone()).ok()?,
            },
            agent.backend.binding(),
            parent_thread_id,
        ))
    }

    /// 从目录事实投影 Native 执行域 Thread（既有 Native 消费方使用）。
    pub(super) fn thread_snapshot(&self, thread_id: &str) -> Result<Option<pl_protocol::Thread>> {
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

    pub(super) fn update_projects(
        &mut self,
        upserted: &[crate::WorkspaceRecord],
        _removed: &[crate::studio::store::directory::ProjectRemoval],
    ) {
        for project in upserted {
            self.projects.insert(
                project.id.clone(),
                format!("{} {}", project.name, project.path).to_lowercase(),
            );
        }
    }

    fn sorted_active_root_rows(&self) -> Vec<SessionDirectoryRow> {
        self.order
            .iter()
            .rev()
            .filter_map(|(_, id)| self.sessions.get(id))
            .filter(|entry| !entry.session.archived)
            .filter_map(|entry| entry.root_row())
            .filter(|row| row.is_root_row())
            .collect()
    }

    fn query(
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
                id: row.thread_id.clone(),
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct DirectoryReadMetrics {
    scanned: usize,
    materialized: usize,
}

struct DirectoryRead {
    frame: ThreadDirectoryFrame,
    updated_at: i64,
    #[cfg(test)]
    metrics: DirectoryReadMetrics,
}

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
    pub(in crate::studio) async fn record_attachments(
        &self,
        records: Vec<crate::studio::AttachmentRecord>,
    ) -> Result<()> {
        self.store.record_attachments(records).await
    }

    pub async fn read_thread_directory(&self) -> Result<StudioThreadDirectoryState> {
        let index = self
            .thread_index
            .lock()
            .expect("thread index lock poisoned");
        Ok(StudioThreadDirectoryState {
            state: self.resource(
                &self.revisions.thread,
                StudioThreadDirectoryData {
                    rows: index.sorted_active_root_rows(),
                },
            ),
        })
    }

    pub fn read_threads_window(
        &self,
        query: &ThreadDirectoryQuery,
        window: &ThreadDirectoryWindow,
        owner_epoch: &str,
    ) -> Result<ThreadDirectoryFrame> {
        let read = self.read_threads_window_inner(query, window, owner_epoch)?;
        Self::check_frame_size(&read.frame)?;
        Ok(read.frame)
    }

    pub fn read_thread_metadata(
        &self,
        thread_id: &str,
        owner_epoch: &str,
    ) -> Result<ThreadMetadataFrame> {
        let frame = {
            let index = self
                .thread_index
                .lock()
                .expect("thread index lock poisoned");
            ThreadMetadataFrame {
                thread_id: thread_id.to_owned(),
                stamp: self.thread_stamp(owner_epoch),
                row: index
                    .directory_facts(thread_id)
                    .map(|(session, agent)| row_projection(session, agent)),
            }
        };
        Self::check_frame_size(&frame)?;
        Ok(frame)
    }

    fn read_threads_window_inner(
        &self,
        query: &ThreadDirectoryQuery,
        window: &ThreadDirectoryWindow,
        owner_epoch: &str,
    ) -> Result<DirectoryRead> {
        let query = query.clone().normalized()?;
        window.validate()?;
        let before = window
            .before
            .as_deref()
            .map(|cursor| {
                ThreadDirectoryCursor::decode(cursor)
                    .ok_or_else(|| StudioError::invalid_argument("Invalid directory cursor"))
            })
            .transpose()?;
        let lock_wait_started = std::time::Instant::now();
        let index = self
            .thread_index
            .lock()
            .expect("thread index lock poisoned");
        let lock_acquired = std::time::Instant::now();
        let (rows, next_cursor, metrics) =
            index.query(&query, before.as_ref(), window.limit as usize);
        let (revision, updated_at) = self.revision(&self.revisions.thread);
        drop(index);
        let lock_wait_micros =
            u64::try_from(lock_acquired.duration_since(lock_wait_started).as_micros())
                .unwrap_or(u64::MAX);
        let lock_held_micros =
            u64::try_from(lock_acquired.elapsed().as_micros()).unwrap_or(u64::MAX);
        tracing::trace!(
            scanned = metrics.scanned,
            materialized = metrics.materialized,
            lock_wait_micros,
            lock_held_micros,
            "read thread directory window"
        );
        Ok(DirectoryRead {
            frame: ThreadDirectoryFrame {
                query,
                window: window.clone(),
                stamp: ResourceStamp {
                    resource_key: THREAD_DIRECTORY_RESOURCE_KEY.into(),
                    owner_epoch: owner_epoch.into(),
                    revision,
                },
                rows,
                next_cursor,
            },
            updated_at,
            #[cfg(test)]
            metrics,
        })
    }

    fn thread_stamp(&self, owner_epoch: &str) -> ResourceStamp {
        ResourceStamp {
            resource_key: THREAD_DIRECTORY_RESOURCE_KEY.into(),
            owner_epoch: owner_epoch.into(),
            revision: self.revision(&self.revisions.thread).0,
        }
    }

    fn check_frame_size(frame: &impl serde::Serialize) -> Result<()> {
        let bytes = serde_json::to_vec(frame)?;
        if bytes.len() > ThreadDirectoryWindow::MAX_FRAME_BYTES {
            return Err(StudioError::new(
                StudioErrorCode::Overloaded,
                "Directory frame exceeds the 256 KiB delivery limit",
                false,
            )
            .into());
        }
        Ok(())
    }

    async fn read_legacy_thread_page(
        &self,
        query: &ThreadDirectoryQuery,
        cursor: Option<&str>,
        limit: usize,
    ) -> Result<StudioThreadDirectoryPage> {
        let limit = limit.clamp(1, ThreadDirectoryWindow::MAX_LIMIT as usize) as u32;
        let read = self.read_threads_window_inner(
            query,
            &ThreadDirectoryWindow {
                before: cursor.map(str::to_owned),
                limit,
            },
            "",
        )?;
        Self::check_frame_size(&read.frame)?;
        #[cfg(test)]
        tests::pause(&self.directory_test_pauses.page_captured).await;
        Ok(StudioThreadDirectoryPage {
            state: pl_protocol::ObservedResource::ready(
                read.frame.stamp.revision,
                read.updated_at,
                StudioThreadDirectoryPageData {
                    rows: read.frame.rows,
                    next_cursor: read.frame.next_cursor,
                },
            ),
        })
    }

    /// Legacy one-shot page entry; it uses the same current RAM owner as observations.
    pub async fn read_thread_directory_page(
        &self,
        cursor: Option<&str>,
        limit: usize,
    ) -> Result<StudioThreadDirectoryPage> {
        self.read_legacy_thread_page(&ThreadDirectoryQuery::default(), cursor, limit)
            .await
    }

    /// Legacy filtered query entry; it delegates to the same RAM query slice.
    pub async fn query_threads(
        &self,
        query: &ThreadDirectoryQuery,
        cursor: Option<&str>,
        limit: usize,
    ) -> Result<StudioThreadDirectoryPage> {
        self.read_legacy_thread_page(query, cursor, limit).await
    }

    /// 应用一次目录增量并发布 `ThreadDirectoryChanged` 事件（纯内存维护）。
    pub async fn apply_thread_delta(
        &self,
        upserted: Vec<SessionDirectoryRow>,
        removed: Vec<String>,
    ) -> Result<StudioProductEventEnvelope> {
        Ok(self.publish_thread_delta(upserted, removed, Vec::new()))
    }

    fn publish_thread_delta(
        &self,
        upserted: Vec<SessionDirectoryRow>,
        removed: Vec<String>,
        archived: Vec<SessionDirectoryRow>,
    ) -> StudioProductEventEnvelope {
        let mut index = self
            .thread_index
            .lock()
            .expect("thread index lock poisoned");
        self.publish_thread_delta_locked(&mut index, upserted, removed, archived)
    }

    fn publish_thread_delta_locked(
        &self,
        index: &mut ThreadDirectoryIndex,
        mut upserted: Vec<SessionDirectoryRow>,
        removed: Vec<String>,
        archived: Vec<SessionDirectoryRow>,
    ) -> StudioProductEventEnvelope {
        upserted.retain(|row| !index.deleted.contains(&row.thread_id));
        for row in &mut upserted {
            Self::apply_explicit_close_row(index, row);
            // 迟到快照不得使最近用户消息时间回退：目录命令携带的完整行可能
            // 早于一次已受理的用户输入，进入当前摘要前保留较新值。
            if let Some((session, agent)) = index.directory_facts(&row.thread_id) {
                if row.is_root_row() {
                    row.last_user_message_at =
                        row.last_user_message_at.max(session.last_user_message_at);
                }
                let _ = agent;
            }
            Self::index_insert_row(index, row.clone());
        }
        for id in &removed {
            index.remove_agent(id);
        }
        for row in archived {
            Self::index_insert_row(index, row);
        }
        self.prepare_child_interaction_directory(&upserted);
        self.remove_child_interaction_directory(&removed);
        // State and tombstones are visible before observers receive removal.
        self.emit_thread_delta_locked(index, upserted, removed)
    }

    /// 把行投影拆回会话/成员事实写入索引。
    fn index_insert_row(index: &mut ThreadDirectoryIndex, row: SessionDirectoryRow) {
        if index.deleted.contains(&row.thread_id)
            || index.deleted_sessions.contains(&row.session_id)
        {
            return;
        }
        let session = SessionDirectoryRecord {
            session_id: row.session_id.clone(),
            root_agent_id: if row.is_root_row() {
                row.agent_id.clone()
            } else {
                index
                    .get_session(&row.session_id)
                    .map(|session| session.root_agent_id.clone())
                    .unwrap_or_default()
            },
            workspace_id: row.workspace_id.clone(),
            title: if row.is_root_row() {
                row.title.clone()
            } else {
                index
                    .get_session(&row.session_id)
                    .map(|session| session.title.clone())
                    .unwrap_or_default()
            },
            native_mode: if row.is_root_row() {
                row.mode.clone()
            } else {
                index
                    .sessions
                    .get(&row.session_id)
                    .and_then(|entry| entry.session.native_mode.clone())
            },
            workspace_mode: row.workspace_mode,
            delegation_mode: row.delegation_mode,
            delegation_preference: row.delegation_preference,
            workspace_path: row.workspace_path.clone(),
            created_at: if row.is_root_row() {
                row.created_at
            } else {
                index
                    .get_session(&row.session_id)
                    .map(|session| session.created_at)
                    .unwrap_or(row.created_at)
            },
            updated_at: row.updated_at,
            last_user_message_at: if row.is_root_row() {
                row.last_user_message_at
            } else {
                index
                    .get_session(&row.session_id)
                    .and_then(|session| session.last_user_message_at)
            },
            archived: row.archived,
        };
        let agent = AgentDirectoryRecord {
            agent_id: row.agent_id.clone(),
            session_id: row.session_id.clone(),
            parent_agent_id: row.parent_agent_id.clone(),
            thread_id: row.thread_id.clone(),
            role: row.role.clone(),
            title: (!row.is_root_row()).then(|| row.title.clone()),
            backend: row.backend.clone(),
            explicitly_closed: false,
            created_at: row.created_at,
            updated_at: row.updated_at,
        };
        index.insert_session(session);
        index.insert_agent(agent);
    }

    fn apply_explicit_close_row(index: &ThreadDirectoryIndex, row: &mut SessionDirectoryRow) {
        if index.explicitly_closed.contains(&row.agent_id)
            && let pl_protocol::session::AgentBackend::Native { status, .. } = &mut row.backend
        {
            *status = if index
                .get_agent(&row.agent_id)
                .is_some_and(|agent| agent.native_status() == Some(ThreadStatus::Closed))
            {
                ThreadStatus::Closed
            } else {
                crate::studio::agent_close::directory_status(*status, true)
            };
        }
    }

    fn apply_explicit_close_agent(index: &ThreadDirectoryIndex, agent: &mut AgentDirectoryRecord) {
        if index.explicitly_closed.contains(&agent.agent_id) {
            // 把关闭意图写回成员事实：`projected_status` 以该标志区分 Closed 与 Idle，
            // 缺失时已确认关闭的成员会被目录投影降级回 Idle。
            agent.explicitly_closed = true;
            if let Some(status) = agent.native_status() {
                let next = if index
                    .get_agent(&agent.agent_id)
                    .is_some_and(|existing| existing.native_status() == Some(ThreadStatus::Closed))
                {
                    ThreadStatus::Closed
                } else {
                    crate::studio::agent_close::directory_status(status, true)
                };
                agent.set_native_status(next);
            }
        }
    }

    /// Publish the durable close intent into this same current-metadata boundary.
    pub(in crate::studio) async fn commit_explicit_close(&self, thread_id: &str) -> Result<()> {
        let _command = self.directory_commands.lock().await;
        self.store
            .catalog()
            .project_explicit_close(thread_id)
            .await?;
        // A cold row is not resident in the directory index. Re-read exactly this durable row
        // instead of opening a list observation for it, then commit through the same path.
        let resident = self
            .thread_index
            .lock()
            .expect("thread index lock poisoned")
            .agent_by_thread(thread_id)
            .is_some();
        if !resident {
            let catalog = self.store.catalog();
            let agent = catalog
                .agent_by_thread(thread_id)
                .ok_or_else(|| StudioError::not_found("session"))?;
            let session_record = catalog
                .get_session(&agent.session_id)
                .ok_or_else(|| StudioError::not_found("session"))?;
            let mut index = self
                .thread_index
                .lock()
                .expect("thread index lock poisoned");
            index.insert_session(session_record.clone());
            index.insert_agent(agent);
        }
        let mut index = self
            .thread_index
            .lock()
            .expect("thread index lock poisoned");
        let Some((session_record, mut agent)) = index
            .directory_facts(thread_id)
            .map(|(session, agent)| (session.clone(), agent.clone()))
        else {
            return Err(StudioError::not_found("session").into());
        };
        let newly_closed = index.explicitly_closed.insert(agent.agent_id.clone());
        let previous_status = agent.native_status();
        Self::apply_explicit_close_agent(&index, &mut agent);
        if !newly_closed && previous_status == agent.native_status() {
            return Ok(());
        }
        index.insert_agent(agent.clone());
        let row = row_projection(&session_record, &agent);
        self.writer.record_directory(DirectoryDelta {
            agent_upserts: vec![agent],
            ..Default::default()
        });
        self.emit_thread_delta_locked(&index, vec![row], vec![]);
        Ok(())
    }

    /// Caller holds thread_index through mutation, watermark capture and synchronous dispatch.
    fn emit_thread_delta_locked(
        &self,
        _index: &ThreadDirectoryIndex,
        upserted: Vec<SessionDirectoryRow>,
        removed: Vec<String>,
    ) -> StudioProductEventEnvelope {
        self.bump(&self.revisions.thread);
        let (revision, updated_at) = self.revision(&self.revisions.thread);
        self.emit(StudioProductEventKind::ThreadDirectoryChanged(
            StudioThreadDirectoryDelta {
                revision,
                updated_at,
                upserted,
                removed,
            },
        ))
    }

    /// Applies only runtime-owned fields to the current directory summary.
    /// Missing or archived entries are never reinserted by a delayed observation.
    pub(in crate::studio) fn patch_thread_runtime(
        &self,
        thread_id: &str,
        status: pl_protocol::ThreadStatus,
        committed_at: i64,
        snapshot: &pl_core::thread::ThreadSnapshot,
    ) -> Result<Option<SessionDirectoryRow>> {
        let delegation = crate::studio::delegation::saved(snapshot)?;
        let frozen_profile = crate::studio::model_route::saved_profile(snapshot)?;
        let explicitly_closed = crate::studio::agent_close::is_explicitly_closed(snapshot)?;
        let mut index = self
            .thread_index
            .lock()
            .expect("thread index lock poisoned");
        let Some((session_record, mut agent)) = index
            .directory_facts(thread_id)
            .map(|(session, agent)| (session.clone(), agent.clone()))
        else {
            return Ok(None);
        };
        if session_record.archived {
            return Ok(None);
        }
        if let Some((profile, _)) = &frozen_profile {
            anyhow::ensure!(
                agent.parent_agent_id.is_some() && profile.profile_id == agent.role,
                "frozen Profile conflicts with directory identity"
            );
        }
        let mut session_next = session_record.clone();
        if let Some(delegation) = delegation {
            session_next.delegation_mode = delegation.mode;
            session_next.delegation_preference = delegation.preference;
        }
        if let Some((profile, _)) = frozen_profile
            && let pl_protocol::session::AgentBackend::Native { config, .. } = &mut agent.backend
        {
            config.route = Some(crate::studio::delegation::profile_model(&profile));
        }
        if explicitly_closed {
            index.explicitly_closed.insert(agent.agent_id.clone());
        }
        agent.set_native_status(status);
        Self::apply_explicit_close_agent(&index, &mut agent);
        agent.updated_at = agent.updated_at.max(committed_at);
        session_next.updated_at = session_next.updated_at.max(committed_at);
        index.insert_agent(agent.clone());
        index.insert_session(session_next.clone());
        // 状态观察是目录事实：只把有界摘要并入 write-behind 目录队列，不在观察热路径做文件 I/O。
        // 同一成员的连续 delta 由队列合并；write-behind 批次经 `apply_directory_delta` 把摘要
        // 幂等写入 catalog/workspaces TOML。调用方在发布后用固定目标 ticket（`flush_through`）
        // 建立保存屏障；状态错误不回滚已提交的内存目录事实。
        self.writer.record_directory(DirectoryDelta {
            session_upserts: vec![session_next.clone()],
            agent_upserts: vec![agent.clone()],
            ..Default::default()
        });
        let row = row_projection(&session_next, &agent);
        self.emit_thread_delta_locked(&index, vec![row.clone()], Vec::new());
        Ok(Some(row))
    }

    /// Records the acceptance of a user message as a directory fact.
    ///
    /// Called only after the runtime successfully admitted a user input (queued inputs count;
    /// rejected submissions never reach this point). The timestamp never regresses, and a missing
    /// or archived entry is not reinserted. Persistence rides the same write-behind directory
    /// queue as runtime patches; a later model/storage failure cannot undo the recorded fact.
    pub(in crate::studio) fn record_user_message(&self, thread_id: &str, accepted_at: i64) {
        let mut index = self
            .thread_index
            .lock()
            .expect("thread index lock poisoned");
        let Some((mut session, agent)) = index
            .directory_facts(thread_id)
            .map(|(session, agent)| (session.clone(), agent.clone()))
        else {
            return;
        };
        if session.archived {
            return;
        }
        session.last_user_message_at = Some(
            session
                .last_user_message_at
                .map_or(accepted_at, |existing| existing.max(accepted_at)),
        );
        session.updated_at = session.updated_at.max(accepted_at);
        index.insert_session(session.clone());
        self.writer.record_directory(DirectoryDelta {
            session_upserts: vec![session.clone()],
            ..Default::default()
        });
        let row = row_projection(&session, &agent);
        self.emit_thread_delta_locked(&index, vec![row], Vec::new());
    }

    /// Records only the Mode fact already committed by core, not an earlier whole-row copy.
    /// A failed/cancelled wait cannot reject that fact: write-behind retains the exact delta and
    /// exposes its normal PersistenceState/retry path. No core operation is replayed on retry.
    pub(in crate::studio) async fn commit_observed_thread_mode(
        &self,
        thread_id: &str,
        mode: pl_protocol::ThreadModeId,
        committed_at: i64,
    ) -> Result<StudioProductEventEnvelope> {
        let (ticket, event) = {
            let mut index = self
                .thread_index
                .lock()
                .expect("thread index lock poisoned");
            let (mut session, mut agent) = index
                .directory_facts(thread_id)
                .map(|(session, agent)| (session.clone(), agent.clone()))
                .ok_or_else(|| StudioError::not_found("session"))?;
            anyhow::ensure!(
                agent.is_root_agent()
                    && matches!(
                        agent.backend,
                        pl_protocol::session::AgentBackend::Native { .. }
                    ),
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
            let row = row_projection(&session, &agent);
            let event =
                self.publish_thread_delta_locked(&mut index, vec![row], Vec::new(), Vec::new());
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

    /// The caller freezes this baseline when deriving its update, before any await.
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

    async fn commit_directory_with_bases(
        &self,
        delta: DirectoryDelta,
        bases: DirectoryBaselines,
    ) -> Result<StudioProductEventEnvelope> {
        if delta.is_empty() {
            return Err(anyhow::anyhow!("directory delta is empty"));
        }
        let _command = self.directory_commands.lock().await;
        #[cfg(test)]
        tests::pause(&self.directory_test_pauses.commit_before_persist).await;
        // Persist without holding the metadata lock. Readers continue to see the previous
        // committed RAM slice until this durable operation succeeds.
        self.store.persist_directory_summaries(&delta).await?;
        #[cfg(test)]
        tests::pause(&self.directory_test_pauses.commit_persisted).await;
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
            .map(|project| crate::WorkspaceRecord {
                id: project.id.clone(),
                kind: project.kind,
                name: project.name.clone(),
                path: project.path.clone(),
                ssh_alias: project.ssh_alias.clone(),
                updated_at: project.updated_at,
            })
            .collect::<Vec<_>>();
        let project_changed = !project_upserts.is_empty() || !delta.project_removals.is_empty();
        let mut envelope = {
            let mut index = self
                .thread_index
                .lock()
                .expect("thread index lock poisoned");
            let removed_agent_ids = index
                .sessions
                .values()
                .filter(|entry| archived_sessions.contains(&entry.session.session_id))
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
            if project_changed {
                index.update_projects(&project_upserts, &delta.project_removals);
            }
            let mut writer_delta = delta.clone();
            writer_delta.session_upserts = frozen_sessions.into_values().collect();
            writer_delta.agent_upserts = frozen_agents.values().cloned().collect();
            let mut published_sessions = writer_delta.session_upserts.clone();
            self.writer.record_directory(writer_delta);
            // 本提交直接冻结的成员行先入发布切面：没有它，register_session、
            // register_child_agent 与 commit_agent_update 这类携带成员事实的提交
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
            let thread_changed = !published_rows.is_empty() || !removed_agent_ids.is_empty();
            if thread_changed {
                Some(self.emit_thread_delta_locked(&index, published_rows, removed_agent_ids))
            } else if project_changed {
                self.bump(&self.revisions.thread);
                self.topics
                    .lock()
                    .expect("product topic channels lock poisoned")
                    .notify(&crate::StudioProductTopic::ThreadDirectory);
                None
            } else {
                None
            }
        };
        if let Some(project_event) = self
            .apply_project_snapshot_delta(&project_upserts, &delta.project_removals)
            .await?
        {
            envelope = Some(project_event);
        }
        envelope.ok_or_else(|| anyhow::anyhow!("directory delta has no observable changes"))
    }

    /// Reads the current metadata summary without activating a cold Thread.
    pub(crate) fn thread_snapshot(&self, thread_id: &str) -> Result<Option<pl_protocol::Thread>> {
        self.thread_index
            .lock()
            .expect("thread index lock poisoned")
            .thread_snapshot(thread_id)
    }

    /// 纯读目录提交切面；不激活成员，也不读取 Native history/snapshot。
    pub(crate) fn agent_execution_identity(
        &self,
        thread_id: &str,
    ) -> Option<(
        pl_protocol::AgentThreadIdentity,
        pl_protocol::AgentBinding,
        Option<pl_protocol::ThreadId>,
    )> {
        self.thread_index
            .lock()
            .expect("thread index lock poisoned")
            .execution_identity(thread_id)
    }

    /// Resolve a product member without activating Native resources or reading history.
    pub(crate) fn member_identity(
        &self,
        session: &pl_protocol::SessionId,
        agent: &pl_protocol::AgentId,
    ) -> Option<pl_protocol::AgentThreadIdentity> {
        let index = self
            .thread_index
            .lock()
            .expect("thread index lock poisoned");
        let member = index
            .sessions
            .get(session.as_str())?
            .agents
            .get(agent.as_str())?;
        index
            .execution_identity(&member.thread_id)
            .map(|(identity, _, _)| identity)
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
            kind: pl_protocol::ThreadStatus::Faulted,
            error: Some(message.into()),
        };
        agent.set_native_status(pl_protocol::ThreadStatus::Faulted);
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

    /// 当前摘要中一个 Thread 的会话/成员事实快照（目录 owner 提交切面）。
    pub(in crate::studio) fn directory_facts(
        &self,
        thread_id: &str,
    ) -> Option<(SessionDirectoryRecord, AgentDirectoryRecord)> {
        self.thread_index
            .lock()
            .expect("thread index lock poisoned")
            .directory_facts(thread_id)
            .map(|(session, agent)| (session.clone(), agent.clone()))
    }

    pub(in crate::studio) fn directory_member(
        &self,
        thread_id: &str,
    ) -> Result<Option<crate::studio::records::DirectoryMember>> {
        let index = self
            .thread_index
            .lock()
            .expect("thread index lock poisoned");
        index
            .directory_facts(thread_id)
            .map(|(session, agent)| {
                crate::studio::records::DirectoryMember::resolve(
                    session.clone(),
                    agent.clone(),
                    |id| {
                        index
                            .sessions
                            .get(&session.session_id)?
                            .agents
                            .get(id)
                            .cloned()
                    },
                )
            })
            .transpose()
    }

    pub(in crate::studio) fn members_for_root(
        &self,
        root_thread_id: &str,
    ) -> Result<Vec<crate::studio::records::DirectoryMember>> {
        let index = self
            .thread_index
            .lock()
            .expect("thread index lock poisoned");
        let Some(entry) = index.sessions.values().find(|entry| {
            entry
                .root_agent()
                .is_some_and(|root| root.thread_id == root_thread_id)
        }) else {
            return Ok(Vec::new());
        };
        entry
            .agents
            .values()
            .map(|agent| {
                crate::studio::records::DirectoryMember::resolve(
                    entry.session.clone(),
                    agent.clone(),
                    |id| entry.agents.get(id).cloned(),
                )
            })
            .collect()
    }
}

/// 命令通道提交时携带的冻结基线：调用方在任意 await 之前读取。
#[derive(Default)]
pub(in crate::studio) struct DirectoryBaselines {
    sessions: HashMap<String, SessionDirectoryRecord>,
    agents: HashMap<String, AgentDirectoryRecord>,
}

impl ThreadDirectoryIndex {
    fn agents_of(&self, session_id: &str) -> Vec<AgentDirectoryRecord> {
        self.sessions
            .get(session_id)
            .map(|entry| entry.agents.values().cloned().collect())
            .unwrap_or_default()
    }
}

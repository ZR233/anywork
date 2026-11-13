//! 会话/成员目录：唯一内存摘要、查询窗口与目录事实提交。
//!
//! 目录身份是 typed 四元组（SessionId/AgentId/parent AgentId/ThreadId）；查询只
//! 从本 owner 的提交切面投影 [`SessionDirectoryRow`]，不从 Native 执行快照反推
//! 成员归属。会话级事实（标题、排序时间、归档、Mode、工作区、分发设置）唯一归属
//! 会话记录；成员关系唯一归属成员记录的 `parent_agent_id`。

use anyhow::{Context, Result};
use pl_protocol::studio::{
    ResourceStamp, StudioError, StudioErrorCode, ThreadDirectoryFrame, ThreadDirectoryQuery,
    ThreadDirectoryWindow, ThreadMetadataFrame,
};
use pl_protocol::{SessionDirectoryRow, ThreadStatus};
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet};
use std::sync::{Arc, Mutex, Weak};
use tokio::sync::watch;

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
    metadata_signals: HashMap<String, watch::Sender<()>>,
}

/// A demand-scoped wakeup registration, not a metadata/version source.
pub(crate) struct ThreadMetadataSignal {
    receiver: Option<watch::Receiver<()>>,
    index: Weak<Mutex<ThreadDirectoryIndex>>,
    thread_id: String,
}

impl ThreadMetadataSignal {
    pub(crate) fn receiver(&mut self) -> &mut watch::Receiver<()> {
        self.receiver.as_mut().expect("live metadata registration")
    }
}

impl Drop for ThreadMetadataSignal {
    fn drop(&mut self) {
        // Remove the receiver before checking the last demand under the same lock as registration.
        self.receiver.take();
        if let Some(index) = self.index.upgrade() {
            let mut index = index.lock().expect("thread index lock poisoned");
            if index
                .metadata_signals
                .get(&self.thread_id)
                .is_some_and(|sender| sender.receiver_count() == 0)
            {
                index.metadata_signals.remove(&self.thread_id);
            }
        }
    }
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
            metadata_signals: HashMap::new(),
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
        let mut changed_members = Vec::new();
        if let Some(previous) = self.sessions.get_mut(&session.session_id) {
            for agent in previous.agents.values() {
                if self.metadata_signals.contains_key(&agent.thread_id)
                    && row_projection(&previous.session, agent) != row_projection(&session, agent)
                {
                    changed_members.push(agent.thread_id.clone());
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
            self.metadata_signals[&id].send_replace(());
        }
    }

    fn insert_agent(&mut self, agent: AgentDirectoryRecord) -> Option<()> {
        if self.deleted.contains(&agent.thread_id) {
            return None;
        }
        let entry = self.sessions.get_mut(&agent.session_id)?;
        let changed = self.metadata_signals.contains_key(&agent.thread_id)
            && entry
                .agent_by_thread(&agent.thread_id)
                .map(|previous| row_projection(&entry.session, previous))
                != Some(row_projection(&entry.session, &agent));
        let thread_id = agent.thread_id.clone();
        entry.insert_agent(agent);
        if changed {
            self.metadata_signals[&thread_id].send_replace(());
        }
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
            if let Some(signal) = self.metadata_signals.get(&agent.thread_id) {
                signal.send_replace(());
            }
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
                        if let Some(signal) = self.metadata_signals.get(&member.thread_id) {
                            signal.send_replace(());
                        }
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

#[derive(Debug)]
struct DirectoryRead {
    query: ThreadDirectoryQuery,
    window: ThreadDirectoryWindow,
    stamp: ResourceStamp,
    rows: Vec<SessionDirectoryRow>,
    next_cursor: Option<String>,
    updated_at: i64,
    #[cfg(test)]
    metrics: DirectoryReadMetrics,
}

impl DirectoryRead {
    fn into_frame(self) -> ThreadDirectoryFrame {
        ThreadDirectoryFrame {
            query: self.query,
            window: self.window,
            stamp: self.stamp,
            thread_ids: self.rows.into_iter().map(|row| row.thread_id).collect(),
            next_cursor: self.next_cursor,
        }
    }
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
    pub(crate) fn subscribe_thread_metadata(&self, thread_id: &str) -> ThreadMetadataSignal {
        let mut index = self
            .thread_index
            .lock()
            .expect("thread index lock poisoned");
        let receiver = index
            .metadata_signals
            .entry(thread_id.to_owned())
            .or_insert_with(|| watch::channel(()).0)
            .subscribe();
        ThreadMetadataSignal {
            receiver: Some(receiver),
            index: Arc::downgrade(&self.thread_index),
            thread_id: thread_id.to_owned(),
        }
    }

    #[cfg(test)]
    pub(crate) fn metadata_signal_count(&self) -> usize {
        self.thread_index.lock().unwrap().metadata_signals.len()
    }

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
        let frame = self
            .read_threads_window_inner(query, window, owner_epoch)?
            .into_frame();
        Self::check_frame_size(&frame)?;
        Ok(frame)
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
            query,
            window: window.clone(),
            stamp: ResourceStamp {
                resource_key: THREAD_DIRECTORY_RESOURCE_KEY.into(),
                owner_epoch: owner_epoch.into(),
                revision,
            },
            rows,
            next_cursor,
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
        #[cfg(test)]
        tests::pause(&self.directory_test_pauses.page_captured).await;
        let page = StudioThreadDirectoryPage {
            state: pl_protocol::ObservedResource::ready(
                read.stamp.revision,
                read.updated_at,
                StudioThreadDirectoryPageData {
                    rows: read.rows,
                    next_cursor: read.next_cursor,
                },
            ),
        };
        Self::check_frame_size(&page)?;
        Ok(page)
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
            if let Some(agent) = index.agent_by_thread(id) {
                let agent_id = agent.agent_id.clone();
                index.remove_agent(&agent_id);
            }
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
            let agent = index
                .get_agent(&row.agent_id)
                .expect("explicit close retains its directory agent");
            if let Some(current) = agent.native_status() {
                *status = crate::studio::agent_close::directory_status(current, true);
            }
        }
    }

    fn apply_explicit_close_agent(index: &ThreadDirectoryIndex, agent: &mut AgentDirectoryRecord) {
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
        agent.explicitly_closed = true;
        agent.set_native_status(if execution_closed {
            ThreadStatus::Closed
        } else {
            ThreadStatus::Closing
        });
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

#[cfg(test)]
pub(super) mod tests {
    use super::*;
    use crate::studio::StudioStore;
    use crate::studio::agent_host::ThreadWriteBehindWriter;
    use crate::studio::records::{AgentDirectoryRecord, SessionDirectoryRecord, row_projection};
    use crate::studio::store::directory::ProjectDirectoryRecord;
    use std::sync::Mutex;
    use tokio::sync::oneshot;

    type PauseSlot = Mutex<Option<(oneshot::Sender<()>, oneshot::Receiver<()>)>>;

    #[derive(Default)]
    pub(in crate::studio::product_event_bus) struct DirectoryTestPauses {
        pub(super) commit_before_persist: PauseSlot,
        pub(super) commit_persisted: PauseSlot,
        pub(super) page_captured: PauseSlot,
    }

    pub(super) async fn pause(slot: &PauseSlot) {
        let checkpoint = slot.lock().unwrap().take();
        if let Some((entered, release)) = checkpoint {
            entered.send(()).unwrap();
            release.await.unwrap();
        }
    }

    pub(super) fn install_pause(slot: &PauseSlot) -> (oneshot::Receiver<()>, oneshot::Sender<()>) {
        let (entered, reached) = oneshot::channel();
        let (release, released) = oneshot::channel();
        assert!(slot.lock().unwrap().replace((entered, released)).is_none());
        (reached, release)
    }

    /// root 目录行：`session_id == agent_id == thread_id`，排序键取 `sort_time`。
    pub(super) fn row(id: &str, workspace_id: &str, sort_time: i64) -> SessionDirectoryRow {
        SessionDirectoryRow {
            session_id: id.into(),
            agent_id: id.into(),
            parent_agent_id: None,
            thread_id: id.into(),
            workspace_id: workspace_id.into(),
            title: format!("Thread {id}"),
            mode: Some(pl_protocol::ThreadModeId::simple()),
            workspace_mode: pl_protocol::ThreadWorkspaceMode::Local,
            delegation_mode: Default::default(),
            delegation_preference: Default::default(),
            workspace_path: format!("/tmp/{id}"),
            role: crate::config::ROOT_AGENT_ROUTE_KEY.into(),
            backend: pl_protocol::session::AgentBackend::Native {
                config: pl_protocol::NativeAgentConfig {
                    route: None,
                    system_instructions: None,
                },
                status: pl_protocol::ThreadStatus::Idle,
            },
            created_at: sort_time,
            updated_at: sort_time,
            last_user_message_at: Some(sort_time),
            archived: false,
        }
    }

    /// 从 root/child 目录行拆出持久化的会话与成员事实（与 owner 的 `index_insert_row`
    /// 拆分方向一致：会话级事实只随 root 行建立）。
    pub(super) fn session_from_row(row: &SessionDirectoryRow) -> SessionDirectoryRecord {
        SessionDirectoryRecord {
            session_id: row.session_id.clone(),
            root_agent_id: row.agent_id.clone(),
            workspace_id: row.workspace_id.clone(),
            title: row.title.clone(),
            native_mode: row.mode.clone(),
            workspace_mode: row.workspace_mode,
            delegation_mode: row.delegation_mode,
            delegation_preference: row.delegation_preference,
            workspace_path: row.workspace_path.clone(),
            created_at: row.created_at,
            updated_at: row.updated_at,
            last_user_message_at: row.last_user_message_at,
            archived: row.archived,
        }
    }

    pub(super) fn agent_from_row(row: &SessionDirectoryRow) -> AgentDirectoryRecord {
        AgentDirectoryRecord {
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
        }
    }

    pub(super) fn set_status(row: &mut SessionDirectoryRow, next: pl_protocol::ThreadStatus) {
        let pl_protocol::session::AgentBackend::Native { status, .. } = &mut row.backend else {
            panic!("Native fixture required");
        };
        *status = next;
    }

    pub(super) async fn fixture(
        rows: Vec<SessionDirectoryRow>,
        projects: Vec<ProjectDirectoryRecord>,
    ) -> Result<(tempfile::TempDir, ProductEventBus)> {
        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        if !rows.is_empty() || !projects.is_empty() {
            let mut sessions = Vec::new();
            let mut agents = Vec::new();
            for row in rows {
                if row.is_root_row() {
                    sessions.push(session_from_row(&row));
                }
                agents.push(agent_from_row(&row));
            }
            store
                .persist_directory_summaries(&DirectoryDelta {
                    project_upserts: projects,
                    session_upserts: sessions,
                    agent_upserts: agents,
                    ..Default::default()
                })
                .await?;
        }
        let writer = ThreadWriteBehindWriter::new(store.clone());
        let events = ProductEventBus::new(store, writer);
        events.initialize_directories().await?;
        Ok((temp, events))
    }

    pub(super) fn project(id: &str, name: &str, path: &str) -> ProjectDirectoryRecord {
        ProjectDirectoryRecord {
            id: id.into(),
            kind: pl_protocol::studio::WorkspaceKind::Project,
            name: name.into(),
            path: path.into(),
            ssh_alias: None,
            created_at: 1,
            updated_at: 1,
            last_opened_at: None,
            closed: false,
        }
    }

    pub(super) fn workspace(project: &ProjectDirectoryRecord) -> crate::WorkspaceRecord {
        crate::WorkspaceRecord {
            id: project.id.clone(),
            kind: project.kind,
            name: project.name.clone(),
            path: project.path.clone(),
            ssh_alias: project.ssh_alias.clone(),
            updated_at: project.updated_at,
        }
    }

    pub(super) fn query(
        events: &ProductEventBus,
        query: &ThreadDirectoryQuery,
        before: Option<String>,
        limit: u32,
    ) -> Result<DirectoryRead> {
        events.read_threads_window_inner(
            query,
            &ThreadDirectoryWindow { before, limit },
            "owner-test",
        )
    }

    pub(super) fn event_delta(event: StudioProductEventEnvelope) -> StudioThreadDirectoryDelta {
        let StudioProductEventKind::ThreadDirectoryChanged(delta) = event.kind else {
            panic!("expected a thread directory event");
        };
        delta
    }

    mod commit {
        use super::*;
        use futures::poll;

        #[tokio::test]
        async fn typed_session_archive_and_delete_use_thread_references_without_resurrection()
        -> Result<()> {
            let mut root = row("root-thread", "p1", 10);
            // Native physical history retains its original root Thread bytes in S1.
            root.session_id = root.thread_id.clone();
            root.agent_id = "root-agent".into();
            let mut child = row("child-thread", "p1", 11);
            child.session_id = root.session_id.clone();
            child.agent_id = "child-agent".into();
            child.parent_agent_id = Some(root.agent_id.clone());
            let (_temp, events) = fixture(
                vec![root.clone(), child.clone()],
                vec![project("p1", "Project", "/workspace/project")],
            )
            .await?;
            let archived = event_delta(
                events
                    .commit_directory(DirectoryDelta::archive_sessions(vec![
                        root.session_id.clone(),
                    ]))
                    .await?,
            );
            assert_eq!(
                archived.removed.into_iter().collect::<BTreeSet<_>>(),
                BTreeSet::from([root.thread_id.clone(), child.thread_id.clone()])
            );
            assert!(
                query(&events, &ThreadDirectoryQuery::default(), None, 10)?
                    .rows
                    .is_empty()
            );
            // This unit isolates directory publication, not the lifecycle deletion journal. Settle the
            // preceding archive first; real delete_thread installs its durable replay fence before removal.
            events.writer.flush().await?;
            events
                .commit_directory(DirectoryDelta::delete_threads(vec![
                    child.thread_id.clone(),
                    root.thread_id.clone(),
                ]))
                .await?;
            // A late observation cannot recreate either member or its now-absent session.
            events.publish_thread_delta(vec![root.clone(), child], vec![], vec![root]);
            assert!(events.store.catalog().sessions().is_empty());
            assert!(events.store.catalog().agents().is_empty());
            assert!(events.thread_index.lock().unwrap().sessions.is_empty());
            events.writer.shutdown().await?;
            Ok(())
        }

        #[tokio::test]
        async fn durable_first_commit_keeps_old_slice_readable_then_publishes_one_new_slice()
        -> Result<()> {
            let original_project = project("p1", "Before Project", "/workspace/project");
            let original = row("existing", "p1", 10);
            let (_temp, events) =
                fixture(vec![original.clone()], vec![original_project.clone()]).await?;
            let before = query(&events, &ThreadDirectoryQuery::default(), None, 10)?;
            let (baseline_session, baseline_agent) =
                events.directory_facts(&original.thread_id).expect("facts");
            let (before_persist, release_persist) =
                install_pause(&events.directory_test_pauses.commit_before_persist);
            let (persisted, release_publish) =
                install_pause(&events.directory_test_pauses.commit_persisted);

            let mut stale_session = baseline_session.clone();
            stale_session.title = "Durable command title".into();
            let new_row = row("new", "p1", 20);
            let new_session = session_from_row(&new_row);
            let new_agent = agent_from_row(&new_row);
            let mut renamed_project = original_project;
            renamed_project.name = "After Project".into();
            renamed_project.updated_at = 2;
            let commit = events.commit_directory_with_bases(
                DirectoryDelta {
                    project_upserts: vec![renamed_project],
                    session_upserts: vec![stale_session, new_session],
                    agent_upserts: vec![baseline_agent.clone(), new_agent],
                    ..Default::default()
                },
                {
                    let mut bases = DirectoryBaselines::default();
                    bases
                        .sessions
                        .insert(baseline_session.session_id.clone(), baseline_session);
                    bases
                        .agents
                        .insert(baseline_agent.agent_id.clone(), baseline_agent);
                    bases
                },
            );
            tokio::pin!(commit);
            assert!(poll!(commit.as_mut()).is_pending());
            before_persist.await?;

            // No metadata lock is held across persistence: synchronous readers return the old slice.
            assert!(events.thread_index.try_lock().is_ok());
            let during_before_persist = query(&events, &ThreadDirectoryQuery::default(), None, 10)?;
            assert_eq!(during_before_persist.rows, before.rows);
            assert_eq!(during_before_persist.stamp, before.stamp);
            assert!(
                query(
                    &events,
                    &ThreadDirectoryQuery {
                        search: Some("after project".into()),
                        ..Default::default()
                    },
                    None,
                    10,
                )?
                .rows
                .is_empty()
            );
            let query_filter = ThreadDirectoryQuery::default();
            let readable = events.query_threads(&query_filter, None, 10).await?;
            assert_eq!(readable.state.value().unwrap().rows, before.rows);

            release_persist.send(()).unwrap();
            tokio::select! {
                result = &mut commit => panic!("commit published before persisted checkpoint: {result:?}"),
                result = persisted => result?,
            }
            let readable = events.query_threads(&query_filter, None, 10).await?;
            assert_eq!(readable.state.value().unwrap().rows, before.rows);
            // The catalog write has completed, but the only query owner still exposes the previous slice.
            assert!(
                events
                    .store
                    .catalog()
                    .get_agent(&new_row.agent_id)
                    .is_some()
            );
            assert_eq!(
                query(&events, &ThreadDirectoryQuery::default(), None, 10)?.rows,
                before.rows
            );

            // A later hot mutation may publish while the durable command is paused. Completion must not
            // write the command's stale copy back over this newer visible metadata.
            events
                .patch_thread_runtime(
                    &original.thread_id,
                    pl_protocol::ThreadStatus::Running,
                    30,
                    &pl_core::thread::ThreadSnapshot::default(),
                )?
                .unwrap();
            let hot = events.read_thread_metadata(&original.thread_id, "owner-test")?;
            assert_eq!(
                hot.row.as_ref().unwrap().native_status().unwrap(),
                pl_protocol::ThreadStatus::Running
            );
            assert!(
                events
                    .read_thread_metadata(&new_row.thread_id, "owner-test")?
                    .row
                    .is_none()
            );

            release_publish.send(()).unwrap();
            commit.await?;
            let after = query(&events, &ThreadDirectoryQuery::default(), None, 10)?;
            let unblocked = events.query_threads(&query_filter, None, 10).await?;
            assert_eq!(unblocked.state.revision(), after.stamp.revision);
            assert_eq!(
                unblocked
                    .state
                    .value()
                    .unwrap()
                    .rows
                    .iter()
                    .map(|row| row.thread_id.as_str())
                    .collect::<Vec<_>>(),
                vec!["new", "existing"]
            );
            assert_eq!(
                after
                    .rows
                    .iter()
                    .map(|row| row.thread_id.as_str())
                    .collect::<Vec<_>>(),
                vec!["new", "existing"]
            );
            assert_eq!(
                after.stamp,
                events
                    .read_thread_metadata(&original.thread_id, "owner-test")?
                    .stamp
            );
            let rebased = events
                .read_thread_metadata(&original.thread_id, "owner-test")?
                .row
                .unwrap();
            assert_eq!(rebased.title, "Durable command title");
            assert_eq!(
                rebased.native_status().unwrap(),
                pl_protocol::ThreadStatus::Running
            );
            assert!(after.stamp.revision > hot.stamp.revision);
            assert_eq!(
                query(
                    &events,
                    &ThreadDirectoryQuery {
                        search: Some("after project".into()),
                        ..Default::default()
                    },
                    None,
                    10,
                )?
                .rows
                .len(),
                2
            );
            events.writer.flush().await?;
            let durable_session = events
                .store
                .catalog()
                .get_session(&original.session_id)
                .expect("rebased session is durable");
            assert_eq!(durable_session.title, "Durable command title");
            let durable_agent = events
                .store
                .catalog()
                .get_agent(&original.agent_id)
                .expect("rebased agent is durable");
            assert_eq!(
                durable_agent.native_status().unwrap(),
                pl_protocol::ThreadStatus::Running
            );
            events.writer.shutdown().await?;
            Ok(())
        }

        #[tokio::test]
        async fn failed_durable_commit_never_changes_the_ram_owner() -> Result<()> {
            let original = row("existing", "p1", 10);
            let (_temp, events) = fixture(
                vec![original.clone()],
                vec![project("p1", "Project", "/workspace/project")],
            )
            .await?;
            let before = query(&events, &ThreadDirectoryQuery::default(), None, 10)?;
            let (baseline_session, _) = events.directory_facts(&original.thread_id).expect("facts");
            let mut conflicting = baseline_session;
            conflicting.workspace_path = "/conflicting/session/identity".into();
            let result = events
                .commit_directory(DirectoryDelta {
                    session_upserts: vec![conflicting],
                    ..Default::default()
                })
                .await;
            assert!(result.is_err());
            let after = query(&events, &ThreadDirectoryQuery::default(), None, 10)?;
            assert_eq!(after.rows, before.rows);
            assert_eq!(after.stamp, before.stamp);
            events.writer.shutdown().await?;
            Ok(())
        }
    }

    mod consistency {
        use super::*;
        use futures::poll;

        #[tokio::test]
        async fn one_shot_page_returns_its_consistent_slice_without_waiting_for_quiet() -> Result<()>
        {
            let existing = row("existing", "p1", 10);
            let (_temp, events) = fixture(
                vec![existing],
                vec![project("p1", "Project", "/workspace/project")],
            )
            .await?;
            let (captured, release) = install_pause(&events.directory_test_pauses.page_captured);
            let page = events.read_thread_directory_page(None, 10);
            tokio::pin!(page);
            assert!(poll!(page.as_mut()).is_pending());
            captured.await?;

            events.record_user_message("existing", 20);
            release.send(()).unwrap();
            let captured = page.await?;
            let current = events.read_thread_directory_page(None, 10).await?;
            assert!(current.state.revision() > captured.state.revision());
            assert_eq!(
                captured.state.value().unwrap().rows[0].last_user_message_at,
                Some(10)
            );
            assert_eq!(
                current.state.value().unwrap().rows[0].last_user_message_at,
                Some(20)
            );

            events.writer.shutdown().await?;
            Ok(())
        }

        #[tokio::test]
        async fn legacy_page_matches_the_owner_snapshot_without_concurrency() -> Result<()> {
            let rows = vec![row("newer", "p1", 20), row("older", "p1", 10)];
            let (_temp, events) =
                fixture(rows, vec![project("p1", "Project", "/workspace/project")]).await?;

            let owner = events.read_thread_directory().await?;
            let page = events.read_thread_directory_page(None, 10).await?;
            assert_eq!(page.state.revision(), owner.state.revision());
            assert_eq!(page.state.updated_at(), owner.state.updated_at());
            assert_eq!(
                page.state.value().unwrap().rows,
                owner.state.value().unwrap().rows
            );

            events.writer.shutdown().await?;
            Ok(())
        }
    }

    mod contention {
        use super::*;
        use crate::studio::store::agent_close::AgentCloseRecord;
        use futures::poll;
        use pl_tool::collaboration::control::AgentWorktreeCleanup;

        #[tokio::test]
        async fn hot_patch_and_query_do_not_wait_for_the_catalog_write_lock() -> Result<()> {
            let (_temp, events) = fixture(
                vec![row("root", "p1", 1)],
                vec![project("p1", "Project", "/workspace/project")],
            )
            .await?;
            let catalog = events.store.catalog().clone();
            let (entered, acquired) = std::sync::mpsc::channel();
            let (release, released) = std::sync::mpsc::channel();
            let holder = std::thread::spawn(move || {
                let _document = catalog.test_hold_document();
                entered.send(()).unwrap();
                released.recv().unwrap();
            });
            acquired.recv()?;
            let worker_events = events.clone();
            let runtime = tokio::runtime::Handle::current();
            let (completed, result) = std::sync::mpsc::channel();
            let worker = std::thread::spawn(move || {
                let _runtime = runtime.enter();
                let value = (|| -> Result<ThreadMetadataFrame> {
                    worker_events.patch_thread_runtime(
                        "root",
                        pl_protocol::ThreadStatus::Running,
                        2,
                        &pl_core::thread::ThreadSnapshot::default(),
                    )?;
                    worker_events.read_thread_metadata("root", "contention-test")
                })();
                completed.send(value).unwrap();
            });
            // Release and join even on a regression, rather than leaking blocked workers.
            let result = result.recv_timeout(std::time::Duration::from_secs(2));
            release.send(())?;
            holder.join().unwrap();
            worker.join().unwrap();
            let frame = result.expect("metadata must not wait for the Catalog I/O lock")?;
            assert_eq!(
                frame.row.unwrap().native_status().unwrap(),
                pl_protocol::ThreadStatus::Running
            );
            events.writer.shutdown().await?;
            Ok(())
        }

        #[tokio::test]
        async fn update_uses_the_request_baseline_not_a_later_runtime_row() -> Result<()> {
            let baseline_row = row("root", "p1", 1);
            let (_temp, events) = fixture(
                vec![baseline_row.clone()],
                vec![project("p1", "Project", "/workspace/project")],
            )
            .await?;
            // The frozen baseline is read before the commit call, as can happen while canceling an
            // auto-title task.
            let (baseline_session, _) = events
                .directory_facts(&baseline_row.thread_id)
                .expect("facts");
            let mut requested = baseline_session.clone();
            requested.title = "Manual title".into();
            events.patch_thread_runtime(
                "root",
                pl_protocol::ThreadStatus::Running,
                2,
                &pl_core::thread::ThreadSnapshot::default(),
            )?;
            events
                .commit_session_update(baseline_session, requested)
                .await?;
            events
                .commit_observed_thread_mode("root", pl_protocol::ThreadModeId::task(), 3)
                .await?;
            let row = events
                .read_thread_metadata("root", "request-base")?
                .row
                .unwrap();
            assert_eq!(row.title, "Manual title");
            assert_eq!(
                row.native_status().unwrap(),
                pl_protocol::ThreadStatus::Running
            );
            assert_eq!(row.mode, Some(pl_protocol::ThreadModeId::task()));
            events.writer.flush().await?;
            let session = events.store.catalog().get_session("root").unwrap();
            let agent = events.store.catalog().get_agent("root").unwrap();
            assert_eq!(session.title, row.title);
            assert_eq!(agent.native_status(), row.native_status());
            assert_eq!(session.native_mode, row.mode);
            events.writer.shutdown().await?;
            Ok(())
        }

        #[tokio::test]
        async fn explicit_close_is_a_current_owner_fact_not_a_catalog_read_dependency() -> Result<()>
        {
            let root = row("root", "p1", 1);
            let mut child = row("child", "p1", 2);
            child.agent_id = "child-agent".into();
            child.session_id = root.session_id.clone();
            child.parent_agent_id = Some(root.agent_id.clone());
            child.last_user_message_at = None;
            let (_temp, events) = fixture(
                vec![root, child],
                vec![project("p1", "Project", "/workspace/project")],
            )
            .await?;
            let missing = events.commit_explicit_close("child").await.unwrap_err();
            assert!(format!("{missing:#}").contains("close progress requires its durable intent"));
            let mut close = AgentCloseRecord {
                agent_id: "child".into(),
                parent_id: "root".into(),
                root_id: "root".into(),
                workspace_id: "p1".into(),
                revision: 1,
                force: false,
                worktree: None,
                git: None,
                execution_closed: false,
                worktree_cleanup: AgentWorktreeCleanup::Pending,
                error: None,
            };
            // save_agent_close validates the real persisted domain fact and its owner.
            events.store.save_agent_close(&close).await?;
            events.commit_explicit_close("child").await?;
            events.patch_thread_runtime(
                "child",
                pl_protocol::ThreadStatus::Running,
                3,
                &pl_core::thread::ThreadSnapshot::default(),
            )?;
            let (_, baseline_agent) = events.directory_facts("child").expect("facts");
            assert_eq!(
                baseline_agent.native_status().unwrap(),
                pl_protocol::ThreadStatus::Closing
            );
            let mut closed_agent = baseline_agent.clone();
            closed_agent.set_native_status(pl_protocol::ThreadStatus::Closed);
            let (saving, release_save) =
                install_pause(&events.directory_test_pauses.commit_before_persist);
            let mut bases = DirectoryBaselines::default();
            bases
                .agents
                .insert(baseline_agent.agent_id.clone(), baseline_agent);
            let commit = events.commit_directory_with_bases(
                DirectoryDelta {
                    agent_upserts: vec![closed_agent],
                    ..Default::default()
                },
                bases,
            );
            tokio::pin!(commit);
            assert!(poll!(commit.as_mut()).is_pending());
            saving.await?;
            events.record_user_message("child", 4);
            assert!(
                events
                    .commit_observed_thread_mode("child", pl_protocol::ThreadModeId::task(), 5)
                    .await
                    .is_err()
            );
            events
                .commit_observed_thread_mode("root", pl_protocol::ThreadModeId::task(), 5)
                .await?;
            release_save.send(()).unwrap();
            commit.await?;
            let projected = events
                .read_thread_metadata("child", "close-projection")?
                .row
                .unwrap();
            assert_eq!(
                projected.native_status().unwrap(),
                pl_protocol::ThreadStatus::Closing,
                "a generic raw Closed candidate cannot acknowledge permanent execution closure"
            );
            assert_eq!(projected.updated_at, 3);
            assert_eq!(projected.mode, None);
            // 已受理用户消息的水位是会话级事实：成员行不携带，主成员行保留并发提交期间的值。
            let root_row = events
                .read_thread_metadata("root", "close-projection")?
                .row
                .unwrap();
            assert_eq!(root_row.last_user_message_at, Some(4));
            // Keep the ACK outside the original paused generic save above, preserving
            // its concurrent mode/message interleaving. A restore read before this lock
            // would still carry false, as the old bool-across-lock implementation did.
            let stale = events.store.agent_close("child").await?.unwrap();
            assert!(!stale.execution_closed);
            let directory_command = events.directory_commands.lock().await;
            let queued = events.commit_explicit_close("child");
            tokio::pin!(queued);
            assert!(
                poll!(queued.as_mut()).is_pending(),
                "the progress publication must wait for the original directory command lock"
            );
            close.execution_closed = true;
            close.changed()?;
            events.store.save_agent_close(&close).await?;
            assert_eq!(
                events.store.agent_close("child").await?,
                Some(close.clone())
            );
            drop(directory_command);
            queued.await?;
            let acknowledged = events
                .read_thread_metadata("child", "close-ack")?
                .row
                .unwrap();
            assert_eq!(
                acknowledged.native_status(),
                Some(pl_protocol::ThreadStatus::Closed)
            );
            assert_eq!(acknowledged.updated_at, 3);
            assert_eq!(acknowledged.mode, None);
            assert_eq!(
                events
                    .store
                    .catalog()
                    .get_agent("child-agent")
                    .unwrap()
                    .native_status(),
                Some(pl_protocol::ThreadStatus::Closed),
                "the queued publication must read the new true ACK, not its old false observation"
            );
            events.commit_explicit_close("child").await?;
            assert_eq!(
                events
                    .read_thread_metadata("child", "repeat-close-restore")?
                    .row
                    .unwrap()
                    .native_status(),
                Some(pl_protocol::ThreadStatus::Closed),
                "repeated close restoration must not regress the acknowledged stage"
            );
            events.patch_thread_runtime(
                "child",
                pl_protocol::ThreadStatus::Idle,
                6,
                &pl_core::thread::ThreadSnapshot::default(),
            )?;
            assert_eq!(
                events
                    .read_thread_metadata("child", "close-test")?
                    .row
                    .unwrap()
                    .native_status()
                    .unwrap(),
                pl_protocol::ThreadStatus::Closed
            );
            events.writer.shutdown().await?;
            let saved_agent = events.store.catalog().get_agent("child-agent").unwrap();
            assert!(saved_agent.explicitly_closed);
            assert_eq!(
                saved_agent.native_status().unwrap(),
                pl_protocol::ThreadStatus::Closed
            );
            assert_eq!(saved_agent.updated_at, 6);
            let saved_session = events.store.catalog().get_session("root").unwrap();
            assert_eq!(saved_session.last_user_message_at, Some(4));
            assert_eq!(
                saved_session.native_mode,
                Some(pl_protocol::ThreadModeId::task())
            );
            Ok(())
        }

        #[tokio::test]
        async fn acp_explicit_close_preserves_external_backend_and_distinct_member_identity()
        -> Result<()> {
            let root = row("root-thread", "p1", 1);
            let mut child = row("acp-thread", "p1", 2);
            child.session_id = root.session_id.clone();
            child.agent_id = "acp-agent".into();
            child.parent_agent_id = Some(root.agent_id.clone());
            child.mode = None;
            child.last_user_message_at = None;
            child.backend = pl_protocol::session::AgentBackend::Acp {
                reference: pl_protocol::session::AcpSessionReference {
                    account_id: "account".into(),
                    acp_session_id: "external-session".into(),
                    cwd: "/workspace/project".into(),
                },
            };
            let (_temp, events) = fixture(
                vec![root, child.clone()],
                vec![project("p1", "Project", "/workspace/project")],
            )
            .await?;
            let (_, stale_agent) = events.directory_facts("acp-thread").unwrap();
            let mut close = AgentCloseRecord {
                agent_id: child.thread_id.clone(),
                parent_id: "root-thread".into(),
                root_id: child.session_id.clone(),
                workspace_id: child.workspace_id.clone(),
                revision: 1,
                force: false,
                worktree: None,
                git: None,
                execution_closed: false,
                worktree_cleanup: AgentWorktreeCleanup::Pending,
                error: None,
            };
            for execution_closed in [false, true] {
                close.execution_closed = execution_closed;
                close.changed()?;
                events.store.save_agent_close(&close).await?;
                events.commit_explicit_close(&child.thread_id).await?;
                let mut updated = stale_agent.clone();
                updated.title = Some(format!(
                    "late title after execution_closed={execution_closed}"
                ));
                events
                    .commit_agent_update(stale_agent.clone(), updated)
                    .await?;
                let (_, agent) = events.directory_facts(&child.thread_id).unwrap();
                assert!(agent.explicitly_closed);
                assert_eq!(agent.backend, child.backend);
                let row = events
                    .read_thread_metadata(&child.thread_id, "acp-close")?
                    .row
                    .unwrap();
                assert_eq!(row.native_status(), None);
                assert_eq!(row.mode, None);
                assert_eq!(row.backend, child.backend);
                let error = events.thread_snapshot(&child.thread_id).unwrap_err();
                assert!(matches!(
                    error.downcast_ref::<crate::thread_assembler::ThreadAssemblyError>(),
                    Some(
                        crate::thread_assembler::ThreadAssemblyError::UnsupportedBackend {
                            backend: pl_protocol::AgentBackendKind::Acp
                        }
                    )
                ));
            }
            events.writer.shutdown().await?;
            let saved = events.store.catalog().get_agent("acp-agent").unwrap();
            assert!(saved.explicitly_closed);
            assert_eq!(saved.backend, child.backend);
            Ok(())
        }
    }

    mod hot {
        use super::*;

        #[derive(Clone, Copy, Debug)]
        enum HotMutation {
            Runtime,
            UserMessage,
            Delta,
            Observed,
        }

        async fn assert_serial_publication(mutation: HotMutation) -> Result<()> {
            let first = row("first", "p1", 1);
            let second = row("second", "p1", 2);
            let (_temp, events) = fixture(
                vec![first.clone(), second],
                vec![project("p1", "Project", "/workspace/project")],
            )
            .await?;
            let baseline_revision = query(&events, &ThreadDirectoryQuery::default(), None, 10)?
                .stamp
                .revision;
            let mut topic = events.subscribe_topic(&crate::StudioProductTopic::ThreadDirectory);
            let mut internal = events.subscribe_internal();
            let worker_events = events.clone();
            let runtime = tokio::runtime::Handle::current();
            let (first_event, second_event, held_index) = tokio::task::spawn_blocking(move || {
                // Stop the real final dispatch after internal.send. A second identity must not pass the
                // first mutation until its row, revision and topic dispatch all leave the index scope.
                let topics = worker_events.topics.lock().unwrap();
                std::thread::scope(|scope| {
                    let first_writer = scope.spawn(|| -> Result<()> {
                        let _runtime = runtime.enter();
                        match mutation {
                            HotMutation::Runtime => {
                                worker_events.patch_thread_runtime(
                                    "first",
                                    pl_protocol::ThreadStatus::Running,
                                    10,
                                    &pl_core::thread::ThreadSnapshot::default(),
                                )?;
                            }
                            HotMutation::UserMessage => {
                                worker_events.record_user_message("first", 10);
                            }
                            HotMutation::Delta => {
                                let mut first = first;
                                first.title = "New first title".into();
                                worker_events.publish_thread_delta(
                                    vec![first],
                                    Vec::new(),
                                    Vec::new(),
                                );
                            }
                            HotMutation::Observed => {
                                runtime.block_on(worker_events.commit_observed_thread_mode(
                                    &first.thread_id,
                                    pl_protocol::ThreadModeId::task(),
                                    10,
                                ))?;
                            }
                        }
                        Ok(())
                    });
                    let first_event = runtime.block_on(internal.recv()).unwrap();
                    let held_index = worker_events.thread_index.try_lock().is_err();
                    let (attempted, started) = std::sync::mpsc::sync_channel(0);
                    let runtime = &runtime;
                    let worker_events = &worker_events;
                    let second_writer = scope.spawn(move || {
                        let _runtime = runtime.enter();
                        attempted.send(()).unwrap();
                        worker_events.record_user_message("second", 20);
                    });
                    started.recv().unwrap();
                    drop(topics);
                    first_writer.join().unwrap().unwrap();
                    second_writer.join().unwrap();
                    let second_event = runtime.block_on(internal.recv()).unwrap();
                    (first_event, second_event, held_index)
                })
            })
            .await?;
            assert!(held_index, "{mutation:?} released index before dispatch");
            assert_eq!(topic.try_recv()?, first_event);
            assert_eq!(topic.try_recv()?, second_event);
            assert!(first_event.sequence < second_event.sequence);
            let first_delta = event_delta(first_event);
            let second_delta = event_delta(second_event);
            assert_eq!(first_delta.revision, baseline_revision + 1);
            assert_eq!(second_delta.revision, first_delta.revision + 1);
            assert_eq!(first_delta.upserted[0].thread_id, "first");
            assert_eq!(second_delta.upserted[0].thread_id, "second");
            assert_eq!(second_delta.upserted[0].last_user_message_at, Some(20));
            let frame = query(&events, &ThreadDirectoryQuery::default(), None, 10)?;
            assert_eq!(frame.stamp.revision, second_delta.revision);
            for row in frame.rows {
                let expected = if row.thread_id == "first" {
                    &first_delta.upserted[0]
                } else {
                    &second_delta.upserted[0]
                };
                assert_eq!(&row, expected);
            }
            events.writer.shutdown().await?;
            Ok(())
        }

        #[tokio::test]
        async fn runtime_patch_is_one_hot_watermark_and_dispatch_scope() -> Result<()> {
            assert_serial_publication(HotMutation::Runtime).await
        }

        #[tokio::test]
        async fn user_message_is_one_hot_watermark_and_dispatch_scope() -> Result<()> {
            assert_serial_publication(HotMutation::UserMessage).await
        }

        #[tokio::test]
        async fn directory_delta_is_one_hot_watermark_and_dispatch_scope() -> Result<()> {
            assert_serial_publication(HotMutation::Delta).await
        }

        #[tokio::test]
        async fn observed_commit_is_one_hot_watermark_and_dispatch_scope() -> Result<()> {
            assert_serial_publication(HotMutation::Observed).await
        }
    }

    mod window {
        use super::*;

        #[tokio::test]
        async fn fixed_pin_group_keeps_old_members_outside_the_ordinary_window() -> Result<()> {
            let rows = (0..30)
                .map(|n| row(&format!("row-{n:03}"), "p1", n))
                .collect();
            let (_temp, events) =
                fixture(rows, vec![project("p1", "Project", "/workspace/project")]).await?;
            let ids = vec!["row-001".into(), "row-000".into()];
            let pinned = ThreadDirectoryQuery {
                workspace_id: Some("p1".into()),
                thread_ids: Some(ids.clone()),
                ..Default::default()
            };
            let ordinary = ThreadDirectoryQuery {
                workspace_id: Some("p1".into()),
                excluded_thread_ids: ids,
                ..Default::default()
            };
            let pins = query(&events, &pinned, None, 64)?;
            assert_eq!(
                pins.rows
                    .iter()
                    .map(|row| row.thread_id.as_str())
                    .collect::<Vec<_>>(),
                ["row-001", "row-000"]
            );
            assert!(pins.next_cursor.is_none());
            let first = query(&events, &ordinary, None, 20)?;
            assert_eq!(first.rows.len(), 20);
            assert_eq!(first.rows.last().unwrap().thread_id, "row-010");
            let next = query(&events, &ordinary, first.next_cursor.clone(), 20)?;
            assert_eq!(next.rows.len(), 8);
            assert_eq!(next.rows.last().unwrap().thread_id, "row-002");
            assert!(next.next_cursor.is_none());
            assert!(
                query(
                    &events,
                    &ThreadDirectoryQuery {
                        thread_ids: Some(vec![]),
                        ..Default::default()
                    },
                    None,
                    20
                )?
                .rows
                .is_empty()
            );

            let running_pins = ThreadDirectoryQuery {
                filter: pl_protocol::studio::ThreadDirectoryFilter::Running,
                ..pinned
            };
            assert!(query(&events, &running_pins, None, 64)?.rows.is_empty());
            let mut updated = {
                let (session, agent) = events.directory_facts("row-000").unwrap();
                row_projection(&session, &agent)
            };
            updated.title = "Changed outside the ordinary window".into();
            set_status(&mut updated, pl_protocol::ThreadStatus::Running);
            events.apply_thread_delta(vec![updated], vec![]).await?;
            let changed = query(&events, &running_pins, None, 64)?;
            assert_eq!(changed.rows.len(), 1);
            assert_eq!(changed.rows[0].thread_id, "row-000");
            assert_eq!(changed.rows[0].title, "Changed outside the ordinary window");
            assert!(changed.stamp.revision > pins.stamp.revision);
            events.writer.shutdown().await?;
            Ok(())
        }
        use pl_protocol::studio::{StudioError, StudioErrorCode, ThreadDirectoryFilter};

        #[tokio::test]
        async fn startup_index_owns_cold_archived_and_child_metadata() -> Result<()> {
            let root = row("root", "p1", 3);
            let mut archived = row("archived", "p1", 2);
            archived.archived = true;
            let mut child = row("child", "p1", 1);
            child.session_id = root.session_id.clone();
            child.parent_agent_id = Some(root.agent_id.clone());
            child.mode = None;
            // 会话级事实（工作区路径、最近用户消息时间）只随主成员行携带。
            child.workspace_path = root.workspace_path.clone();
            child.last_user_message_at = None;
            let (_temp, events) = fixture(
                vec![root.clone(), archived.clone(), child.clone()],
                vec![project("p1", "Project", "/workspace/project")],
            )
            .await?;

            for expected in [&root, &archived, &child] {
                let frame = events.read_thread_metadata(&expected.thread_id, "owner-a")?;
                assert_eq!(frame.stamp.resource_key, THREAD_DIRECTORY_RESOURCE_KEY);
                assert_eq!(frame.stamp.owner_epoch, "owner-a");
                assert_eq!(frame.row.as_ref(), Some(expected));
            }
            assert!(
                events
                    .read_thread_metadata("missing", "owner-a")?
                    .row
                    .is_none()
            );
            assert_eq!(
                query(&events, &ThreadDirectoryQuery::default(), None, 10)?.rows,
                vec![root]
            );
            let archived_query = ThreadDirectoryQuery {
                archived: true,
                ..Default::default()
            };
            assert_eq!(
                query(&events, &archived_query, None, 10)?.rows,
                vec![archived]
            );
            events.writer.shutdown().await?;
            Ok(())
        }

        #[tokio::test]
        async fn limit_and_seek_return_complete_windows_with_bounded_materialization() -> Result<()>
        {
            let rows = (1..=6)
                .map(|value| row(&format!("t{value}"), "p1", value))
                .collect::<Vec<_>>();
            let (_temp, events) =
                fixture(rows, vec![project("p1", "Project", "/workspace/project")]).await?;
            let window = ThreadDirectoryWindow {
                before: None,
                limit: 2,
            };
            let first = events.read_threads_window_inner(
                &ThreadDirectoryQuery::default(),
                &window,
                "owner-a",
            )?;
            assert_eq!(
                first
                    .rows
                    .iter()
                    .map(|row| row.thread_id.as_str())
                    .collect::<Vec<_>>(),
                vec!["t6", "t5"]
            );
            assert_eq!(first.metrics.scanned, 3);
            assert_eq!(first.metrics.materialized, 3);
            let second = query(
                &events,
                &ThreadDirectoryQuery::default(),
                first.next_cursor,
                2,
            )?;
            assert_eq!(
                second
                    .rows
                    .iter()
                    .map(|row| row.thread_id.as_str())
                    .collect::<Vec<_>>(),
                vec!["t4", "t3"]
            );
            assert!(second.next_cursor.is_some());
            events.writer.shutdown().await?;
            Ok(())
        }

        #[tokio::test]
        async fn off_window_metadata_and_project_changes_recompute_membership_order_and_stamp()
        -> Result<()> {
            let p1 = project("p1", "Alpha", "/workspace/alpha");
            let p2 = project("p2", "Beta", "/workspace/beta");
            let a = row("a", "p1", 30);
            let b = row("b", "p1", 20);
            let c = row("c", "p1", 10);
            let (_temp, events) =
                fixture(vec![a.clone(), b.clone(), c.clone()], vec![p1, p2.clone()]).await?;
            let initial = query(&events, &ThreadDirectoryQuery::default(), None, 1)?;
            assert_eq!(initial.rows, vec![a]);

            let mut changed = c;
            changed.title = "Needle renamed".into();
            set_status(&mut changed, pl_protocol::ThreadStatus::Running);
            changed.workspace_id = "p2".into();
            changed.last_user_message_at = Some(40);
            changed.updated_at = 40;
            events
                .apply_thread_delta(vec![changed.clone()], Vec::new())
                .await?;
            let filtered = ThreadDirectoryQuery {
                workspace_id: Some("p2".into()),
                search: Some("needle".into()),
                filter: ThreadDirectoryFilter::Running,
                ..Default::default()
            };
            let after = query(&events, &filtered, None, 1)?;
            assert_eq!(after.rows, vec![changed.clone()]);
            assert!(after.stamp.revision > initial.stamp.revision);

            events
                .commit_directory(DirectoryDelta::archive_sessions(vec![
                    changed.session_id.clone(),
                ]))
                .await?;
            assert!(query(&events, &filtered, None, 1)?.rows.is_empty());
            let archived = ThreadDirectoryQuery {
                archived: true,
                workspace_id: Some("p2".into()),
                search: Some("needle".into()),
                filter: ThreadDirectoryFilter::Running,
                ..Default::default()
            };
            assert_eq!(query(&events, &archived, None, 1)?.rows[0].thread_id, "c");

            let mut renamed_project = p2;
            renamed_project.name = "Find Me Project".into();
            renamed_project.path = "/workspace/find-me".into();
            renamed_project.updated_at = 2;
            let before_project = query(&events, &ThreadDirectoryQuery::default(), None, 1)?.stamp;
            events
                .apply_project_delta(&[workspace(&renamed_project)], &[])
                .await?;
            let project_query = ThreadDirectoryQuery {
                search: Some("find me".into()),
                archived: true,
                ..Default::default()
            };
            let project_result = query(&events, &project_query, None, 10)?;
            assert_eq!(project_result.rows[0].thread_id, "c");
            assert!(project_result.stamp.revision > before_project.revision);
            events.writer.shutdown().await?;
            Ok(())
        }

        #[tokio::test]
        async fn invalid_window_cursor_and_oversized_frame_are_typed_failures() -> Result<()> {
            let mut oversized = row("large", "p1", 1);
            oversized.title = "x".repeat(ThreadDirectoryWindow::MAX_FRAME_BYTES);
            let (_temp, events) = fixture(
                vec![oversized],
                vec![project("p1", "Project", "/workspace/project")],
            )
            .await?;
            // Titles are not part of the structural delivery budget.
            let structure = events.read_threads_window(
                &ThreadDirectoryQuery::default(),
                &ThreadDirectoryWindow {
                    before: None,
                    limit: 1,
                },
                "owner-test",
            )?;
            assert_eq!(structure.thread_ids, ["large"]);
            let error = events
                .query_threads(&ThreadDirectoryQuery::default(), None, 1)
                .await
                .expect_err("oversized one-shot row page must fail");
            assert_eq!(
                error.downcast_ref::<StudioError>().unwrap().code,
                StudioErrorCode::Overloaded
            );
            let error = events
                .read_thread_metadata("large", "owner-test")
                .expect_err("oversized metadata frame must fail");
            assert_eq!(
                error.downcast_ref::<StudioError>().unwrap().code,
                StudioErrorCode::Overloaded
            );
            let error = query(
                &events,
                &ThreadDirectoryQuery::default(),
                Some("not-a-cursor".into()),
                1,
            )
            .expect_err("invalid cursor must fail");
            assert_eq!(
                error.downcast_ref::<StudioError>().unwrap().code,
                StudioErrorCode::InvalidArgument
            );
            events.writer.shutdown().await?;
            Ok(())
        }
    }
}

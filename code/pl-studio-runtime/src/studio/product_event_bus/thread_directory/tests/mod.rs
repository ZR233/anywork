use super::*;
use crate::studio::StudioStore;
use crate::studio::records::{AgentDirectoryRecord, SessionDirectoryRecord, row_projection};
use crate::studio::storage::write_behind::ThreadWriteBehindWriter;
use crate::studio::store::directory::ProjectDirectoryRecord;
use tokio::sync::oneshot;

type Checkpoint = (oneshot::Sender<()>, oneshot::Receiver<()>);

fn checkpoint() -> (oneshot::Receiver<()>, oneshot::Sender<()>, Checkpoint) {
    let (entered, reached) = oneshot::channel();
    let (release, released) = oneshot::channel();
    (reached, release, (entered, released))
}

async fn reach(checkpoint: Option<Checkpoint>) {
    if let Some((entered, release)) = checkpoint {
        entered.send(()).unwrap();
        release.await.unwrap();
    }
}

async fn commit_at_boundaries(
    events: &ProductEventBus,
    delta: DirectoryDelta,
    bases: DirectoryBaselines,
    before: Option<Checkpoint>,
    after: Option<Checkpoint>,
) -> Result<StudioProductEventEnvelope> {
    let _command = events.directory_commands.lock().await;
    reach(before).await;
    let saved = events.persist_directory_commit(delta, bases).await?;
    reach(after).await;
    events.publish_directory_commit(saved)
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
        mode: Some(crate::mode::ThreadModeId::auto()),
        workspace_mode: crate::ThreadWorkspaceMode::Local,
        delegation_mode: Default::default(),
        delegation_preference: Default::default(),
        workspace_path: format!("/tmp/{id}"),
        role: crate::config::ROOT_AGENT_ROUTE_KEY.into(),
        backend: crate::AgentBackend::Native {
            config: crate::NativeAgentConfig {
                route: None,
                system_instructions: None,
            },
            status: crate::ThreadStatus::Idle,
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
        acp_title: matches!(&row.backend, crate::AgentBackend::Acp { .. }).then_some(
            AcpDirectoryTitle {
                label: AcpTitleLabel::Legacy,
                peer: None,
            },
        ),
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

pub(super) fn set_status(row: &mut SessionDirectoryRow, next: crate::ThreadStatus) {
    let crate::AgentBackend::Native { status, .. } = &mut row.backend else {
        panic!("Native fixture required");
    };
    *status = next;
}

pub(in crate::studio::product_event_bus) async fn fixture(
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

pub(in crate::studio::product_event_bus) fn project(
    id: &str,
    name: &str,
    path: &str,
) -> ProjectDirectoryRecord {
    ProjectDirectoryRecord {
        id: id.into(),
        kind: crate::WorkspaceKind::Project,
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
    crate::WorkspaceRecord::from(project)
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

mod agent_directory;

mod commit;

mod consistency;

mod contention;

mod hot;

mod window;

mod agent_publication;
mod index;

impl ProductEventBus {
    /// Publishes one metadata wake. Idle registrations are reclaimed here, matching topic notify.
    pub(crate) fn notify_thread_metadata_for_test(&self, thread_id: &str) {
        let mut index = self
            .thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        index.metadata_signals.wake(thread_id);
    }

    pub(crate) fn metadata_signal_count(&self) -> usize {
        self.thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .metadata_signals
            .len()
    }

    /// 应用一次目录增量并发布 `ThreadDirectoryChanged` 事件（纯内存维护）。
    pub(crate) async fn apply_thread_delta(
        &self,
        upserted: Vec<SessionDirectoryRow>,
        removed: Vec<String>,
    ) -> Result<StudioProductEventEnvelope> {
        Ok(self.publish_thread_delta(upserted, removed, Vec::new()))
    }

    pub(super) fn publish_thread_delta(
        &self,
        upserted: Vec<SessionDirectoryRow>,
        removed: Vec<String>,
        archived: Vec<SessionDirectoryRow>,
    ) -> StudioProductEventEnvelope {
        let mut index = self
            .thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.publish_thread_delta_locked(&mut index, upserted, removed, archived)
    }

    pub(super) fn publish_thread_delta_locked(
        &self,
        index: &mut ThreadDirectoryIndex,
        mut upserted: Vec<SessionDirectoryRow>,
        removed: Vec<String>,
        archived: Vec<SessionDirectoryRow>,
    ) -> StudioProductEventEnvelope {
        let before_agents = index.agent_directory_members(
            index
                .agent_to_session
                .keys()
                .cloned()
                .chain(upserted.iter().map(|row| row.agent_id.clone())),
        );
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
        self.publish_agent_directory_locked(index, before_agents);
        // State and tombstones are visible before observers receive removal.
        self.emit_thread_delta_locked(index, upserted, removed)
    }

    /// 把行投影拆回会话/成员事实写入索引。
    pub(super) fn index_insert_row(index: &mut ThreadDirectoryIndex, row: SessionDirectoryRow) {
        if index.deleted.contains(&row.thread_id)
            || index.deleted_sessions.contains(&row.session_id)
        {
            return;
        }
        let existing = index.get_session(&row.session_id);
        let acp_title = existing.and_then(|session| session.acp_title.clone());
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
            // Projected rows carry the visible value, not the underlying ACP label.
            title: match existing {
                Some(session) if acp_title.is_some() || !row.is_root_row() => session.title.clone(),
                _ if row.is_root_row() => row.title.clone(),
                _ => String::new(),
            },
            acp_title,
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
        let mut agent = AgentDirectoryRecord {
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
        Self::apply_explicit_close_agent(index, &mut agent);
        index.insert_agent(agent);
    }

    pub(super) fn apply_explicit_close_row(
        index: &ThreadDirectoryIndex,
        row: &mut SessionDirectoryRow,
    ) {
        if index.explicitly_closed.contains(&row.agent_id)
            && let crate::AgentBackend::Native { status, .. } = &mut row.backend
        {
            let agent = index
                .get_agent(&row.agent_id)
                .expect("explicit close retains its directory agent");
            if let Some(current) = agent.native_status() {
                *status = crate::studio::agent_close::directory_status(current, true);
            }
        }
    }
}

use super::*;
use crate::studio::StudioStore;
use crate::studio::agent_host::ThreadWriteBehindWriter;
use crate::studio::records::{AgentDirectoryRecord, SessionDirectoryRecord, row_projection};
use crate::studio::store::directory::ProjectDirectoryRecord;
use std::sync::Mutex;
use tokio::sync::oneshot;

mod commit;
mod consistency;
mod contention;
mod hot;
mod window;

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

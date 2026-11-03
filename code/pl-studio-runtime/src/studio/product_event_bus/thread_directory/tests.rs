use super::*;
use crate::studio::StudioStore;
use crate::studio::agent_host::ThreadWriteBehindWriter;
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

pub(super) async fn fixture(
    threads: Vec<Thread>,
    projects: Vec<ProjectDirectoryRecord>,
) -> Result<(tempfile::TempDir, ProductEventBus)> {
    let temp = tempfile::tempdir()?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    if !threads.is_empty() || !projects.is_empty() {
        store
            .persist_directory_summaries(&DirectoryDelta {
                project_upserts: projects,
                thread_upserts: threads,
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

pub(super) fn thread(id: &str, workspace_id: &str, sort_time: i64) -> Thread {
    let mut thread = Thread::placeholder(id);
    thread.workspace_id = workspace_id.into();
    thread.root_thread_id = id.into();
    thread.agent_path = id.into();
    thread.title = format!("Thread {id}");
    thread.created_at = sort_time;
    thread.updated_at = sort_time;
    thread.last_user_message_at = Some(sort_time);
    thread
}

pub(super) fn query(
    events: &ProductEventBus,
    query: &ThreadDirectoryQuery,
    before: Option<String>,
    limit: u32,
) -> Result<ThreadDirectoryFrame> {
    events.read_threads_window(
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

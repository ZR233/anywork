//! The original private owner may stop for deletion without a successful preservation receipt.
use super::*;
use crate::studio::store::thread_preparation::{PreparationBinding, PreparationSave};
use pl_core::thread::cold::{ColdStore, ColdStoreError, StoragePressure, ThreadWrite};
use std::sync::{
    Arc,
    atomic::{AtomicBool, AtomicUsize, Ordering},
};

#[derive(Debug)]
struct PrivateFlushFailure {
    sink: ThreadStorageSink,
    closing: Arc<AtomicBool>,
    flushes: Arc<AtomicUsize>,
}

impl ColdStore for PrivateFlushFailure {
    fn pressure(&self, id: &str) -> StoragePressure {
        self.sink.pressure(id)
    }
    fn admit(&self, id: &str, write: ThreadWrite) -> std::result::Result<(), ColdStoreError> {
        if write.checkpoint.state.lifecycle == pl_core::thread::ThreadLifecycle::Closed {
            self.closing.store(true, Ordering::SeqCst);
        }
        self.sink.admit(id, write)
    }
    async fn flush(&self, id: &str, sequence: u64) -> std::result::Result<(), ColdStoreError> {
        self.flushes.fetch_add(1, Ordering::SeqCst);
        self.sink.flush(id, sequence).await?;
        if self.closing.load(Ordering::SeqCst) {
            return Err(ColdStoreError {
                source: Box::new(std::io::Error::other("private original save ACK failed")),
            });
        }
        Ok(())
    }
}

#[tokio::test]
async fn permanent_delete_private_required_save_records_real_stop_without_save_ack() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let _endpoint = configure(&home)?;
    let workspace = temp.path().join("workspace");
    tokio::fs::create_dir_all(&workspace).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let project = runtime.open_project(&workspace).await?;
    let root = runtime
        .create_thread_with_id("delete-private-root", &project.id, "root")
        .await?;
    runtime.ensure_thread_owner(&root.id).await?.flush().await?;
    let id = "delete-private-required";
    let mut private = pl_protocol::Thread::placeholder(id);
    private.workspace_id = project.id.clone();
    private.workspace_path = workspace.to_string_lossy().into_owned();
    private.root_thread_id = root.id.clone();
    private.parent_thread_id = Some(root.id.clone());
    let (_, agent) = crate::studio::records::directory_facts_from_thread(&private);
    runtime
        .agent_facility
        .product_events
        .commit_directory(DirectoryDelta {
            agent_upserts: vec![agent],
            ..Default::default()
        })
        .await?;
    runtime
        .store
        .begin_thread_preparation(PreparationIdentity {
            thread_id: id.into(),
            workspace_id: project.id.clone(),
            parent_id: Some(root.id.clone()),
            root_id: root.id.clone(),
        })
        .await?;
    let binding = WorkspaceIdentity::canonical(
        WorkspaceEndpoint::Local,
        dunce::canonicalize(&workspace)?
            .to_string_lossy()
            .into_owned(),
    )?;
    runtime.store.bind_thread_preparation(id, &binding).await?;
    let sink = ThreadStorageSink::new(runtime.store.clone(), private, None).await?;
    let projection = spawn_live_projection_for_thread(runtime.store.clone(), id);
    let flushes = Arc::new(AtomicUsize::new(0));
    let mut spec =
        crate::thread_assembler::archive_test_spec(id.into(), Some(root.id.clone()), &workspace);
    spec.cold_store = Some(ColdStoreHandle::new(PrivateFlushFailure {
        sink,
        closing: Arc::new(AtomicBool::new(false)),
        flushes: flushes.clone(),
    }));
    spec.initial_extensions.insert(
        String::new(),
        pl_core::context::OpaquePayload::text("invalid initialization"),
    );
    assert!(
        runtime
            .session_for_roots(std::slice::from_ref(&root.id))?
            .assemble(spec)
            .await
            .is_err()
    );
    let record = runtime
        .store
        .thread_preparation(id)
        .await?
        .context("retained private owner")?;
    assert_eq!(record.save, PreparationSave::Required);
    assert!(!record.stopped);
    assert!(
        runtime
            .session_of(id)
            .and_then(|session| session.observed_thread(id))
            .is_some()
    );
    let before = flushes.load(Ordering::SeqCst);
    assert!(
        !workspace.join(SessionFiles::new(id).root()).exists(),
        "the first execution removal must also handle an absent bound session"
    );
    runtime
        .store
        .database()
        .execute_unprepared(
            "CREATE TRIGGER inspect_private_stop BEFORE UPDATE ON studio_objects
         WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='removing'
         BEGIN SELECT RAISE(ABORT,'inspect deletion stop without save'); END",
        )
        .await?;
    let error = tokio::time::timeout(
        std::time::Duration::from_secs(15),
        runtime.delete_thread("inspect-private".into(), root.id.clone()),
    )
    .await?
    .expect_err("inspect the retained stop ACK before physical deletion");
    ensure!(
        format!("{error:#}").contains("inspect deletion stop without save"),
        "{error:#}"
    );
    projection.await?;
    let stopped = runtime
        .store
        .thread_preparation(id)
        .await?
        .context("private stop ACK")?;
    assert!(stopped.stopped && stopped.retired && stopped.deletion_stopped);
    assert_eq!(stopped.save, PreparationSave::Required);
    assert!(stopped.storage.as_ref().unwrap().closed_receipt.is_none());
    assert_eq!(
        stopped.binding,
        PreparationBinding::Bound { identity: binding }
    );
    assert_eq!(
        flushes.load(Ordering::SeqCst),
        before,
        "deletion must never retry original flush"
    );
    assert!(
        runtime
            .session_of(id)
            .and_then(|session| session.observed_thread(id))
            .is_none()
    );
    runtime
        .store
        .database()
        .execute_unprepared("DROP TRIGGER inspect_private_stop")
        .await?;
    runtime
        .delete_thread("finish-private".into(), root.id)
        .await?
        .context("private deletion reply")?;
    assert!(runtime.store.thread_preparation(id).await?.is_none());
    runtime.shutdown_runtime().await?;
    Ok(())
}

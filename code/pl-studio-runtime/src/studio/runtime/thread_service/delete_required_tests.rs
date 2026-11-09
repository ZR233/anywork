//! The original private owner may stop for deletion without a successful preservation receipt.
use super::*;

#[tokio::test]
async fn permanent_delete_sealed_missing_public_member_retries_frozen_scope() -> Result<()> {
    use crate::studio::store::thread_archive::ArchiveScope;
    for missing_root in [false, true] {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home)?;
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let project = runtime.open_project(&workspace).await?;
        let root = runtime
            .create_thread_with_id("missing-public-root", &project.id, "root")
            .await?;
        let middle = cold_child(&runtime, &root.clone().into(), "missing-public-middle").await?;
        let leaf = cold_child(&runtime, &middle, "missing-public-leaf").await?;
        let neighbor = runtime
            .create_thread_with_id("missing-public-neighbor", &project.id, "keep")
            .await?;
        let binding = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::Local,
            dunce::canonicalize(&workspace)?
                .to_string_lossy()
                .into_owned(),
        )?;
        for id in [&root.id, &middle.id, &leaf.id, &neighbor.id] {
            runtime.store.bind_workspace_identity(id, &binding).await?;
            let execution = workspace.join(SessionFiles::new(id).root());
            tokio::fs::create_dir_all(&execution).await?;
            tokio::fs::write(execution.join("marker"), id).await?;
        }
        runtime.store.database().execute_unprepared(
            "CREATE TRIGGER pause_missing_public BEFORE UPDATE ON studio_objects
             WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='removing'
             BEGIN SELECT RAISE(ABORT,'pause sealed public deletion'); END"
        ).await?;
        let error = runtime
            .delete_thread("freeze-missing-public".into(), root.id.clone())
            .await
            .expect_err("retain a sealed deletion before physical cleanup");
        assert!(
            format!("{error:#}").contains("pause sealed public deletion"),
            "{error:#}"
        );
        let deletion = runtime.store.thread_delete(&root.id).await?.unwrap();
        assert_eq!(deletion.phase, DeletePhase::Sealed);
        let scope = ArchiveScope::Thread(root.id.clone());
        let frozen = runtime.store.thread_archive(&scope).await?.unwrap();
        assert_eq!(frozen.members.len(), 3);
        let tree = runtime.store.read_directory_tree(&root.id).await?;
        let mut extra = tree.clone();
        let mut unadmitted = tree[0].clone();
        unadmitted.id = "outside-sealed-scope".into();
        extra.push(unadmitted);
        assert!(
            runtime
                .freeze_thread_removal(scope.clone(), &extra, &[])
                .await
                .is_err()
        );
        assert!(
            runtime
                .store
                .thread_preparation("outside-sealed-scope")
                .await?
                .is_none()
        );
        for field in ["workspace", "root", "parent", "binding"] {
            let mut changed = tree.clone();
            let member = changed
                .iter_mut()
                .find(|thread| thread.id == middle.id)
                .unwrap();
            match field {
                "workspace" => member.workspace_id = "different-workspace".into(),
                "root" => member.root_thread_id = neighbor.id.clone(),
                "parent" => member.parent_thread_id = Some(neighbor.id.clone()),
                // Change the frozen original, rather than asking a mutable path to override it.
                "binding" => {}
                _ => unreachable!(),
            }
            if field == "binding" {
                let mut conflicting = frozen.clone();
                conflicting
                    .members
                    .iter_mut()
                    .find(|member| member.thread_id == middle.id)
                    .unwrap()
                    .execution
                    .root
                    .push_str("-replacement");
                conflicting.changed()?;
                runtime.store.save_thread_archive(&conflicting).await?;
                assert!(
                    runtime
                        .freeze_thread_removal(scope.clone(), &tree, &[])
                        .await
                        .is_err()
                );
                let mut restored = frozen.clone();
                restored.revision = conflicting.revision;
                restored.changed()?;
                runtime.store.save_thread_archive(&restored).await?;
            } else {
                assert!(
                    runtime
                        .freeze_thread_removal(scope.clone(), &changed, &[])
                        .await
                        .is_err(),
                    "{field}"
                );
            }
        }
        runtime
            .agent_facility
            .product_events
            .drain_directory_writes()
            .await?;
        let missing = if missing_root { &root.id } else { &leaf.id };
        let catalog = runtime.store.catalog();
        let mut sessions = catalog.sessions();
        let mut agents = catalog.agents();
        if missing_root {
            sessions.retain(|session| session.session_id != root.id);
            agents.retain(|agent| agent.session_id != root.id);
        } else {
            agents.retain(|agent| agent.thread_id != *missing);
        }
        // Retain the original runtime responsibility while removing canonical public facts
        // between attempts. Removing the whole root also removes its session and descendants,
        // so the directory remains structurally valid.
        catalog.test_restore_records(sessions, agents).await?;
        assert!(runtime.store.read_thread(missing).await?.is_none());
        let remaining = runtime.store.read_directory_tree(&root.id).await?;
        let retried = runtime
            .freeze_thread_removal(scope.clone(), &remaining, &[])
            .await?;
        assert_eq!(retried.members.len(), frozen.members.len());
        for original in &frozen.members {
            let member = retried
                .members
                .iter()
                .find(|member| member.thread_id == original.thread_id)
                .unwrap();
            assert_eq!(member.execution, original.execution);
            assert_eq!(member.host_session, original.host_session);
        }
        runtime
            .store
            .database()
            .execute_unprepared("DROP TRIGGER pause_missing_public")
            .await?;
        let reply = runtime
            .delete_thread("retry-missing-public".into(), root.id.clone())
            .await?
            .unwrap();
        assert_eq!(reply.result.deleted_thread_ids, deletion.thread_ids);
        for original in &frozen.members {
            assert!(!original.host_session.exists());
            assert!(
                !workspace
                    .join(SessionFiles::new(&original.thread_id).root())
                    .exists()
            );
        }
        assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
        assert_eq!(
            tokio::fs::read(
                workspace
                    .join(SessionFiles::new(&neighbor.id).root())
                    .join("marker")
            )
            .await?,
            neighbor.id.as_bytes()
        );
        runtime.shutdown_runtime().await?;
    }
    Ok(())
}

#[tokio::test]
async fn permanent_delete_cold_private_preparations_join_and_retire_after_restart() -> Result<()> {
    use crate::studio::store::thread_preparation::{PreparationBinding, PreparationSave};
    for restart in [false, true] {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home)?;
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let project = runtime.open_project(&workspace).await?;
        let root = runtime
            .create_thread_with_id("cold-private-root", &project.id, "root")
            .await?;
        let neighbor = runtime
            .create_thread_with_id("cold-private-neighbor", &project.id, "keep")
            .await?;
        let id = "cold-private-child";
        runtime
            .store
            .begin_removal_preparation(
                PreparationIdentity {
                    thread_id: id.into(),
                    workspace_id: project.id.clone(),
                    parent_id: Some(root.id.clone()),
                    root_id: root.id.clone(),
                },
                false,
            )
            .await?;
        let binding = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::Local,
            dunce::canonicalize(&workspace)?
                .to_string_lossy()
                .into_owned(),
        )?;
        runtime.store.bind_thread_preparation(id, &binding).await?;
        // A durable obligation from a previous owner must not require loading its cold store.
        runtime
            .store
            .require_preparation_save(id, "departed-incarnation", 7)
            .await?;
        let host = runtime.store.session_paths(&project.id, id)?;
        tokio::fs::create_dir_all(host.root()).await?;
        tokio::fs::write(host.history_database(), b"unreadable private content").await?;
        let execution = workspace.join(SessionFiles::new(id).root());
        tokio::fs::create_dir_all(&execution).await?;
        tokio::fs::write(execution.join("artifact"), b"private").await?;
        let runtime = if restart {
            runtime.shutdown_runtime().await?;
            StudioRuntime::initialize(options(&home)).await?
        } else {
            runtime
        };
        runtime.store.database().execute_unprepared(
            "CREATE TRIGGER inspect_cold_private BEFORE UPDATE ON studio_objects
             WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='removing'
             BEGIN SELECT RAISE(ABORT,'inspect cold private stop'); END"
        ).await?;
        let error = runtime
            .delete_thread("inspect-cold-private".into(), root.id.clone())
            .await
            .expect_err("inspect ACK before physical deletion");
        assert!(
            format!("{error:#}").contains("inspect cold private stop"),
            "{error:#}"
        );
        let record = runtime.store.thread_preparation(id).await?.unwrap();
        assert!(record.stopped && record.deletion_stopped && record.retired);
        assert_eq!(record.save, PreparationSave::Required);
        assert_eq!(
            record.binding,
            PreparationBinding::Bound { identity: binding }
        );
        assert!(record.storage.unwrap().closed_receipt.is_none());
        assert!(
            runtime
                .store
                .thread_persistence()
                .shared_history(id)
                .is_none()
        );
        assert_eq!(
            tokio::fs::read(host.history_database()).await?,
            b"unreadable private content"
        );
        runtime
            .store
            .database()
            .execute_unprepared("DROP TRIGGER inspect_cold_private")
            .await?;
        runtime
            .delete_thread("finish-cold-private".into(), root.id.clone())
            .await?
            .unwrap();
        assert!(!host.root().exists());
        assert!(!execution.exists());
        assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
        runtime.shutdown_runtime().await?;
    }
    Ok(())
}

#[tokio::test]
async fn permanent_delete_missing_frozen_private_and_failed_member_continue_independent_items()
-> Result<()> {
    use crate::studio::store::thread_archive::ArchiveScope;
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let _endpoint = configure(&home)?;
    let workspace = temp.path().join("workspace");
    tokio::fs::create_dir_all(&workspace).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let project = runtime.open_project(&workspace).await?;
    let root = runtime
        .create_thread_with_id("continue-root", &project.id, "root")
        .await?;
    let neighbor = runtime
        .create_thread_with_id("continue-neighbor", &project.id, "keep")
        .await?;
    let id = "continue-private";
    let identity = PreparationIdentity {
        thread_id: id.into(),
        workspace_id: project.id.clone(),
        parent_id: Some(root.id.clone()),
        root_id: root.id.clone(),
    };
    runtime
        .store
        .begin_removal_preparation(identity, false)
        .await?;
    runtime
        .store
        .bind_thread_preparation(
            id,
            &WorkspaceIdentity::canonical(
                WorkspaceEndpoint::Local,
                dunce::canonicalize(&workspace)?
                    .to_string_lossy()
                    .into_owned(),
            )?,
        )
        .await?;
    let host = runtime.store.session_paths(&project.id, id)?;
    tokio::fs::create_dir_all(host.root()).await?;
    let execution = workspace.join(SessionFiles::new(id).root());
    tokio::fs::create_dir_all(&execution).await?;
    let tree = runtime.store.read_directory_tree(&root.id).await?;
    let archive = runtime
        .freeze_thread_removal(ArchiveScope::Thread(root.id.clone()), &tree, &[])
        .await?;
    runtime.store.save_thread_archive(&archive).await?;
    runtime
        .store
        .database()
        .execute_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "DELETE FROM studio_objects WHERE owner_id=? AND object_kind='threadPreparation'",
            [id.into()],
        ))
        .await?;
    let failed = workspace.join(SessionFiles::new(&root.id).root());
    if failed.exists() {
        tokio::fs::remove_dir_all(&failed).await?;
    }
    tokio::fs::create_dir_all(failed.parent().unwrap()).await?;
    tokio::fs::write(&failed, b"preserve wrong target kind").await?;
    runtime
        .delete_thread("continue-delete".into(), root.id.clone())
        .await
        .expect_err("one unsafe target");
    let operation = runtime.store.thread_delete(&root.id).await?.unwrap();
    assert_eq!(operation.phase, DeletePhase::Removing);
    let private = operation
        .members
        .iter()
        .find(|member| member.identity.thread_id == id)
        .unwrap();
    assert!(private.execution_deleted && private.host_deleted);
    assert!(!execution.exists() && !host.root().exists());
    assert_eq!(
        tokio::fs::read(&failed).await?,
        b"preserve wrong target kind"
    );
    assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
    // Completed siblings must not be re-deleted when a retry encounters a replacement.
    tokio::fs::create_dir_all(&execution).await?;
    tokio::fs::write(execution.join("replacement"), b"keep").await?;
    tokio::fs::remove_file(&failed).await?;
    runtime
        .delete_thread("continue-retry".into(), root.id)
        .await?
        .unwrap();
    assert_eq!(
        tokio::fs::read(execution.join("replacement")).await?,
        b"keep"
    );
    runtime.shutdown_runtime().await?;
    Ok(())
}
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

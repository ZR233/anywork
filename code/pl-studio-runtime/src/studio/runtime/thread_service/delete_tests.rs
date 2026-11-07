//! Real lifecycle deletion, independent of UI/FRB and without external model requests.
use super::*;
use crate::studio::{
    agent_host::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity},
    runtime::conversation_reader::ConversationReader,
    storage_fault_test_support::{ThreadStorageSink, spawn_live_projection_for_thread},
    store::{
        directory::DirectoryDelta, thread_delete::DeletePhase,
        thread_preparation::PreparationIdentity,
    },
};
use pl_core::thread::{ThreadHandle, cold::ColdStoreHandle};
use pl_tool::workspace::SessionFiles;
use sea_orm::{ConnectionTrait, DatabaseBackend, Statement};

#[path = "delete_required_tests.rs"]
mod required;

#[tokio::test]
async fn permanent_delete_preflight_failure_retries_without_repairing_history() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let _endpoint = configure(&home)?;
    let workspace = temp.path().join("workspace");
    tokio::fs::create_dir_all(&workspace).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let project = runtime.open_project(&workspace).await?;
    let root = runtime
        .create_thread_with_id("preflight-root", &project.id, "root")
        .await?;
    let files = SessionFiles::new(&root.id);
    let path = workspace.join(files.root());
    if path.exists() {
        tokio::fs::remove_dir_all(&path).await?;
    }
    tokio::fs::create_dir_all(path.parent().unwrap()).await?;
    tokio::fs::write(&path, b"unexpected file").await?;
    let error = runtime
        .delete_thread("preflight-fail".into(), root.id.clone())
        .await
        .expect_err("wrong target kind must be preserved");
    let public = crate::error_mapping::studio_error_from_anyhow_ref(&error);
    assert!(public.message.contains("删除执行端目录"), "{public}");
    let operation = runtime.store.thread_delete(&root.id).await?.unwrap();
    assert!(
        !operation
            .members
            .iter()
            .find(|member| member.identity.thread_id == root.id)
            .unwrap()
            .execution_removal_started
    );
    assert_eq!(tokio::fs::read(&path).await?, b"unexpected file");
    tokio::fs::remove_file(&path).await?;
    tokio::fs::create_dir(&path).await?;
    tokio::fs::write(path.join("retry"), b"disposable").await?;
    runtime
        .delete_thread("preflight-retry".into(), root.id.clone())
        .await?
        .context("retry must complete")?;
    assert!(!path.exists());
    assert!(runtime.store.read_thread(&root.id).await?.is_none());
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn permanent_delete_takes_pending_project_archive_atomically_and_preserves_neighbor()
-> Result<()> {
    use crate::studio::store::thread_archive::{ArchivePhase, ArchiveScope};
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let _endpoint = configure(&home)?;
    let workspace = temp.path().join("workspace");
    tokio::fs::create_dir_all(&workspace).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let project = runtime.open_project(&workspace).await?;
    let root = runtime
        .create_thread_with_id("transfer-root", &project.id, "root")
        .await?;
    let neighbor = runtime
        .create_thread_with_id("transfer-neighbor", &project.id, "neighbor")
        .await?;
    let source_scope = ArchiveScope::Workspace(project.id.clone());
    runtime
        .store
        .database()
        .execute_unprepared(
            "CREATE TRIGGER reject_project_cleanup BEFORE UPDATE ON studio_objects
         WHEN NEW.object_kind='threadArchive'
         AND json_extract(NEW.payload_json,'$.scope.kind')='workspace'
         AND json_extract(NEW.payload_json,'$.phase')='cleaned'
         BEGIN SELECT RAISE(ABORT,'project cleanup ACK failure'); END",
        )
        .await?;
    let error = runtime
        .archive_project(&project.id)
        .await
        .expect_err("project archive must leave its original cleanup responsibility");
    assert!(
        format!("{error:#}").contains("project cleanup ACK failure"),
        "{error:#}"
    );
    let source = runtime.store.thread_archive(&source_scope).await?;
    let source = source.context("pending project archive")?;
    assert_eq!(source.phase, ArchivePhase::Saved);
    assert!(
        source
            .members
            .iter()
            .all(|member| member.host_cleaned && member.execution_cleaned)
    );
    let original_neighbor = source
        .members
        .iter()
        .find(|member| member.thread_id == neighbor.id)
        .context("neighbor cleanup responsibility")?;
    runtime
        .store
        .database()
        .execute_unprepared(
            "CREATE TRIGGER reject_delete_transfer BEFORE INSERT ON studio_objects
         WHEN NEW.object_kind='threadDelete' BEGIN SELECT RAISE(ABORT,'transfer rollback'); END",
        )
        .await?;
    assert!(
        runtime
            .delete_thread("transfer-fail".into(), root.id.clone())
            .await
            .is_err()
    );
    let unchanged = runtime.store.thread_archive(&source_scope).await?.unwrap();
    assert_eq!(unchanged.revision, source.revision);
    assert_eq!(unchanged.thread_ids(), source.thread_ids());
    assert!(
        runtime
            .store
            .thread_archive(&ArchiveScope::Thread(root.id.clone()))
            .await?
            .is_none()
    );
    assert!(runtime.store.thread_delete(&root.id).await?.is_none());
    runtime
        .store
        .database()
        .execute_unprepared("DROP TRIGGER reject_delete_transfer")
        .await?;
    runtime
        .delete_thread("transfer-success".into(), root.id.clone())
        .await?
        .context("delete without finishing preservation")?;
    let remaining = runtime.store.thread_archive(&source_scope).await?.unwrap();
    assert_eq!(remaining.phase, ArchivePhase::Saved);
    assert_eq!(remaining.thread_ids(), vec![neighbor.id.clone()]);
    assert_eq!(
        serde_json::to_value(&remaining.members[0])?,
        serde_json::to_value(original_neighbor)?,
        "the neighbor's original binding and completed cleanup must survive unchanged"
    );
    assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
    assert!(runtime.store.read_thread(&root.id).await?.is_none());
    runtime.shutdown_runtime().await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let resumed = runtime.store.thread_archive(&source_scope).await?.unwrap();
    assert_eq!(resumed.phase, ArchivePhase::Saved);
    assert_eq!(resumed.thread_ids(), vec![neighbor.id.clone()]);
    assert_eq!(
        serde_json::to_value(&resumed.members[0])?,
        serde_json::to_value(original_neighbor)?
    );
    runtime
        .store
        .database()
        .execute_unprepared("DROP TRIGGER reject_project_cleanup")
        .await?;
    runtime
        .archive_project(&project.id)
        .await?
        .context("remaining project archive can continue")?;
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn permanent_delete_resumes_removing_with_a_previously_published_project_archive()
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
        .create_thread_with_id("resume-root", &project.id, "root")
        .await?;
    let neighbor = runtime
        .create_thread_with_id("resume-neighbor", &project.id, "neighbor")
        .await?;
    runtime
        .archive_project(&project.id)
        .await?
        .context("archive project")?;
    let scope = ArchiveScope::Workspace(project.id.clone());
    let mut original = runtime.store.thread_archive(&scope).await?.unwrap();
    runtime
        .store
        .database()
        .execute_unprepared(
            "CREATE TRIGGER pause_before_removing BEFORE UPDATE ON studio_objects
         WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='removing'
         BEGIN SELECT RAISE(ABORT,'pause before removing'); END",
        )
        .await?;
    let error = runtime
        .delete_thread("resume-pause".into(), root.id.clone())
        .await
        .expect_err("pause after producers released");
    assert!(
        format!("{error:#}").contains("pause before removing"),
        "{error:#}"
    );
    runtime
        .store
        .database()
        .execute_unprepared("DROP TRIGGER pause_before_removing")
        .await?;
    // Prior producers could persist Removing while the published project still
    // retained its members. Recreate that durable cut using the original record.
    let mut deletion = runtime.store.thread_delete(&root.id).await?.unwrap();
    deletion.phase = DeletePhase::Removing;
    deletion.changed()?;
    runtime.store.save_thread_delete(&deletion).await?;
    original.revision = runtime
        .store
        .thread_archive(&scope)
        .await?
        .unwrap()
        .revision
        + 1;
    runtime.store.save_thread_archive(&original).await?;
    runtime.shutdown_runtime().await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    runtime
        .delete_thread("resume-complete".into(), root.id.clone())
        .await?
        .context("resumed deletion")?;
    assert_eq!(
        runtime
            .store
            .thread_archive(&scope)
            .await?
            .unwrap()
            .thread_ids(),
        vec![neighbor.id.clone()]
    );
    assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
    assert!(runtime.store.read_thread(&root.id).await?.is_none());
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn permanent_delete_releases_live_failed_save_and_failed_terminal_without_repair()
-> Result<()> {
    use crate::thread_assembler::{
        agent_review::ReviewDeliverySource,
        review_dispatch::{TerminalAuthority, TerminalDelivery, TerminalMaterialRetention},
    };
    use pl_core::{context::OpaquePayload, thread::extensions::ExtensionMutation};
    use std::sync::{Arc, atomic::AtomicU64};
    use tokio_util::sync::CancellationToken;

    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let _endpoint = configure(&home)?;
    let workspace = temp.path().join("workspace");
    tokio::fs::create_dir_all(&workspace).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let project = runtime.open_project(&workspace).await?;
    let root = runtime
        .create_thread_with_id("delete-live-fault", &project.id, "root")
        .await?;
    let owner = runtime.ensure_thread_owner(&root.id).await?;
    owner.flush().await?;
    runtime.synchronize_thread_observation(&root.id).await?;
    let child = cold_child(&runtime, &root.clone().into(), "delete-cold-child").await?;
    let producer_released = CancellationToken::new();
    let released = producer_released.clone();
    runtime
        .threads
        .start_terminal_delivery(Arc::new(TerminalDelivery {
            thread: child.clone(),
            sequence: 1,
            authority: Arc::new(TerminalAuthority::capture(&owner.snapshot())?),
            original: None,
            source: ReviewDeliverySource::Reconciliation,
            revocation: Arc::new(AtomicU64::new(0)),
            channel: None,
            wake: false,
            _material: Some(Arc::new(TerminalMaterialRetention::new(move || {
                released.cancel()
            }))),
        }))
        .await?;
    let failure = tokio::time::timeout(
        std::time::Duration::from_secs(10),
        runtime.threads.join_review_delivery(&child.id),
    )
    .await?
    .expect_err("missing original must block the actual terminal producer");
    ensure!(
        format!("{failure:#}").contains("original terminal message is missing"),
        "{failure:#}"
    );
    assert!(
        !producer_released.is_cancelled(),
        "failed producer must remain retained before deletion"
    );

    let host = runtime.store.session_paths(&project.id, &root.id)?;
    let db = sea_orm::Database::connect(
        crate::studio::paths::sqlite_file_options(
            &host.history_database(),
            crate::studio::paths::SqliteFileMode::ReadWrite,
            |options| options,
        )
        .await?,
    )
    .await?;
    db.execute_unprepared("CREATE TRIGGER reject_delete_save BEFORE UPDATE ON session_checkpoint BEGIN SELECT RAISE(ABORT,'permanent deletion must not repair this save'); END").await?;
    owner
        .mutate_extensions(vec![ExtensionMutation::Put {
            id: "delete-fault".into(),
            expected_revision: None,
            payload: OpaquePayload::text("unsaved content"),
        }])
        .await?;
    let save_error = tokio::time::timeout(std::time::Duration::from_secs(10), owner.flush())
        .await?
        .expect_err("the live writer must expose its real save failure");
    ensure!(
        format!("{save_error:#}").contains("permanent deletion must not repair"),
        "{save_error:#}"
    );
    db.close().await?;
    let channel = runtime.store.thread_persistence().history_channel(&root.id);
    let durable = channel.subscribe().borrow().committed_sequence;
    let unsaved_sequence = owner.snapshot().commit_sequence;
    assert!(durable < unsaved_sequence);
    assert!(runtime.thread_observations.live_feed(&root.id).is_some());
    let history = runtime.store.history(&root.id).await?;

    tokio::time::timeout(
        std::time::Duration::from_secs(15),
        runtime.delete_thread("delete-live-fault".into(), root.id.clone()),
    )
    .await??
    .context("deletion reply")?;
    assert!(
        producer_released.is_cancelled(),
        "the failed producer's retained task must actually exit"
    );
    assert!(channel.deletion_joined(), "writer must actually join");
    assert_eq!(
        channel.subscribe().borrow().committed_sequence,
        durable,
        "deletion must not invent a save ACK"
    );
    assert_eq!(
        owner.snapshot().commit_sequence,
        unsaved_sequence,
        "deletion adds no preservation facts"
    );
    assert_eq!(
        owner.snapshot().lifecycle,
        pl_core::thread::ThreadLifecycle::Closed
    );
    assert!(runtime.threads.observed_thread(&root.id).is_none());
    assert!(runtime.thread_observations.live_feed(&root.id).is_none());
    assert!(
        runtime
            .store
            .thread_persistence()
            .shared_history(&root.id)
            .is_none()
    );
    assert!(!host.root().exists());
    let closed = history
        .parent_report(1)
        .await
        .expect_err("the original pool must reject reads after deletion");
    ensure!(
        format!("{closed:#}").contains("permanently closed"),
        "{closed:#}"
    );
    runtime.shutdown_runtime().await?;
    Ok(())
}

async fn cold_child(
    runtime: &StudioRuntime,
    parent: &pl_protocol::Thread,
    id: &str,
) -> Result<pl_protocol::Thread> {
    let mut child = pl_protocol::Thread::placeholder(id);
    child.agent_path = format!("{}/{}", parent.agent_path, child.id);
    child.workspace_id = parent.workspace_id.clone();
    child.workspace_path = parent.workspace_path.clone();
    child.root_thread_id = parent.root_thread_id.clone();
    child.parent_thread_id = Some(parent.id.clone());
    let (_, agent) = crate::studio::records::directory_facts_from_thread(&child);
    runtime
        .agent_facility
        .product_events
        .commit_directory(DirectoryDelta {
            agent_upserts: vec![agent],
            ..Default::default()
        })
        .await?;
    let sink = ThreadStorageSink::new(runtime.store.clone(), child.clone(), None).await?;
    let projection = spawn_live_projection_for_thread(runtime.store.clone(), &child.id);
    let owner = ThreadHandle::resume_without_model(child.id.clone(), None)?;
    owner.attach_storage(ColdStoreHandle::new(sink)).await?;
    owner.close().await?;
    runtime
        .store
        .thread_persistence()
        .history_channel(&child.id)
        .stop_and_join()
        .await?;
    projection.await?;
    // S1 archive belongs to the Session, not independently to a child. The caller exercises
    // both active and archived Session trees while this child stays cold in either case.
    Ok(child)
}

#[tokio::test]
async fn permanent_delete_cold_missing_or_unreadable_history_skips_storage_and_temp_cleanup()
-> Result<()> {
    for unreadable_history in [false, true] {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home)?;
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let project = runtime.open_project(&workspace).await?;
        let (delta, session, agent) = DirectoryDelta::register_session(
            "delete-cold".into(),
            &project.id,
            "cold",
            pl_protocol::ThreadModeId::simple(),
            pl_protocol::ThreadWorkspaceMode::Local,
            dunce::canonicalize(&workspace)?
                .to_string_lossy()
                .into_owned(),
            crate::config::ROOT_AGENT_ROUTE_KEY,
        );
        runtime
            .agent_facility
            .product_events
            .commit_directory(delta)
            .await?;
        let root = crate::studio::ThreadRecord::from_directory_thread(
            crate::studio::records::thread_projection(&session, &agent),
        );
        let neighbor = runtime
            .create_thread_with_id("keep-cold", &project.id, "neighbor")
            .await?;
        let host = runtime.store.session_paths(&project.id, &root.id)?;
        runtime
            .store
            .begin_removal_preparation(
                PreparationIdentity {
                    thread_id: root.id.clone(),
                    workspace_id: project.id.clone(),
                    parent_id: None,
                    root_id: root.id.clone(),
                },
                true,
            )
            .await?;
        assert!(runtime.threads.observed_thread(&root.id).is_none());
        assert!(!host.history_database().exists());
        if unreadable_history {
            tokio::fs::create_dir_all(host.root()).await?;
            tokio::fs::write(host.history_database(), b"not a SQLite database").await?;
        }
        let files = SessionFiles::new(&root.id);
        tokio::fs::create_dir_all(workspace.join(files.root())).await?;
        // A stale temp file must not need to satisfy archive temp-directory validation:
        // permanent deletion removes the dedicated session root in one operation.
        tokio::fs::write(workspace.join(files.temp()), b"disposable temp file").await?;
        runtime.store.database().execute_unprepared(
            "CREATE TRIGGER pause_cold_delete BEFORE UPDATE ON studio_objects
             WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='removing'
             BEGIN SELECT RAISE(ABORT,'pause before physical deletion'); END"
        ).await?;
        let error = runtime
            .delete_thread("pause-cold".into(), root.id.clone())
            .await
            .expect_err("the phase commit must reach the injected barrier");
        assert!(
            format!("{error:#}").contains("pause before physical deletion"),
            "{error:#}"
        );
        assert!(
            runtime
                .store
                .thread_persistence()
                .shared_history(&root.id)
                .is_none(),
            "cold deletion must not open a history pool"
        );
        assert_eq!(
            tokio::fs::read(workspace.join(files.temp())).await?,
            b"disposable temp file"
        );
        if unreadable_history {
            assert_eq!(
                tokio::fs::read(host.history_database()).await?,
                b"not a SQLite database"
            );
        } else {
            assert!(!host.history_database().exists());
        }
        runtime
            .store
            .database()
            .execute_unprepared("DROP TRIGGER pause_cold_delete")
            .await?;
        runtime
            .delete_thread("finish-cold".into(), root.id.clone())
            .await?
            .context("cold deletion reply")?;
        assert!(!host.root().exists());
        assert!(!workspace.join(files.root()).exists());
        assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
        assert!(
            runtime
                .delete_thread("repeat-cold".into(), root.id.clone())
                .await?
                .is_none()
        );
        runtime.shutdown_runtime().await?;
    }
    Ok(())
}

#[tokio::test]
async fn permanent_delete_removes_active_or_archived_tree_private_files_and_revokes_readers()
-> Result<()> {
    for archived in [false, true] {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home)?;
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let project = runtime.open_project(&workspace).await?;
        let root = runtime
            .create_thread_with_id("delete-root", &project.id, "root")
            .await?;
        let neighbor = runtime
            .create_thread_with_id("delete-neighbor", &project.id, "neighbor")
            .await?;
        runtime.ensure_thread_owner(&root.id).await?.flush().await?;
        runtime
            .ensure_thread_owner(&neighbor.id)
            .await?
            .flush()
            .await?;
        let child = cold_child(&runtime, &root.clone().into(), "delete-cold-child").await?;
        let grandchild = cold_child(&runtime, &child, "delete-cold-grandchild").await?;
        for (agent, parent) in [
            (&child.id, &root.id),
            (&grandchild.id, &child.id),
            (&neighbor.id, &neighbor.id),
        ] {
            runtime.store.database().execute_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
                "INSERT INTO agent_evaluations
                 (agent_id,parent_agent_id,account_id,model_id,profile_id,mode,preference,turn_id,
                  revision,task_category,outcome,comment,created_at,updated_at)
                 VALUES (?,?,'fixture','model','profile','profile','balanced','final',1,'coding','notRated','original evaluation',1,1)",
                [agent.clone().into(), parent.clone().into()])).await?;
        }
        let config = runtime.config_runtime.read()?;
        runtime.config_runtime.update(config.revision, |desired| {
            let mut next = desired.clone();
            next.ui.pinned_thread_ids = vec![root.id.clone(), neighbor.id.clone()];
            Ok(next)
        })?;
        let private = PreparationIdentity {
            thread_id: "delete-unpublished".into(),
            workspace_id: project.id.clone(),
            parent_id: Some(root.id.clone()),
            root_id: root.id.clone(),
        };
        runtime
            .store
            .begin_thread_preparation(private.clone())
            .await?;
        let binding = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::Local,
            dunce::canonicalize(&workspace)?
                .to_string_lossy()
                .into_owned(),
        )?;
        runtime
            .store
            .bind_thread_preparation(&private.thread_id, &binding)
            .await?;
        runtime
            .store
            .confirm_preparation_stop(&private.thread_id)
            .await?;
        runtime
            .store
            .set_preparation_disposition(
                &private.thread_id,
                crate::studio::store::thread_preparation::PreparationDisposition::Remove,
            )
            .await?;
        runtime
            .store
            .confirm_preparation_retirement(&private.thread_id)
            .await?;
        let ids = [&root.id, &child.id, &grandchild.id, &private.thread_id];
        for id in ids {
            let host = runtime.store.session_paths(&project.id, id)?;
            for name in ["notes", "plan", "reports", "resources", "attachments"] {
                tokio::fs::create_dir_all(host.root().join(name)).await?;
                tokio::fs::write(host.root().join(name).join("private"), b"delete this body")
                    .await?;
            }
            let files = SessionFiles::new(id);
            for path in [files.temp(), files.artifacts()] {
                tokio::fs::create_dir_all(workspace.join(&path)).await?;
                tokio::fs::write(
                    workspace.join(path).join("private"),
                    b"delete execution data",
                )
                .await?;
            }
        }
        let neighbor_files = SessionFiles::new(&neighbor.id);
        tokio::fs::write(
            workspace.join(neighbor_files.artifacts()).join("keep"),
            b"neighbor artifact",
        )
        .await?;
        tokio::fs::write(workspace.join("business"), b"ordinary project content").await?;
        if archived {
            runtime
                .archive_thread("archive-delete".into(), root.id.clone())
                .await?
                .context("archive reply")?;
        }
        let feed = runtime
            .open_conversation_feed(
                &root.id,
                pl_protocol::ChatScope::Main,
                pl_protocol::ReadDemand {
                    max_items: 16,
                    max_bytes: 65536,
                },
            )
            .await?;
        let reader: ConversationReader = feed.reader().clone();
        let old_history = runtime.store.history(&root.id).await?;
        let root_host = runtime.store.session_paths(&project.id, &root.id)?;
        let child_host = runtime.store.session_paths(&project.id, &child.id)?;
        let grandchild_host = runtime.store.session_paths(&project.id, &grandchild.id)?;
        let private_host = runtime
            .store
            .session_paths(&project.id, &private.thread_id)?;
        assert!(
            runtime
                .delete_thread("reject-child".into(), child.id.clone())
                .await
                .is_err()
        );
        let started = std::time::Instant::now();
        let result = runtime
            .delete_thread("permanent-delete".into(), root.id.clone())
            .await?
            .context("delete reply")?;
        println!(
            "PERMANENT_DELETE_TREE members=4 depth=3 archived={archived} elapsed_us={}",
            started.elapsed().as_micros()
        );
        assert_eq!(result.result.deleted_thread_ids.len(), ids.len());
        for id in ids {
            assert!(result.result.deleted_thread_ids.contains(id));
        }
        assert_eq!(
            result
                .result
                .next_root
                .as_ref()
                .map(|root| root.id.as_str()),
            Some(neighbor.id.as_str())
        );
        assert!(
            reader.ensure().is_err(),
            "an old reader must lose its read qualification"
        );
        assert!(
            old_history.conversation_database_id().await.is_err(),
            "the original pools must close"
        );
        for host in [root_host, child_host, grandchild_host, private_host] {
            assert!(!host.root().exists());
        }
        for id in ids {
            assert!(runtime.store.read_thread(id).await?.is_none());
            assert!(!workspace.join(SessionFiles::new(id).root()).exists());
            assert!(runtime.store.thread_preparation(id).await?.is_none());
            let owned = runtime.store.database().query_one_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
                "SELECT 1 FROM studio_objects WHERE owner_id=? AND owner_kind IN ('thread','agent')",
                [id.clone().into()])).await?;
            assert!(owned.is_none(), "private/lease/close records must be gone");
        }
        for id in [&child.id, &grandchild.id] {
            assert!(runtime.store.read_agent_evaluation(id).await?.is_none());
        }
        assert!(
            runtime
                .store
                .database()
                .query_one_raw(Statement::from_sql_and_values(
                    DatabaseBackend::Sqlite,
                    "SELECT 1 FROM agent_evaluations WHERE agent_id=?",
                    [neighbor.id.clone().into()]
                ))
                .await?
                .is_some()
        );
        assert_eq!(
            runtime.config_runtime.read()?.config.ui.pinned_thread_ids,
            vec![neighbor.id.clone()]
        );
        let (session, agent) = crate::studio::records::directory_facts_from_thread(
            &pl_protocol::Thread::from(root.clone()),
        );
        let mut delayed =
            crate::studio::records::row_projection(&session.expect("root session"), &agent);
        delayed.title = "late metadata must not restore deletion".into();
        runtime
            .agent_facility
            .product_events
            .apply_thread_delta(vec![delayed], vec![])
            .await?;
        assert!(
            runtime
                .agent_facility
                .product_events
                .thread_snapshot(&root.id)
                .is_none()
        );
        assert_eq!(
            tokio::fs::read(workspace.join("business")).await?,
            b"ordinary project content"
        );
        assert_eq!(
            tokio::fs::read(workspace.join(neighbor_files.artifacts()).join("keep")).await?,
            b"neighbor artifact"
        );
        assert!(
            runtime
                .store
                .history(&neighbor.id)
                .await?
                .conversation_database_id()
                .await?
                .is_some()
        );
        assert!(
            runtime
                .create_thread_with_id(&root.id, &project.id, "cannot recreate")
                .await
                .is_err()
        );
        assert!(runtime.restore_thread(root.id.clone()).await.is_err());
        assert!(
            runtime
                .delete_thread("duplicate-delete".into(), root.id.clone())
                .await?
                .is_none()
        );
        let operation = runtime.store.thread_delete(&root.id).await?.unwrap();
        assert_eq!(operation.phase, DeletePhase::Published);
        assert!(operation.members.is_empty());
        runtime.shutdown_runtime().await?;
        let restarted = StudioRuntime::initialize(options(&home)).await?;
        assert!(restarted.store.read_thread(&root.id).await?.is_none());
        assert!(restarted.store.read_thread(&neighbor.id).await?.is_some());
        assert!(
            restarted
                .create_thread_with_id(&root.id, &project.id, "cannot restart")
                .await
                .is_err()
        );
        restarted.shutdown_runtime().await?;
    }
    Ok(())
}

#[cfg(unix)]
#[tokio::test]
async fn permanent_delete_failure_is_durable_retries_original_binding_and_preserves_neighbor()
-> Result<()> {
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let _endpoint = configure(&home)?;
    let workspace = temp.path().join("workspace");
    tokio::fs::create_dir_all(&workspace).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let project = runtime.open_project(&workspace).await?;
    let root = runtime
        .create_thread_with_id("retry-delete", &project.id, "root")
        .await?;
    let neighbor = runtime
        .create_thread_with_id("retry-neighbor", &project.id, "neighbor")
        .await?;
    runtime.ensure_thread_owner(&root.id).await?.flush().await?;
    runtime
        .ensure_thread_owner(&neighbor.id)
        .await?
        .flush()
        .await?;
    let files = SessionFiles::new(&root.id);
    let outside = temp.path().join("outside");
    tokio::fs::create_dir(&outside).await?;
    tokio::fs::write(outside.join("keep"), b"outside").await?;
    runtime.store.database().execute_unprepared(
        "CREATE TRIGGER reject_deleted_phase BEFORE UPDATE ON studio_objects
         WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='dataDeleted'
         BEGIN SELECT RAISE(ABORT,'injected deletion commit failure'); END"
    ).await?;
    assert!(
        runtime
            .delete_thread("fail-delete".into(), root.id.clone())
            .await
            .is_err()
    );
    assert_eq!(
        runtime.store.thread_delete(&root.id).await?.unwrap().phase,
        DeletePhase::Removing
    );
    assert!(runtime.store.history(&root.id).await.is_err());
    assert!(runtime.ensure_thread_owner(&root.id).await.is_err());
    runtime
        .store
        .database()
        .execute_unprepared("DROP TRIGGER reject_deleted_phase")
        .await?;
    runtime.shutdown_runtime().await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    // Retrying a durable host-deleted member must not re-delete a same-path replacement.
    let host = runtime.store.session_paths(&project.id, &root.id)?;
    tokio::fs::create_dir_all(host.root()).await?;
    tokio::fs::write(host.root().join("replacement"), b"preserve replacement").await?;
    let result = runtime
        .delete_thread("retry-delete".into(), root.id.clone())
        .await?
        .context("retry reply")?;
    assert_eq!(result.result.deleted_root_id, root.id);
    assert_eq!(
        tokio::fs::read(host.root().join("replacement")).await?,
        b"preserve replacement"
    );
    assert!(!workspace.join(files.root()).exists());
    assert_eq!(tokio::fs::read(outside.join("keep")).await?, b"outside");
    assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn permanent_delete_effect_before_ack_preserves_host_and_execution_replacements() -> Result<()>
{
    for host_target in [false, true] {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home)?;
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let project = runtime.open_project(&workspace).await?;
        let root = runtime
            .create_thread_with_id("unknown-delete", &project.id, "root")
            .await?;
        let neighbor = runtime
            .create_thread_with_id("unknown-neighbor", &project.id, "neighbor")
            .await?;
        runtime.ensure_thread_owner(&root.id).await?.flush().await?;
        runtime
            .ensure_thread_owner(&neighbor.id)
            .await?
            .flush()
            .await?;
        let host = runtime.store.session_paths(&project.id, &root.id)?;
        let target = if host_target {
            host.root().to_owned()
        } else {
            workspace.join(SessionFiles::new(&root.id).root())
        };
        let field = if host_target {
            "hostDeleted"
        } else {
            "executionDeleted"
        };
        let started = if host_target {
            "hostRemovalStarted"
        } else {
            "executionRemovalStarted"
        };
        runtime
            .store
            .database()
            .execute_unprepared(&format!(
                "CREATE TRIGGER reject_session_removal_start BEFORE UPDATE ON studio_objects
             WHEN NEW.object_kind='threadDelete'
              AND json_extract(NEW.payload_json,'$.phase')='removing'
              AND json_extract(NEW.payload_json,'$.members[0].{started}')=1
             BEGIN SELECT RAISE(ABORT,'injected started fence failure'); END"
            ))
            .await?;
        assert!(
            runtime
                .delete_thread("unknown-start-failure".into(), root.id.clone())
                .await
                .is_err()
        );
        assert!(
            target.is_dir(),
            "removal cannot outrun its durable started fence"
        );
        runtime
            .store
            .database()
            .execute_unprepared("DROP TRIGGER reject_session_removal_start")
            .await?;
        runtime
            .store
            .database()
            .execute_unprepared(&format!(
                "CREATE TRIGGER reject_session_removal_ack BEFORE UPDATE ON studio_objects
             WHEN NEW.object_kind='threadDelete'
              AND json_extract(NEW.payload_json,'$.phase')='removing'
              AND json_extract(NEW.payload_json,'$.members[0].{field}')=1
             BEGIN SELECT RAISE(ABORT,'injected effect-before-ACK failure'); END"
            ))
            .await?;
        assert!(
            runtime
                .delete_thread("unknown-first".into(), root.id.clone())
                .await
                .is_err()
        );
        assert!(
            !target.exists(),
            "physical removal must precede the injected ACK failure"
        );
        let pending = runtime
            .store
            .thread_delete(&root.id)
            .await?
            .context("retained removal")?;
        let member = &pending.members[0];
        assert!(if host_target {
            member.host_removal_started && !member.host_deleted
        } else {
            member.execution_removal_started && !member.execution_deleted
        });
        let mut old_payload = serde_json::to_value(&pending)?;
        let old_member = old_payload["members"][0].as_object_mut().unwrap();
        old_member.remove("hostRemovalStarted");
        old_member.remove("executionRemovalStarted");
        let old: crate::studio::store::thread_delete::ThreadDeleteOperation =
            serde_json::from_value(old_payload)?;
        assert!(
            old.members[0].host_removal_started && old.members[0].execution_removal_started,
            "old Removing records cannot prove the physical effect was unstarted"
        );
        runtime
            .store
            .database()
            .execute_unprepared("DROP TRIGGER reject_session_removal_ack")
            .await?;
        runtime.shutdown_runtime().await?;
        tokio::fs::create_dir_all(&target).await?;
        tokio::fs::write(target.join("replacement"), b"preserve unknown replacement").await?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        assert!(
            runtime
                .delete_thread("unknown-retry".into(), root.id.clone())
                .await
                .is_err(),
            "an unacknowledged removal must never delete a same-path replacement"
        );
        assert_eq!(
            tokio::fs::read(target.join("replacement")).await?,
            b"preserve unknown replacement"
        );
        assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
        // Only this fixture owns the replacement. Once it is absent, retry may reconcile the
        // original removal without issuing another destructive call against an existing object.
        tokio::fs::remove_dir_all(&target).await?;
        runtime
            .delete_thread("unknown-absent".into(), root.id.clone())
            .await?
            .context("absence reconciliation")?;
        assert!(!host.root().exists());
        assert!(!workspace.join(SessionFiles::new(&root.id).root()).exists());
        assert!(
            runtime
                .store
                .history(&neighbor.id)
                .await?
                .conversation_database_id()
                .await?
                .is_some()
        );
        runtime.shutdown_runtime().await?;
    }
    Ok(())
}

async fn git_fixture(root: &Path, args: &[&str]) -> Result<String> {
    let output = tokio::process::Command::new("git")
        .args(args)
        .current_dir(root)
        .output()
        .await?;
    ensure!(
        output.status.success(),
        "Git fixture {args:?}: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    Ok(String::from_utf8(output.stdout)?)
}

#[tokio::test]
async fn archive_owned_worktrees_wait_for_borrowers_and_git_locks_discard_content_and_preserve_refs()
-> Result<()> {
    use crate::{
        agent::worktree::{
            LocalWorktreeBackend, WorktreeCreateSpec, WorktreeManager, WorktreeOwnership,
        },
        studio::{
            agent_host::worktree_lease::{
                WorktreeLease, WorktreeLeaseOwnerKind, WorktreeLeaseState,
            },
            store::thread_archive::{ArchivePhase, ArchiveScope},
        },
    };
    for root_owned in [true, false] {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home)?;
        let repository = temp.path().join("repository");
        tokio::fs::create_dir(&repository).await?;
        git_fixture(&repository, &["init", "--quiet"]).await?;
        git_fixture(
            &repository,
            &[
                "-c",
                "user.name=fixture",
                "-c",
                "user.email=fixture@example.invalid",
                "commit",
                "--quiet",
                "--allow-empty",
                "-m",
                "fixture",
            ],
        )
        .await?;
        let repository = dunce::canonicalize(repository)?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let project = runtime.open_project(&repository).await?;
        let manager = WorktreeManager::new(
            repository.clone(),
            std::sync::Arc::new(LocalWorktreeBackend::default()),
        );
        let head = manager.resolve_head(&repository).await?;
        let owner_id = if root_owned {
            "owned-root"
        } else {
            "owned-private-child"
        };
        let ownership = if root_owned {
            WorktreeOwnership::Session {
                thread_id: "owned-root".into(),
            }
        } else {
            WorktreeOwnership::Child {
                child_id: owner_id.into(),
            }
        };
        let handle = manager
            .create(WorktreeCreateSpec {
                repo_root: repository.clone(),
                root_thread_id: "owned-root".into(),
                ownership,
                base_commit: head.clone(),
            })
            .await
            .map_err(|error| anyhow::anyhow!("{error:?}"))?;
        let identity = WorkspaceIdentity::canonical(
            WorkspaceEndpoint::Local,
            handle.path.to_string_lossy().into_owned(),
        )?;
        let mut lease = WorktreeLease {
            revision: 1,
            state: WorktreeLeaseState::Prepared,
            owner_kind: if root_owned {
                WorktreeLeaseOwnerKind::Session
            } else {
                WorktreeLeaseOwnerKind::Child
            },
            owner_thread_id: owner_id.into(),
            root_thread_id: "owned-root".into(),
            workspace_id: project.id.clone(),
            ssh_alias: None,
            repository_root: repository.to_string_lossy().into_owned(),
            path: identity.root.clone(),
            base_commit: head,
        };
        runtime
            .store
            .bind_workspace_identity(owner_id, &identity)
            .await?;
        runtime
            .agent_facility
            .worktrees
            .record_durable(lease.clone())
            .await?;
        lease.transition(WorktreeLeaseState::Active);
        runtime
            .agent_facility
            .worktrees
            .record_durable(lease)
            .await?;
        let root = if root_owned {
            let (delta, session, agent) = DirectoryDelta::register_session(
                "owned-root".into(),
                &project.id,
                "owned",
                pl_protocol::ThreadModeId::simple(),
                pl_protocol::ThreadWorkspaceMode::Worktree,
                identity.root.clone(),
                crate::config::ROOT_AGENT_ROUTE_KEY,
            );
            runtime
                .agent_facility
                .product_events
                .commit_directory(delta)
                .await?;
            let root = crate::studio::ThreadRecord::from_directory_thread(
                crate::studio::records::thread_projection(&session, &agent),
            );
            runtime.register_new_thread(root.clone()).await?;
            root
        } else {
            let root = runtime
                .create_thread_with_id("owned-root", &project.id, "local root")
                .await?;
            let preparation = PreparationIdentity {
                thread_id: owner_id.into(),
                workspace_id: project.id.clone(),
                parent_id: Some(root.id.clone()),
                root_id: root.id.clone(),
            };
            runtime.store.begin_thread_preparation(preparation).await?;
            runtime
                .store
                .bind_thread_preparation(owner_id, &identity)
                .await?;
            runtime.store.confirm_preparation_stop(owner_id).await?;
            runtime
                .store
                .confirm_preparation_retirement(owner_id)
                .await?;
            root
        };
        runtime.ensure_thread_owner(&root.id).await?.flush().await?;
        let reliable = runtime
            .store
            .registered_session_paths(&root.id)?
            .history_database();
        tokio::fs::write(handle.path.join(".gitignore"), b"ignored\n").await?;
        tokio::fs::write(handle.path.join("dirty"), b"untracked content").await?;
        tokio::fs::write(handle.path.join("ignored"), b"ignored content").await?;
        let refs = git_fixture(
            &repository,
            &["for-each-ref", "--format=%(refname):%(objectname)"],
        )
        .await?;
        let borrower = runtime
            .agent_facility
            .worktrees
            .reserve_workspace("outside-tree", WorkspaceEndpoint::Local)?;
        runtime
            .agent_facility
            .worktrees
            .assign_workspace(&borrower, identity.clone())?;
        assert!(
            runtime
                .archive_thread("borrower-archive".into(), root.id.clone())
                .await
                .is_err()
        );
        assert!(handle.path.join("dirty").is_file());
        assert_eq!(
            runtime
                .store
                .thread_archive(&ArchiveScope::Thread(root.id.clone()))
                .await?
                .unwrap()
                .phase,
            ArchivePhase::Saved
        );
        drop(borrower);
        let mut legacy = runtime
            .store
            .thread_archive(&ArchiveScope::Thread(root.id.clone()))
            .await?
            .unwrap();
        legacy.worktrees.clear();
        legacy.phase = ArchivePhase::Cleaned;
        legacy.changed()?;
        runtime.store.save_thread_archive(&legacy).await?;
        git_fixture(
            &repository,
            &["worktree", "lock", handle.path.to_str().unwrap()],
        )
        .await?;
        assert!(
            runtime
                .archive_thread("locked-archive".into(), root.id.clone())
                .await
                .is_err()
        );
        assert!(handle.path.join("dirty").is_file());
        git_fixture(
            &repository,
            &["worktree", "unlock", handle.path.to_str().unwrap()],
        )
        .await?;
        // Forced cleanup must not inspect disposable file content or depend on a healthy index.
        let index = git_fixture(&handle.path, &["rev-parse", "--git-path", "index"]).await?;
        let index = Path::new(index.trim());
        let index = if index.is_absolute() {
            index.to_owned()
        } else {
            handle.path.join(index)
        };
        tokio::fs::write(index, b"invalid disposable Git index").await?;
        assert!(
            git_fixture(&handle.path, &["status", "--porcelain=v1"])
                .await
                .is_err()
        );
        runtime
            .archive_thread("discard-archive".into(), root.id.clone())
            .await?
            .context("archive reply")?;
        assert!(!handle.path.exists());
        assert!(reliable.is_file());
        assert_eq!(
            git_fixture(
                &repository,
                &["for-each-ref", "--format=%(refname):%(objectname)"]
            )
            .await?,
            refs
        );
        assert!(repository.is_dir());
        if root_owned {
            let replacement = manager
                .create(WorktreeCreateSpec {
                    repo_root: repository.clone(),
                    root_thread_id: root.id.clone(),
                    ownership: WorktreeOwnership::Session {
                        thread_id: root.id.clone(),
                    },
                    base_commit: manager.resolve_head(&repository).await?,
                })
                .await
                .map_err(|error| anyhow::anyhow!("{error:?}"))?;
            tokio::fs::write(
                replacement.path.join("replacement"),
                b"preserve replacement",
            )
            .await?;
            assert!(
                runtime
                    .archive_thread("replacement-archive".into(), root.id.clone())
                    .await
                    .is_err()
            );
            assert_eq!(
                tokio::fs::read(replacement.path.join("replacement")).await?,
                b"preserve replacement"
            );
            manager
                .cleanup(
                    &replacement,
                    crate::agent::worktree::WorktreeCleanupPolicy::Discard,
                )
                .await?;
            runtime
                .archive_thread("settle-original-archive".into(), root.id.clone())
                .await?
                .context("settled archive")?;
        }
        runtime.restore_thread(root.id.clone()).await?;
        if root_owned {
            assert!(runtime.ensure_thread_owner(&root.id).await.is_err());
        }
        assert!(
            !handle.path.exists(),
            "restoration cannot recreate a removed worktree"
        );
        runtime
            .delete_thread("delete-archived-worktrees".into(), root.id.clone())
            .await?
            .context("delete reply")?;
        assert!(!reliable.exists());
        assert!(repository.join(".git").is_dir());
        assert_eq!(
            git_fixture(
                &repository,
                &["for-each-ref", "--format=%(refname):%(objectname)"]
            )
            .await?,
            refs
        );
        runtime.shutdown_runtime().await?;
    }
    Ok(())
}

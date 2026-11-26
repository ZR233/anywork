//! Real lifecycle deletion, independent of UI/FRB and without external model requests.
use super::super::StudioRuntime;
use super::test_support::{configure, git_fixture, options};
use anyhow::{Context, Result, ensure};
use std::path::Path;

mod publication_recovery;
use crate::studio::{
    store::{
        directory::DirectoryDelta, thread_delete::DeletePhase,
        thread_preparation::PreparationIdentity,
    },
    worktree::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity},
};
use crate::test_support::storage::{ThreadStorageSink, spawn_live_projection_for_thread};
use pl_core::thread::ThreadHandle;
use pl_tool::workspace::SessionFiles;
use sea_orm::{ConnectionTrait, DatabaseBackend, Statement};

#[tokio::test]
async fn permanent_delete_preflight_failure_retries_without_repairing_history() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let _endpoint = configure(&home).await?;
    let workspace = temp.path().join("workspace");
    tokio::fs::create_dir_all(&workspace).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let project = runtime.open_project(&workspace).await?;
    let root = runtime
        .create_thread_with_id("preflight-root", &project.id, "root")
        .await?;
    runtime
        .archive_thread("prepare-path-fault".into(), root.id.clone())
        .await?
        .context("archive before replacing the disposable path")?;
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
        operation
            .members
            .iter()
            .find(|member| member.identity.thread_id == root.id)
            .unwrap()
            .host_deleted,
        "an independent host directory must finish after execution preflight fails"
    );
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
    let _endpoint = configure(&home).await?;
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
    let _endpoint = configure(&home).await?;
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
    let _endpoint = configure(&home).await?;
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
        .require_session(&child.id)?
        .start_terminal_delivery(Arc::new(TerminalDelivery {
            thread: child.clone(),
            sequence: 1,
            authority: Arc::new(TerminalAuthority::capture(&owner.snapshot())?),
            original: Arc::new(pl_core::thread::inbox::ThreadMessage {
                kind: pl_core::context::AgentMessageKind::Report,
                id: "invalid-terminal-identity".into(),
                source_id: format!("studio.child:{}", child.id),
                payload: OpaquePayload::new("pl.studio.turn-report", 3, "{}")?,
                context: Vec::new(),
            }),
            finish: None,
            source: ReviewDeliverySource::Reconciliation,
            revocation: Arc::new(AtomicU64::new(0)),
            channel: None,
            wake: false,
            _material: Some(Arc::new(TerminalMaterialRetention::new(move || {
                released.cancel()
            }))),
        }))
        .await?;
    tokio::time::timeout(
        std::time::Duration::from_secs(10),
        runtime
            .require_session(&child.id)?
            .join_review_delivery(&child.id),
    )
    .await?
    .expect_err("invalid terminal must block the actual producer");
    assert!(
        !producer_released.is_cancelled(),
        "failed producer must remain retained before deletion"
    );

    let host = runtime.store.session_paths(&project.id, &root.id)?;
    let conversation = runtime.store.conversation_store(&root.id).await?;
    conversation.flush_current(owner.runtime_epoch()).await?;
    let current_writer = runtime
        .store
        .thread_persistence()
        .current_writer(&root.id, host.root().to_path_buf())
        .await?;
    let current_file = host.current_file();
    tokio::fs::rename(&current_file, current_file.with_extension("json.saved")).await?;
    tokio::fs::create_dir(&current_file).await?;
    owner
        .mutate_extensions(vec![ExtensionMutation::Put {
            id: "delete-fault".into(),
            expected_revision: None,
            payload: OpaquePayload::text("unsaved content"),
        }])
        .await?;
    let save_error = tokio::time::timeout(
        std::time::Duration::from_secs(10),
        conversation.flush_current(owner.runtime_epoch()),
    )
    .await?
    .expect_err("the live Current writer must expose its real save failure");
    ensure!(
        format!("{save_error:#}").contains("current.json"),
        "{save_error:#}"
    );
    let failed_current = current_writer
        .snapshot()
        .error
        .map(|error| error.to_string())
        .context("blocked Current save failure")?;
    let channel = runtime.store.thread_persistence().history_channel(&root.id);
    let unsaved_sequence = owner.snapshot().commit_sequence;
    assert!(runtime.thread_observations.meta_bus(&root.id).is_some());

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
        current_writer
            .snapshot()
            .error
            .map(|error| error.to_string()),
        Some(failed_current),
        "deletion must not retry or replace the original Current failure"
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
    assert!(
        runtime
            .session_of(&root.id)
            .and_then(|session| session.observed_thread(&root.id))
            .is_none()
    );
    assert!(runtime.thread_observations.meta_bus(&root.id).is_none());
    assert!(
        runtime
            .store
            .thread_persistence()
            .shared_history(&root.id)
            .is_none()
    );
    assert!(!host.root().exists());
    runtime.shutdown_runtime().await?;
    Ok(())
}

async fn cold_child(
    runtime: &StudioRuntime,
    parent: &crate::Thread,
    id: &str,
) -> Result<crate::Thread> {
    let mut child = crate::Thread::placeholder(id);
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
    // This cold member needs an independent Current and an empty History store. A
    // Current-only extension has no historical original and owes no History checkpoint.
    runtime.store.history(&child.id).await?;
    let owner = ThreadHandle::start_current(child.id.clone(), None)?;
    let epoch = owner.runtime_epoch();
    let mut current = runtime.store.state_for(&child.workspace_id, &child.id)?;
    current
        .attach_current(
            runtime.store.thread_persistence().clone(),
            None,
            epoch,
            crate::studio::storage::current_writer::CurrentSource::from_thread(owner.clone()),
        )
        .await?;
    owner
        .mutate_extensions(vec![pl_core::thread::extensions::ExtensionMutation::Put {
            id: "fixture.cold-child".into(),
            expected_revision: None,
            payload: pl_core::context::OpaquePayload::text("durable cold Current"),
        }])
        .await?;
    current
        .close_current(epoch, crate::thread_assembler::ClosePurpose::Preserve)
        .await?;
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
        let _endpoint = configure(&home).await?;
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let project = runtime.open_project(&workspace).await?;
        let (delta, session, agent) = DirectoryDelta::register_session(
            crate::studio::store::directory::SessionDirectoryUpsert {
                session_id: "delete-cold".into(),
                workspace_id: &project.id,
                title: "cold",
                mode: crate::mode::ThreadModeId::auto(),
                workspace_mode: crate::ThreadWorkspaceMode::Local,
                workspace_path: dunce::canonicalize(&workspace)?
                    .to_string_lossy()
                    .into_owned(),
                role: crate::config::ROOT_AGENT_ROUTE_KEY,
            },
        );
        runtime
            .agent_facility
            .product_events
            .commit_directory(delta)
            .await?;
        let root = crate::studio::ThreadRecord::from_directory_thread(
            crate::studio::records::thread_projection(&session, &agent, |id| {
                runtime
                    .store
                    .catalog()
                    .get_agent(id)
                    .map(|agent| agent.thread_id)
            })?,
        );
        let neighbor = runtime
            .create_thread_with_id("keep-cold", &project.id, "neighbor")
            .await?;
        let host = runtime.store.session_paths(&project.id, &root.id)?;
        runtime
            .store
            .record_thread_preparation(
                PreparationIdentity {
                    thread_id: root.id.clone(),
                    workspace_id: project.id.clone(),
                    parent_id: None,
                    root_id: root.id.clone(),
                },
                true,
            )
            .await?;
        assert!(
            runtime
                .session_of(&root.id)
                .and_then(|session| session.observed_thread(&root.id))
                .is_none()
        );
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
        runtime
            .store
            .database()
            .execute_unprepared(
                "CREATE TRIGGER pause_cold_delete BEFORE UPDATE ON studio_objects
         WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='removing'
         BEGIN SELECT RAISE(ABORT,'pause before physical deletion'); END",
            )
            .await?;
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
        let _endpoint = configure(&home).await?;
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
        let old_feed = runtime.open_conversation_feed(&root.id, 16).await?;
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
                .map(|root| root.thread_id.as_str()),
            Some(neighbor.id.as_str())
        );
        assert!(
            old_feed.reset_to_latest(16).await.is_err(),
            "an old ConversationFeed must lose its read qualification"
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
            assert!(
                sea_orm::ConnectionTrait::query_one_raw(
                    runtime.store.database(),
                    sea_orm::Statement::from_sql_and_values(
                        sea_orm::DatabaseBackend::Sqlite,
                        "SELECT agent_id FROM agent_evaluations WHERE agent_id=?",
                        [id.clone().into()]
                    )
                )
                .await?
                .is_none()
            );
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
        let (session, agent) =
            crate::studio::records::directory_facts_from_thread(&crate::Thread::from(root.clone()));
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
                .thread_snapshot(&root.id)?
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
            !runtime
                .store
                .open_history_reader(&neighbor.id)
                .await?
                .database_id()
                .is_empty()
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
    let _endpoint = configure(&home).await?;
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
    runtime
        .store
        .database()
        .execute_unprepared(
            "CREATE TRIGGER reject_deleted_phase BEFORE UPDATE ON studio_objects
     WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='dataDeleted'
     BEGIN SELECT RAISE(ABORT,'injected deletion commit failure'); END",
        )
        .await?;
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
        let _endpoint = configure(&home).await?;
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
            !runtime
                .store
                .open_history_reader(&neighbor.id)
                .await?
                .database_id()
                .is_empty()
        );
        runtime.shutdown_runtime().await?;
    }
    Ok(())
}

#[tokio::test]
async fn permanent_delete_releases_unregistered_worktree_without_touching_leftovers() -> Result<()>
{
    use crate::{
        agent::worktree::{
            ExecutorWorktreeBackend, WorktreeCreateSpec, WorktreeManager, WorktreeOwnership,
        },
        studio::{
            store::thread_archive::ArchiveScope,
            worktree::worktree_lease::{WorktreeLease, WorktreeLeaseOwnerKind, WorktreeLeaseState},
        },
    };
    for root_owned in [true, false] {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home).await?;
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
            std::sync::Arc::new(ExecutorWorktreeBackend::new(
                pl_remote_helper::Executor::local()?,
            )),
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
                crate::studio::store::directory::SessionDirectoryUpsert {
                    session_id: "owned-root".into(),
                    workspace_id: &project.id,
                    title: "owned",
                    mode: crate::mode::ThreadModeId::auto(),
                    workspace_mode: crate::ThreadWorkspaceMode::Worktree,
                    workspace_path: identity.root.clone(),
                    role: crate::config::ROOT_AGENT_ROUTE_KEY,
                },
            );
            runtime
                .agent_facility
                .product_events
                .commit_directory(delta)
                .await?;
            let root = crate::studio::ThreadRecord::from_directory_thread(
                crate::studio::records::thread_projection(&session, &agent, |id| {
                    runtime
                        .store
                        .catalog()
                        .get_agent(id)
                        .map(|agent| agent.thread_id)
                })?,
            );
            runtime.ensure_thread_owner(&root.id).await?;
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

        let neighbor = runtime
            .create_thread_with_id("neighbor", &project.id, "neighbor")
            .await?;
        runtime.shutdown_runtime().await?;
        git_fixture(
            &repository,
            &[
                "worktree",
                "remove",
                "--force",
                handle.path.to_str().unwrap(),
            ],
        )
        .await?;
        tokio::fs::create_dir_all(&handle.path).await?;
        let leftover = handle.path.join("keep.txt");
        tokio::fs::write(&leftover, b"unowned content").await?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        assert!(
            runtime
                .archive_thread("archive-orphan".into(), root.id.clone())
                .await
                .is_err()
        );
        runtime
            .delete_thread("delete-orphan".into(), root.id.clone())
            .await?
            .context("delete must complete")?;
        assert_eq!(tokio::fs::read(&leftover).await?, b"unowned content");
        assert!(runtime.store.read_thread(&root.id).await?.is_none());
        assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
        assert!(
            runtime
                .store
                .thread_archive(&ArchiveScope::Thread(root.id.clone()))
                .await?
                .is_none()
        );
        runtime.shutdown_runtime().await?;
        let reopened = StudioRuntime::initialize(options(&home)).await?;
        assert!(reopened.store.read_thread(&root.id).await?.is_none());
        assert!(reopened.store.read_thread(&neighbor.id).await?.is_some());
        assert_eq!(tokio::fs::read(&leftover).await?, b"unowned content");
        reopened.shutdown_runtime().await?;
    }
    Ok(())
}

mod required {
    //! The original private owner may stop for deletion without a successful preservation receipt.
    use super::*;
    use crate::studio::ThreadRecord;

    #[tokio::test]
    async fn permanent_delete_sealed_missing_public_member_retries_frozen_scope() -> Result<()> {
        use crate::studio::store::thread_archive::ArchiveScope;
        for missing_root in [false, true] {
            let temp = tempfile::tempdir()?;
            let home = temp.path().join("home");
            let _endpoint = configure(&home).await?;
            let workspace = temp.path().join("workspace");
            tokio::fs::create_dir_all(&workspace).await?;
            let runtime = StudioRuntime::initialize(options(&home)).await?;
            let project = runtime.open_project(&workspace).await?;
            let root = runtime
                .create_thread_with_id("missing-public-root", &project.id, "root")
                .await?;
            let middle =
                cold_child(&runtime, &root.clone().into(), "missing-public-middle").await?;
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
            runtime
                .store
                .database()
                .execute_unprepared(
                    "CREATE TRIGGER pause_missing_public BEFORE UPDATE ON studio_objects
         WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='removing'
         BEGIN SELECT RAISE(ABORT,'pause sealed public deletion'); END",
                )
                .await?;
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
            unadmitted.agent.thread_id = "outside-sealed-scope".into();
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
                    .find(|thread| thread.agent.thread_id == middle.id)
                    .unwrap();
                match field {
                    "workspace" => member.session.workspace_id = "different-workspace".into(),
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
    async fn permanent_delete_cold_private_preparations_join_and_retire_after_restart() -> Result<()>
    {
        use crate::studio::store::thread_preparation::{PreparationBinding, PreparationSave};
        for restart in [false, true] {
            let temp = tempfile::tempdir()?;
            let home = temp.path().join("home");
            let _endpoint = configure(&home).await?;
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
                .record_thread_preparation(
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
            runtime
                .store
                .database()
                .execute_unprepared(
                    "CREATE TRIGGER inspect_cold_private BEFORE UPDATE ON studio_objects
         WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='removing'
         BEGIN SELECT RAISE(ABORT,'inspect cold private stop'); END",
                )
                .await?;
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
        let _endpoint = configure(&home).await?;
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
            .record_thread_preparation(identity, false)
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
    #[tokio::test]
    async fn permanent_delete_private_required_save_records_real_stop_without_save_ack()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home).await?;
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let project = runtime.open_project(&workspace).await?;
        let root = runtime
            .create_thread_with_id("delete-private-root", &project.id, "root")
            .await?;
        runtime.ensure_thread_owner(&root.id).await?.flush().await?;
        let id = "delete-private-required";
        let mut private = crate::Thread::placeholder(id);
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
        let sink = ThreadStorageSink::new(runtime.store.clone(), private).await?;
        let current_file = runtime.store.registered_session_paths(id)?.current_file();
        tokio::fs::create_dir_all(&current_file).await?;
        let projection = spawn_live_projection_for_thread(runtime.store.clone(), id);
        let mut spec =
            crate::test_support::archive_test_spec(id.into(), Some(root.id.clone()), &workspace);
        spec.history_sink = Some(sink);
        spec.initial_extensions.insert(
            "fixture.private-required".into(),
            pl_core::context::OpaquePayload::text("valid initialization"),
        );
        let thread = runtime
            .session_for_roots(std::slice::from_ref(&root.id))?
            .assemble(spec)
            .await?;
        let conversation = runtime.store.conversation_store(id).await?;
        let current_writer = runtime
            .store
            .thread_persistence()
            .current_writer(
                id,
                runtime
                    .store
                    .registered_session_paths(id)?
                    .root()
                    .to_path_buf(),
            )
            .await?;
        let save_error = tokio::time::timeout(
            std::time::Duration::from_secs(10),
            conversation.flush_current(thread.runtime_epoch()),
        )
        .await?
        .expect_err("the private owner must retain its real Current failure");
        ensure!(
            format!("{save_error:#}").contains("current.json"),
            "{save_error:#}"
        );
        let record = runtime
            .store
            .thread_preparation(id)
            .await?
            .context("retained private owner")?;
        assert_eq!(record.save, PreparationSave::Required);
        assert!(!record.stopped);
        let before = current_writer
            .snapshot()
            .error
            .map(|error| error.to_string())
            .context("blocked private current save failure")?;
        assert!(
            runtime
                .session_of(id)
                .and_then(|session| session.observed_thread(id))
                .is_some()
        );
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
            current_writer
                .snapshot()
                .error
                .map(|error| error.to_string()),
            Some(before),
            "deletion must not retry or replace the original Current failure"
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

    #[tokio::test]
    async fn permanent_delete_unpublished_bound_root_retries_after_restart() -> Result<()> {
        use crate::studio::store::thread_archive::ArchiveScope;
        for (restart, remote) in [(false, false), (true, false), (false, true), (true, true)] {
            let temp = tempfile::tempdir()?;
            let home = temp.path().join("home");
            let _endpoint = configure(&home).await?;
            let workspace = temp.path().join("workspace");
            tokio::fs::create_dir_all(&workspace).await?;
            let runtime = StudioRuntime::initialize(options(&home)).await?;
            let project = runtime.open_project(&workspace).await?;
            // Publish only directory identity: the original preparation never attached storage.
            let (delta, session, agent) = DirectoryDelta::register_session(
                crate::studio::store::directory::SessionDirectoryUpsert {
                    session_id: "private-root".into(),
                    workspace_id: &project.id,
                    title: "root",
                    mode: crate::mode::ThreadModeId::auto(),
                    workspace_mode: crate::ThreadWorkspaceMode::Local,
                    workspace_path: workspace.to_string_lossy().into_owned(),
                    role: crate::config::ROOT_AGENT_ROUTE_KEY,
                },
            );
            runtime
                .agent_facility
                .product_events
                .commit_directory(delta)
                .await?;
            let root = ThreadRecord::from_directory_thread(
                crate::studio::records::thread_projection(&session, &agent, |id| {
                    runtime
                        .store
                        .catalog()
                        .get_agent(id)
                        .map(|agent| agent.thread_id)
                })?,
            );
            let neighbor = runtime
                .create_thread_with_id("private-root-neighbor", &project.id, "keep")
                .await?;
            runtime
                .store
                .record_thread_preparation(
                    PreparationIdentity {
                        thread_id: root.id.clone(),
                        workspace_id: project.id.clone(),
                        parent_id: None,
                        root_id: root.id.clone(),
                    },
                    false,
                )
                .await?;
            let binding = if remote {
                WorkspaceIdentity::canonical(
                    WorkspaceEndpoint::Ssh {
                        host: "fixture.invalid".into(),
                        port: 22,
                        username: "fixture".into(),
                    },
                    "/isolated/workspace".into(),
                )?
            } else {
                WorkspaceIdentity::canonical(
                    WorkspaceEndpoint::Local,
                    dunce::canonicalize(&workspace)?
                        .to_string_lossy()
                        .into_owned(),
                )?
            };
            runtime
                .store
                .bind_thread_preparation(&root.id, &binding)
                .await?;
            let execution = workspace.join(SessionFiles::new(&root.id).root());
            tokio::fs::create_dir_all(&execution).await?;
            tokio::fs::write(execution.join("marker"), b"remove").await?;
            let host = runtime.store.session_paths(&project.id, &root.id)?;
            tokio::fs::create_dir_all(host.root()).await?;
            tokio::fs::write(host.root().join("marker"), b"host").await?;
            runtime
                .agent_facility
                .product_events
                .drain_directory_writes()
                .await?;
            // Retirement must release resources without writing a child-failure projection.
            // The directory becomes writable again before actual deletion publication.
            let catalog = runtime.store.paths().catalog_file();
            let catalog_bytes = tokio::fs::read(&catalog).await?;
            tokio::fs::remove_file(&catalog).await?;
            tokio::fs::create_dir(&catalog).await?;
            runtime
                .store
                .database()
                .execute_unprepared(
                    "CREATE TRIGGER pause_private_root BEFORE UPDATE ON studio_objects
         WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='removing'
         BEGIN SELECT RAISE(ABORT,'pause private root deletion'); END",
                )
                .await?;
            let error = runtime
                .delete_thread("pause-private-root".into(), root.id.clone())
                .await
                .expect_err("pause before removal");
            ensure!(
                format!("{error:#}").contains("pause private root deletion"),
                "{error:#}"
            );
            let archive = runtime
                .store
                .thread_archive(&ArchiveScope::Thread(root.id.clone()))
                .await?
                .unwrap();
            assert!(archive.members.is_empty());
            assert_eq!(archive.private_members.len(), 1);
            let preparation = runtime.store.thread_preparation(&root.id).await?.unwrap();
            assert!(preparation.stopped && preparation.retired && preparation.deletion_stopped);
            assert!(!preparation.published && preparation.storage.is_none());
            assert!(execution.exists());
            assert_eq!(
                runtime
                    .store
                    .catalog()
                    .get_agent(&root.id)
                    .unwrap()
                    .native_status(),
                agent.native_status()
            );
            tokio::fs::remove_dir(&catalog).await?;
            tokio::fs::write(&catalog, catalog_bytes).await?;
            runtime
                .store
                .database()
                .execute_unprepared("DROP TRIGGER pause_private_root")
                .await?;
            let runtime = if restart {
                runtime.shutdown_runtime().await?;
                StudioRuntime::initialize(options(&home)).await?
            } else {
                runtime
            };
            let result = runtime
                .delete_thread("finish-private-root".into(), root.id.clone())
                .await;
            if remote {
                // No real SSH service is contacted. Retirement must finish even when its original
                // endpoint is unavailable; independent host removal still proceeds, with remote
                // cleanup retained as a real failure rather than silently falling back to local.
                let error = result.expect_err("unconfigured original endpoint must remain pending");
                ensure!(
                    format!("{error:#}")
                        .contains("delete frozen SSH endpoint is no longer configured"),
                    "{error:#}"
                );
                let operation = runtime.store.thread_delete(&root.id).await?.unwrap();
                assert_eq!(operation.phase, DeletePhase::Removing);
                assert!(operation.members[0].host_deleted);
                assert!(!operation.members[0].execution_deleted);
                assert!(execution.exists());
                assert!(runtime.store.read_thread(&root.id).await?.is_some());
            } else {
                result?.context("root deletion must finish")?;
                assert!(!execution.exists());
                assert!(runtime.store.read_thread(&root.id).await?.is_none());
            }
            assert!(!host.root().exists());
            assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
            runtime.shutdown_runtime().await?;
        }
        Ok(())
    }
}

mod auxiliary {
    //! Deletion isolates undecodable auxiliary rows while ordinary reads remain strict.
    use super::*;
    use std::sync::{Arc, Mutex};
    use tracing::{Subscriber, field::Visit, span};

    #[derive(Clone, Default)]
    struct Captured(Arc<Mutex<Vec<String>>>);

    impl Visit for Captured {
        fn record_str(&mut self, field: &tracing::field::Field, value: &str) {
            self.0
                .lock()
                .unwrap()
                .push(format!("{}={value}", field.name()));
        }
        fn record_debug(&mut self, field: &tracing::field::Field, value: &dyn std::fmt::Debug) {
            self.0
                .lock()
                .unwrap()
                .push(format!("{}={value:?}", field.name()));
        }
    }

    impl Subscriber for Captured {
        fn enabled(&self, metadata: &tracing::Metadata<'_>) -> bool {
            metadata.target().starts_with("pl_studio_runtime")
        }
        fn new_span(&self, attributes: &span::Attributes<'_>) -> span::Id {
            attributes.record(&mut self.clone());
            static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);
            span::Id::from_u64(NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed))
        }
        fn record(&self, _: &span::Id, values: &span::Record<'_>) {
            values.record(&mut self.clone());
        }
        fn record_follows_from(&self, _: &span::Id, _: &span::Id) {}
        fn event(&self, event: &tracing::Event<'_>) {
            event.record(&mut self.clone());
        }
        fn enter(&self, _: &span::Id) {}
        fn exit(&self, _: &span::Id) {}
    }

    async fn damaged_aux(
        runtime: &StudioRuntime,
        kind: &str,
        owner: &str,
        object: &str,
        schema: i64,
        payload: &str,
    ) -> Result<()> {
        runtime
            .store
            .database()
            .execute_raw(Statement::from_sql_and_values(
                DatabaseBackend::Sqlite,
                "INSERT OR REPLACE INTO studio_objects
     (owner_kind,owner_id,object_kind,revision,schema_version,payload_json,payload_hash,updated_at)
     VALUES (?,?,?,1,?,?,?,0)",
                [
                    kind.into(),
                    owner.into(),
                    object.into(),
                    schema.into(),
                    payload.into(),
                    pl_core::context::content_hash(payload.as_bytes()).into(),
                ],
            ))
            .await?;
        Ok(())
    }

    #[tokio::test]
    async fn permanent_delete_skips_bad_aux_preserves_unknown_rows_and_logs_safe_reasons()
    -> Result<()> {
        use crate::studio::store::thread_archive::ArchiveScope;
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home).await?;
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let project = runtime.open_project(&workspace).await?;
        let root = runtime
            .create_thread_with_id("bad-aux-root", &project.id, "root")
            .await?;
        let neighbor = runtime
            .create_thread_with_id("bad-aux-neighbor", &project.id, "keep")
            .await?;
        let secret = "SYNTHETIC-SECRET-USER-CONTENT";
        let broken = format!(r#"{{"rootId":"{secret}""#);
        let project_scope = ArchiveScope::Workspace(project.id.clone()).key();
        let neighbor_scope = ArchiveScope::Thread(neighbor.id.clone()).key();
        let root_scope = ArchiveScope::Thread(root.id.clone()).key();
        for scope in [&project_scope, &neighbor_scope, &root_scope] {
            damaged_aux(&runtime, "archive", scope, "threadArchive", 2, &broken).await?;
        }
        damaged_aux(
            &runtime,
            "thread",
            "unknown-private",
            "threadPreparation",
            2,
            &broken,
        )
        .await?;
        let invalid = serde_json::json!({
            "identity": { "threadId": "invalid-stop", "workspaceId": project.id,
                "parentId": neighbor.id, "rootId": neighbor.id },
            "revision": 1, "binding": { "state": "unbound" },
            "save": "required", "storage": null, "disposition": "pending",
            "stopped": true, "retired": false, "published": false
        });
        // Use the actual binding representation so this reaches validation, rather than JSON shape.
        let mut invalid = invalid;
        invalid["binding"] = serde_json::to_value(
            crate::studio::store::thread_preparation::PreparationBinding::Unbound,
        )?;
        damaged_aux(
            &runtime,
            "thread",
            "invalid-stop",
            "threadPreparation",
            2,
            &invalid.to_string(),
        )
        .await?;
        assert!(runtime.store.thread_preparations().await.is_err());
        assert!(runtime.store.thread_archives().await.is_err());
        let captured = Captured::default();
        let dispatch = tracing::Dispatch::new(captured.clone());
        let _capture = tracing::dispatcher::set_default(&dispatch);
        let failed = workspace.join(SessionFiles::new(&root.id).root());
        if failed.exists() {
            tokio::fs::remove_dir_all(&failed).await?;
        }
        tokio::fs::create_dir_all(failed.parent().unwrap()).await?;
        tokio::fs::write(&failed, secret).await?;
        runtime
            .delete_thread("safe-aux-failed-correlation".into(), root.id.clone())
            .await
            .expect_err("preserve the wrong target while logging safe failure metadata");
        tokio::fs::remove_file(&failed).await?;
        runtime
            .delete_thread("safe-aux-correlation".into(), root.id.clone())
            .await?
            .unwrap();
        let records = captured.0.lock().unwrap().join("\n");
        for expected in [
            "deletion_id=safe-aux-correlation",
            "stage=",
            "member=",
            "reason=aux_json",
            "reason=preparation_save_ack",
            "decision=preserve_unknown_skip",
            "outcome=skipped",
            "elapsed_ms=",
            "line=",
            "column=",
            "outcome=incomplete",
            "decision=continue_independent",
        ] {
            assert!(
                records.contains(expected),
                "missing {expected} in {records}"
            );
        }
        assert!(
            !records.contains(secret),
            "raw auxiliary body leaked into diagnostics"
        );
        assert!(runtime.store.read_thread(&root.id).await?.is_none());
        assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
        // Shared objects whose scope cannot be decoded retain exactly their original bytes.
        let rows = runtime
            .store
            .database()
            .query_all_raw(Statement::from_sql_and_values(
                DatabaseBackend::Sqlite,
                "SELECT payload_json FROM studio_objects WHERE
     (owner_kind='archive' AND owner_id IN (?,?))
     OR (owner_id='unknown-private' AND object_kind='threadPreparation')",
                [project_scope.into(), neighbor_scope.into()],
            ))
            .await?;
        assert_eq!(rows.len(), 3);
        for row in rows {
            assert_eq!(row.try_get::<String>("", "payload_json")?, broken);
        }
        assert!(runtime.store.thread_preparations().await.is_err());
        runtime.shutdown_runtime().await?;
        Ok(())
    }
}

mod recovery {
    //! Durable intent failures must not contaminate independently committed deletion progress.
    use super::*;
    use crate::studio::store::thread_archive::{ArchiveScope, ThreadArchiveOperation};
    use std::sync::Arc;

    async fn reject_intent(
        runtime: &StudioRuntime,
        owner: &str,
        object: &str,
        target: &str,
        collection: &str,
        identity: &str,
        flag: &str,
    ) -> Result<()> {
        // The first intent fails at revision N+1. A buggy caller's later independent save at
        // N+2 succeeds, exposing any unsaved in-memory flag that leaked into that commit.
        let sql = format!(
            "CREATE TRIGGER reject_first_intent BEFORE UPDATE ON studio_objects
     WHEN NEW.owner_id='{owner}' AND NEW.object_kind='{object}'
      AND NEW.revision=OLD.revision+1
      AND EXISTS (SELECT 1 FROM json_each(NEW.payload_json,'$.{collection}')
        WHERE json_extract(value,'$.{identity}')='{target}' AND json_extract(value,'$.{flag}')=1)
      AND NOT EXISTS (SELECT 1 FROM json_each(OLD.payload_json,'$.{collection}')
        WHERE json_extract(value,'$.{identity}')='{target}' AND json_extract(value,'$.{flag}')=1)
     BEGIN SELECT RAISE(ABORT,'one intent persistence failure'); END"
        );
        runtime.store.database().execute_unprepared(&sql).await?;
        Ok(())
    }

    #[tokio::test]
    async fn permanent_delete_progress_failure_keeps_session_targets_retryable() -> Result<()> {
        for flag in [
            "executionRemovalStarted",
            "hostRemovalStarted",
            "executionDeleted",
            "hostDeleted",
        ] {
            let temp = tempfile::tempdir()?;
            let home = temp.path().join("home");
            let _endpoint = configure(&home).await?;
            let workspace = temp.path().join("workspace");
            tokio::fs::create_dir_all(&workspace).await?;
            let runtime = StudioRuntime::initialize(options(&home)).await?;
            let project = runtime.open_project(&workspace).await?;
            let root = runtime
                .create_thread_with_id("intent-root", &project.id, "root")
                .await?;
            let child = cold_child(&runtime, &root.clone().into(), "intent-child").await?;
            for id in [&root.id, &child.id] {
                let host = runtime.store.session_paths(&project.id, id)?;
                tokio::fs::create_dir_all(host.root()).await?;
                tokio::fs::write(host.root().join("marker"), id).await?;
                let execution = workspace.join(SessionFiles::new(id).root());
                tokio::fs::create_dir_all(&execution).await?;
                tokio::fs::write(execution.join("marker"), id).await?;
            }
            reject_intent(
                &runtime,
                &root.id,
                "threadDelete",
                &root.id,
                "members",
                "identity.threadId",
                flag,
            )
            .await?;
            let error = runtime
                .delete_thread("reject-session-intent".into(), root.id.clone())
                .await
                .expect_err("the failed item remains pending while independent members finish");
            assert!(
                format!("{error:#}").contains("one intent persistence failure"),
                "{error:#}"
            );
            let operation = runtime.store.thread_delete(&root.id).await?.unwrap();
            assert_eq!(operation.phase, DeletePhase::Removing);
            let member = operation
                .members
                .iter()
                .find(|member| member.identity.thread_id == root.id)
                .unwrap();
            let completion = flag.ends_with("Deleted");
            let failed_path = if flag.starts_with("execution") {
                assert_eq!(member.execution_removal_started, completion);
                assert!(!member.execution_deleted && member.host_deleted);
                workspace.join(SessionFiles::new(&root.id).root())
            } else {
                assert_eq!(member.host_removal_started, completion);
                assert!(!member.host_deleted && member.execution_deleted);
                member.host_session.clone()
            };
            if completion {
                assert!(
                    !failed_path.exists(),
                    "physical removal precedes the failed completion ACK"
                );
            } else {
                assert!(
                    failed_path.join("marker").is_file(),
                    "failed intent must not perform removal"
                );
            }
            let independent = operation
                .members
                .iter()
                .find(|member| member.identity.thread_id == child.id)
                .unwrap();
            assert!(independent.host_deleted && independent.execution_deleted);
            runtime
                .store
                .database()
                .execute_unprepared("DROP TRIGGER reject_first_intent")
                .await?;
            runtime
                .delete_thread("retry-session-intent".into(), root.id)
                .await?
                .unwrap();
            assert!(!failed_path.exists());
            runtime.shutdown_runtime().await?;
        }
        Ok(())
    }

    async fn private_worktrees(
        runtime: &StudioRuntime,
        repository: &Path,
        workspace_id: &str,
        root: &str,
        ids: &[&str],
    ) -> Result<Vec<std::path::PathBuf>> {
        use crate::{
            agent::worktree::{
                ExecutorWorktreeBackend, WorktreeCreateSpec, WorktreeManager, WorktreeOwnership,
            },
            studio::worktree::worktree_lease::{
                WorktreeLease, WorktreeLeaseOwnerKind, WorktreeLeaseState,
            },
        };
        let manager = WorktreeManager::new(
            repository.to_owned(),
            Arc::new(ExecutorWorktreeBackend::new(
                pl_remote_helper::Executor::local()?,
            )),
        );
        let head = manager.resolve_head(repository).await?;
        let mut paths = Vec::new();
        for id in ids {
            let handle = manager
                .create(WorktreeCreateSpec {
                    repo_root: repository.to_owned(),
                    root_thread_id: root.into(),
                    ownership: WorktreeOwnership::Child {
                        child_id: (*id).into(),
                    },
                    base_commit: head.clone(),
                })
                .await?;
            let identity = WorkspaceIdentity::canonical(
                WorkspaceEndpoint::Local,
                handle.path.to_string_lossy().into_owned(),
            )?;
            runtime
                .store
                .record_thread_preparation(
                    PreparationIdentity {
                        thread_id: (*id).into(),
                        workspace_id: workspace_id.into(),
                        root_id: root.into(),
                        parent_id: Some(root.into()),
                    },
                    false,
                )
                .await?;
            runtime.store.bind_thread_preparation(id, &identity).await?;
            runtime.store.bind_workspace_identity(id, &identity).await?;
            let mut lease = WorktreeLease {
                revision: 1,
                state: WorktreeLeaseState::Prepared,
                owner_kind: WorktreeLeaseOwnerKind::Child,
                owner_thread_id: (*id).into(),
                root_thread_id: root.into(),
                workspace_id: workspace_id.into(),
                ssh_alias: None,
                repository_root: repository.to_string_lossy().into_owned(),
                path: identity.root.clone(),
                base_commit: head.clone(),
            };
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
            tokio::fs::write(handle.path.join("marker"), b"original worktree").await?;
            paths.push(handle.path);
        }
        Ok(paths)
    }

    async fn repository_fixture(path: &Path) -> Result<()> {
        tokio::fs::create_dir_all(path).await?;
        git_fixture(path, &["init", "--quiet"]).await?;
        git_fixture(
            path,
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
        Ok(())
    }

    #[tokio::test]
    async fn permanent_delete_progress_failure_keeps_multiple_worktrees_retryable() -> Result<()> {
        for flag in ["removalStarted", "cleaned"] {
            let temp = tempfile::tempdir()?;
            let home = temp.path().join("home");
            let _endpoint = configure(&home).await?;
            let repository = temp.path().join("repository");
            repository_fixture(&repository).await?;
            let repository = dunce::canonicalize(repository)?;
            let runtime = StudioRuntime::initialize(options(&home)).await?;
            let project = runtime.open_project(&repository).await?;
            let root = runtime
                .create_thread_with_id("worktree-intent-root", &project.id, "root")
                .await?;
            let paths = private_worktrees(
                &runtime,
                &repository,
                &project.id,
                &root.id,
                &["worktree-intent-a", "worktree-intent-b"],
            )
            .await?;
            let scope = ArchiveScope::Thread(root.id.clone());
            reject_intent(
                &runtime,
                &scope.key(),
                "threadArchive",
                "worktree-intent-a",
                "worktrees",
                "lease.ownerThreadId",
                flag,
            )
            .await?;
            let error = runtime
                .delete_thread("reject-worktree-intent".into(), root.id.clone())
                .await
                .expect_err("first worktree intent fails, second worktree still completes");
            assert!(
                format!("{error:#}").contains("one intent persistence failure"),
                "{error:#}"
            );
            let archive = runtime.store.thread_archive(&scope).await?.unwrap();
            let first = archive
                .worktrees
                .iter()
                .find(|entry| entry.lease.owner_thread_id == "worktree-intent-a")
                .unwrap();
            assert!(!first.cleaned);
            if flag == "removalStarted" {
                assert!(!first.removal_started && first.common_dir.is_none());
                assert!(paths[0].join("marker").is_file());
            } else {
                assert!(first.removal_started && first.common_dir.is_some());
                assert!(
                    !paths[0].exists(),
                    "physical removal finished before its ACK failed"
                );
            }
            let second = archive
                .worktrees
                .iter()
                .find(|entry| entry.lease.owner_thread_id == "worktree-intent-b")
                .unwrap();
            assert!(second.removal_started && second.cleaned);
            assert!(!paths[1].exists());
            let operation = runtime.store.thread_delete(&root.id).await?.unwrap();
            assert!(operation.members.iter().all(|member| member.host_deleted));
            let member = operation
                .members
                .iter()
                .find(|member| member.identity.thread_id == "worktree-intent-a")
                .unwrap();
            assert!(
                !member.execution_deleted,
                "uncommitted progress cannot acknowledge execution deletion"
            );
            let public = crate::error_mapping::studio_error_from_anyhow_ref(
                &runtime
                    .store
                    .history(&root.id)
                    .await
                    .err()
                    .context("reads must be revoked")?,
            );
            assert_eq!(public.code, crate::StudioErrorCode::Conflict);
            assert!(public.message.contains("重试删除"));
            runtime
                .store
                .database()
                .execute_unprepared("DROP TRIGGER reject_first_intent")
                .await?;
            runtime
                .delete_thread("retry-worktree-intent".into(), root.id)
                .await?
                .unwrap();
            assert!(paths.iter().all(|path| !path.exists()));
            assert!(repository.join(".git").is_dir());
            runtime.shutdown_runtime().await?;
        }
        Ok(())
    }

    async fn pause_sealed(runtime: &StudioRuntime) -> Result<()> {
        runtime
            .store
            .database()
            .execute_unprepared(
                "CREATE TRIGGER pause_recovery BEFORE UPDATE ON studio_objects
     WHEN NEW.object_kind='threadDelete' AND json_extract(NEW.payload_json,'$.phase')='removing'
     BEGIN SELECT RAISE(ABORT,'inspect frozen recovery'); END",
            )
            .await?;
        Ok(())
    }

    async fn lose_archive(
        runtime: &StudioRuntime,
        scope: &ArchiveScope,
        corrupt: bool,
    ) -> Result<()> {
        let sql = if corrupt {
            "UPDATE studio_objects SET payload_json='broken archive',payload_hash='invalid'
     WHERE owner_kind='archive' AND owner_id=? AND object_kind='threadArchive'"
        } else {
            "DELETE FROM studio_objects WHERE owner_kind='archive' AND owner_id=? AND object_kind='threadArchive'"
        };
        runtime
            .store
            .database()
            .execute_raw(Statement::from_sql_and_values(
                DatabaseBackend::Sqlite,
                sql,
                [scope.key().into()],
            ))
            .await?;
        Ok(())
    }

    #[tokio::test]
    async fn permanent_delete_recovers_frozen_members_without_canonical_or_archive_aux()
    -> Result<()> {
        for corrupt in [false, true] {
            let temp = tempfile::tempdir()?;
            let home = temp.path().join("home");
            let _endpoint = configure(&home).await?;
            let workspace = temp.path().join("workspace");
            tokio::fs::create_dir_all(&workspace).await?;
            let runtime = StudioRuntime::initialize(options(&home)).await?;
            let project = runtime.open_project(&workspace).await?;
            let root = runtime
                .create_thread_with_id("aux-recovery-root", &project.id, "root")
                .await?;
            let child = cold_child(&runtime, &root.clone().into(), "aux-recovery-child").await?;
            let neighbor = runtime
                .create_thread_with_id("aux-recovery-neighbor", &project.id, "keep")
                .await?;
            assert!(runtime.store.thread_preparation(&child.id).await?.is_none());
            let execution = workspace.join(SessionFiles::new(&child.id).root());
            tokio::fs::create_dir_all(&execution).await?;
            tokio::fs::write(execution.join("marker"), b"frozen child").await?;
            pause_sealed(&runtime).await?;
            let first = runtime
                .delete_thread("seal-aux-recovery".into(), root.id.clone())
                .await
                .unwrap_err();
            assert!(
                format!("{first:#}").contains("inspect frozen recovery"),
                "{first:#}"
            );
            let frozen = runtime.store.thread_delete(&root.id).await?.unwrap();
            let scope = ArchiveScope::Thread(root.id.clone());
            runtime
                .agent_facility
                .product_events
                .drain_directory_writes()
                .await?;
            let catalog = runtime.store.catalog();
            let mut agents = catalog.agents();
            agents.retain(|agent| agent.thread_id != child.id);
            catalog
                .test_restore_records(catalog.sessions(), agents)
                .await?;
            lose_archive(&runtime, &scope, corrupt).await?;
            runtime
        .store
        .database()
        .execute_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "DELETE FROM studio_objects WHERE owner_id=? AND object_kind='threadPreparation'",
            [root.id.clone().into()],
        ))
        .await?;
            let error = runtime
                .delete_thread("inspect-aux-recovery".into(), root.id.clone())
                .await
                .unwrap_err();
            assert!(
                format!("{error:#}").contains("inspect frozen recovery"),
                "{error:#}"
            );
            let restored = runtime.store.thread_delete(&root.id).await?.unwrap();
            assert!(
                runtime.store.thread_preparation(&root.id).await?.is_none(),
                "durable deletion must not recreate an absent preparation as unbound"
            );
            assert_eq!(restored.thread_ids, frozen.thread_ids);
            for member in &frozen.members {
                let current = restored
                    .members
                    .iter()
                    .find(|current| current.identity == member.identity)
                    .unwrap();
                assert_eq!(current.host_session, member.host_session);
                assert_eq!(current.execution, member.execution);
            }
            if corrupt {
                let raw = runtime.store.database().query_one_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "SELECT payload_json FROM studio_objects WHERE owner_kind='archive' AND owner_id=? AND object_kind='threadArchive'",
            [scope.key().into()],
        )).await?.unwrap();
                assert_eq!(raw.try_get::<String>("", "payload_json")?, "broken archive");
            }
            runtime
                .store
                .database()
                .execute_unprepared("DROP TRIGGER pause_recovery")
                .await?;
            runtime
                .delete_thread("finish-aux-recovery".into(), root.id)
                .await?
                .unwrap();
            assert!(!execution.exists());
            assert!(runtime.store.read_thread(&neighbor.id).await?.is_some());
            runtime.shutdown_runtime().await?;
        }
        Ok(())
    }

    #[tokio::test]
    async fn permanent_delete_keeps_unavailable_worktree_progress_blocked() -> Result<()> {
        for corrupt in [false, true] {
            let temp = tempfile::tempdir()?;
            let home = temp.path().join("home");
            let _endpoint = configure(&home).await?;
            let repository = temp.path().join("repository");
            repository_fixture(&repository).await?;
            let repository = dunce::canonicalize(repository)?;
            let runtime = StudioRuntime::initialize(options(&home)).await?;
            let project = runtime.open_project(&repository).await?;
            let root = runtime
                .create_thread_with_id("unknown-git-root", &project.id, "root")
                .await?;
            let paths = private_worktrees(
                &runtime,
                &repository,
                &project.id,
                &root.id,
                &["unknown-git-child"],
            )
            .await?;
            pause_sealed(&runtime).await?;
            assert!(
                runtime
                    .delete_thread("seal-unknown-git".into(), root.id.clone())
                    .await
                    .is_err()
            );
            let scope = ArchiveScope::Thread(root.id.clone());
            let original: ThreadArchiveOperation =
                runtime.store.thread_archive(&scope).await?.unwrap();
            runtime
                .store
                .database()
                .execute_unprepared("DROP TRIGGER pause_recovery")
                .await?;
            lose_archive(&runtime, &scope, corrupt).await?;
            let error = runtime
                .delete_thread("block-unknown-git".into(), root.id.clone())
                .await
                .unwrap_err();
            assert!(
                format!("{error:#}").contains("no readable original owner"),
                "{error:#}"
            );
            assert!(paths[0].join("marker").is_file());
            assert_eq!(
                runtime.store.thread_delete(&root.id).await?.unwrap().phase,
                DeletePhase::Sealed
            );
            // Restore the exact original owner only to release this fixture's managed resources.
            lose_archive(&runtime, &scope, false).await?;
            runtime.store.save_thread_archive(&original).await?;
            runtime
                .delete_thread("finish-known-git".into(), root.id)
                .await?
                .unwrap();
            runtime.shutdown_runtime().await?;
        }
        Ok(())
    }
}

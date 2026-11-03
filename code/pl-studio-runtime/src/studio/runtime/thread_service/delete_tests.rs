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

async fn cold_child(
    runtime: &StudioRuntime,
    root: &crate::studio::ThreadRecord,
) -> Result<pl_protocol::Thread> {
    let mut child = pl_protocol::Thread::placeholder("delete-archived-child");
    child.agent_path = format!("{}/{}", root.id, child.id);
    child.workspace_id = root.workspace_id.clone();
    child.workspace_path = root.workspace_path.clone();
    child.root_thread_id = root.id.clone();
    child.parent_thread_id = Some(root.id.clone());
    runtime
        .agent_facility
        .product_events
        .commit_directory(DirectoryDelta {
            thread_upserts: vec![child.clone()],
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
    runtime
        .agent_facility
        .product_events
        .commit_directory(DirectoryDelta::archive_threads(vec![child.id.clone()]))
        .await?;
    Ok(child)
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
        let child = cold_child(&runtime, &root).await?;
        for (agent, parent) in [(&child.id, &root.id), (&neighbor.id, &neighbor.id)] {
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
            .confirm_preparation_retirement(&private.thread_id)
            .await?;
        let ids = [&root.id, &child.id, &private.thread_id];
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
        let private_host = runtime
            .store
            .session_paths(&project.id, &private.thread_id)?;
        assert!(
            runtime
                .delete_thread("reject-child".into(), child.id.clone())
                .await
                .is_err()
        );
        let result = runtime
            .delete_thread("permanent-delete".into(), root.id.clone())
            .await?
            .context("delete reply")?;
        assert_eq!(result.result.deleted_thread_ids.len(), 3);
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
        for host in [root_host, child_host, private_host] {
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
        assert!(
            runtime
                .store
                .read_agent_evaluation(&child.id)
                .await?
                .is_none()
        );
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
        let mut delayed = pl_protocol::Thread::from(root.clone());
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
            let (delta, protocol) = DirectoryDelta::register_root_thread(
                "owned-root".into(),
                &project.id,
                "owned",
                pl_protocol::ThreadModeId::simple(),
                pl_protocol::ThreadWorkspaceMode::Worktree,
                identity.root.clone(),
            );
            runtime
                .agent_facility
                .product_events
                .commit_directory(delta)
                .await?;
            let root = crate::studio::ThreadRecord::from_directory_thread(protocol);
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

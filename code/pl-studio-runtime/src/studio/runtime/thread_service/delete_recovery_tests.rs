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
async fn permanent_delete_intent_failure_keeps_session_targets_retryable() -> Result<()> {
    for flag in ["executionRemovalStarted", "hostRemovalStarted"] {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home)?;
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
        let failed_path = if flag == "executionRemovalStarted" {
            assert!(!member.execution_removal_started);
            assert!(!member.execution_deleted && member.host_deleted);
            workspace.join(SessionFiles::new(&root.id).root())
        } else {
            assert!(!member.host_removal_started);
            assert!(!member.host_deleted && member.execution_deleted);
            member.host_session.clone()
        };
        assert!(
            failed_path.join("marker").is_file(),
            "the failed intent never called physical removal"
        );
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
        studio::agent_host::worktree_lease::{
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
            .begin_removal_preparation(
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
async fn permanent_delete_intent_failure_keeps_multiple_worktrees_retryable() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let _endpoint = configure(&home)?;
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
        "removalStarted",
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
    assert!(!first.removal_started && !first.cleaned && first.common_dir.is_none());
    let second = archive
        .worktrees
        .iter()
        .find(|entry| entry.lease.owner_thread_id == "worktree-intent-b")
        .unwrap();
    assert!(second.removal_started && second.cleaned);
    assert!(paths[0].join("marker").is_file());
    assert!(!paths[1].exists());
    let operation = runtime.store.thread_delete(&root.id).await?.unwrap();
    assert!(operation.members.iter().all(|member| member.host_deleted));
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

async fn lose_archive(runtime: &StudioRuntime, scope: &ArchiveScope, corrupt: bool) -> Result<()> {
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
async fn permanent_delete_recovers_frozen_members_without_canonical_or_archive_aux() -> Result<()> {
    for corrupt in [false, true] {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home)?;
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
        let _endpoint = configure(&home)?;
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
        let original: ThreadArchiveOperation = runtime.store.thread_archive(&scope).await?.unwrap();
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

//! Real archive settlement and durable recovery at the Runtime boundary.

use super::super::StudioRuntime;
use super::test_support::{configure, git_fixture, options};
use crate::studio::ThreadVisibility;
use anyhow::{Context, Result, ensure};
use std::path::Path;

mod private_preparation;

#[tokio::test]
async fn archive_private_preparation_failed_retirement_survives_restart_and_preserves_delivery()
-> Result<()> {
    use crate::studio::{
        store::{
            thread_archive::{ArchivePhase, ArchiveScope},
            thread_preparation::{PreparationBinding, PreparationIdentity},
        },
        worktree::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity},
    };
    use crate::test_support::storage::close_factory;
    use sea_orm::ConnectionTrait;
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let _endpoint = configure(&home).await?;
    let repository = temp.path().join("repository");
    let checkout = temp.path().join("private-worktree");
    tokio::fs::create_dir_all(&repository).await?;
    for args in [
        vec!["init", "--quiet"],
        vec![
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
        vec![
            "worktree",
            "add",
            "--quiet",
            "--detach",
            checkout.to_str().unwrap(),
            "HEAD",
        ],
    ] {
        let output = tokio::process::Command::new("git")
            .args(args)
            .current_dir(&repository)
            .output()
            .await?;
        ensure!(
            output.status.success(),
            "isolated Git fixture: {:?}",
            output
        );
    }
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let workspace = runtime.open_project(&repository).await?;
    let root = runtime
        .create_thread_with_id("private-root", &workspace.id, "root")
        .await?;
    runtime.ensure_thread_owner(&root.id).await?.flush().await?;
    let identity = PreparationIdentity {
        thread_id: "unpublished-physical-child".into(),
        workspace_id: workspace.id.clone(),
        parent_id: Some(root.id.clone()),
        root_id: root.id.clone(),
    };
    let binding = WorkspaceIdentity::canonical(
        WorkspaceEndpoint::Local,
        dunce::canonicalize(&checkout)?
            .to_string_lossy()
            .into_owned(),
    )?;
    runtime
        .store
        .begin_thread_preparation(identity.clone())
        .await?;
    runtime
        .store
        .bind_thread_preparation(&identity.thread_id, &binding)
        .await?;
    let physical = close_factory(&runtime.store)?;
    let owner = physical
        .unpublished_workspace(&identity.thread_id, &checkout)
        .await?;
    let files = pl_tool::workspace::SessionFiles::new(&identity.thread_id);
    let session = checkout.join(files.root());
    for directory in ["artifacts", ".venv", "scratch/.venv"] {
        tokio::fs::create_dir_all(session.join(directory)).await?;
        tokio::fs::write(session.join(directory).join("keep"), directory).await?;
    }
    tokio::fs::write(checkout.join("business"), b"keep worktree").await?;
    // This completed physical preparer never attached storage. Its return is the real stop ACK;
    // retirement is deliberately left pending, and the canonical child has never been published.
    drop(owner);
    runtime
        .store
        .confirm_preparation_stop(&identity.thread_id)
        .await?;
    runtime
        .freeze_thread_archive(
            ArchiveScope::Thread(root.id.clone()),
            std::slice::from_ref(&runtime.store.directory_member(&root.id)?.unwrap()),
            std::slice::from_ref(&identity),
        )
        .await?;
    runtime
        .store
        .database()
        .execute_unprepared(
            "CREATE TRIGGER fail_private_retirement BEFORE UPDATE ON studio_objects
     WHEN NEW.object_kind = 'threadPreparation'
      AND NEW.owner_id = 'unpublished-physical-child'
      AND json_extract(NEW.payload_json, '$.retired') = 1
     BEGIN SELECT RAISE(ABORT, 'injected private retirement ACK failure'); END",
        )
        .await?;
    assert!(
        runtime
            .archive_thread("private-first".into(), root.id.clone())
            .await
            .is_err()
    );
    let pending = runtime
        .store
        .thread_archive(&ArchiveScope::Thread(root.id.clone()))
        .await?
        .unwrap();
    assert_eq!(pending.phase, ArchivePhase::Sealed);
    assert_eq!(pending.private_members.len(), 1);
    assert_eq!(pending.private_members[0].identity, identity);
    assert_eq!(
        pending.private_members[0].binding,
        PreparationBinding::Bound {
            identity: binding.clone()
        }
    );
    assert!(
        !runtime
            .store
            .thread_preparation(&identity.thread_id)
            .await?
            .unwrap()
            .retired
    );
    assert!(
        runtime
            .store
            .read_thread(&identity.thread_id)
            .await?
            .is_none()
    );
    assert!(session.join("scratch/prepared").is_file());
    assert!(
        session.join("artifacts/keep").is_file(),
        "real factory must not dispose the root"
    );
    runtime.shutdown_runtime().await?;
    physical.shutdown().await?;
    drop(physical);
    drop(runtime);

    let runtime = StudioRuntime::initialize(options(&home)).await?;
    assert!(
        runtime
            .session_of(&identity.thread_id)
            .and_then(|session| session.observed_thread(&identity.thread_id))
            .is_none()
    );
    assert!(
        runtime
            .store
            .read_thread(&identity.thread_id)
            .await?
            .is_none()
    );
    // A missing registry/catalog child must not turn the original failed retirement into success.
    assert!(
        runtime
            .archive_thread("private-still-failing".into(), root.id.clone())
            .await
            .is_err()
    );
    assert!(session.join("scratch/prepared").is_file());
    runtime
        .store
        .database()
        .execute_unprepared("DROP TRIGGER fail_private_retirement")
        .await?;
    runtime
        .archive_thread("private-retry".into(), root.id.clone())
        .await?
        .context("archive")?;
    let finished = runtime
        .store
        .thread_archive(&ArchiveScope::Thread(root.id))
        .await?
        .unwrap();
    assert_eq!(finished.phase, ArchivePhase::Published);
    assert_eq!(finished.private_members.len(), 1);
    assert!(finished.private_members[0].retired);
    assert!(
        finished.private_members[0].execution_cleaned && finished.private_members[0].host_cleaned
    );
    assert!(!checkout.join(files.temp()).exists());
    assert!(!session.join("scratch/prepared").exists());
    for directory in ["artifacts", ".venv", "scratch/.venv"] {
        assert_eq!(
            tokio::fs::read(session.join(directory).join("keep")).await?,
            directory.as_bytes()
        );
    }
    assert_eq!(
        tokio::fs::read(checkout.join("business")).await?,
        b"keep worktree"
    );
    let output = tokio::process::Command::new("git")
        .args(["worktree", "list", "--porcelain", "-z"])
        .current_dir(&repository)
        .output()
        .await?;
    assert!(output.status.success());
    let expected = dunce::canonicalize(&checkout)?;
    let mut registered = false;
    for field in String::from_utf8(output.stdout)?.split('\0') {
        if let Some(path) = field.strip_prefix("worktree ") {
            registered |= dunce::canonicalize(path)? == expected;
        }
    }
    assert!(registered, "the preserved checkout must remain registered");
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn archive_temp_removes_only_bound_disposable_directories_and_restores_lazily() -> Result<()>
{
    use pl_tool::workspace::SessionFiles;
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let _endpoint = configure(&home).await?;
    let workspace = temp.path().join("workspace");
    tokio::fs::create_dir_all(&workspace).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let project = runtime.open_project(&workspace).await?;
    let thread = runtime
        .create_thread_with_id("archive-temp", &project.id, "archive")
        .await?;
    let neighbor = runtime
        .create_thread_with_id("neighbor-temp", &project.id, "neighbor")
        .await?;
    runtime
        .ensure_thread_owner(&thread.id)
        .await?
        .flush()
        .await?;
    let files = SessionFiles::new(&thread.id);
    let neighbor_files = SessionFiles::new(&neighbor.id);
    let session = runtime.store.registered_session_paths(&thread.id)?;
    tokio::fs::create_dir_all(session.temp_dir()).await?;
    tokio::fs::write(session.temp_dir().join("transfer"), b"disposable").await?;
    let resources = runtime.store.session_resources_dir(&thread.id)?;
    tokio::fs::create_dir_all(&resources).await?;
    tokio::fs::write(resources.join("reliable"), b"keep reliable").await?;
    tokio::fs::write(workspace.join(files.temp()).join("probe"), b"disposable").await?;
    tokio::fs::write(
        workspace.join(files.artifacts()).join("delivery"),
        b"keep artifact",
    )
    .await?;
    tokio::fs::write(
        workspace.join(neighbor_files.temp()).join("active"),
        b"keep neighbor",
    )
    .await?;
    tokio::fs::write(workspace.join("business"), b"keep business").await?;

    runtime
        .archive_thread("archive-temp-operation".into(), thread.id.clone())
        .await?
        .context("archive reply")?;
    assert!(!session.temp_dir().exists());
    assert!(!workspace.join(files.temp()).exists());
    assert!(session.history_database().is_file());
    assert_eq!(
        tokio::fs::read(resources.join("reliable")).await?,
        b"keep reliable"
    );
    assert_eq!(
        tokio::fs::read(workspace.join(files.artifacts()).join("delivery")).await?,
        b"keep artifact"
    );
    assert_eq!(
        tokio::fs::read(workspace.join(neighbor_files.temp()).join("active")).await?,
        b"keep neighbor"
    );
    assert_eq!(
        tokio::fs::read(workspace.join("business")).await?,
        b"keep business"
    );
    let restored = runtime.restore_thread(thread.id.clone()).await?;
    assert!(!restored.archived);
    assert!(
        !workspace.join(files.temp()).exists(),
        "catalog restoration is not execution"
    );
    runtime.ensure_thread_owner(&thread.id).await?;
    assert!(workspace.join(files.commands()).is_dir());
    assert!(!workspace.join(files.temp()).join("probe").exists());
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn archive_temp_failure_survives_restart_and_cold_reads_do_not_recreate_temp() -> Result<()> {
    use crate::studio::store::thread_archive::{ArchivePhase, ArchiveScope};
    use pl_tool::workspace::SessionFiles;
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let _endpoint = configure(&home).await?;
    let workspace = temp.path().join("workspace");
    tokio::fs::create_dir_all(&workspace).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let project = runtime.open_project(&workspace).await?;
    let thread = runtime
        .create_thread_with_id("retry-temp", &project.id, "retry")
        .await?;
    let files = SessionFiles::new(&thread.id);
    let session = runtime.store.registered_session_paths(&thread.id)?;
    tokio::fs::create_dir_all(session.temp_dir()).await?;
    tokio::fs::write(session.temp_dir().join("transfer"), b"disposable").await?;
    // A non-directory at the dedicated temp address is a deterministic I/O failure even under root.
    tokio::fs::remove_dir_all(workspace.join(files.temp())).await?;
    tokio::fs::write(workspace.join(files.temp()), b"wrong kind").await?;
    assert!(
        runtime
            .archive_thread("retry-temp-first".into(), thread.id.clone())
            .await
            .is_err()
    );
    assert_eq!(
        runtime
            .store
            .thread_archive(&ArchiveScope::Thread(thread.id.clone()))
            .await?
            .unwrap()
            .phase,
        ArchivePhase::Saved
    );
    assert_eq!(
        runtime
            .store
            .read_thread(&thread.id)
            .await?
            .unwrap()
            .visibility,
        ThreadVisibility::Active
    );
    runtime.shutdown_runtime().await?;
    drop(runtime);

    let runtime = StudioRuntime::initialize(options(&home)).await?;
    assert_eq!(
        tokio::fs::read(workspace.join(files.temp())).await?,
        b"wrong kind"
    );
    runtime
        .store
        .read_thread(&thread.id)
        .await?
        .context("cold catalog")?;
    assert!(
        runtime
            .session_of(&thread.id)
            .and_then(|session| session.observed_thread(&thread.id))
            .is_none()
    );
    tokio::fs::remove_file(workspace.join(files.temp())).await?;
    runtime
        .archive_thread("retry-temp-second".into(), thread.id.clone())
        .await?
        .context("retry reply")?;
    assert!(!session.temp_dir().exists());
    assert!(!workspace.join(files.temp()).exists());
    assert_eq!(
        runtime
            .store
            .thread_archive(&ArchiveScope::Thread(thread.id))
            .await?
            .unwrap()
            .phase,
        ArchivePhase::Published
    );
    runtime.shutdown_runtime().await?;
    Ok(())
}

mod worktree_settlement {
    use super::*;
    use crate::studio::{
        store::{directory::DirectoryDelta, thread_preparation::PreparationIdentity},
        worktree::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity},
    };
    #[tokio::test]
    async fn archive_owned_worktrees_wait_for_borrowers_and_git_locks_discard_content_and_preserve_refs()
    -> Result<()> {
        use crate::{
            agent::worktree::{
                ExecutorWorktreeBackend, WorktreeCreateSpec, WorktreeManager, WorktreeOwnership,
            },
            studio::{
                store::thread_archive::{ArchivePhase, ArchiveScope},
                worktree::worktree_lease::{
                    WorktreeLease, WorktreeLeaseOwnerKind, WorktreeLeaseState,
                },
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
}

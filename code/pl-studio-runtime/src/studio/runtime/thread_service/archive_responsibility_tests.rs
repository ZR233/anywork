//! Real failed spawn disposal and process restart, using only isolated product/workspace fixtures.
use super::*;
use crate::{
    studio::{
        agent_host::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity},
        storage_fault_test_support::{
            ThreadStorageSink, close_factory, spawn_live_projection_for_thread,
        },
        store::{
            thread_archive::{ArchivePhase, ArchiveScope},
            thread_preparation::{
                PreparationBinding, PreparationDisposition, PreparationIdentity, PreparationSave,
                ThreadPreparationRecord,
            },
        },
    },
    thread_assembler::{
        ChildThreadRequest, StudioChildFactory, StudioChildResources, StudioThreadSpec,
        ThreadAssemblyError, archive_test_spec, spawn_failed_archive_fixture,
    },
};
use pl_core::thread::{
    ThreadHandle,
    cold::{ColdStore, ColdStoreError, ColdStoreHandle, StoragePressure, ThreadWrite},
};
use sea_orm::ConnectionTrait;
use std::{sync::Arc, time::Duration};

type Prepare = dyn Fn(
        ChildThreadRequest,
    ) -> futures::future::BoxFuture<'static, Result<StudioThreadSpec, ThreadAssemblyError>>
    + Send
    + Sync;
struct FailingPreparer {
    prepare: Arc<Prepare>,
    physical: crate::studio::StudioThreadFactory,
}
impl std::fmt::Debug for FailingPreparer {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("FailingPreparer")
    }
}
impl StudioChildFactory for FailingPreparer {
    async fn prepare(
        &self,
        request: ChildThreadRequest,
    ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
        (self.prepare)(request).await
    }
    async fn discard_unpublished(
        &self,
        id: &str,
        usage: Option<&crate::studio::WorkspaceUsageLease>,
        disposition: pl_tool::collaboration::thread::WorkspaceRelease,
    ) -> Result<(), ThreadAssemblyError> {
        StudioChildResources::discard_unpublished(&self.physical, id, usage, disposition).await
    }
}

async fn git(root: &Path, args: &[&str]) -> Result<()> {
    let output = tokio::process::Command::new("git")
        .args(args)
        .current_dir(root)
        .output()
        .await?;
    ensure!(
        output.status.success(),
        "isolated worktree fixture: {output:?}"
    );
    Ok(())
}

#[tokio::test]
async fn archive_first_scope_write_failure_recovers_exited_private_owner_and_original_binding()
-> Result<()> {
    for restart in [false, true] {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home)?;
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        git(&workspace, &["init", "--quiet"]).await?;
        git(
            &workspace,
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
        let checkout = dunce::canonicalize(temp.path())?.join("private-worktree");
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let project = runtime.open_project(&workspace).await?;
        let root = runtime
            .create_thread_with_id("first-write-root", &project.id, "root")
            .await?;
        runtime.ensure_thread_owner(&root.id).await?.flush().await?;
        let physical = Arc::new(close_factory(&runtime.store)?);
        let release = Arc::new(tokio::sync::Semaphore::new(0));
        let (ready, mut prepared) = tokio::sync::watch::channel(None);
        let factory = FailingPreparer {
            physical: physical.factory.clone(),
            prepare: Arc::new({
                let physical = physical.clone();
                let repository = workspace.clone();
                let workspace = checkout.clone();
                let release = release.clone();
                let store = runtime.store.clone();
                move |request| {
                    let physical = physical.clone();
                    let repository = repository.clone();
                    let workspace = workspace.clone();
                    let release = release.clone();
                    let ready = ready.clone();
                    let store = store.clone();
                    Box::pin(async move {
                        let binding = WorkspaceIdentity::canonical(
                            WorkspaceEndpoint::Local,
                            workspace.to_string_lossy().into_owned(),
                        )
                        .unwrap();
                        store
                            .bind_thread_preparation(&request.id, &binding)
                            .await
                            .unwrap();
                        git(
                            &repository,
                            &[
                                "worktree",
                                "add",
                                "--quiet",
                                "--detach",
                                workspace.to_str().unwrap(),
                                "HEAD",
                            ],
                        )
                        .await
                        .unwrap();
                        let owner = physical
                            .unpublished_workspace(&request.id, &workspace)
                            .await
                            .unwrap();
                        ready
                            .send_replace(Some((request.id.clone(), request.cancellation.clone())));
                        release.acquire().await.unwrap().forget();
                        drop(owner);
                        Err(ThreadAssemblyError::Closed)
                    })
                }
            }),
        };
        let mut spawn = tokio::spawn(spawn_failed_archive_fixture(
            runtime.threads.clone(),
            root.id.clone(),
            factory,
        ));
        tokio::time::timeout(Duration::from_secs(5), prepared.wait_for(Option::is_some)).await??;
        let (id, cancellation) = prepared.borrow().clone().unwrap();
        let files = pl_tool::workspace::SessionFiles::new(&id);
        let session = checkout.join(files.root());
        tokio::fs::write(checkout.join("business"), b"keep worktree").await?;
        for directory in ["artifacts", ".venv", "scratch/.venv"] {
            tokio::fs::create_dir_all(session.join(directory)).await?;
            tokio::fs::write(session.join(directory).join("keep"), directory).await?;
        }
        runtime
            .store
            .database()
            .execute_unprepared(
                "CREATE TRIGGER reject_first_archive BEFORE INSERT ON studio_objects
             WHEN NEW.object_kind='threadArchive'
             BEGIN SELECT RAISE(ABORT,'injected first archive scope failure'); END",
            )
            .await?;
        let first = tokio::time::timeout(
            Duration::from_secs(5),
            runtime.archive_thread("first-write-failure".into(), root.id.clone()),
        )
        .await?;
        assert!(first.is_err());
        assert!(
            runtime.store.publish_preparation(&id).await.is_err(),
            "an admitted builder must not publish away retained archive preserve responsibility"
        );
        assert!(
            !cancellation.is_cancelled(),
            "no cancellation before the complete scope commits"
        );
        assert!(
            runtime
                .store
                .thread_archive(&ArchiveScope::Thread(root.id.clone()))
                .await?
                .is_none()
        );
        release.add_permits(1);
        assert!(
            tokio::time::timeout(Duration::from_secs(5), &mut spawn)
                .await??
                .is_err()
        );
        let scope = runtime
            .threads
            .seal_archive_scope(std::slice::from_ref(&root.id))?;
        assert!(
            !scope.thread_ids().contains(&id),
            "real disposal and reservation have exited"
        );
        drop(scope);
        let original = runtime.store.thread_preparation(&id).await?.unwrap();
        assert!(original.stopped && original.retired);
        assert_eq!(
            original.disposition,
            PreparationDisposition::ArchivePreserve
        );
        assert!(matches!(original.binding, PreparationBinding::Bound { .. }));
        assert!(runtime.store.read_thread(&id).await?.is_none());
        assert!(runtime.ensure_thread_owner(&root.id).await.is_err());
        assert!(session.join("scratch/prepared").exists());
        runtime
            .store
            .database()
            .execute_unprepared("DROP TRIGGER reject_first_archive")
            .await?;
        physical.shutdown().await?;
        drop(physical);
        let runtime = if restart {
            runtime.shutdown_runtime().await?;
            drop(runtime);
            StudioRuntime::initialize(options(&home)).await?
        } else {
            runtime
        };
        runtime
            .archive_thread("first-write-retry".into(), root.id.clone())
            .await?
            .context("retry")?;
        let completed = runtime
            .store
            .thread_archive(&ArchiveScope::Thread(root.id))
            .await?
            .unwrap();
        assert_eq!(completed.phase, ArchivePhase::Published);
        let member = completed
            .private_members
            .iter()
            .find(|member| member.identity.thread_id == id)
            .context("exited private owner must remain in the complete frozen scope")?;
        assert_eq!(member.binding, original.binding);
        assert!(member.host_cleaned && member.execution_cleaned);
        assert_eq!(
            runtime
                .store
                .thread_preparation(&id)
                .await?
                .unwrap()
                .disposition,
            PreparationDisposition::TempCleaned
        );
        assert!(!checkout.join(files.temp()).exists());
        assert!(!session.join("scratch/prepared").exists());
        for directory in ["artifacts", ".venv", "scratch/.venv"] {
            assert_eq!(
                tokio::fs::read(session.join(directory).join("keep")).await?,
                directory.as_bytes()
            );
        }
        assert!(checkout.join(".git").is_file());
        assert_eq!(
            tokio::fs::read(checkout.join("business")).await?,
            b"keep worktree"
        );
        let worktrees = tokio::process::Command::new("git")
            .args(["worktree", "list", "--porcelain", "-z"])
            .current_dir(&workspace)
            .output()
            .await?;
        assert!(worktrees.status.success());
        let expected = dunce::canonicalize(&checkout)?;
        let mut registered = false;
        for field in String::from_utf8(worktrees.stdout)?.split('\0') {
            if let Some(path) = field.strip_prefix("worktree ") {
                registered |= dunce::canonicalize(path)? == expected;
            }
        }
        assert!(registered, "the preserved checkout must remain registered");
        runtime.shutdown_runtime().await?;
    }
    Ok(())
}

#[derive(Debug)]
struct RejectLaterPrivateWrites {
    sink: ThreadStorageSink,
    original_fence: u64,
}
impl ColdStore for RejectLaterPrivateWrites {
    fn pressure(&self, id: &str) -> StoragePressure {
        self.sink.pressure(id)
    }
    fn admit(&self, id: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
        if write.effect.sequence > self.original_fence {
            return Err(ColdStoreError {
                source: Box::new(std::io::Error::other(
                    "injected later private checkpoint failure",
                )),
            });
        }
        self.sink.admit(id, write)
    }
    async fn flush(&self, id: &str, through: u64) -> Result<(), ColdStoreError> {
        self.sink.flush(id, through).await
    }
}

/// Seeds the isolated home with the durable facts the crashing private owner inherits: the
/// project, the required root with a durable owner checkpoint, the required-private catalog
/// row, and a real older incarnation's durable earlier checkpoint. This heavy preparation runs
/// in the parent and shuts its runtime down cleanly, so the spawned producer's bounded crash
/// window only has to cover the original owner's own work.
async fn seed_private_crash_fixture(base: &Path) -> Result<()> {
    eprintln!("private crash seed: start");
    let home = base.join("home");
    let workspace = base.join("workspace");
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    eprintln!("private crash seed: runtime initialized");
    let project = runtime.open_project(&workspace).await?;
    let root = runtime
        .create_thread_with_id("required-root", &project.id, "root")
        .await?;
    runtime.ensure_thread_owner(&root.id).await?.flush().await?;
    eprintln!("private crash seed: root ready");
    let mut protocol = pl_protocol::Thread::placeholder("required-private");
    protocol.agent_path = protocol.id.clone();
    protocol.workspace_id = project.id.clone();
    protocol.workspace_path = workspace.to_string_lossy().into_owned();
    protocol.root_thread_id = root.id.clone();
    protocol.parent_thread_id = Some(root.id.clone());
    runtime
        .agent_facility
        .product_events
        .commit_directory(crate::studio::store::directory::DirectoryDelta {
            thread_upserts: vec![protocol.clone()],
            ..Default::default()
        })
        .await?;
    // A real older incarnation leaves a durable earlier checkpoint before private AttachCold.
    let old = ThreadStorageSink::new(runtime.store.clone(), protocol.clone(), None).await?;
    let projection = spawn_live_projection_for_thread(runtime.store.clone(), &protocol.id);
    let previous = ThreadHandle::resume_without_model(protocol.id.clone(), None)?;
    previous.attach_storage(ColdStoreHandle::new(old)).await?;
    previous.close().await?;
    runtime
        .store
        .thread_persistence()
        .history_channel(&protocol.id)
        .stop_and_join()
        .await?;
    projection.await?;
    runtime.shutdown_runtime().await?;
    eprintln!("private crash seed: earlier checkpoint durable and seed runtime shut down");
    Ok(())
}

async fn produce_private_storage_crash(base: &Path, receipt: bool) -> Result<()> {
    eprintln!("private crash fixture: initialize receipt={receipt}");
    let home = base.join("home");
    let workspace = base.join("workspace");
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    eprintln!("private crash fixture: runtime initialized");
    let project = runtime.open_project(&workspace).await?;
    eprintln!("private crash fixture: project reopened");
    // The crashing owner still has to observe the seeded root: assembling required-private
    // reserves against its live parent entry before the private AttachCold.
    runtime
        .ensure_thread_owner("required-root")
        .await?
        .flush()
        .await?;
    eprintln!("private crash fixture: root owner restored");
    let protocol = runtime
        .store
        .catalog()
        .get("required-private")
        .context("seeded required-private catalog row")?
        .to_thread();
    let checkpoint = runtime
        .store
        .history(&protocol.id)
        .await?
        .checkpoint()
        .await?
        .context("seeded durable earlier checkpoint")?;
    eprintln!("private crash fixture: seeded protocol and checkpoint read");
    let old_fence = checkpoint.history_fence;
    let physical = close_factory(&runtime.store)?;
    runtime
        .store
        .begin_thread_preparation(PreparationIdentity {
            thread_id: protocol.id.clone(),
            workspace_id: project.id.clone(),
            parent_id: protocol.parent_thread_id.clone(),
            root_id: protocol.root_thread_id.clone(),
        })
        .await?;
    let binding = WorkspaceIdentity::canonical(
        WorkspaceEndpoint::Local,
        dunce::canonicalize(&workspace)?
            .to_string_lossy()
            .into_owned(),
    )?;
    runtime
        .store
        .bind_thread_preparation(&protocol.id, &binding)
        .await?;
    let _preparer = physical
        .unpublished_workspace(&protocol.id, &workspace)
        .await?;
    let files = pl_tool::workspace::SessionFiles::new(&protocol.id);
    tokio::fs::create_dir_all(workspace.join(files.artifacts())).await?;
    tokio::fs::write(workspace.join(files.artifacts()).join("keep"), b"delivery").await?;
    if receipt {
        runtime
            .store
            .database()
            .execute_unprepared(
                "CREATE TRIGGER reject_original_stop BEFORE UPDATE ON studio_objects
             WHEN NEW.object_kind='threadPreparation' AND NEW.owner_id='required-private'
              AND json_extract(NEW.payload_json,'$.stopped')=1
             BEGIN SELECT RAISE(ABORT,'injected stop after original closed receipt'); END",
            )
            .await?;
    }
    let sink =
        ThreadStorageSink::new(runtime.store.clone(), protocol.clone(), Some(&checkpoint)).await?;
    let _projection = spawn_live_projection_for_thread(runtime.store.clone(), &protocol.id);
    let storage = if receipt {
        ColdStoreHandle::new(sink)
    } else {
        ColdStoreHandle::new(RejectLaterPrivateWrites {
            sink,
            original_fence: old_fence,
        })
    };
    let mut spec = archive_test_spec(
        protocol.id.clone(),
        protocol.parent_thread_id.clone(),
        &workspace,
    );
    spec.checkpoint = Some(checkpoint);
    spec.cold_store = Some(storage);
    spec.initial_extensions.insert(
        String::new(),
        pl_core::context::OpaquePayload::text("invalid initialization"),
    );
    eprintln!("private crash fixture: attach and fail initialization");
    assert!(runtime.threads.assemble(spec).await.is_err());
    eprintln!("private crash fixture: original failure retained");
    let record = runtime
        .store
        .thread_preparation(&protocol.id)
        .await?
        .unwrap();
    assert!(!record.published && !record.stopped);
    assert_eq!(
        record.save,
        if receipt {
            PreparationSave::Confirmed
        } else {
            PreparationSave::Required
        }
    );
    let evidence = serde_json::json!({"record": record, "oldFence": old_fence});
    tokio::fs::write(
        base.join("original-owner-evidence.json"),
        serde_json::to_vec(&evidence)?,
    )
    .await?;
    // The enclosing test starts this exact test binary as an isolated producer process. Do not
    // run graceful shutdown: it would either retry or discharge the original obligation.
    std::process::exit(0);
}

async fn crash_original_private_owner(base: &Path, receipt: bool) -> Result<serde_json::Value> {
    seed_private_crash_fixture(base).await?;
    let mut command = tokio::process::Command::new(std::env::current_exe()?);
    command
        .arg("archive_original_required_receipt_is_not_replaced_by_a_cold_checkpoint_after_crash")
        .arg("--nocapture")
        .env("ANYWORK_ARCHIVE_PRIVATE_CRASH_FIXTURE", base)
        .kill_on_drop(true);
    if receipt {
        command.env("ANYWORK_ARCHIVE_PRIVATE_RECEIPT", "1");
    } else {
        command.env_remove("ANYWORK_ARCHIVE_PRIVATE_RECEIPT");
    }
    command
        .stdout(std::process::Stdio::inherit())
        .stderr(std::process::Stdio::inherit());
    let mut child = command.spawn()?;
    let status = match tokio::time::timeout(Duration::from_secs(20), child.wait()).await {
        Ok(result) => result?,
        Err(error) => {
            child.kill().await?;
            child.wait().await?;
            return Err(error)
                .context("original private producer did not reach its crash boundary");
        }
    };
    ensure!(status.success(), "original producer fixture: {status}");
    Ok(serde_json::from_slice(
        &tokio::fs::read(base.join("original-owner-evidence.json")).await?,
    )?)
}

#[tokio::test]
async fn archive_original_required_receipt_is_not_replaced_by_a_cold_checkpoint_after_crash()
-> Result<()> {
    const CHILD: &str = "ANYWORK_ARCHIVE_PRIVATE_CRASH_FIXTURE";
    if let Some(base) = std::env::var_os(CHILD) {
        return produce_private_storage_crash(
            Path::new(&base),
            std::env::var_os("ANYWORK_ARCHIVE_PRIVATE_RECEIPT").is_some(),
        )
        .await;
    }
    for receipt in [false, true] {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let _endpoint = configure(&home)?;
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let evidence = crash_original_private_owner(temp.path(), receipt).await?;
        let original: ThreadPreparationRecord = serde_json::from_value(evidence["record"].clone())?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        assert!(
            runtime
                .store
                .read_thread("required-private")
                .await?
                .is_some()
        );
        assert!(
            runtime
                .threads
                .observed_thread("required-private")
                .is_none()
        );
        if receipt {
            runtime
                .store
                .database()
                .execute_unprepared("DROP TRIGGER reject_original_stop")
                .await?;
        } else {
            let before = runtime
                .store
                .history("required-private")
                .await?
                .checkpoint()
                .await?
                .unwrap();
            assert_eq!(before.history_fence, evidence["oldFence"].as_u64().unwrap());
        }
        let result = tokio::time::timeout(
            Duration::from_secs(10),
            runtime.archive_thread("required-restart".into(), "required-root".into()),
        )
        .await?;
        let pending = runtime
            .store
            .thread_preparation("required-private")
            .await?
            .unwrap();
        assert_eq!(
            pending.storage.as_ref().unwrap().incarnation,
            original.storage.as_ref().unwrap().incarnation
        );
        let operation = runtime
            .store
            .thread_archive(&ArchiveScope::Thread("required-root".into()))
            .await?
            .unwrap();
        let member = operation
            .private_members
            .iter()
            .find(|member| member.identity.thread_id == "required-private")
            .context(
                "catalog membership must not promote the original private storage obligation",
            )?;
        assert_eq!(member.binding, original.binding);
        let files = pl_tool::workspace::SessionFiles::new("required-private");
        if receipt {
            result?.context("valid original closed receipt must permit retry")?;
            assert_eq!(operation.phase, ArchivePhase::Published);
            assert_eq!(pending.save, PreparationSave::Confirmed);
            assert_eq!(pending.disposition, PreparationDisposition::TempCleaned);
            assert!(!workspace.join(files.temp()).exists());
        } else {
            assert!(result.is_err());
            assert_eq!(pending.save, PreparationSave::Required);
            assert!(pending.storage.as_ref().unwrap().closed_receipt.is_none());
            assert_eq!(operation.phase, ArchivePhase::Sealed);
            assert!(
                runtime
                    .threads
                    .observed_thread("required-private")
                    .is_none(),
                "no substitute cold incarnation"
            );
            assert!(
                workspace
                    .join(files.root())
                    .join("scratch/prepared")
                    .exists()
            );
            assert!(runtime.ensure_thread_owner("required-root").await.is_err());
        }
        assert_eq!(
            tokio::fs::read(workspace.join(files.artifacts()).join("keep")).await?,
            b"delivery"
        );
        runtime.shutdown_runtime().await?;
    }
    Ok(())
}

async fn archive_receipt_scope(runtime: &StudioRuntime, scope: &ArchiveScope) -> Result<()> {
    match scope {
        ArchiveScope::Thread(id) => {
            runtime
                .archive_thread("receipt-retry".into(), id.clone())
                .await?
                .context("thread archive")?;
        }
        ArchiveScope::Workspace(id) => {
            runtime
                .archive_project(id)
                .await?
                .context("workspace archive")?;
        }
    }
    Ok(())
}

async fn reject_changed_saved_projection(
    runtime: &StudioRuntime,
    scope: &ArchiveScope,
) -> Result<()> {
    let tree = runtime.store.read_directory_tree("required-root").await?;
    let private_index = tree
        .iter()
        .position(|thread| thread.id == "required-private")
        .unwrap();
    let frozen = runtime.store.thread_archive(scope).await?.unwrap();
    assert_eq!(frozen.phase, ArchivePhase::Saved);
    let mut changed = tree.clone();
    let mut extra = tree[private_index].clone();
    extra.id = "unfrozen-member".into();
    changed.push(extra);
    let error = runtime
        .freeze_thread_archive(scope.clone(), &changed, &[])
        .await
        .unwrap_err();
    assert!(error.to_string().contains("gained a member"), "{error:#}");
    let mut new_admission = frozen.private_members[0].identity.clone();
    new_admission.thread_id = "unfrozen-preparation".into();
    assert!(
        runtime
            .freeze_thread_archive(scope.clone(), &tree, &[new_admission])
            .await
            .is_err()
    );
    assert!(
        runtime
            .store
            .thread_preparation("unfrozen-preparation")
            .await?
            .is_none()
    );
    let without_public = tree
        .iter()
        .filter(|thread| thread.id != "required-root")
        .cloned()
        .collect::<Vec<_>>();
    assert!(
        runtime
            .freeze_thread_archive(scope.clone(), &without_public, &[])
            .await
            .is_err()
    );
    for field in ["workspace", "root", "parent"] {
        let mut changed = tree.clone();
        match field {
            "workspace" => changed[private_index].workspace_id = "different-workspace".into(),
            "root" => changed[private_index].root_thread_id = "different-root".into(),
            "parent" => changed[private_index].parent_thread_id = Some("different-parent".into()),
            _ => unreachable!(),
        }
        let error = runtime
            .freeze_thread_archive(scope.clone(), &changed, &[])
            .await
            .unwrap_err();
        assert!(
            error.to_string().contains("changed identity"),
            "{field}: {error:#}"
        );
    }
    // A filtered projection can lose P precisely because its canonical ownership changed.
    // Its absence must not be mistaken for a private identity that never had a catalog row.
    let canonical = runtime.store.catalog().get("required-private").unwrap();
    let without_private = tree
        .iter()
        .filter(|thread| thread.id != "required-private")
        .cloned()
        .collect::<Vec<_>>();
    for field in ["workspace", "root", "parent"] {
        let mut shifted = canonical.clone();
        match field {
            "workspace" => shifted.workspace_id = "different-workspace".into(),
            "root" => shifted.root_thread_id = "different-root".into(),
            "parent" => shifted.parent_thread_id = Some("different-parent".into()),
            _ => unreachable!(),
        }
        runtime.store.catalog().upsert(shifted).await?;
        let outcome = runtime
            .freeze_thread_archive(scope.clone(), &without_private, &[])
            .await;
        runtime.store.catalog().upsert(canonical.clone()).await?;
        let error = outcome.unwrap_err();
        assert!(
            error.to_string().contains("changed identity"),
            "{field}: {error:#}"
        );
    }
    // A validly encoded but conflicting frozen binding must not be repaired from a newer view.
    let mut conflicting = frozen.clone();
    let original = match &mut conflicting.private_members[0].binding {
        PreparationBinding::Bound { identity } => identity,
        PreparationBinding::Unbound => panic!("receipt fixture has a frozen physical binding"),
    };
    original.root.push_str("-different-binding");
    conflicting.changed()?;
    runtime.store.save_thread_archive(&conflicting).await?;
    let error = runtime
        .freeze_thread_archive(scope.clone(), &tree, &[])
        .await
        .unwrap_err();
    assert!(
        error.to_string().contains("physical binding changed"),
        "{error:#}"
    );
    let mut restored = frozen;
    restored.revision = conflicting.revision;
    restored.changed()?;
    runtime.store.save_thread_archive(&restored).await?;
    // A private identity does not owe catalog publication; its original responsibility remains.
    let without_private = tree
        .into_iter()
        .filter(|thread| thread.id != "required-private")
        .collect::<Vec<_>>();
    let projected = runtime
        .freeze_thread_archive(scope.clone(), &without_private, &[])
        .await?;
    assert_eq!(projected.members.len(), 1);
    assert_eq!(projected.private_members.len(), 1);
    Ok(())
}

#[tokio::test]
async fn archive_private_catalog_projection_retries_saved_cleaned_and_published_ack() -> Result<()>
{
    for workspace_archive in [false, true] {
        for restart in [false, true] {
            let temp = tempfile::tempdir()?;
            let home = temp.path().join("home");
            let _endpoint = configure(&home)?;
            let workspace = temp.path().join("workspace");
            tokio::fs::create_dir_all(&workspace).await?;
            let evidence = crash_original_private_owner(temp.path(), true).await?;
            let original: ThreadPreparationRecord =
                serde_json::from_value(evidence["record"].clone())?;
            let mut runtime = StudioRuntime::initialize(options(&home)).await?;
            runtime
                .store
                .database()
                .execute_unprepared("DROP TRIGGER reject_original_stop")
                .await?;
            let root = runtime.store.read_thread("required-root").await?.unwrap();
            let scope = if workspace_archive {
                ArchiveScope::Workspace(root.workspace_id.clone())
            } else {
                ArchiveScope::Thread(root.id.clone())
            };
            let files = pl_tool::workspace::SessionFiles::new("required-private");
            let blocked_temp = workspace.join(files.temp());
            tokio::fs::write(&blocked_temp, b"recoverable temp obstruction").await?;
            let error = archive_receipt_scope(&runtime, &scope).await.unwrap_err();
            let saved = runtime.store.thread_archive(&scope).await?.unwrap();
            assert_eq!(
                saved.phase,
                ArchivePhase::Saved,
                "must reach the real cleanup failure: {error:#}"
            );
            assert_eq!(saved.members.len(), 1);
            assert_eq!(saved.private_members.len(), 1);
            assert_eq!(saved.private_members[0].binding, original.binding);
            assert_eq!(saved.private_members[0].save, PreparationSave::Confirmed);
            assert!(saved.private_members[0].stopped && saved.private_members[0].retired);
            assert_eq!(
                runtime
                    .store
                    .read_thread("required-private")
                    .await?
                    .unwrap()
                    .visibility,
                crate::studio::ThreadVisibility::Active
            );
            reject_changed_saved_projection(&runtime, &scope).await?;
            if restart {
                runtime.shutdown_runtime().await?;
                drop(runtime);
                runtime = StudioRuntime::initialize(options(&home)).await?;
            }
            tokio::fs::remove_file(&blocked_temp).await?;
            runtime.store.database().execute_unprepared(
                "CREATE TRIGGER reject_cleanup_ack BEFORE UPDATE ON studio_objects
                 WHEN NEW.object_kind='threadArchive' AND json_extract(NEW.payload_json,'$.phase')='cleaned'
                 BEGIN SELECT RAISE(ABORT,'injected Cleaned ACK failure'); END",
            ).await?;
            let error = archive_receipt_scope(&runtime, &scope).await.unwrap_err();
            assert!(
                format!("{error:#}").contains("injected Cleaned ACK failure"),
                "{error:#}"
            );
            let cleaned_without_ack = runtime.store.thread_archive(&scope).await?.unwrap();
            assert_eq!(cleaned_without_ack.phase, ArchivePhase::Saved);
            assert!(
                cleaned_without_ack.private_members[0].host_cleaned
                    && cleaned_without_ack.private_members[0].execution_cleaned
            );
            assert_eq!(
                runtime
                    .store
                    .read_thread("required-private")
                    .await?
                    .unwrap()
                    .visibility,
                crate::studio::ThreadVisibility::Active
            );
            if restart {
                runtime.shutdown_runtime().await?;
                drop(runtime);
                runtime = StudioRuntime::initialize(options(&home)).await?;
            }
            runtime
                .store
                .database()
                .execute_unprepared("DROP TRIGGER reject_cleanup_ack")
                .await?;
            runtime.store.database().execute_unprepared(
                "CREATE TRIGGER reject_published_ack BEFORE UPDATE ON studio_objects
                 WHEN NEW.object_kind='threadArchive' AND json_extract(NEW.payload_json,'$.phase')='published'
                 BEGIN SELECT RAISE(ABORT,'injected Published ACK failure'); END",
            ).await?;
            let error = archive_receipt_scope(&runtime, &scope).await.unwrap_err();
            assert!(
                format!("{error:#}").contains("injected Published ACK failure"),
                "{error:#}"
            );
            assert_eq!(
                runtime.store.thread_archive(&scope).await?.unwrap().phase,
                ArchivePhase::Cleaned
            );
            assert_eq!(
                runtime
                    .store
                    .read_thread("required-private")
                    .await?
                    .unwrap()
                    .visibility,
                crate::studio::ThreadVisibility::Archived
            );
            if restart {
                runtime.shutdown_runtime().await?;
                drop(runtime);
                runtime = StudioRuntime::initialize(options(&home)).await?;
            }
            runtime
                .store
                .database()
                .execute_unprepared("DROP TRIGGER reject_published_ack")
                .await?;
            archive_receipt_scope(&runtime, &scope).await?;
            let published = runtime.store.thread_archive(&scope).await?.unwrap();
            assert_eq!(published.phase, ArchivePhase::Published);
            assert_eq!(published.members.len(), 1);
            assert_eq!(published.private_members.len(), 1);
            assert_eq!(published.private_members[0].binding, original.binding);
            let preparation = runtime
                .store
                .thread_preparation("required-private")
                .await?
                .unwrap();
            assert_eq!(
                preparation.storage.as_ref().unwrap().incarnation,
                original.storage.as_ref().unwrap().incarnation
            );
            assert_eq!(preparation.disposition, PreparationDisposition::TempCleaned);
            assert!(!blocked_temp.exists());
            for id in ["required-root", "required-private"] {
                assert!(
                    !runtime
                        .store
                        .registered_session_paths(id)?
                        .temp_dir()
                        .exists(),
                    "{id} host temp must stay cleaned across ACK retries"
                );
                assert!(runtime.threads.observed_thread(id).is_none());
            }
            assert_eq!(
                tokio::fs::read(workspace.join(files.artifacts()).join("keep")).await?,
                b"delivery"
            );
            runtime.shutdown_runtime().await?;
        }
    }
    Ok(())
}

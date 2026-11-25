//! Standalone acceptance at the real runtime boundary, without touching platform Documents.
use super::*;
use crate::studio::runtime::thread_service::test_support::{configure, options, request};

#[tokio::test]
async fn standalone_prepare_is_concurrent_idempotent_and_rejects_project_operations() -> Result<()>
{
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let root = temp.path().join("documents/anywork");
    let (left, right) = tokio::join!(
        runtime.prepare_standalone_workspace_at(Some(root.clone())),
        runtime.prepare_standalone_workspace_at(Some(root.clone()))
    );
    let project = left?;
    assert_eq!(project, right?);
    assert_eq!(project.kind, WorkspaceKind::Standalone);
    assert_eq!(Path::new(&project.path), dunce::canonicalize(&root)?);
    assert_eq!(
        runtime
            .agent_facility
            .product_events
            .project_snapshot()
            .await,
        vec![project.clone()]
    );
    assert_eq!(
        runtime.prepare_standalone_workspace_at(None).await?,
        project
    );
    assert!(
        runtime
            .store
            .list_threads_for_project(&project.id)
            .await?
            .is_empty()
    );
    assert!(runtime.open_project(&root).await.is_err());
    assert!(runtime.rename_project(&project.id, "fake").await.is_err());
    assert!(runtime.archive_project(&project.id).await.is_err());
    assert!(
        runtime
            .apply_settings_field(crate::UpdateSettingsFieldRequest {
                operation_id: "pin-standalone".into(),
                update: crate::SettingsFieldUpdate::ProjectPinned {
                    id: project.id.clone(),
                    value: true,
                },
            })
            .await
            .is_err()
    );
    runtime.shutdown_runtime().await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    assert_eq!(
        runtime.prepare_standalone_workspace_at(None).await?,
        project
    );
    assert_eq!(
        runtime
            .agent_facility
            .product_events
            .project_snapshot()
            .await,
        vec![project]
    );
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn standalone_prepare_failure_does_not_publish_or_convert_user_project() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let runtime = StudioRuntime::initialize(options(&temp.path().join("home"))).await?;
    assert!(runtime.prepare_standalone_workspace_at(None).await.is_err());
    let blocked = temp.path().join("blocked");
    tokio::fs::write(&blocked, b"not a directory").await?;
    assert!(
        runtime
            .prepare_standalone_workspace_at(Some(blocked))
            .await
            .is_err()
    );
    assert!(
        runtime
            .agent_facility
            .product_events
            .project_snapshot()
            .await
            .is_empty()
    );
    let root = temp.path().join("user-project");
    tokio::fs::create_dir(&root).await?;
    let project = runtime.open_project(&root).await?;
    assert!(
        runtime
            .prepare_standalone_workspace_at(Some(root))
            .await
            .is_err()
    );
    assert_eq!(
        runtime
            .agent_facility
            .product_events
            .project_snapshot()
            .await,
        vec![project]
    );
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn canonical_standalone_without_snapshot_is_republished_before_thread_creation() -> Result<()>
{
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let endpoint = configure(&home).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let root = temp.path().join("documents/anywork");
    tokio::fs::create_dir_all(&root).await?;
    let path = dunce::canonicalize(&root)?.to_string_lossy().into_owned();
    let owner = crate::studio::store::directory::ProjectDirectoryRecord {
        id: "project-canonical-standalone".into(),
        kind: WorkspaceKind::Standalone,
        name: "preserved owner".into(),
        path: path.clone(),
        ssh_alias: None,
        created_at: 17,
        updated_at: 23,
        last_opened_at: Some(19),
        closed: false,
    };
    runtime
        .store
        .persist_directory_summaries(&DirectoryDelta::upsert_project(owner))
        .await?;
    assert!(
        runtime
            .agent_facility
            .product_events
            .project_snapshot()
            .await
            .is_empty(),
        "fixture must model cancellation before ProductEventBus publication"
    );
    let before_entry = runtime
        .store
        .workspaces()
        .get("project-canonical-standalone")
        .context("canonical owner")?;
    let before_document =
        tokio::fs::read_to_string(runtime.store.paths().workspaces_file()).await?;

    let project = runtime
        .prepare_standalone_workspace_at(Some(temp.path().join("ignored-root")))
        .await?;
    assert_eq!(project, before_entry.project());
    assert_eq!(
        runtime
            .agent_facility
            .product_events
            .project_snapshot()
            .await,
        vec![project.clone()]
    );
    assert_eq!(
        runtime
            .store
            .workspaces()
            .get(&project.id)
            .context("replayed owner")?,
        before_entry
    );
    assert_eq!(
        tokio::fs::read_to_string(runtime.store.paths().workspaces_file()).await?,
        before_document,
        "event repair must not alter the canonical document or its revision"
    );
    let thread = runtime.create_thread(&project.id, "after replay").await?;
    assert_eq!(
        Path::new(&thread.workspace_path),
        dunce::canonicalize(root.join(&thread.id))?
    );
    runtime.shutdown_runtime().await?;
    assert!(
        endpoint.finish().await?.is_empty(),
        "storage-only startup must not send inference"
    );
    Ok(())
}

#[tokio::test]
async fn standalone_threads_use_exclusive_directories_and_restore_without_rebinding() -> Result<()>
{
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let endpoint = configure(&home).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let root = temp.path().join("documents/anywork");
    let project = runtime
        .prepare_standalone_workspace_at(Some(root.clone()))
        .await?;
    let first = runtime.create_thread(&project.id, "first").await?;
    let second = runtime.create_thread(&project.id, "second").await?;
    for thread in [&first, &second] {
        let expected = dunce::canonicalize(root.join(&thread.id))?;
        assert_eq!(Path::new(&thread.workspace_path), expected);
        assert_ne!(thread.workspace_path, project.path);
        assert!(!expected.join(".git").exists());
        assert_eq!(
            runtime
                .store
                .workspace_identity(&thread.id)
                .await?
                .context("bound workspace")?
                .root,
            thread.workspace_path
        );
    }
    assert_ne!(first.workspace_path, second.workspace_path);
    let sentinel = Path::new(&first.workspace_path).join("user-work.txt");
    tokio::fs::write(&sentinel, b"keep user files").await?;
    let collision = root.join("occupied-thread");
    tokio::fs::create_dir(&collision).await?;
    tokio::fs::write(collision.join("unknown"), b"keep unknown leftovers").await?;
    assert!(
        runtime
            .create_thread_with_id("occupied-thread", &project.id, "not published")
            .await
            .is_err()
    );
    assert!(runtime.find_owned_thread("occupied-thread")?.is_none());
    assert_eq!(
        tokio::fs::read(collision.join("unknown")).await?,
        b"keep unknown leftovers"
    );
    assert!(
        runtime
            .create_thread_with_id("../escape", &project.id, "unsafe")
            .await
            .is_err()
    );
    runtime.shutdown_runtime().await?;

    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let restored = runtime
        .find_owned_thread(&first.id)?
        .context("cold Thread")?;
    assert_eq!(restored.workspace_path, first.workspace_path);
    runtime.ensure_thread_owner(&restored.id).await?;
    assert_eq!(
        runtime
            .store
            .workspace_identity(&first.id)
            .await?
            .context("restored workspace")?
            .root,
        first.workspace_path
    );
    assert_eq!(
        runtime.store.read_project(&project.id).await?.unwrap().kind,
        WorkspaceKind::Standalone
    );
    runtime
        .archive_thread("archive-standalone".into(), first.id.clone())
        .await?;
    assert_eq!(tokio::fs::read(&sentinel).await?, b"keep user files");
    runtime.shutdown_runtime().await?;
    assert!(
        endpoint.finish().await?.is_empty(),
        "storage-only startup must not send inference"
    );
    Ok(())
}

#[tokio::test]
async fn standalone_start_rejects_worktree_without_publishing_or_creating_directories() -> Result<()>
{
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let _endpoint = configure(&home).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let root = temp.path().join("documents/anywork");
    let project = runtime
        .prepare_standalone_workspace_at(Some(root.clone()))
        .await?;
    let result = runtime
        .create_thread_command(
            project.id.clone(),
            request(crate::ThreadWorkspaceMode::Worktree),
            None,
        )
        .await;
    let error = result.expect_err("standalone worktree must fail");
    assert!(
        error.to_string().contains("only support local"),
        "{error:#}"
    );
    assert!(
        runtime
            .store
            .list_threads_for_project(&project.id)
            .await?
            .is_empty()
    );
    assert!(
        tokio::fs::read_dir(root)
            .await?
            .next_entry()
            .await?
            .is_none()
    );
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn standalone_start_directory_creation_failure_is_not_published() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let home = temp.path().join("home");
    let _endpoint = configure(&home).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let root = temp.path().join("documents/anywork");
    let project = runtime
        .prepare_standalone_workspace_at(Some(root.clone()))
        .await?;
    let original = root.clone();
    // Fault injection after admission, immediately before the real exclusive create_dir. This
    // simulates the filesystem becoming unwritable without global env or production test knobs.
    let observer = std::sync::Arc::new(move |progress: crate::ThreadPreparationProgress| {
        if matches!(
            progress.stage,
            crate::ThreadPreparationStage::PreparingWorkspace
        ) {
            std::fs::rename(&root, root.with_file_name("preserved")).unwrap();
            std::fs::write(&root, b"blocked parent").unwrap();
        }
    });
    let error = runtime
        .create_thread_command(
            project.id.clone(),
            request(crate::ThreadWorkspaceMode::Local),
            Some(observer),
        )
        .await
        .expect_err("directory creation must fail");
    assert!(
        error
            .to_string()
            .contains("create standalone Thread directory"),
        "{error:#}"
    );
    let directory = runtime
        .agent_facility
        .product_events
        .read_thread_directory()
        .await?;
    assert!(
        directory
            .state
            .value()
            .context("ready directory")?
            .rows
            .is_empty()
    );
    assert!(
        runtime
            .store
            .list_threads_for_project(&project.id)
            .await?
            .is_empty()
    );
    assert_eq!(tokio::fs::read(original).await?, b"blocked parent");
    runtime.shutdown_runtime().await?;
    Ok(())
}

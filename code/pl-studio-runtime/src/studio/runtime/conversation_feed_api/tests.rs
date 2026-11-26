use crate::studio::runtime::StudioRuntime;
use crate::studio::runtime::thread_service::test_support::{configure, options};
use anyhow::{Context, Result};

#[tokio::test]
async fn cold_session_meta_reports_corrupt_history_but_accepts_absence() -> Result<()> {
    let temporary = tempfile::tempdir()?;
    let home = temporary.path().join("home");
    let _endpoint = configure(&home).await?;
    let workspace = temporary.path().join("workspace");
    tokio::fs::create_dir_all(&workspace).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let project = runtime.open_project(&workspace).await?;
    let thread = runtime
        .create_thread(&project.id, "cold history metadata")
        .await?;
    let owner = runtime.ensure_thread_owner(&thread.id).await?;
    runtime.synchronize_thread_observation(&thread.id).await?;
    runtime
        .store
        .conversation_store(&thread.id)
        .await?
        .flush_current(owner.runtime_epoch())
        .await?;
    let paths = runtime.store.registered_session_paths(&thread.id)?;
    runtime.shutdown_runtime().await?;
    drop(runtime);

    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let current = tokio::fs::read(paths.current_file())
        .await
        .context("saved fixture Current")?;
    tokio::fs::write(paths.history_database(), b"invalid history database").await?;
    assert!(runtime.open_conversation_feed(&thread.id, 8).await.is_err());
    assert!(
        runtime.thread_session_meta(&thread.id).await.is_err(),
        "corruption must not become partial metadata success"
    );
    assert_eq!(
        tokio::fs::read(paths.history_database()).await?,
        b"invalid history database"
    );
    assert_eq!(tokio::fs::read(paths.current_file()).await?, current);
    assert!(!paths.root().join("migration-backups").exists());
    assert!(
        runtime
            .session_of(&thread.id)
            .and_then(|session| session.observed_thread(&thread.id))
            .is_none()
    );

    // Missing history still permits the saved pause metadata; it is not corruption.
    tokio::fs::remove_file(paths.history_database()).await?;
    assert!(
        !runtime
            .thread_session_meta(&thread.id)
            .await?
            .execution_present
    );
    assert!(!paths.history_database().exists());
    runtime.shutdown_runtime().await?;
    Ok(())
}

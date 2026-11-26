use super::*;
use crate::studio::runtime::StudioRuntime;
use crate::studio::runtime::thread_observation::RetainedProjection;
use crate::studio::runtime::thread_service::test_support::{configure, options};
use crate::studio::thread_projection::LiveProjection;
use futures::poll;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio_util::sync::CancellationToken;

pub(super) struct SourceSelectionPause {
    pub(super) selected: CancellationToken,
    pub(super) resume: CancellationToken,
}

#[tokio::test]
async fn source_selection_follows_a_replaced_observation_without_reading_current() -> Result<()> {
    tokio::time::timeout(std::time::Duration::from_secs(30), async {
        let temporary = tempfile::tempdir()?;
        let home = temporary.path().join("home");
        let _endpoint = configure(&home).await?;
        let workspace = temporary.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let runtime = StudioRuntime::initialize(options(&home)).await?;
        let project = runtime.open_project(&workspace).await?;
        let thread = runtime
            .create_thread(&project.id, "replaced observer")
            .await?;
        let original = runtime.ensure_thread_owner(&thread.id).await?;
        runtime.synchronize_thread_observation(&thread.id).await?;
        let selected = CancellationToken::new();
        let resume = CancellationToken::new();
        *runtime
            .thread_observations
            .0
            .source_selection_pause
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(SourceSelectionPause {
            selected: selected.clone(),
            resume: resume.clone(),
        });
        let opening = runtime.open_conversation_feed(&thread.id, 8);
        tokio::pin!(opening);
        tokio::select! {
            result = &mut opening => panic!("source selection did not pause: {}", result.is_ok()),
            () = selected.cancelled() => {},
        }

        // The reader retains the old observation, but this does not block normal close/restart.
        runtime
            .require_session(&thread.id)?
            .close(&thread.id)
            .await?;
        let replacement = runtime.ensure_thread_owner(&thread.id).await?;
        assert_ne!(original.runtime_epoch(), replacement.runtime_epoch());
        runtime.synchronize_thread_observation(&thread.id).await?;
        runtime
            .store
            .conversation_store(&thread.id)
            .await?
            .flush_current(replacement.runtime_epoch())
            .await?;
        let path = runtime
            .store
            .registered_session_paths(&thread.id)?
            .current_file();
        tokio::fs::write(&path, b"invalid current after replacement is ready").await?;
        resume.cancel();

        let opened = opening.await;
        let result = match opened {
            Ok(feed) => {
                let actual = feed.session_meta_snapshot().owner_epoch;
                feed.close().await;
                anyhow::ensure!(actual == replacement.runtime_epoch().to_string());
                Ok(())
            }
            Err(error) => Err(error.context("ready replacement must not read the cold checkpoint")),
        };
        runtime.shutdown_runtime().await?;
        result
    })
    .await?
}

/// Hold the Store's existing initializer, so the real observer has registered but cannot publish.
/// No worker is replaced: failure, retry, Current cleanup and publication use production paths.
#[tokio::test]
async fn source_wait_reports_initialization_failure_and_preserves_its_owner_identity() -> Result<()>
{
    let temporary = tempfile::tempdir()?;
    let home = temporary.path().join("home");
    let _endpoint = configure(&home).await?;
    let workspace = temporary.path().join("workspace");
    tokio::fs::create_dir_all(&workspace).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let project = runtime.open_project(&workspace).await?;
    let thread = runtime
        .create_thread(&project.id, "initializing observation")
        .await?;
    runtime.shutdown_runtime().await?;
    drop(runtime);
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let conversation = runtime.store.conversation_store(&thread.id).await?;
    let release = CancellationToken::new();
    let fail = Arc::new(AtomicBool::new(true));
    let preparing = conversation.initialize_projection(Arc::new({
        let release = release.clone();
        let fail = fail.clone();
        let sessions = runtime.sessions.clone();
        let store = runtime.store.clone();
        let thread = thread.clone();
        move || {
            let (release, fail, sessions, store, thread) = (
                release.clone(),
                fail.clone(),
                sessions.clone(),
                store.clone(),
                thread.clone(),
            );
            Box::pin(async move {
                release.cancelled().await;
                anyhow::ensure!(
                    !fail.load(Ordering::Acquire),
                    "injected observation preparation failure"
                );
                let handle = sessions
                    .holding(&thread.id)
                    .and_then(|session| session.observed_thread(&thread.id))
                    .context("original execution must remain resident")?;
                let snapshot = handle.snapshot();
                let history = store.history(&thread.id).await?;
                let channel = store.thread_persistence().history_channel(&thread.id);
                let mut projection = LiveProjection::new();
                projection.bind_execution(
                    channel.order_index(),
                    handle.runtime_epoch(),
                    history.database_id().to_owned(),
                )?;
                projection.mark_bus_admitted();
                projection.restore_current(&thread.into(), &snapshot)?;
                Ok(RetainedProjection {
                    projection,
                    pending: None,
                    usage: snapshot.usage_summary,
                })
            })
        }
    }));
    tokio::pin!(preparing);
    assert!(poll!(preparing.as_mut()).is_pending());
    let owner = runtime.ensure_thread_owner(&thread.id).await?;
    let slot = runtime.thread_observations.observation_slot(&thread.id);
    let mut source = slot.subscribe_bus();
    let pending = runtime
        .thread_observations
        .ready_bus(&thread.id, &mut source);
    tokio::pin!(pending);
    assert!(
        poll!(pending.as_mut()).is_pending(),
        "initializing execution must not become a cold read"
    );
    assert!(
        slot.meta_bus().is_none(),
        "unprepared source must stay private"
    );
    release.cancel();
    assert!(preparing.await.is_err());
    let error = tokio::time::timeout(std::time::Duration::from_secs(10), pending)
        .await?
        .expect_err("initialization failure must end the reader wait");
    assert!(format!("{error:#}").contains("injected observation preparation failure"));
    assert_eq!(owner.snapshot().lifecycle, ThreadLifecycle::Closed);

    fail.store(false, Ordering::Release);
    // An explicit synchronization already owns retry semantics; a page never initiates retries.
    let observation = runtime
        .thread_observations
        .observations(Some(&thread.id))
        .pop()
        .unwrap()
        .1;
    let mut progress = observation.state.progress.subscribe();
    observation.state.retry.notify_one();
    tokio::time::timeout(std::time::Duration::from_secs(10), async {
        loop {
            if progress.borrow_and_update().initialized {
                break;
            }
            progress.changed().await?;
        }
        Ok::<_, anyhow::Error>(())
    })
    .await??;
    let feed = runtime.open_conversation_feed(&thread.id, 8).await?;
    let meta = feed.session_meta_snapshot();
    assert_eq!(meta.owner_epoch, owner.runtime_epoch().to_string());
    assert_eq!(
        runtime.thread_session_meta(&thread.id).await?.owner_epoch,
        meta.owner_epoch
    );
    feed.close().await;
    assert!(
        runtime
            .require_session(&thread.id)?
            .observed_thread(&thread.id)
            .unwrap()
            .same_instance(&owner)
    );

    // Closing outward delivery rejects even a prepared source, without taking execution ownership.
    runtime.thread_observations.close_deliveries();
    assert!(
        runtime
            .thread_observations
            .ready_bus(&thread.id, &mut slot.subscribe_bus())
            .await
            .is_err()
    );
    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn closing_delivery_ends_an_initialization_wait() -> Result<()> {
    let temporary = tempfile::tempdir()?;
    let home = temporary.path().join("home");
    let _endpoint = configure(&home).await?;
    let workspace = temporary.path().join("workspace");
    tokio::fs::create_dir_all(&workspace).await?;
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let project = runtime.open_project(&workspace).await?;
    let thread = runtime
        .create_thread(&project.id, "cancel observation wait")
        .await?;
    runtime.shutdown_runtime().await?;
    drop(runtime);
    let runtime = StudioRuntime::initialize(options(&home)).await?;
    let conversation = runtime.store.conversation_store(&thread.id).await?;
    let preparing =
        conversation.initialize_projection(Arc::new(|| Box::pin(std::future::pending())));
    tokio::pin!(preparing);
    assert!(poll!(preparing.as_mut()).is_pending());
    runtime.ensure_thread_owner(&thread.id).await?;
    let slot = runtime.thread_observations.observation_slot(&thread.id);
    let mut source = slot.subscribe_bus();
    let pending = runtime
        .thread_observations
        .ready_bus(&thread.id, &mut source);
    tokio::pin!(pending);
    assert!(poll!(pending.as_mut()).is_pending());
    runtime.thread_observations.close_deliveries();
    let error = tokio::time::timeout(std::time::Duration::from_secs(10), pending)
        .await?
        .expect_err("delivery cancellation must end the wait");
    assert!(error.to_string().contains("delivery closed"));
    // Delete has its own cancellation/join path, including an initializer that never completes.
    runtime
        .delete_thread("cancel-initializer".into(), thread.id.clone())
        .await?;
    runtime.shutdown_runtime().await?;
    Ok(())
}

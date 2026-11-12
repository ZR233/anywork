use super::*;
use pl_protocol::{
    CompletedTurnState, ThreadNotification, ThreadNotificationEnvelope, ThreadSnapshot,
    ThreadSubscriptionUpdate, Turn, TurnCompletion, TurnState,
    studio::{StudioError, StudioErrorCode, StudioErrorReason},
};
use tokio_util::sync::CancellationToken;

fn baseline(revision: u64) -> ThreadSubscriptionUpdate {
    let mut snapshot = ThreadSnapshot::empty("thread");
    snapshot.revision = revision;
    ThreadSubscriptionUpdate::Snapshot {
        completed_history_version: pl_protocol::COMPLETED_HISTORY_VERSION,
        snapshot: Box::new(snapshot),
    }
}

fn terminal(epoch: u64, base: u64) -> (ThreadSubscriptionUpdate, TurnAnchor) {
    let turn = Turn {
        id: "turn".into(),
        thread_id: "thread".into(),
        input_id: None,
        revision: 3,
        state: TurnState::Completed(CompletedTurnState::new(Some(1), 2, TurnCompletion::Normal)),
        updated_at: 2,
    };
    let anchor = TurnAnchor::from_turn(&turn).expect("terminal fixture");
    (
        ThreadSubscriptionUpdate::Notification {
            notification: Box::new(ThreadNotificationEnvelope::new(
                "thread",
                epoch,
                base,
                base + 1,
                2,
                ThreadNotification::TurnCompleted { turn },
            )),
        },
        anchor,
    )
}

#[test]
fn resync_segments_do_not_reuse_old_anchors_or_revision_domains() -> Result<()> {
    let directory = tempfile::tempdir()?;
    let sink = Evidence::new(directory.path().into())?;
    let mut file = sink.create("events.jsonl", "thread")?;
    let mut progress = EventProgress::new("thread")?;
    progress.observe(baseline(10))?;
    let (event, anchor) = terminal(7, 10);
    progress.observe(event)?;
    assert!(progress.match_target(anchor.clone())?);
    let error = anyhow::Error::new(
        StudioError::new(StudioErrorCode::Busy, "source replaced", true).with_reason(
            StudioErrorReason::ConversationResyncRequired,
            serde_json::json!({}),
        ),
    )
    .context("public feed");
    progress.invalidate(&error, &mut file)?;
    assert!(!progress.coverage.complete);
    assert!(!progress.coverage.interval_complete);
    assert!(progress.coverage.target.is_none());
    assert!(progress.coverage.matched_at.is_none());
    assert!(progress.coverage.consumed_last.is_none());
    assert!(!progress.match_target(anchor.clone())?);
    progress.observe(baseline(0))?;
    assert!(!progress.match_target(anchor.clone())?);
    // The same terminal identity has to be delivered again, now in the new segment's epoch.
    let (event, _) = terminal(1, 0);
    progress.observe(event)?;
    assert!(progress.match_target(anchor)?);
    assert!(!progress.coverage.complete);
    assert!(progress.coverage.error.is_none());
    progress.end_segment(None)?;
    let segments = &progress.coverage.segments;
    assert_eq!(segments.len(), 2);
    assert!(!segments[0].complete && segments[0].invalidated.is_some());
    assert_eq!(segments[0].initial_snapshot_revision, Some(10));
    assert!(segments[1].complete && segments[1].invalidated.is_none());
    assert_eq!(segments[1].initial_snapshot_revision, Some(0));
    assert_eq!(segments[1].matched_at.context("new match")?.epoch, 1);
    file.finish(true)?;
    Ok(())
}

#[test]
fn only_typed_source_invalidation_is_reopened() {
    for code in [
        StudioErrorCode::Busy,
        StudioErrorCode::NotFound,
        StudioErrorCode::PermissionDenied,
        StudioErrorCode::Storage,
        StudioErrorCode::Cancelled,
    ] {
        let error = anyhow::Error::new(StudioError::new(code, "conversationResyncRequired", true));
        assert!(super::super::state::resync_error(&error).is_none());
    }
    assert!(
        super::super::state::resync_error(&anyhow::anyhow!("conversationResyncRequired")).is_none()
    );
}

#[tokio::test]
async fn unactivated_public_state_baseline_and_writer_cleanup_do_not_require_checkpoint()
-> Result<()> {
    use pl_studio_runtime::{StudioHostKind, StudioRuntime, StudioRuntimeOptions};
    let directory = tempfile::tempdir()?;
    let repo = directory.path().join("workspace");
    std::fs::create_dir(&repo)?;
    let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
        studio_home: Some(directory.path().join("home")),
        host: StudioHostKind::Test,
        ..StudioRuntimeOptions::desktop()
    })
    .await?;
    let result: Result<()> = async {
        let project = runtime.open_project(&repo).await?;
        // This fresh home has no credentials. Public creation registers the session, then
        // activation fails before an owner/checkpoint is installed. No provider is contacted.
        let activation = runtime
            .create_thread(&project.id, "State writer cleanup")
            .await;
        anyhow::ensure!(
            activation.is_err(),
            "an unconfigured home cannot activate a model"
        );
        let state = runtime.read_state().await?;
        let members = &state
            .thread_directory
            .state
            .value()
            .context("ready directory")?
            .rows;
        anyhow::ensure!(members.len() == 1, "expected the registered Thread");
        let thread_id = &members[0].thread_id;
        anyhow::ensure!(
            runtime.thread_snapshot(thread_id).await.is_err(),
            "fixture unexpectedly has a saved snapshot"
        );
        let sink = Evidence::new(directory.path().into())?;
        let scene = super::super::Boundary::new(30, CancellationToken::new());
        let snapshot = super::super::state::snapshot(&runtime, thread_id, &scene).await?;
        anyhow::ensure!(
            &snapshot.thread.id == thread_id,
            "baseline identity mismatch"
        );
        anyhow::ensure!(
            snapshot.runtime.is_none() && snapshot.storage.is_none(),
            "fixture unexpectedly has an owner projection"
        );
        // No model is submitted. Each case owns a real passive feed and actual spawned writer.
        for cancel_scene in [false, true] {
            let interrupt = CancellationToken::new();
            let scene = super::super::Boundary::new(30, interrupt.clone());
            let feed = runtime.open_conversation_state_feed(thread_id).await?;
            let released = feed.cancellation_token();
            let mut writer = EventWriter::start(
                feed,
                &runtime,
                &scene,
                &sink,
                thread_id,
                usize::from(cancel_scene),
            )?;
            let baseline: Result<()> = async {
                while writer
                    .progress
                    .lock()
                    .map_err(|_| anyhow::anyhow!("event progress poisoned"))?
                    .coverage
                    .initial_snapshot_revision
                    .is_none()
                {
                    scene
                        .read(async { writer.changed.changed().await.context("writer baseline") })
                        .await?;
                }
                Ok(())
            }
            .await;
            if cancel_scene {
                interrupt.cancel();
            }
            let coverage = writer
                .finish(Err(anyhow::anyhow!("no submitted Turn")), &scene)
                .await?;
            baseline?;
            anyhow::ensure!(
                released.is_cancelled(),
                "join must release the real State feed"
            );
            anyhow::ensure!(
                !coverage.complete && !coverage.capture_complete,
                "missing anchor cannot complete coverage"
            );
            anyhow::ensure!(
                coverage
                    .error
                    .as_ref()
                    .is_some_and(|error| error.contains("no submitted Turn")),
                "missing anchor must remain visible"
            );
            anyhow::ensure!(
                coverage.segments.len() == 1,
                "unexpected source replacement"
            );
        }
        let records = std::fs::read_to_string(directory.path().join("files.jsonl"))?;
        anyhow::ensure!(
            records.lines().count() == 2,
            "both writer files must be finalized"
        );
        Ok(())
    }
    .await;
    let shutdown = runtime.shutdown_runtime().await;
    result.with_context(|| format!("runtime cleanup: {:?}", shutdown.as_ref().map(|_| ())))?;
    shutdown?;
    Ok(())
}

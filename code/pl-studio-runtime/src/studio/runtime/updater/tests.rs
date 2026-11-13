use super::*;
use crate::studio::{StudioStore, agent_host::ThreadWriteBehindWriter};
use crate::{StudioProductEventKind, StudioProductTopic};
use pl_studio_update::{StudioUpdateAsset, StudioUpdateError};
use std::{
    collections::VecDeque,
    sync::atomic::{AtomicUsize, Ordering},
};

pub(super) enum CheckStep {
    Value(Result<StudioUpdateCheck, StudioUpdateError>),
    Panic,
}
pub(super) enum DownloadStep {
    Ready,
    Fail(StudioUpdateErrorCode),
    Panic,
    InvalidProgress,
    Wait(Arc<tokio::sync::Notify>),
}
pub(super) struct TestIo {
    checks: Mutex<VecDeque<CheckStep>>,
    downloads: Mutex<VecDeque<DownloadStep>>,
    calls: AtomicUsize,
    checked: tokio::sync::Notify,
    download_started: tokio::sync::Notify,
    live_downloads: AtomicUsize,
    path: std::path::PathBuf,
}
impl TestIo {
    pub(super) async fn check(&self) -> Result<StudioUpdateCheck, StudioUpdateError> {
        self.calls.fetch_add(1, Ordering::SeqCst);
        self.checked.notify_one();
        let next = self.checks.lock().await.pop_front();
        match next {
            Some(CheckStep::Value(value)) => value,
            Some(CheckStep::Panic) => panic!("injected check panic"),
            None => Ok(StudioUpdateCheck::UpToDate),
        }
    }
    pub(super) async fn download(
        &self,
        events: tokio::sync::mpsc::UnboundedSender<StudioUpdateEvent>,
        cancellation: StudioUpdateCancellation,
    ) -> Result<InstallerLease, StudioUpdateError> {
        struct Live<'a>(&'a AtomicUsize);
        impl Drop for Live<'_> {
            fn drop(&mut self) {
                self.0.fetch_sub(1, Ordering::SeqCst);
            }
        }
        self.live_downloads.fetch_add(1, Ordering::SeqCst);
        self.download_started.notify_one();
        let _live = Live(&self.live_downloads);
        let step = self
            .downloads
            .lock()
            .await
            .pop_front()
            .expect("expected a scripted download");
        events
            .send(StudioUpdateEvent::Started { total: 100 })
            .unwrap();
        let error = match step {
            DownloadStep::Fail(code) => Some(code),
            DownloadStep::Panic => panic!("injected download panic"),
            DownloadStep::InvalidProgress => {
                events
                    .send(StudioUpdateEvent::Progress {
                        downloaded: 101,
                        total: 100,
                    })
                    .unwrap();
                cancellation.cancelled().await;
                Some(StudioUpdateErrorCode::Cancelled)
            }
            DownloadStep::Wait(release) => {
                tokio::select! {
                    _ = release.notified() => None,
                    _ = cancellation.cancelled() => Some(StudioUpdateErrorCode::Cancelled),
                }
            }
            DownloadStep::Ready => None,
        };
        if let Some(code) = error {
            let error = StudioUpdateError::new(code, "injected download failure");
            let _ = events.send(StudioUpdateEvent::Failed {
                code: error.code().as_str().into(),
                message: error.to_string(),
            });
            return Err(error);
        }
        events
            .send(StudioUpdateEvent::Progress {
                downloaded: 100,
                total: 100,
            })
            .unwrap();
        events.send(StudioUpdateEvent::Verifying).unwrap();
        Ok(InstallerLease::Test {
            _lease: std::fs::File::open(&self.path).unwrap(),
        })
    }
}
fn update(version: &str) -> StudioUpdate {
    StudioUpdate {
        version: version.into(),
        published_at: 1,
        notes_url: "https://example.test/notes".into(),
        installer: StudioUpdateAsset {
            url: "https://example.test/setup.exe".into(),
            size: 100,
            sha256: "0".repeat(64),
            signature: "https://example.test/setup.exe.minisig".into(),
        },
    }
}
fn available(version: &str) -> CheckStep {
    CheckStep::Value(Ok(StudioUpdateCheck::Available(update(version))))
}
async fn fixture(
    checks: Vec<CheckStep>,
    downloads: Vec<DownloadStep>,
) -> Result<(tempfile::TempDir, StudioUpdateRuntime, Arc<TestIo>)> {
    let temp = tempfile::tempdir()?;
    let mut owner = StudioUpdateRuntime::with_publisher(Arc::new(|_| {}))?;
    let path = temp.path().join("verified-installer");
    std::fs::write(&path, "test installer lease")?;
    let io = Arc::new(TestIo {
        checks: Mutex::new(checks.into()),
        downloads: Mutex::new(downloads.into()),
        calls: AtomicUsize::new(0),
        checked: tokio::sync::Notify::new(),
        download_started: tokio::sync::Notify::new(),
        live_downloads: AtomicUsize::new(0),
        path,
    });
    owner.test_io = Some(Arc::clone(&io));
    Ok((temp, owner, io))
}
async fn settle(owner: &StudioUpdateRuntime, io: &TestIo, calls: usize) {
    while io.calls.load(Ordering::SeqCst) < calls {
        tokio::time::timeout(std::time::Duration::from_secs(1), io.checked.notified())
            .await
            .expect("scheduled check did not start");
    }
    let round = owner.active.lock().await.clone();
    if let Some(round) = round {
        let _ = tokio::time::timeout(std::time::Duration::from_secs(1), round.wait())
            .await
            .expect("update round did not finish");
    }
}
async fn download_started(io: &TestIo) {
    while io.live_downloads.load(Ordering::SeqCst) == 0 {
        tokio::time::timeout(
            std::time::Duration::from_secs(1),
            io.download_started.notified(),
        )
        .await
        .expect("download did not start");
    }
}
async fn next(owner: &StudioUpdateRuntime, io: &TestIo, calls: usize) {
    tokio::time::advance(automatic::CHECK_INTERVAL).await;
    settle(owner, io, calls).await;
}

#[tokio::test]
async fn updater_errors_and_panics_never_end_the_twenty_minute_loop() -> Result<()> {
    let (_temp, owner, io) = fixture(
        vec![
            CheckStep::Value(Err(StudioUpdateError::new(
                StudioUpdateErrorCode::Network,
                "offline",
            ))),
            CheckStep::Value(Err(StudioUpdateError::new(
                StudioUpdateErrorCode::InvalidManifest,
                "invalid manifest",
            ))),
            CheckStep::Panic,
            available("2.0.0"),
            available("2.0.0"),
            available("2.0.0"),
            available("2.0.0"),
            available("2.0.0"),
        ],
        vec![
            DownloadStep::Fail(StudioUpdateErrorCode::Network),
            DownloadStep::Fail(StudioUpdateErrorCode::SignatureInvalid),
            DownloadStep::Panic,
            DownloadStep::InvalidProgress,
            DownloadStep::Ready,
        ],
    )
    .await?;
    tokio::time::pause();
    let stop = StudioUpdateCancellation::new();
    let task = tokio::spawn({
        let owner = owner.clone();
        let stop = stop.clone();
        async move { owner.run_automatic(stop).await }
    });
    settle(&owner, &io, 1).await;
    assert!(matches!(
        owner.read().await.activity,
        StudioUpdateActivity::CheckFailed(_)
    ));
    tokio::time::advance(automatic::CHECK_INTERVAL - std::time::Duration::from_secs(1)).await;
    tokio::task::yield_now().await;
    assert_eq!(io.calls.load(Ordering::SeqCst), 1);
    tokio::time::advance(std::time::Duration::from_secs(1)).await;
    settle(&owner, &io, 2).await;
    for calls in 3..=8 {
        next(&owner, &io, calls).await;
        assert_eq!(io.live_downloads.load(Ordering::SeqCst), 0);
        assert!(!task.is_finished());
    }
    assert_eq!(
        owner.read().await.ready_update.unwrap().update.version,
        "2.0.0"
    );
    stop.cancel();
    task.await?;
    assert!(owner.active.lock().await.is_none());
    Ok(())
}

#[tokio::test]
async fn updater_retains_ready_lease_across_failures_and_replaces_only_after_verification()
-> Result<()> {
    let (_temp, owner, io) = fixture(
        vec![
            available("2.0.0"),
            available("2.0.0"),
            available("1.5.0"),
            available("3.0.0"),
            available("3.0.0"),
        ],
        vec![
            DownloadStep::Ready,
            DownloadStep::Fail(StudioUpdateErrorCode::Network),
            DownloadStep::Ready,
        ],
    )
    .await?;
    tokio::time::pause();
    let stop = StudioUpdateCancellation::new();
    let task = tokio::spawn({
        let owner = owner.clone();
        let stop = stop.clone();
        async move { owner.run_automatic(stop).await }
    });
    settle(&owner, &io, 1).await;
    for calls in 2..=4 {
        next(&owner, &io, calls).await;
        let state = owner.read().await;
        assert_eq!(state.ready_update.unwrap().update.version, "2.0.0");
        assert_eq!(
            owner
                .prepared
                .lock()
                .await
                .installer
                .as_ref()
                .unwrap()
                .0
                .update
                .version,
            "2.0.0"
        );
    }
    assert!(matches!(
        owner.read().await.activity,
        StudioUpdateActivity::InstallFailed(_)
    ));
    next(&owner, &io, 5).await;
    assert_eq!(
        owner.read().await.ready_update.unwrap().update.version,
        "3.0.0"
    );
    assert!(
        io.downloads.lock().await.is_empty(),
        "same/older versions must not download"
    );
    stop.cancel();
    task.await?;
    Ok(())
}

#[tokio::test]
async fn updater_cancel_only_stops_this_round_and_shutdown_joins_the_next_one() -> Result<()> {
    let release = Arc::new(tokio::sync::Notify::new());
    let (_temp, owner, io) = fixture(
        vec![available("2.0.0"), available("2.0.0")],
        vec![
            DownloadStep::Wait(release.clone()),
            DownloadStep::Wait(release),
        ],
    )
    .await?;
    tokio::time::pause();
    let stop = StudioUpdateCancellation::new();
    let task = tokio::spawn({
        let owner = owner.clone();
        let stop = stop.clone();
        async move { owner.run_automatic(stop).await }
    });
    download_started(&io).await;
    assert_eq!(io.live_downloads.load(Ordering::SeqCst), 1);
    owner.cancel_current().await?;
    assert_eq!(io.live_downloads.load(Ordering::SeqCst), 0);
    assert!(!task.is_finished());
    tokio::time::advance(automatic::CHECK_INTERVAL).await;
    download_started(&io).await;
    assert_eq!(io.calls.load(Ordering::SeqCst), 2);
    assert_eq!(io.live_downloads.load(Ordering::SeqCst), 1);
    stop.cancel();
    task.await?;
    assert_eq!(io.live_downloads.load(Ordering::SeqCst), 0);
    assert!(owner.active.lock().await.is_none());
    Ok(())
}

#[tokio::test]
async fn updater_manual_preparation_joins_only_current_round_and_pins_its_version() -> Result<()> {
    let release = Arc::new(tokio::sync::Notify::new());
    let (_temp, owner, io) = fixture(
        vec![available("2.0.0")],
        vec![DownloadStep::Wait(release.clone())],
    )
    .await?;
    tokio::time::pause();
    let stop = StudioUpdateCancellation::new();
    let task = tokio::spawn({
        let owner = owner.clone();
        let stop = stop.clone();
        async move { owner.run_automatic(stop).await }
    });
    download_started(&io).await;
    let selection = StudioUpdateCancellation::new();
    let manual = tokio::spawn({
        let owner = owner.clone();
        let selection = selection.clone();
        async move { owner.prepare_selected(0, "2.0.0", selection).await }
    });
    tokio::task::yield_now().await;
    release.notify_one();
    assert_eq!(
        manual.await??,
        StudioUpdatePreparationResult::Ready {
            version: "2.0.0".into()
        }
    );
    assert!(
        !task.is_finished(),
        "preparation completion never waits for scheduler exit"
    );
    tokio::time::advance(automatic::CHECK_INTERVAL).await;
    tokio::task::yield_now().await;
    assert_eq!(
        io.calls.load(Ordering::SeqCst),
        1,
        "selected installer cannot be replaced before exit"
    );
    selection.cancel();
    next(&owner, &io, 2).await;
    stop.cancel();
    task.await?;
    Ok(())
}

#[tokio::test]
async fn updater_selecting_retained_ready_cancels_new_candidate_and_preserves_target() -> Result<()>
{
    let release = Arc::new(tokio::sync::Notify::new());
    let (_temp, owner, io) = fixture(
        vec![available("2.0.0"), available("3.0.0")],
        vec![DownloadStep::Ready, DownloadStep::Wait(release)],
    )
    .await?;
    tokio::time::pause();
    let stop = StudioUpdateCancellation::new();
    let task = tokio::spawn({
        let owner = owner.clone();
        let stop = stop.clone();
        async move { owner.run_automatic(stop).await }
    });
    settle(&owner, &io, 1).await;
    tokio::time::advance(automatic::CHECK_INTERVAL).await;
    download_started(&io).await;
    assert_eq!(
        owner
            .prepare_selected(0, "2.0.0", StudioUpdateCancellation::new())
            .await?,
        StudioUpdatePreparationResult::Ready {
            version: "2.0.0".into()
        }
    );
    assert_eq!(io.live_downloads.load(Ordering::SeqCst), 0);
    assert_eq!(
        owner.read().await.ready_update.unwrap().update.version,
        "2.0.0"
    );
    stop.cancel();
    task.await?;
    Ok(())
}

#[tokio::test]
async fn updater_topics_fan_out_committed_state_and_late_reads_share_the_same_revision()
-> Result<()> {
    let (temp, mut owner, _io) = fixture(vec![available("2.0.0")], vec![]).await?;
    let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
    let writer = ThreadWriteBehindWriter::new(store.clone());
    let events = crate::ProductEventBus::new(store, writer);
    let publisher = events.clone();
    owner.events = Arc::new(move |state| {
        publisher.emit_updater_state(state);
    });
    let mut first = events.subscribe_topic(&StudioProductTopic::Updater);
    let mut second = events.subscribe_topic(&StudioProductTopic::Updater);
    owner
        .check_cancellable(&StudioUpdateCancellation::new())
        .await?;
    let mut last = None;
    while let Ok(event) = first.try_recv() {
        let other = second.try_recv()?;
        assert_eq!(event.sequence, other.sequence);
        if let StudioProductEventKind::UpdaterStateChanged(state) = event.kind {
            last = Some(state);
        }
    }
    assert_eq!(last.unwrap(), owner.read().await);
    drop(first);
    owner
        .check_cancellable(&StudioUpdateCancellation::new())
        .await?;
    assert!(second.try_recv().is_ok());
    Ok(())
}

#[tokio::test(start_paused = true)]
async fn updater_waking_after_missed_ticks_does_not_burst_or_overlap() {
    let stop = StudioUpdateCancellation::new();
    let count = Arc::new(AtomicUsize::new(0));
    let (entered, mut entries) = tokio::sync::mpsc::unbounded_channel();
    let task = tokio::spawn({
        let stop = stop.clone();
        let count = count.clone();
        async move {
            automatic::schedule(&stop, || {
                let count = count.clone();
                let entered = entered.clone();
                async move {
                    let n = count.fetch_add(1, Ordering::SeqCst);
                    entered.send(n).unwrap();
                    if n == 0 {
                        tokio::time::sleep(automatic::CHECK_INTERVAL * 4).await;
                    }
                }
            })
            .await;
        }
    });
    assert_eq!(entries.recv().await, Some(0));
    tokio::time::advance(automatic::CHECK_INTERVAL * 4).await;
    assert_eq!(entries.recv().await, Some(1));
    for _ in 0..10 {
        tokio::task::yield_now().await;
    }
    assert_eq!(count.load(Ordering::SeqCst), 2);
    stop.cancel();
    task.await.unwrap();
}

#[tokio::test]
async fn updater_stale_selection_is_a_command_failure_and_leaves_no_failed_resource_owner()
-> Result<()> {
    let (_temp, owner, _io) = fixture(vec![], vec![]).await?;
    let result = owner
        .prepare_selected(0, "no-longer-available", StudioUpdateCancellation::new())
        .await?;
    assert!(
        matches!(result, StudioUpdatePreparationResult::Failed { error } if error.code == "conflict")
    );
    assert!(owner.active.lock().await.is_none());
    assert!(owner.prepared.lock().await.selection().is_none());
    owner
        .check_cancellable(&StudioUpdateCancellation::new())
        .await?;
    assert!(matches!(
        owner.read().await.activity,
        StudioUpdateActivity::UpToDate(_)
    ));
    Ok(())
}

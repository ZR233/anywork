//! Process-owned update scheduling, current operation, and verified installer lease.

mod automatic;
mod state;

pub use state::*;

use std::panic::AssertUnwindSafe;
use std::sync::Arc;

use anyhow::{Context, Result};
use futures::{
    FutureExt,
    future::{BoxFuture, Shared},
};
use pl_protocol::StateError;
use serde::{Deserialize, Serialize};
use tokio::sync::{Mutex, RwLock};

use crate::studio::ids::unix_seconds;
use pl_studio_update::STUDIO_VERSION;
use pl_studio_update::{
    StudioUpdate, StudioUpdateCancellation, StudioUpdateCheck, StudioUpdateErrorCode,
    StudioUpdateEvent, StudioUpdater,
};

/// Command completion, not a second delivery path for canonical snapshots.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase")]
pub enum StudioUpdatePreparationResult {
    Ready { version: String },
    Cancelled,
    Failed { error: StateError },
}

// A publishing callback keeps clock/error tests independent of the product bus's database.
// Production installs exactly one callback to the existing ProductEventBus.
type UpdatePublisher = Arc<dyn Fn(StudioUpdateStateSnapshot) + Send + Sync>;

enum InstallerLease {
    Verified(Box<pl_studio_update::PreparedStudioUpdate>),
    #[cfg(test)]
    Test {
        _lease: std::fs::File,
    },
}
impl InstallerLease {
    async fn launch(&mut self) -> Result<(), pl_studio_update::StudioUpdateError> {
        match self {
            Self::Verified(installer) => installer.launch().await,
            #[cfg(test)]
            Self::Test { .. } => Err(pl_studio_update::StudioUpdateError::new(
                StudioUpdateErrorCode::UnsupportedPlatform,
                "test installer leases cannot launch processes",
            )),
        }
    }

    async fn abort_install(&mut self) -> Result<(), pl_studio_update::StudioUpdateError> {
        match self {
            Self::Verified(installer) => installer.abort_install().await,
            #[cfg(test)]
            Self::Test { .. } => Ok(()),
        }
    }

    async fn prepare_install(
        &mut self,
        cancellation: &StudioUpdateCancellation,
    ) -> Result<(), pl_studio_update::StudioUpdateError> {
        match self {
            Self::Verified(installer) => installer.prepare_install(cancellation).await,
            #[cfg(test)]
            Self::Test { .. } => Ok(()),
        }
    }
}

#[derive(Default)]
struct PreparedUpdate {
    installer: Option<(StudioReadyUpdate, InstallerLease)>,
    selected_version: Option<String>,
    selection_cancellation: Option<StudioUpdateCancellation>,
    launched_version: Option<String>,
}

impl PreparedUpdate {
    fn selection(&self) -> Option<&str> {
        // Cancellation is only a signal. Keep the reservation until the owner
        // has joined the platform handoff and released it explicitly.
        self.selected_version.as_deref()
    }
}

struct UpdateRound {
    cancellation: StudioUpdateCancellation,
    completion: Shared<BoxFuture<'static, Result<(), Arc<String>>>>,
}

impl UpdateRound {
    async fn wait(&self) -> Result<()> {
        self.completion
            .clone()
            .await
            .map_err(|error| anyhow::anyhow!("{error}"))
    }
}

enum RoundKind {
    Check,
    Automatic,
    Prepare(StudioUpdate),
}

#[derive(Clone)]
pub(crate) struct StudioUpdateRuntime {
    updater: StudioUpdater,
    #[cfg(test)]
    test_io: Option<Arc<tests::TestIo>>,
    active: Arc<Mutex<Option<Arc<UpdateRound>>>>,
    state: Arc<RwLock<StudioUpdateStateSnapshot>>,
    events: UpdatePublisher,
    prepared: Arc<Mutex<PreparedUpdate>>,
}

impl StudioUpdateRuntime {
    pub(crate) async fn record_installation_failure(&self, message: String) -> Result<()> {
        let mut state = self.state.write().await;
        anyhow::ensure!(
            state.revision() == 0 && matches!(state.activity, StudioUpdateActivity::Idle(_)),
            "installation outcome must precede updater publication"
        );
        state.installation_error = Some(StateError {
            code: "installerFailed".into(),
            message,
            retryable: true,
        });
        Ok(())
    }

    pub(crate) async fn abort_cancelled_installation(&self) -> Result<()> {
        let mut prepared = self.prepared.lock().await;
        if prepared
            .selection_cancellation
            .as_ref()
            .is_some_and(StudioUpdateCancellation::is_cancelled)
        {
            if let Some((_, InstallerLease::Verified(installer))) = prepared.installer.as_mut() {
                installer.abort_install().await?;
            }
            prepared.selected_version = None;
            prepared.selection_cancellation = None;
        }
        Ok(())
    }

    pub(crate) async fn abort_installation(&self) -> Result<()> {
        let mut prepared = self.prepared.lock().await;
        if let Some((_, InstallerLease::Verified(installer))) = prepared.installer.as_mut() {
            installer.abort_install().await?;
        }
        prepared.selected_version = None;
        prepared.selection_cancellation = None;
        Ok(())
    }

    pub(crate) fn new(events: crate::ProductEventBus) -> Result<Self> {
        Self::with_publisher(Arc::new(move |state| {
            events.emit_updater_state(state);
        }))
    }

    fn with_publisher(events: UpdatePublisher) -> Result<Self> {
        Ok(Self {
            updater: StudioUpdater::new_default()?,
            #[cfg(test)]
            test_io: None,
            active: Arc::new(Mutex::new(None)),
            state: Arc::new(RwLock::new(
                if pl_studio_update::StudioUpdatePlatform::current().is_some() {
                    StudioUpdateStateSnapshot::idle(unix_seconds())
                } else {
                    StudioUpdateStateSnapshot::disabled(unix_seconds())
                },
            )),
            events,
            prepared: Arc::new(Mutex::new(PreparedUpdate::default())),
        })
    }

    pub(crate) async fn read(&self) -> StudioUpdateStateSnapshot {
        self.state.read().await.clone()
    }

    pub(crate) async fn check_cancellable(
        &self,
        cancellation: &StudioUpdateCancellation,
    ) -> Result<()> {
        self.abort_cancelled_installation().await?;
        let round = {
            let mut active = self.active.lock().await;
            if active.is_some() || self.prepared.lock().await.selection().is_some() {
                return Err(busy());
            }
            self.spawn_round(&mut active, RoundKind::Check, cancellation.clone())
        };
        round.wait().await
    }

    /// A retained scheduler owns one round at a time; UI cancellation never cancels `stop`.
    pub(crate) async fn run_automatic(&self, stop: StudioUpdateCancellation) {
        automatic::schedule(&stop, || async {
            if let Err(error) = self.abort_cancelled_installation().await {
                self.publish_owner_failure(&error).await;
                return;
            }
            let round = {
                let mut active = self.active.lock().await;
                if active.is_some() || self.prepared.lock().await.selection().is_some() {
                    return;
                }
                self.spawn_round(
                    &mut active,
                    RoundKind::Automatic,
                    StudioUpdateCancellation::new(),
                )
            };
            tokio::select! {
                biased;
                _ = stop.cancelled() => round.cancellation.cancel(),
                _ = round.completion.clone() => {}
            }
            // Cancellation is only a signal. Retain and join the real round.
            let _ = round.wait().await;
        })
        .await;
    }

    /// Freeze the current identity before cancellation; never cancel a later round.
    pub(crate) async fn cancel_current(&self) -> Result<()> {
        let round = self.active.lock().await.clone();
        if let Some(round) = round {
            round.cancellation.cancel();
            round.wait().await?;
        }
        Ok(())
    }

    /// Reserve the selected version before awaiting any active background work.
    pub(crate) async fn prepare_selected(
        &self,
        expected_revision: u64,
        version: &str,
        cancellation: StudioUpdateCancellation,
    ) -> Result<StudioUpdatePreparationResult> {
        if cancellation.is_cancelled() {
            return Ok(StudioUpdatePreparationResult::Cancelled);
        }
        self.abort_cancelled_installation().await?;
        let round = {
            let mut active = self.active.lock().await;
            let mut prepared = self.prepared.lock().await;
            let state = self.read().await;
            if state.revision() < expected_revision {
                return Ok(rejected_selection("update revision conflict"));
            }
            if prepared
                .selection()
                .is_some_and(|selected| selected != version)
            {
                return Ok(rejected_selection("another update version is selected"));
            }
            let ready = prepared
                .installer
                .as_ref()
                .is_some_and(|(ready, _)| ready.update.version == version);
            let candidate = state
                .activity
                .update()
                .filter(|update| update.version == version)
                .cloned();
            if !ready && candidate.is_none() {
                return Ok(rejected_selection(
                    "requested update is no longer available",
                ));
            }
            prepared.selected_version = Some(version.to_string());
            prepared.selection_cancellation = Some(cancellation.clone());
            if let Some(round) = active.as_ref() {
                if ready {
                    round.cancellation.cancel();
                }
                Some(Arc::clone(round))
            } else if ready {
                None
            } else {
                Some(self.spawn_round(
                    &mut active,
                    RoundKind::Prepare(candidate.context("missing update candidate")?),
                    cancellation.clone(),
                ))
            }
        };
        if let Some(round) = round {
            tokio::select! {
                biased;
                _ = cancellation.cancelled() => round.cancellation.cancel(),
                _ = round.completion.clone() => {}
            }
            let _ = round.wait().await;
        }
        let mut prepared = self.prepared.lock().await;
        // A cancelled request must not leave a latent restart reservation.
        if !cancellation.is_cancelled()
            && prepared
                .installer
                .as_ref()
                .is_some_and(|(ready, _)| ready.update.version == version)
        {
            let installer = &mut prepared
                .installer
                .as_mut()
                .expect("selected installer exists")
                .1;
            match installer.prepare_install(&cancellation).await {
                Ok(()) if !cancellation.is_cancelled() => {
                    return Ok(StudioUpdatePreparationResult::Ready {
                        version: version.to_string(),
                    });
                }
                result => {
                    installer.abort_install().await?;
                    prepared.selected_version = None;
                    prepared.selection_cancellation = None;
                    drop(prepared);
                    let error = result.err().unwrap_or_else(|| {
                        pl_studio_update::StudioUpdateError::new(
                            StudioUpdateErrorCode::Cancelled,
                            "update installation cancelled",
                        )
                    });
                    let cancelled = cancellation.is_cancelled()
                        || error.code() == StudioUpdateErrorCode::Cancelled;
                    let failure = state_error(&error);
                    self.publish_owner_failure(&error.into()).await;
                    return Ok(if cancelled {
                        StudioUpdatePreparationResult::Cancelled
                    } else {
                        StudioUpdatePreparationResult::Failed { error: failure }
                    });
                }
            }
        }
        prepared.selected_version = None;
        prepared.selection_cancellation = None;
        let state = self.read().await;
        let error = match &state.activity {
            StudioUpdateActivity::CheckFailed(value) => value.error().clone(),
            StudioUpdateActivity::InstallFailed(value) => value.error().clone(),
            _ => StateError {
                code: "cancelled".into(),
                message: "Studio update preparation was cancelled".into(),
                retryable: true,
            },
        };
        if cancellation.is_cancelled() || error.code == "cancelled" {
            Ok(StudioUpdatePreparationResult::Cancelled)
        } else {
            Ok(StudioUpdatePreparationResult::Failed { error })
        }
    }

    /// Called while admission is locked; completion exists before tasks can publish anything.
    fn spawn_round(
        &self,
        active: &mut Option<Arc<UpdateRound>>,
        kind: RoundKind,
        cancellation: StudioUpdateCancellation,
    ) -> Arc<UpdateRound> {
        let (completed, completion) = tokio::sync::oneshot::channel();
        let round = Arc::new(UpdateRound {
            cancellation,
            completion: async move {
                completion
                    .await
                    .unwrap_or_else(|_| Err(Arc::new("update round completion was lost".into())))
            }
            .boxed()
            .shared(),
        });
        *active = Some(Arc::clone(&round));
        let owner = self.clone();
        let token = round.cancellation.clone();
        let task = tokio::spawn(async move { owner.perform_round(kind, token).await });
        let owner = self.clone();
        let observed = Arc::clone(&round);
        tokio::spawn(async move {
            let result = match task.await {
                Ok(result) => result,
                Err(_) => Err(anyhow::anyhow!("Studio update round panicked")),
            };
            if let Err(error) = &result {
                tracing::warn!(error = %error, "Studio update round failed; scheduler remains active");
                // Recovery must not retain a failed round, even if its event publisher panics.
                if AssertUnwindSafe(owner.publish_owner_failure(error))
                    .catch_unwind()
                    .await
                    .is_err()
                {
                    tracing::error!("Studio update failure publication panicked");
                }
            }
            let mut active = owner.active.lock().await;
            if active
                .as_ref()
                .is_some_and(|current| Arc::ptr_eq(current, &observed))
            {
                *active = None;
            }
            let _ = completed.send(result.map_err(|error| Arc::new(format!("{error:#}"))));
        });
        round
    }

    async fn perform_round(
        &self,
        kind: RoundKind,
        cancellation: StudioUpdateCancellation,
    ) -> Result<()> {
        let update = match kind {
            RoundKind::Prepare(update) => Some(update),
            RoundKind::Check | RoundKind::Automatic => {
                let state = self.check(&cancellation).await?;
                if matches!(kind, RoundKind::Automatic) {
                    match state.activity {
                        StudioUpdateActivity::Available(value) => Some(value.update().clone()),
                        _ => None,
                    }
                } else {
                    None
                }
            }
        };
        if let Some(update) = update {
            self.prepare(update, cancellation).await?;
        }
        Ok(())
    }

    async fn fetch_update(&self) -> Result<StudioUpdateCheck, pl_studio_update::StudioUpdateError> {
        #[cfg(test)]
        if let Some(io) = &self.test_io {
            return io.check().await;
        }
        self.updater.check(STUDIO_VERSION.trim()).await
    }

    async fn download_update(
        &self,
        update: StudioUpdate,
        events: tokio::sync::mpsc::UnboundedSender<StudioUpdateEvent>,
        cancellation: StudioUpdateCancellation,
    ) -> Result<InstallerLease, pl_studio_update::StudioUpdateError> {
        #[cfg(test)]
        if let Some(io) = &self.test_io {
            return io.download(events, cancellation).await;
        }
        self.updater
            .download(update, events, cancellation)
            .await
            .map(|installer| InstallerLease::Verified(Box::new(installer)))
    }

    async fn check(
        &self,
        cancellation: &StudioUpdateCancellation,
    ) -> Result<StudioUpdateStateSnapshot> {
        let previous = self.read().await;
        let running = self
            .apply(StudioUpdateCommand::BeginCheck {
                expected_revision: previous.revision(),
                operation_id: format!("studio-update-check-{}", previous.revision() + 1),
                started_at: unix_seconds(),
            })
            .await?;
        let result = tokio::select! {
            biased;
            _ = cancellation.cancelled() => Err(pl_studio_update::StudioUpdateError::new(StudioUpdateErrorCode::Cancelled, "Studio update check was cancelled")),
            result = self.fetch_update() => result,
        };
        let checked_at = unix_seconds();
        let command = match result {
            Ok(StudioUpdateCheck::UpToDate) => StudioUpdateCommand::FinishUpToDate {
                expected_revision: running.revision(),
                checked_at,
            },
            Ok(StudioUpdateCheck::Available(update)) => {
                let newer = running.ready_update.as_ref().is_none_or(|ready| {
                    semver::Version::parse(&update.version).ok()
                        > semver::Version::parse(&ready.update.version).ok()
                });
                if newer {
                    StudioUpdateCommand::FinishAvailable {
                        expected_revision: running.revision(),
                        checked_at,
                        update,
                    }
                } else {
                    StudioUpdateCommand::FinishUpToDate {
                        expected_revision: running.revision(),
                        checked_at,
                    }
                }
            }
            Err(error) => {
                tracing::warn!(code = error.code().as_str(), error = %error, "Studio update check failed");
                StudioUpdateCommand::FailCheck {
                    expected_revision: running.revision(),
                    failed_at: checked_at,
                    error: state_error(&error),
                }
            }
        };
        self.apply(command).await
    }

    async fn apply_install_event(
        &self,
        event: StudioUpdateEvent,
        update: &StudioUpdate,
    ) -> Result<()> {
        let current = self.read().await;
        let now = unix_seconds();
        let command = match event {
            StudioUpdateEvent::Started { total } => StudioUpdateCommand::BeginDownload {
                expected_revision: current.revision(),
                updated_at: now,
                update: update.clone(),
                total,
            },
            StudioUpdateEvent::Progress { downloaded, total } => {
                StudioUpdateCommand::ReportDownload {
                    expected_revision: current.revision(),
                    updated_at: now,
                    downloaded,
                    total,
                }
            }
            StudioUpdateEvent::Verifying => StudioUpdateCommand::BeginVerify {
                expected_revision: current.revision(),
                updated_at: now,
            },
            StudioUpdateEvent::Failed { code, message } => StudioUpdateCommand::FailInstall {
                expected_revision: current.revision(),
                failed_at: now,
                error: StateError {
                    retryable: matches!(code.as_str(), "network" | "io" | "cancelled"),
                    code,
                    message,
                },
            },
        };
        self.apply(command).await?;
        Ok(())
    }

    async fn prepare(
        &self,
        update: StudioUpdate,
        cancellation: StudioUpdateCancellation,
    ) -> Result<()> {
        let (events, mut receiver) = tokio::sync::mpsc::unbounded_channel();
        let download =
            AssertUnwindSafe(self.download_update(update.clone(), events, cancellation.clone()))
                .catch_unwind();
        let projection = async {
            let outcome = AssertUnwindSafe(async {
                while let Some(event) = receiver.recv().await {
                    self.apply_install_event(event, &update).await?;
                }
                Ok::<_, anyhow::Error>(())
            })
            .catch_unwind()
            .await;
            if !matches!(outcome, Ok(Ok(()))) {
                cancellation.cancel();
            }
            outcome
        };
        // Both futures are scoped to the round. A panic cannot detach a child task.
        let (downloaded, projected) = tokio::join!(download, projection);
        projected.map_err(|_| anyhow::anyhow!("update progress projection panicked"))??;
        let installer = match downloaded.map_err(|_| anyhow::anyhow!("update download panicked"))? {
            Ok(installer) => installer,
            Err(error) => {
                anyhow::ensure!(
                    matches!(
                        self.read().await.activity,
                        StudioUpdateActivity::InstallFailed(_)
                    ),
                    "download failed without terminal state: {error}"
                );
                return Ok(());
            }
        };
        let mut prepared = self.prepared.lock().await;
        if cancellation.is_cancelled()
            || prepared
                .selection()
                .is_some_and(|selected| selected != update.version)
        {
            drop(prepared);
            self.publish_owner_failure(&anyhow::anyhow!(pl_studio_update::StudioUpdateError::new(
                StudioUpdateErrorCode::Cancelled,
                "update preparation was cancelled"
            )))
            .await;
            return Ok(());
        }
        let current = self.read().await;
        let next = current.decide(StudioUpdateCommand::MarkReady {
            expected_revision: current.revision(),
            ready_at: unix_seconds(),
        })?;
        let ready = next
            .ready_update
            .clone()
            .context("verified update has no ready metadata")?;
        // Publish only after the owner holds the lease. Keep the prior lease on any failure above.
        prepared.installer = Some((ready, installer));
        *self.state.write().await = next.clone();
        drop(prepared);
        (self.events)(next);
        Ok(())
    }

    pub(crate) async fn launch_ready_on_exit(&self) -> Result<Option<String>> {
        let active = self.active.lock().await;
        anyhow::ensure!(active.is_none(), "update round is still running at exit");
        let mut prepared = self.prepared.lock().await;
        if let Some(version) = &prepared.launched_version {
            return Ok(Some(version.clone()));
        }
        if prepared.selection().is_none() {
            return Ok(None);
        }
        let Some((ready, installer)) = prepared.installer.as_mut() else {
            return Ok(None);
        };
        let version = ready.update.version.clone();
        installer.launch().await?;
        prepared.launched_version = Some(version.clone());
        drop(prepared);
        let current = self.read().await;
        if let Err(error) = self
            .apply(StudioUpdateCommand::MarkInstallerLaunched {
                expected_revision: current.revision(),
                launched_at: unix_seconds(),
            })
            .await
        {
            tracing::error!(%error, "installer launched but update projection failed");
        }
        Ok(Some(version))
    }

    async fn apply(&self, command: StudioUpdateCommand) -> Result<StudioUpdateStateSnapshot> {
        let mut current = self.state.write().await;
        let next = current.decide(command)?;
        *current = next.clone();
        drop(current);
        (self.events)(next.clone());
        Ok(next)
    }

    async fn publish_owner_failure(&self, error: &anyhow::Error) {
        let current = self.read().await;
        let failure = error
            .downcast_ref::<pl_studio_update::StudioUpdateError>()
            .map(state_error)
            .unwrap_or_else(|| StateError {
                code: "io".into(),
                message: format!("update round failed: {error:#}"),
                retryable: true,
            });
        let command = if current.activity.update().is_some() {
            StudioUpdateCommand::FailInstall {
                expected_revision: current.revision(),
                failed_at: unix_seconds(),
                error: failure,
            }
        } else {
            StudioUpdateCommand::FailCheck {
                expected_revision: current.revision(),
                failed_at: unix_seconds(),
                error: failure,
            }
        };
        if let Err(error) = self.apply(command).await {
            tracing::error!(%error, "updater rejected round failure state");
        }
    }
}

fn busy() -> anyhow::Error {
    pl_studio_update::StudioUpdateError::new(
        StudioUpdateErrorCode::InstallInProgress,
        "another update command is already running",
    )
    .into()
}

fn state_error(error: &pl_studio_update::StudioUpdateError) -> StateError {
    StateError {
        code: error.code().as_str().to_string(),
        message: error.to_string(),
        retryable: matches!(
            error.code(),
            StudioUpdateErrorCode::Network
                | StudioUpdateErrorCode::Io
                | StudioUpdateErrorCode::Cancelled
        ),
    }
}

fn rejected_selection(message: &str) -> StudioUpdatePreparationResult {
    StudioUpdatePreparationResult::Failed {
        error: StateError {
            code: "conflict".into(),
            message: message.into(),
            retryable: true,
        },
    }
}

#[cfg(test)]
mod tests {
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
            platform: pl_studio_update::StudioUpdatePlatform::WindowsX86_64,
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
    async fn updater_manual_preparation_joins_only_current_round_and_pins_its_version() -> Result<()>
    {
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
    async fn updater_selecting_retained_ready_cancels_new_candidate_and_preserves_target()
    -> Result<()> {
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

    #[tokio::test]
    async fn updater_imports_installation_failure_before_bootstrap_and_keeps_it_through_first_check()
     {
        let (_temp, owner, _io) = fixture(
            vec![CheckStep::Value(Ok(StudioUpdateCheck::UpToDate))],
            vec![],
        )
        .await
        .unwrap();
        owner
            .record_installation_failure("PackageKit installation failed".into())
            .await
            .unwrap();
        let baseline = owner.read().await;
        assert_eq!(baseline.revision(), 0);
        assert_eq!(
            baseline.installation_error.as_ref().unwrap().message,
            "PackageKit installation failed"
        );
        owner
            .check_cancellable(&StudioUpdateCancellation::new())
            .await
            .unwrap();
        let checked = owner.read().await;
        assert!(matches!(
            checked.activity,
            StudioUpdateActivity::UpToDate(_)
        ));
        assert!(checked.revision() > baseline.revision());
        assert_eq!(checked.installation_error, baseline.installation_error);
        assert!(
            owner
                .record_installation_failure("late receipt".into())
                .await
                .is_err()
        );
    }
}

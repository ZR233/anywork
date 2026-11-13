//! Process-owned update scheduling, current operation, and verified installer lease.

mod automatic;
mod state;
#[cfg(test)]
mod tests;

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
    Verified(pl_studio_update::PreparedStudioUpdate),
    #[cfg(test)]
    Test {
        _lease: std::fs::File,
    },
}
impl InstallerLease {
    fn launch(
        &mut self,
        mode: pl_studio_update::StudioUpdateLaunch,
    ) -> Result<(), pl_studio_update::StudioUpdateError> {
        match self {
            Self::Verified(installer) => installer.launch(mode),
            #[cfg(test)]
            Self::Test { .. } => Err(pl_studio_update::StudioUpdateError::new(
                StudioUpdateErrorCode::UnsupportedPlatform,
                "test installer leases cannot launch processes",
            )),
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
    fn selection(&mut self) -> Option<&str> {
        if self
            .selection_cancellation
            .as_ref()
            .is_some_and(StudioUpdateCancellation::is_cancelled)
        {
            self.selected_version = None;
            self.selection_cancellation = None;
        }
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
            state: Arc::new(RwLock::new(StudioUpdateStateSnapshot::idle(unix_seconds()))),
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
            return Ok(StudioUpdatePreparationResult::Ready {
                version: version.to_string(),
            });
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
            .map(InstallerLease::Verified)
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

    pub(crate) async fn launch_ready_on_exit(
        &self,
        mode: pl_studio_update::StudioUpdateLaunch,
    ) -> Result<Option<String>> {
        let active = self.active.lock().await;
        anyhow::ensure!(active.is_none(), "update round is still running at exit");
        let mut prepared = self.prepared.lock().await;
        if let Some(version) = &prepared.launched_version {
            return Ok(Some(version.clone()));
        }
        let Some((ready, installer)) = prepared.installer.as_mut() else {
            return Ok(None);
        };
        let version = ready.update.version.clone();
        installer.launch(mode)?;
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

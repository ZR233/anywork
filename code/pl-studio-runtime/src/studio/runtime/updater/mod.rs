//! Canonical, process-owned Studio updater lifecycle. Download files own resume progress.

mod state;

pub use state::*;

use std::sync::Arc;

use anyhow::{Context, Result};
use pl_protocol::StateError;
use tokio::sync::{Mutex, MutexGuard, RwLock};

use crate::studio::ids::unix_seconds;
use crate::updater::STUDIO_VERSION;
use crate::{
    StudioUpdate, StudioUpdateCheck, StudioUpdateErrorCode, StudioUpdateEvent, StudioUpdater,
};

enum PreparedUpdate {
    None,
    Ready(crate::PreparedStudioUpdate),
    Launched,
}

#[derive(Clone)]
pub(crate) struct StudioUpdateRuntime {
    updater: StudioUpdater,
    command_lock: Arc<Mutex<()>>,
    state: Arc<RwLock<StudioUpdateStateSnapshot>>,
    events: crate::ProductEventBus,
    prepared: Arc<Mutex<PreparedUpdate>>,
}

impl StudioUpdateRuntime {
    pub(crate) fn new(events: crate::ProductEventBus) -> Result<Self> {
        Ok(Self {
            updater: StudioUpdater::new_default()?,
            command_lock: Arc::new(Mutex::new(())),
            state: Arc::new(RwLock::new(StudioUpdateStateSnapshot::idle(unix_seconds()))),
            events,
            prepared: Arc::new(Mutex::new(PreparedUpdate::None)),
        })
    }

    pub(crate) async fn read(&self) -> StudioUpdateStateSnapshot {
        self.state.read().await.clone()
    }

    pub(crate) async fn check_cancellable(
        &self,
        cancellation: &crate::StudioUpdateCancellation,
    ) -> Result<StudioUpdateStateSnapshot> {
        let _command = self.command_lock.try_lock().map_err(|_| {
            crate::StudioUpdateError::new(
                StudioUpdateErrorCode::InstallInProgress,
                "another update command is already running",
            )
        })?;
        let previous = self.read().await;
        if matches!(previous, StudioUpdateStateSnapshot::Ready(_)) {
            return Ok(previous);
        }
        let running = self
            .apply(StudioUpdateCommand::BeginCheck {
                expected_revision: previous.revision(),
                operation_id: format!("studio-update-check-{}", previous.revision() + 1),
                started_at: unix_seconds(),
            })
            .await?;
        let result = tokio::select! {
            _ = cancellation.cancelled() => Err(crate::StudioUpdateError::new(
                StudioUpdateErrorCode::Cancelled, "Studio background update check was cancelled",
            )),
            result = self.updater.check(STUDIO_VERSION.trim()) => result,
        };
        let checked_at = unix_seconds();
        let command = match result {
            Ok(StudioUpdateCheck::UpToDate) => StudioUpdateCommand::FinishUpToDate {
                expected_revision: running.revision(),
                checked_at,
            },
            Ok(StudioUpdateCheck::Available(update)) => StudioUpdateCommand::FinishAvailable {
                expected_revision: running.revision(),
                checked_at,
                update,
            },
            Err(error) => {
                tracing::warn!(code = error.code().as_str(), error = %error, "Studio update check failed");
                let command = StudioUpdateCommand::FailCheck {
                    expected_revision: running.revision(),
                    failed_at: checked_at,
                    error: state_error(&error),
                };
                return self.apply(command).await;
            }
        };
        self.apply(command).await
    }

    pub(crate) async fn verified_update(
        &self,
        expected_revision: u64,
        version: &str,
    ) -> Result<StudioUpdate> {
        let state = self.read().await;
        anyhow::ensure!(
            state.revision() >= expected_revision,
            "update revision conflict: expected {expected_revision}, actual {}",
            state.revision()
        );
        let update = match &state {
            StudioUpdateStateSnapshot::Available(value) => value.update(),
            StudioUpdateStateSnapshot::Downloading(value) => value.update(),
            StudioUpdateStateSnapshot::Verifying(value) => value.update(),
            StudioUpdateStateSnapshot::Ready(value) => value.update(),
            StudioUpdateStateSnapshot::InstallFailed(value) => value.update(),
            _ => anyhow::bail!("cached update is not available for installation"),
        };
        (update.version == version)
            .then(|| update.clone())
            .context("requested update is not the cached verified update")
    }

    pub(crate) async fn apply_install_event(
        &self,
        update: &StudioUpdate,
        event: &StudioUpdateEvent,
    ) -> Result<StudioUpdateStateSnapshot> {
        let current = self.read().await;
        let now = unix_seconds();
        let command = match event {
            StudioUpdateEvent::Started { total } => StudioUpdateCommand::BeginDownload {
                expected_revision: current.revision(),
                updated_at: now,
                update: update.clone(),
                total: *total,
            },
            StudioUpdateEvent::Progress { downloaded, total } => {
                StudioUpdateCommand::ReportDownload {
                    expected_revision: current.revision(),
                    updated_at: now,
                    downloaded: *downloaded,
                    total: *total,
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
                    code: code.clone(),
                    message: message.clone(),
                    retryable: code == StudioUpdateErrorCode::Network.as_str()
                        || code == StudioUpdateErrorCode::Io.as_str()
                        || code == StudioUpdateErrorCode::Cancelled.as_str(),
                },
            },
        };
        self.apply(command).await
    }

    pub(crate) async fn lock_install(
        &self,
        update: &StudioUpdate,
    ) -> Result<MutexGuard<'_, ()>, crate::StudioUpdateError> {
        let command = self.command_lock.try_lock().map_err(|_| {
            crate::StudioUpdateError::new(
                StudioUpdateErrorCode::InstallInProgress,
                "another update command is already running",
            )
        })?;
        let state = self.read().await;
        if !matches!(
            state,
            StudioUpdateStateSnapshot::Available(_)
                | StudioUpdateStateSnapshot::Ready(_)
                | StudioUpdateStateSnapshot::InstallFailed(_)
        ) || state.update() != Some(update)
        {
            return Err(crate::StudioUpdateError::new(
                StudioUpdateErrorCode::InvalidManifest,
                "selected update is no longer available for installation",
            ));
        }
        Ok(command)
    }

    /// 保留下载和进度投影的真实所有者，只有校验与投影完成才发布 Ready。
    pub(crate) async fn prepare(
        &self,
        update: StudioUpdate,
        cancellation: crate::StudioUpdateCancellation,
        progress: Option<tokio::sync::mpsc::UnboundedSender<StudioUpdateStateSnapshot>>,
    ) -> Result<()> {
        let _command = self.lock_install(&update).await?;
        let current = self.read().await;
        if matches!(current, StudioUpdateStateSnapshot::Ready(_)) {
            if let Some(progress) = progress {
                let _ = progress.send(current);
            }
            return Ok(());
        }
        *self.prepared.lock().await = PreparedUpdate::None;
        let (events, mut receiver) = tokio::sync::mpsc::unbounded_channel();
        let owner = self.clone();
        let target = update.clone();
        let projection_cancellation = cancellation.clone();
        let projection_progress = progress.clone();
        let projection = tokio::spawn(async move {
            while let Some(event) = receiver.recv().await {
                let snapshot = match owner.apply_install_event(&target, &event).await {
                    Ok(snapshot) => snapshot,
                    Err(error) => {
                        projection_cancellation.cancel();
                        return Err(error);
                    }
                };
                if let Some(progress) = &projection_progress {
                    let _ = progress.send(snapshot);
                }
            }
            Ok::<_, anyhow::Error>(())
        });
        let result = self.updater.download(update, events, cancellation).await;
        // 即使下载失败也完整观察投影，不能让状态事件越过退出屏障。
        let projected = projection
            .await
            .context("updater download projection task failed")
            .and_then(|result| result);
        if let Err(error) = projected {
            self.publish_owner_failure(&error).await;
            return Err(error);
        }
        let prepared = match result {
            Ok(prepared) => prepared,
            Err(error) => {
                // 下载业务失败已由完成的投影发布；所有者失败仍必须向调用方传播。
                anyhow::ensure!(
                    matches!(
                        self.read().await,
                        StudioUpdateStateSnapshot::InstallFailed(_)
                    ),
                    "update download failed without a terminal state: {error}"
                );
                return Ok(());
            }
        };
        let current = self.read().await;
        // Publish Ready only after this owner holds the verified file lease.
        *self.prepared.lock().await = PreparedUpdate::Ready(prepared);
        let ready = self
            .apply(StudioUpdateCommand::MarkReady {
                expected_revision: current.revision(),
                ready_at: unix_seconds(),
            })
            .await?;
        if let Some(progress) = progress {
            let _ = progress.send(ready);
        }
        Ok(())
    }

    pub(crate) async fn launch_ready_on_exit(
        &self,
        mode: crate::StudioUpdateLaunch,
    ) -> Result<Option<String>> {
        let _command = self
            .command_lock
            .try_lock()
            .context("update command is still running at exit")?;
        let state = self.read().await;
        let version = match &state {
            StudioUpdateStateSnapshot::Ready(value) => value.update().version.clone(),
            StudioUpdateStateSnapshot::InstallerLaunched(value) => {
                return Ok(Some(value.update().version.clone()));
            }
            _ => return Ok(None),
        };
        let mut prepared = self.prepared.lock().await;
        match &mut *prepared {
            PreparedUpdate::Ready(installer) => {
                installer.launch(mode)?;
                *prepared = PreparedUpdate::Launched;
            }
            PreparedUpdate::Launched => {}
            PreparedUpdate::None => anyhow::bail!("ready update has no verified installer lease"),
        }
        drop(prepared);
        // The OS handoff wins even if its display projection fails afterwards.
        if let Err(error) = self
            .apply(StudioUpdateCommand::MarkInstallerLaunched {
                expected_revision: state.revision(),
                launched_at: unix_seconds(),
            })
            .await
        {
            tracing::error!(%error, "installer launched but updater projection failed");
        }
        Ok(Some(version))
    }

    async fn apply(&self, command: StudioUpdateCommand) -> Result<StudioUpdateStateSnapshot> {
        let mut current = self.state.write().await;
        let decision = current.decide(command)?;
        let next = decision.next_state;
        if !decision.changed {
            return Ok(next);
        }
        *current = next.clone();
        drop(current);
        self.events.emit_updater_state(next.clone());
        Ok(next)
    }

    /// 投影所有者失败必须发布诊断，不能把缺少文件租约的安装包发布为 Ready。
    async fn publish_owner_failure(&self, error: &anyhow::Error) {
        let mut current = self.state.write().await;
        let failure = StateError {
            code: StudioUpdateErrorCode::Io.as_str().to_string(),
            message: format!("update state owner failed: {error:#}"),
            retryable: true,
        };
        let command = if current.update().is_some() {
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
        let next = match current.decide(command) {
            Ok(decision) => decision.next_state,
            Err(transition) => {
                tracing::error!(error = %transition, "updater rejected its owner failure state");
                return;
            }
        };
        *current = next.clone();
        drop(current);
        self.events.emit_updater_state(next);
    }
}

fn state_error(error: &crate::StudioUpdateError) -> StateError {
    StateError {
        code: error.code().as_str().to_string(),
        message: error.to_string(),
        retryable: matches!(
            error.code(),
            StudioUpdateErrorCode::Network | StudioUpdateErrorCode::Io
        ),
    }
}

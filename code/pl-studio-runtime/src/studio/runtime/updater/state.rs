//! 更新状态目录页：声明各状态载荷与命令、快照、迁移子模块，并导出稳定入口。

use serde::{Deserialize, Serialize};

use pl_studio_update::StudioUpdate;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AvailableUpdateState {
    pub(super) revision: u64,
    pub(super) checked_at: i64,
    pub(super) update: StudioUpdate,
}

impl AvailableUpdateState {
    pub const fn checked_at(&self) -> i64 {
        self.checked_at
    }

    pub const fn update(&self) -> &StudioUpdate {
        &self.update
    }
}

use crate::StateError;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CheckFailedUpdateState {
    pub(super) revision: u64,
    pub(super) failed_at: i64,
    pub(super) error: StateError,
}

impl CheckFailedUpdateState {
    pub const fn failed_at(&self) -> i64 {
        self.failed_at
    }

    pub const fn error(&self) -> &StateError {
        &self.error
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CheckingUpdateState {
    pub(super) revision: u64,
    pub(super) operation_id: String,
    pub(super) started_at: i64,
}

impl CheckingUpdateState {
    pub fn operation_id(&self) -> &str {
        &self.operation_id
    }

    pub const fn started_at(&self) -> i64 {
        self.started_at
    }
}

// 更新状态机接收的命令载荷，统一携带乐观锁 revision 与业务数据。

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StudioUpdateCommand {
    BeginCheck {
        expected_revision: u64,
        operation_id: String,
        started_at: i64,
    },
    FinishUpToDate {
        expected_revision: u64,
        checked_at: i64,
    },
    FinishAvailable {
        expected_revision: u64,
        checked_at: i64,
        update: StudioUpdate,
    },
    FailCheck {
        expected_revision: u64,
        failed_at: i64,
        error: StateError,
    },
    BeginDownload {
        expected_revision: u64,
        updated_at: i64,
        update: StudioUpdate,
        total: u64,
    },
    ReportDownload {
        expected_revision: u64,
        updated_at: i64,
        downloaded: u64,
        total: u64,
    },
    BeginVerify {
        expected_revision: u64,
        updated_at: i64,
    },
    MarkInstallerLaunched {
        expected_revision: u64,
        launched_at: i64,
    },
    MarkReady {
        expected_revision: u64,
        ready_at: i64,
    },
    FailInstall {
        expected_revision: u64,
        failed_at: i64,
        error: StateError,
    },
}

impl StudioUpdateCommand {
    pub(super) const fn expected_revision(&self) -> u64 {
        match self {
            Self::BeginCheck {
                expected_revision, ..
            }
            | Self::FinishUpToDate {
                expected_revision, ..
            }
            | Self::FinishAvailable {
                expected_revision, ..
            }
            | Self::FailCheck {
                expected_revision, ..
            }
            | Self::BeginDownload {
                expected_revision, ..
            }
            | Self::ReportDownload {
                expected_revision, ..
            }
            | Self::BeginVerify {
                expected_revision, ..
            }
            | Self::MarkInstallerLaunched {
                expected_revision, ..
            }
            | Self::MarkReady {
                expected_revision, ..
            }
            | Self::FailInstall {
                expected_revision, ..
            } => *expected_revision,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DisabledUpdateState {
    pub(super) revision: u64,
    pub(super) updated_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DownloadingUpdateState {
    pub(super) revision: u64,
    pub(super) updated_at: i64,
    pub(super) update: StudioUpdate,
    pub(super) downloaded: u64,
    pub(super) total: u64,
}

impl DownloadingUpdateState {
    pub const fn update(&self) -> &StudioUpdate {
        &self.update
    }

    pub const fn downloaded(&self) -> u64 {
        self.downloaded
    }

    pub const fn total(&self) -> u64 {
        self.total
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct IdleUpdateState {
    pub(super) revision: u64,
    pub(super) updated_at: i64,
}

impl IdleUpdateState {
    pub(super) const fn new(updated_at: i64) -> Self {
        Self {
            revision: 0,
            updated_at,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct InstallFailedUpdateState {
    pub(super) revision: u64,
    pub(super) failed_at: i64,
    pub(super) update: StudioUpdate,
    pub(super) error: StateError,
}

impl InstallFailedUpdateState {
    pub const fn failed_at(&self) -> i64 {
        self.failed_at
    }

    pub const fn update(&self) -> &StudioUpdate {
        &self.update
    }

    pub const fn error(&self) -> &StateError {
        &self.error
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct InstallerLaunchedUpdateState {
    pub(super) revision: u64,
    pub(super) launched_at: i64,
    pub(super) update: StudioUpdate,
}

impl InstallerLaunchedUpdateState {
    pub const fn launched_at(&self) -> i64 {
        self.launched_at
    }

    pub const fn update(&self) -> &StudioUpdate {
        &self.update
    }
}

/// 已验证并持有文件租约，等待退出或用户主动重启安装。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReadyUpdateState {
    pub(super) revision: u64,
    pub(super) ready_at: i64,
    pub(super) update: StudioUpdate,
}

impl ReadyUpdateState {
    pub const fn ready_at(&self) -> i64 {
        self.ready_at
    }

    pub const fn update(&self) -> &StudioUpdate {
        &self.update
    }
}

// 更新状态对外快照：状态种类枚举、tagged 载荷表示与只读访问器。

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum StudioUpdateStateKind {
    Disabled,
    Idle,
    Checking,
    UpToDate,
    Available,
    Downloading,
    Verifying,
    Ready,
    InstallerLaunched,
    CheckFailed,
    InstallFailed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum StudioUpdateActivity {
    Disabled(DisabledUpdateState),
    Idle(IdleUpdateState),
    Checking(CheckingUpdateState),
    UpToDate(UpToDateUpdateState),
    Available(AvailableUpdateState),
    Downloading(DownloadingUpdateState),
    Verifying(VerifyingUpdateState),
    Ready(ReadyUpdateState),
    InstallerLaunched(InstallerLaunchedUpdateState),
    CheckFailed(CheckFailedUpdateState),
    InstallFailed(InstallFailedUpdateState),
}

impl StudioUpdateActivity {
    pub fn idle(updated_at: i64) -> Self {
        Self::Idle(IdleUpdateState::new(updated_at))
    }

    pub const fn kind(&self) -> StudioUpdateStateKind {
        match self {
            Self::Disabled(_) => StudioUpdateStateKind::Disabled,
            Self::Idle(_) => StudioUpdateStateKind::Idle,
            Self::Checking(_) => StudioUpdateStateKind::Checking,
            Self::UpToDate(_) => StudioUpdateStateKind::UpToDate,
            Self::Available(_) => StudioUpdateStateKind::Available,
            Self::Downloading(_) => StudioUpdateStateKind::Downloading,
            Self::Verifying(_) => StudioUpdateStateKind::Verifying,
            Self::Ready(_) => StudioUpdateStateKind::Ready,
            Self::InstallerLaunched(_) => StudioUpdateStateKind::InstallerLaunched,
            Self::CheckFailed(_) => StudioUpdateStateKind::CheckFailed,
            Self::InstallFailed(_) => StudioUpdateStateKind::InstallFailed,
        }
    }

    pub const fn revision(&self) -> u64 {
        match self {
            Self::Disabled(value) => value.revision,
            Self::Idle(value) => value.revision,
            Self::Checking(value) => value.revision,
            Self::UpToDate(value) => value.revision,
            Self::Available(value) => value.revision,
            Self::Downloading(value) => value.revision,
            Self::Verifying(value) => value.revision,
            Self::Ready(value) => value.revision,
            Self::InstallerLaunched(value) => value.revision,
            Self::CheckFailed(value) => value.revision,
            Self::InstallFailed(value) => value.revision,
        }
    }

    pub const fn updated_at(&self) -> i64 {
        match self {
            Self::Disabled(value) => value.updated_at,
            Self::Idle(value) => value.updated_at,
            Self::Checking(value) => value.started_at,
            Self::UpToDate(value) => value.checked_at,
            Self::Available(value) => value.checked_at,
            Self::Downloading(value) => value.updated_at,
            Self::Verifying(value) => value.updated_at,
            Self::Ready(value) => value.ready_at,
            Self::InstallerLaunched(value) => value.launched_at,
            Self::CheckFailed(value) => value.failed_at,
            Self::InstallFailed(value) => value.failed_at,
        }
    }

    pub fn update(&self) -> Option<&StudioUpdate> {
        match self {
            Self::Available(value) => Some(&value.update),
            Self::Downloading(value) => Some(&value.update),
            Self::Verifying(value) => Some(&value.update),
            Self::Ready(value) => Some(&value.update),
            Self::InstallerLaunched(value) => Some(&value.update),
            Self::InstallFailed(value) => Some(&value.update),
            Self::Disabled(_)
            | Self::Idle(_)
            | Self::Checking(_)
            | Self::UpToDate(_)
            | Self::CheckFailed(_) => None,
        }
    }
}

/// Current activity and the independently retained, verified installer share one revision.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StudioUpdateStateSnapshot {
    pub activity: StudioUpdateActivity,
    pub ready_update: Option<StudioReadyUpdate>,
    /// Previous install outcome stays visible while this process checks again.
    pub installation_error: Option<crate::StateError>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StudioReadyUpdate {
    pub update: StudioUpdate,
    pub ready_at: i64,
}

impl StudioUpdateStateSnapshot {
    pub fn disabled(updated_at: i64) -> Self {
        Self {
            activity: StudioUpdateActivity::Disabled(DisabledUpdateState {
                revision: 0,
                updated_at,
            }),
            ready_update: None,
            installation_error: None,
        }
    }

    pub fn idle(updated_at: i64) -> Self {
        Self {
            activity: StudioUpdateActivity::idle(updated_at),
            ready_update: None,
            installation_error: None,
        }
    }

    pub const fn revision(&self) -> u64 {
        self.activity.revision()
    }
    pub const fn updated_at(&self) -> i64 {
        self.activity.updated_at()
    }
    pub fn update(&self) -> Option<&StudioUpdate> {
        self.ready_update
            .as_ref()
            .map(|ready| &ready.update)
            .or_else(|| self.activity.update())
    }
}

// 更新状态机的唯一迁移入口 decide：校验命令 revision 与状态合法性，产出决策或迁移错误。

use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum StudioUpdateTransitionError {
    #[error("updater revision is stale: expected {expected}, actual {actual}, command {command:?}")]
    StaleRevision {
        expected: u64,
        actual: u64,
        command: Box<StudioUpdateCommand>,
    },
    #[error("updater in {current:?} rejects command {command:?}")]
    IllegalTransition {
        current: StudioUpdateStateKind,
        command: Box<StudioUpdateCommand>,
    },
    #[error("updater command {command:?} does not match available update {current_version}")]
    CorrelationMismatch {
        current_version: String,
        command: Box<StudioUpdateCommand>,
    },
    #[error("updater in {current:?} rejects invalid payload for command {command:?}: {detail}")]
    InvalidPayload {
        current: StudioUpdateStateKind,
        command: Box<StudioUpdateCommand>,
        detail: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct StudioUpdateTransitionDecision {
    next_state: StudioUpdateActivity,
}

impl StudioUpdateActivity {
    fn decide(
        &self,
        command: StudioUpdateCommand,
    ) -> Result<StudioUpdateTransitionDecision, StudioUpdateTransitionError> {
        if command.expected_revision() != self.revision() {
            return Err(StudioUpdateTransitionError::StaleRevision {
                expected: command.expected_revision(),
                actual: self.revision(),
                command: Box::new(command),
            });
        }
        let revision = self.revision().saturating_add(1);
        let next = match (self, &command) {
            (
                Self::Idle(_)
                | Self::UpToDate(_)
                | Self::Available(_)
                | Self::CheckFailed(_)
                | Self::InstallFailed(_)
                | Self::Ready(_),
                StudioUpdateCommand::BeginCheck {
                    operation_id,
                    started_at,
                    ..
                },
            ) => Self::Checking(CheckingUpdateState {
                revision,
                operation_id: operation_id.clone(),
                started_at: *started_at,
            }),
            (Self::Checking(_), StudioUpdateCommand::FinishUpToDate { checked_at, .. }) => {
                Self::UpToDate(UpToDateUpdateState {
                    revision,
                    checked_at: *checked_at,
                })
            }
            (
                Self::Checking(_),
                StudioUpdateCommand::FinishAvailable {
                    checked_at, update, ..
                },
            ) => Self::Available(AvailableUpdateState {
                revision,
                checked_at: *checked_at,
                update: update.clone(),
            }),
            (
                Self::Idle(_) | Self::UpToDate(_) | Self::Checking(_) | Self::CheckFailed(_),
                StudioUpdateCommand::FailCheck {
                    failed_at, error, ..
                },
            ) => Self::CheckFailed(CheckFailedUpdateState {
                revision,
                failed_at: *failed_at,
                error: error.clone(),
            }),
            (
                Self::Available(_) | Self::Ready(_) | Self::InstallFailed(_),
                StudioUpdateCommand::BeginDownload { update, .. },
            ) if self.update() != Some(update) => {
                return Err(StudioUpdateTransitionError::CorrelationMismatch {
                    current_version: self
                        .update()
                        .expect("installable states have an update")
                        .version
                        .clone(),
                    command: Box::new(command),
                });
            }
            (
                Self::Available(_) | Self::Ready(_) | Self::InstallFailed(_),
                StudioUpdateCommand::BeginDownload { total: 0, .. },
            ) => {
                return Err(StudioUpdateTransitionError::InvalidPayload {
                    current: self.kind(),
                    command: Box::new(command),
                    detail: "download total must be positive".to_string(),
                });
            }
            (
                Self::Available(_) | Self::Ready(_) | Self::InstallFailed(_),
                StudioUpdateCommand::BeginDownload {
                    updated_at,
                    update,
                    total,
                    ..
                },
            ) => Self::Downloading(DownloadingUpdateState {
                revision,
                updated_at: *updated_at,
                update: update.clone(),
                downloaded: 0,
                total: *total,
            }),
            (
                Self::Downloading(current),
                StudioUpdateCommand::ReportDownload {
                    updated_at,
                    downloaded,
                    total,
                    ..
                },
            ) if *total != current.total || *downloaded > *total => {
                return Err(StudioUpdateTransitionError::InvalidPayload {
                    current: self.kind(),
                    command: Box::new(command.clone()),
                    detail: format!(
                        "download progress {downloaded}/{total} does not match active total {}",
                        current.total
                    ),
                });
            }
            (
                Self::Downloading(current),
                StudioUpdateCommand::ReportDownload {
                    updated_at,
                    downloaded,
                    total,
                    ..
                },
            ) => Self::Downloading(DownloadingUpdateState {
                revision,
                updated_at: *updated_at,
                update: current.update.clone(),
                downloaded: *downloaded,
                total: *total,
            }),
            (Self::Downloading(current), StudioUpdateCommand::BeginVerify { updated_at, .. }) => {
                Self::Verifying(VerifyingUpdateState {
                    revision,
                    updated_at: *updated_at,
                    update: current.update.clone(),
                    downloaded: current.downloaded,
                    total: current.total,
                })
            }
            (Self::Verifying(current), StudioUpdateCommand::MarkReady { ready_at, .. }) => {
                Self::Ready(ReadyUpdateState {
                    revision,
                    ready_at: *ready_at,
                    update: current.update.clone(),
                })
            }
            (
                Self::Ready(current),
                StudioUpdateCommand::MarkInstallerLaunched { launched_at, .. },
            ) => Self::InstallerLaunched(InstallerLaunchedUpdateState {
                revision,
                launched_at: *launched_at,
                update: current.update.clone(),
            }),
            (
                Self::Ready(_)
                | Self::Downloading(_)
                | Self::Available(_)
                | Self::Verifying(_)
                | Self::InstallFailed(_),
                StudioUpdateCommand::FailInstall {
                    failed_at, error, ..
                },
            ) => Self::InstallFailed(InstallFailedUpdateState {
                revision,
                failed_at: *failed_at,
                update: self
                    .update()
                    .expect("install states have an update")
                    .clone(),
                error: error.clone(),
            }),
            _ => {
                return Err(StudioUpdateTransitionError::IllegalTransition {
                    current: self.kind(),
                    command: Box::new(command),
                });
            }
        };
        Ok(StudioUpdateTransitionDecision { next_state: next })
    }
}

impl StudioUpdateStateSnapshot {
    pub fn decide(
        &self,
        command: StudioUpdateCommand,
    ) -> Result<Self, StudioUpdateTransitionError> {
        // A verified installer remains installable while another check/download is active.
        if let StudioUpdateCommand::MarkInstallerLaunched {
            expected_revision,
            launched_at,
        } = command
        {
            if expected_revision != self.revision() {
                return Err(StudioUpdateTransitionError::StaleRevision {
                    expected: expected_revision,
                    actual: self.revision(),
                    command: Box::new(command),
                });
            }
            if let Some(ready) = &self.ready_update {
                return Ok(Self {
                    activity: StudioUpdateActivity::InstallerLaunched(
                        InstallerLaunchedUpdateState {
                            revision: self.revision() + 1,
                            launched_at,
                            update: ready.update.clone(),
                        },
                    ),
                    ready_update: self.ready_update.clone(),
                    installation_error: None,
                });
            }
        }
        let next = self.activity.decide(command)?.next_state;
        let ready_update = match &next {
            StudioUpdateActivity::Ready(value) => Some(StudioReadyUpdate {
                update: value.update().clone(),
                ready_at: value.ready_at(),
            }),
            _ => self.ready_update.clone(),
        };
        let installation_error = if matches!(next, StudioUpdateActivity::InstallerLaunched(_)) {
            None
        } else {
            self.installation_error.clone()
        };
        Ok(Self {
            activity: next,
            ready_update,
            installation_error,
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UpToDateUpdateState {
    pub(super) revision: u64,
    pub(super) checked_at: i64,
}

impl UpToDateUpdateState {
    pub const fn checked_at(&self) -> i64 {
        self.checked_at
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct VerifyingUpdateState {
    pub(super) revision: u64,
    pub(super) updated_at: i64,
    pub(super) update: StudioUpdate,
    pub(super) downloaded: u64,
    pub(super) total: u64,
}

impl VerifyingUpdateState {
    pub const fn update(&self) -> &StudioUpdate {
        &self.update
    }

    pub const fn downloaded(&self) -> u64 {
        self.downloaded
    }

    pub const fn total(&self) -> u64 {
        self.total
    }
}

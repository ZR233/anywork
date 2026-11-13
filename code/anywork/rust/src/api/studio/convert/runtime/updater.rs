//! Canonical updater state projection.

use crate::api::studio::types::*;
use pl_studio_runtime::{
    StudioUpdateActivity, StudioUpdatePreparationResult, StudioUpdateStateSnapshot,
};
use pl_studio_update::StudioUpdate;

pub(crate) fn bridge_update_state(state: StudioUpdateStateSnapshot) -> BridgeUpdaterStateSnapshot {
    let revision = state.revision();
    let updated_at = state.updated_at();
    let activity = match state.activity {
        StudioUpdateActivity::Disabled(_) => {
            BridgeUpdaterActivity::Disabled(BridgeDisabledUpdaterState {
                revision,
                updated_at,
            })
        }
        StudioUpdateActivity::Idle(_) => BridgeUpdaterActivity::Idle(BridgeIdleUpdaterState {
            revision,
            updated_at,
        }),
        StudioUpdateActivity::Checking(value) => {
            BridgeUpdaterActivity::Checking(BridgeCheckingUpdaterState {
                revision,
                operation_id: value.operation_id().to_string(),
                started_at: value.started_at(),
            })
        }
        StudioUpdateActivity::UpToDate(value) => {
            BridgeUpdaterActivity::UpToDate(BridgeUpToDateUpdaterState {
                revision,
                checked_at: value.checked_at(),
            })
        }
        StudioUpdateActivity::Available(value) => {
            BridgeUpdaterActivity::Available(BridgeAvailableUpdaterState {
                revision,
                checked_at: value.checked_at(),
                update: bridge_update(value.update()),
            })
        }
        StudioUpdateActivity::Downloading(value) => {
            BridgeUpdaterActivity::Downloading(BridgeDownloadingUpdaterState {
                revision,
                updated_at,
                update: bridge_update(value.update()),
                downloaded: value.downloaded(),
                total: value.total(),
            })
        }
        StudioUpdateActivity::Verifying(value) => {
            BridgeUpdaterActivity::Verifying(BridgeVerifyingUpdaterState {
                revision,
                updated_at,
                update: bridge_update(value.update()),
                downloaded: value.downloaded(),
                total: value.total(),
            })
        }
        StudioUpdateActivity::Ready(value) => {
            BridgeUpdaterActivity::Ready(BridgeReadyUpdaterState {
                revision,
                ready_at: value.ready_at(),
                update: bridge_update(value.update()),
            })
        }
        StudioUpdateActivity::InstallerLaunched(value) => {
            BridgeUpdaterActivity::InstallerLaunched(BridgeInstallerLaunchedUpdaterState {
                revision,
                launched_at: value.launched_at(),
                update: bridge_update(value.update()),
            })
        }
        StudioUpdateActivity::CheckFailed(value) => {
            BridgeUpdaterActivity::CheckFailed(BridgeCheckFailedUpdaterState {
                revision,
                failed_at: value.failed_at(),
                error: value.error().into(),
            })
        }
        StudioUpdateActivity::InstallFailed(value) => {
            BridgeUpdaterActivity::InstallFailed(BridgeInstallFailedUpdaterState {
                revision,
                failed_at: value.failed_at(),
                update: bridge_update(value.update()),
                error: value.error().into(),
            })
        }
    };
    BridgeUpdaterStateSnapshot {
        activity,
        ready_update: state.ready_update.map(|ready| BridgeReadyUpdate {
            update: bridge_update(&ready.update),
            ready_at: ready.ready_at,
        }),
    }
}

fn bridge_update(update: &StudioUpdate) -> BridgeVerifiedUpdateSummary {
    BridgeVerifiedUpdateSummary {
        version: update.version.clone(),
        published_at: update.published_at,
        notes_url: update.notes_url.clone(),
    }
}

pub(crate) fn bridge_preparation_result(
    result: StudioUpdatePreparationResult,
) -> BridgeUpdatePreparationResult {
    match result {
        StudioUpdatePreparationResult::Ready { version } => {
            BridgeUpdatePreparationResult::Ready { version }
        }
        StudioUpdatePreparationResult::Cancelled => BridgeUpdatePreparationResult::Cancelled,
        StudioUpdatePreparationResult::Failed { error } => BridgeUpdatePreparationResult::Failed {
            error: (&error).into(),
        },
    }
}

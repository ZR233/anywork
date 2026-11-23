//! ACP 官方 server 自动准备的 Bridge 转换。
//!
//! 只做 wire ↔ FRB 镜像的字面映射；不解释状态、不改 revision、不产生任何副作用。

use crate::api::studio::convert::acp::bridge_acp_provider;
use crate::api::studio::types::{
    BridgeAcpInstallAvailability, BridgeAcpInstallEntry, BridgeAcpInstallFailure,
    BridgeAcpInstallFailureCode, BridgeAcpInstallProgress, BridgeAcpInstallRelease,
    BridgeAcpInstallSnapshot, BridgeAcpInstallStage, BridgeAcpInstallState,
    BridgeAcpInstallUpdateState, BridgeAcpInstalledServer, BridgeAcpProvider,
};

/// 平台可用性镜像；`target` 原样透传，不在客户端重新推断平台。
pub(crate) fn bridge_acp_install_availability(
    availability: pl_studio_runtime::AcpInstallAvailability,
) -> BridgeAcpInstallAvailability {
    match availability {
        pl_studio_runtime::AcpInstallAvailability::Available { target } => {
            BridgeAcpInstallAvailability::Available { target }
        }
        pl_studio_runtime::AcpInstallAvailability::UnsupportedPlatform => {
            BridgeAcpInstallAvailability::UnsupportedPlatform
        }
    }
}

pub(crate) fn bridge_acp_install_release(
    release: pl_studio_runtime::AcpInstallRelease,
) -> BridgeAcpInstallRelease {
    BridgeAcpInstallRelease {
        version: release.version,
        target: release.target,
        archive_url: release.archive_url,
        sha256: release.sha256,
    }
}

fn bridge_acp_install_progress(
    progress: pl_studio_runtime::AcpInstallProgress,
) -> BridgeAcpInstallProgress {
    BridgeAcpInstallProgress {
        completed_bytes: progress.completed_bytes,
        total_bytes: progress.total_bytes,
        bytes_per_second: progress.bytes_per_second,
    }
}

fn bridge_acp_install_stage(stage: pl_studio_runtime::AcpInstallStage) -> BridgeAcpInstallStage {
    match stage {
        pl_studio_runtime::AcpInstallStage::Resolve => BridgeAcpInstallStage::Resolve,
        pl_studio_runtime::AcpInstallStage::WaitForLock => BridgeAcpInstallStage::WaitForLock,
        pl_studio_runtime::AcpInstallStage::Download => BridgeAcpInstallStage::Download,
        pl_studio_runtime::AcpInstallStage::Verify => BridgeAcpInstallStage::Verify,
        pl_studio_runtime::AcpInstallStage::Extract => BridgeAcpInstallStage::Extract,
        pl_studio_runtime::AcpInstallStage::Publish => BridgeAcpInstallStage::Publish,
        pl_studio_runtime::AcpInstallStage::Close => BridgeAcpInstallStage::Close,
    }
}

fn bridge_acp_install_failure_code(
    code: pl_studio_runtime::AcpInstallFailureCode,
) -> BridgeAcpInstallFailureCode {
    use pl_studio_runtime::AcpInstallFailureCode as Wire;
    match code {
        Wire::UnsupportedPlatform => BridgeAcpInstallFailureCode::UnsupportedPlatform,
        Wire::SourceRejected => BridgeAcpInstallFailureCode::SourceRejected,
        Wire::Network => BridgeAcpInstallFailureCode::Network,
        Wire::Timeout => BridgeAcpInstallFailureCode::Timeout,
        Wire::TooLarge => BridgeAcpInstallFailureCode::TooLarge,
        Wire::ChecksumMismatch => BridgeAcpInstallFailureCode::ChecksumMismatch,
        Wire::InvalidArchive => BridgeAcpInstallFailureCode::InvalidArchive,
        Wire::MissingExecutable => BridgeAcpInstallFailureCode::MissingExecutable,
        Wire::CacheCorrupt => BridgeAcpInstallFailureCode::CacheCorrupt,
        Wire::Io => BridgeAcpInstallFailureCode::Io,
        Wire::Busy => BridgeAcpInstallFailureCode::Busy,
        Wire::StaleOperation => BridgeAcpInstallFailureCode::StaleOperation,
        Wire::Cancelled => BridgeAcpInstallFailureCode::Cancelled,
        Wire::ResourceClose => BridgeAcpInstallFailureCode::ResourceClose,
    }
}

fn bridge_acp_install_failure(
    failure: pl_studio_runtime::AcpInstallFailure,
) -> BridgeAcpInstallFailure {
    BridgeAcpInstallFailure {
        code: bridge_acp_install_failure_code(failure.code),
        stage: bridge_acp_install_stage(failure.stage),
        message: failure.message,
        retryable: failure.retryable,
    }
}

fn bridge_acp_installed_server(
    server: pl_studio_runtime::AcpInstalledServer,
) -> BridgeAcpInstalledServer {
    BridgeAcpInstalledServer {
        installation_id: server.installation_id,
        release: bridge_acp_install_release(server.release),
        program: server.program,
        ready_at: server.ready_at,
        reused: server.reused,
    }
}

pub(crate) fn bridge_acp_install_state(
    state: pl_studio_runtime::AcpInstallState,
) -> BridgeAcpInstallState {
    use pl_studio_runtime::AcpInstallState as Wire;
    match state {
        Wire::Idle => BridgeAcpInstallState::Idle,
        Wire::Resolving { operation_id } => BridgeAcpInstallState::Resolving { operation_id },
        Wire::Waiting {
            operation_id,
            release,
        } => BridgeAcpInstallState::Waiting {
            operation_id,
            release: bridge_acp_install_release(release),
        },
        Wire::Downloading {
            operation_id,
            release,
            progress,
            retry_count,
        } => BridgeAcpInstallState::Downloading {
            operation_id,
            release: bridge_acp_install_release(release),
            progress: bridge_acp_install_progress(progress),
            retry_count,
        },
        Wire::Verifying {
            operation_id,
            release,
            progress,
        } => BridgeAcpInstallState::Verifying {
            operation_id,
            release: bridge_acp_install_release(release),
            progress: bridge_acp_install_progress(progress),
        },
        Wire::Extracting {
            operation_id,
            release,
            progress,
        } => BridgeAcpInstallState::Extracting {
            operation_id,
            release: bridge_acp_install_release(release),
            progress: bridge_acp_install_progress(progress),
        },
        Wire::Publishing {
            operation_id,
            release,
        } => BridgeAcpInstallState::Publishing {
            operation_id,
            release: bridge_acp_install_release(release),
        },
        Wire::Closing {
            operation_id,
            failure,
        } => BridgeAcpInstallState::Closing {
            operation_id,
            failure: failure.map(bridge_acp_install_failure),
        },
        Wire::Ready {
            operation_id,
            server,
        } => BridgeAcpInstallState::Ready {
            operation_id,
            server: bridge_acp_installed_server(server),
        },
        Wire::Cancelling { operation_id } => BridgeAcpInstallState::Cancelling { operation_id },
        Wire::Cancelled { operation_id } => BridgeAcpInstallState::Cancelled { operation_id },
        Wire::Failed {
            operation_id,
            failure,
        } => BridgeAcpInstallState::Failed {
            operation_id,
            failure: bridge_acp_install_failure(failure),
        },
    }
}

pub(crate) fn bridge_acp_install_update_state(
    state: pl_studio_runtime::AcpInstallUpdateState,
) -> BridgeAcpInstallUpdateState {
    use pl_studio_runtime::AcpInstallUpdateState as Wire;
    match state {
        Wire::Idle => BridgeAcpInstallUpdateState::Idle,
        Wire::Checking => BridgeAcpInstallUpdateState::Checking,
        Wire::UpToDate {
            checked_at,
            latest_version,
        } => BridgeAcpInstallUpdateState::UpToDate {
            checked_at,
            latest_version,
        },
        Wire::UpdateAvailable { checked_at, latest } => {
            BridgeAcpInstallUpdateState::UpdateAvailable {
                checked_at,
                latest: bridge_acp_install_release(latest),
            }
        }
        Wire::IncompatibleMajor {
            checked_at,
            latest_version,
        } => BridgeAcpInstallUpdateState::IncompatibleMajor {
            checked_at,
            latest_version,
        },
        Wire::Failed {
            checked_at,
            failure,
        } => BridgeAcpInstallUpdateState::Failed {
            checked_at,
            failure: bridge_acp_install_failure(failure),
        },
    }
}

pub(crate) fn bridge_acp_install_snapshot(
    snapshot: pl_studio_runtime::AcpInstallSnapshot,
) -> BridgeAcpInstallSnapshot {
    BridgeAcpInstallSnapshot {
        revision: snapshot.revision,
        updated_at: snapshot.updated_at,
        installations: snapshot
            .installations
            .into_iter()
            .map(|entry| BridgeAcpInstallEntry {
                provider: bridge_acp_provider(entry.provider),
                state: bridge_acp_install_state(entry.state),
                installed: entry.installed.map(bridge_acp_installed_server),
                update: bridge_acp_install_update_state(entry.update),
            })
            .collect(),
    }
}

/// FRB provider 镜像 → wire provider；与 `bridge_acp_provider` 互为反向穷尽映射。
pub(crate) fn protocol_acp_install_provider(
    provider: BridgeAcpProvider,
) -> pl_studio_runtime::AcpProvider {
    match provider {
        BridgeAcpProvider::Antigravity => pl_studio_runtime::AcpProvider::Antigravity,
    }
}

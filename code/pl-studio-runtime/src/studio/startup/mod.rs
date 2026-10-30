//! Global startup failure and recovery boundary; individual session activation stays separate.

mod backup;
mod error;

pub(super) use backup::StartupBackup;
pub(crate) use backup::validate_credential_recovery;
pub use error::{StudioStartupError, StudioStartupErrorKind};
pub(crate) use error::{cleanup_error, data_error, input_error, migration_error};

/// Safe startup recovery metadata; original configuration and credentials never enter this DTO.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct StudioStartupRecovery {
    pub backup_path: String,
    pub reason: String,
    pub created_at: i64,
}
pub(crate) mod storage_layout;

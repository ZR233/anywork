use serde::{Deserialize, Serialize};

/// FRB wire projection of the transport-neutral Studio error code.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeErrorCode {
    NotInitialized,
    RuntimeStopped,
    InstanceBusy,
    InvalidArgument,
    NotFound,
    Busy,
    Conflict,
    StaleRevision,
    Superseded,
    PermissionDenied,
    Cancelled,
    CancellationTooLate,
    Overloaded,
    Unavailable,
    Protocol,
    Storage,
    Update,
    Internal,
}

/// FRB-only wire representation of [`pl_protocol::studio::StudioError`].
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, thiserror::Error)]
#[serde(rename_all = "camelCase")]
#[error("{message} (correlation id: {correlation_id})")]
pub struct BridgeError {
    pub code: BridgeErrorCode,
    pub message: String,
    pub retryable: bool,
    pub correlation_id: String,
    pub details: Option<BridgeErrorDetails>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum BridgeErrorDetails {
    Startup {
        step: String,
        kind: BridgeStartupFailureKind,
    },
    Revision {
        expected: u64,
        actual: u64,
    },
    SshAuthentication {
        password_offered: Option<bool>,
    },
    Reason {
        reason: String,
    },
    Identity {
        identity: String,
    },
    TimelineRevision {
        item_id: String,
        field: String,
        revision: u64,
    },
    Validation {
        issues: Vec<BridgeValidationIssue>,
    },
    Thread {
        thread_id: String,
    },
    ResourceLimit {
        resource: String,
        capacity: u64,
    },
    Bot {
        code: String,
        platform_code: Option<String>,
        guidance: Option<String>,
    },
    CatalogRevision {
        revision: u64,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeValidationIssue {
    pub code: String,
    pub path: String,
    pub message: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeStartupFailureKind {
    ModeDefinitions,
    Migration,
    PersistentData,
    Environment,
    Cancelled,
    Internal,
}

impl From<pl_protocol::studio::StudioErrorDetails> for BridgeErrorDetails {
    fn from(details: pl_protocol::studio::StudioErrorDetails) -> Self {
        use pl_protocol::studio::{StartupFailureKind, StudioErrorDetails};
        match details {
            StudioErrorDetails::Startup { step, kind } => Self::Startup {
                step,
                kind: match kind {
                    StartupFailureKind::ModeDefinitions => {
                        BridgeStartupFailureKind::ModeDefinitions
                    }
                    StartupFailureKind::Migration => BridgeStartupFailureKind::Migration,
                    StartupFailureKind::PersistentData => BridgeStartupFailureKind::PersistentData,
                    StartupFailureKind::Environment => BridgeStartupFailureKind::Environment,
                    StartupFailureKind::Cancelled => BridgeStartupFailureKind::Cancelled,
                    StartupFailureKind::Internal => BridgeStartupFailureKind::Internal,
                },
            },
            StudioErrorDetails::Revision { expected, actual } => {
                Self::Revision { expected, actual }
            }
            StudioErrorDetails::SshAuthentication { password_offered } => {
                Self::SshAuthentication { password_offered }
            }
            StudioErrorDetails::Reason { reason } => Self::Reason { reason },
            StudioErrorDetails::Identity { identity } => Self::Identity { identity },
            StudioErrorDetails::TimelineRevision {
                item_id,
                field,
                revision,
            } => Self::TimelineRevision {
                item_id,
                field,
                revision,
            },
            StudioErrorDetails::Validation { issues } => Self::Validation {
                issues: issues
                    .into_iter()
                    .map(|issue| BridgeValidationIssue {
                        code: issue.code,
                        path: issue.path,
                        message: issue.message,
                    })
                    .collect(),
            },
            StudioErrorDetails::Thread { thread_id } => Self::Thread { thread_id },
            StudioErrorDetails::ResourceLimit { resource, capacity } => {
                Self::ResourceLimit { resource, capacity }
            }
            StudioErrorDetails::Bot {
                code,
                platform_code,
                guidance,
            } => Self::Bot {
                code,
                platform_code,
                guidance,
            },
            StudioErrorDetails::CatalogRevision { revision } => Self::CatalogRevision { revision },
        }
    }
}

impl BridgeError {
    pub(crate) fn not_initialized() -> Self {
        pl_protocol::studio::StudioError::new(
            pl_protocol::studio::StudioErrorCode::NotInitialized,
            "Studio runtime is not initialized",
            true,
        )
        .into()
    }

    pub(crate) fn runtime_stopped() -> Self {
        pl_protocol::studio::StudioError::new(
            pl_protocol::studio::StudioErrorCode::RuntimeStopped,
            "Studio runtime has stopped; restart the application",
            false,
        )
        .into()
    }

    pub(crate) fn invalid_argument(message: impl Into<String>) -> Self {
        pl_protocol::studio::StudioError::invalid_argument(message).into()
    }
}

impl From<pl_protocol::studio::StudioError> for BridgeError {
    fn from(error: pl_protocol::studio::StudioError) -> Self {
        Self {
            code: error.code.into(),
            message: error.message,
            retryable: error.retryable,
            correlation_id: error.correlation_id,
            details: error.details.map(|details| (*details).into()),
        }
    }
}

impl From<pl_protocol::studio::StudioErrorCode> for BridgeErrorCode {
    fn from(code: pl_protocol::studio::StudioErrorCode) -> Self {
        use pl_protocol::studio::StudioErrorCode;

        match code {
            StudioErrorCode::NotInitialized => Self::NotInitialized,
            StudioErrorCode::RuntimeStopped => Self::RuntimeStopped,
            StudioErrorCode::InstanceBusy => Self::InstanceBusy,
            StudioErrorCode::InvalidArgument => Self::InvalidArgument,
            StudioErrorCode::NotFound => Self::NotFound,
            StudioErrorCode::Busy => Self::Busy,
            StudioErrorCode::Conflict => Self::Conflict,
            StudioErrorCode::StaleRevision => Self::StaleRevision,
            StudioErrorCode::Superseded => Self::Superseded,
            StudioErrorCode::PermissionDenied => Self::PermissionDenied,
            StudioErrorCode::Cancelled => Self::Cancelled,
            StudioErrorCode::CancellationTooLate => Self::CancellationTooLate,
            StudioErrorCode::Overloaded => Self::Overloaded,
            StudioErrorCode::Unavailable => Self::Unavailable,
            StudioErrorCode::Protocol => Self::Protocol,
            StudioErrorCode::Storage => Self::Storage,
            StudioErrorCode::Update => Self::Update,
            StudioErrorCode::Internal => Self::Internal,
        }
    }
}

impl From<anyhow::Error> for BridgeError {
    fn from(error: anyhow::Error) -> Self {
        pl_studio_runtime::studio_error_from_anyhow(error).into()
    }
}

impl From<serde_json::Error> for BridgeError {
    fn from(error: serde_json::Error) -> Self {
        Self::from(anyhow::Error::new(error))
    }
}

impl From<pl_protocol::PureError> for BridgeError {
    fn from(error: pl_protocol::PureError) -> Self {
        Self::from(anyhow::Error::new(error))
    }
}

impl From<pl_studio_runtime::StudioUpdateError> for BridgeError {
    fn from(error: pl_studio_runtime::StudioUpdateError) -> Self {
        Self::from(anyhow::Error::new(error))
    }
}

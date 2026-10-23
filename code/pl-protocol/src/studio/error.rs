//! Studio API 的稳定错误分类与脱敏错误体。

use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

static NEXT_CORRELATION_ID: AtomicU64 = AtomicU64::new(1);

/// Stable Studio API error categories shared by FRB and HTTP.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum StudioErrorCode {
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

impl StudioErrorCode {
    /// Stable camelCase label shared by logs, diagnostics and shutdown reports.
    pub const fn label(self) -> &'static str {
        match self {
            Self::NotInitialized => "notInitialized",
            Self::RuntimeStopped => "runtimeStopped",
            Self::InstanceBusy => "instanceBusy",
            Self::InvalidArgument => "invalidArgument",
            Self::NotFound => "notFound",
            Self::Busy => "busy",
            Self::Conflict => "conflict",
            Self::StaleRevision => "staleRevision",
            Self::Superseded => "superseded",
            Self::PermissionDenied => "permissionDenied",
            Self::Cancelled => "cancelled",
            Self::CancellationTooLate => "cancellationTooLate",
            Self::Overloaded => "overloaded",
            Self::Unavailable => "unavailable",
            Self::Protocol => "protocol",
            Self::Storage => "storage",
            Self::Update => "update",
            Self::Internal => "internal",
        }
    }
}

/// A redacted API error. Internal diagnostics are correlated through `correlation_id` only.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, thiserror::Error, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[error("{message} (correlation id: {correlation_id})")]
pub struct StudioError {
    pub code: StudioErrorCode,
    pub message: String,
    pub retryable: bool,
    pub correlation_id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub details: Option<StudioErrorDetails>,
}

/// Stable diagnostic fields. Arbitrary JSON is not part of the error contract.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum StudioErrorDetails {
    Startup { step: String, kind: StartupFailureKind },
    Revision { expected: u64, actual: u64 },
    SshAuthentication { password_offered: Option<bool> },
    Reason { reason: String },
    Identity { identity: String },
    TimelineRevision { item_id: String, field: String, revision: u64 },
    Validation { issues: Vec<crate::ThreadModeValidationIssue> },
    Thread { thread_id: String },
    ResourceLimit { resource: String, capacity: u64 },
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum StartupFailureKind {
    ModeDefinitions,
    Migration,
    PersistentData,
    Environment,
    Cancelled,
    Internal,
}

impl StudioError {
    pub fn new(code: StudioErrorCode, message: impl Into<String>, retryable: bool) -> Self {
        Self {
            code,
            message: message.into(),
            retryable,
            correlation_id: next_correlation_id(),
            details: None,
        }
    }

    pub fn with_details(mut self, details: StudioErrorDetails) -> Self {
        self.details = Some(details);
        self
    }

    pub fn invalid_argument(message: impl Into<String>) -> Self {
        Self::new(StudioErrorCode::InvalidArgument, message, false)
    }

    pub fn not_found(resource: &'static str) -> Self {
        Self::new(
            StudioErrorCode::NotFound,
            format!("The requested Studio {resource} was not found"),
            false,
        )
    }

    pub fn instance_busy() -> Self {
        Self::new(
            StudioErrorCode::InstanceBusy,
            "Another Studio runtime already owns this home",
            true,
        )
    }

    pub fn internal() -> Self {
        Self::new(
            StudioErrorCode::Internal,
            "Studio could not complete the operation",
            false,
        )
    }

    pub fn storage() -> Self {
        Self::new(
            StudioErrorCode::Storage,
            "Studio storage is unavailable",
            true,
        )
    }
}

fn next_correlation_id() -> String {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_secs());
    let sequence = NEXT_CORRELATION_ID.fetch_add(1, Ordering::Relaxed);
    format!("studio-{timestamp:x}-{sequence:x}")
}

pub type StudioResult<T> = Result<T, StudioError>;

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

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum BridgeControlFailureFacts {
    Unspecified,
    ChildThreadAction {
        thread_id: String,
        action: String,
        parent_thread_id: Option<String>,
    },
    ThreadAction {
        thread_id: String,
        action: String,
    },
    ExpectedExecution {
        thread_id: String,
        expected_execution_id: String,
    },
    Executing {
        thread_id: String,
        execution_id: String,
        phase: String,
    },
    ExpectedContinuation {
        thread_id: String,
        expected_continuation_id: String,
    },
    ContinuationAccepted {
        thread_id: String,
        operation_id: String,
        accepted: bool,
    },
    ContinuationOperation {
        thread_id: String,
        operation_id: String,
    },
    ContinuationPointConflict {
        thread_id: String,
        operation_id: String,
        expected_continuation_id: String,
        accepted_continuation_id: String,
    },
    ContinuationRouteConflict {
        thread_id: String,
        operation_id: String,
        expected_model_route_revision: u64,
        accepted_model_route_revision: u64,
    },
    StaleContinuation {
        thread_id: String,
        expected_continuation_id: String,
        current_continuation_id: String,
    },
    ClaimedContinuation {
        thread_id: String,
        continuation_id: String,
    },
    ChildInteraction {
        interaction_id: String,
        interaction_thread_id: String,
    },
    InteractionRevision {
        interaction_id: String,
        expected_revision: u64,
        current_revision: u64,
    },
    InteractionTerminal {
        interaction_id: String,
        current_revision: u64,
    },
    InteractionOperation {
        operation_id: String,
        interaction_id: String,
    },
    ChildHost {
        host_thread_id: String,
        host_is_child: bool,
    },
    InteractionHost {
        host_thread_id: String,
        interaction_thread_id: String,
    },
    DecisionDurability {
        interaction_id: String,
        decision_saved: bool,
    },
    UnreadableDecision {
        thread_id: String,
        interaction_id: String,
    },
    DecisionIdentity {
        interaction_id: String,
        current_revision: u64,
        operation_identity_recorded: bool,
    },
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
    Control {
        reason: String,
        facts: BridgeControlFailureFacts,
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
            StudioErrorDetails::Control { reason, facts } => Self::Control { reason, facts: facts.into() },
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

impl From<pl_protocol::studio::ControlFailureFacts> for BridgeControlFailureFacts {
    fn from(value: pl_protocol::studio::ControlFailureFacts) -> Self {
        use pl_protocol::studio::ControlFailureFacts as Facts;
        match value {
            Facts::Unspecified => Self::Unspecified,
            Facts::ChildThreadAction { thread_id, action, parent_thread_id } => Self::ChildThreadAction { thread_id, action, parent_thread_id },
            Facts::ThreadAction { thread_id, action } => Self::ThreadAction { thread_id, action },
            Facts::ExpectedExecution { thread_id, expected_execution_id } => Self::ExpectedExecution { thread_id, expected_execution_id },
            Facts::Executing { thread_id, execution_id, phase } => Self::Executing { thread_id, execution_id, phase },
            Facts::ExpectedContinuation { thread_id, expected_continuation_id } => Self::ExpectedContinuation { thread_id, expected_continuation_id },
            Facts::ContinuationAccepted { thread_id, operation_id, accepted } => Self::ContinuationAccepted { thread_id, operation_id, accepted },
            Facts::ContinuationOperation { thread_id, operation_id } => Self::ContinuationOperation { thread_id, operation_id },
            Facts::ContinuationPointConflict { thread_id, operation_id, expected_continuation_id, accepted_continuation_id } => Self::ContinuationPointConflict { thread_id, operation_id, expected_continuation_id, accepted_continuation_id },
            Facts::ContinuationRouteConflict { thread_id, operation_id, expected_model_route_revision, accepted_model_route_revision } => Self::ContinuationRouteConflict { thread_id, operation_id, expected_model_route_revision, accepted_model_route_revision },
            Facts::StaleContinuation { thread_id, expected_continuation_id, current_continuation_id } => Self::StaleContinuation { thread_id, expected_continuation_id, current_continuation_id },
            Facts::ClaimedContinuation { thread_id, continuation_id } => Self::ClaimedContinuation { thread_id, continuation_id },
            Facts::ChildInteraction { interaction_id, interaction_thread_id } => Self::ChildInteraction { interaction_id, interaction_thread_id },
            Facts::InteractionRevision { interaction_id, expected_revision, current_revision } => Self::InteractionRevision { interaction_id, expected_revision, current_revision },
            Facts::InteractionTerminal { interaction_id, current_revision } => Self::InteractionTerminal { interaction_id, current_revision },
            Facts::InteractionOperation { operation_id, interaction_id } => Self::InteractionOperation { operation_id, interaction_id },
            Facts::ChildHost { host_thread_id, host_is_child } => Self::ChildHost { host_thread_id, host_is_child },
            Facts::InteractionHost { host_thread_id, interaction_thread_id } => Self::InteractionHost { host_thread_id, interaction_thread_id },
            Facts::DecisionDurability { interaction_id, decision_saved } => Self::DecisionDurability { interaction_id, decision_saved },
            Facts::UnreadableDecision { thread_id, interaction_id } => Self::UnreadableDecision { thread_id, interaction_id },
            Facts::DecisionIdentity { interaction_id, current_revision, operation_identity_recorded } => Self::DecisionIdentity { interaction_id, current_revision, operation_identity_recorded },
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

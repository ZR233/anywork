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
    pub details_json: Option<String>,
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
            details_json: error.details.map(|details| details.to_string()),
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

impl From<pl_studio_update::StudioUpdateError> for BridgeError {
    fn from(error: pl_studio_update::StudioUpdateError) -> Self {
        Self::from(anyhow::Error::new(error))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn protocol_version_mismatch_reason_survives_bridge_conversion() {
        let error = pl_protocol::studio::StudioError::new(
            pl_protocol::studio::StudioErrorCode::Protocol,
            "unsupported completed-history version",
            false,
        )
        .with_reason(
            pl_protocol::studio::StudioErrorReason::ProtocolVersionMismatch,
            serde_json::Value::Null,
        );
        let bridge = BridgeError::from(error);
        let details: serde_json::Value = serde_json::from_str(
            bridge
                .details_json
                .as_deref()
                .expect("reason is carried in details"),
        )
        .expect("details JSON remains valid");
        assert_eq!(
            details["reason"],
            pl_protocol::studio::StudioErrorReason::ProtocolVersionMismatch.label()
        );
    }
}

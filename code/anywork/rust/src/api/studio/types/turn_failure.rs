//! One typed failure vocabulary shared by Timeline, Thread facets and immutable read values.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeTurnFailureCategory {
    Provider,
    ProviderCapacity,
    Tool,
    Validation,
    Protocol,
    Internal,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeProviderFailureKind {
    Authentication,
    Authorization,
    Capacity,
    Configuration,
    Transport,
    Protocol,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeRetryDisposition {
    Retryable { retry_after_ms: Option<u64> },
    Permanent,
}

impl From<pl_protocol::TurnFailureCategory> for BridgeTurnFailureCategory {
    fn from(value: pl_protocol::TurnFailureCategory) -> Self {
        match value {
            pl_protocol::TurnFailureCategory::Provider => Self::Provider,
            pl_protocol::TurnFailureCategory::ProviderCapacity => Self::ProviderCapacity,
            pl_protocol::TurnFailureCategory::Tool => Self::Tool,
            pl_protocol::TurnFailureCategory::Validation => Self::Validation,
            pl_protocol::TurnFailureCategory::Protocol => Self::Protocol,
            pl_protocol::TurnFailureCategory::Internal => Self::Internal,
        }
    }
}

impl From<pl_protocol::ProviderFailureKind> for BridgeProviderFailureKind {
    fn from(value: pl_protocol::ProviderFailureKind) -> Self {
        match value {
            pl_protocol::ProviderFailureKind::Authentication => Self::Authentication,
            pl_protocol::ProviderFailureKind::Authorization => Self::Authorization,
            pl_protocol::ProviderFailureKind::Capacity => Self::Capacity,
            pl_protocol::ProviderFailureKind::Configuration => Self::Configuration,
            pl_protocol::ProviderFailureKind::Transport => Self::Transport,
            pl_protocol::ProviderFailureKind::Protocol => Self::Protocol,
            pl_protocol::ProviderFailureKind::Unknown => Self::Unknown,
        }
    }
}

impl From<pl_protocol::RetryDisposition> for BridgeRetryDisposition {
    fn from(value: pl_protocol::RetryDisposition) -> Self {
        match value {
            pl_protocol::RetryDisposition::Retryable { retry_after_ms } => {
                Self::Retryable { retry_after_ms }
            }
            pl_protocol::RetryDisposition::Permanent => Self::Permanent,
        }
    }
}

use super::super::source as bridge;
use pl_protocol::products::source as protocol;

impl From<protocol::ObservedHeader> for bridge::BridgeObservedHeader {
    fn from(value: protocol::ObservedHeader) -> Self {
        Self {
            brief: value.brief.into(),
            status: value.status.into(),
        }
    }
}

impl From<protocol::ObservedBrief> for bridge::BridgeObservedBrief {
    fn from(value: protocol::ObservedBrief) -> Self {
        match value {
            protocol::ObservedBrief::Uninitialized {
                revision,
                updated_at,
            } => Self::Uninitialized {
                revision,
                updated_at,
            },
            protocol::ObservedBrief::Loading {
                revision,
                started_at,
            } => Self::Loading {
                revision,
                started_at,
            },
            protocol::ObservedBrief::Ready {
                revision,
                updated_at,
                last_checked_at,
            } => Self::Ready {
                revision,
                updated_at,
                last_checked_at,
            },
            protocol::ObservedBrief::Refreshing {
                revision,
                started_at,
                last_checked_at,
            } => Self::Refreshing {
                revision,
                started_at,
                last_checked_at,
            },
            protocol::ObservedBrief::Stale {
                revision,
                stale_at,
                last_checked_at,
            } => Self::Stale {
                revision,
                stale_at,
                last_checked_at,
            },
            protocol::ObservedBrief::Degraded {
                revision,
                failed_at,
                last_checked_at,
                retryable,
            } => Self::Degraded {
                revision,
                failed_at,
                last_checked_at,
                retryable,
            },
            protocol::ObservedBrief::Failed {
                revision,
                failed_at,
                retryable,
            } => Self::Failed {
                revision,
                failed_at,
                retryable,
            },
            protocol::ObservedBrief::Stopped {
                revision,
                stopped_at,
            } => Self::Stopped {
                revision,
                stopped_at,
            },
        }
    }
}

impl From<protocol::SourceStateErrorRead> for bridge::BridgeSourceStateErrorRead {
    fn from(value: protocol::SourceStateErrorRead) -> Self {
        Self {
            code: value.code.into(),
            message: value.message.into(),
            retryable: value.retryable,
        }
    }
}

impl From<protocol::ProductSourceStatusReadHeader> for bridge::BridgeProductSourceStatusReadHeader {
    fn from(value: protocol::ProductSourceStatusReadHeader) -> Self {
        match value {
            protocol::ProductSourceStatusReadHeader::Uninitialized {
                revision,
                updated_at,
            } => Self::Uninitialized {
                revision,
                updated_at,
            },
            protocol::ProductSourceStatusReadHeader::Loading {
                revision,
                operation,
                operation_id,
                started_at,
            } => Self::Loading {
                revision,
                operation: operation.into(),
                operation_id: operation_id.into(),
                started_at,
            },
            protocol::ProductSourceStatusReadHeader::Ready {
                revision,
                updated_at,
                last_checked_at,
            } => Self::Ready {
                revision,
                updated_at,
                last_checked_at,
            },
            protocol::ProductSourceStatusReadHeader::Refreshing {
                revision,
                operation,
                operation_id,
                started_at,
                last_checked_at,
            } => Self::Refreshing {
                revision,
                operation: operation.into(),
                operation_id: operation_id.into(),
                started_at,
                last_checked_at,
            },
            protocol::ProductSourceStatusReadHeader::Stale {
                revision,
                stale_at,
                last_checked_at,
            } => Self::Stale {
                revision,
                stale_at,
                last_checked_at,
            },
            protocol::ProductSourceStatusReadHeader::Degraded {
                revision,
                failed_at,
                last_checked_at,
                operation,
                error,
            } => Self::Degraded {
                revision,
                failed_at,
                last_checked_at,
                operation: operation.into(),
                error: error.into(),
            },
            protocol::ProductSourceStatusReadHeader::Failed {
                revision,
                failed_at,
                operation,
                error,
            } => Self::Failed {
                revision,
                failed_at,
                operation: operation.into(),
                error: error.into(),
            },
            protocol::ProductSourceStatusReadHeader::Stopped {
                revision,
                stopped_at,
            } => Self::Stopped {
                revision,
                stopped_at,
            },
        }
    }
}

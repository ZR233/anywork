//! Typed failures of the shared transport.

use std::sync::Arc;

/// Failure of one shared transport operation or of the physical connection itself.
///
/// The variants deliberately separate lifecycle from payload problems:
///
/// - [`TransportError::Closed`] means the physical connection can no longer serve work.
///   It is an error and must never be confused with `Ok(None)` from
///   `ConnectionHandle::try_reserve`, which only reports that this connection has no
///   ordinary slot left while the connection is still healthy.
/// - [`TransportError::Cancelled`] means an operation was abandoned by its caller.
/// - [`TransportError::ControlAlreadyOpened`] means the reserved control stream of this
///   connection was already claimed; it is not a connection failure.
/// - [`TransportError::Io`], [`TransportError::Multiplex`] and
///   [`TransportError::DriverTask`] keep the real underlying failure, so a heartbeat can
///   distinguish a dead SSH channel from a protocol defect or an abnormal driver task end.
/// - [`TransportError::InvalidRecord`], [`TransportError::RecordTooLarge`] and
///   [`TransportError::Encoding`] are record problems. A local encoding or budget failure
///   leaves the physical connection usable; a peer record problem ends only the affected
///   stream.
///
/// Business failures travel inside `RemoteResponse::Error`/`RemoteEvent` payloads and
/// never become a connection failure.
///
/// Non-cloneable sources are shared through [`Arc`] so every waiter of a connection's
/// terminal state can report the same real cause.
#[derive(Debug, Clone, thiserror::Error)]
pub enum TransportError {
    /// The physical connection is closed or closing.
    #[error("the remote transport is closed")]
    Closed,
    /// The operation was abandoned before it produced a result.
    #[error("the remote transport operation was cancelled")]
    Cancelled,
    /// The reserved control stream of this connection was already opened.
    #[error("the reserved control stream of this connection was already opened")]
    ControlAlreadyOpened,
    /// Reading or writing the underlying channel failed.
    #[error("remote transport I/O failed: {0}")]
    Io(#[source] Arc<std::io::Error>),
    /// The multiplexer rejected the connection or failed on it.
    #[error("remote transport multiplexer failed: {0}")]
    Multiplex(#[source] Arc<yamux::ConnectionError>),
    /// The connection driver task ended abnormally: it panicked or was cancelled.
    #[error("remote transport driver task ended abnormally: {0}")]
    DriverTask(#[source] Arc<tokio::task::JoinError>),
    /// The peer handed over a record that violates the record contract.
    #[error("invalid remote record: {reason}")]
    InvalidRecord {
        /// What exactly was wrong with the record.
        reason: String,
    },
    /// A record exceeded the per-frame budget.
    #[error("remote record of {actual} bytes exceeds the {limit}-byte budget")]
    RecordTooLarge {
        /// Configured per-frame budget.
        limit: usize,
        /// Actual encoded or declared size.
        actual: usize,
    },
    /// A record could not be encoded or decoded as JSON.
    #[error("failed to encode or decode a remote record: {source}")]
    Encoding {
        /// The underlying serialization failure.
        #[source]
        source: Arc<serde_json::Error>,
    },
}

impl TransportError {
    pub(crate) fn io(error: std::io::Error) -> Self {
        Self::Io(Arc::new(error))
    }

    pub(crate) fn encoding(error: serde_json::Error) -> Self {
        Self::Encoding {
            source: Arc::new(error),
        }
    }

    pub(crate) fn invalid_record(reason: impl Into<String>) -> Self {
        Self::InvalidRecord {
            reason: reason.into(),
        }
    }
}

/// Maps a multiplexer failure onto the shared classification, keeping the real source.
pub(crate) fn multiplex(error: yamux::ConnectionError) -> TransportError {
    match error {
        yamux::ConnectionError::Closed => TransportError::Closed,
        yamux::ConnectionError::Io(error) => TransportError::io(error),
        other => TransportError::Multiplex(Arc::new(other)),
    }
}

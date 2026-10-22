//! Shared SSH substream transport and bounded record framing for both helper peers.
//!
//! One physical SSH stdio channel carries one Yamux connection. The connection owner
//! owns the only driver task; it keeps polling the multiplexer for inbound streams and
//! outbound opens, so a slow operation consumer, a blocked reader or an open request
//! waiting for a peer acknowledgement can never stop the driver from making progress.
//!
//! # Budgets
//!
//! [`OPERATION_STREAMS`], [`MAX_RECORD_BYTES`] and [`DATA_CHUNK_BYTES`] bound *physical*
//! resources and the memory of *one* record. They never bound the number of logical
//! sessions, directory entries, file length or operation total: a logical endpoint that
//! needs more concurrent operations opens another physical connection
//! (`ConnectionHandle::try_reserve` returns `None` when this connection has no ordinary
//! slot left), and an operation larger than one record streams consecutive records.
//!
//! One Yamux stream is reserved for the long-lived control channel; the remaining
//! [`OPERATION_STREAMS`] slots back ordinary request streams. The component default of
//! 512 streams, the 1 GiB aggregate receive window and the 16 KiB send split are kept
//! as-is; raising them is not a substitute for the endpoint pool.
//!
//! # Records
//!
//! Every record is exactly two length-delimited frames: a JSON `RemoteRecordHeader`
//! followed by a binary body (present even when empty). Each frame is limited to
//! [`MAX_RECORD_BYTES`]. Both frames are fully encoded and validated before the first
//! byte is published, so a local encoding failure is reported as a typed error and
//! leaves the physical connection usable.
//!
//! # Ownership, cancellation and shutdown
//!
//! [`ConnectionOwner`] uniquely owns the driver task; [`ConnectionHandle`] clones only
//! observe and reserve, so no reference cycle keeps the driver alive. Dropping the owner
//! cancels the driver; [`ConnectionOwner::close`] and `wait_closed` wait for the real end
//! of that task (including an abnormal end, reported as [`TransportError::DriverTask`])
//! instead of assuming it.
//!
//! One monotone lifecycle carries the observed facts — running, closing, stopping (admission
//! closed, resources released) — while the final result is the real join of the driver task,
//! shared by every observer and never invented by a drop guard. Admission — ordinary
//! reservations (non-blocking `try_reserve` and waiting `reserve`), the control claim and
//! starting a close — is decided by one short synchronous gate that also closes the slot
//! semaphore, so a reservation can never slip past a close; every termination path closes
//! admission first, answers admitted requests with the connection's real result, releases
//! undelivered handles and the hand-off queue, and only then ends the task.
//!
//! The reserved control stream may be opened once per connection; a second attempt fails
//! with [`TransportError::ControlAlreadyOpened`], and abandoning the first attempt after
//! it claimed that identity closes the physical connection instead of letting the peer
//! accept a second control stream.
//!
//! A [`StreamReservation`] transfers its slot to the [`RemoteStream`] it opens, and the
//! slot is returned only when that stream is really released (including both halves of
//! `tokio::io::split`) *and* the multiplexer has reaped it. Recycling through the driver
//! keeps the reservation budget an exact statement of physical capacity, so an ordinary
//! open can never collide with the connection's stream limit. Cancelling `open` before
//! the stream exists releases the slot and leaves no peer-visible stream; cancelling
//! after the stream was handed to the multiplexer resets it.
//!
//! A half-read or half-written record leaves the affected stream unusable, and the
//! caller must discard that operation stream. The control channel has its own owner and
//! must never be abandoned in the middle of a transaction.

mod connection;
mod duplex;
mod error;
mod incoming;
mod progress;
mod record;
mod stream;

pub use connection::{ConnectionHandle, ConnectionOwner, StreamReservation};
pub use error::TransportError;
pub use incoming::IncomingStreams;
pub use record::{RecordReader, RecordWriter, RemoteRecord};
pub use stream::RemoteStream;

/// Binary body type of a [`RemoteRecord`].
pub use bytes::Bytes;
/// Typed wire message carried by a [`RemoteRecord`].
pub use pl_protocol::remote::RemoteMessage;
/// JSON failure source of [`TransportError::Encoding`]; aliased to keep it unambiguous.
pub use serde_json::Error as JsonError;
/// Tokio stream traits implemented by [`RemoteStream`] and accepted by the record types.
pub use tokio::io::{AsyncRead, AsyncWrite};
/// Abnormal driver task end of [`TransportError::DriverTask`].
pub use tokio::task::JoinError;
/// Progress timestamp type returned by `ConnectionHandle::last_progress`.
pub use tokio::time::Instant;
/// Multiplexer failure source of [`TransportError::Multiplex`].
pub use yamux::ConnectionError;

/// Largest binary body or JSON header a single record frame may carry.
///
/// This is a record memory bound, not an operation limit.
pub const MAX_RECORD_BYTES: usize = 64 * 1024;

/// Production block size for streamed file and process bodies.
///
/// It is a scheduling and memory unit; larger operations send consecutive blocks.
pub const DATA_CHUNK_BYTES: usize = 16 * 1024;

/// Ordinary operation stream slots of one physical connection.
///
/// The control stream is reserved on top of this budget.
pub const OPERATION_STREAMS: usize = 511;

/// Which side of the multiplexed connection this process implements.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    /// Opens the reserved control stream and all ordinary operation streams.
    Client,
    /// Accepts inbound streams; it never opens business streams on its own.
    Server,
}

impl Role {
    pub(crate) fn mode(self) -> yamux::Mode {
        match self {
            Self::Client => yamux::Mode::Client,
            Self::Server => yamux::Mode::Server,
        }
    }
}

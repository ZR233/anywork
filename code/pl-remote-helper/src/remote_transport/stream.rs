//! One multiplexed substream seen by both peers.

use std::fmt;
use std::io;
use std::pin::Pin;
use std::sync::Arc;
use std::task::{Context, Poll};

use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::sync::{Notify, OwnedSemaphorePermit, mpsc};
use tokio_util::compat::{Compat, FuturesAsyncReadCompatExt};

/// Hands an ordinary slot back to the connection driver instead of to the semaphore.
///
/// The multiplexer keeps counting a stream until its own driver has reaped it. Recycling
/// through the driver keeps the reservation budget exact: a slot never becomes available
/// again while the multiplexer still counts its stream, so an ordinary open can never
/// collide with the connection's physical stream limit. It is also the honest capacity
/// statement the logical endpoint needs before it decides to open another connection.
#[derive(Debug, Clone)]
pub(crate) struct SlotRecycler {
    release: mpsc::Sender<OwnedSemaphorePermit>,
    wake: Arc<Notify>,
}

impl SlotRecycler {
    pub(crate) fn new(release: mpsc::Sender<OwnedSemaphorePermit>, wake: Arc<Notify>) -> Self {
        Self { release, wake }
    }
}

/// Ordinary slot of one operation stream, recycled when the stream is really gone.
struct SlotGuard {
    recycler: SlotRecycler,
    slot: Option<OwnedSemaphorePermit>,
}

impl SlotGuard {
    fn new(recycler: SlotRecycler, slot: Option<OwnedSemaphorePermit>) -> Self {
        Self { recycler, slot }
    }
}

impl fmt::Debug for SlotGuard {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("SlotGuard")
            .field("reserved", &self.slot.is_some())
            .finish_non_exhaustive()
    }
}

impl Drop for SlotGuard {
    fn drop(&mut self) {
        let Some(slot) = self.slot.take() else {
            return;
        };
        // A rejected send hands the slot back and it is released here: no driver left
        // means the whole connection is gone. `wake` keeps the driver from sleeping on a
        // recycled slot that the multiplexer already reaped.
        let _ = self.recycler.release.try_send(slot);
        self.recycler.wake.notify_one();
    }
}

/// One bidirectional Yamux substream as Tokio asynchronous I/O.
///
/// The stream owns the ordinary slot of the reservation that opened it, so the slot is
/// returned exactly when the last handle of this stream goes away, including after
/// `tokio::io::split`. Accepted inbound streams do not hold an ordinary slot of this
/// side; they consume the peer's.
///
/// Dropping a stream whose send side is still open resets it on the peer instead of
/// leaving an orphan stream behind.
pub struct RemoteStream {
    // Field order is the drop order: the multiplexed stream goes away first, so its
    // slot can only be recycled after the multiplexer can observe the drop.
    inner: Compat<yamux::Stream>,
    id: u32,
    slot: SlotGuard,
}

impl RemoteStream {
    pub(crate) fn new(
        stream: yamux::Stream,
        recycler: SlotRecycler,
        slot: Option<OwnedSemaphorePermit>,
    ) -> Self {
        let id = stream.id().val();
        // Yamux speaks `futures::io`; one `Compat` value serves Tokio reads and writes.
        Self {
            inner: stream.compat(),
            id,
            slot: SlotGuard::new(recycler, slot),
        }
    }

    /// Yamux identity of this stream within the physical connection.
    ///
    /// The value only orders streams of one connection; it is not a stable global name.
    pub fn id(&self) -> u32 {
        self.id
    }
}

impl fmt::Debug for RemoteStream {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("RemoteStream")
            .field("id", &self.id)
            .field("slot", &self.slot)
            .finish_non_exhaustive()
    }
}

impl AsyncRead for RemoteStream {
    fn poll_read(
        self: Pin<&mut Self>,
        context: &mut Context<'_>,
        buffer: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        Pin::new(&mut self.get_mut().inner).poll_read(context, buffer)
    }
}

impl AsyncWrite for RemoteStream {
    fn poll_write(
        self: Pin<&mut Self>,
        context: &mut Context<'_>,
        data: &[u8],
    ) -> Poll<io::Result<usize>> {
        Pin::new(&mut self.get_mut().inner).poll_write(context, data)
    }

    fn poll_flush(self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.get_mut().inner).poll_flush(context)
    }

    fn poll_shutdown(self: Pin<&mut Self>, context: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.get_mut().inner).poll_shutdown(context)
    }
}

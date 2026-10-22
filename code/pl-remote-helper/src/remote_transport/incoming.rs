//! Hand-off of accepted inbound streams to the accepting task.

use std::collections::VecDeque;
use std::fmt;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};

use tokio::sync::Notify;

use crate::remote_transport::TransportError;
use crate::remote_transport::connection::{JoinedTask, Shared};
use crate::remote_transport::stream::RemoteStream;

/// Hand-off queue state: queued handles plus whether the connection ended.
#[derive(Debug)]
struct Queue {
    closed: bool,
    streams: VecDeque<yamux::Stream>,
}

/// Bounded hand-off queue between the driver and the accepting task.
///
/// Only stream handles are queued, never payloads, so the queue can never grow with the
/// size of a directory, file or process output. Its capacity is the multiplexer's own
/// physical stream budget: the driver never has to drop an accepted stream, and it still
/// never waits on the consumer — it keeps driving the multiplexer when the consumer is
/// behind, holding the handles itself.
#[derive(Debug)]
pub(crate) struct Inbound {
    capacity: usize,
    queue: Mutex<Queue>,
    /// Wakes the accepting task when a stream is queued or the connection ends.
    pub(crate) accepted: Notify,
    /// Wakes the driver when queue space became available again.
    pub(crate) drained: Notify,
}

impl Inbound {
    pub(crate) fn new(capacity: usize) -> Self {
        Self {
            capacity,
            queue: Mutex::new(Queue {
                closed: false,
                streams: VecDeque::new(),
            }),
            accepted: Notify::new(),
            drained: Notify::new(),
        }
    }

    /// Queues one stream, or hands it back when the connection already ended.
    pub(crate) fn push(&self, stream: yamux::Stream) -> Option<yamux::Stream> {
        {
            let mut queue = self.lock();
            if queue.closed || queue.streams.len() >= self.capacity {
                // The handle is returned to the driver; it is never queued twice.
                return Some(stream);
            }
            queue.streams.push_back(stream);
        }
        self.accepted.notify_one();
        None
    }

    fn pop(&self) -> Option<yamux::Stream> {
        let mut queue = self.lock();
        if queue.closed {
            return None;
        }
        queue.streams.pop_front()
    }

    /// Ends the hand-off and releases every undelivered handle.
    ///
    /// Dropping a handle resets its stream on the peer instead of leaving it pending.
    pub(crate) fn close(&self) {
        {
            let mut queue = self.lock();
            queue.closed = true;
            queue.streams.clear();
        }
        self.accepted.notify_waiters();
        self.drained.notify_waiters();
    }

    fn lock(&self) -> MutexGuard<'_, Queue> {
        // The queue is only touched for short, panic-free bookkeeping; recover the
        // contents instead of spreading a poisoning panic through the transport.
        self.queue.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

/// Inbound half of one physical connection, held by the accepting peer.
///
/// `accept` hands streams over until the driver task really ended: it then returns
/// `Ok(None)` for a deliberate local close and `Err` with the final cause, including
/// [`TransportError::DriverTask`] for an abnormal task end. It never blocks the driver.
pub struct IncomingStreams {
    shared: Arc<Shared>,
    /// Shared real join of the driver task; the hand-off ends only when this completes.
    joined: JoinedTask,
}

impl IncomingStreams {
    pub(crate) fn new(shared: Arc<Shared>, joined: JoinedTask) -> Self {
        Self { shared, joined }
    }

    /// Waits for the next inbound stream.
    ///
    /// # Errors
    ///
    /// Returns the connection's final failure once the driver task really ended, and
    /// [`TransportError::Closed`] when no final cause could be published.
    pub async fn accept(&mut self) -> Result<Option<RemoteStream>, TransportError> {
        // Subscribe to the persistent lifecycle before looking at it, so a close published
        // from now on is never missed.
        let mut lifecycle = self.shared.state_watch();
        let mut joined = self.joined.clone();
        let end = loop {
            if let Some(stream) = self.shared.inbound.pop() {
                self.shared.inbound.drained.notify_one();
                return Ok(Some(RemoteStream::new(
                    stream,
                    self.shared.recycler(),
                    None,
                )));
            }
            // `accepted` keeps a stored permit, so an arrival between the pop above and this
            // wait still wakes us; `changed` is persistent, so a close is never lost.
            let accepted = self.shared.inbound.accepted.notified();
            tokio::select! {
                outcome = &mut joined => break outcome,
                changed = lifecycle.changed() => changed.map_err(|_| TransportError::Closed)?,
                _ = accepted => {}
            }
        };
        // The driver task really ended, so the hand-off cannot grow any further.
        self.shared.terminal_from(end).map(|()| None)
    }
}

impl fmt::Debug for IncomingStreams {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("IncomingStreams")
            .field("closed", &self.shared.is_closed())
            .finish_non_exhaustive()
    }
}

//! Connection ownership, the single multiplexer driver, and stream reservations.

use std::collections::VecDeque;
use std::fmt;
use std::sync::{Arc, Mutex, MutexGuard, PoisonError};
use std::task::{Context, Poll};

use futures::FutureExt;
use futures::future::{BoxFuture, Shared as SharedJoin};
use tokio::io::{AsyncRead, AsyncWrite};
use tokio::sync::{Notify, OwnedSemaphorePermit, Semaphore, TryAcquireError, mpsc, oneshot, watch};
use tokio::task::AbortHandle;
use tokio_util::compat::TokioAsyncReadCompatExt;

use crate::remote_transport::duplex::Duplex;
use crate::remote_transport::error::{TransportError, multiplex};
use crate::remote_transport::incoming::{Inbound, IncomingStreams};
use crate::remote_transport::progress::Progress;
use crate::remote_transport::stream::{RemoteStream, SlotRecycler};
use crate::remote_transport::{OPERATION_STREAMS, Role};

/// Multiplexer streams reserved for the control channel of one connection.
const CONTROL_STREAMS: usize = 1;

/// Physical streams of one connection: the component's stream budget.
const CONNECTION_STREAMS: usize = OPERATION_STREAMS + CONTROL_STREAMS;

// The hand-off queue and the pool's expansion decision rest on this physical budget.
const _: () = assert!(CONNECTION_STREAMS == 512);

/// Accepted inbound streams the driver hands over before it has to hold them.
///
/// This is the same physical stream budget, not a second capacity source: the multiplexer
/// never accepts more streams than this, so no accepted stream ever has to be dropped and
/// no payload is ever queued.
const INBOUND_QUEUE_STREAMS: usize = CONNECTION_STREAMS;

/// Accepted inbound streams one driver poll may take before yielding to the runtime.
const INBOUND_BATCH: usize = 32;

/// Real joined result of the driver task.
pub(crate) type Joined = Result<(), Arc<tokio::task::JoinError>>;

/// One shared join future: every observer awaits the same real task result, and cancelling
/// one observer never loses the responsibility or the result for the others.
pub(crate) type JoinedTask = SharedJoin<BoxFuture<'static, Joined>>;

/// How one physical connection ended.
#[derive(Debug, Clone)]
pub(crate) enum Terminal {
    /// The local side closed the connection deliberately.
    Closed,
    /// The connection failed, or the peer ended it without a local close request.
    Failed(TransportError),
}

/// One outbound open request owned by the driver until it is answered.
struct OpenRequest {
    /// Ordinary-slot permit of the caller; the driver keeps it with the stream.
    slot: Option<OwnedSemaphorePermit>,
    reply: oneshot::Sender<Result<RemoteStream, TransportError>>,
}

impl fmt::Debug for OpenRequest {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("OpenRequest")
            .field("reserved", &self.slot.is_some())
            .finish_non_exhaustive()
    }
}

/// Observable lifecycle of one physical connection.
///
/// The states are monotone and carried by a single watch channel, so every observer sees
/// the same fact instead of several surfaces that could disagree.
#[derive(Debug, Clone)]
pub(crate) enum State {
    /// The connection admits work and the driver is running.
    Running,
    /// Admission is closed and the driver is draining the multiplexer.
    Closing,
    /// Admission is closed and the driver released its resources; the joined result of the
    /// driver task is still pending.
    ///
    /// The final observable result is the real join of the driver task, never a state
    /// published by a drop guard.
    Stopping(Terminal),
}

impl State {
    fn rank(&self) -> u8 {
        match self {
            Self::Running => 0,
            Self::Closing => 1,
            Self::Stopping(_) => 2,
        }
    }
}

/// Short synchronous gate deciding ordinary reservations, the control claim and starting a
/// close on one linearization point.
///
/// It is never held across an await and guards no I/O: it only orders admission against
/// closing, so no check-then-act window can exist between them.
#[derive(Debug)]
struct Admission {
    closed: bool,
    control_claimed: bool,
}

/// State shared by the owner, its observer clones and the driver.
pub(crate) struct Shared {
    /// Bounded queue of ordinary opens; the slot budget keeps it from overflowing.
    open_tx: mpsc::Sender<OpenRequest>,
    /// Single reserved control open.
    control_tx: mpsc::Sender<OpenRequest>,
    /// Wakes the driver when an open request was queued or the lifecycle moved.
    wake: Arc<Notify>,
    /// Recycles ordinary slots through the driver once their stream is really reaped.
    recycler: SlotRecycler,
    /// Admission gate; the same gate closes the connection.
    admission: Mutex<Admission>,
    /// Ordinary operation slots of this physical connection.
    permits: Arc<Semaphore>,
    progress: Arc<Progress>,
    pub(crate) inbound: Arc<Inbound>,
    state_tx: watch::Sender<State>,
    state_rx: watch::Receiver<State>,
}

impl Shared {
    fn new() -> (Arc<Self>, DriverChannels) {
        let (open_tx, open_rx) = mpsc::channel(OPERATION_STREAMS);
        let (control_tx, control_rx) = mpsc::channel(1);
        // One message per ordinary slot, so a recycled slot can never be rejected.
        let (release_tx, release_rx) = mpsc::channel(OPERATION_STREAMS);
        let (state_tx, state_rx) = watch::channel(State::Running);
        let wake = Arc::new(Notify::new());
        let shared = Arc::new(Self {
            open_tx,
            control_tx,
            wake: Arc::clone(&wake),
            recycler: SlotRecycler::new(release_tx, wake),
            admission: Mutex::new(Admission {
                closed: false,
                control_claimed: false,
            }),
            permits: Arc::new(Semaphore::new(OPERATION_STREAMS)),
            progress: Arc::new(Progress::new()),
            inbound: Arc::new(Inbound::new(INBOUND_QUEUE_STREAMS)),
            state_tx,
            state_rx: state_rx.clone(),
        });
        (
            shared,
            DriverChannels {
                open_rx,
                control_rx,
                release_rx,
            },
        )
    }

    /// Handle a stream uses to hand its slot back for recycling.
    pub(crate) fn recycler(&self) -> SlotRecycler {
        self.recycler.clone()
    }

    /// Current lifecycle state.
    pub(crate) fn state(&self) -> State {
        self.state_rx.borrow().clone()
    }

    /// Subscription to lifecycle changes; a late subscriber still sees the current state.
    pub(crate) fn state_watch(&self) -> watch::Receiver<State> {
        self.state_rx.clone()
    }

    /// Whether the connection no longer admits work.
    ///
    /// This reads the same admission fact that decides reservations and the control claim,
    /// so `is_closed` and a refused reservation can never disagree.
    pub(crate) fn is_closed(&self) -> bool {
        self.lock_admission().closed
    }

    fn lock_admission(&self) -> MutexGuard<'_, Admission> {
        self.admission
            .lock()
            .unwrap_or_else(PoisonError::into_inner)
    }

    /// Closes admission on the shared linearization point.
    ///
    /// The slot semaphore is closed inside the same gate, so a reservation or a control
    /// claim either happens strictly before this call or is refused by it.
    fn close_admission(&self) {
        let mut admission = self.lock_admission();
        admission.closed = true;
        self.permits.close();
    }

    /// Admits one ordinary operation slot without waiting.
    fn admit(
        self: &Arc<Self>,
        joined: JoinedTask,
    ) -> Result<Option<StreamReservation>, TransportError> {
        let slot = {
            let admission = self.lock_admission();
            if admission.closed {
                return Err(TransportError::Closed);
            }
            match Arc::clone(&self.permits).try_acquire_owned() {
                Ok(slot) => slot,
                Err(TryAcquireError::NoPermits) => return Ok(None),
                Err(TryAcquireError::Closed) => return Err(TransportError::Closed),
            }
        };
        Ok(Some(self.reservation(slot, joined)))
    }

    /// Admits an already acquired slot, re-checking admission in the same critical section.
    fn admit_acquired(
        self: &Arc<Self>,
        slot: OwnedSemaphorePermit,
        joined: JoinedTask,
    ) -> Result<StreamReservation, TransportError> {
        {
            let admission = self.lock_admission();
            if admission.closed {
                // Hand the physical slot back before reporting the close.
                drop(admission);
                drop(slot);
                return Err(TransportError::Closed);
            }
        }
        Ok(self.reservation(slot, joined))
    }

    fn reservation(
        self: &Arc<Self>,
        slot: OwnedSemaphorePermit,
        joined: JoinedTask,
    ) -> StreamReservation {
        StreamReservation {
            shared: Arc::clone(self),
            slot,
            joined,
        }
    }

    /// Claims the reserved control identity of this connection.
    fn claim_control(self: &Arc<Self>) -> Result<ControlClaim, TransportError> {
        let mut admission = self.lock_admission();
        if admission.closed {
            return Err(TransportError::Closed);
        }
        if admission.control_claimed {
            return Err(TransportError::ControlAlreadyOpened);
        }
        admission.control_claimed = true;
        Ok(ControlClaim {
            shared: Arc::clone(self),
            armed: true,
        })
    }

    /// Requests a deliberate close; the driver observes it and terminates the multiplexer.
    fn request_close(&self) {
        self.close_admission();
        self.advance(State::Closing);
    }

    /// Records that the driver released its resources; the joined result is still pending.
    fn stopping(&self, outcome: Terminal) {
        self.close_admission();
        self.inbound.close();
        self.advance(State::Stopping(outcome));
    }

    /// The driver's own outcome, once it released its resources.
    fn driver_outcome(&self) -> Option<Terminal> {
        match self.state() {
            State::Stopping(outcome) => Some(outcome),
            _ => None,
        }
    }

    /// Moves the lifecycle forward; a later fact is never overwritten by an earlier one.
    ///
    /// The rank comparison and the publication happen under the watch's write lock, so two
    /// racing closers can never let an earlier fact overwrite a later one (for example a
    /// `Closing` publication restoring itself over `Stopping`).
    fn advance(&self, next: State) {
        let published = self.state_tx.send_if_modified(|current| {
            if next.rank() <= current.rank() {
                return false;
            }
            *current = next;
            true
        });
        if published {
            self.wake.notify_waiters();
        }
    }

    /// Combines the real joined task result with the driver's own outcome.
    pub(crate) fn terminal_from(&self, outcome: Joined) -> Result<(), TransportError> {
        match outcome {
            Ok(()) => match self.driver_outcome() {
                Some(Terminal::Closed) => Ok(()),
                Some(Terminal::Failed(error)) => Err(error),
                // The task ended without publishing its own outcome; never a clean close.
                None => Err(TransportError::Closed),
            },
            Err(join_error) => Err(TransportError::DriverTask(join_error)),
        }
    }

    /// Waits for the real end of the driver task and reports its terminal result.
    async fn terminal_result(&self, joined: JoinedTask) -> Result<(), TransportError> {
        self.terminal_from(joined.await)
    }

    /// Terminal error for a caller whose request can no longer be served.
    async fn terminal_error(&self, joined: JoinedTask) -> TransportError {
        match self.terminal_result(joined).await {
            Ok(()) => TransportError::Closed,
            Err(error) => error,
        }
    }
}

impl fmt::Debug for Shared {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("Shared")
            .field("state", &self.state())
            .field("available_slots", &self.permits.available_permits())
            .finish_non_exhaustive()
    }
}

/// Exclusive owner of one multiplexed physical connection.
///
/// The owner keeps the only task that drives the Yamux connection. Observer clones
/// ([`ConnectionHandle`]) never own that task, so no reference cycle can extend its
/// lifetime. Dropping the owner cancels the driver; a graceful shutdown must use
/// [`ConnectionOwner::close`] or [`ConnectionOwner::wait_closed`] and observe the real
/// result.
///
/// The real join of that task is shared with every observer, so each waiter — `close`,
/// `wait_closed`, the inbound acceptor, a refused reservation — sees the true end of the task
/// (including an abnormal end), and cancelling one waiter never loses the result for others.
pub struct ConnectionOwner {
    shared: Arc<Shared>,
    /// Hard cancellation of the driver task.
    driver: AbortHandle,
    /// Shared real join of the driver task; the final result comes from here only.
    joined: JoinedTask,
}

impl ConnectionOwner {
    /// Starts the transport over a physical reader/writer pair.
    ///
    /// `start` returns immediately with the owner, an observer handle and the inbound
    /// stream acceptor for this role. The driver task is spawned on the current Tokio
    /// runtime and owns the multiplexer from now on.
    ///
    /// # Panics
    ///
    /// Panics when called outside a Tokio runtime, because the driver task is spawned
    /// there.
    pub fn start<R, W>(
        reader: R,
        writer: W,
        role: Role,
    ) -> (Self, ConnectionHandle, IncomingStreams)
    where
        R: AsyncRead + Unpin + Send + 'static,
        W: AsyncWrite + Unpin + Send + 'static,
    {
        let (shared, channels) = Shared::new();
        let connection = yamux::Connection::new(
            Duplex::new(reader, writer, Arc::clone(&shared.progress)).compat(),
            connection_config(),
            role.mode(),
        );
        // The terminal guard exists before the task does, so a task that is dropped before
        // its first poll still releases the connection and wakes every waiter.
        let task = DriverTask {
            connection,
            channels,
            shared: Arc::clone(&shared),
            guard: TerminalGuard {
                shared: Arc::clone(&shared),
                armed: true,
            },
        };
        let driver = tokio::spawn(drive(task));
        let abort = driver.abort_handle();
        // The real join of that task is shared by every observer: awaiting it never replaces
        // the outcome with a synthetic one, and cancelling one observer cannot lose it.
        let joined: JoinedTask = driver
            .map(|joined| joined.map_err(Arc::new))
            .boxed()
            .shared();
        let handle = ConnectionHandle {
            shared: Arc::clone(&shared),
            joined: joined.clone(),
        };
        let incoming = IncomingStreams::new(Arc::clone(&shared), joined.clone());
        (
            Self {
                shared,
                driver: abort,
                joined,
            },
            handle,
            incoming,
        )
    }

    /// Closes the connection and waits until the driver task really ended.
    ///
    /// Closing admission happens before the first await, so no reservation can be granted
    /// after this call started.
    ///
    /// # Errors
    ///
    /// Returns the failure that ended the connection, including a failure that happened
    /// before the close request and an abnormal task end, so callers never report a clean
    /// shutdown they did not observe.
    pub async fn close(&self) -> Result<(), TransportError> {
        self.shared.request_close();
        self.shared.terminal_result(self.joined.clone()).await
    }

    /// Waits until the driver task really ended.
    ///
    /// # Errors
    ///
    /// Returns the failure that ended the connection; `Ok(())` means the local side closed
    /// it deliberately. An abnormal task end is reported as
    /// [`TransportError::DriverTask`].
    pub async fn wait_closed(&self) -> Result<(), TransportError> {
        self.shared.terminal_result(self.joined.clone()).await
    }
}

impl fmt::Debug for ConnectionOwner {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ConnectionOwner")
            .field("shared", &self.shared)
            .finish_non_exhaustive()
    }
}

impl Drop for ConnectionOwner {
    fn drop(&mut self) {
        // Abandoned owner: close admission and cancel the driver instead of leaving a task
        // that could outlive every observer. Observers still learn the real end of the
        // task, including a cancelled join result, instead of a silent shutdown.
        self.shared.request_close();
        self.driver.abort();
    }
}

/// Cloneable observer of one connection.
///
/// A handle can reserve ordinary slots, open the reserved control stream and observe the
/// connection state. It never owns the driver task and never keeps the connection alive.
#[derive(Clone)]
pub struct ConnectionHandle {
    shared: Arc<Shared>,
    /// Shared real join of the driver task; every refusal reports that real result.
    joined: JoinedTask,
}

impl ConnectionHandle {
    /// Reserves one ordinary operation slot without waiting.
    ///
    /// # Errors
    ///
    /// Returns the connection's real terminal result once it stops admitting work, which is
    /// an error and never a capacity statement. `Ok(None)` means this physical connection has
    /// no ordinary slot left while it is still healthy; the logical endpoint should open
    /// another physical connection in that case instead of queueing unbounded work.
    pub fn try_reserve(&self) -> Result<Option<StreamReservation>, TransportError> {
        // Reservation and closing share one synchronous admission gate, so a reservation can
        // never slip past a close that already returned.
        self.shared.admit(self.joined.clone())
    }

    /// Waits for one ordinary physical slot.
    ///
    /// The wait is real semaphore capacity, not a poll loop: a released stream returns its
    /// slot and wakes one waiter. Cancelling the wait keeps no permit and sends no bytes.
    ///
    /// # Errors
    ///
    /// Returns the connection's real terminal result when it stops admitting work, including
    /// an abnormal driver task end.
    pub async fn reserve(&self) -> Result<StreamReservation, TransportError> {
        // Closing the connection closes this semaphore, so every waiter wakes immediately
        // instead of waiting for capacity that can never come.
        let slot = match Arc::clone(&self.shared.permits).acquire_owned().await {
            Ok(slot) => slot,
            Err(_) => return Err(self.shared.terminal_error(self.joined.clone()).await),
        };
        match self.shared.admit_acquired(slot, self.joined.clone()) {
            Ok(reservation) => Ok(reservation),
            // A close linearized while we waited; report its real result, never a stale slot.
            Err(_) => Err(self.shared.terminal_error(self.joined.clone()).await),
        }
    }

    /// Opens the reserved control stream of this connection.
    ///
    /// The control stream is reserved on top of the ordinary slots, so it is available even
    /// while every operation slot is in use. It belongs to exactly one caller: the identity
    /// is claimed on the first poll of this future, and abandoning it after that point closes
    /// the physical connection instead of letting a peer that already accepted the first
    /// stream accept a second control stream.
    ///
    /// # Errors
    ///
    /// Returns [`TransportError::ControlAlreadyOpened`] when the control stream of this
    /// connection was already claimed, and the connection's real terminal result when it
    /// stops admitting work or the multiplexer refused the stream.
    pub async fn open_control(&self) -> Result<RemoteStream, TransportError> {
        // Nothing is claimed until this future is polled for the first time; the claim then
        // happens under the same admission gate as closing.
        let mut claim = match self.shared.claim_control() {
            Ok(claim) => claim,
            // Admission is already closed: report the real terminal result of the task.
            Err(TransportError::Closed) => {
                return Err(self.shared.terminal_error(self.joined.clone()).await);
            }
            Err(error) => return Err(error),
        };
        let (reply, response) = oneshot::channel();
        if self
            .shared
            .control_tx
            .send(OpenRequest { slot: None, reply })
            .await
            .is_err()
        {
            return Err(self.shared.terminal_error(self.joined.clone()).await);
        }
        self.shared.wake.notify_one();
        let stream = match response.await {
            Ok(result) => result?,
            // The driver dropped the request: report the real task result instead of a
            // synthetic "closed" invented from a vanished sender.
            Err(_) => return Err(self.shared.terminal_error(self.joined.clone()).await),
        };
        claim.armed = false;
        Ok(stream)
    }

    /// Whether the connection no longer admits work.
    pub fn is_closed(&self) -> bool {
        self.shared.is_closed()
    }

    /// Waits until the driver task really ended.
    ///
    /// # Errors
    ///
    /// Returns the real terminal result of the connection, including
    /// [`TransportError::DriverTask`] for an abnormal task end.
    pub async fn wait_closed(&self) -> Result<(), TransportError> {
        self.shared.terminal_result(self.joined.clone()).await
    }

    /// Instant of the last real byte progress on the physical channel.
    pub fn last_progress(&self) -> tokio::time::Instant {
        self.shared.progress.now()
    }
}

impl fmt::Debug for ConnectionHandle {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("ConnectionHandle")
            .field("shared", &self.shared)
            .finish_non_exhaustive()
    }
}

/// One reserved ordinary operation slot, waiting for its stream.
///
/// Dropping the reservation returns the slot. Opening it transfers the slot to the
/// stream, which keeps it until the stream is really released.
pub struct StreamReservation {
    shared: Arc<Shared>,
    slot: OwnedSemaphorePermit,
    /// Shared real join of the driver task; a failed open reports that real result.
    joined: JoinedTask,
}

impl StreamReservation {
    /// Opens the operation stream of this reservation.
    ///
    /// # Errors
    ///
    /// Returns the connection's real terminal result when it ended before a stream was
    /// handed over. Cancelling this future before the stream exists releases the slot
    /// without creating a peer-visible stream; cancelling after the multiplexer created the
    /// stream resets that stream instead of leaving it orphaned.
    pub async fn open(self) -> Result<RemoteStream, TransportError> {
        let Self {
            shared,
            slot,
            joined,
        } = self;
        let (reply, response) = oneshot::channel();
        if shared
            .open_tx
            .send(OpenRequest {
                slot: Some(slot),
                reply,
            })
            .await
            .is_err()
        {
            // The request was never accepted; the real cause is the joined task result.
            return Err(shared.terminal_error(joined).await);
        }
        shared.wake.notify_one();
        match response.await {
            Ok(result) => result,
            // The driver dropped the request without answering: report the real task result.
            Err(_) => Err(shared.terminal_error(joined).await),
        }
    }
}

impl fmt::Debug for StreamReservation {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("StreamReservation")
            .finish_non_exhaustive()
    }
}

/// Why the driver stopped.
enum DriverExit {
    Closed,
    Failed(TransportError),
}

impl DriverExit {
    fn into_terminal(self) -> Terminal {
        match self {
            Self::Closed => Terminal::Closed,
            Self::Failed(error) => Terminal::Failed(error),
        }
    }
}

/// Outcome of one outbound-open attempt.
enum OpenStep {
    /// The multiplexer has no stream for us yet and registered its own wake-up.
    Idle,
    /// One stream was handed to its caller.
    Opened,
    /// A request whose caller went away was discarded before opening anything.
    Discarded,
    /// The connection ended; the driver must stop.
    Exit(DriverExit),
}

/// Releases the connection's resources even when the driver task is cancelled mid-flight.
struct TerminalGuard {
    shared: Arc<Shared>,
    armed: bool,
}

impl Drop for TerminalGuard {
    fn drop(&mut self) {
        if self.armed {
            // Abnormal end (never polled, cancelled or panicked): release admission, the
            // hand-off queue and every undelivered handle. The final result is the real join
            // of this task, published only to observers awaiting it.
            self.shared
                .stopping(Terminal::Failed(TransportError::Closed));
        }
    }
}

/// Closes the physical connection when a claimed control identity is abandoned.
struct ControlClaim {
    shared: Arc<Shared>,
    armed: bool,
}

impl Drop for ControlClaim {
    fn drop(&mut self) {
        if self.armed {
            // The peer may already have accepted the first control stream; opening a
            // second one would break the reserved-channel contract, so close instead.
            self.shared.request_close();
        }
    }
}

/// Keeps the component's physical budgets and half-close semantics.
fn connection_config() -> yamux::Config {
    let mut config = yamux::Config::default();
    // Both peers answer on the stream whose send direction they already half-closed.
    config.set_read_after_close(true);
    config
}

/// Everything the driver future owns, including its terminal guard.
///
/// The guard is built before the task is spawned and lives inside the future, so a task
/// that is dropped before its first poll still closes admission, releases the hand-off
/// queue and wakes every waiter. Fields are declared in release order: the multiplexer and
/// its channels go first, the guard last, so no state transition is published while
/// resources are still held.
struct DriverTask<IO> {
    connection: yamux::Connection<IO>,
    channels: DriverChannels,
    shared: Arc<Shared>,
    guard: TerminalGuard,
}

/// Drives the multiplexer until the connection ends, then publishes the real result.
async fn drive<IO>(mut task: DriverTask<IO>)
where
    IO: futures::io::AsyncRead + futures::io::AsyncWrite + Unpin + Send + 'static,
{
    // Partial moves keep `task` alive, so its guard still runs if this future is cancelled.
    let connection = task.connection;
    let channels = task.channels;
    let shared = task.shared;
    let wake = Arc::clone(&shared.wake);
    let inbound = Arc::clone(&shared.inbound);
    let mut lifecycle = shared.state_watch();
    let mut driver = Driver::new(connection, Arc::clone(&shared), channels);

    let exit = loop {
        tokio::select! {
            exit = std::future::poll_fn(|context| driver.poll_step(context)) => break exit,
            _ = wake.notified() => {}
            changed = lifecycle.changed() => {
                // The lifecycle sender lives as long as the connection itself.
                if changed.is_err() {
                    break DriverExit::Failed(TransportError::Closed);
                }
            }
            _ = inbound.drained.notified() => {}
        }
    };

    // One ordered termination sequence on every path: close admission first, stop new
    // requests, release undelivered streams and the hand-off queue, answer every admitted
    // request with this same real reason, and only then publish the lifecycle transition.
    // The final result is the shared join of this task, owned by the observers.
    shared.close_admission();
    let terminal = exit.into_terminal();
    let reason = match &terminal {
        Terminal::Closed => TransportError::Closed,
        Terminal::Failed(error) => error.clone(),
    };
    driver.close_request_channels();
    driver.release_inbound();
    driver.settle(&reason);
    drop(driver);
    shared.stopping(terminal);
    task.guard.armed = false;
}

/// Channels the driver task receives from the rest of the connection.
///
/// They carry stream handles and slot permits only, never payloads, and every one of them
/// is bounded.
struct DriverChannels {
    open_rx: mpsc::Receiver<OpenRequest>,
    control_rx: mpsc::Receiver<OpenRequest>,
    release_rx: mpsc::Receiver<OwnedSemaphorePermit>,
}

/// The single owner of the multiplexer inside the driver task.
struct Driver<IO> {
    connection: yamux::Connection<IO>,
    shared: Arc<Shared>,
    channels: DriverChannels,
    pending_control: Option<OpenRequest>,
    pending_open: Option<OpenRequest>,
    pending_inbound: VecDeque<yamux::Stream>,
    /// Recycled slots held back until the multiplexer has reaped their streams.
    pending_release: Vec<OwnedSemaphorePermit>,
    closing: bool,
}

impl<IO> Driver<IO>
where
    IO: futures::io::AsyncRead + futures::io::AsyncWrite + Unpin + Send + 'static,
{
    fn new(
        connection: yamux::Connection<IO>,
        shared: Arc<Shared>,
        channels: DriverChannels,
    ) -> Self {
        Self {
            connection,
            shared,
            channels,
            pending_control: None,
            pending_open: None,
            pending_inbound: VecDeque::new(),
            pending_release: Vec::new(),
            closing: false,
        }
    }

    /// One fair round of driver work.
    ///
    /// Outbound opens are served first so a reservation never waits for an unrelated
    /// inbound stream, and inbound streams are still polled on every round so the
    /// multiplexer keeps acknowledging and window-updating while an open waits for peer
    /// acknowledgement or a consumer is behind.
    fn poll_step(&mut self, context: &mut Context<'_>) -> Poll<DriverExit> {
        let closing_requested = !matches!(self.shared.state(), State::Running);
        if closing_requested && !self.closing {
            self.begin_closing();
        }
        let mut accepted = 0usize;
        loop {
            if self.closing {
                return match self.connection.poll_close(context) {
                    Poll::Ready(Ok(())) => Poll::Ready(DriverExit::Closed),
                    Poll::Ready(Err(error)) => {
                        self.shared.close_admission();
                        Poll::Ready(DriverExit::Failed(multiplex(error)))
                    }
                    Poll::Pending => Poll::Pending,
                };
            }
            self.hand_over_inbound();
            // Recycled slots are collected before the multiplexer is polled and published
            // only after a full reap round, so a reservation is never granted for a
            // stream the multiplexer still counts.
            self.hold_recycled_slots();
            self.load_requests();
            let progressed = match self.poll_outbound(context) {
                OpenStep::Exit(exit) => return Poll::Ready(exit),
                OpenStep::Opened | OpenStep::Discarded => true,
                OpenStep::Idle => false,
            };
            match self.connection.poll_next_inbound(context) {
                Poll::Ready(Some(Ok(stream))) => {
                    // Accepted handles are bounded by the multiplexer's own stream budget,
                    // so the backlog never has to drop one.
                    self.pending_inbound.push_back(stream);
                    accepted += 1;
                    if accepted >= INBOUND_BATCH {
                        // Real work is ready; yield so one flooding peer cannot monopolize
                        // the runtime while the backlog is drained.
                        context.waker().wake_by_ref();
                        return Poll::Pending;
                    }
                }
                Poll::Ready(Some(Err(error))) => {
                    // Close admission at the detection point, not only in the termination
                    // sequence, so no reservation can be granted for a dead connection.
                    self.shared.close_admission();
                    return Poll::Ready(DriverExit::Failed(multiplex(error)));
                }
                Poll::Ready(None) => {
                    // End of the physical channel without a local close request.
                    self.shared.close_admission();
                    return Poll::Ready(DriverExit::Failed(TransportError::Closed));
                }
                Poll::Pending => {
                    // Every dropped stream observed before this poll has been reaped, so
                    // the slots collected above are physically free again.
                    self.release_recycled_slots();
                    if progressed {
                        // Further queued requests may still be servable; coming back
                        // immediately keeps them alive without starving inbound work.
                        context.waker().wake_by_ref();
                    }
                    return Poll::Pending;
                }
            }
        }
    }

    /// Collects slots whose streams their last owner released, without publishing them.
    fn hold_recycled_slots(&mut self) {
        while let Ok(slot) = self.channels.release_rx.try_recv() {
            self.pending_release.push(slot);
        }
    }

    /// Makes the held slots available again; only correct right after a full reap round.
    fn release_recycled_slots(&mut self) {
        // Dropping an owned permit returns it to the reservation semaphore.
        self.pending_release.clear();
    }

    /// Hands buffered inbound streams to the consumer queue without ever waiting on it.
    fn hand_over_inbound(&mut self) {
        while let Some(stream) = self.pending_inbound.pop_front() {
            if let Some(stream) = self.shared.inbound.push(stream) {
                self.pending_inbound.push_front(stream);
                return;
            }
        }
    }

    /// Picks up queued open requests; at most one of each kind is in flight.
    fn load_requests(&mut self) {
        if self.pending_control.is_none() {
            while let Ok(request) = self.channels.control_rx.try_recv() {
                if request.reply.is_closed() {
                    // The caller went away before the stream existed; drop the slot only.
                    continue;
                }
                self.pending_control = Some(request);
                break;
            }
        }
        if self.pending_open.is_none() {
            while let Ok(request) = self.channels.open_rx.try_recv() {
                if request.reply.is_closed() {
                    continue;
                }
                self.pending_open = Some(request);
                break;
            }
        }
    }

    /// Serves one pending open without blocking the inbound path.
    fn poll_outbound(&mut self, context: &mut Context<'_>) -> OpenStep {
        let control = self.pending_control.is_some();
        if !control && self.pending_open.is_none() {
            return OpenStep::Idle;
        }
        if self.cancel_before_open(control) {
            return OpenStep::Discarded;
        }

        match self.connection.poll_new_outbound(context) {
            Poll::Ready(Ok(stream)) => {
                let request = if control {
                    self.pending_control.take()
                } else {
                    self.pending_open.take()
                };
                match request {
                    Some(request) => self.complete(request, Ok(stream)),
                    None => drop(stream),
                }
                OpenStep::Opened
            }
            Poll::Ready(Err(error)) => {
                // A refused or failed open ends the physical connection; both pending
                // requests must learn about it instead of waiting forever.
                self.shared.close_admission();
                let error = multiplex(error);
                if let Some(request) = self.pending_control.take() {
                    self.complete(request, Err(error.clone()));
                }
                if let Some(request) = self.pending_open.take() {
                    self.complete(request, Err(error.clone()));
                }
                OpenStep::Exit(DriverExit::Failed(error))
            }
            // The multiplexer registered the wake-up that a peer acknowledgement
            // provides for the next outbound stream.
            Poll::Pending => OpenStep::Idle,
        }
    }

    /// Drops a request whose caller already went away, so the peer never sees the stream.
    fn cancel_before_open(&mut self, control: bool) -> bool {
        let cancelled = if control {
            self.pending_control
                .as_ref()
                .is_some_and(|request| request.reply.is_closed())
        } else {
            self.pending_open
                .as_ref()
                .is_some_and(|request| request.reply.is_closed())
        };
        if cancelled {
            if control {
                self.pending_control = None;
            } else {
                self.pending_open = None;
            }
        }
        cancelled
    }

    /// Hands a stream to its caller; the caller's slot travels with the stream.
    fn complete(&self, request: OpenRequest, outcome: Result<yamux::Stream, TransportError>) {
        let OpenRequest { slot, reply } = request;
        let result = match outcome {
            Ok(stream) => Ok(RemoteStream::new(stream, self.shared.recycler(), slot)),
            Err(error) => {
                drop(slot);
                Err(error)
            }
        };
        if reply.send(result).is_err() {
            tracing::debug!("dropping an opened stream: its caller is no longer waiting");
        }
    }

    /// Stops admitting work and starts closing the multiplexer.
    fn begin_closing(&mut self) {
        self.closing = true;
        // Admission is closed before anything is drained, so no reservation or control
        // claim can be granted while the multiplexer is closing.
        self.shared.close_admission();
        // Requests can no longer be served; answer every buffered one with the closing
        // reason and reject any later one at its own sender.
        self.close_request_channels();
        self.settle(&TransportError::Closed);
    }

    /// Stops new open requests from being enqueued; buffered ones stay drainable.
    fn close_request_channels(&mut self) {
        self.channels.open_rx.close();
        self.channels.control_rx.close();
    }

    /// Answers every pending and queued open with the same real reason.
    fn settle(&mut self, reason: &TransportError) {
        if let Some(request) = self.pending_control.take() {
            self.complete(request, Err(reason.clone()));
        }
        if let Some(request) = self.pending_open.take() {
            self.complete(request, Err(reason.clone()));
        }
        while let Ok(request) = self.channels.control_rx.try_recv() {
            self.complete(request, Err(reason.clone()));
        }
        while let Ok(request) = self.channels.open_rx.try_recv() {
            self.complete(request, Err(reason.clone()));
        }
    }

    /// Releases every undelivered handle and the shared hand-off queue before settling.
    fn release_inbound(&mut self) {
        self.pending_inbound.clear();
        self.release_recycled_slots();
        self.shared.inbound.close();
    }
}

impl<IO> fmt::Debug for Driver<IO> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("Driver")
            .field("closing", &self.closing)
            .field("backlog", &self.pending_inbound.len())
            .finish_non_exhaustive()
    }
}

use super::*;
use pl_protocol::studio::{FeedCloseOutcome, FeedCloseReport};
use pl_protocol::thread_facets::execution::{ExecutionChange, ExecutionEvent, ExecutionFrame};
use pl_protocol::thread_facets::identity::{
    ResyncReason, ThreadFeedIdentity, ThreadObservationMode,
};
use std::collections::VecDeque;

const PENDING_FRAMES: usize = 64;
const PENDING_BYTES: usize = 8 * 1024 * 1024;
const DATA_BYTES: usize = 256 * 1024;

struct Data {
    frame: ExecutionFrame,
    snapshot: Arc<ExecutionSnapshot>,
    extra: Vec<Fact>,
    bytes: usize,
    sequence: u64,
}

struct Window {
    claimed: bool,
    closing: bool,
    sent: u64,
    acked: u64,
    next: u64,
    pending: VecDeque<Data>,
    pending_bytes: usize,
    unacked: VecDeque<Data>,
    terminal: Option<ExecutionFrame>,
    terminal_sent: bool,
    last_revision: Option<u64>,
}

pub(in crate::studio::runtime) struct ExecutionDelivery {
    identity: ThreadFeedIdentity,
    projection: Arc<ExecutionProjection>,
    window: Mutex<Window>,
    changed: Notify,
}

pub enum DeliveryStep {
    Waiting,
    Data,
    Terminal,
}

impl ExecutionProjection {
    pub(in crate::studio::runtime) fn subscribe(
        self: &Arc<Self>,
        mode: ThreadObservationMode,
    ) -> Result<Arc<ExecutionDelivery>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        ensure_open(&state)?;
        if let Some(error) = &state.capture_error {
            return Err(error.clone());
        }
        let listener = Arc::new(ExecutionDelivery {
            identity: ThreadFeedIdentity {
                feed_id: crate::studio::new_id("thread-feed"),
                runtime_epoch: self.epoch.clone(),
                incarnation: self.incarnation,
                facet: ThreadFacet::Execution,
                mode,
            },
            projection: self.clone(),
            window: Mutex::new(Window {
                claimed: false,
                closing: false,
                sent: 0,
                acked: 0,
                next: 1,
                pending: VecDeque::new(),
                pending_bytes: 0,
                unacked: VecDeque::with_capacity(2),
                terminal: None,
                terminal_sent: false,
                last_revision: None,
            }),
            changed: Notify::new(),
        });
        // Subscribe before capturing the baseline, under the same producer guard. The current
        // material and all following changes belong to this exact incarnation without a gap.
        state
            .listeners
            .retain(|listener| listener.strong_count() != 0);
        state.listeners.push(Arc::downgrade(&listener));
        if let Some(current) = &state.current {
            listener.publish(current.clone(), None, Vec::new());
        }
        Ok(listener)
    }
}

impl ExecutionDelivery {
    pub(in crate::studio::runtime) fn identity(&self) -> ThreadFeedIdentity {
        self.identity.clone()
    }

    pub(in crate::studio::runtime) fn claim(&self) -> Result<(), StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if window.closing {
            return Err(cancelled());
        }
        if window.claimed {
            return Err(StudioError::new(
                StudioErrorCode::Conflict,
                "Execution stream was already claimed",
                false,
            ));
        }
        window.claimed = true;
        Ok(())
    }

    pub(super) fn publish(
        &self,
        snapshot: Arc<ExecutionSnapshot>,
        change: Option<(u64, ExecutionChange)>,
        extra: Vec<Fact>,
    ) {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if window.closing || window.terminal.is_some() {
            return;
        }
        let event = match window.last_revision {
            None => ExecutionEvent::Baseline {
                identity: self.identity.clone(),
                stamp: snapshot.stamp.clone(),
                value: snapshot.value.clone(),
            },
            Some(previous) => match change {
                Some((base_revision, value)) if previous == base_revision => {
                    if value.interactions.as_ref().is_some_and(|delta| {
                        delta.upserted.len()
                            + delta.removed_entries.len()
                            + delta.terminal_facts.len()
                            > 100
                    }) {
                        self.resync(&mut window, ResyncReason::ReliableQueueFull);
                        return;
                    }
                    ExecutionEvent::Change {
                        stamp: snapshot.stamp.clone(),
                        base_revision,
                        value,
                    }
                }
                Some(_) | None => {
                    self.resync(&mut window, ResyncReason::RevisionGap);
                    return;
                }
            },
        };
        let sequence = window.next;
        let frame = ExecutionFrame::Data {
            delivery_sequence: sequence,
            event: Box::new(event),
        };
        let bytes = match crate::studio::runtime::read_budget::json_bytes(&frame) {
            Ok(bytes) if bytes <= DATA_BYTES => bytes,
            Ok(_) => {
                window.terminal = Some(ExecutionFrame::Failure {
                    identity: self.identity.clone(),
                    error: StudioError::new(
                        StudioErrorCode::Overloaded,
                        "Execution Data exceeds its source JSON byte budget",
                        false,
                    ),
                });
                self.changed.notify_waiters();
                return;
            }
            Err(error) => {
                window.terminal = Some(ExecutionFrame::Failure {
                    identity: self.identity.clone(),
                    error,
                });
                self.changed.notify_waiters();
                return;
            }
        };
        let Some(total) = window.pending_bytes.checked_add(bytes) else {
            self.resync(&mut window, ResyncReason::ReliableQueueFull);
            return;
        };
        if window.pending.len() >= PENDING_FRAMES || total > PENDING_BYTES {
            self.resync(&mut window, ResyncReason::ReliableQueueFull);
            return;
        }
        let Some(next) = sequence.checked_add(1) else {
            window.terminal = Some(ExecutionFrame::Failure {
                identity: self.identity.clone(),
                error: exhausted(),
            });
            self.changed.notify_waiters();
            return;
        };
        window.next = next;
        window.pending_bytes = total;
        window.last_revision = Some(snapshot.stamp.revision);
        window.pending.push_back(Data {
            frame,
            snapshot,
            extra,
            bytes,
            sequence,
        });
        drop(window);
        self.changed.notify_waiters();
    }

    fn resync(&self, window: &mut Window, reason: ResyncReason) {
        window.terminal = Some(ExecutionFrame::ResyncRequired {
            identity: self.identity.clone(),
            reason,
        });
        window.pending.clear();
        window.pending_bytes = 0;
        self.changed.notify_waiters();
    }

    pub(super) fn request_resync(&self, reason: ResyncReason) {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if window.terminal.is_none() && !window.terminal_sent {
            self.resync(&mut window, reason);
        }
    }

    pub(super) fn finish(&self, terminal: Terminal) {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if window.terminal.is_none() && !window.terminal_sent {
            window.terminal = Some(match terminal {
                Terminal::Failure(error) => ExecutionFrame::Failure {
                    identity: self.identity.clone(),
                    error,
                },
                Terminal::Closed(reason) => ExecutionFrame::Closed {
                    identity: self.identity.clone(),
                    reason,
                },
            });
        }
        drop(window);
        self.changed.notify_waiters();
    }

    /// Nonblocking actual send under producer -> delivery lock order. There is no second mpsc
    /// queue or borrowed slot outside the FIFO accounting; a full window never holds this lock.
    pub(in crate::studio::runtime) fn send_next(
        &self,
        send: impl FnOnce(ExecutionFrame) -> Result<(), StudioError>,
    ) -> Result<DeliveryStep, StudioError> {
        let mut state = self
            .projection
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if !window.claimed {
            return Err(if window.closing {
                cancelled()
            } else {
                StudioError::invalid_argument("Execution stream has not been claimed")
            });
        }
        if window.terminal_sent {
            return Ok(DeliveryStep::Terminal);
        }
        if let Some(frame) = &window.terminal {
            send(frame.clone())?;
            window.terminal_sent = true;
            return Ok(DeliveryStep::Terminal);
        }
        if window.unacked.len() == 2 {
            return Ok(DeliveryStep::Waiting);
        }
        let Some(data) = window.pending.front() else {
            return Ok(DeliveryStep::Waiting);
        };
        send(data.frame.clone())?;
        for fact in data.snapshot.facts.iter().chain(&data.extra) {
            if let Some(locator) = state.locators.get_mut(&(fact.entry, fact.revision)) {
                locator.exposed_from = Some(
                    locator
                        .exposed_from
                        .map_or(data.snapshot.stamp.revision, |old| {
                            old.min(data.snapshot.stamp.revision)
                        }),
                );
            }
        }
        if let Some(data) = window.pending.pop_front() {
            window.pending_bytes -= data.bytes;
            window.sent = data.sequence;
            window.unacked.push_back(data);
        }
        Ok(DeliveryStep::Data)
    }

    pub(in crate::studio::runtime) fn ack(&self, sequence: u64) -> Result<(), StudioError> {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if window.closing {
            return Err(cancelled());
        }
        if sequence == 0 || sequence <= window.acked {
            return Ok(());
        }
        if sequence > window.sent {
            return Err(StudioError::new(
                StudioErrorCode::Protocol,
                "Execution ACK exceeds the sent prefix",
                false,
            ));
        }
        window.acked = sequence;
        while window
            .unacked
            .front()
            .is_some_and(|data| data.sequence <= sequence)
        {
            window.unacked.pop_front();
        }
        drop(window);
        self.changed.notify_waiters();
        Ok(())
    }

    pub(in crate::studio::runtime) async fn ready(&self) {
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            {
                let window = self
                    .window
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                if window.terminal.is_some()
                    || window.terminal_sent
                    || (!window.pending.is_empty() && window.unacked.len() < 2)
                {
                    return;
                }
            }
            changed.await;
        }
    }

    pub(in crate::studio::runtime) fn request_close(&self) {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        window.closing = true;
        if window.terminal.is_none() && !window.terminal_sent {
            window.terminal = Some(ExecutionFrame::Closed {
                identity: self.identity.clone(),
                reason: FeedClosedReason::Requested,
            });
        }
        drop(window);
        self.changed.notify_waiters();
    }

    pub(in crate::studio::runtime) fn close(&self) -> FeedCloseReport {
        self.request_close();
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        window.pending.clear();
        window.pending_bytes = 0;
        window.unacked.clear();
        FeedCloseReport {
            feed_id: self.identity.feed_id.clone(),
            outcome: FeedCloseOutcome::Clean,
        }
    }
}

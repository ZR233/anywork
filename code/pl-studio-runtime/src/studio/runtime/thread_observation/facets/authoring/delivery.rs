use super::*;
use pl_protocol::studio::{FeedCloseOutcome, FeedCloseReport};
use pl_protocol::thread_facets::authoring::{AuthoringChange, AuthoringEvent, AuthoringFrame};
use pl_protocol::thread_facets::identity::{ThreadFeedIdentity, ThreadObservationMode};
use std::collections::VecDeque;

const PENDING_FRAMES: usize = 64;
const PENDING_BYTES: usize = 8 * 1024 * 1024;
const DATA_BYTES: usize = 256 * 1024;
struct Data {
    frame: AuthoringFrame,
    snapshot: Arc<AuthoringSnapshot>,
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
    terminal: Option<AuthoringFrame>,
    terminal_sent: bool,
    last_revision: Option<u64>,
}
pub(in crate::studio::runtime) struct AuthoringDelivery {
    identity: ThreadFeedIdentity,
    projection: Arc<AuthoringProjection>,
    window: Mutex<Window>,
    changed: Notify,
}
pub enum DeliveryStep {
    Waiting,
    Data,
    Terminal,
}

impl AuthoringProjection {
    pub(in crate::studio::runtime) fn subscribe(
        self: &Arc<Self>,
        mode: ThreadObservationMode,
    ) -> Result<Arc<AuthoringDelivery>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        ensure_open(&state)?;
        if let Some(error) = &state.capture_error {
            return Err(error.wire.clone());
        }
        let listener = Arc::new(AuthoringDelivery {
            identity: ThreadFeedIdentity {
                feed_id: crate::studio::new_id("authoring-feed"),
                runtime_epoch: self.epoch.clone(),
                incarnation: self.incarnation,
                facet: ThreadFacet::Authoring,
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
        // The initial capture and all subsequent committed captures share this publication guard.
        state
            .listeners
            .retain(|listener| listener.strong_count() != 0);
        state.listeners.push(Arc::downgrade(&listener));
        if let Some(current) = &state.current {
            listener.publish(current.clone(), None);
        }
        Ok(listener)
    }
}
impl AuthoringDelivery {
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
                "Authoring stream was already claimed",
                false,
            ));
        }
        window.claimed = true;
        Ok(())
    }
    pub(super) fn publish(
        &self,
        snapshot: Arc<AuthoringSnapshot>,
        change: Option<(u64, AuthoringChange)>,
    ) {
        let mut window = self
            .window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if window.closing || window.terminal.is_some() {
            return;
        }
        let event = match window.last_revision {
            None => AuthoringEvent::Baseline {
                identity: self.identity.clone(),
                stamp: snapshot.stamp.clone(),
                value: snapshot.value.clone(),
            },
            Some(previous) => match change {
                Some((base_revision, value)) if previous == base_revision => {
                    AuthoringEvent::Change {
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
        let frame = AuthoringFrame::Data {
            delivery_sequence: sequence,
            event,
        };
        let frame_bytes = match crate::studio::runtime::read_budget::json_bytes(&frame) {
            Ok(bytes) if bytes <= DATA_BYTES => bytes,
            Ok(_) => {
                self.resync(&mut window, ResyncReason::ReliableQueueFull);
                return;
            }
            Err(error) => {
                window.terminal = Some(AuthoringFrame::Failure {
                    identity: self.identity.clone(),
                    error,
                });
                self.changed.notify_waiters();
                return;
            }
        };
        let Some(bytes) = snapshot.source_bytes.checked_add(frame_bytes) else {
            self.resync(&mut window, ResyncReason::ReliableQueueFull);
            return;
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
            window.terminal = Some(AuthoringFrame::Failure {
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
            bytes,
            sequence,
        });
        drop(window);
        self.changed.notify_waiters();
    }
    fn resync(&self, window: &mut Window, reason: ResyncReason) {
        window.terminal = Some(AuthoringFrame::ResyncRequired {
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
                Terminal::Failure(error) => AuthoringFrame::Failure {
                    identity: self.identity.clone(),
                    error,
                },
                Terminal::Closed(reason) => AuthoringFrame::Closed {
                    identity: self.identity.clone(),
                    reason,
                },
            });
        }
        drop(window);
        self.changed.notify_waiters();
    }
    /// Actual synchronous send is the sole ref-exposure edge. No transport borrows a frame into
    /// another queue, and neither a full window nor its final control terminal awaits capacity.
    pub(in crate::studio::runtime) fn send_next(
        &self,
        send: impl FnOnce(AuthoringFrame) -> Result<(), StudioError>,
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
                StudioError::invalid_argument("Authoring stream has not been claimed")
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
        for fact in &data.snapshot.facts {
            if let Some(locator) = state.locators.get_mut(&(fact.entry, fact.revision)) {
                locator.exposed_from = Some(
                    locator
                        .exposed_from
                        .map_or(data.snapshot.stamp.revision, |first| {
                            first.min(data.snapshot.stamp.revision)
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
                "Authoring ACK exceeds the sent prefix",
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
            window.terminal = Some(AuthoringFrame::Closed {
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

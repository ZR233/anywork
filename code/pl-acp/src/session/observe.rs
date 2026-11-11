//! 只限制待交付窗口；消费后立即归还额度。失效不影响业务协议。
use std::sync::Arc;

use tokio::sync::{OwnedSemaphorePermit, Semaphore, mpsc, watch};

use super::{Completed, Error, PermissionId, schema::*};

const EVENTS: usize = 64;
const BYTES: usize = 8 * 1024 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Gap {
    WindowExceeded,
    Disconnected,
    Encoding,
}

#[derive(Debug, Clone)]
pub enum Event {
    Initialized(Box<AgentCapabilities>),
    Update(SessionNotification),
    Ready(NewSessionResponse),
    Failed(Error),
    Permission {
        id: PermissionId,
        request: RequestPermissionRequest,
    },
    Configured(SetSessionConfigOptionResponse),
    ModeSet(SessionModeId),
    Completed(Completed),
    Gap(Gap),
}

struct Envelope {
    event: Event,
    _bytes: OwnedSemaphorePermit,
}

pub struct Observer {
    receiver: mpsc::Receiver<Envelope>,
    gap: watch::Receiver<Option<Gap>>,
    ended: bool,
}

impl Observer {
    /// Gap 恰好交付一次并结束此观察；丢弃尚未交付窗口，不伪装成完整历史。
    pub async fn recv(&mut self) -> Option<Event> {
        if self.ended {
            return None;
        }
        loop {
            if let Some(gap) = *self.gap.borrow_and_update() {
                self.ended = true;
                self.receiver.close();
                while self.receiver.try_recv().is_ok() {}
                return Some(Event::Gap(gap));
            }
            tokio::select! {
                biased;
                result = self.gap.changed() => {
                    if result.is_err() { return self.receiver.recv().await.map(|envelope| envelope.event); }
                }
                envelope = self.receiver.recv() => return envelope.map(|envelope| envelope.event),
            }
        }
    }
}

pub(super) struct Sender {
    sender: Option<mpsc::Sender<Envelope>>,
    bytes: Arc<Semaphore>,
    gap: watch::Sender<Option<Gap>>,
}

pub(super) fn channel() -> (Sender, Observer) {
    let (sender, receiver) = mpsc::channel(EVENTS);
    let (gap, observed_gap) = watch::channel(None);
    (
        Sender {
            sender: Some(sender),
            bytes: Arc::new(Semaphore::new(BYTES)),
            gap,
        },
        Observer {
            receiver,
            gap: observed_gap,
            ended: false,
        },
    )
}

impl Sender {
    /// The driver must release pending permissions even if the receiver disappears while
    /// the protocol is otherwise quiet. This future owns no state lock.
    pub(super) fn invalidated(&self) -> impl Future<Output = ()> + Send + 'static {
        let sender = self.sender.clone();
        let mut gap = self.gap.subscribe();
        async move {
            let Some(sender) = sender else {
                return;
            };
            tokio::select! {
                () = sender.closed() => {}
                () = async {
                    loop {
                        if gap.borrow_and_update().is_some() { break; }
                        if gap.changed().await.is_err() { break; }
                    }
                } => {}
            }
        }
    }

    pub(super) fn gap(&self) -> Option<Gap> {
        (*self.gap.borrow()).or_else(|| {
            self.sender
                .as_ref()
                .filter(|sender| sender.is_closed())
                .map(|_| Gap::Disconnected)
        })
    }

    pub(super) fn send(
        &mut self,
        event: Event,
        size: Result<usize, agent_client_protocol::Error>,
    ) -> bool {
        let Some(sender) = &self.sender else {
            return false;
        };
        let result = (|| {
            if sender.is_closed() {
                return Err(Gap::Disconnected);
            }
            // Include envelope and variant overhead, in addition to the SDK's complete JSON payload.
            let size = size
                .map_err(|_| Gap::Encoding)?
                .saturating_add(std::mem::size_of::<Envelope>());
            if size > BYTES {
                return Err(Gap::WindowExceeded);
            }
            let permit = self
                .bytes
                .clone()
                .try_acquire_many_owned(size as u32)
                .map_err(|_| Gap::WindowExceeded)?;
            sender
                .try_send(Envelope {
                    event,
                    _bytes: permit,
                })
                .map_err(|error| match error {
                    mpsc::error::TrySendError::Full(_) => Gap::WindowExceeded,
                    mpsc::error::TrySendError::Closed(_) => Gap::Disconnected,
                })
        })();
        if let Err(gap) = result {
            self.gap.send_replace(Some(gap));
            self.sender = None;
            return false;
        }
        true
    }
}

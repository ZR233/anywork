use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;

use futures::{FutureExt, Stream, StreamExt, stream};
use pl_protocol::studio::{AcpBusinessFailure, AcpSessionEvent, AcpSessionFrame};
use pl_studio_runtime::AcpSessionOpen;
use tokio::sync::Mutex;
use tokio_util::sync::CancellationToken;

use crate::api::studio::convert::acp_business as convert;
use crate::api::studio::types::{BridgeAcpBusinessError, BridgeAcpSessionFrame, BridgeError};

#[cfg(all(test, target_os = "linux"))]
#[path = "feed_real_transport.rs"]
mod real_transport;

type Events = Pin<Box<dyn Stream<Item = AcpSessionEvent> + Send>>;
type Completion = Pin<Box<dyn Future<Output = Result<(), AcpBusinessFailure>> + Send>>;

/// Owns only an observation and a publication waiter, never the business session.
#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeAcpSessionObservation {
    inner: Arc<Observation>,
}
#[flutter_rust_bridge::frb(ignore)]
struct Observation {
    closing: CancellationToken,
    source: Mutex<Option<Source>>,
}
#[flutter_rust_bridge::frb(ignore)]
struct Source {
    accepted: Option<AcpSessionFrame>,
    events: Events,
    events_ended: bool,
    prefer_completion: bool,
    completion: Option<Completion>,
}
impl Source {
    fn new(opened: AcpSessionOpen) -> Self {
        let has_observation = opened.observation.is_some();
        let events: Events = match opened.observation {
            Some(observation) => {
                Box::pin(stream::unfold(observation, |mut observation| async move {
                    observation.recv().await.map(|event| (event, observation))
                }))
            }
            None => Box::pin(stream::empty()),
        };
        Self {
            accepted: Some(AcpSessionFrame::Accepted {
                target: opened.target,
                has_observation,
            }),
            events,
            events_ended: false,
            prefer_completion: false,
            completion: Some(Box::pin(async move { opened.completion.wait().await })),
        }
    }
    async fn next(&mut self) -> Option<AcpSessionFrame> {
        if let Some(accepted) = self.accepted.take() {
            return Some(accepted);
        }
        // One buffered event may precede publication; subsequent pulls always
        // poll the original completion first, even under continuous updates.
        if self.prefer_completion
            && let Some(result) = self
                .completion
                .as_mut()
                .and_then(|completion| completion.as_mut().now_or_never())
        {
            self.completion = None;
            return Some(AcpSessionFrame::Settled { result });
        }
        loop {
            tokio::select! {
                biased;
                event = self.events.next(), if !self.events_ended => match event {
                    Some(event) => {
                        self.prefer_completion = true;
                        return Some(AcpSessionFrame::Event { event: Box::new(event) });
                    },
                    None => self.events_ended = true,
                },
                result = async {
                    match self.completion.as_mut() {
                        Some(completion) => completion.await,
                        None => std::future::pending().await,
                    }
                }, if self.completion.is_some() => {
                    self.completion = None;
                    return Some(AcpSessionFrame::Settled { result });
                },
                else => return None,
            }
        }
    }
}
impl BridgeAcpSessionObservation {
    #[flutter_rust_bridge::frb(ignore)]
    pub(super) fn new(opened: AcpSessionOpen, closing: CancellationToken) -> Self {
        Self {
            inner: Arc::new(Observation {
                closing,
                source: Mutex::new(Some(Source::new(opened))),
            }),
        }
    }
    /// Pulls the original window; a concurrent read is Busy, not a second consumer.
    pub async fn next(&self) -> Result<Option<BridgeAcpSessionFrame>, BridgeAcpBusinessError> {
        let mut source = self.inner.source.try_lock().map_err(|_| {
            BridgeAcpBusinessError::Runtime(BridgeError::from(
                pl_protocol::studio::StudioError::new(
                    pl_protocol::studio::StudioErrorCode::Busy,
                    "An ACP observation next is already in flight",
                    true,
                ),
            ))
        })?;
        if self.inner.closing.is_cancelled() {
            *source = None;
            return Ok(None);
        }
        let next = match source.as_mut() {
            None => return Ok(None),
            Some(source) => tokio::select! {
                biased;
                () = self.inner.closing.cancelled() => None,
                next = source.next() => next,
            },
        };
        match next {
            None => {
                *source = None;
                Ok(None)
            }
            Some(frame) => match convert::frame(frame) {
                Ok(frame) => Ok(Some(frame)),
                // Do not silently skip an unknown official variant and continue as if complete.
                Err(error) => {
                    *source = None;
                    Err(error)
                }
            },
        }
    }
    /// Releases observation only. It does not cancel a prompt or close a session.
    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.inner.closing.cancel();
    }

    /// Joins the in-flight local read and drops the exact original observer/waiter.
    pub async fn close(&self) -> Result<(), BridgeAcpBusinessError> {
        self.request_close();
        *self.inner.source.lock().await = None;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::studio::types::{BridgeAcpSettlement, BridgeErrorCode};

    fn observation(source: Source) -> BridgeAcpSessionObservation {
        BridgeAcpSessionObservation {
            inner: Arc::new(Observation {
                closing: CancellationToken::new(),
                source: Mutex::new(Some(source)),
            }),
        }
    }

    #[tokio::test]
    async fn resident_pull_has_accepted_then_exactly_one_original_settlement() {
        let observation = observation(Source {
            accepted: Some(AcpSessionFrame::Accepted {
                target: pl_protocol::studio::AcpSessionTarget {
                    session_id: "product-session".into(),
                    agent_id: "product-agent".into(),
                    thread_id: "product-thread".into(),
                    instance: 41,
                },
                has_observation: false,
            }),
            events: Box::pin(stream::empty()),
            events_ended: false,
            prefer_completion: false,
            completion: Some(Box::pin(async { Ok(()) })),
        });
        let Some(BridgeAcpSessionFrame::Accepted {
            target,
            has_observation,
        }) = observation.next().await.unwrap()
        else {
            panic!("missing acceptance");
        };
        assert_eq!(target.session_id, "product-session");
        assert_eq!(target.agent_id, "product-agent");
        assert_eq!(target.thread_id, "product-thread");
        assert_eq!(target.instance, 41);
        assert!(!has_observation);
        assert_eq!(
            observation.next().await.unwrap(),
            Some(BridgeAcpSessionFrame::Settled {
                result: BridgeAcpSettlement::Succeeded,
            })
        );
        assert!(observation.next().await.unwrap().is_none());
        observation.close().await.unwrap();
    }

    #[tokio::test]
    async fn only_one_next_is_inflight_and_local_close_releases_it() {
        let entered = Arc::new(tokio::sync::Notify::new());
        let notify = entered.clone();
        let observation = Arc::new(observation(Source {
            accepted: None,
            events: Box::pin(stream::once(async move {
                notify.notify_one();
                std::future::pending::<AcpSessionEvent>().await
            })),
            events_ended: false,
            prefer_completion: false,
            completion: Some(Box::pin(std::future::pending())),
        }));
        let reader = observation.clone();
        let next = tokio::spawn(async move { reader.next().await });
        entered.notified().await;
        assert!(matches!(
            observation.next().await,
            Err(BridgeAcpBusinessError::Runtime(BridgeError {
                code: BridgeErrorCode::Busy,
                ..
            }))
        ));
        observation.request_close();
        observation.close().await.unwrap();
        assert!(next.await.unwrap().unwrap().is_none());
        assert!(observation.inner.source.lock().await.is_none());
        assert!(observation.next().await.unwrap().is_none());
    }

    #[tokio::test]
    async fn settled_is_not_starved_by_a_continuously_ready_observation() {
        let observation = observation(Source {
            accepted: None,
            events: Box::pin(stream::repeat(AcpSessionEvent::ModeSet {
                mode_id: "peer-mode".into(),
            })),
            events_ended: false,
            prefer_completion: false,
            completion: Some(Box::pin(async { Ok(()) })),
        });
        assert!(matches!(
            observation.next().await.unwrap(),
            Some(BridgeAcpSessionFrame::Event { .. })
        ));
        assert_eq!(
            observation.next().await.unwrap(),
            Some(BridgeAcpSessionFrame::Settled {
                result: BridgeAcpSettlement::Succeeded,
            })
        );
        assert!(matches!(
            observation.next().await.unwrap(),
            Some(BridgeAcpSessionFrame::Event { .. })
        ));
        observation.close().await.unwrap();
    }
}

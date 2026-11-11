//! Scheduling only: one accepted frame, one original completion, one original observer.

use std::future::Future;
use std::pin::Pin;

use futures::{FutureExt, Stream, StreamExt, stream};
use pl_protocol::studio::{AcpBusinessFailure, AcpSessionEvent, AcpSessionFrame};
use pl_studio_runtime::AcpSessionOpen;

type Events = Pin<Box<dyn Stream<Item = AcpSessionEvent> + Send>>;
type Completion = Pin<Box<dyn Future<Output = Result<(), AcpBusinessFailure>> + Send>>;

pub(super) struct OpenFrames {
    accepted: Option<AcpSessionFrame>,
    events: Events,
    events_ended: bool,
    prefer_completion: bool,
    completion: Option<Completion>,
}

impl OpenFrames {
    pub(super) fn new(open: AcpSessionOpen) -> Self {
        let has_observation = open.observation.is_some();
        let events: Events = match open.observation {
            Some(observation) => {
                Box::pin(stream::unfold(observation, |mut observation| async move {
                    observation.recv().await.map(|event| (event, observation))
                }))
            }
            None => Box::pin(stream::empty()),
        };
        Self {
            accepted: Some(AcpSessionFrame::Accepted {
                target: open.target,
                has_observation,
            }),
            events,
            events_ended: false,
            prefer_completion: false,
            completion: Some(Box::pin(async move { open.completion.wait().await })),
        }
    }

    pub(super) async fn next(&mut self) -> Option<AcpSessionFrame> {
        if let Some(accepted) = self.accepted.take() {
            return Some(accepted);
        }
        // Give one already-buffered update its original early delivery, then poll
        // publication before any further event. A perpetually ready observer must
        // not starve Settled. Reborrowing the pinned future does not cancel it.
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
            // The unfold stream retains an in-flight recv across select cancellation.
            // In particular, a Ready consumed by recv while it awaits publication is not lost.
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_protocol::studio::{AcpObservationGap, AcpSessionTarget, SessionNotification};

    fn source(events: Events, completion: Completion, has_observation: bool) -> OpenFrames {
        OpenFrames {
            accepted: Some(AcpSessionFrame::Accepted {
                target: AcpSessionTarget {
                    session_id: "product-session".into(),
                    agent_id: "product-agent".into(),
                    thread_id: "product-thread".into(),
                    instance: 41,
                },
                has_observation,
            }),
            events,
            events_ended: false,
            prefer_completion: false,
            completion: Some(completion),
        }
    }

    #[tokio::test]
    async fn buffered_load_update_precedes_ready_and_settled_without_replay() {
        // These are transport scheduling inputs, not a replacement SDK/peer.
        let update: SessionNotification = serde_json::from_value(serde_json::json!({
            "sessionId": "remote-session",
            "update": {
                "sessionUpdate": "agent_message_chunk",
                "content": {"type": "text", "text": "load replay"}
            }
        }))
        .unwrap();
        let events = stream::iter([
            AcpSessionEvent::Update { update },
            AcpSessionEvent::Ready {
                response: serde_json::from_value(serde_json::json!({
                    "sessionId": "remote-session"
                }))
                .unwrap(),
            },
        ]);
        let mut frames = source(Box::pin(events), Box::pin(async { Ok(()) }), true);
        let Some(AcpSessionFrame::Accepted {
            target,
            has_observation,
        }) = frames.next().await
        else {
            panic!("Accepted must be first");
        };
        assert!(has_observation);
        assert_eq!(target.session_id, "product-session");
        assert_eq!(target.agent_id, "product-agent");
        assert_eq!(target.thread_id, "product-thread");
        assert_eq!(target.instance, 41);
        assert!(matches!(
            frames.next().await,
            Some(AcpSessionFrame::Event { event })
                if matches!(event.as_ref(), AcpSessionEvent::Update { .. })
        ));
        assert!(matches!(
            frames.next().await,
            Some(AcpSessionFrame::Settled { result: Ok(()) })
        ));
        assert!(matches!(
            frames.next().await,
            Some(AcpSessionFrame::Event { event })
                if matches!(event.as_ref(), AcpSessionEvent::Ready { .. })
        ));
        assert!(frames.next().await.is_none());
    }

    #[tokio::test]
    async fn resident_only_has_accepted_and_one_settled() {
        let mut frames = source(Box::pin(stream::empty()), Box::pin(async { Ok(()) }), false);
        assert!(matches!(
            frames.next().await,
            Some(AcpSessionFrame::Accepted {
                has_observation: false,
                ..
            })
        ));
        assert!(matches!(
            frames.next().await,
            Some(AcpSessionFrame::Settled { result: Ok(()) })
        ));
        assert!(frames.next().await.is_none());
    }

    #[tokio::test]
    async fn gap_ends_events_but_keeps_pending_publication_result() {
        let (send, recv) = tokio::sync::oneshot::channel();
        let mut frames = source(
            Box::pin(stream::iter([AcpSessionEvent::Gap {
                gap: AcpObservationGap::WindowExceeded,
            }])),
            Box::pin(async { recv.await.unwrap() }),
            true,
        );
        let _ = frames.next().await;
        assert!(matches!(
            frames.next().await,
            Some(AcpSessionFrame::Event { event })
                if matches!(event.as_ref(), AcpSessionEvent::Gap { .. })
        ));
        assert!(
            tokio::time::timeout(std::time::Duration::from_millis(5), frames.next())
                .await
                .is_err()
        );
        send.send(Ok(())).unwrap();
        assert!(matches!(
            frames.next().await,
            Some(AcpSessionFrame::Settled { result: Ok(()) })
        ));
        assert!(frames.next().await.is_none());
    }

    #[tokio::test]
    async fn settled_does_not_discard_an_inflight_observer_receive() {
        use std::sync::{
            Arc,
            atomic::{AtomicUsize, Ordering},
        };
        let receives = Arc::new(AtomicUsize::new(0));
        let count = receives.clone();
        let (event_send, event_recv) = tokio::sync::oneshot::channel();
        let events = stream::unfold(Some(event_recv), move |receiver| {
            let count = count.clone();
            async move {
                let receiver = receiver?;
                count.fetch_add(1, Ordering::Relaxed);
                let event = receiver.await.unwrap();
                Some((event, None))
            }
        });
        let (settle_send, settle_recv) = tokio::sync::oneshot::channel();
        let mut frames = source(
            Box::pin(events),
            Box::pin(async { settle_recv.await.unwrap() }),
            true,
        );
        let _ = frames.next().await;
        assert!(
            tokio::time::timeout(std::time::Duration::from_millis(5), frames.next())
                .await
                .is_err()
        );
        settle_send.send(Ok(())).unwrap();
        assert!(matches!(
            frames.next().await,
            Some(AcpSessionFrame::Settled { result: Ok(()) })
        ));
        event_send
            .send(AcpSessionEvent::ModeSet {
                mode_id: "mode-from-peer".into(),
            })
            .unwrap();
        let Some(AcpSessionFrame::Event { event }) = frames.next().await else {
            panic!("original receive was lost");
        };
        let AcpSessionEvent::ModeSet { mode_id } = *event else {
            panic!("original receive changed event kind");
        };
        assert_eq!(mode_id.to_string(), "mode-from-peer");
        assert_eq!(receives.load(Ordering::Relaxed), 1);
        assert!(frames.next().await.is_none());
    }

    #[tokio::test]
    async fn settled_is_not_starved_by_a_continuously_ready_observation() {
        let mut frames = source(
            Box::pin(stream::repeat(AcpSessionEvent::ModeSet {
                mode_id: "peer-mode".into(),
            })),
            Box::pin(async { Ok(()) }),
            true,
        );
        assert!(matches!(
            frames.next().await,
            Some(AcpSessionFrame::Accepted { .. })
        ));
        assert!(matches!(
            frames.next().await,
            Some(AcpSessionFrame::Event { .. })
        ));
        assert!(matches!(
            frames.next().await,
            Some(AcpSessionFrame::Settled { result: Ok(()) })
        ));
        assert!(matches!(
            frames.next().await,
            Some(AcpSessionFrame::Event { .. })
        ));
    }
}

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

#[cfg(all(test, target_os = "linux"))]
mod real_transport {
    //! The real Runtime observer/completion enter the production FRB handle directly.
    use std::panic::AssertUnwindSafe;
    use std::path::PathBuf;
    use std::time::Duration;

    use anyhow::{Context, Result, ensure};
    use pl_protocol::studio::*;
    use tokio::time::{sleep, timeout};

    use super::*;
    use crate::api::studio::types::{
        BridgeAcpObservationGap, BridgeAcpRunId, BridgeAcpSessionEvent, BridgeAcpSettlement,
    };

    use acp_transport_fixture::AcpTransportFixture as Fixture;

    async fn finish(fixture: &Fixture) -> Result<()> {
        let release = std::fs::write(fixture.home.path().join("release"), "");
        let stopped = fixture.runtime.shutdown_runtime().await;
        for name in ["pid", "child"] {
            if fixture.home.path().join(name).exists() {
                let pid = fixture.pid(name)?;
                ensure!(
                    !PathBuf::from(format!("/proc/{pid}")).exists(),
                    "{name} {pid} leaked"
                );
            }
        }
        release?;
        ensure!(stopped?.state.is_stopped());
        Ok(())
    }

    async fn frame(handle: &BridgeAcpSessionObservation) -> Result<BridgeAcpSessionFrame> {
        handle
            .next()
            .await?
            .context("real FRB observation ended early")
    }

    #[tokio::test]
    async fn real_peer_frb_close_observation_does_not_cancel_original_prompt() -> Result<()> {
        let fixture = Fixture::new("prompt-hold").await?;
        let outcome = AssertUnwindSafe(timeout(Duration::from_secs(30), async {
            let opened = fixture.open().await?;
            let target = opened.target.clone();
            let handle = Arc::new(BridgeAcpSessionObservation::new(
                opened,
                CancellationToken::new(),
            ));
            let BridgeAcpSessionFrame::Accepted {
                target: bridged,
                has_observation: true,
            } = frame(&handle).await?
            else {
                anyhow::bail!("real FRB acceptance missing");
            };
            ensure!(bridged == target.clone().into());
            let (mut initialized, mut ready, mut settled) = (0, 0, 0);
            while ready == 0 || settled == 0 {
                match frame(&handle).await? {
                    BridgeAcpSessionFrame::Settled {
                        result: BridgeAcpSettlement::Succeeded,
                    } => settled += 1,
                    BridgeAcpSessionFrame::Event { event }
                        if matches!(*event, BridgeAcpSessionEvent::Initialized { .. }) =>
                    {
                        ensure!(initialized == 0 && ready == 0);
                        initialized += 1;
                    }
                    BridgeAcpSessionFrame::Event { event }
                        if matches!(*event, BridgeAcpSessionEvent::Ready { .. }) =>
                    {
                        ensure!(initialized == 1);
                        ready += 1
                    }
                    other => anyhow::bail!("unexpected real FRB publication: {other:?}"),
                }
            }
            ensure!(initialized == 1 && ready == 1 && settled == 1);
            let run = fixture
                .runtime
                .prompt_acp_session(
                    target.clone(),
                    vec![acp_schema::ContentBlock::Text(
                        acp_schema::TextContent::new("actual FRB run"),
                    )],
                )
                .await?;
            timeout(Duration::from_secs(10), async {
                while !fixture.home.path().join("prompting").exists() {
                    sleep(Duration::from_millis(10)).await;
                }
            })
            .await?;
            let active =
                convert::snapshot(fixture.runtime.acp_session_snapshot(target.clone()).await?)?;
            let bridged_run: BridgeAcpRunId = run.into();
            ensure!(active.active_run == Some(bridged_run));
            ensure!(active.target == bridged);

            // Close the actual opaque handle with a real pending recv, not a fake Source.
            let next = handle.next();
            tokio::pin!(next);
            ensure!(futures::poll!(next.as_mut()).is_pending());
            // Join in place: failure/timeout drops both futures, never a detached reader.
            let (next, closed) = tokio::join!(next, handle.close());
            closed?;
            ensure!(next?.is_none());
            ensure!(handle.next().await?.is_none());
            ensure!(handle.inner.source.lock().await.is_none());
            let held = fixture.runtime.acp_session_snapshot(target.clone()).await?;
            ensure!(held.ready && !held.closing && held.active_run == Some(run));
            std::fs::write(fixture.home.path().join("release"), "")?;
            let completed = loop {
                let snapshot = fixture.runtime.acp_session_snapshot(target.clone()).await?;
                if let Some(completed) = snapshot.last_completed {
                    break completed;
                }
                sleep(Duration::from_millis(10)).await;
            };
            ensure!(completed.run == run && completed.result.is_ok());
            ensure!(completed.summary == "actual answer");
            let close = convert::close(fixture.runtime.close_acp_session(target.clone()).await?)?;
            ensure!(
                close.local_complete && !close.sdk_finished && !close.cleanup_timed_out,
                "{close:?}"
            );
            ensure!(
                close.owner_failures.is_empty()
                    && close.worker_error.is_none()
                    && close.driver_error.is_none()
            );
            ensure!(close.unfinished_prompt.is_none() && !close.unfinished_controls);
            ensure!(close.last_completed.as_ref().map(|done| done.run) == Some(bridged_run));
            // Closing a member retains the shared account process; finish verifies its final exit.
            ensure!(PathBuf::from(format!("/proc/{}", fixture.pid("pid")?)).exists());
            // Inspect after the peer was released and the member driver joined.
            let methods = std::fs::read_to_string(fixture.home.path().join("calls"))?;
            ensure!(
                methods
                    .lines()
                    .filter(|method| *method == "session/prompt")
                    .count()
                    == 1
            );
            ensure!(!methods.lines().any(|method| method == "session/cancel"));
            let stale = fixture
                .runtime
                .interrupt_acp_session(target, run)
                .await
                .unwrap_err();
            ensure!(matches!(
                stale.kind,
                AcpBusinessFailureKind::Stale | AcpBusinessFailureKind::Closed
            ));
            Ok::<_, anyhow::Error>(())
        }))
        .catch_unwind()
        .await;
        finish(&fixture).await?;
        match outcome {
            Ok(result) => result?,
            Err(panic) => std::panic::resume_unwind(panic),
        }
    }

    #[tokio::test]
    async fn real_peer_frb_sdk_gap_keeps_original_product_completion() -> Result<()> {
        let fixture = Fixture::new("gap").await?;
        let outcome = AssertUnwindSafe(timeout(Duration::from_secs(30), async {
        let opened = fixture.open_intent(AcpOpenIntent::Load("remote-one".into())).await?;
        let target = opened.target.clone();
        // Deliberately leave the ORIGINAL observation unread while the real SDK fills
        // its window. Runtime publication still completes independently of this reader.
        loop {
            match fixture.runtime.acp_session_snapshot(target.clone()).await {
                Ok(snapshot) if snapshot.ready => break,
                Ok(_) => {}
                Err(error) if error.kind == AcpBusinessFailureKind::NotReady => {}
                Err(error) => return Err(error.into()),
            }
            sleep(Duration::from_millis(10)).await;
        }
        let handle = BridgeAcpSessionObservation::new(opened, CancellationToken::new());
        ensure!(matches!(frame(&handle).await?, BridgeAcpSessionFrame::Accepted { has_observation: true, .. }));
        ensure!(matches!(frame(&handle).await?, BridgeAcpSessionFrame::Event { event }
            if matches!(*event, BridgeAcpSessionEvent::Gap { gap: BridgeAcpObservationGap::WindowExceeded })));
        ensure!(frame(&handle).await? == BridgeAcpSessionFrame::Settled { result: BridgeAcpSettlement::Succeeded });
        ensure!(handle.next().await?.is_none());
        handle.close().await?;
        let snapshot = convert::snapshot(fixture.runtime.acp_session_snapshot(target.clone()).await?)?;
        ensure!(snapshot.ready && snapshot.acp_session_id.as_ref().map(|id| id.value.as_str()) == Some("remote-one"));
        ensure!(snapshot.observation_gap == Some(BridgeAcpObservationGap::WindowExceeded));
        let close = fixture.runtime.close_acp_session(target).await?;
        ensure!(close.local_complete && !close.sdk_finished && close.owner_failures.is_empty(), "{close:?}");
        Ok::<_, anyhow::Error>(())
    })).catch_unwind().await;
        finish(&fixture).await?;
        match outcome {
            Ok(result) => result?,
            Err(panic) => std::panic::resume_unwind(panic),
        }
    }

    use crate::test_fixture_acp_transport_fixture as acp_transport_fixture;
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

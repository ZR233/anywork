//! The real Runtime observer/completion enter the production FRB handle directly.
use std::panic::AssertUnwindSafe;
use std::path::PathBuf;
use std::time::Duration;

use anyhow::{Context, Result, ensure};
use pl_protocol::studio::*;
use pl_studio_runtime as studio_runtime;
use tokio::time::{sleep, timeout};

use super::*;
use crate::api::studio::types::{
    BridgeAcpObservationGap, BridgeAcpRunId, BridgeAcpSessionEvent, BridgeAcpSettlement,
};

#[expect(
    dead_code,
    reason = "Shared fixture also serves direct runtime consumers"
)]
#[path = "../../../../../../../pl-studio-runtime/tests/support/acp_transport_fixture.rs"]
mod acp_transport_fixture;
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
            close.local_complete && close.sdk_finished && !close.cleanup_timed_out,
            "{close:?}"
        );
        ensure!(
            close.owner_failures.is_empty()
                && close.worker_error.is_none()
                && close.driver_error.is_none()
        );
        ensure!(close.unfinished_prompt.is_none() && !close.unfinished_controls);
        ensure!(close.last_completed.as_ref().map(|done| done.run) == Some(bridged_run));
        ensure!(!PathBuf::from(format!("/proc/{}", fixture.pid("pid")?)).exists());
        // Inspect only after the peer was released and the real owner/worker joined.
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
        ensure!(close.local_complete && close.sdk_finished && close.owner_failures.is_empty(), "{close:?}");
        Ok::<_, anyhow::Error>(())
    })).catch_unwind().await;
    finish(&fixture).await?;
    match outcome {
        Ok(result) => result?,
        Err(panic) => std::panic::resume_unwind(panic),
    }
}

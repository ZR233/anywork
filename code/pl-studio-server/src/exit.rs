//! HTTP owners are joined before the runtime's one finalizer; a timeout retains actual handles.
use std::time::{Duration, Instant};

use axum::Router;
use futures::FutureExt;
use pl_protocol::studio::{StudioError, StudioShutdownIssue};
use tokio::net::TcpListener;

use crate::AppState;

pub(crate) async fn run(listener: TcpListener, app: Router, state: AppState) -> anyhow::Result<()> {
    let shutdown = state.shutdown.clone();
    let mut server = tokio::spawn(async move {
        axum::serve(listener, app).with_graceful_shutdown(shutdown.cancelled_owned()).await
    });
    let mut server_result = None;
    tokio::select! { biased;
        result = &mut server => { server_result = Some(result); }
        () = crate::wait_for_signal() => {}
    }
    // One first deadline, shared by HTTP drains and the existing runtime exit orchestration.
    let deadline = Instant::now() + Duration::from_secs(30);
    state.shutdown.cancel();
    state.templates.seal();
    let force = crate::wait_for_signal();
    tokio::pin!(force);
    let report = {
        let cleanup = async {
            // The original fence retains its own failures in runtime's early-issues slot. Do
            // not duplicate them as external issues; only HTTP-owned evidence is seeded here.
            let _ = state.runtime.fence_exit_admission().await;
            let mut issues = Vec::new();
            issues.extend(state.templates.close_for_exit(deadline).await);
            if server_result.is_none() {
                match tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), &mut server).await {
                    Ok(result) => server_result = Some(result),
                    Err(_) => issues.push(issue("serverPending", "HTTP request/response tasks have not joined", true)),
                }
            }
            match &server_result {
                Some(Err(_)) => issues.push(issue("serverJoinError", "The HTTP serve task did not join successfully", false)),
                Some(Ok(Err(_))) => issues.push(issue("serveError", "The HTTP server ended with an IO failure", false)),
                Some(Ok(Ok(()))) | None => {}
            }
            // After serve joins, no old handler can register another pump. If it did not join,
            // serverPending already blocks Clean and the retained state keeps late registrations.
            issues.extend(join_legacy(&state, deadline).await);
            let remaining_ms = match u32::try_from(deadline.saturating_duration_since(Instant::now()).as_millis()) {
                Ok(remaining) => remaining,
                Err(_) => {
                    issues.push(issue("invalidExitBudget", "HTTP remaining exit budget could not be represented", false));
                    0
                }
            };
            state.runtime.shutdown_runtime_for_exit(remaining_ms, issues).await
        };
        tokio::pin!(cleanup);
        tokio::select! { biased;
            () = &mut force => std::process::exit(130),
            report = &mut cleanup => report,
        }
    };
    if report.is_clean() {
        // A missing/failed actual serve join was seeded above, so it cannot accompany Clean.
        match server_result {
            Some(Ok(Ok(()))) => Ok(()),
            _ => anyhow::bail!("HTTP shutdown completed without a successful serve join"),
        }
    } else {
        tracing::error!(outcome = ?report.outcome, issues = ?report.issues,
            "HTTP shutdown is degraded; retaining owners until the next exit signal");
        // Never drop a timed-out JoinHandle or unresolved transport registry and call it Clean.
        // This is the original second-signal force-exit path, not another finalizer/retry budget.
        let _retained = (state, server, server_result);
        force.await;
        std::process::exit(130);
    }
}

async fn join_legacy(state: &AppState, deadline: Instant) -> Vec<StudioShutdownIssue> {
    let active = std::mem::take(&mut state.legacy_streams.lock().unwrap_or_else(std::sync::PoisonError::into_inner).active);
    let mut pending = Vec::new();
    let mut failures = Vec::new();
    for mut task in active {
        let result = match (&mut task).now_or_never() {
            Some(result) => Some(result),
            None => tokio::time::timeout_at(tokio::time::Instant::from_std(deadline), &mut task).await.ok(),
        };
        match result {
            Some(Ok(())) => {}
            Some(Err(error)) => failures.push(error),
            None => pending.push(task),
        }
    }
    let mut streams = state.legacy_streams.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
    streams.active.extend(pending);
    streams.failures.extend(failures);
    let mut issues: Vec<_> = streams.failures.iter().map(|_| issue("legacyStreamJoinError",
        "An existing HTTP stream pump did not join successfully", false)).collect();
    issues.extend(streams.active.iter().map(|_| issue("legacyStreamPending",
        "An existing HTTP stream pump has not joined", true)));
    issues
}

fn issue(code: &str, message: &str, retryable: bool) -> StudioShutdownIssue {
    StudioShutdownIssue { stage: "httpTransport".into(), code: code.into(), message: message.into(), retryable,
        correlation_id: StudioError::internal().correlation_id }
}

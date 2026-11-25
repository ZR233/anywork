use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{Context, Result};
use pl_lifecycle::CloseError;
use tokio::sync::oneshot;

use super::orchestrator::SERVICE_STAGE_LIMIT;
use super::stages::{
    ShutdownBudget, StageOutcome, StageReport, StageStatus, run_observer_stage, stage_order,
};
use crate::studio::StudioRuntime;
use crate::studio::runtime::bot_archive_test_host::BotArchiveTestHost;
use crate::studio::runtime::observation_lifecycle::{
    ObservationCloseError, ObserverTask, RuntimeObservationOwner, RuntimeObserver,
};

struct PausedProjection {
    _temp: tempfile::TempDir,
    runtime: StudioRuntime,
    observer: Arc<pl_lifecycle::Managed<ObserverTask>>,
    closing: oneshot::Receiver<()>,
    resume: oneshot::Sender<()>,
}

impl PausedProjection {
    async fn new() -> Result<Self> {
        let temp = tempfile::tempdir()?;
        let runtime = runtime_with_fresh_observer(temp.path()).await?;
        let (closing, notified) = oneshot::channel();
        let (resume, released) = oneshot::channel();
        let observer = runtime
            .observations
            .start(RuntimeObserver::Lsp, |cancel| async move {
                let closing_token = cancel.clone();
                let task = tokio::spawn(async move {
                    closing_token.cancelled().await;
                    closing.send(()).unwrap();
                    released.await.unwrap();
                });
                Ok(ObserverTask::new(cancel, task))
            })
            .await
            .unwrap();
        Ok(Self {
            _temp: temp,
            runtime,
            observer,
            closing: notified,
            resume,
        })
    }
}

async fn runtime_with_fresh_observer(root: &std::path::Path) -> Result<StudioRuntime> {
    let host = BotArchiveTestHost::new(root).await?;
    let mut runtime = host.runtime.as_ref().clone();
    runtime.observations.request_close();
    for observer in [
        RuntimeObserver::Profiles,
        RuntimeObserver::Persistence,
        RuntimeObserver::Lsp,
        RuntimeObserver::ModelRefresh,
    ] {
        assert!(runtime.observations.close(observer, None).await.is_clean());
    }
    runtime.observations = Arc::new(RuntimeObservationOwner::new());
    Ok(runtime)
}

async fn assert_original_refresh_finished(
    runtime: &StudioRuntime,
    original: &Arc<pl_lifecycle::Managed<ObserverTask>>,
) {
    let cached = runtime
        .observations
        .start(RuntimeObserver::Lsp, |_| async {
            panic!("shutdown must not replace the original watcher")
        })
        .await
        .unwrap();
    assert!(Arc::ptr_eq(original, &cached));
    assert!(
        runtime
            .observations
            .close(RuntimeObserver::Lsp, None)
            .await
            .is_clean()
    );
}

async fn assert_no_service_started(runtime: &StudioRuntime) {
    assert!(runtime.service_stops.lsp.lock().await.is_none());
    assert!(runtime.service_stops.ssh.lock().await.is_none());
}

fn stage<'a>(report: &'a StageReport, name: &str) -> &'a StageOutcome {
    report
        .outcomes
        .iter()
        .find(|outcome| outcome.stage == name)
        .expect("original stage ID")
}

#[tokio::test]
async fn paused_refresh_blocks_lsp_and_ssh_until_same_projection_ack() -> Result<()> {
    let mut fixture = PausedProjection::new().await?;
    fixture.runtime.broadcast_cancel().await;
    fixture.runtime.shutdown_agent_framework().await?;
    let mut shutdown = Box::pin(fixture.runtime.shutdown_runtime());
    tokio::select! {
        result = &mut shutdown => { let _ = result; anyhow::bail!("shutdown completed before projection ACK"); },
        result = &mut fixture.closing => result?,
    }
    assert!(futures::poll!(&mut shutdown).is_pending());
    assert_no_service_started(&fixture.runtime).await;
    fixture.resume.send(()).unwrap();
    let stopped = shutdown.await?;
    assert!(stopped.state.is_stopped());
    assert_original_refresh_finished(&fixture.runtime, &fixture.observer).await;
    // 整体关闭已经完成；重复 join 原 retained job，不从 Ready 的夹具重复执行 Stop 命令。
    for slot in [
        &fixture.runtime.service_stops.lsp,
        &fixture.runtime.service_stops.ssh,
    ] {
        let job = slot
            .lock()
            .await
            .clone()
            .context("original retained stop job")?;
        assert!(job.join().await.is_ok());
        assert!(job.join().await.is_ok());
    }
    Ok(())
}

#[tokio::test]
async fn projection_timeout_keeps_services_and_original_resource_for_strict_retry() -> Result<()> {
    let fixture = PausedProjection::new().await?;
    fixture.runtime.broadcast_cancel().await;
    fixture.runtime.shutdown_agent_framework().await?;
    let deadline = Instant::now() + Duration::from_secs(1);
    let budget = ShutdownBudget::at_deadline(deadline);
    let report = fixture.runtime.run_shutdown_stages(budget, None).await;
    assert_eq!(budget.deadline(), Some(deadline));
    assert!(stage(&report, "agentFramework").is_done());
    assert!(matches!(
        stage(&report, "lspState").status,
        StageStatus::TimedOut
    ));
    assert!(!stage(&report, "lspStop").is_done());
    assert!(!stage(&report, "ssh").is_done());
    assert_no_service_started(&fixture.runtime).await;
    let pending = fixture
        .runtime
        .observations
        .close(
            RuntimeObserver::Lsp,
            Some(tokio::time::Instant::from_std(deadline)),
        )
        .await;
    assert_eq!(pending.pending.len(), 1);
    assert_eq!(pending.pending[0].resource.label, "lspState");
    fixture.resume.send(()).unwrap();
    let retry = fixture.runtime.shutdown_runtime().await?;
    assert!(retry.state.is_stopped());
    assert_original_refresh_finished(&fixture.runtime, &fixture.observer).await;
    Ok(())
}

#[tokio::test]
async fn startup_dispose_waits_for_projection_before_stopping_services() -> Result<()> {
    let mut fixture = PausedProjection::new().await?;
    let mut dispose = Box::pin(fixture.runtime.dispose_startup());
    tokio::select! {
        result = &mut dispose => { let _ = result; anyhow::bail!("startup dispose bypassed projection ACK"); },
        result = &mut fixture.closing => result?,
    }
    assert_no_service_started(&fixture.runtime).await;
    fixture.resume.send(()).unwrap();
    dispose.await?;
    assert_original_refresh_finished(&fixture.runtime, &fixture.observer).await;
    for slot in [
        &fixture.runtime.service_stops.lsp,
        &fixture.runtime.service_stops.ssh,
    ] {
        let job = slot.lock().await.clone().context("retained stop job")?;
        assert!(job.join().await.is_ok());
    }
    assert!(
        fixture
            .runtime
            .agent_facility
            .persistence
            .lock()
            .await
            .is_none()
    );
    Ok(())
}

#[tokio::test]
async fn failed_projection_is_reported_once_and_never_acks_service_stop_or_startup_dispose()
-> Result<()> {
    let temp = tempfile::tempdir()?;
    let runtime = runtime_with_fresh_observer(temp.path()).await?;
    let original = runtime
        .observations
        .start(RuntimeObserver::Lsp, |cancel| async move {
            Ok(ObserverTask::new(
                cancel,
                tokio::spawn(async { panic!("retained LSP projection panic") }),
            ))
        })
        .await
        .unwrap();
    runtime.broadcast_cancel().await;
    let report = runtime
        .run_shutdown_stages(ShutdownBudget::unbounded(), None)
        .await;
    let StageStatus::Failed(error) = &stage(&report, "lspState").status else {
        anyhow::bail!("panic was hidden")
    };
    let failure = error
        .downcast_ref::<ObservationCloseError>()
        .context("typed observer report")?;
    assert_eq!(failure.0.failures.len(), 1);
    assert!(
        failure
            .to_string()
            .contains("retained LSP projection panic")
    );
    assert_eq!(
        report
            .outcomes
            .iter()
            .filter(|outcome| outcome.stage == "lspState")
            .count(),
        1
    );
    assert!(stage(&report, "agentProfiles").is_done());
    assert!(stage(&report, "persistenceObserver").is_done());
    assert!(stage(&report, "modelRefresh").is_done());
    assert!(!stage(&report, "lspStop").is_done());
    assert!(!stage(&report, "ssh").is_done());
    assert_no_service_started(&runtime).await;
    let cleanup = runtime.dispose_startup().await.unwrap_err();
    assert_eq!(cleanup.step, "stop_services");
    assert_eq!(cleanup.kind, crate::StudioStartupErrorKind::Internal);
    let source = std::error::Error::source(&cleanup).context("startup retains cleanup report")?;
    let same = source
        .downcast_ref::<ObservationCloseError>()
        .context("original typed source")?;
    assert_eq!(same.0.scope_id, failure.0.scope_id);
    assert_eq!(same.0.failures[0].resource, failure.0.failures[0].resource);
    let (CloseError::Resource(a), CloseError::Resource(b)) =
        (&same.0.failures[0].error, &failure.0.failures[0].error)
    else {
        anyhow::bail!("lost original task error")
    };
    assert!(Arc::ptr_eq(a, b));
    let cached = runtime
        .observations
        .start(RuntimeObserver::Lsp, |_| async {
            panic!("must not restart")
        })
        .await
        .unwrap();
    assert!(Arc::ptr_eq(&original, &cached));
    assert_no_service_started(&runtime).await;
    // Explicit test teardown is not a successful production dependency ACK.
    runtime.external_runtimes.lsp.shutdown().await?;
    runtime.ssh_manager.shutdown().await?;
    runtime.thread_factory.local_executor().close().await?;
    Ok(())
}

#[tokio::test(start_paused = true)]
async fn strict_observer_wait_has_no_service_cap_and_bounded_wait_uses_first_deadline() {
    let observations = Arc::new(RuntimeObservationOwner::new());
    let (release, released) = oneshot::channel();
    let original = observations
        .start(RuntimeObserver::Lsp, |cancel| async move {
            let task_cancel = cancel.clone();
            let task = tokio::spawn(async move {
                task_cancel.cancelled().await;
                released.await.unwrap();
            });
            Ok(ObserverTask::new(cancel, task))
        })
        .await
        .unwrap();
    let mut strict = Box::pin(run_observer_stage(
        observations.clone(),
        RuntimeObserver::Lsp,
        ShutdownBudget::unbounded(),
        stage_order::LSP_STATE,
    ));
    assert!(futures::poll!(&mut strict).is_pending());
    tokio::time::advance(SERVICE_STAGE_LIMIT + Duration::from_secs(1)).await;
    assert!(
        futures::poll!(&mut strict).is_pending(),
        "observer is not an external service with a five-second cap"
    );
    // 虚拟时钟已推进：用 remaining duration 重新起算会错误地延长这一共同绝对期限。
    let deadline = tokio::time::Instant::now() + Duration::from_secs(2);
    let bounded = ShutdownBudget::at_deadline(deadline.into_std());
    let mut first = Box::pin(run_observer_stage(
        observations.clone(),
        RuntimeObserver::Lsp,
        bounded,
        stage_order::LSP_STATE,
    ));
    assert!(futures::poll!(&mut first).is_pending());
    tokio::time::advance(Duration::from_secs(2)).await;
    let std::task::Poll::Ready(first) = futures::poll!(&mut first) else {
        panic!("observer extended the first absolute deadline")
    };
    assert!(matches!(first.status, StageStatus::TimedOut));
    let again = run_observer_stage(
        observations.clone(),
        RuntimeObserver::Lsp,
        bounded,
        stage_order::LSP_STATE,
    )
    .await;
    assert!(matches!(again.status, StageStatus::TimedOut));
    let cached = observations
        .start(RuntimeObserver::Lsp, |_| async {
            panic!("no replacement on timeout")
        })
        .await
        .unwrap();
    assert!(Arc::ptr_eq(&original, &cached));
    release.send(()).unwrap();
    assert!(strict.await.is_done());
}

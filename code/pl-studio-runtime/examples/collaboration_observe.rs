//! Private live evidence collection, never an automated acceptance verdict.
#[path = "collaboration_observe/evidence.rs"]
mod evidence;
#[path = "collaboration_observe/git.rs"]
mod git;
#[path = "collaboration_observe/inputs.rs"]
mod inputs;
#[path = "collaboration_observe/observe.rs"]
mod observe;

use anyhow::Result;
use evidence::{Evidence, Manifest, Termination};
use pl_studio_runtime::{StudioHostKind, StudioRuntime, StudioRuntimeOptions};
use std::time::Instant;
use tokio_util::sync::CancellationToken;

/// Shared absolute admission boundary. Only resource-free observation waits use `read`.
pub struct Boundary {
    deadline: tokio::time::Instant,
    interrupt: CancellationToken,
}

#[derive(Debug, thiserror::Error)]
#[error("observation stopped: {0:?}")]
pub struct Stopped(pub Termination);

impl Boundary {
    pub fn new(seconds: u64, interrupt: CancellationToken) -> Self {
        Self {
            deadline: tokio::time::Instant::now() + std::time::Duration::from_secs(seconds),
            interrupt,
        }
    }
    pub fn check(&self) -> Result<()> {
        if self.interrupt.is_cancelled() {
            return Err(Stopped(Termination::Interrupted).into());
        }
        if tokio::time::Instant::now() >= self.deadline {
            return Err(Stopped(Termination::TimedOut).into());
        }
        Ok(())
    }
    pub async fn stopped(&self) {
        tokio::select! { _ = self.interrupt.cancelled() => (), _ = tokio::time::sleep_until(self.deadline) => () }
    }
    pub async fn read<T>(&self, future: impl std::future::Future<Output = Result<T>>) -> Result<T> {
        self.check()?;
        let result = tokio::select! { biased; _ = self.stopped() => Err(Stopped(if self.interrupt.is_cancelled() { Termination::Interrupted } else { Termination::TimedOut }).into()), result = future => result };
        match (result, self.check()) {
            (Err(error), Err(stopped)) => {
                Err(stopped.context(format!("read also failed: {error:#}")))
            }
            (_, Err(stopped)) => Err(stopped),
            (result, Ok(())) => result,
        }
    }
    pub fn returned(&self, name: &str, started: Instant, manifest: &mut Manifest) {
        manifest
            .admitted_operations
            .push(evidence::OperationTiming {
                operation: name.into(),
                elapsed_millis: started.elapsed().as_millis(),
                stopped_on_return: self.check().err().map(|error| error.to_string()),
            });
    }
}

#[tokio::main]
async fn main() -> Result<()> {
    inputs::require_linux()?;
    let artifacts = inputs::artifact_directory()?;
    let evidence = Evidence::new(artifacts)?;
    let started = Instant::now();
    let mut manifest = Manifest::new()?;
    let interrupt = CancellationToken::new();
    let stop_signal = CancellationToken::new();
    let signal_task = {
        let interrupt = interrupt.clone();
        let stop_signal = stop_signal.clone();
        tokio::spawn(async move {
            tokio::select! {
                _ = stop_signal.cancelled() => Ok(()),
                result = tokio::signal::ctrl_c() => {
                    interrupt.cancel();
                    result
                }
            }
        })
    };
    let result = run(&evidence, &mut manifest, &interrupt).await;
    stop_signal.cancel();
    match signal_task.await {
        Ok(Ok(())) => (),
        Ok(Err(error)) => manifest.issues.push(format!("Ctrl+C listener: {error}")),
        Err(error) => manifest
            .issues
            .push(format!("Ctrl+C listener join: {error}")),
    }
    if let Err(error) = &result {
        if let Some(stopped) = error.downcast_ref::<Stopped>() {
            manifest.termination = stopped.0;
        } else if evidence.exhausted() {
            manifest.termination = Termination::BudgetExceeded;
        }
        manifest.issues.push(format!("primary: {error:#}"));
    }
    manifest.ended_at = evidence::unix_seconds()?;
    manifest.elapsed_millis = started.elapsed().as_millis();
    manifest.evidence_complete = result.is_ok()
        && manifest.issues.is_empty()
        && manifest.unfinished.is_empty()
        && manifest.shutdown_observed
        && !manifest.cleanup_budget_expired
        && manifest.events.iter().all(|event| event.complete)
        && manifest
            .thread_exports
            .iter()
            .all(|thread| thread.complete && thread.nonterminal_tools == 0)
        && matches!(
            manifest.termination,
            Termination::SimpleTreeIdleObserved | Termination::TaskCompletedObserved
        );
    manifest.collected_bytes = evidence.bytes();
    evidence.finish(&manifest)?;
    println!(
        "证据收集终止原因：{:?}；清单：{}。这不是验收结论。",
        manifest.termination,
        evidence.root().join("manifest.json").display()
    );
    // Provider errors may contain private payloads: retain them in the private manifest, not stdout.
    anyhow::ensure!(
        manifest.evidence_complete,
        "证据不完整，请检查私有 manifest.json 中的终止原因、主错误和清理错误"
    );
    Ok(())
}

async fn run(
    evidence: &Evidence,
    manifest: &mut Manifest,
    interrupt: &CancellationToken,
) -> Result<()> {
    let seconds = inputs::observation_seconds()?;
    let scene = Boundary::new(seconds, interrupt.clone());
    let scene_started = Instant::now();
    manifest.requested_seconds = seconds;
    let prepared = inputs::Inputs::prepare(evidence, &scene).await;
    manifest.scenario_elapsed_millis = scene_started.elapsed().as_millis();
    let inputs = prepared?;
    manifest.mode = inputs.mode.clone();
    manifest.root_route_override = inputs.route_override.is_some();
    manifest.prompt_sha256 = evidence::sha256(inputs.prompt.as_bytes());
    manifest.workspace = Some(inputs.workspace.clone());
    scene.check()?;
    let before = git::capture_git(evidence, &inputs.workspace, "before", &scene).await;
    manifest.scenario_elapsed_millis = scene_started.elapsed().as_millis();
    before?;
    scene.check()?;
    let admitted = Instant::now();
    let initialized = StudioRuntime::initialize(StudioRuntimeOptions {
        studio_home: Some(inputs.home.clone()),
        host: StudioHostKind::Desktop,
        ..StudioRuntimeOptions::desktop()
    })
    .await;
    scene.returned("initialize", admitted, manifest);
    manifest.scenario_elapsed_millis = scene_started.elapsed().as_millis();
    let runtime = match initialized {
        Ok(runtime) => runtime,
        Err(error) => {
            return Err(match scene.check() {
                Err(stopped) => stopped.context(format!("initialize also failed: {error:#}")),
                Ok(()) => anyhow::Error::new(error).context("initialize isolated Studio"),
            });
        }
    };
    let mut collection = observe::Collection::new(evidence.clone());
    let result = collection.run(&runtime, &inputs, manifest, &scene).await;
    manifest.scenario_elapsed_millis = scene_started.elapsed().as_millis();
    if let Err(error) = &result {
        manifest.termination = if let Err(stopped) = scene.check() {
            stopped
                .downcast_ref::<Stopped>()
                .map_or(Termination::CollectionError, |stopped| stopped.0)
        } else if let Some(stopped) = error.downcast_ref::<Stopped>() {
            stopped.0
        } else if evidence.exhausted() {
            Termination::BudgetExceeded
        } else if error.downcast_ref::<std::io::Error>().is_some()
            || error
                .downcast_ref::<pl_protocol::studio::StudioError>()
                .is_some_and(|error| error.code == pl_protocol::studio::StudioErrorCode::Storage)
        {
            Termination::StorageError
        } else if error
            .downcast_ref::<pl_protocol::studio::StudioError>()
            .is_some()
        {
            Termination::ApiError
        } else {
            Termination::CollectionError
        };
        manifest.issues.push(format!("collection: {error:#}"));
    }
    // Stop only our subscriptions, then join every writer. Runtime ownership stays here throughout
    // export and shutdown; no select drops a future that owns a writer or a shutdown operation.
    let cleanup_started = Instant::now();
    let cleanup = Boundary::new(30, CancellationToken::new());
    collection
        .finish_writers(&runtime, manifest, &cleanup)
        .await;
    if let Err(error) = collection.export(&runtime, manifest, &cleanup).await {
        manifest.issues.push(format!("final export: {error:#}"));
        if evidence.exhausted() {
            manifest.termination = Termination::BudgetExceeded;
        }
    }
    manifest.cleanup_elapsed_millis = cleanup_started.elapsed().as_millis();
    manifest.cleanup_budget_expired = cleanup.check().is_err();
    if manifest.cleanup_budget_expired {
        manifest
            .unfinished
            .push("30-second total cleanup evidence budget expired".into());
    }
    let shutdown_started = Instant::now();
    match runtime.shutdown_runtime().await {
        Ok(snapshot) => {
            manifest.shutdown_observed = true;
            if let Err(error) = evidence.json(
                "shutdown-runtime.json",
                "actual runtime shutdown receipt",
                &snapshot,
            ) {
                manifest
                    .issues
                    .push(format!("shutdown receipt export: {error:#}"));
            }
        }
        Err(error) => manifest.issues.push(format!("runtime shutdown: {error:#}")),
    }
    manifest.shutdown_elapsed_millis = shutdown_started.elapsed().as_millis();
    // Runtime shutdown is cleanup, never evidence of Task completion.
    result
}

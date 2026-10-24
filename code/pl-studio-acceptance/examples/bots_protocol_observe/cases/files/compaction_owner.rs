//! One Session-owned public Studio runtime and its one compact operation.
//!
//! Case futures borrow this owner; cancelling/dropping a case never drops a
//! JoinHandle. Cleanup closes the real runtime before joining the registered
//! compact task and only then releases the runtime. No global task registry.

use anyhow::{Context, Result, bail, ensure};
use pl_studio_runtime::{StudioRuntime, StudioRuntimeOptions};
use serde::Serialize;
use std::{path::Path, time::Duration};
use tokio::task::JoinHandle;

#[derive(Debug, Clone, Serialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub(in crate::cases) enum CompactTerminal {
    Succeeded,
    Failed { message: String },
    JoinFailed { message: String },
}

#[derive(Debug, Clone, Default, Serialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::cases) struct CleanupEvidence {
    epoch: u32,
    pub runtime_closed: bool,
    pub compact_spawned: bool,
    pub compact_pending_before_shutdown: bool,
    pub compact_joined: bool,
    pub compact_aborted: bool,
    pub compact_terminal: Option<CompactTerminal>,
}

#[derive(Default)]
pub(in crate::cases) struct CompactionOwner {
    runtime: Option<StudioRuntime>,
    task: Option<JoinHandle<Result<()>>>,
    evidence: CleanupEvidence,
}

impl CompactionOwner {
    pub(super) async fn initialize(&mut self, home: &Path) -> Result<()> {
        ensure!(
            self.runtime.is_none() && self.task.is_none(),
            "previous compact runtime still needs cleanup"
        );
        let runtime =
            StudioRuntime::initialize(StudioRuntimeOptions::http_server(Some(home.to_path_buf())))
                .await?;
        // No await between receiving the initialized owner and registering it.
        self.runtime = Some(runtime);
        self.evidence = CleanupEvidence {
            epoch: self.evidence.epoch + 1,
            ..CleanupEvidence::default()
        };
        Ok(())
    }

    pub(super) fn runtime(&self) -> Result<StudioRuntime> {
        self.runtime
            .clone()
            .context("public compact runtime is not registered")
    }

    pub(super) fn spawn_compact(&mut self, thread_id: &str) -> Result<()> {
        ensure!(self.task.is_none(), "a compact task is already registered");
        let runtime = self.runtime()?;
        let thread_id = thread_id.to_owned();
        self.task = Some(tokio::spawn(async move {
            runtime.compact_thread(&thread_id).await
        }));
        self.evidence.compact_spawned = true;
        self.evidence.compact_joined = false;
        self.evidence.compact_terminal = None;
        Ok(())
    }

    pub(super) async fn join_compact(&mut self, budget: Duration) -> Result<CompactTerminal> {
        let task = self
            .task
            .as_mut()
            .context("no registered compact task to join")?;
        // Borrow the slot: timeout/cancellation leaves the only join obligation
        // in this owner, available to the runner's subsequent cleanup.
        let joined = tokio::time::timeout(budget, task)
            .await
            .context("registered compact task did not join within its budget")?;
        self.task = None;
        self.evidence.compact_joined = true;
        let terminal = match joined {
            Ok(Ok(())) => CompactTerminal::Succeeded,
            Ok(Err(error)) => CompactTerminal::Failed {
                message: crate::report::one_line(&format!("{error:#}")),
            },
            Err(error) => CompactTerminal::JoinFailed {
                message: error.to_string(),
            },
        };
        self.evidence.compact_terminal = Some(terminal.clone());
        ensure!(
            !matches!(terminal, CompactTerminal::JoinFailed { .. }),
            "compact worker failed to join normally: {terminal:?}"
        );
        Ok(terminal)
    }

    pub(in crate::cases) fn evidence(&self) -> CleanupEvidence {
        self.evidence.clone()
    }

    pub(in crate::cases) async fn close(&mut self) -> Result<CleanupEvidence> {
        let mut errors = Vec::new();
        if let Some(task) = self.task.as_ref() {
            self.evidence.compact_pending_before_shutdown = !task.is_finished();
        }
        if let Some(runtime) = self.runtime.as_ref() {
            match tokio::time::timeout(Duration::from_secs(40), runtime.shutdown_runtime()).await {
                Ok(Ok(_)) => self.evidence.runtime_closed = true,
                Ok(Err(error)) => errors.push(format!("public runtime shutdown: {error:#}")),
                Err(_) => errors.push("public runtime shutdown exceeded 40s".into()),
            }
        }
        if self.task.is_some()
            && let Err(error) = self.join_compact(Duration::from_secs(10)).await
        {
            errors.push(format!("compact join after shutdown: {error:#}"));
            if let Some(task) = self.task.as_mut() {
                // This is a reported cleanup failure, never a successful
                // product cancellation. Even fallback abort is awaited.
                task.abort();
                let joined = task.await;
                self.task = None;
                self.evidence.compact_joined = true;
                self.evidence.compact_aborted = true;
                self.evidence.compact_terminal = Some(CompactTerminal::JoinFailed {
                    message: format!("fallback abort after shutdown/join failure: {joined:?}"),
                });
            }
        }
        if self.evidence.runtime_closed && self.task.is_none() {
            self.runtime = None;
        }
        if errors.is_empty() {
            Ok(self.evidence())
        } else {
            bail!(errors.join("; "))
        }
    }
}

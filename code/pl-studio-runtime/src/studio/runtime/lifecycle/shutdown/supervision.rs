//! The original shutdown coordinator owns stage completions and finalization admission.
//! No business future, notification or file release runs under its synchronous state lock.

use std::collections::BTreeMap;
use std::future::Future;
use std::panic::AssertUnwindSafe;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use anyhow::Context;
use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use tokio::sync::{oneshot, watch};

use crate::studio::{StudioRuntime, StudioRuntimeCommand, StudioRuntimeState, unix_seconds};
use crate::{StudioShutdownIssue, StudioShutdownReport};

use super::{EXIT_CLEANUP_BUDGET, ShutdownBudget, panic_text};

/// Closed identities retain the original diagnostic order, independently of completion order.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(super) enum StageId {
    AgentFramework,
    Persistence,
    ModelCatalog,
    Recovery,
    ModelRefresh,
    Title,
    McpStartupReconcile,
    McpHealth,
    McpStop,
    McpStopped,
    LspState,
    LspStop,
    LspStopped,
    ToolRefresh,
    PersistenceObserver,
    Ssh,
    AgentProfiles,
    AcpAuth,
    Bots,
    AcpInstall,
    DetailReads,
    Store,
    /// 统计进度 follower 的有界 join；追加在末尾，既有 stage 的 order 不变。
    StatisticsFollower,
}

impl StageId {
    pub(super) fn order(self) -> usize {
        self as usize
    }

    pub(super) fn label(self) -> &'static str {
        match self {
            Self::AgentFramework => "agentFramework",
            Self::Persistence => "persistence",
            Self::ModelCatalog => "modelCatalog",
            Self::Recovery => "recovery",
            Self::ModelRefresh => "modelRefresh",
            Self::Title => "title",
            Self::McpStartupReconcile => "mcpStartupReconcile",
            Self::McpHealth => "mcpHealth",
            Self::McpStop => "mcpStop",
            Self::McpStopped => "mcpStopped",
            Self::LspState => "lspState",
            Self::LspStop => "lspStop",
            Self::LspStopped => "lspStopped",
            Self::ToolRefresh => "toolRefresh",
            Self::PersistenceObserver => "persistenceObserver",
            Self::Ssh => "ssh",
            Self::AgentProfiles => "agentProfiles",
            Self::AcpAuth => "acpAuth",
            Self::Bots => "bots",
            Self::AcpInstall => "acpInstall",
            Self::DetailReads => "detailReads",
            Self::Store => "store",
            Self::StatisticsFollower => "statisticsFollower",
        }
    }
}

#[derive(Debug)]
pub(super) enum FailureCause {
    Failed(anyhow::Error),
    Panicked(tokio::task::JoinError),
}

#[derive(Debug)]
pub(super) struct StageFailure {
    pub(super) cause: FailureCause,
    pub(super) diagnostics: OnceLock<Vec<StudioShutdownIssue>>,
    retry_eligible: bool,
}

impl StageFailure {
    pub(super) fn new(id: StageId, cause: FailureCause) -> Arc<Self> {
        Arc::new(Self {
            retry_eligible: super::recovery::can_retry(id, &cause),
            cause,
            diagnostics: OnceLock::new(),
        })
    }
}

type StageCompletion = Shared<BoxFuture<'static, Result<(), Arc<StageFailure>>>>;

#[derive(Clone)]
pub(super) struct StageJob {
    // An owned token cannot suffer numeric wraparound or an ABA retry grant.
    attempt: Arc<()>,
    completion: StageCompletion,
}

impl StageJob {
    fn gated<F, Fut>(id: StageId, make: F) -> (Self, oneshot::Sender<()>)
    where
        F: FnOnce() -> Fut + Send + 'static,
        Fut: Future<Output = anyhow::Result<()>> + Send + 'static,
    {
        let (start, ready) = oneshot::channel();
        let handle = tokio::spawn(async move {
            ready
                .await
                .context("shutdown stage startup gate was not released")?;
            make().await
        });
        let completion = async move {
            match handle.await {
                Ok(Ok(())) => Ok(()),
                Ok(Err(error)) => Err(StageFailure::new(id, FailureCause::Failed(error))),
                Err(join) => Err(StageFailure::new(id, FailureCause::Panicked(join))),
            }
        }
        .boxed()
        .shared();
        (
            Self {
                attempt: Arc::new(()),
                completion,
            },
            start,
        )
    }

    pub(super) async fn join(&self) -> Result<(), Arc<StageFailure>> {
        // Shared retains the original JoinHandle and raw result if every observer leaves.
        // It is deliberately lazy: only an actual later join confirms the terminal result.
        self.completion.clone().await
    }

    pub(super) fn observed_result(&self) -> Option<Result<(), Arc<StageFailure>>> {
        self.completion.peek().cloned()
    }

    fn observed_failure(&self) -> Option<&Arc<StageFailure>> {
        self.completion
            .peek()
            .and_then(|result| result.as_ref().err())
    }
}

#[derive(Clone, Default)]
pub(super) struct RetrySnapshot(BTreeMap<StageId, Arc<()>>);

struct StageSlot {
    current: StageJob,
    // One first cause plus the current completion, not an unbounded attempt history.
    first_failure: Option<Arc<StageFailure>>,
}

struct ExitAdmission {
    deadline: Instant,
    issues: Vec<StudioShutdownIssue>,
}

#[derive(Default)]
struct CoordinatorState {
    exit: Option<ExitAdmission>,
    stages: BTreeMap<StageId, StageSlot>,
    clean_committed: bool,
}

#[derive(Clone)]
pub(super) struct ExitBlock {
    pub(super) issues: Vec<StudioShutdownIssue>,
    pub(super) expired: bool,
}

#[derive(Clone)]
pub(super) enum AdmissionDenied {
    Finalized,
    Exit(ExitBlock),
}

pub(super) enum CleanCommit {
    First,
    AlreadyCommitted,
}

pub(super) enum CleanCommitError {
    Exit(ExitBlock),
    Runtime(crate::studio::StudioRuntimeTransitionError),
}

#[derive(Clone)]
pub(crate) struct ShutdownRun {
    report: Arc<watch::Sender<Option<StudioShutdownReport>>>,
    state: Arc<Mutex<CoordinatorState>>,
}

impl Default for ShutdownRun {
    fn default() -> Self {
        let (report, _) = watch::channel(None);
        Self {
            report: Arc::new(report),
            state: Arc::new(Mutex::new(CoordinatorState::default())),
        }
    }
}

impl CoordinatorState {
    fn exit_block(&self) -> Option<ExitBlock> {
        let exit = self.exit.as_ref()?;
        let expired = Instant::now() >= exit.deadline;
        (expired || !exit.issues.is_empty()).then(|| ExitBlock {
            issues: exit.issues.clone(),
            expired,
        })
    }
}

impl ShutdownRun {
    /// Freeze only failures already confirmed at strict entry. A later failure needs a new call.
    pub(super) fn retry_snapshot(&self) -> RetrySnapshot {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        RetrySnapshot(
            state
                .stages
                .iter()
                .filter_map(|(id, slot)| {
                    slot.current
                        .observed_failure()
                        .filter(|failure| failure.retry_eligible)
                        .map(|_| (*id, slot.current.attempt.clone()))
                })
                .collect(),
        )
    }

    pub(super) fn ensure_stage<F, Fut>(
        &self,
        id: StageId,
        retries: &RetrySnapshot,
        make: F,
    ) -> Result<StageJob, AdmissionDenied>
    where
        F: FnOnce() -> Fut + Send + 'static,
        Fut: Future<Output = anyhow::Result<()>> + Send + 'static,
    {
        let (job, start, retired) = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if state.clean_committed {
                return Err(AdmissionDenied::Finalized);
            }
            let retry = state.stages.get(&id).is_some_and(|slot| {
                retries
                    .0
                    .get(&id)
                    .is_some_and(|attempt| Arc::ptr_eq(attempt, &slot.current.attempt))
                    && slot
                        .current
                        .observed_failure()
                        .is_some_and(|failure| failure.retry_eligible)
            });
            if let Some(slot) = state.stages.get(&id)
                && !retry
            {
                return Ok(slot.current.clone());
            }
            if id == StageId::Store
                && let Some(block) = state.exit_block()
            {
                return Err(AdmissionDenied::Exit(block));
            }
            let retired = state.stages.remove(&id);
            let first_failure = retired.as_ref().and_then(|slot| {
                slot.first_failure
                    .clone()
                    .or_else(|| slot.current.observed_failure().cloned())
            });
            let (job, start) = StageJob::gated(id, make);
            state.stages.insert(
                id,
                StageSlot {
                    current: job.clone(),
                    first_failure,
                },
            );
            (job, start, retired)
        };
        // Sending can wake external executor code; dropping retired values can release resources.
        // Both happen after the original slot is installed and the coordinator guard is gone.
        let _ = start.send(());
        if let Some(slot) = &retired
            && let Some(failure) = slot.current.observed_failure()
        {
            // The original observer may have left after join but before collecting diagnostics.
            // Archive that confirmed failure before retiring its completion, outside the lock.
            super::archive_stage_failure(id, failure);
        }
        drop(retired);
        Ok(job)
    }

    pub(super) fn exit_issues(&self) -> Vec<StudioShutdownIssue> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .exit
            .as_ref()
            .map_or_else(Vec::new, |exit| exit.issues.clone())
    }

    /// Rejoining admitted Store IO needs no new finalization permission, even after D0/E blocks
    /// starting a new close. Its actual completion must remain observable without running make.
    pub(super) fn existing_store(&self) -> Option<StageJob> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .stages
            .get(&StageId::Store)
            .map(|slot| slot.current.clone())
    }

    pub(super) fn deadline_report(&self, stage: &str) -> StudioShutdownReport {
        let mut report = StudioShutdownReport::deadline_exceeded(
            stage,
            pl_protocol::studio::StudioError::internal().correlation_id,
        );
        report.issues.extend(self.exit_issues());
        report
    }

    /// D0, E and ownership of the sole exit runner are one synchronous admission decision.
    pub(super) fn start_exit(
        &self,
        runtime: &StudioRuntime,
        requested: Duration,
        issues: Vec<StudioShutdownIssue>,
    ) -> Instant {
        let deadline = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if let Some(exit) = &state.exit {
                return exit.deadline;
            }
            let deadline = Instant::now() + requested.min(EXIT_CLEANUP_BUDGET);
            state.exit = Some(ExitAdmission { deadline, issues });
            deadline
        };
        let runtime = runtime.clone();
        let report = self.report.clone();
        tokio::spawn(async move {
            let remaining = deadline.saturating_duration_since(Instant::now());
            let guard = tokio::time::timeout(remaining, runtime.lifecycle_lock.lock())
                .await
                .ok();
            let Some(_lifecycle_guard) = guard else {
                let _ = report
                    .send_replace(Some(runtime.shutdown_run.deadline_report("lifecycleLock")));
                return;
            };
            let outcome = AssertUnwindSafe(runtime.execute_shutdown(
                ShutdownBudget::at_deadline(deadline),
                RetrySnapshot::default(),
            ))
            .catch_unwind()
            .await;
            let value = match outcome {
                Ok(report) => report,
                Err(payload) => {
                    tracing::error!(pid = std::process::id(), panic = %panic_text(&payload),
                        "Studio shutdown orchestration task panicked; reporting Degraded");
                    StudioShutdownReport::panicked()
                }
            };
            let _ = report.send_replace(Some(value));
        });
        deadline
    }

    /// Only this boundary may commit Clean. Lock order is coordinator -> pure RuntimeState.
    /// RuntimeState owns only its snapshot mutex; it never calls back into this coordinator.
    pub(super) fn commit_clean(
        &self,
        runtime_state: &StudioRuntimeState,
    ) -> Result<CleanCommit, CleanCommitError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.clean_committed {
            return Ok(CleanCommit::AlreadyCommitted);
        }
        if let Some(block) = state.exit_block() {
            return Err(CleanCommitError::Exit(block));
        }
        runtime_state
            .apply(StudioRuntimeCommand::FinishShutdown {
                expected_revision: runtime_state.snapshot().revision,
                at: unix_seconds(),
            })
            .map_err(CleanCommitError::Runtime)?;
        state.clean_committed = true;
        Ok(CleanCommit::First)
    }

    pub(super) async fn wait(&self, deadline: Option<Instant>) -> Option<StudioShutdownReport> {
        let mut receiver = self.report.subscribe();
        loop {
            let current = receiver.borrow().clone();
            if current.is_some() {
                return current;
            }
            match deadline {
                None => receiver.changed().await.ok()?,
                Some(deadline) => {
                    let remaining = deadline.saturating_duration_since(Instant::now());
                    if remaining.is_zero() {
                        return None;
                    }
                    tokio::time::timeout(remaining, receiver.changed())
                        .await
                        .ok()?
                        .ok()?;
                }
            }
        }
    }
}

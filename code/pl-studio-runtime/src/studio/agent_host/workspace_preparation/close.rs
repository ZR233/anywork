//! Fixed-policy workspace cleanup. The caller's original close owner retains this future;
//! failures retain only this operation, never another canonical lease table or background task.
use std::sync::{Arc, Mutex};

use futures::FutureExt;
use futures::future::{BoxFuture, Shared};
use pl_tool::collaboration::thread::AgentWorkspaceDisposition;

use super::{
    WorktreeHandle, WorktreeLease, WorktreeLeaseOwner, WorktreeLeaseState, WorktreeManager,
};
use crate::agent::worktree::WorktreeError;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::studio) enum WorkspaceClosePhase {
    PreserveRecord,
    Identity,
    Preview,
    CleanupRecord,
    Discard,
    FailureRecord,
    CleanRecord,
    Done,
}

#[derive(Debug, Clone)]
pub(in crate::studio) enum WorkspaceCloseCause {
    Lease(Arc<anyhow::Error>),
    Physical(Arc<WorktreeError>),
}
impl std::fmt::Display for WorkspaceCloseCause {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Lease(error) => write!(f, "{error:#}"),
            Self::Physical(error) => write!(f, "{error}"),
        }
    }
}
impl std::error::Error for WorkspaceCloseCause {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Lease(error) => Some(error.as_ref().as_ref()),
            Self::Physical(error) => Some(error.as_ref()),
        }
    }
}
#[derive(Debug, Clone)]
pub(in crate::studio) struct WorkspaceCloseIssue {
    #[allow(dead_code)] // 保留：关闭/停机诊断事实，报告投影的读取方尚未接回；删除会丢失去噪证据。
    pub(in crate::studio) phase: WorkspaceClosePhase,
    pub(in crate::studio) cause: WorkspaceCloseCause,
}

#[derive(Clone)]
pub(in crate::studio) struct WorkspaceCloseFailure {
    run: Arc<WorkspaceClose>,
    pub(in crate::studio) issues: Vec<WorkspaceCloseIssue>,
    pub(in crate::studio) physical_complete: bool,
}
impl std::fmt::Debug for WorkspaceCloseFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("WorkspaceCloseFailure")
            .field("issues", &self.issues)
            .field("physical_complete", &self.physical_complete)
            .finish_non_exhaustive()
    }
}
impl std::fmt::Display for WorkspaceCloseFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("original workspace cleanup remains unresolved")
    }
}
impl std::error::Error for WorkspaceCloseFailure {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.issues.first().map(|issue| &issue.cause as _)
    }
}

impl WorkspaceCloseFailure {
    pub(in crate::studio) fn can_resume_original(&self) -> bool {
        let progress = self
            .run
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if progress.terminal || progress.phase == WorkspaceClosePhase::Done {
            return false;
        }
        if self
            .run
            .leases
            .get(&progress.recorded.owner_thread_id)
            .as_ref()
            != Some(&progress.recorded)
            || self
                .run
                .leases
                .is_creating(&progress.recorded.owner_thread_id)
        {
            return false;
        }
        match progress.wait.as_ref().and_then(Shared::peek) {
            None | Some(Ok(())) => true,
            Some(Err(error)) => physical_retryable(error),
        }
    }

    pub(in crate::studio) fn original_is_complete(&self) -> bool {
        self.run
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .phase
            == WorkspaceClosePhase::Done
    }

    pub(in crate::studio) async fn resume_original(&self) -> Result<(), Self> {
        if self.original_is_complete() {
            return Ok(());
        }
        if !self.can_resume_original() {
            return Err(self.clone());
        }
        self.run.drive().await
    }
}

type PhysicalWait = Shared<BoxFuture<'static, Result<(), Arc<WorktreeError>>>>;
struct Progress {
    lease: WorktreeLease,
    recorded: WorktreeLease,
    phase: WorkspaceClosePhase,
    wait: Option<PhysicalWait>,
    issues: Vec<WorkspaceCloseIssue>,
    physical_complete: bool,
    terminal: bool,
}
struct WorkspaceClose {
    leases: WorktreeLeaseOwner,
    manager: WorktreeManager,
    disposition: AgentWorkspaceDisposition,
    progress: Mutex<Progress>,
}

pub(in crate::studio) async fn close_workspace(
    leases: &WorktreeLeaseOwner,
    manager: &WorktreeManager,
    lease: WorktreeLease,
    disposition: AgentWorkspaceDisposition,
) -> Result<(), WorkspaceCloseFailure> {
    let phase = if lease.state == WorktreeLeaseState::Cleaned {
        WorkspaceClosePhase::Done
    } else {
        WorkspaceClosePhase::PreserveRecord
    };
    let run = Arc::new(WorkspaceClose {
        leases: leases.clone(),
        manager: manager.clone(),
        disposition,
        progress: Mutex::new(Progress {
            recorded: lease.clone(),
            lease,
            phase,
            wait: None,
            issues: Vec::new(),
            physical_complete: false,
            terminal: false,
        }),
    });
    run.drive().await
}

impl WorkspaceClose {
    fn failure(self: &Arc<Self>) -> WorkspaceCloseFailure {
        let progress = self
            .progress
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        WorkspaceCloseFailure {
            run: self.clone(),
            issues: progress.issues.clone(),
            physical_complete: progress.physical_complete,
        }
    }

    fn record(
        self: &Arc<Self>,
        phase: WorkspaceClosePhase,
        next: WorkspaceClosePhase,
        state: WorktreeLeaseState,
    ) -> Result<(), WorkspaceCloseFailure> {
        let mut lease = {
            let progress = self
                .progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            progress.lease.clone()
        };
        lease.transition(state);
        match self.leases.record(lease.clone()) {
            Ok(()) => {
                let mut progress = self
                    .progress
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                progress.recorded = lease.clone();
                progress.lease = lease;
                progress.phase = next;
                Ok(())
            }
            Err(error) => {
                {
                    let mut progress = self
                        .progress
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    progress.phase = phase;
                    progress.terminal = true;
                    progress.issues.push(WorkspaceCloseIssue {
                        phase,
                        cause: WorkspaceCloseCause::Lease(Arc::new(error)),
                    });
                }
                Err(self.failure())
            }
        }
    }

    async fn physical(
        self: &Arc<Self>,
        phase: WorkspaceClosePhase,
    ) -> Result<(), WorkspaceCloseFailure> {
        let (wait, retired) = {
            let mut progress = self
                .progress
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let replace = progress.wait.as_ref().is_none_or(
                |wait| matches!(wait.peek(), Some(Err(error)) if physical_retryable(error)),
            );
            let retired = if replace {
                let manager = self.manager.clone();
                let handle = WorktreeHandle {
                    path: std::path::PathBuf::from(&progress.lease.path),
                    branch: progress.lease.branch.clone(),
                    base_commit: progress.lease.base_commit.clone(),
                };
                let future = async move {
                    match phase {
                        WorkspaceClosePhase::Preview => {
                            manager.preview_existing(&handle).await.map(|_| ())
                        }
                        WorkspaceClosePhase::Discard => manager.discard(&handle).await,
                        _ => unreachable!("physical wait only belongs to Preview or Discard"),
                    }
                    .map_err(Arc::new)
                }
                .boxed()
                .shared();
                progress.wait.replace(future)
            } else {
                None
            };
            (
                progress
                    .wait
                    .as_ref()
                    .expect("original workspace wait installed")
                    .clone(),
                retired,
            )
        };
        drop(retired);
        match wait.await {
            Ok(()) => {
                let retired = {
                    let mut progress = self
                        .progress
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    progress.issues.clear();
                    if phase == WorkspaceClosePhase::Preview {
                        progress.phase = WorkspaceClosePhase::CleanupRecord;
                    } else {
                        progress.physical_complete = true;
                        progress.phase = WorkspaceClosePhase::CleanRecord;
                    }
                    progress.wait.take()
                };
                drop(retired);
                Ok(())
            }
            Err(error) => {
                {
                    let mut progress = self
                        .progress
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    progress.issues = vec![WorkspaceCloseIssue {
                        phase,
                        cause: WorkspaceCloseCause::Physical(error.clone()),
                    }];
                    progress.terminal = !physical_retryable(&error);
                }
                if phase == WorkspaceClosePhase::Discard {
                    // Preserve both causes if the canonical preservation record also refuses.
                    self.record(
                        WorkspaceClosePhase::FailureRecord,
                        WorkspaceClosePhase::Discard,
                        WorktreeLeaseState::Preserved,
                    )?;
                }
                Err(self.failure())
            }
        }
    }

    async fn drive(self: &Arc<Self>) -> Result<(), WorkspaceCloseFailure> {
        loop {
            let (phase, terminal, recorded) = {
                let progress = self
                    .progress
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                (progress.phase, progress.terminal, progress.recorded.clone())
            };
            if phase == WorkspaceClosePhase::Done {
                return Ok(());
            }
            if terminal {
                return Err(self.failure());
            }
            if self.leases.get(&recorded.owner_thread_id).as_ref() != Some(&recorded)
                || self.leases.is_creating(&recorded.owner_thread_id)
            {
                {
                    let mut progress = self
                        .progress
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner);
                    progress.terminal = true;
                    progress.issues.push(WorkspaceCloseIssue {
                        phase: WorkspaceClosePhase::Identity,
                        cause: WorkspaceCloseCause::Lease(Arc::new(anyhow::anyhow!(
                            "original workspace lease changed during close"
                        ))),
                    });
                }
                return Err(self.failure());
            }
            match phase {
                WorkspaceClosePhase::PreserveRecord => {
                    let next = if self.disposition == AgentWorkspaceDisposition::Preserve {
                        WorkspaceClosePhase::Done
                    } else {
                        WorkspaceClosePhase::Identity
                    };
                    self.record(phase, next, WorktreeLeaseState::Preserved)?;
                }
                WorkspaceClosePhase::Identity => {
                    let lease = self
                        .progress
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .lease
                        .clone();
                    if let Err(error) = lease.validate_identity() {
                        {
                            let mut progress = self
                                .progress
                                .lock()
                                .unwrap_or_else(std::sync::PoisonError::into_inner);
                            progress.terminal = true;
                            progress.issues.push(WorkspaceCloseIssue {
                                phase,
                                cause: WorkspaceCloseCause::Lease(Arc::new(error)),
                            });
                        }
                        return Err(self.failure());
                    }
                    self.progress
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .phase = WorkspaceClosePhase::Preview;
                }
                WorkspaceClosePhase::Preview => self.physical(phase).await?,
                WorkspaceClosePhase::CleanupRecord => self.record(
                    phase,
                    WorkspaceClosePhase::Discard,
                    WorktreeLeaseState::CleanupRequested,
                )?,
                WorkspaceClosePhase::Discard => {
                    let retrying = self
                        .progress
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .wait
                        .as_ref()
                        .is_some_and(|wait| matches!(wait.peek(), Some(Err(_))));
                    if retrying {
                        self.record(
                            WorkspaceClosePhase::CleanupRecord,
                            WorkspaceClosePhase::Discard,
                            WorktreeLeaseState::CleanupRequested,
                        )?;
                    }
                    self.physical(phase).await?;
                }
                WorkspaceClosePhase::CleanRecord => self.record(
                    phase,
                    WorkspaceClosePhase::Done,
                    WorktreeLeaseState::Cleaned,
                )?,
                WorkspaceClosePhase::FailureRecord | WorkspaceClosePhase::Done => {
                    return Err(self.failure());
                }
            }
        }
    }
}

fn physical_retryable(error: &WorktreeError) -> bool {
    match error {
        WorktreeError::Missing
        | WorktreeError::IdentityMismatch(_)
        | WorktreeError::InvalidResource(_)
        | WorktreeError::UnsafeBranch(_) => false,
        WorktreeError::CleanupFailed { failures, .. } => {
            !failures.is_empty() && failures.iter().all(physical_retryable)
        }
        WorktreeError::OperationFailedWithCleanup { operation, cleanup } => {
            physical_retryable(operation) && physical_retryable(cleanup)
        }
        WorktreeError::OperationFailedAfterCleanup { operation } => physical_retryable(operation),
        WorktreeError::GitLaunchFailed { .. }
        | WorktreeError::GitTimedOut { .. }
        | WorktreeError::GitExited { .. }
        | WorktreeError::GitStatusUnknown { .. }
        | WorktreeError::LocalIo { .. }
        | WorktreeError::Remote { .. }
        | WorktreeError::RemoteExecution { .. }
        | WorktreeError::RemoteFile { .. } => true,
    }
}

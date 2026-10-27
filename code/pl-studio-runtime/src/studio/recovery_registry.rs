//! Recovery issues and scan lifecycle share one owner and revision.
use crate::studio::{StudioRecoveryIssue, ids::unix_seconds};
use pl_protocol::{ObservedResource, ObservedResourceCommand, StateError, StateOperation};
use std::{
    collections::BTreeSet,
    sync::{Arc, Mutex},
};

#[derive(Debug, Clone)]
enum ScanState {
    Idle,
    Stopped,
    Checking,
    Failed(StateError),
}
#[derive(Debug)]
struct State {
    issues: Vec<StudioRecoveryIssue>,
    removed: BTreeSet<String>,
    retired_threads: BTreeSet<String>,
    scan: ScanState,
    revision: u64,
    updated_at: i64,
}
impl State {
    fn touch(&mut self) {
        self.revision = self.revision.saturating_add(3);
        self.updated_at = unix_seconds();
    }
    fn snapshot(&self) -> ObservedResource<Vec<StudioRecoveryIssue>> {
        let base = ObservedResource::ready(self.revision, self.updated_at, self.issues.clone());
        if matches!(self.scan, ScanState::Idle) {
            return base;
        }
        if matches!(self.scan, ScanState::Stopped) {
            return base
                .decide(ObservedResourceCommand::Stop {
                    expected_revision: self.revision,
                    stopped_at: self.updated_at,
                })
                .expect("Ready accepts Stop")
                .next_state;
        }
        // These local transitions are valid by construction. Reserve two revisions for
        // projecting checking/failure so every mutation remains newer than its predecessor.
        let checking = base
            .decide(ObservedResourceCommand::Begin {
                expected_revision: self.revision,
                operation: StateOperation::Check,
                operation_id: "startup-recovery".into(),
                started_at: self.updated_at,
            })
            .expect("Ready accepts Begin")
            .next_state;
        match &self.scan {
            ScanState::Failed(error) => {
                checking
                    .decide(ObservedResourceCommand::Fail {
                        expected_revision: checking.revision(),
                        failed_at: self.updated_at,
                        error: error.clone(),
                    })
                    .expect("Refreshing accepts Fail")
                    .next_state
            }
            ScanState::Idle | ScanState::Stopped | ScanState::Checking => checking,
        }
    }
}

#[derive(Debug, Clone)]
pub struct StudioRecoveryRegistry {
    inner: Arc<Mutex<State>>,
}

enum ThreadAccess {
    Read,
    Execute,
}

impl StudioRecoveryRegistry {
    pub(crate) fn ensure_thread_read_access(
        &self,
        thread: &pl_protocol::Thread,
    ) -> anyhow::Result<()> {
        self.ensure_thread_access(thread, ThreadAccess::Read)
    }

    pub(crate) fn ensure_thread_execution_access(
        &self,
        thread: &pl_protocol::Thread,
    ) -> anyhow::Result<()> {
        self.ensure_thread_access(thread, ThreadAccess::Execute)
    }

    fn ensure_thread_access(
        &self,
        thread: &pl_protocol::Thread,
        access: ThreadAccess,
    ) -> anyhow::Result<()> {
        use crate::{StudioRecoveryImpact as Impact, StudioRecoveryIssueScope as Scope};
        let issues = self
            .snapshot()
            .into_iter()
            .filter(|issue| {
                let applies = match issue.scope {
                    Scope::Application => true,
                    Scope::Project => false,
                    Scope::Thread => {
                        issue.thread_id.as_deref() == Some(thread.id.as_str())
                            && (issue.project_id.is_none()
                                || thread.project_id.is_empty()
                                || issue.project_id.as_deref() == Some(thread.project_id.as_str()))
                    }
                };
                applies
                    && match issue.impact {
                        Impact::Advisory => false,
                        Impact::ExecutionBlocked => matches!(access, ThreadAccess::Execute),
                        Impact::AccessBlocked => true,
                    }
            })
            .collect::<Vec<_>>();
        if issues.is_empty() {
            return Ok(());
        }
        Err(pl_protocol::studio::StudioError::new(
            pl_protocol::studio::StudioErrorCode::Unavailable,
            match access {
                ThreadAccess::Execute => "Thread execution is blocked by recovery",
                ThreadAccess::Read => "Thread access is blocked by recovery",
            },
            true,
        )
        .with_details(serde_json::to_value(issues)?)
        .into())
    }

    pub(crate) fn ensure_project_execution_access(&self, project_id: &str) -> anyhow::Result<()> {
        use crate::{StudioRecoveryImpact as Impact, StudioRecoveryIssueScope as Scope};
        let issues = self
            .snapshot()
            .into_iter()
            .filter(|issue| {
                (issue.scope == Scope::Application
                    || (issue.scope == Scope::Project
                        && issue.project_id.as_deref() == Some(project_id)))
                    && issue.impact != Impact::Advisory
            })
            .collect::<Vec<_>>();
        if issues.is_empty() {
            return Ok(());
        }
        Err(pl_protocol::studio::StudioError::new(
            pl_protocol::studio::StudioErrorCode::Unavailable,
            "Project execution preparation is blocked by recovery",
            true,
        )
        .with_details(serde_json::json!({"projectId": project_id, "issues": issues}))
        .into())
    }

    pub(crate) fn apply_execution_workspace_check(
        &self,
        thread: &pl_protocol::Thread,
        error: Option<&anyhow::Error>,
    ) -> ObservedResource<Vec<StudioRecoveryIssue>> {
        let id = format!("execution-workspace:{}", thread.id);
        let issue = error.map(|error| Self::execution_workspace_issue(thread, error));
        self.update_if_current(&id, issue, || true, |_| {});
        self.state()
    }

    pub(crate) fn execution_workspace_issue(
        thread: &pl_protocol::Thread,
        error: &anyhow::Error,
    ) -> StudioRecoveryIssue {
        StudioRecoveryIssue {
            id: format!("execution-workspace:{}", thread.id),
            scope: crate::StudioRecoveryIssueScope::Thread,
            category: crate::StudioRecoveryIssueCategory::Repository,
            impact: crate::StudioRecoveryImpact::ExecutionBlocked,
            action: crate::StudioRecoveryIssueAction::Retry,
            project_id: Some(thread.project_id.clone()),
            thread_id: Some(thread.id.clone()),
            message: format!("Thread execution workspace is unavailable: {error:#}"),
            worktree: None,
        }
    }

    pub fn new() -> Self {
        Self {
            inner: Arc::new(Mutex::new(State {
                issues: Vec::new(),
                removed: BTreeSet::new(),
                retired_threads: BTreeSet::new(),
                scan: ScanState::Idle,
                revision: 0,
                updated_at: unix_seconds(),
            })),
        }
    }
    pub fn snapshot(&self) -> Vec<StudioRecoveryIssue> {
        self.inner
            .lock()
            .expect("recovery lock poisoned")
            .issues
            .clone()
    }
    pub(crate) fn state(&self) -> ObservedResource<Vec<StudioRecoveryIssue>> {
        self.inner
            .lock()
            .expect("recovery lock poisoned")
            .snapshot()
    }
    pub(crate) fn begin(&self) {
        let mut inner = self.inner.lock().expect("recovery lock poisoned");
        inner.removed.clear();
        inner.retired_threads.clear();
        inner.scan = ScanState::Checking;
        inner.touch();
    }
    pub(crate) fn stop(&self) {
        let mut inner = self.inner.lock().expect("recovery lock poisoned");
        inner.scan = ScanState::Stopped;
        inner.touch();
    }
    pub(crate) fn fail(&self, error: StateError) {
        let mut inner = self.inner.lock().expect("recovery lock poisoned");
        inner.scan = ScanState::Failed(error);
        inner.touch();
    }
    pub fn replace(&self, issues: Vec<StudioRecoveryIssue>) {
        let mut inner = self.inner.lock().expect("recovery lock poisoned");
        // Keep observer-owned issues; merge only the audit's categories and never resurrect
        // a result removed by a user or retired owner while this scan was in flight.
        inner.issues.retain(|issue| {
            issue.id.starts_with("tool-refresh:") || issue.id.starts_with("tool-cleanup:")
        });
        for issue in issues {
            if !inner.removed.contains(&issue.id)
                && !issue
                    .thread_id
                    .as_ref()
                    .is_some_and(|id| inner.retired_threads.contains(id))
            {
                inner.issues.push(issue);
            }
        }
        inner.scan = ScanState::Idle;
        inner.touch();
    }
    pub(in crate::studio) fn update_if_current(
        &self,
        issue_id: &str,
        issue: Option<StudioRecoveryIssue>,
        is_current: impl FnOnce() -> bool,
        publish: impl FnOnce(ObservedResource<Vec<StudioRecoveryIssue>>),
    ) {
        let mut inner = self.inner.lock().expect("recovery lock poisoned");
        if !is_current() {
            return;
        }
        if issue.is_none() && !inner.issues.iter().any(|current| current.id == issue_id) {
            return;
        }
        inner.issues.retain(|current| current.id != issue_id);
        if let Some(issue) = issue {
            inner.issues.push(issue);
        }
        inner.touch();
        publish(inner.snapshot());
    }
    pub(crate) fn retire_thread(
        &self,
        thread_id: &str,
    ) -> ObservedResource<Vec<StudioRecoveryIssue>> {
        let mut inner = self.inner.lock().expect("recovery lock poisoned");
        inner.retired_threads.insert(thread_id.into());
        inner
            .issues
            .retain(|issue| issue.thread_id.as_deref() != Some(thread_id));
        inner.touch();
        inner.snapshot()
    }
    pub fn remove(&self, issue_id: &str) -> ObservedResource<Vec<StudioRecoveryIssue>> {
        let mut inner = self.inner.lock().expect("recovery lock poisoned");
        inner.removed.insert(issue_id.into());
        inner.issues.retain(|current| current.id != issue_id);
        inner.touch();
        inner.snapshot()
    }
}
impl Default for StudioRecoveryRegistry {
    fn default() -> Self {
        Self::new()
    }
}

//! Recovery issues and scan lifecycle share one owner and revision.
use crate::studio::{StudioRecoveryIssue, ids::unix_seconds};
use pl_protocol::{ObservedResource, ObservedResourceCommand, StateError, StateOperation};
use std::{
    collections::BTreeSet,
    sync::{Arc, Mutex},
};

pub(in crate::studio) mod diagnostic;

#[derive(Debug, Clone)]
enum ScanState {
    Idle,
    Stopped,
    Checking,
    Failed(Arc<anyhow::Error>),
}
#[derive(Debug)]
struct State {
    issues: Vec<StudioRecoveryIssue>,
    removed: BTreeSet<String>,
    retired_threads: BTreeSet<String>,
    scan: ScanState,
    revision: u64,
    updated_at: i64,
    projection: Option<Arc<super::runtime::recovery::RecoverySource>>,
}
impl State {
    fn touch(&mut self) {
        self.revision = self.revision.saturating_add(3);
        self.updated_at = unix_seconds();
        if let Some(source) = &self.projection {
            source.publish(self.snapshot());
        }
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
                        error: StateError {
                            code: "recoveryCheckFailed".into(),
                            message: diagnostic::bounded(&format!(
                                "Recovery scan failed: {}",
                                diagnostic::failure(error.as_ref().as_ref())
                            )),
                            retryable: true,
                        },
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
impl StudioRecoveryRegistry {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(Mutex::new(State {
                issues: Vec::new(),
                removed: BTreeSet::new(),
                retired_threads: BTreeSet::new(),
                scan: ScanState::Idle,
                revision: 0,
                updated_at: unix_seconds(),
                projection: None,
            })),
        }
    }
    pub(in crate::studio) fn attach_source(
        &self,
        source: Arc<super::runtime::recovery::RecoverySource>,
    ) {
        let mut state = self.inner.lock().expect("recovery lock poisoned");
        source.publish(state.snapshot());
        state.projection = Some(source);
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
    pub(crate) fn fail(&self, error: anyhow::Error) {
        let mut inner = self.inner.lock().expect("recovery lock poisoned");
        inner.scan = ScanState::Failed(Arc::new(error));
        inner.touch();
    }
    pub fn replace(&self, issues: Vec<StudioRecoveryIssue>) {
        let mut inner = self.inner.lock().expect("recovery lock poisoned");
        // Keep observer-owned issues; merge only the audit's categories and never resurrect
        // a result removed by a user or retired owner while this scan was in flight.
        inner.issues.retain(|issue| {
            issue.id.starts_with("tool-refresh:") || issue.id.starts_with("tool-cleanup:")
        });
        for mut issue in issues {
            issue.message = diagnostic::bounded(&issue.message);
            if !inner.removed.contains(&issue.id)
                && !issue.thread_id.as_ref().is_some_and(|id| {
                    inner.retired_threads.contains(id) && !is_worktree_issue(&issue)
                })
            {
                inner.issues.push(issue);
            }
        }
        inner.scan = ScanState::Idle;
        inner.touch();
    }
    /// The current-owner check, mutation and typed source publication share this boundary.
    /// Producers do not need a second transport callback or a full-table return payload.
    pub(in crate::studio) fn update_if_current(
        &self,
        issue_id: &str,
        issue: Option<StudioRecoveryIssue>,
        is_current: impl FnOnce() -> bool,
    ) {
        let mut inner = self.inner.lock().expect("recovery lock poisoned");
        if !is_current() {
            return;
        }
        if issue.is_none() && !inner.issues.iter().any(|current| current.id == issue_id) {
            return;
        }
        inner.issues.retain(|current| current.id != issue_id);
        if let Some(mut issue) = issue {
            issue.message = diagnostic::bounded(&issue.message);
            inner.issues.push(issue);
        }
        inner.touch();
    }
    pub(crate) fn retire_thread(&self, thread_id: &str) {
        let mut inner = self.inner.lock().expect("recovery lock poisoned");
        inner.retired_threads.insert(thread_id.into());
        inner.issues.retain(|issue| {
            issue.thread_id.as_deref() != Some(thread_id) || is_worktree_issue(issue)
        });
        inner.touch();
    }
    pub fn remove(&self, issue_id: &str) {
        let mut inner = self.inner.lock().expect("recovery lock poisoned");
        inner.removed.insert(issue_id.into());
        inner.issues.retain(|current| current.id != issue_id);
        inner.touch();
    }
}

fn is_worktree_issue(issue: &StudioRecoveryIssue) -> bool {
    issue.id.starts_with("worktree-lease-")
}
impl Default for StudioRecoveryRegistry {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::agent::worktree::{RemoteClientError, RemoteExecutionError, WorktreeError};

    #[test]
    fn publication_preserves_typed_failure_facts_without_free_form_secrets() {
        let secret = format!(
            "ssh://name:credential@example.invalid/private/{}",
            "秘密".repeat(3000)
        );
        let cases = [
            (
                WorktreeError::LocalIo {
                    operation: "inspect worktree directory",
                    source: std::io::Error::new(
                        std::io::ErrorKind::PermissionDenied,
                        secret.clone(),
                    ),
                },
                vec!["inspect worktree directory", "PermissionDenied"],
            ),
            (
                WorktreeError::Remote {
                    operation: "open remote worktree",
                    source: RemoteClientError::Protocol(secret.clone()),
                },
                vec!["open remote worktree", "SSH Protocol"],
            ),
            (
                WorktreeError::RemoteExecution {
                    args: "worktree list --porcelain".into(),
                    source: RemoteExecutionError::Spawn {
                        source: RemoteClientError::AuthenticationFailed(
                            pl_tool::remote::SshAuthFailure::new(
                                secret.clone(),
                                vec!["password".into()],
                            ),
                        ),
                    },
                },
                vec!["worktree list", "spawn", "SSH AuthenticationFailed"],
            ),
            (
                WorktreeError::GitExited {
                    args: "worktree list --porcelain".into(),
                    exit_code: 128,
                    stderr: format!("No such file or directory: {secret}"),
                },
                vec![
                    "worktree list",
                    "128",
                    "does not establish worktree absence",
                ],
            ),
        ];
        for (cause, facts) in cases {
            let registry = StudioRecoveryRegistry::new();
            registry.begin();
            registry.fail(anyhow::Error::new(cause).context(secret.clone()));
            let ObservedResource::Degraded(state) = registry.state() else {
                panic!("failed scan keeps its existing Recovery value");
            };
            let message = &state.error().message;
            assert_eq!(state.error().code, "recoveryCheckFailed");
            assert!(message.chars().count() <= 2048);
            assert!(
                !message.contains("credential")
                    && !message.contains("example.invalid")
                    && !message.contains("秘密")
            );
            for fact in facts {
                assert!(
                    message.contains(fact),
                    "known fact {fact} lost in {message}"
                );
            }
            let inner = registry.inner.lock().unwrap();
            assert!(
                matches!(&inner.scan, ScanState::Failed(cause) if cause.downcast_ref::<WorktreeError>().is_some()),
                "publication must retain the original typed cause, not just its safe message"
            );
        }
        let registry = StudioRecoveryRegistry::new();
        let error = pl_protocol::studio::StudioError::internal();
        let correlation = error.correlation_id.clone();
        registry.fail(error.into());
        let ObservedResource::Degraded(state) = registry.state() else {
            panic!("failed scan");
        };
        assert!(state.error().message.contains(&correlation));
    }

    #[test]
    fn issue_publication_bounds_unicode_without_changing_typed_workspace_paths() {
        let registry = StudioRecoveryRegistry::new();
        let issue = crate::StudioRecoveryIssue {
            id: "bounded-recovery".into(),
            scope: crate::StudioRecoveryIssueScope::Project,
            category: crate::StudioRecoveryIssueCategory::Repository,
            action: crate::StudioRecoveryIssueAction::Retry,
            project_id: Some("project".into()),
            thread_id: None,
            message: "诊".repeat(2050),
            worktree: Some(crate::StudioWorktreeRecoveryPreview {
                inspection: crate::StudioWorktreeInspection::Unavailable,
                owner_kind: crate::StudioRecoveryWorktreeOwner::Session,
                owner_thread_id: "root".into(),
                lease_revision: 7,
                state: "preserved".into(),
                repository_root: "/expected/repository".into(),
                path: "/expected/原工作树".into(),
                branch: "pure-session-root".into(),
                base_commit: "original".into(),
                head_commit: None,
                dirty: None,
                changed_files: None,
            }),
        };
        registry.replace(vec![issue.clone()]);
        assert_eq!(registry.snapshot()[0].message, "诊".repeat(2048));
        registry.update_if_current(&issue.id, Some(issue.clone()), || true);
        let state = registry.state();
        let view = state.value().expect("published Recovery");
        assert_eq!(view[0].message, "诊".repeat(2048));
        assert_eq!(view[0].worktree, issue.worktree);
        assert_eq!(view[0].action, issue.action);
    }
}

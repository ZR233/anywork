use std::collections::BTreeSet;
use std::path::Path;
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::Result;

use crate::agent::worktree::{
    LocalWorktreeBackend, RemoteWorktreeBackend, WorktreeBackend, WorktreeError, WorktreeHandle,
    WorktreeManager,
};
use crate::studio::agent_host::worktree_lease::{WorktreeLease, WorktreeLeaseState};
use crate::studio::{
    StudioRecoveryIssue, StudioRecoveryIssueAction, StudioRecoveryIssueCategory,
    StudioRecoveryIssueScope, StudioRecoveryWorktreeOwner, StudioWorktreeInspection,
};

use super::super::StudioRuntime;
use crate::studio::recovery_registry::diagnostic;

fn background_git_command() -> tokio::process::Command {
    let mut command = tokio::process::Command::new("git");
    command.env("LC_ALL", "C");
    #[cfg(windows)]
    command.args(["-c", "core.longpaths=true"]);
    pl_remote_helper::process::configure_background_command(&mut command);
    command
}

/// Git's existing CLI discovery has no structured NotRepository result. Only these complete
/// C-locale discovery answers prove an ordinary non-Git project; other exit-128 failures do not.
fn is_non_git_project(output: &std::process::Output) -> bool {
    if output.status.code() != Some(128) || !output.stdout.is_empty() {
        return false;
    }
    let Ok(stderr) = std::str::from_utf8(&output.stderr) else {
        return false;
    };
    let mut lines = stderr.lines();
    let Some(discovery) = lines.next() else {
        return false;
    };
    if discovery == "fatal: not a git repository (or any of the parent directories): .git" {
        return lines.next().is_none();
    }
    discovery
        .strip_prefix("fatal: not a git repository (or any parent up to mount point ")
        .and_then(|mount| mount.strip_suffix(')'))
        .is_some_and(|mount| !mount.is_empty())
        && lines.next()
            == Some("Stopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set).")
        && lines.next().is_none()
}

fn discovery_git_failure(args: &str, output: std::process::Output) -> WorktreeError {
    let args = args.to_owned();
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    match output.status.code() {
        Some(exit_code) => WorktreeError::GitExited {
            args,
            exit_code,
            stderr,
        },
        None => WorktreeError::GitStatusUnknown { args, stderr },
    }
}

impl StudioRuntime {
    pub(in crate::studio::runtime) async fn append_worktree_recovery_issues(
        &self,
        recovery_issues: &mut Vec<StudioRecoveryIssue>,
    ) -> Result<()> {
        for lease in self.agent_facility.worktrees.snapshot() {
            // Only resources that need manual handling enter the cleanup entry: a healthy
            // `active` (or in-creation `prepared`) lease owned by a registered Thread is
            // never reported, so a stale card can never target a live workspace.
            if let Some(issue) = self.worktree_recovery_issue(&lease).await {
                recovery_issues.push(issue);
            }
        }
        self.append_unregistered_worktrees(recovery_issues).await?;
        Ok(())
    }

    /// Discover local resources whose last lease may have been lost with an unflushed process.
    /// Unknown ownership is diagnostic only: no inferred lease or automatic deletion.
    async fn append_unregistered_worktrees(
        &self,
        issues: &mut Vec<StudioRecoveryIssue>,
    ) -> Result<()> {
        let known = self
            .agent_facility
            .worktrees
            .snapshot()
            .into_iter()
            .filter(|lease| lease.state != WorktreeLeaseState::Cleaned)
            .map(|lease| normalized_local_path(Path::new(&lease.path)))
            .collect::<BTreeSet<_>>();
        for project in self.agent_facility.product_events.project_snapshot().await {
            if project.ssh_alias.is_some() {
                continue;
            }
            let project_path = PathBuf::from(&project.path);
            let root = background_git_command()
                .args(["rev-parse", "--show-toplevel"])
                .current_dir(&project_path)
                .output()
                .await
                .map_err(|source| WorktreeError::LocalIo {
                    operation: "discover worktrees: launch git repository discovery",
                    source,
                })?;
            if !root.status.success() {
                if is_non_git_project(&root) {
                    continue;
                }
                return Err(discovery_git_failure("rev-parse --show-toplevel", root).into());
            }
            let root = String::from_utf8(root.stdout)?;
            if root.trim().is_empty() {
                return Err(WorktreeError::GitStatusUnknown {
                    args: "rev-parse --show-toplevel".into(),
                    stderr: "repository discovery returned an empty root".into(),
                }
                .into());
            }
            let root = normalized_local_path(Path::new(root.trim()));
            let managed = root.join(".anywork/worktrees");
            let mut found = BTreeSet::new();
            let parents = match tokio::fs::read_dir(&managed).await {
                Ok(parents) => Some(parents),
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
                Err(source) => {
                    return Err(WorktreeError::LocalIo {
                        operation: "discover worktrees: read managed directory",
                        source,
                    }
                    .into());
                }
            };
            if let Some(mut parents) = parents {
                while let Some(parent) =
                    parents
                        .next_entry()
                        .await
                        .map_err(|source| WorktreeError::LocalIo {
                            operation: "discover worktrees: read managed directory entry",
                            source,
                        })?
                {
                    if !parent
                        .file_type()
                        .await
                        .map_err(|source| WorktreeError::LocalIo {
                            operation: "discover worktrees: inspect parent directory entry",
                            source,
                        })?
                        .is_dir()
                    {
                        continue;
                    }
                    let mut children =
                        tokio::fs::read_dir(parent.path()).await.map_err(|source| {
                            WorktreeError::LocalIo {
                                operation: "discover worktrees: read parent directory",
                                source,
                            }
                        })?;
                    while let Some(child) =
                        children
                            .next_entry()
                            .await
                            .map_err(|source| WorktreeError::LocalIo {
                                operation: "discover worktrees: read child directory entry",
                                source,
                            })?
                    {
                        found.insert(normalized_local_path(&child.path()));
                    }
                }
            }
            let registered = background_git_command()
                .args(["worktree", "list", "--porcelain", "-z"])
                .current_dir(&root)
                .output()
                .await
                .map_err(|source| WorktreeError::LocalIo {
                    operation: "discover worktrees: launch git worktree list",
                    source,
                })?;
            if !registered.status.success() {
                return Err(
                    discovery_git_failure("worktree list --porcelain -z", registered).into(),
                );
            }
            for field in registered.stdout.split(|byte| *byte == 0) {
                if let Some(path) = field.strip_prefix(b"worktree ") {
                    let path = normalized_local_path(Path::new(std::str::from_utf8(path)?));
                    if path.starts_with(&managed) {
                        found.insert(path);
                    }
                }
            }
            for path in found.difference(&known) {
                issues.push(StudioRecoveryIssue {
                    id: format!("unregistered-worktree:{}:{}", project.id, pl_core::context::content_hash(path.to_string_lossy().as_bytes())),
                    scope: StudioRecoveryIssueScope::Project, category: StudioRecoveryIssueCategory::Repository,
                    action: StudioRecoveryIssueAction::Retry, project_id: Some(project.id.clone()), thread_id: None,
                    message: "Unregistered managed worktree preserved; ownership must be inspected before explicit cleanup".into(), worktree: None,
                });
            }
        }
        Ok(())
    }

    /// Recovery issue for a lease that needs manual handling, or `None` when the resource
    /// is still used by a registered owner.
    async fn worktree_recovery_issue(&self, lease: &WorktreeLease) -> Option<StudioRecoveryIssue> {
        // 创建中的 lease 是进程内正在工作的资源：既不是崩溃遗留，也不可人工处置。
        if self
            .agent_facility
            .worktrees
            .is_creating(&lease.owner_thread_id)
        {
            return None;
        }
        if lease.state == WorktreeLeaseState::Cleaned {
            return None;
        }
        let facts = self.worktree_issue_facts(lease).await;
        if lease.state != WorktreeLeaseState::Preserved
            && matches!(facts.owner, Ok(WorktreeOwnerFacts { live: true, .. }))
            && facts.inspection() == StudioWorktreeInspection::Available
        {
            return None;
        }
        Some(self.worktree_issue(lease, &facts, worktree_state_message(lease)))
    }

    /// Observation never changes lease state. Existence is established only by backend stat.
    async fn worktree_issue_facts(&self, lease: &WorktreeLease) -> WorktreeIssueFacts {
        let observation = match lease.validate_identity() {
            Err(_) => Err(WorktreeError::IdentityMismatch(
                "the durable lease does not match its owner-derived path and branch".into(),
            )),
            Ok(()) => match self.worktree_manager(lease) {
                Ok(manager) => manager.preview(&worktree_handle(lease)).await,
                Err(error) => Err(error),
            },
        };
        WorktreeIssueFacts {
            observation,
            owner: self.worktree_owner_facts(&lease.owner_thread_id).await,
        }
    }

    fn worktree_issue(
        &self,
        lease: &WorktreeLease,
        facts: &WorktreeIssueFacts,
        message: String,
    ) -> StudioRecoveryIssue {
        let preview = facts.observation.as_ref().ok();
        let changed_files = preview.map(|preview| preview.changed_files.clone());
        let mut message = message;
        match &facts.observation {
            Ok(_) => {}
            Err(WorktreeError::Missing) => message
                .push_str("; worktree path is missing; this inspection does not mark it cleaned"),
            Err(WorktreeError::IdentityMismatch(_)) => {
                message.push_str(
                    "; worktree identity conflicts with its lease; cleanup is not authorized by this inspection",
                );
            }
            Err(_) => message.push_str(
                "; worktree could not be confirmed; cleanup is not authorized by this inspection",
            ),
        }
        if let Err(error) = &facts.observation {
            message.push_str("; ");
            message.push_str(&worktree_error_diagnostic(error));
        }
        match &facts.owner {
            Ok(owner) if !owner.exists => {
                message.push_str("; no published Thread remains for this lease")
            }
            Ok(owner) if owner.live => {
                message.push_str("; an active Thread still owns this workspace")
            }
            Ok(_) => {}
            Err(error) => {
                message.push_str("; cannot confirm workspace owner: ");
                message.push_str(&diagnostic::failure(error.as_ref()));
            }
        }
        let can_cleanup = matches!(&facts.owner, Ok(WorktreeOwnerFacts { live: false, .. }))
            && preview.is_some_and(|preview| preview.changed_files.is_empty())
            && !matches!(
                lease.state,
                WorktreeLeaseState::Cleaned | WorktreeLeaseState::CleanupRequested
            )
            && !self
                .agent_facility
                .worktrees
                .is_creating(&lease.owner_thread_id);
        StudioRecoveryIssue {
            id: worktree_issue_id(&lease.owner_thread_id),
            scope: StudioRecoveryIssueScope::Thread,
            category: StudioRecoveryIssueCategory::Repository,
            action: if can_cleanup {
                StudioRecoveryIssueAction::CleanupWorktree
            } else {
                StudioRecoveryIssueAction::Retry
            },
            project_id: Some(lease.project_id.clone()),
            // The issue belongs to the Thread that owns the workspace. A child's site must be resolvable
            // — and retirable — by that child alone; attributing it to the root made activation unable
            // to clear its own entry and let a root activation clear a different child's entry.
            thread_id: Some(lease.owner_thread_id.clone()),
            message: diagnostic::bounded(&message),
            worktree: Some(crate::StudioWorktreeRecoveryPreview {
                inspection: facts.inspection(),
                owner_kind: recovery_owner(lease.owner_kind),
                owner_thread_id: lease.owner_thread_id.clone(),
                lease_revision: lease.revision,
                state: lease.state.label().to_string(),
                repository_root: lease.repository_root.clone(),
                path: lease.path.clone(),
                branch: lease.branch.clone(),
                base_commit: lease.base_commit.clone(),
                head_commit: preview.map(|preview| preview.head.clone()),
                dirty: preview.map(|preview| !preview.changed_files.is_empty()),
                changed_files,
            }),
        }
    }

    pub async fn cleanup_preserved_worktree(
        &self,
        owner_kind: StudioRecoveryWorktreeOwner,
        owner_thread_id: &str,
        expected_lease_revision: u64,
    ) -> Result<()> {
        let runtime = self.clone();
        let owner_thread_id = owner_thread_id.to_owned();
        self.run_thread_lifecycle_operation(async move {
            runtime
                .cleanup_preserved_worktree_owned(
                    owner_kind,
                    &owner_thread_id,
                    expected_lease_revision,
                )
                .await
        })
        .await
    }

    /// The retained lifecycle worker owns admission and the owner guard through every flush/Git
    /// await. Dropping the public waiter cannot abandon an admitted cleanupRequested lease.
    async fn cleanup_preserved_worktree_owned(
        &self,
        owner_kind: StudioRecoveryWorktreeOwner,
        owner_thread_id: &str,
        expected_lease_revision: u64,
    ) -> Result<()> {
        // Physical cleanup is serialized with every other product operation on this owner: a restore or
        // archive holds the lifecycle admission, and activation, submission and stopping hold the
        // per-Thread operation guard. Both are taken here in the same order archiving uses (lifecycle
        // first), so a cleanup can neither race a restore that revives the Thread and reuses the site
        // nor an activation that is already running in it.
        let _operation = self.threads.agent_operation(owner_thread_id).await;
        // Re-read the lease *after* the guards: the facts the card was rendered from may already be
        // stale, and every check below must run against the state that is true while nothing else can
        // change it.
        let mut lease = self
            .agent_facility
            .worktrees
            .get(owner_thread_id)
            .ok_or_else(|| anyhow::anyhow!("worktree lease does not exist"))?;
        // 创建中的 lease 属于进程内正在进行的创建，陈旧卡片不得删除它。
        anyhow::ensure!(
            !self.agent_facility.worktrees.is_creating(owner_thread_id),
            "worktree lease is still being created"
        );
        anyhow::ensure!(
            recovery_owner(lease.owner_kind) == owner_kind,
            "worktree lease ownership does not match the requested source"
        );
        anyhow::ensure!(
            lease.revision == expected_lease_revision,
            "worktree lease revision conflict: expected {expected_lease_revision}, actual {}",
            lease.revision
        );
        anyhow::ensure!(
            lease.state != WorktreeLeaseState::Cleaned
                && lease.state != WorktreeLeaseState::CleanupRequested,
            "worktree lease is already cleaned"
        );
        // Server-side precondition: a stale or forged card must never delete a workspace a
        // live Thread still owns. The lease state cannot grant that: a `preserved` site may be a
        // directory a running child is using, so only a site whose owner Thread is no longer live is
        // eligible for explicit cleanup.
        let handle = worktree_handle(&lease);
        let preflight = async {
            anyhow::ensure!(
                !self
                    .worktree_owner_facts(&lease.owner_thread_id)
                    .await?
                    .live,
                "worktree lease is still owned by a live Thread"
            );
            lease.validate_identity()?;
            let manager = self.worktree_manager(&lease)?;
            let status = manager.preview(&handle).await?;
            anyhow::ensure!(
                status.changed_files.is_empty(),
                "cleanup refused tracked, untracked or ignored local content"
            );
            Ok::<_, anyhow::Error>(manager)
        }
        .await;
        let manager = match preflight {
            Ok(manager) => manager,
            Err(error) => {
                self.publish_worktree_recovery(None, &lease).await;
                return Err(error);
            }
        };
        // Persist intent before the destructive operation; removal never deletes the branch.
        lease.transition(WorktreeLeaseState::CleanupRequested);
        self.agent_facility.worktrees.record(lease.clone())?;
        if let Err(error) = self.agent_facility.worktrees.flush().await {
            // No destructive operation was attempted. Keep a retryable owner fact and a fresh CAS
            // card rather than stranding the process-local lease at cleanupRequested.
            lease.transition(WorktreeLeaseState::Preserved);
            self.agent_facility.worktrees.record(lease.clone())?;
            self.publish_worktree_recovery(
                Some("cleanup intent could not be saved; no removal was attempted"),
                &lease,
            )
            .await;
            return Err(error);
        }
        if let Err(error) = manager.remove_clean(&handle).await {
            lease.transition(WorktreeLeaseState::Preserved);
            self.agent_facility.worktrees.record(lease.clone())?;
            // 回落改变了 lease revision：必须同步刷新卡片，否则下一次显式重试会被 CAS 拒绝。
            self.publish_worktree_recovery(Some(&worktree_error_diagnostic(&error)), &lease)
                .await;
            self.agent_facility.worktrees.flush().await?;
            return Err(error.into());
        }
        lease.transition(WorktreeLeaseState::Cleaned);
        self.agent_facility.worktrees.record(lease.clone())?;
        self.agent_facility.worktrees.flush().await?;
        self.recovery.remove(&worktree_issue_id(owner_thread_id));
        Ok(())
    }

    fn worktree_manager(&self, lease: &WorktreeLease) -> Result<WorktreeManager, WorktreeError> {
        let repository_root = PathBuf::from(&lease.repository_root);
        let backend: Arc<dyn WorktreeBackend> = match lease.ssh_alias.as_deref() {
            Some(server_id) => Arc::new(RemoteWorktreeBackend::new(
                self.ssh_manager.clone(),
                server_id,
                repository_root.clone(),
            )?),
            None => Arc::new(LocalWorktreeBackend::default()),
        };
        Ok(WorktreeManager::new(repository_root, backend))
    }

    /// Hot facts precede write-behind rows; query failure cannot prove the owner inactive.
    async fn worktree_owner_facts(&self, thread_id: &str) -> Result<WorktreeOwnerFacts> {
        // A retained execution/shutdown owner is stronger evidence than a missing or archived
        // directory row. Never infer inactivity while an in-process incarnation still exists.
        if self.threads.observed_thread(thread_id).is_some() {
            return Ok(WorktreeOwnerFacts {
                exists: true,
                live: true,
            });
        }
        if let Some(thread) = self
            .agent_facility
            .product_events
            .thread_snapshot(thread_id)
        {
            return Ok(WorktreeOwnerFacts {
                exists: true,
                live: !thread.archived,
            });
        }
        let record = self.store.read_thread_association(thread_id).await?;
        Ok(WorktreeOwnerFacts {
            exists: record.is_some(),
            live: record
                .is_some_and(|record| record.visibility == crate::studio::ThreadVisibility::Active),
        })
    }

    /// Publishes the Recovery a failed `worktree` session activation must leave behind.
    ///
    /// The issue carries revision, branch, base and path whenever a durable lease still
    /// exists; a missing lease is reported without inventing ownership.
    pub(in crate::studio::runtime) async fn publish_session_workspace_issue(
        &self,
        thread: &pl_protocol::Thread,
        error: &anyhow::Error,
    ) {
        let issue_id = worktree_issue_id(&thread.id);
        let without_lease = || StudioRecoveryIssue {
            id: issue_id.clone(),
            scope: StudioRecoveryIssueScope::Thread,
            category: StudioRecoveryIssueCategory::Repository,
            action: StudioRecoveryIssueAction::Retry,
            project_id: Some(thread.project_id.clone()),
            thread_id: Some(thread.id.clone()),
            message: String::new(),
            worktree: None,
        };
        // 只要该 owner 还有 durable lease，就必须发布它的完整 preview（不论归属类型）；
        // 只有确实没有 lease 时才退化为无 preview 的诊断。
        let mut issue = match self.agent_facility.worktrees.get(&thread.id) {
            Some(lease) => {
                let facts = self.worktree_issue_facts(&lease).await;
                self.worktree_issue(&lease, &facts, String::new())
            }
            None => without_lease(),
        };
        issue.id = issue_id.clone();
        issue.thread_id = Some(thread.id.clone());
        let diagnostic = diagnostic::failure(error.as_ref());
        issue.message = diagnostic::bounded(&format!(
            "Thread cannot use its saved workspace and was not moved to the main workspace: {diagnostic}; {}",
            issue.message
        ));
        self.recovery
            .update_if_current(&issue_id, Some(issue), || true);
    }

    /// Publishes (or refreshes) the Recovery of one worktree lease from its **current**
    /// durable record; both ownership kinds share this entry.
    ///
    /// A creation failure that converges the lease to `preserved` must be visible
    /// immediately with its ownership, revision and preview instead of waiting for the
    /// next startup audit. The lease issue id is reused, so an earlier diagnostic for the
    /// same Thread is replaced rather than duplicated.
    pub(in crate::studio::runtime) async fn publish_worktree_recovery(
        &self,
        reason: Option<&str>,
        lease: &WorktreeLease,
    ) {
        let facts = self.worktree_issue_facts(lease).await;
        let state_message = worktree_state_message(lease);
        let message = match reason.map(str::trim).filter(|reason| !reason.is_empty()) {
            Some(reason) => format!("{reason}; {state_message}"),
            None => state_message,
        };
        let issue = self.worktree_issue(lease, &facts, message);
        let issue_id = issue.id.clone();
        self.recovery
            .update_if_current(&issue_id, Some(issue), || true);
    }

    pub(in crate::studio::runtime) async fn append_unavailable_project_recovery_issues(
        &self,
        recovery_issues: &mut Vec<StudioRecoveryIssue>,
    ) -> Result<()> {
        for project in self.store.list_projects().await? {
            if project.ssh_alias.is_some() {
                continue;
            }
            let inspection = async {
                // Availability needs the directory fact, not a Git-root search whose legacy
                // string error discards the original IO kind before this publication boundary.
                let canonical = tokio::fs::canonicalize(&project.path)
                    .await
                    .map_err(|source| WorktreeError::LocalIo {
                        operation: "resolve project workspace",
                        source,
                    })?;
                let metadata = tokio::fs::metadata(canonical).await.map_err(|source| {
                    WorktreeError::LocalIo {
                        operation: "inspect project workspace directory",
                        source,
                    }
                })?;
                if !metadata.is_dir() {
                    return Err(WorktreeError::InvalidResource(
                        "project workspace is not a directory".into(),
                    ));
                }
                Ok::<_, WorktreeError>(())
            }
            .await;
            let Err(error) = inspection else {
                continue;
            };
            if recovery_issues.iter().any(|issue| {
                issue.scope == StudioRecoveryIssueScope::Project
                    && issue.project_id.as_deref() == Some(project.id.as_str())
            }) {
                continue;
            }
            recovery_issues.push(StudioRecoveryIssue {
                id: format!("recovery-issue-project-path-{}", project.id),
                scope: StudioRecoveryIssueScope::Project,
                category: StudioRecoveryIssueCategory::Repository,
                action: StudioRecoveryIssueAction::RemoveProject,
                project_id: Some(project.id),
                thread_id: None,
                message: diagnostic::bounded(&format!(
                    "Project workspace inspection failed: {}",
                    diagnostic::failure(&error)
                )),
                worktree: None,
            });
        }
        Ok(())
    }
}

#[cfg(windows)]
fn normalized_local_path(path: &Path) -> PathBuf {
    let path = dunce::simplified(path);
    PathBuf::from(path.to_string_lossy().replace('\\', "/"))
}

#[cfg(not(windows))]
fn normalized_local_path(path: &Path) -> PathBuf {
    dunce::simplified(path).to_path_buf()
}

fn recovery_owner(
    owner_kind: crate::studio::agent_host::worktree_lease::WorktreeLeaseOwnerKind,
) -> StudioRecoveryWorktreeOwner {
    use crate::studio::agent_host::worktree_lease::WorktreeLeaseOwnerKind;
    match owner_kind {
        WorktreeLeaseOwnerKind::Session => StudioRecoveryWorktreeOwner::Session,
        WorktreeLeaseOwnerKind::Child => StudioRecoveryWorktreeOwner::Child,
    }
}

fn worktree_issue_id(owner_thread_id: &str) -> String {
    format!("worktree-lease-{owner_thread_id}")
}

/// Preview facts of one durable lease; the single source for every worktree Recovery
/// entry so a published preview always matches the recorded lease.
struct WorktreeIssueFacts {
    observation: Result<crate::agent::worktree::WorktreeStatus, WorktreeError>,
    owner: Result<WorktreeOwnerFacts>,
}

struct WorktreeOwnerFacts {
    exists: bool,
    live: bool,
}

impl WorktreeIssueFacts {
    fn inspection(&self) -> StudioWorktreeInspection {
        match &self.observation {
            Ok(_) => StudioWorktreeInspection::Available,
            Err(WorktreeError::Missing) => StudioWorktreeInspection::Missing,
            Err(WorktreeError::IdentityMismatch(_)) => StudioWorktreeInspection::IdentityMismatch,
            Err(_) => StudioWorktreeInspection::Unavailable,
        }
    }
}

fn worktree_error_diagnostic(error: &WorktreeError) -> String {
    error.safe_diagnostic()
}

/// Describes a lease by its actual ownership and state instead of assuming `preserved`.
fn worktree_state_message(lease: &WorktreeLease) -> String {
    format!(
        "Pure {} worktree is {} and needs explicit review; lease_revision={}",
        lease.owner_kind.label(),
        lease.state.label(),
        lease.revision
    )
}

fn worktree_handle(lease: &WorktreeLease) -> WorktreeHandle {
    WorktreeHandle {
        path: PathBuf::from(&lease.path),
        branch: lease.branch.clone(),
        base_commit: lease.base_commit.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::runtime::recovery::StudioRecoverySourceStatusRead;
    use crate::studio::test_support::RuntimeFixture;
    use anyhow::Context;
    use pl_protocol::products::feed::recovery::{RecoveryEvent, RecoveryFrame};
    use pl_protocol::products::identity::ProductReadOrigin;
    use pl_protocol::products::source::ProductSourceStatusReadHeader;
    use pl_protocol::studio::{FeedCloseOutcome, ReadText};

    async fn join_scan(runtime: &StudioRuntime) -> Result<()> {
        let task = runtime.recovery_task.lock().await.clone();
        if let Some(task) = task {
            tokio::time::timeout(std::time::Duration::from_secs(10), task.join())
                .await?
                .map_err(|error| anyhow::anyhow!("fixture recovery task failed: {error}"))?;
        }
        Ok(())
    }

    async fn source_text(read: &StudioRecoverySourceStatusRead, text: ReadText) -> Result<String> {
        match text {
            ReadText::Inline { text } => Ok(text),
            ReadText::Deferred { field_id, .. } => {
                let chunk = read.text(field_id, 0, 8192).await?;
                anyhow::ensure!(
                    chunk.next_offset.is_none(),
                    "bounded diagnostic must fit its read budget"
                );
                Ok(chunk.text)
            }
        }
    }

    /// Runs the real background scan, then reads only the status reference exposed by its
    /// original typed feed. No test publication or diagnostic formatter substitutes for scanning.
    async fn published_scan_diagnostic(runtime: &StudioRuntime) -> Result<Option<String>> {
        join_scan(runtime).await?;
        runtime.start_recovery_scan().await;
        join_scan(runtime).await?;
        let feed = runtime.open_recovery().await?;
        feed.claim()?;
        let mut sent = None;
        assert!(feed.send_pending(|frame| {
            sent = Some(frame);
            Ok(())
        })?);
        let Some(RecoveryFrame::Data {
            delivery_sequence,
            event: RecoveryEvent::Baseline {
                identity, value, ..
            },
        }) = sent
        else {
            anyhow::bail!("scan did not expose its original Recovery baseline");
        };
        feed.ack_through(delivery_sequence)?;
        let read = runtime
            .open_recovery_source_status_read(
                value.header.source.status,
                ProductReadOrigin {
                    owner_epoch: identity.owner_epoch,
                    incarnation: identity.incarnation,
                },
            )
            .await?;
        let diagnostic = match read.header().await? {
            ProductSourceStatusReadHeader::Ready { .. } => None,
            ProductSourceStatusReadHeader::Degraded { error, .. }
            | ProductSourceStatusReadHeader::Failed { error, .. } => {
                assert_eq!(source_text(&read, error.code).await?, "recoveryCheckFailed");
                Some(source_text(&read, error.message).await?)
            }
            other => anyhow::bail!("joined scan has no final source status: {other:?}"),
        };
        assert!(matches!(
            read.close().await.outcome,
            FeedCloseOutcome::Clean
        ));
        feed.request_close();
        Ok(diagnostic)
    }

    #[tokio::test]
    async fn unregistered_scan_skips_plain_projects_but_not_git_discovery_failures() -> Result<()> {
        let fixture = RuntimeFixture::new().await?;
        join_scan(&fixture.runtime).await?;
        let root = PathBuf::from(&fixture.project.path);
        let managed = root.join(".anywork/worktrees");
        assert!(matches!(tokio::fs::symlink_metadata(&managed).await,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound));
        let plain = root.with_file_name("ordinary-private-project");
        tokio::fs::create_dir(&plain).await?;
        fixture.runtime.open_project(&plain).await?;
        assert!(
            published_scan_diagnostic(&fixture.runtime).await?.is_none(),
            "ordinary non-Git projects and an absent managed directory are valid scan results"
        );
        assert!(fixture.runtime.recovery_issues().is_empty());

        // A malformed gitfile also exits 128. It must not be confused with the exact ordinary
        // non-repository answer, even though the project remains a readable directory.
        tokio::fs::write(plain.join(".git"), "private invalid Git metadata\n").await?;
        let failure = fixture
            .runtime
            .append_worktree_recovery_issues(&mut Vec::new())
            .await
            .unwrap_err();
        assert!(matches!(failure.downcast_ref::<WorktreeError>(),
            Some(WorktreeError::GitExited { args, exit_code: 128, .. }) if args == "rev-parse --show-toplevel"));
        let diagnostic = published_scan_diagnostic(&fixture.runtime)
            .await?
            .context("Git failure must be published")?;
        assert!(diagnostic.contains("rev-parse --show-toplevel") && diagnostic.contains("128"));
        assert!(diagnostic.chars().count() <= 2048);
        assert!(!diagnostic.contains(&fixture.project.path));
        assert!(
            !diagnostic.contains("ordinary-private-project")
                && !diagnostic.contains("private invalid Git metadata")
        );
        tokio::fs::remove_file(plain.join(".git")).await?;
        assert!(published_scan_diagnostic(&fixture.runtime).await?.is_none());
        fixture.finish().await
    }

    #[tokio::test]
    async fn unregistered_scan_keeps_diagnostics_on_directory_and_git_launch_failures() -> Result<()>
    {
        let fixture = RuntimeFixture::new().await?;
        join_scan(&fixture.runtime).await?;
        let root = PathBuf::from(&fixture.project.path);
        let managed = root.join(".anywork/worktrees");
        tokio::fs::create_dir_all(managed.join("orphan-root/orphan-child")).await?;
        assert!(published_scan_diagnostic(&fixture.runtime).await?.is_none());
        let issues = fixture.runtime.recovery_issues();
        assert_eq!(issues.len(), 1);
        assert_eq!(issues[0].action, StudioRecoveryIssueAction::Retry);

        // NotADirectory is deterministic for an owned ordinary file, unlike chmod under root.
        // Keep the discovered site intact while blocking only access to its managed parent.
        let retained = root.join(".anywork/retained-private-worktrees");
        tokio::fs::rename(&managed, &retained).await?;
        tokio::fs::write(&managed, "private managed-directory obstruction").await?;
        let failure = fixture
            .runtime
            .append_worktree_recovery_issues(&mut Vec::new())
            .await
            .unwrap_err();
        assert!(matches!(failure.downcast_ref::<WorktreeError>(),
            Some(WorktreeError::LocalIo { operation, source })
                if *operation == "discover worktrees: read managed directory"
                    && source.kind() == std::io::ErrorKind::NotADirectory));
        let diagnostic = published_scan_diagnostic(&fixture.runtime)
            .await?
            .context("directory failure must be published")?;
        assert!(
            diagnostic.contains("read managed directory") && diagnostic.contains("NotADirectory")
        );
        assert!(diagnostic.chars().count() <= 2048);
        assert!(
            !diagnostic.contains(&fixture.project.path)
                && !diagnostic.contains("private managed-directory obstruction")
        );
        assert_eq!(
            fixture.runtime.recovery_issues(),
            issues,
            "failed scans cannot replace known diagnostics with success"
        );
        tokio::fs::remove_file(&managed).await?;
        tokio::fs::rename(&retained, &managed).await?;
        assert!(published_scan_diagnostic(&fixture.runtime).await?.is_none());

        // Failure to enter Git's cwd is a typed launch failure, not evidence that the managed
        // directory is absent. No PATH/environment mutation or process-wide injection is used.
        let retained = root.with_file_name("retained-private-workspace");
        tokio::fs::rename(&root, &retained).await?;
        let failure = fixture
            .runtime
            .append_worktree_recovery_issues(&mut Vec::new())
            .await
            .unwrap_err();
        assert!(matches!(failure.downcast_ref::<WorktreeError>(),
            Some(WorktreeError::LocalIo { operation, source })
                if *operation == "discover worktrees: launch git repository discovery"
                    && source.kind() == std::io::ErrorKind::NotFound));
        let diagnostic = published_scan_diagnostic(&fixture.runtime)
            .await?
            .context("Git launch failure must be published")?;
        assert!(
            diagnostic.contains("launch git repository discovery")
                && diagnostic.contains("NotFound")
        );
        assert!(diagnostic.chars().count() <= 2048);
        assert!(
            !diagnostic.contains(&fixture.project.path)
                && !diagnostic.contains("retained-private-workspace")
        );
        assert_eq!(fixture.runtime.recovery_issues(), issues);
        tokio::fs::rename(&retained, &root).await?;
        assert!(published_scan_diagnostic(&fixture.runtime).await?.is_none());
        fixture.finish().await
    }
}

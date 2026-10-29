use std::collections::BTreeSet;
use std::path::Path;
use std::path::PathBuf;

use anyhow::Result;

use crate::agent::worktree::{WorktreeError, WorktreeHandle, WorktreeManager};
use crate::studio::agent_host::worktree_lease::{WorktreeLease, WorktreeLeaseState};
use crate::studio::{
    StudioRecoveryImpact, StudioRecoveryIssue, StudioRecoveryIssueAction,
    StudioRecoveryIssueCategory, StudioRecoveryIssueScope, StudioRecoveryWorktreeOwner,
    StudioWorktreeInspection,
};
use pl_tool::workspace::resolve_workspace_root;

use super::super::StudioRuntime;

fn background_git_command() -> tokio::process::Command {
    let mut command = tokio::process::Command::new("git");
    #[cfg(windows)]
    command.args(["-c", "core.longpaths=true"]);
    pl_remote_helper::process::configure_background_command(&mut command);
    command
}

impl StudioRuntime {
    pub(in crate::studio::runtime) async fn append_agent_close_recovery_issues(
        &self,
        issues: &mut Vec<StudioRecoveryIssue>,
    ) -> Result<()> {
        for record in self.store.agent_closes().await? {
            let residual_registration = matches!(
                record.worktree_cleanup,
                crate::studio::agent_close::AgentWorktreeCleanup::NotPresent {
                    registration_present: true,
                    ..
                }
            );
            if record.execution_closed
                && record.worktree_cleanup.is_terminal()
                && record.error.is_none()
                && !residual_registration
            {
                continue;
            }
            issues.push(StudioRecoveryIssue {
                id: format!("agent-close:{}", record.agent_id),
                scope: StudioRecoveryIssueScope::Thread,
                category: StudioRecoveryIssueCategory::Storage,
                impact: StudioRecoveryImpact::Advisory,
                action: if residual_registration && record.error.is_none() { StudioRecoveryIssueAction::None } else { StudioRecoveryIssueAction::Retry },
                project_id: Some(record.project_id),
                thread_id: Some(record.agent_id),
                message: record.error.map_or_else(
                    || {
                        if residual_registration {
                            "Closed child path is absent; its exact Git registration was preserved without pruning".into()
                        } else {
                            "Explicit child close has unfinished execution or owned-worktree cleanup".into()
                        }
                    },
                    |error| error.message,
                ),
                worktree: None,
            });
        }
        Ok(())
    }

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
                .await;
            let Ok(root) = root else {
                continue;
            };
            if !root.status.success() {
                continue;
            }
            let root = normalized_local_path(Path::new(String::from_utf8(root.stdout)?.trim()));
            let managed = root.join(".anywork/worktrees");
            let mut found = BTreeSet::new();
            if let Ok(mut parents) = tokio::fs::read_dir(&managed).await {
                while let Some(parent) = parents.next_entry().await? {
                    if !parent.file_type().await?.is_dir() {
                        continue;
                    }
                    let mut children = tokio::fs::read_dir(parent.path()).await?;
                    while let Some(child) = children.next_entry().await? {
                        found.insert(normalized_local_path(&child.path()));
                    }
                }
            }
            let registered = background_git_command()
                .args(["worktree", "list", "--porcelain", "-z"])
                .current_dir(&root)
                .output()
                .await?;
            anyhow::ensure!(
                registered.status.success(),
                "cannot inspect registered worktrees for {}: {}",
                project.id,
                String::from_utf8_lossy(&registered.stderr)
            );
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
                    impact: StudioRecoveryImpact::Advisory,
                    action: StudioRecoveryIssueAction::Retry, project_id: Some(project.id.clone()), thread_id: None,
                    message: format!("Unregistered worktree preserved at {}; ownership must be inspected before explicit cleanup", path.display()), worktree: None,
                });
            }
        }
        Ok(())
    }

    /// Recovery issue for a lease that needs manual handling, or `None` when the resource
    /// is still used by a registered owner.
    async fn worktree_recovery_issue(&self, lease: &WorktreeLease) -> Option<StudioRecoveryIssue> {
        if self
            .store
            .agent_close(&lease.owner_thread_id)
            .await
            .ok()
            .flatten()
            .is_some()
        {
            return None;
        }
        // 创建中的 lease 是进程内正在工作的资源：既不是崩溃遗留，也不可人工处置。
        if self
            .agent_facility
            .worktrees
            .is_creating(&lease.owner_thread_id)
        {
            return None;
        }
        if lease.state == WorktreeLeaseState::Cleaned {
            return if self.agent_facility.worktrees.is_durable(lease) {
                None
            } else {
                Some(self.worktree_issue(
                    lease,
                    &WorktreeIssueFacts {
                        observation: Err(WorktreeError::InvalidResource(
                            "physical cleanup completed; durable completion acknowledgement is pending".into(),
                        ).into()),
                        owner: self.worktree_owner_facts(&lease.owner_thread_id).await,
                    },
                    worktree_state_message(lease),
                ))
            };
        }
        let facts = self.worktree_issue_facts(lease).await;
        if lease.state != WorktreeLeaseState::Preserved
            && matches!(facts.owner, Ok(WorktreeOwnerFacts { live: true, .. }))
            && facts.inspection() == StudioWorktreeInspection::Available
        {
            return None;
        }
        let mut issue = self.worktree_issue(lease, &facts, worktree_state_message(lease));
        if self.thread_requires_execution_workspace(lease, &facts) && facts.observation.is_err() {
            issue.impact = StudioRecoveryImpact::ExecutionBlocked;
        }
        Some(issue)
    }

    /// Observation never changes lease state. Existence is established only by backend stat.
    async fn worktree_issue_facts(&self, lease: &WorktreeLease) -> WorktreeIssueFacts {
        let observation = async {
            lease.validate_identity()?;
            self.worktree_manager(lease)
                .await?
                .preview(&worktree_handle(lease))
                .await
                .map_err(anyhow::Error::from)
        }
        .await;
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
        let changed_files = preview.map(|preview| {
            preview
                .changed_files
                .iter()
                .chain(&preview.ignored_files)
                .cloned()
                .collect()
        });
        let mut message = message;
        match facts
            .observation
            .as_ref()
            .err()
            .and_then(|error| error.downcast_ref::<WorktreeError>())
        {
            None if facts.observation.is_ok() => {}
            Some(WorktreeError::Missing) => message
                .push_str("; worktree path is missing; this inspection does not mark it cleaned"),
            Some(WorktreeError::IdentityMismatch(_)) => {
                message.push_str(
                    "; worktree identity conflicts with its lease; cleanup is not authorized by this inspection",
                );
            }
            _ => message.push_str(
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
                message.push_str(&super::shutdown::redacted_chain(error));
            }
        }
        let can_cleanup = matches!(&facts.owner, Ok(WorktreeOwnerFacts { live: false, .. }))
            && preview.is_some_and(|preview| {
                preview.changed_files.is_empty() && preview.ignored_files.is_empty()
            })
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
            impact: StudioRecoveryImpact::Advisory,
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
            message: bounded_diagnostic(&message),
            worktree: Some(crate::StudioWorktreeRecoveryPreview {
                inspection: facts.inspection(),
                owner_kind: recovery_owner(lease.owner_kind),
                owner_thread_id: lease.owner_thread_id.clone(),
                lease_revision: lease.revision,
                state: lease.state.label().to_string(),
                repository_root: lease.repository_root.clone(),
                path: lease.path.clone(),
                branch: preview.and_then(|preview| preview.branch.clone()),
                base_commit: lease.base_commit.clone(),
                head_commit: preview.map(|preview| preview.head.clone()),
                dirty: preview.map(|preview| {
                    !preview.changed_files.is_empty() || !preview.ignored_files.is_empty()
                }),
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

    /// Execution relevance is separate from physical cleanup eligibility. A closed or healthy
    /// preserved child must not turn a root's unrelated workspace into an execution dependency.
    fn thread_requires_execution_workspace(
        &self,
        lease: &WorktreeLease,
        facts: &WorktreeIssueFacts,
    ) -> bool {
        facts.owner.as_ref().is_ok_and(|owner| owner.live)
            && !self
                .store
                .catalog()
                .get(&lease.owner_thread_id)
                .is_some_and(|entry| entry.explicitly_closed)
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
        let lease = self
            .agent_facility
            .worktrees
            .get(owner_thread_id)
            .ok_or_else(|| anyhow::anyhow!("worktree lease does not exist"))?;
        anyhow::ensure!(
            self.store.agent_close(owner_thread_id).await?.is_none(),
            "closed child worktrees belong to their durable close owner, not generic Recovery cleanup"
        );
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
        // Server-side precondition: a stale or forged card must never delete a workspace a
        // live Thread still owns. The lease state cannot grant that: a `preserved` site may be a
        // directory a running child is using, so only a site whose owner Thread is no longer live is
        // eligible for explicit cleanup.
        anyhow::ensure!(
            !self
                .worktree_owner_facts(&lease.owner_thread_id)
                .await?
                .live,
            "worktree lease is still owned by a live Thread"
        );
        let owner = self.find_owned_thread(&lease.owner_thread_id).await?;
        if let Some(owner) = &owner {
            anyhow::ensure!(
                lease.project_id == owner.project_id
                    && lease.root_thread_id == owner.root_thread_id,
                WorktreeError::IdentityMismatch(
                    "owner: lease differs from the directory owner".into()
                )
            );
        }
        let project = match self
            .agent_facility
            .product_events
            .project_snapshot()
            .await
            .into_iter()
            .find(|project| project.id == lease.project_id)
        {
            Some(project) => project,
            None => self
                .store
                .read_project(&lease.project_id)
                .await?
                .ok_or_else(|| {
                    WorktreeError::IdentityMismatch("project: lease project is missing".into())
                })?,
        };
        anyhow::ensure!(
            project.ssh_alias == lease.ssh_alias,
            WorktreeError::IdentityMismatch("remote target: project differs from the lease".into())
        );
        let project_root =
            crate::studio::agent_host::workspace_preparation::resolved_project_root(&project)?;
        let (repository, manager, endpoint) =
            crate::studio::agent_host::workspace_preparation::repository_manager(
                &self.ssh_manager,
                project.ssh_alias.as_deref(),
                &project_root,
            )
            .await?;
        anyhow::ensure!(
            repository == std::path::Path::new(&lease.repository_root),
            WorktreeError::IdentityMismatch("repository: project differs from the lease".into())
        );
        let identity =
            crate::studio::agent_host::workspace_preparation::cleanup_identity(&self.store, &lease)
                .await?;
        anyhow::ensure!(
            endpoint == identity.endpoint && identity.matches_root(&lease.path),
            WorktreeError::IdentityMismatch(
                "physical cleanup endpoint differs from the original binding".into()
            )
        );
        if let Err(error) = crate::studio::agent_host::workspace_preparation::cleanup_workspace(
            &self.store,
            &self.agent_facility.worktrees,
            &manager,
            lease,
            crate::agent::worktree::WorktreeCleanupPolicy::Safe,
        )
        .await
        {
            if let Some(remaining) = self.agent_facility.worktrees.get(owner_thread_id) {
                self.publish_worktree_recovery(Some("safe cleanup did not complete"), &remaining)
                    .await;
            }
            return Err(error);
        }
        let issues = self.recovery.remove(&worktree_issue_id(owner_thread_id));
        self.agent_facility
            .product_events
            .emit_recovery_state(issues);
        Ok(())
    }

    async fn worktree_manager(&self, lease: &WorktreeLease) -> Result<WorktreeManager> {
        crate::studio::agent_host::workspace_preparation::manager_from_lease(
            &self.store,
            &self.ssh_manager,
            lease,
        )
        .await
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
            impact: StudioRecoveryImpact::ExecutionBlocked,
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
        issue.impact = StudioRecoveryImpact::ExecutionBlocked;
        issue.thread_id = Some(thread.id.clone());
        let diagnostic = super::shutdown::redacted_chain(error);
        issue.message = bounded_diagnostic(&format!(
            "Thread cannot use its saved workspace and was not moved to the main workspace: {diagnostic}; {}",
            issue.message
        ));
        self.recovery.update_if_current(
            &issue_id,
            Some(issue),
            || true,
            |issues| {
                self.agent_facility
                    .product_events
                    .emit_recovery_state(issues);
            },
        );
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
        let mut issue = self.worktree_issue(lease, &facts, message);
        if self.thread_requires_execution_workspace(lease, &facts) && facts.observation.is_err() {
            issue.impact = StudioRecoveryImpact::ExecutionBlocked;
        }
        let issue_id = issue.id.clone();
        self.recovery.update_if_current(
            &issue_id,
            Some(issue),
            || true,
            |issues| {
                self.agent_facility
                    .product_events
                    .emit_recovery_state(issues);
            },
        );
    }

    pub(in crate::studio::runtime) async fn append_unavailable_project_recovery_issues(
        &self,
        recovery_issues: &mut Vec<StudioRecoveryIssue>,
    ) -> Result<()> {
        for project in self.store.list_projects().await? {
            if project.ssh_alias.is_some() {
                continue;
            }
            let Err(error) = resolve_workspace_root(Path::new(&project.path)) else {
                continue;
            };
            let issue_id = format!("recovery-issue-project-path-{}", project.id);
            // A project-scoped reminder (for example an unregistered worktree) must not hide an
            // independent, real failure of the project's execution workspace.
            if recovery_issues.iter().any(|issue| issue.id == issue_id) {
                continue;
            }
            recovery_issues.push(StudioRecoveryIssue {
                id: issue_id,
                scope: StudioRecoveryIssueScope::Project,
                category: StudioRecoveryIssueCategory::Repository,
                impact: StudioRecoveryImpact::ExecutionBlocked,
                action: StudioRecoveryIssueAction::Retry,
                project_id: Some(project.id),
                thread_id: None,
                message: format!("Project workspace is unavailable: {error}"),
                worktree: None,
            });
        }
        Ok(())
    }

    pub(in crate::studio::runtime) async fn append_thread_execution_recovery_issues(
        &self,
        issues: &mut Vec<StudioRecoveryIssue>,
    ) -> Result<()> {
        for entry in self.store.catalog().entries() {
            let thread = entry.to_thread();
            if thread.archived || entry.explicitly_closed {
                continue;
            }
            let result = self
                .thread_factory
                .verify_execution_workspace(
                    &thread,
                    None,
                    crate::studio::thread_factory::ExecutionWorkspaceCheck::Audit,
                )
                .await;
            if let Err(error) = result {
                issues.push(
                    crate::studio::StudioRecoveryRegistry::execution_workspace_issue(
                        &thread, &error,
                    ),
                );
            }
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
    observation: Result<crate::agent::worktree::WorktreeStatus>,
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
            Err(error) => match error.downcast_ref::<WorktreeError>() {
                Some(WorktreeError::Missing) => StudioWorktreeInspection::Missing,
                Some(WorktreeError::IdentityMismatch(_)) => {
                    StudioWorktreeInspection::IdentityMismatch
                }
                _ => StudioWorktreeInspection::Unavailable,
            },
        }
    }
}

fn bounded_diagnostic(message: &str) -> String {
    message.chars().take(2048).collect()
}

fn worktree_error_diagnostic(error: &anyhow::Error) -> String {
    match error
        .chain()
        .find_map(|source| source.downcast_ref::<WorktreeError>())
    {
        Some(error) => error.safe_diagnostic(),
        None => super::shutdown::redacted_chain(error),
    }
}

/// Describes a lease by its actual ownership and state instead of assuming `preserved`.
fn worktree_state_message(lease: &WorktreeLease) -> String {
    if lease.state == WorktreeLeaseState::Cleaned {
        return "Worktree physical cleanup completed; durable completion acknowledgement is pending".into();
    }
    format!(
        "Managed {} worktree is {} and needs explicit review",
        lease.owner_kind.label(),
        lease.state.label()
    )
}

fn worktree_handle(lease: &WorktreeLease) -> WorktreeHandle {
    WorktreeHandle {
        path: PathBuf::from(&lease.path),
        base_commit: lease.base_commit.clone(),
    }
}

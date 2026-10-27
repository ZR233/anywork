use std::collections::BTreeSet;
use std::path::Path;
use std::path::PathBuf;

use anyhow::Result;

use crate::agent::worktree::{WorktreeHandle, WorktreeManager};
use crate::studio::agent_host::worktree_lease::{WorktreeLease, WorktreeLeaseState};
use crate::studio::{
    StudioRecoveryImpact, StudioRecoveryIssue, StudioRecoveryIssueAction,
    StudioRecoveryIssueCategory, StudioRecoveryIssueScope, StudioRecoveryWorktreeOwner,
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
                        identity_error: None,
                        preview_error: None,
                        preview: None,
                    },
                    worktree_state_message(lease),
                ))
            };
        }
        let facts = self.worktree_issue_facts(lease).await;
        // A lease without its Thread row is a crash artifact: keep the physical resource
        // and report it as a diagnostic instead of inferring ownership or deleting it.
        let orphaned_row = !self.thread_row_exists(&lease.owner_thread_id).await;
        let execution_owner = self
            .thread_requires_execution_workspace(&lease.owner_thread_id)
            .await;
        let resource_unavailable = facts.preview.is_none();
        let needs_manual_handling = lease.state == WorktreeLeaseState::Preserved
            || !execution_owner
            || facts.identity_error.is_some()
            // A `prepared` lease may legitimately lack its physical root while creation is
            // still in flight, so only an owning state escalates a missing resource.
            || (resource_unavailable && lease.state != WorktreeLeaseState::Prepared);
        if !needs_manual_handling {
            return None;
        }
        let orphan_suffix = if orphaned_row {
            "; no published Thread remains for this lease, so it is preserved for diagnosis"
        } else {
            ""
        };
        // The message must describe the resource as it actually is: a lease can need
        // review while still `active` because its owner Thread is archived.
        let message = match facts
            .identity_error
            .as_ref()
            .or(facts.preview_error.as_ref())
        {
            Some(diagnostic) => format!("{diagnostic}{orphan_suffix}"),
            None => format!("{}{orphan_suffix}", worktree_state_message(lease)),
        };
        let mut issue = self.worktree_issue(lease, &facts, message);
        if execution_owner && (resource_unavailable || facts.identity_error.is_some()) {
            issue.impact = StudioRecoveryImpact::ExecutionBlocked;
        }
        Some(issue)
    }

    /// Fresh preview facts of one durable lease, computed from its current record.
    async fn worktree_issue_facts(&self, lease: &WorktreeLease) -> WorktreeIssueFacts {
        if lease.state == WorktreeLeaseState::Cleaned {
            return WorktreeIssueFacts {
                identity_error: None,
                preview_error: None,
                preview: None,
            };
        }
        let handle = worktree_handle(lease);
        let mut identity_error = lease
            .validate_identity()
            .err()
            .map(|error| error.to_string());
        let mut preview_error = None;
        let preview = match identity_error.as_ref() {
            Some(_) => None,
            None => match self.worktree_manager(lease).await {
                Ok(manager) => match async {
                    manager
                        .validate_registered_site(&handle.path, &handle.branch)
                        .await?;
                    let preview = manager.preview(&handle).await?;
                    if preview.branch.as_deref() != Some(handle.branch.as_str()) {
                        return Err(crate::agent::worktree::WorktreeError::InvalidResource(
                            "worktree is not on its saved branch".into(),
                        ));
                    }
                    Ok(preview)
                }
                .await
                {
                    Ok(preview) => Some(preview),
                    Err(error) => {
                        preview_error = Some(format!("{error:#}"));
                        None
                    }
                },
                Err(error) => {
                    identity_error = Some(error.to_string());
                    None
                }
            },
        };
        WorktreeIssueFacts {
            identity_error,
            preview_error,
            preview,
        }
    }

    fn worktree_issue(
        &self,
        lease: &WorktreeLease,
        facts: &WorktreeIssueFacts,
        message: String,
    ) -> StudioRecoveryIssue {
        let changed_files = facts
            .preview
            .as_ref()
            .map(|preview| preview.changed_files.clone())
            .unwrap_or_default();
        StudioRecoveryIssue {
            id: worktree_issue_id(&lease.owner_thread_id),
            scope: StudioRecoveryIssueScope::Thread,
            category: StudioRecoveryIssueCategory::Repository,
            impact: StudioRecoveryImpact::Advisory,
            action: StudioRecoveryIssueAction::CleanupWorktree,
            project_id: Some(lease.project_id.clone()),
            // The issue belongs to the Thread that owns the workspace. A child's site must be resolvable
            // — and retirable — by that child alone; attributing it to the root made activation unable
            // to clear its own entry and let a root activation clear a different child's entry.
            thread_id: Some(lease.owner_thread_id.clone()),
            message,
            worktree: Some(crate::StudioWorktreeRecoveryPreview {
                owner_kind: recovery_owner(lease.owner_kind),
                owner_thread_id: lease.owner_thread_id.clone(),
                lease_revision: lease.revision,
                state: lease.state.label().to_string(),
                repository_root: lease.repository_root.clone(),
                path: lease.path.clone(),
                branch: lease.branch.clone(),
                base_commit: lease.base_commit.clone(),
                head_commit: facts.preview.as_ref().map(|preview| preview.head.clone()),
                dirty: !changed_files.is_empty(),
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
        self.run_archive(async move {
            let result = runtime
                .cleanup_preserved_worktree_with_lifecycle_lock(
                    owner_kind,
                    &owner_thread_id,
                    expected_lease_revision,
                )
                .await;
            if let Err(error) = &result
                && let Some(lease) = runtime.agent_facility.worktrees.get(&owner_thread_id)
            {
                runtime
                    .publish_worktree_recovery(Some(&format!("{error:#}")), &lease)
                    .await;
            }
            result
        })
        .await
    }

    async fn cleanup_preserved_worktree_with_lifecycle_lock(
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
            !self.live_thread_owns_lease(&lease.owner_thread_id).await,
            "worktree lease is still owned by a live Thread"
        );
        lease.validate_identity()?;
        self.thread_factory
            .prepare_workspace_cleanup(&lease)
            .await?;
        let manager = self.worktree_manager(&lease).await?;
        crate::studio::agent_host::workspace_preparation::cleanup_workspace(
            &self.store,
            &self.agent_facility.worktrees,
            &manager,
            lease,
        )
        .await?;
        let issues = self.recovery.remove(&worktree_issue_id(owner_thread_id));
        self.agent_facility
            .product_events
            .emit_recovery_state(issues);
        Ok(())
    }

    async fn worktree_manager(&self, lease: &WorktreeLease) -> Result<WorktreeManager> {
        Ok(
            crate::studio::agent_host::workspace_preparation::manager_from_lease(
                &self.store,
                &self.ssh_manager,
                lease,
            )
            .await?,
        )
    }

    /// Whether the product directory still holds a Thread row for a lease owner.
    ///
    /// Hot facts precede the cold row because directory commits are write-behind.
    async fn thread_row_exists(&self, thread_id: &str) -> bool {
        if self
            .agent_facility
            .product_events
            .thread_snapshot(thread_id)
            .is_some()
        {
            return true;
        }
        matches!(
            self.store.read_thread_association(thread_id).await,
            Ok(Some(_))
        )
    }

    /// Diagnostic execution qualification only: a durable seal makes workspace faults advisory.
    /// It does not prove that resource owners, processes or external reviewers have stopped.
    async fn thread_requires_execution_workspace(&self, thread_id: &str) -> bool {
        self.live_thread_owns_lease(thread_id).await
            && !self
                .store
                .catalog()
                .get(thread_id)
                .is_some_and(|entry| entry.explicitly_closed)
    }

    /// Conservative physical cleanup protection for every active (non-archived) owner.
    /// Explicit execution closure never relaxes this protection: its cleanup may have failed and
    /// sibling reviewers can still borrow the workspace without owning its lease.
    async fn live_thread_owns_lease(&self, thread_id: &str) -> bool {
        if let Some(thread) = self
            .agent_facility
            .product_events
            .thread_snapshot(thread_id)
        {
            return !thread.archived;
        }
        matches!(
            self.store.read_thread_association(thread_id).await,
            Ok(Some(record)) if record.visibility == crate::studio::ThreadVisibility::Active
        )
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
            action: StudioRecoveryIssueAction::CleanupWorktree,
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
        issue.message = format!(
            "Thread {} cannot use its saved workspace and was not moved to the main workspace: {error:#}",
            thread.id
        );
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
        let message = match facts
            .identity_error
            .as_ref()
            .or(facts.preview_error.as_ref())
        {
            Some(error) => format!("{message}; {error}"),
            None => message,
        };
        let mut issue = self.worktree_issue(lease, &facts, message);
        if self
            .thread_requires_execution_workspace(&lease.owner_thread_id)
            .await
            && (facts.identity_error.is_some() || facts.preview.is_none())
        {
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
    identity_error: Option<String>,
    preview_error: Option<String>,
    preview: Option<crate::agent::worktree::WorktreeStatus>,
}

/// Describes a lease by its actual ownership and state instead of assuming `preserved`.
fn worktree_state_message(lease: &WorktreeLease) -> String {
    if lease.state == WorktreeLeaseState::Cleaned {
        return "Worktree physical cleanup completed; durable completion acknowledgement is pending".into();
    }
    format!(
        "Pure {} worktree {} is {} and needs explicit review",
        lease.owner_kind.label(),
        lease.branch,
        lease.state.label()
    )
}

fn worktree_handle(lease: &WorktreeLease) -> WorktreeHandle {
    WorktreeHandle {
        path: PathBuf::from(&lease.path),
        branch: lease.branch.clone(),
        base_commit: lease.base_commit.clone(),
    }
}

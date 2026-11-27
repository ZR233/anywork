//! Durable child close intent shared by Native and ACP children.
//!
//! `ChildCloseCoordinator` owns the saved record's lifecycle: resuming an existing intent, proving
//! its binding still matches the frozen lease, freezing a new intent, advancing execution-close
//! progress and recording failures. Each backend proves the closing identity from its own directory
//! facts and releases its own owner; neither re-implements the record transitions. No model or
//! execution workspace is restored while closing a saved child.
use super::{StudioThreadFactory, errors::resource_error};
use crate::Thread;
use crate::studio::{
    agent_close::state_error,
    store::agent_close::{AgentCloseRecord, OwnedWorktreeBinding},
    worktree::workspace_preparation,
};
use crate::thread_assembler::ThreadAssemblyError;
use anyhow::{Context, Result, ensure};
use pl_tool::collaboration::control::{AgentCloseResult, AgentWorktreeCleanup};

/// The collaboration-tree identity a saved close intent must still describe.
pub(super) struct ChildCloseIdentity {
    agent_id: String,
    parent_id: String,
    root_id: String,
    workspace_id: String,
}

impl ChildCloseIdentity {
    fn native(thread: &Thread) -> Result<Self> {
        Ok(Self {
            agent_id: thread.id.clone(),
            parent_id: thread
                .parent_thread_id
                .clone()
                .context("cannot close a root as a child")?,
            root_id: thread.root_thread_id.clone(),
            workspace_id: thread.workspace_id.clone(),
        })
    }

    fn acp(member: &crate::studio::records::DirectoryMember) -> Result<Self> {
        ensure!(
            matches!(&member.agent.backend, crate::AgentBackend::Acp { .. }),
            "ACP close requires an ACP member"
        );
        Ok(Self {
            agent_id: member.agent.thread_id.clone(),
            parent_id: member
                .parent_thread_id
                .clone()
                .context("cannot close root as child")?,
            root_id: member.root_thread_id.clone(),
            workspace_id: member.session.workspace_id.clone(),
        })
    }
}

/// Durable close-intent lifecycle for one child, independent of the owning backend.
pub(super) struct ChildCloseCoordinator<'a> {
    factory: &'a StudioThreadFactory,
    identity: &'a ChildCloseIdentity,
}

impl StudioThreadFactory {
    pub(super) fn child_close<'a>(
        &'a self,
        identity: &'a ChildCloseIdentity,
    ) -> ChildCloseCoordinator<'a> {
        ChildCloseCoordinator {
            factory: self,
            identity,
        }
    }
}

impl ChildCloseCoordinator<'_> {
    /// Resume the saved intent: prove its identity and lease, honour a force upgrade while the
    /// worktree cleanup is still retriable, and restore the physical seal. `None` when no intent
    /// is saved yet.
    pub(super) async fn resume(&self, force: bool) -> Result<Option<AgentCloseRecord>> {
        let Some(mut record) = self
            .factory
            .services
            .store
            .agent_close(&self.identity.agent_id)
            .await?
        else {
            return Ok(None);
        };
        self.validate_saved(&record)?;
        let mut updated = false;
        if force && !record.force && !record.worktree_cleanup.is_terminal() {
            record.force = true;
            updated = true;
        }
        if !record.execution_closed || !record.worktree_cleanup.is_terminal() {
            if record.error.take().is_some() {
                updated = true;
            }
            if record.execution_closed
                && matches!(record.worktree_cleanup, AgentWorktreeCleanup::Failed { .. })
            {
                record.worktree_cleanup = AgentWorktreeCleanup::Pending;
                updated = true;
            }
        }
        if updated {
            record.changed()?;
            self.factory
                .services
                .store
                .save_agent_close(&record)
                .await?;
            self.factory
                .services
                .product_events
                .commit_explicit_close(&record.agent_id)
                .await?;
            self.factory.sync_agent_close_recovery(&record);
        }
        if let Some(binding) = &record.worktree
            && !record.worktree_cleanup.is_terminal()
        {
            self.factory
                .services
                .worktrees
                .restore_workspace_seal(&record.agent_id, binding.identity.clone())?;
        }
        Ok(Some(record))
    }

    /// Prove the saved record still describes this child and its immutable lease binding.
    /// Generic shutdown may settle Preserve, but can never change that binding.
    pub(super) fn validate_saved(&self, record: &AgentCloseRecord) -> Result<()> {
        let id = &self.identity.agent_id;
        ensure!(
            record.agent_id == *id
                && record.parent_id == self.identity.parent_id
                && record.root_id == self.identity.root_id
                && record.workspace_id == self.identity.workspace_id,
            "saved close identity differs from the original collaboration tree"
        );
        if let Some(binding) = &record.worktree {
            let current = self
                .factory
                .services
                .worktrees
                .get(id)
                .context("closed child ownership lease is missing")?;
            let original = &binding.lease;
            ensure!(
                current.owner_kind == original.owner_kind
                    && current.owner_thread_id == original.owner_thread_id
                    && current.root_thread_id == original.root_thread_id
                    && current.workspace_id == original.workspace_id
                    && current.repository_root == original.repository_root
                    && current.path == original.path
                    && current.base_commit == original.base_commit
                    && current.ssh_alias == original.ssh_alias,
                "closed child ownership binding changed"
            );
        }
        Ok(())
    }

    /// Freeze a new intent after the backend proved the child's workspace ownership.
    pub(super) async fn create(
        &self,
        worktree: Option<OwnedWorktreeBinding>,
        force: bool,
    ) -> Result<AgentCloseRecord> {
        let record = AgentCloseRecord {
            agent_id: self.identity.agent_id.clone(),
            parent_id: self.identity.parent_id.clone(),
            root_id: self.identity.root_id.clone(),
            workspace_id: self.identity.workspace_id.clone(),
            revision: 1,
            force,
            worktree,
            git: None,
            execution_closed: false,
            worktree_cleanup: AgentWorktreeCleanup::Pending,
            error: None,
        };
        // The product transaction is the permanent execution seal. A readback error is not rollback.
        let saved = self.factory.services.store.save_agent_close(&record).await;
        if let Some(binding) = &record.worktree {
            if let Some(frozen) = self
                .factory
                .services
                .store
                .workspace_identity(&record.agent_id)
                .await?
            {
                ensure!(
                    frozen == binding.identity,
                    "closed child physical identity changed"
                );
            }
            match self
                .factory
                .services
                .store
                .agent_close(&record.agent_id)
                .await
            {
                Ok(Some(actual)) if actual == record => self
                    .factory
                    .services
                    .worktrees
                    .restore_workspace_seal(&record.agent_id, binding.identity.clone())?,
                Ok(None) => {}
                Ok(_) => anyhow::bail!("close intent changed during save; resources preserved"),
                Err(error) => {
                    self.factory
                        .services
                        .worktrees
                        .restore_workspace_seal(&record.agent_id, binding.identity.clone())?;
                    return Err(error.context(
                        "close save outcome unresolved; physical workspace remains sealed",
                    ));
                }
            }
        }
        saved?;
        self.factory
            .services
            .product_events
            .commit_explicit_close(&record.agent_id)
            .await?;
        Ok(record)
    }

    /// Advance the saved intent to execution-closed once every owner joined, then release the
    /// physical resources of a child that owns no worktree. Worktree cleanup stays with the caller.
    pub(super) async fn mark_execution_closed(&self) -> Result<AgentCloseRecord> {
        let id = &self.identity.agent_id;
        let mut record = self
            .factory
            .services
            .store
            .agent_close(id)
            .await?
            .context("close intent is missing")?;
        self.validate_saved(&record)?;
        self.factory
            .services
            .worktrees
            .ensure_thread_workspace_idle(id)?;
        if !record.execution_closed {
            record.execution_closed = true;
            record.error = None;
            record.changed()?;
            self.factory
                .services
                .store
                .save_agent_close(&record)
                .await?;
        }
        self.factory
            .services
            .product_events
            .commit_explicit_close(id)
            .await?;
        self.factory.sync_agent_close_recovery(&record);
        if record.worktree.is_none()
            && let Some(identity) = self.factory.services.store.workspace_identity(id).await?
        {
            // Retained SessionFiles are not a live use after all runtime owners joined.
            self.factory
                .services
                .worktrees
                .release_workspace_resources(id, &identity)?;
        }
        Ok(record)
    }
}

impl StudioThreadFactory {
    /// Native: the caller holds the root/tree coordinator. No model or execution workspace is restored.
    pub(crate) async fn begin_child_close(
        &self,
        thread: &Thread,
        snapshot: Option<&pl_core::thread::ThreadSnapshot>,
        force: bool,
    ) -> Result<AgentCloseRecord> {
        self.validate_child_close_association(thread).await?;
        ensure!(
            !self.services.store.has_legacy_retirement(&thread.id),
            "old unpublished retirement facts require explicit recovery; original data preserved"
        );
        let identity = ChildCloseIdentity::native(thread)?;
        let coordinator = self.child_close(&identity);
        if let Some(record) = coordinator.resume(force).await? {
            return Ok(record);
        }
        let snapshot = snapshot.context("explicit close needs the original saved assignment")?;
        self.validate_child_close(thread, snapshot)?;
        let assignment = crate::studio::workspace_receipt::from_snapshot(snapshot)
            .map_err(anyhow::Error::msg)?
            .context("child has no frozen workspace")?;
        let worktree = if assignment.mode == crate::AgentWorkspaceMode::Worktree {
            let lease = self
                .services
                .worktrees
                .get(&thread.id)
                .context("child ownership lease is missing")?;
            let physical =
                workspace_preparation::cleanup_identity(&self.services.store, &lease).await?;
            ensure!(
                physical.matches_root(&assignment.root),
                "owned worktree assignment changed"
            );
            Some(OwnedWorktreeBinding {
                lease,
                identity: physical,
            })
        } else {
            None
        };
        coordinator.create(worktree, force).await
    }

    /// ACP children use the existing workspace and final-worktree owners, not Native Threads.
    pub(crate) async fn begin_acp_child_close(
        &self,
        id: &str,
        force: bool,
    ) -> Result<AgentCloseResult> {
        let member = self.directory_member(id)?;
        let identity = ChildCloseIdentity::acp(&member)?;
        let coordinator = self.child_close(&identity);
        if let Some(record) = coordinator.resume(force).await? {
            return Ok(record.result());
        }
        let worktree = if let Some(lease) = self.services.worktrees.get(id) {
            ensure!(
                lease.owner_kind
                    == crate::studio::worktree::worktree_lease::WorktreeLeaseOwnerKind::Child
                    && lease.root_thread_id == member.root_thread_id
                    && lease.workspace_id == member.session.workspace_id,
                "ACP child does not own this worktree"
            );
            let physical =
                workspace_preparation::cleanup_identity(&self.services.store, &lease).await?;
            ensure!(
                self.services.store.workspace_identity(id).await?.as_ref() == Some(&physical)
                    && physical.matches_root(&lease.path),
                "ACP execution workspace changed"
            );
            Some(OwnedWorktreeBinding {
                lease,
                identity: physical,
            })
        } else {
            None
        };
        Ok(coordinator.create(worktree, force).await?.result())
    }

    /// Native: called only after actual Turn/tool/process/observer/writer/report ACK completion.
    pub(crate) async fn finish_child_execution(&self, thread: &Thread) -> Result<()> {
        let identity = ChildCloseIdentity::native(thread)?;
        self.child_close(&identity)
            .mark_execution_closed()
            .await
            .map(|_| ())
    }

    /// ACP: the original result-delivery join may need the Native parent's inbox gate, so the
    /// caller drops its root permit first and this join removes the owned worktree afterwards.
    pub(crate) async fn finish_acp_child_close(
        &self,
        id: &str,
    ) -> Result<(AgentCloseResult, Option<crate::StateError>)> {
        let member = self.directory_member(id)?;
        let identity = ChildCloseIdentity::acp(&member)?;
        let mut record = self.child_close(&identity).mark_execution_closed().await?;
        match self.cleanup_one_owned_worktree(&mut record).await {
            Ok(()) => {
                self.services
                    .product_events
                    .commit_explicit_close(id)
                    .await?;
                self.sync_agent_close_recovery(&record);
                Ok((record.result(), None))
            }
            Err(error) => {
                if !record.worktree_cleanup.is_terminal() {
                    record.worktree_cleanup = AgentWorktreeCleanup::Failed {
                        path: record
                            .worktree
                            .as_ref()
                            .map(|binding| binding.lease.path.clone()),
                        error: state_error(&error),
                    };
                }
                record.error = Some(state_error(&error));
                record.changed()?;
                self.services.store.save_agent_close(&record).await?;
                self.services
                    .product_events
                    .commit_explicit_close(id)
                    .await?;
                self.sync_agent_close_recovery(&record);
                Ok((record.result(), record.error))
            }
        }
    }

    /// Live-sync `agent-close:{id}` into `StudioRecoveryRegistry` whenever a close record
    /// advances to a failure or terminal completion.
    pub(crate) fn sync_agent_close_recovery(&self, record: &AgentCloseRecord) {
        let issue_id = format!("agent-close:{}", record.agent_id);
        let issue = crate::studio::store::agent_close::agent_close_recovery_issue(record);
        self.services.recovery.update_if_current(
            &issue_id,
            issue,
            || true,
            |state| {
                self.services.product_events.emit_recovery_state(state);
            },
        );
    }

    /// Native worktree cleanup re-proves the same saved binding before touching Git.
    pub(super) fn validate_close_identity(
        &self,
        thread: &Thread,
        record: &AgentCloseRecord,
    ) -> Result<()> {
        let identity = ChildCloseIdentity::native(thread)?;
        self.child_close(&identity).validate_saved(record)
    }

    pub(crate) async fn record_child_close_error(
        &self,
        id: &str,
        error: &anyhow::Error,
    ) -> Result<()> {
        if let Some(mut record) = self.services.store.agent_close(id).await? {
            record.error = Some(state_error(error));
            record.changed()?;
            self.services.store.save_agent_close(&record).await?;
            self.services
                .product_events
                .commit_explicit_close(id)
                .await?;
            self.sync_agent_close_recovery(&record);
        }
        Ok(())
    }

    /// Qualify the current document's permanent intent, then publish the durable close job's progress.
    /// The Core owner's resource lifecycle cannot stand in for the execution-close ACK.
    pub(crate) async fn project_child_close(
        &self,
        thread: &crate::Thread,
        snapshot: &pl_core::thread::ThreadSnapshot,
    ) -> Result<(), ThreadAssemblyError> {
        let result = async {
            anyhow::ensure!(
                crate::studio::agent_close::is_explicitly_closed(snapshot)?,
                "explicit close projection requires canonical intent"
            );
            let record = self
                .services
                .store
                .agent_close(&thread.id)
                .await?
                .context("close intent is missing")?;
            self.validate_close_identity(thread, &record)?;
            self.services
                .product_events
                .commit_explicit_close(&thread.id)
                .await?;
            Ok::<_, anyhow::Error>(())
        }
        .await;
        result.map_err(|error| resource_error("project durable child closure", error))
    }

    pub(crate) async fn child_close_storage(
        &self,
        thread: &crate::Thread,
        current: &pl_core::thread::current::ThreadCurrent,
    ) -> Result<crate::studio::ThreadStorageBinding, ThreadAssemblyError> {
        if current.thread_id != thread.id {
            return Err(ThreadAssemblyError::Identity(thread.id.clone()));
        }
        crate::studio::storage::thread_writer::ThreadStorageSink::new(
            self.services.store.clone(),
            thread.clone(),
        )
        .await
        .map(|sink| sink.binding())
        .map_err(|error| resource_error("open closing child persistence", error))
    }

    pub(crate) fn validate_child_close(
        &self,
        thread: &crate::Thread,
        snapshot: &pl_core::thread::ThreadSnapshot,
    ) -> Result<(), ThreadAssemblyError> {
        let saved = snapshot
            .extensions
            .get(crate::studio::workspace_receipt::EXTENSION)
            .ok_or_else(|| {
                ThreadAssemblyError::Identity(format!(
                    "child {} has no workspace receipt",
                    thread.id
                ))
            })?;
        let assignment = crate::studio::workspace_receipt::from_payload(&saved.payload)
            .map_err(|error| resource_error("decode closing child workspace", error))?;
        self.validate_child_close_workspace(thread, &assignment)
    }

    pub(crate) fn validate_child_close_workspace(
        &self,
        thread: &crate::Thread,
        assignment: &crate::AgentWorkspaceAssignmentSnapshot,
    ) -> Result<(), ThreadAssemblyError> {
        use crate::studio::worktree::worktree_lease::WorktreeLeaseOwnerKind;
        let lease = self.services.worktrees.get(&thread.id);
        if assignment.mode != crate::AgentWorkspaceMode::Worktree {
            // In particular a reviewer never owns the worktree named by its review assignment.
            if lease.is_some() {
                return Err(ThreadAssemblyError::Identity(
                    "non-worktree child owns an unexpected lease".into(),
                ));
            }
            return Ok(());
        }
        let receipt = assignment
            .worktree
            .as_ref()
            .filter(|receipt| receipt.path == assignment.root)
            .ok_or_else(|| {
                ThreadAssemblyError::Identity("invalid closing worktree receipt".into())
            })?;
        let lease = lease
            .filter(|lease| {
                lease.owner_kind == WorktreeLeaseOwnerKind::Child
                    && lease.owner_thread_id == thread.id
                    && lease.root_thread_id == thread.root_thread_id
                    && lease.workspace_id == thread.workspace_id
                    && lease.repository_root == receipt.repository_root
                    && lease.path == receipt.path
                    && lease.base_commit == receipt.base_commit
            })
            .ok_or_else(|| {
                ThreadAssemblyError::Identity(
                    "closing child workspace ownership cannot be proven".into(),
                )
            })?;
        lease
            .validate_identity()
            .map_err(|error| resource_error("validate closing child workspace", error))
    }

    /// Directory inheritance identifies the collaboration tree, not a child's assigned checkout.
    pub(super) async fn validate_child_close_association(
        &self,
        thread: &crate::Thread,
    ) -> Result<(), ThreadAssemblyError> {
        let parent_id = thread
            .parent_thread_id
            .as_deref()
            .ok_or(ThreadAssemblyError::Closed)?;
        let parent = self.directory_member(parent_id)?;
        let root = self.directory_member(&thread.root_thread_id)?;
        if root.parent_thread_id.is_some()
            || root.agent.thread_id != root.root_thread_id
            || parent.root_thread_id != root.agent.thread_id
            || parent.session.workspace_id != thread.workspace_id
            || root.session.workspace_id != thread.workspace_id
            || parent.session.workspace_path != thread.workspace_path
            || root.session.workspace_path != thread.workspace_path
            || parent.session.workspace_mode != thread.workspace_mode
            || root.session.workspace_mode != thread.workspace_mode
        {
            return Err(ThreadAssemblyError::Identity(
                "closing child directory ancestry changed".into(),
            ));
        }
        Ok(())
    }
}

//! Closing a saved child checks frozen workspace ownership without restoring execution resources.
use super::{StudioThreadFactory, errors::resource_error};
use crate::studio::{
    agent_close::{AgentWorktreeCleanup, state_error},
    agent_host::workspace_preparation,
    store::agent_close::{AgentCloseRecord, OwnedWorktreeBinding},
};
use crate::thread_assembler::ThreadAssemblyError;
use anyhow::{Context, Result, ensure};
use pl_protocol::Thread;

impl StudioThreadFactory {
    /// The caller holds the root/tree coordinator. No model or execution workspace is restored.
    pub(crate) async fn begin_child_close(
        &self,
        thread: &Thread,
        snapshot: Option<&pl_core::thread::ThreadSnapshot>,
        force: bool,
    ) -> Result<AgentCloseRecord> {
        self.validate_child_close_association(thread).await?;
        ensure!(
            !self
                .services
                .store
                .has_legacy_retirement(&thread.id)
                .await?,
            "old unpublished retirement facts require explicit recovery; original data preserved"
        );
        if let Some(mut record) = self.services.store.agent_close(&thread.id).await? {
            self.validate_close_identity(thread, &record)?;
            if force && !record.force && !record.worktree_cleanup.is_terminal() {
                record.force = true;
                record.changed()?;
                self.services.store.save_agent_close(&record).await?;
            }
            if let Some(binding) = &record.worktree
                && !record.worktree_cleanup.is_terminal()
            {
                self.services
                    .worktrees
                    .restore_workspace_seal(&thread.id, binding.identity.clone())?;
            }
            return Ok(record);
        }
        let snapshot = snapshot.context("explicit close needs the original saved assignment")?;
        self.validate_child_close(thread, snapshot)?;
        let assignment = crate::studio::workspace_receipt::from_snapshot(snapshot)
            .map_err(anyhow::Error::msg)?
            .context("child has no frozen workspace")?;
        let worktree = if assignment.mode == pl_protocol::AgentWorkspaceMode::Worktree {
            let lease = self
                .services
                .worktrees
                .get(&thread.id)
                .context("child ownership lease is missing")?;
            let identity =
                workspace_preparation::cleanup_identity(&self.services.store, &lease).await?;
            ensure!(
                identity.root == assignment.root,
                "owned worktree assignment changed"
            );
            Some(OwnedWorktreeBinding { lease, identity })
        } else {
            None
        };
        let record = AgentCloseRecord {
            agent_id: thread.id.clone(),
            parent_id: thread
                .parent_thread_id
                .clone()
                .context("cannot close a root as a child")?,
            root_id: thread.root_thread_id.clone(),
            project_id: thread.project_id.clone(),
            revision: 1,
            force,
            worktree,
            git: None,
            execution_closed: false,
            worktree_cleanup: AgentWorktreeCleanup::Pending,
            error: None,
        };
        // The product transaction is the permanent execution seal. A readback error is not rollback.
        let saved = self.services.store.save_agent_close(&record).await;
        if let Some(binding) = &record.worktree {
            if let Some(frozen) = self.services.store.workspace_identity(&thread.id).await? {
                ensure!(
                    frozen == binding.identity,
                    "closed child physical identity changed"
                );
            }
            match self.services.store.agent_close(&thread.id).await {
                Ok(Some(actual)) if actual == record => self
                    .services
                    .worktrees
                    .restore_workspace_seal(&thread.id, binding.identity.clone())?,
                Ok(None) => {}
                Ok(_) => anyhow::bail!("close intent changed during save; resources preserved"),
                Err(error) => {
                    self.services
                        .worktrees
                        .restore_workspace_seal(&thread.id, binding.identity.clone())?;
                    return Err(error.context(
                        "close save outcome unresolved; physical workspace remains sealed",
                    ));
                }
            }
        }
        saved?;
        self.services
            .store
            .catalog()
            .project_explicit_close(&thread.id)
            .await?;
        Ok(record)
    }

    pub(super) fn validate_close_identity(
        &self,
        thread: &Thread,
        record: &AgentCloseRecord,
    ) -> Result<()> {
        ensure!(
            record.agent_id == thread.id
                && Some(&record.parent_id) == thread.parent_thread_id.as_ref()
                && record.root_id == thread.root_thread_id
                && record.project_id == thread.project_id,
            "saved close identity differs from the original collaboration tree"
        );
        if let Some(binding) = &record.worktree {
            let current = self
                .services
                .worktrees
                .get(&thread.id)
                .context("closed child ownership lease is missing")?;
            let original = &binding.lease;
            // Generic shutdown may settle Preserve, but cannot change the immutable binding.
            ensure!(
                current.owner_kind == original.owner_kind
                    && current.owner_thread_id == original.owner_thread_id
                    && current.root_thread_id == original.root_thread_id
                    && current.project_id == original.project_id
                    && current.repository_root == original.repository_root
                    && current.path == original.path
                    && current.base_commit == original.base_commit
                    && current.ssh_alias == original.ssh_alias,
                "closed child ownership binding changed"
            );
        }
        Ok(())
    }

    /// Called only after actual Turn/tool/process/observer/writer/report ACK completion.
    pub(crate) async fn finish_child_execution(&self, thread: &Thread) -> Result<()> {
        let mut record = self
            .services
            .store
            .agent_close(&thread.id)
            .await?
            .context("close intent is missing")?;
        self.validate_close_identity(thread, &record)?;
        self.services
            .worktrees
            .ensure_thread_workspace_idle(&thread.id)?;
        if !record.execution_closed {
            record.execution_closed = true;
            record.error = None;
            record.changed()?;
            self.services.store.save_agent_close(&record).await?;
        }
        if record.worktree.is_none()
            && let Some(identity) = self.services.store.workspace_identity(&thread.id).await?
        {
            // Retained SessionFiles are not a live use after all runtime owners joined.
            self.services
                .worktrees
                .release_workspace_resources(&thread.id, &identity)?;
        }
        Ok(())
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
        }
        Ok(())
    }

    /// Only callers that just flushed (or cold-read) the canonical checkpoint may publish this
    /// projection. Normal shutdown observations do not call it.
    pub(crate) async fn project_child_close(
        &self,
        thread: &pl_protocol::Thread,
        snapshot: &pl_core::thread::ThreadSnapshot,
    ) -> Result<(), ThreadAssemblyError> {
        let result = async {
            anyhow::ensure!(
                crate::studio::agent_close::is_explicitly_closed(snapshot)?,
                "explicit close projection requires canonical intent"
            );
            self.services
                .store
                .catalog()
                .project_explicit_close(&thread.id)
                .await?;
            let mut projected = self
                .services
                .product_events
                .thread_snapshot(&thread.id)
                .unwrap_or_else(|| thread.clone());
            projected.status = if snapshot.lifecycle == pl_core::thread::ThreadLifecycle::Closed {
                pl_protocol::ThreadStatus::Closed
            } else {
                pl_protocol::ThreadStatus::Closing
            };
            self.services
                .product_events
                .commit_directory(crate::studio::store::directory::DirectoryDelta {
                    thread_upserts: vec![projected],
                    ..Default::default()
                })
                .await?;
            Ok::<_, anyhow::Error>(())
        }
        .await;
        result.map_err(|error| resource_error("project durable child closure", error))
    }

    pub(crate) async fn child_close_storage(
        &self,
        thread: &pl_protocol::Thread,
        checkpoint: &pl_core::thread::ThreadCheckpoint,
    ) -> Result<crate::studio::ThreadStorageBinding, ThreadAssemblyError> {
        crate::studio::storage::thread_writer::ThreadStorageSink::new(
            self.services.store.clone(),
            thread.clone(),
            Some(checkpoint),
        )
        .await
        .map(|sink| sink.binding())
        .map_err(|error| resource_error("open closing child persistence", error))
    }

    pub(crate) fn validate_child_close(
        &self,
        thread: &pl_protocol::Thread,
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
        thread: &pl_protocol::Thread,
        assignment: &pl_protocol::AgentWorkspaceAssignmentSnapshot,
    ) -> Result<(), ThreadAssemblyError> {
        use crate::studio::agent_host::worktree_lease::WorktreeLeaseOwnerKind;
        let lease = self.services.worktrees.get(&thread.id);
        if assignment.mode != pl_protocol::AgentWorkspaceMode::Worktree {
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
                    && lease.project_id == thread.project_id
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
        thread: &pl_protocol::Thread,
    ) -> Result<(), ThreadAssemblyError> {
        let parent_id = thread
            .parent_thread_id
            .as_deref()
            .ok_or(ThreadAssemblyError::Closed)?;
        let parent = self.thread_record(parent_id).await?;
        let root = self.thread_record(&thread.root_thread_id).await?;
        if root.parent_thread_id.is_some()
            || root.id != root.root_thread_id
            || parent.root_thread_id != root.id
            || parent.project_id != thread.project_id
            || root.project_id != thread.project_id
            || parent.workspace_path != thread.workspace_path
            || root.workspace_path != thread.workspace_path
            || parent.workspace_mode != thread.workspace_mode
            || root.workspace_mode != thread.workspace_mode
        {
            return Err(ThreadAssemblyError::Identity(
                "closing child directory ancestry changed".into(),
            ));
        }
        Ok(())
    }
}

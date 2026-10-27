//! Closing a saved child checks frozen workspace ownership without restoring execution resources.
use super::{StudioThreadFactory, errors::resource_error};
use crate::thread_assembler::ThreadAssemblyError;

impl StudioThreadFactory {
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
    ) -> Result<pl_core::thread::cold::ColdStoreHandle, ThreadAssemblyError> {
        crate::studio::storage::thread_writer::ThreadStorageSink::new(
            self.services.store.clone(),
            thread.clone(),
            Some(checkpoint),
        )
        .await
        .map(pl_core::thread::cold::ColdStoreHandle::new)
        .map_err(|error| resource_error("open closing child persistence", error))
    }

    pub(crate) fn validate_child_close(
        &self,
        thread: &pl_protocol::Thread,
        snapshot: &pl_core::thread::ThreadSnapshot,
    ) -> Result<(), ThreadAssemblyError> {
        use crate::studio::agent_host::worktree_lease::WorktreeLeaseOwnerKind;
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
}

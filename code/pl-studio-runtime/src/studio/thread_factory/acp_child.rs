//! ACP children use the existing workspace and final-worktree owners, not Native Threads.
use super::{StudioThreadFactory, child_resources::PreparedChildWorkspace, errors::resource_error};
use crate::studio::store::agent_close::{AgentCloseRecord, OwnedWorktreeBinding};
use crate::thread_assembler::{ChildThreadRequest, ThreadAssemblyError};
use anyhow::{Context, ensure};
use pl_tool::collaboration::control::{AgentCloseResult, AgentWorktreeCleanup};

impl StudioThreadFactory {
    fn validate_acp_close(&self, id: &str, record: &AgentCloseRecord) -> anyhow::Result<()> {
        let member = self.directory_member(id)?;
        ensure!(
            matches!(
                member.agent.backend,
                pl_protocol::session::AgentBackend::Acp { .. }
            ),
            "ACP close requires an ACP member"
        );
        ensure!(
            record.agent_id == id
                && member.parent_thread_id.as_deref() == Some(record.parent_id.as_str())
                && member.root_thread_id == record.root_id
                && member.session.workspace_id == record.workspace_id,
            "ACP close identity changed"
        );
        if let Some(binding) = &record.worktree {
            let actual = self
                .services
                .worktrees
                .get(id)
                .context("ACP worktree lease is missing")?;
            let frozen = &binding.lease;
            ensure!(
                actual.owner_kind == frozen.owner_kind
                    && actual.owner_thread_id == frozen.owner_thread_id
                    && actual.root_thread_id == frozen.root_thread_id
                    && actual.workspace_id == frozen.workspace_id
                    && actual.repository_root == frozen.repository_root
                    && actual.path == frozen.path
                    && actual.base_commit == frozen.base_commit
                    && actual.ssh_alias == frozen.ssh_alias,
                "ACP worktree ownership changed"
            );
        }
        Ok(())
    }

    pub(crate) async fn begin_acp_child_close(
        &self,
        id: &str,
        force: bool,
    ) -> anyhow::Result<AgentCloseResult> {
        if let Some(mut record) = self.services.store.agent_close(id).await? {
            self.validate_acp_close(id, &record)?;
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
                    .restore_workspace_seal(id, binding.identity.clone())?;
            }
            return Ok(record.result());
        }
        let member = self.directory_member(id)?;
        let pl_protocol::session::AgentBackend::Acp { .. } = &member.agent.backend else {
            anyhow::bail!("ACP close requires an ACP member");
        };
        let parent = member
            .parent_thread_id
            .clone()
            .context("cannot close root as child")?;
        let worktree = if let Some(lease) = self.services.worktrees.get(id) {
            ensure!(
                lease.owner_kind
                    == crate::studio::agent_host::worktree_lease::WorktreeLeaseOwnerKind::Child
                    && lease.root_thread_id == member.root_thread_id
                    && lease.workspace_id == member.session.workspace_id,
                "ACP child does not own this worktree"
            );
            let identity = crate::studio::agent_host::workspace_preparation::cleanup_identity(
                &self.services.store,
                &lease,
            )
            .await?;
            ensure!(
                self.services.store.workspace_identity(id).await?.as_ref() == Some(&identity)
                    && identity.matches_root(&lease.path),
                "ACP execution workspace changed"
            );
            Some(OwnedWorktreeBinding { lease, identity })
        } else {
            None
        };
        let record = AgentCloseRecord {
            agent_id: id.into(),
            parent_id: parent,
            root_id: member.root_thread_id,
            workspace_id: member.session.workspace_id,
            revision: 1,
            force,
            worktree,
            git: None,
            execution_closed: false,
            worktree_cleanup: AgentWorktreeCleanup::Pending,
            error: None,
        };
        self.save_child_close_intent(&record).await?;
        Ok(record.result())
    }

    pub(crate) async fn finish_acp_child_close(
        &self,
        id: &str,
    ) -> anyhow::Result<(AgentCloseResult, Option<pl_protocol::StateError>)> {
        let mut record = self
            .services
            .store
            .agent_close(id)
            .await?
            .context("ACP close intent is missing")?;
        self.validate_acp_close(id, &record)?;
        self.services.worktrees.ensure_thread_workspace_idle(id)?;
        if !record.execution_closed {
            record.execution_closed = true;
            record.error = None;
            record.changed()?;
            self.services.store.save_agent_close(&record).await?;
        }
        self.services
            .product_events
            .commit_explicit_close(id)
            .await?;
        if record.worktree.is_none()
            && let Some(identity) = self.services.store.workspace_identity(id).await?
        {
            self.services
                .worktrees
                .release_workspace_resources(id, &identity)?;
        }
        match self.cleanup_one_owned_worktree(&mut record).await {
            Ok(()) => Ok((record.result(), None)),
            Err(error) => {
                record.error = Some(crate::studio::agent_close::state_error(&error));
                record.changed()?;
                self.services.store.save_agent_close(&record).await?;
                Ok((record.result(), record.error))
            }
        }
    }

    pub(crate) async fn directory_rows_for_root(
        &self,
        caller: &str,
    ) -> anyhow::Result<Vec<(pl_protocol::SessionDirectoryRow, bool)>> {
        let caller = self.directory_member(caller)?;
        let members = self
            .services
            .store
            .read_directory_tree(&caller.root_thread_id)
            .await?;
        Ok(members
            .into_iter()
            .map(|member| (member.row(), member.agent.explicitly_closed))
            .collect())
    }

    pub(in crate::studio) async fn verify_acp_workspace(
        &self,
        id: &str,
        project: &crate::studio::WorkspaceRecord,
        business_root: &str,
    ) -> anyhow::Result<()> {
        let frozen = self
            .services
            .store
            .workspace_identity(id)
            .await?
            .ok_or_else(|| anyhow::anyhow!("ACP member has no physical workspace identity"))?;
        let actual = self
            .resolve_workspace_identity(project, std::path::Path::new(business_root))
            .await?;
        anyhow::ensure!(frozen == actual, "ACP physical workspace identity changed");
        if let Some(lease) = self.services.worktrees.get(id) {
            lease.validate_identity()?;
            anyhow::ensure!(
                actual.matches_root(&lease.path),
                "ACP worktree binding changed"
            );
        }
        Ok(())
    }

    pub(in crate::studio) async fn prepare_acp_child_workspace(
        &self,
        request: &ChildThreadRequest,
        mode: pl_protocol::AgentWorkspaceMode,
    ) -> Result<PreparedChildWorkspace, ThreadAssemblyError> {
        let prepared = self.prepare_child_workspace(request, mode).await?;
        if let Some(worktree) = &prepared.worktree {
            self.confirm_worktree_binding(
                &worktree.lease,
                &prepared.workspace_usage,
                &request.workspace_owner,
            )
            .await
            .map_err(|error| resource_error("activate ACP child workspace", error))?;
        }
        Ok(prepared)
    }
}

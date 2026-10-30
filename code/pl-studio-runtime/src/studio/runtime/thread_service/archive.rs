//! The archive worker owns admission, the original binding and every incomplete cleanup step.
use std::path::Path;

use anyhow::{Context, Result, ensure};
use pl_tool::workspace::{SessionFiles, SessionTempBackend, path_safety};

use super::super::StudioRuntime;
use crate::studio::{
    ThreadRecord,
    agent_host::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity},
    store::thread_archive::{ArchiveMember, ArchivePhase, ArchiveScope, ThreadArchiveOperation},
};

impl StudioRuntime {
    pub(super) async fn freeze_thread_archive(
        &self,
        scope: ArchiveScope,
        threads: &[ThreadRecord],
    ) -> Result<ThreadArchiveOperation> {
        let previous = self.store.thread_archive(&scope).await?;
        if let Some(operation) = &previous
            && operation.phase != ArchivePhase::Published
        {
            let expected = operation
                .members
                .iter()
                .map(|member| &member.thread_id)
                .collect::<std::collections::BTreeSet<_>>();
            let actual = threads
                .iter()
                .map(|thread| &thread.id)
                .collect::<std::collections::BTreeSet<_>>();
            ensure!(
                actual == expected,
                "archive scope changed while cleanup was pending"
            );
            return Ok(operation.clone());
        }
        for pending in self.store.thread_archives().await? {
            if pending.phase != ArchivePhase::Published {
                ensure!(
                    !pending
                        .members
                        .iter()
                        .any(|member| threads.iter().any(|thread| thread.id == member.thread_id)),
                    "overlapping archive operation must be retried first"
                );
            }
        }
        let mut members = Vec::new();
        for thread in threads {
            let execution = match self.store.workspace_identity(&thread.id).await? {
                Some(identity) => identity,
                None => {
                    let project = self
                        .store
                        .workspaces()
                        .get(&thread.workspace_id)
                        .context("archive workspace is not registered")?
                        .project();
                    if let Some(bot) = self.bots.config_for_thread(&thread.root_thread_id).await? {
                        WorkspaceIdentity::canonical(
                            WorkspaceEndpoint::Local,
                            self.bots
                                .workspace_root(&bot)
                                .to_string_lossy()
                                .into_owned(),
                        )?
                    } else if project.ssh_alias.is_some() {
                        self.thread_factory
                            .resolve_workspace_identity(&project, Path::new(&thread.workspace_path))
                            .await?
                    } else {
                        WorkspaceIdentity::canonical(
                            WorkspaceEndpoint::Local,
                            thread.workspace_path.clone(),
                        )?
                    }
                }
            };
            let session = self.store.session_paths(&thread.workspace_id, &thread.id)?;
            members.push(ArchiveMember {
                thread_id: thread.id.clone(),
                workspace_id: thread.workspace_id.clone(),
                host_session: session.root().to_owned(),
                host_temp: session.temp_dir(),
                execution,
                host_cleaned: false,
                execution_cleaned: false,
            });
        }
        let revision = previous.map_or(Ok(1), |previous| {
            previous
                .revision
                .checked_add(1)
                .context("archive revision exhausted")
        })?;
        let operation = ThreadArchiveOperation {
            scope,
            revision,
            members,
            phase: ArchivePhase::Sealed,
        };
        self.store.save_thread_archive(&operation).await?;
        Ok(operation)
    }

    pub(super) async fn archive_save_confirmed(
        &self,
        operation: &mut ThreadArchiveOperation,
    ) -> Result<()> {
        if operation.phase == ArchivePhase::Sealed {
            operation.phase = ArchivePhase::Saved;
            operation.changed()?;
            self.store.save_thread_archive(operation).await?;
        }
        Ok(())
    }

    /// Invoked only after close_tree returned its stop/join/writer ACK and resource-release ACK.
    pub(super) async fn clean_archive_temps(
        &self,
        operation: &mut ThreadArchiveOperation,
    ) -> Result<()> {
        ensure!(
            operation.phase != ArchivePhase::Sealed,
            "archive has no durable save confirmation"
        );
        for index in 0..operation.members.len() {
            let member = operation.members[index].clone();
            if !member.execution_cleaned {
                let files = SessionFiles::new(&member.thread_id);
                match &member.execution.endpoint {
                    WorkspaceEndpoint::Local => {
                        let backend = SessionTempBackend::Local(Path::new(&member.execution.root));
                        backend.migrate(&files).await?;
                        backend.remove(&files).await?;
                    }
                    WorkspaceEndpoint::Ssh { .. } => {
                        let profile = self
                            .ssh_manager
                            .list_servers()
                            .await
                            .into_iter()
                            .find(|entry| {
                                WorkspaceEndpoint::from_profile(Some(&entry.profile))
                                    == member.execution.endpoint
                            })
                            .context("archive frozen SSH endpoint is no longer configured")?
                            .profile;
                        let host = self
                            .ssh_manager
                            .open_workspace_host(&profile.alias, member.execution.root.clone())
                            .await?;
                        ensure!(
                            WorkspaceEndpoint::from_profile(Some(&host.profile))
                                == member.execution.endpoint
                                && host.files.canonical_path() == member.execution.root,
                            "archive SSH endpoint or canonical root changed"
                        );
                        let backend = SessionTempBackend::Ssh(&host.files);
                        backend.migrate(&files).await?;
                        backend.remove(&files).await?;
                    }
                }
                operation.members[index].execution_cleaned = true;
                operation.changed()?;
                self.store.save_thread_archive(operation).await?;
            }
            if !member.host_cleaned {
                let current = self
                    .store
                    .session_paths(&member.workspace_id, &member.thread_id)?;
                ensure!(
                    current.root() == member.host_session && current.temp_dir() == member.host_temp,
                    "archive host session binding changed"
                );
                let anchor = member
                    .host_session
                    .ancestors()
                    .last()
                    .context("archive host path has no root")?;
                path_safety::validate_path_for_write_async(anchor, &member.host_session).await?;
                match tokio::fs::symlink_metadata(&member.host_temp).await {
                    Ok(_) => {
                        path_safety::validate_existing_path_async(
                            &member.host_session,
                            &member.host_temp,
                        )
                        .await?;
                        path_safety::remove_dir_all_no_follow_async(
                            &member.host_session,
                            &member.host_temp,
                        )
                        .await?;
                    }
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                    Err(error) => return Err(error.into()),
                }
                operation.members[index].host_cleaned = true;
                operation.changed()?;
                self.store.save_thread_archive(operation).await?;
            }
        }
        operation.phase = ArchivePhase::Cleaned;
        operation.changed()?;
        self.store.save_thread_archive(operation).await
    }

    pub(super) async fn archive_published(
        &self,
        operation: &mut ThreadArchiveOperation,
    ) -> Result<()> {
        operation.phase = ArchivePhase::Published;
        operation.changed()?;
        self.store.save_thread_archive(operation).await
    }
}

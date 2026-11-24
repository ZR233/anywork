//! The archive worker owns admission, the original binding and every incomplete cleanup step.
use std::path::Path;

use anyhow::{Context, Result, ensure};
use pl_tool::workspace::{SessionFiles, SessionTempBackend, path_safety};

use super::super::StudioRuntime;
use crate::studio::{
    records::DirectoryMember,
    store::thread_archive::{
        ArchiveMember, ArchivePhase, ArchiveScope, PrivateArchiveMember, ThreadArchiveOperation,
    },
    store::thread_preparation::{PreparationBinding, PreparationIdentity, PreparationSave},
    worktree::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity},
};

#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) enum ArchivePurpose {
    Preserve,
    Delete,
}

enum ArchiveTempTarget {
    Public(usize),
    Private(usize),
}

struct HostTempBinding<'a> {
    workspace_id: &'a str,
    thread_id: &'a str,
    host_session: &'a Path,
    host_temp: &'a Path,
    mismatch: &'static str,
}

impl StudioRuntime {
    pub(super) async fn freeze_thread_archive(
        &self,
        scope: ArchiveScope,
        threads: &[DirectoryMember],
        admitted: &[PreparationIdentity],
    ) -> Result<ThreadArchiveOperation> {
        let operation = self
            .freeze_archive_scope(scope, threads, admitted, ArchivePurpose::Preserve)
            .await?;
        self.store.save_thread_archive(&operation).await?;
        Ok(operation)
    }

    pub(super) async fn freeze_thread_removal(
        &self,
        scope: ArchiveScope,
        threads: &[DirectoryMember],
        admitted: &[PreparationIdentity],
    ) -> Result<ThreadArchiveOperation> {
        self.freeze_archive_scope(scope, threads, admitted, ArchivePurpose::Delete)
            .await
    }

    pub(super) async fn restore_deleted_members(
        &self,
        archive: &mut ThreadArchiveOperation,
        deletion: &crate::studio::store::thread_delete::ThreadDeleteOperation,
    ) -> Result<()> {
        // The durable deletion is the complete identity/binding authority. Auxiliary archive
        // rows may retain progress, but losing them cannot shrink this frozen responsibility.
        for frozen in &deletion.members {
            let record = self
                .store
                .thread_preparation_for_deletion(&frozen.identity.thread_id)
                .await?;
            if let Some(record) = &record {
                ensure!(
                    record.identity == frozen.identity,
                    "delete preparation original identity changed"
                );
                if let (
                    PreparationBinding::Bound { identity: original },
                    PreparationBinding::Bound { identity: current },
                ) = (&frozen.execution, &record.binding)
                {
                    ensure!(
                        original == current,
                        "delete preparation original binding changed"
                    );
                }
            }
            if let Some(member) = archive
                .members
                .iter()
                .find(|member| member.thread_id == frozen.identity.thread_id)
            {
                ensure!(
                    member.workspace_id == frozen.identity.workspace_id
                        && member.root_id == frozen.identity.root_id
                        && member.parent_id == frozen.identity.parent_id
                        && member.host_session == frozen.host_session,
                    "delete archive member changed its original identity"
                );
                if let PreparationBinding::Bound { identity } = &frozen.execution {
                    ensure!(
                        *identity == member.execution,
                        "delete archive original binding changed"
                    );
                }
                continue;
            }
            if let Some(member) = archive
                .private_members
                .iter_mut()
                .find(|member| member.identity.thread_id == frozen.identity.thread_id)
            {
                ensure!(
                    member.identity == frozen.identity
                        && member.host_session == frozen.host_session,
                    "delete archive member changed its original identity"
                );
                if let PreparationBinding::Bound { .. } = &frozen.execution {
                    ensure!(
                        member.binding == PreparationBinding::Unbound
                            || member.binding == frozen.execution,
                        "delete archive original binding changed"
                    );
                    member.binding = frozen.execution.clone();
                }
                continue;
            }
            let binding = if frozen.execution == PreparationBinding::Unbound {
                record
                    .as_ref()
                    .map(|record| record.binding.clone())
                    .unwrap_or(PreparationBinding::Unbound)
            } else {
                frozen.execution.clone()
            };
            let host_temp = frozen.host_session.join("temp");
            if let PreparationBinding::Bound { identity } = &binding
                && record.as_ref().is_none_or(|record| record.published)
            {
                archive.members.push(ArchiveMember {
                    association_only: frozen.association_only,
                    thread_id: frozen.identity.thread_id.clone(),
                    workspace_id: frozen.identity.workspace_id.clone(),
                    root_id: frozen.identity.root_id.clone(),
                    parent_id: frozen.identity.parent_id.clone(),
                    host_session: frozen.host_session.clone(),
                    host_temp,
                    execution: identity.clone(),
                    host_cleaned: false,
                    execution_cleaned: false,
                });
            } else {
                archive.private_members.push(PrivateArchiveMember {
                    identity: frozen.identity.clone(),
                    host_session: frozen.host_session.clone(),
                    host_temp,
                    binding,
                    stopped: record.as_ref().is_some_and(|record| record.stopped),
                    save: record
                        .as_ref()
                        .map_or(PreparationSave::Unattached, |record| record.save),
                    retired: record.as_ref().is_some_and(|record| record.retired),
                    host_cleaned: false,
                    execution_cleaned: false,
                });
            }
        }
        Ok(())
    }

    pub(super) async fn archive_save_confirmed(
        &self,
        operation: &mut ThreadArchiveOperation,
    ) -> Result<()> {
        ensure!(
            operation.private_members.iter().all(|member| member.stopped
                && member.retired
                && member.save != PreparationSave::Required),
            "private archive members still have pending stop/save/resource responsibility"
        );
        if operation.phase == ArchivePhase::Sealed {
            operation.phase = ArchivePhase::Saved;
            operation.changed()?;
            self.store.save_thread_archive(operation).await?;
        }
        Ok(())
    }

    pub(super) async fn retire_private_archive_members(
        &self,
        operation: &mut ThreadArchiveOperation,
    ) -> Result<()> {
        for index in 0..operation.private_members.len() {
            let member = operation.private_members[index].clone();
            let mut record = self
                .store
                .thread_preparation(&member.identity.thread_id)
                .await?
                .context("private archive responsibility is missing")?;
            // Only the original incarnation can have persisted this closed/joined receipt.
            // It also proves producer stop if a crash separated receipt persistence from stop.
            if !record.stopped
                && record.save == PreparationSave::Confirmed
                && record.storage.as_ref().is_some_and(|storage| {
                    storage
                        .closed_receipt
                        .is_some_and(|through| through >= storage.required_through)
                })
            {
                self.store
                    .confirm_preparation_stop(&member.identity.thread_id)
                    .await?;
                record = self
                    .store
                    .thread_preparation(&member.identity.thread_id)
                    .await?
                    .context("original receipt owner disappeared")?;
            }
            ensure!(
                record.identity == member.identity && record.binding == member.binding,
                "private archive original binding changed"
            );
            ensure!(
                record.stopped && record.save != PreparationSave::Required,
                "private preparation has not acknowledged its original producers/checkpoint; responsibility retained"
            );
            if !record.retired {
                self.thread_factory
                    .retire_archive_preparation(&record)
                    .await?;
            }
            let confirmed = self
                .store
                .thread_preparation(&member.identity.thread_id)
                .await?
                .context("private retirement ACK disappeared")?;
            ensure!(
                confirmed.retired && confirmed.stopped,
                "private resource retirement remains pending"
            );
            operation.private_members[index].stopped = confirmed.stopped;
            operation.private_members[index].save = confirmed.save;
            operation.private_members[index].retired = confirmed.retired;
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
        // Public and private duties stay distinct, but each flag is still persisted alone.
        let targets = (0..operation.members.len())
            .map(ArchiveTempTarget::Public)
            .chain((0..operation.private_members.len()).map(ArchiveTempTarget::Private))
            .collect::<Vec<_>>();
        for target in targets {
            self.clean_archive_temp_target(operation, target).await?;
        }
        self.clean_archive_worktrees(operation).await?;
        operation.phase = ArchivePhase::Cleaned;
        operation.changed()?;
        self.store.save_thread_archive(operation).await
    }

    async fn clean_archive_temp_target(
        &self,
        operation: &mut ThreadArchiveOperation,
        target: ArchiveTempTarget,
    ) -> Result<()> {
        match target {
            ArchiveTempTarget::Public(index) => {
                let member = operation.members[index].clone();
                if member.association_only {
                    // ACP has only a product association, never Native SessionFiles or history.
                    return Ok(());
                }
                if !member.execution_cleaned {
                    if !execution_removed_with_worktree(operation, &member.execution) {
                        clean_execution_temp(&self.ssh_manager, &member).await?;
                    }
                    self.acknowledge_temp_flag(operation, |operation| {
                        operation.members[index].execution_cleaned = true;
                    })
                    .await?;
                }
                self.clean_recorded_host_temp(HostTempBinding {
                    workspace_id: &member.workspace_id,
                    thread_id: &member.thread_id,
                    host_session: &member.host_session,
                    host_temp: &member.host_temp,
                    mismatch: "archive host session binding changed",
                })
                .await?;
                if !member.host_cleaned {
                    self.acknowledge_temp_flag(operation, |operation| {
                        operation.members[index].host_cleaned = true;
                    })
                    .await?;
                }
                Ok(())
            }
            ArchiveTempTarget::Private(index) => {
                let member = operation.private_members[index].clone();
                ensure!(
                    member.stopped && member.retired && member.save != PreparationSave::Required,
                    "private producer/save ACK is pending"
                );
                if !member.execution_cleaned {
                    if let PreparationBinding::Bound { identity } = &member.binding
                        && !execution_removed_with_worktree(operation, identity)
                    {
                        clean_execution_temp(
                            &self.ssh_manager,
                            &ArchiveMember {
                                association_only: false,
                                thread_id: member.identity.thread_id.clone(),
                                workspace_id: member.identity.workspace_id.clone(),
                                parent_id: member.identity.parent_id.clone(),
                                root_id: member.identity.root_id.clone(),
                                host_session: member.host_session.clone(),
                                host_temp: member.host_temp.clone(),
                                execution: identity.clone(),
                                host_cleaned: member.host_cleaned,
                                execution_cleaned: false,
                            },
                        )
                        .await?;
                    }
                    self.acknowledge_temp_flag(operation, |operation| {
                        operation.private_members[index].execution_cleaned = true;
                    })
                    .await?;
                }
                self.clean_recorded_host_temp(HostTempBinding {
                    workspace_id: &member.identity.workspace_id,
                    thread_id: &member.identity.thread_id,
                    host_session: &member.host_session,
                    host_temp: &member.host_temp,
                    mismatch: "private host binding changed",
                })
                .await?;
                if !member.host_cleaned {
                    self.acknowledge_temp_flag(operation, |operation| {
                        operation.private_members[index].host_cleaned = true;
                    })
                    .await?;
                }
                self.store
                    .confirm_preparation_temp_cleanup(&member.identity, &member.binding)
                    .await?;
                Ok(())
            }
        }
    }

    async fn acknowledge_temp_flag(
        &self,
        operation: &mut ThreadArchiveOperation,
        mark: impl FnOnce(&mut ThreadArchiveOperation),
    ) -> Result<()> {
        mark(operation);
        operation.changed()?;
        self.store.save_thread_archive(operation).await
    }

    /// Host temp is removed on every retry. Resuming the archive reopens the session layout,
    /// which may recreate a directory this member already acknowledged as cleaned.
    async fn clean_recorded_host_temp(&self, binding: HostTempBinding<'_>) -> Result<()> {
        let current = self
            .store
            .session_paths(binding.workspace_id, binding.thread_id)?;
        ensure!(
            current.root() == binding.host_session && current.temp_dir() == binding.host_temp,
            "{}",
            binding.mismatch
        );
        clean_host_temp(binding.host_session, binding.host_temp).await
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

fn execution_removed_with_worktree(
    operation: &ThreadArchiveOperation,
    identity: &WorkspaceIdentity,
) -> bool {
    // A new archive/delete can revisit a previously archived SSH worktree. Opening that removed
    // directory would fail before reaching the existing Git absence verification below.
    operation.worktrees.iter().any(|worktree| {
        (worktree.cleaned
            || worktree.lease.state
                == crate::studio::worktree::worktree_lease::WorktreeLeaseState::Cleaned)
            && identity.within(&worktree.identity)
    })
}

async fn clean_host_temp(session: &Path, temp: &Path) -> Result<()> {
    let anchor = session
        .ancestors()
        .last()
        .context("archive host path has no root")?;
    path_safety::validate_path_for_write_async(anchor, session).await?;
    match tokio::fs::symlink_metadata(temp).await {
        Ok(_) => {
            path_safety::validate_existing_path_async(session, temp).await?;
            path_safety::remove_dir_all_no_follow_async(session, temp).await?;
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(error.into()),
    }
    Ok(())
}

async fn clean_execution_temp(
    ssh: &pl_tool::remote::SshManager,
    member: &ArchiveMember,
) -> Result<()> {
    let files = SessionFiles::new(&member.thread_id);
    match &member.execution.endpoint {
        WorkspaceEndpoint::Local => {
            let backend = SessionTempBackend::local(Path::new(&member.execution.root)).await?;
            backend.migrate(&files).await?;
            backend.remove(&files).await?;
        }
        WorkspaceEndpoint::Ssh { .. } => {
            let profile = ssh
                .list_servers()
                .await
                .into_iter()
                .find(|entry| {
                    WorkspaceEndpoint::from_profile(Some(&entry.profile))
                        == member.execution.endpoint
                })
                .context("archive frozen SSH endpoint is no longer configured")?
                .profile;
            let host = ssh
                .open_workspace_binding(&profile.alias, member.execution.root.clone())
                .await?;
            ensure!(
                WorkspaceEndpoint::from_profile(Some(&host.profile)) == member.execution.endpoint
                    && host.files().canonical_path() == member.execution.root,
                "archive SSH endpoint or canonical root changed"
            );
            let backend = SessionTempBackend::new(&host.files());
            backend.migrate(&files).await?;
            backend.remove(&files).await?;
        }
    }
    Ok(())
}

#[cfg(all(test, unix))]
mod ssh_tests {
    use super::*;

    #[tokio::test]
    async fn archive_temp_ssh_identity_change_and_disconnect_preserve_cleanup_responsibility()
    -> Result<()> {
        use pl_tool::remote::{SshConfigFile, SshManager, SshServerProfile};
        let temp = tempfile::tempdir()?;
        let config = temp.path().join("ssh-config");
        // `-F` uses only this fixture. No user SSH config, keys, agent or known_hosts are read.
        tokio::fs::write(&config,
            "Host *\n  UserKnownHostsFile /dev/null\n  GlobalKnownHostsFile /dev/null\n  IdentityAgent none\n  IdentityFile none\n  IdentitiesOnly yes\n").await?;
        let ssh = SshManager::new(None, None).with_ssh_config(SshConfigFile::at(&config));
        let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await?;
        let profile = SshServerProfile {
            alias: "isolated-archive".into(),
            host_name: "127.0.0.1".into(),
            port: listener.local_addr()?.port(),
            username: "isolated-fixture".into(),
            identity_file: None,
        };
        let host_session = temp.path().join("session");
        tokio::fs::create_dir_all(host_session.join("temp")).await?;
        tokio::fs::write(host_session.join("temp/transfer"), b"owned").await?;
        let member = ArchiveMember {
            association_only: false,
            thread_id: "ssh-thread".into(),
            workspace_id: "workspace".into(),
            parent_id: None,
            root_id: "ssh-thread".into(),
            host_temp: host_session.join("temp"),
            host_session,
            execution: WorkspaceIdentity::canonical(
                WorkspaceEndpoint::from_profile(Some(&profile)),
                "/isolated/workspace".into(),
            )?,
            host_cleaned: false,
            execution_cleaned: false,
        };
        let mut changed = profile.clone();
        changed.username = "different-identity".into();
        ssh.save_server(changed).await?;
        let mismatch = clean_execution_temp(&ssh, &member).await.unwrap_err();
        assert!(mismatch.to_string().contains("frozen SSH endpoint"));
        ssh.save_server(profile).await?;
        let mut peer = tokio::spawn(async move {
            let (stream, _) = listener.accept().await?;
            drop(stream); // Real SSH transport loss before a helper can report any path fact.
            Ok::<_, std::io::Error>(())
        });
        let outcome = tokio::time::timeout(
            std::time::Duration::from_secs(20),
            clean_execution_temp(&ssh, &member),
        )
        .await;
        ssh.shutdown().await?;
        match tokio::time::timeout(std::time::Duration::from_secs(2), &mut peer).await {
            Ok(joined) => joined??,
            Err(_) => {
                peer.abort();
                let _ = peer.await;
                anyhow::bail!("isolated SSH fixture was never contacted: {outcome:?}");
            }
        }
        let error = outcome?.expect_err("transport loss is not PathNotFound or archive success");
        assert!(
            error.downcast_ref::<pl_tool::remote::SshError>().is_some(),
            "the original transport error must survive the archive boundary"
        );
        assert!(!member.execution_cleaned && !member.host_cleaned);
        assert_eq!(
            tokio::fs::read(member.host_temp.join("transfer")).await?,
            b"owned"
        );
        Ok(())
    }
}

#[cfg(test)]
#[path = "archive_cold_tree_tests.rs"]
mod cold_tree;

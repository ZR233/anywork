//! The archive worker owns admission, the original binding and every incomplete cleanup step.
use std::path::Path;

use anyhow::{Context, Result, ensure};
use pl_tool::workspace::{SessionFiles, SessionTempBackend, path_safety};

use super::super::StudioRuntime;
use crate::studio::{
    ThreadRecord,
    agent_host::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity},
    store::thread_archive::{
        ArchiveMember, ArchivePhase, ArchiveScope, PrivateArchiveMember, ThreadArchiveOperation,
    },
    store::thread_preparation::{
        PreparationBinding, PreparationDisposition, PreparationIdentity, PreparationSave,
    },
};

impl StudioRuntime {
    pub(super) async fn freeze_thread_archive(
        &self,
        scope: ArchiveScope,
        threads: &[ThreadRecord],
        admitted: &[PreparationIdentity],
    ) -> Result<ThreadArchiveOperation> {
        let previous = self.store.thread_archive(&scope).await?;
        // These original responsibilities outlive both the registry owner and a failed first
        // threadArchive write. Discover by trusted identity, never by scanning physical paths.
        let mut admitted = admitted.to_vec();
        for record in self.store.thread_preparations().await? {
            let in_scope = match &scope {
                ArchiveScope::Thread(root) => record.identity.root_id == *root,
                ArchiveScope::Workspace(workspace) => record.identity.workspace_id == *workspace,
            };
            if in_scope
                && !record.published
                && record.disposition != PreparationDisposition::TempCleaned
                && !(record.disposition == PreparationDisposition::Remove && record.retired)
                && !admitted
                    .iter()
                    .any(|identity| identity.thread_id == record.identity.thread_id)
            {
                admitted.push(record.identity);
            }
        }
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
                expected.is_subset(&actual),
                "archive scope changed while cleanup was pending"
            );
            ensure!(
                actual == expected || operation.phase == ArchivePhase::Sealed,
                "archive gained a member after durable save confirmation"
            );
        }
        for pending in self.store.thread_archives().await? {
            if pending.phase != ArchivePhase::Published && pending.scope != scope {
                ensure!(
                    !pending
                        .thread_ids()
                        .iter()
                        .any(|id| threads.iter().any(|thread| thread.id == *id)
                            || admitted.iter().any(|member| member.thread_id == *id)),
                    "overlapping archive operation must be retried first"
                );
            }
        }
        let mut members = previous
            .as_ref()
            .filter(|operation| operation.phase != ArchivePhase::Published)
            .map(|operation| operation.members.clone())
            .unwrap_or_default();
        for identity in &admitted {
            self.store
                .begin_thread_preparation(identity.clone())
                .await?;
        }
        for thread in threads {
            let preparation = self.store.thread_preparation(&thread.id).await?;
            if preparation.as_ref().is_some_and(|record| !record.published) {
                members.retain(|member| member.thread_id != thread.id);
                continue;
            }
            if let Some(member) = members.iter().find(|member| member.thread_id == thread.id) {
                ensure!(
                    member.workspace_id == thread.workspace_id
                        && member.parent_id == thread.parent_thread_id
                        && member.root_id == thread.root_thread_id,
                    "archive canonical member changed identity"
                );
                if let Some(PreparationBinding::Bound { identity }) =
                    preparation.map(|record| record.binding)
                {
                    ensure!(
                        identity == member.execution,
                        "archive canonical member rebound during preparation"
                    );
                }
                continue;
            }
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
                parent_id: thread.parent_thread_id.clone(),
                root_id: thread.root_thread_id.clone(),
                host_session: session.root().to_owned(),
                host_temp: session.temp_dir(),
                execution,
                host_cleaned: false,
                execution_cleaned: false,
            });
        }
        let mut private_members = previous
            .as_ref()
            .filter(|operation| operation.phase != ArchivePhase::Published)
            .map(|operation| operation.private_members.clone())
            .unwrap_or_default();
        let mut private_identities = private_members
            .iter()
            .map(|member| member.identity.clone())
            .collect::<Vec<_>>();
        for identity in &admitted {
            if !members
                .iter()
                .any(|member| member.thread_id == identity.thread_id)
                && !private_identities
                    .iter()
                    .any(|previous| previous.thread_id == identity.thread_id)
            {
                // A live captured admission cannot start physical preparation before this same
                // typed original-owner record commits. This is not absence-based recovery.
                self.store
                    .begin_thread_preparation(identity.clone())
                    .await?;
                private_identities.push(identity.clone());
            }
        }
        for identity in private_identities {
            let mut record = self
                .store
                .thread_preparation(&identity.thread_id)
                .await?
                .context("archive lost its original private preparation responsibility")?;
            ensure!(
                record.identity == identity,
                "private archive identity changed"
            );
            if let Some(public) = members
                .iter()
                .find(|member| member.thread_id == identity.thread_id)
            {
                ensure!(
                    public.workspace_id == identity.workspace_id
                        && public.parent_id == identity.parent_id
                        && public.root_id == identity.root_id,
                    "published private member changed identity"
                );
                if let PreparationBinding::Bound { identity: original } = &record.binding {
                    ensure!(
                        *original == public.execution,
                        "private member rebound during publication"
                    );
                }
                private_members.retain(|member| member.identity.thread_id != identity.thread_id);
                continue;
            }
            if record.disposition == PreparationDisposition::Remove && record.retired {
                private_members.retain(|member| member.identity.thread_id != identity.thread_id);
                continue;
            }
            if matches!(
                record.disposition,
                PreparationDisposition::Pending | PreparationDisposition::Remove
            ) {
                self.store
                    .set_preparation_disposition(
                        &identity.thread_id,
                        PreparationDisposition::ArchivePreserve,
                    )
                    .await?;
                record = self
                    .store
                    .thread_preparation(&identity.thread_id)
                    .await?
                    .context("original preserve responsibility disappeared")?;
            }
            if let Some(member) = private_members
                .iter_mut()
                .find(|member| member.identity.thread_id == identity.thread_id)
            {
                if let PreparationBinding::Bound { identity: original } = &member.binding {
                    ensure!(
                        record.binding
                            == PreparationBinding::Bound {
                                identity: original.clone()
                            },
                        "private archive original binding changed"
                    );
                }
                member.binding = record.binding;
                member.stopped = record.stopped;
                member.save = record.save;
                member.retired = record.retired;
            } else {
                let session = self
                    .store
                    .session_paths(&identity.workspace_id, &identity.thread_id)?;
                private_members.push(PrivateArchiveMember {
                    identity,
                    host_session: session.root().to_owned(),
                    host_temp: session.temp_dir(),
                    binding: record.binding,
                    stopped: record.stopped,
                    save: record.save,
                    retired: record.retired,
                    host_cleaned: false,
                    execution_cleaned: false,
                });
            }
        }
        let phase = previous
            .as_ref()
            .filter(|operation| operation.phase != ArchivePhase::Published)
            .map_or(ArchivePhase::Sealed, |operation| operation.phase);
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
            private_members,
            phase,
        };
        self.store.save_thread_archive(&operation).await?;
        Ok(operation)
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
        for index in 0..operation.members.len() {
            let member = operation.members[index].clone();
            if !member.execution_cleaned {
                clean_execution_temp(&self.ssh_manager, &member).await?;
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
        for index in 0..operation.private_members.len() {
            let member = operation.private_members[index].clone();
            ensure!(
                member.stopped && member.retired && member.save != PreparationSave::Required,
                "private producer/save ACK is pending"
            );
            if !member.execution_cleaned {
                if let PreparationBinding::Bound { identity } = &member.binding {
                    clean_execution_temp(
                        &self.ssh_manager,
                        &ArchiveMember {
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
                operation.private_members[index].execution_cleaned = true;
                operation.changed()?;
                self.store.save_thread_archive(operation).await?;
            }
            if !member.host_cleaned {
                let current = self
                    .store
                    .session_paths(&member.identity.workspace_id, &member.identity.thread_id)?;
                ensure!(
                    current.root() == member.host_session && current.temp_dir() == member.host_temp,
                    "private host binding changed"
                );
                clean_host_temp(&member.host_session, &member.host_temp).await?;
                operation.private_members[index].host_cleaned = true;
                operation.changed()?;
                self.store.save_thread_archive(operation).await?;
            }
            self.store
                .confirm_preparation_temp_cleanup(&member.identity, &member.binding)
                .await?;
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
            let backend = SessionTempBackend::Local(Path::new(&member.execution.root));
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
                .open_workspace_host(&profile.alias, member.execution.root.clone())
                .await?;
            ensure!(
                WorkspaceEndpoint::from_profile(Some(&host.profile)) == member.execution.endpoint
                    && host.files.canonical_path() == member.execution.root,
                "archive SSH endpoint or canonical root changed"
            );
            let backend = SessionTempBackend::Ssh(&host.files);
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
            error
                .downcast_ref::<pl_tool::remote::RemoteClientError>()
                .is_some(),
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

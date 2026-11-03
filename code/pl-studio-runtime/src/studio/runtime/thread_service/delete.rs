//! Explicit root deletion reuses the archive stop/save/resource owner.
use std::path::Path;

use anyhow::{Context, Result, ensure};
use pl_tool::workspace::{SessionFiles, SessionTempBackend, path_safety};

use super::super::{DeleteThreadCommandReply, StudioDeleteThreadResult, StudioRuntime};
use crate::studio::{
    agent_host::worktree_lease::WorkspaceEndpoint,
    store::{
        directory::DirectoryDelta,
        thread_archive::{ArchivePhase, ArchiveScope, ThreadArchiveOperation},
        thread_delete::{DeleteMember, DeletePhase, ThreadDeleteOperation},
        thread_preparation::{PreparationBinding, PreparationIdentity},
    },
};

impl StudioRuntime {
    pub async fn delete_thread(
        &self,
        operation_id: String,
        thread_id: String,
    ) -> Result<Option<DeleteThreadCommandReply>> {
        Self::validate_operation_id(&operation_id)?;
        let runtime = self.clone();
        self.run_thread_lifecycle_operation(async move {
            runtime.delete_thread_owned(operation_id, thread_id).await
        })
        .await
    }

    async fn delete_thread_owned(
        &self,
        operation_id: String,
        root_id: String,
    ) -> Result<Option<DeleteThreadCommandReply>> {
        let previous = self.store.thread_delete(&root_id).await?;
        if previous
            .as_ref()
            .is_some_and(|operation| operation.phase == DeletePhase::Published)
        {
            return Ok(None);
        }
        let root = self.store.read_thread(&root_id).await?;
        if let Some(root) = &root {
            ensure!(
                root.parent_thread_id.is_none() && root.root_thread_id == root_id,
                "permanent deletion requires a root Thread"
            );
        } else if previous.is_none() {
            return Ok(None);
        }
        let scope = self
            .threads
            .seal_archive_scope(std::slice::from_ref(&root_id))?;
        let workspace_id = root
            .as_ref()
            .map(|root| root.workspace_id.as_str())
            .or_else(|| {
                previous
                    .as_ref()
                    .and_then(|operation| operation.members.first())
                    .map(|member| member.identity.workspace_id.as_str())
            })
            .context("delete responsibility lost its original workspace")?
            .to_owned();
        let admitted = scope.preparation_identities(&workspace_id);
        let mut operation = if let Some(previous) = previous {
            previous
        } else {
            let tree = self.store.read_directory_tree(&root_id).await?;
            let archive = self
                .freeze_thread_archive(ArchiveScope::Thread(root_id.clone()), &tree, &admitted)
                .await?;
            let mut members = delete_members(&archive);
            // Finished private preparations can still own host history and external artifacts.
            for preparation in self.store.thread_preparations().await? {
                if preparation.identity.root_id == root_id
                    && !members
                        .iter()
                        .any(|member| member.identity.thread_id == preparation.identity.thread_id)
                {
                    members.push(DeleteMember {
                        host_session: self
                            .store
                            .session_paths(
                                &preparation.identity.workspace_id,
                                &preparation.identity.thread_id,
                            )?
                            .root()
                            .to_owned(),
                        identity: preparation.identity,
                        execution: preparation.binding,
                        execution_deleted: false,
                        host_deleted: false,
                        execution_removal_started: false,
                        host_removal_started: false,
                    });
                }
            }
            let mut thread_ids = members
                .iter()
                .map(|member| member.identity.thread_id.clone())
                .collect::<Vec<_>>();
            thread_ids.sort();
            thread_ids.dedup();
            let operation = ThreadDeleteOperation {
                root_id: root_id.clone(),
                thread_ids,
                revision: 1,
                phase: DeletePhase::Sealed,
                members,
            };
            self.store.save_thread_delete(&operation).await?;
            operation
        };
        let ids = operation.thread_ids.clone();
        let _pins = self.residency.pin_many(ids.iter().cloned());
        scope.cancel_preparations();
        let _bots = self.bots.quiesce_archive_threads(&ids).await?;
        if operation.phase == DeletePhase::Sealed {
            for id in &ids {
                self.title_tasks
                    .cancel(
                        id,
                        super::super::thread_title::ThreadTitleCancellationCause::ThreadArchive,
                    )
                    .await;
            }
            self.end_thread_tree_work(&ids).await?;
            tokio::time::timeout(
                self.archive_settle_timeout(),
                self.threads.drain_archive_preparations(&scope),
            )
            .await
            .context("delete preparations did not join")??;
            let tree = self.store.read_directory_tree(&root_id).await?;
            ensure!(
                tree.iter().all(|thread| ids.contains(&thread.id)),
                "delete scope gained an unfrozen member"
            );
            let mut archive = self
                .freeze_thread_archive(ArchiveScope::Thread(root_id.clone()), &tree, &admitted)
                .await?;
            ensure!(
                archive.thread_ids().iter().all(|id| ids.contains(id)),
                "delete preparation escaped its frozen scope"
            );
            // A preparation can bind only after the first durable deletion scope. Freeze that
            // original assignment after joining it, before any disposable or permanent removal.
            for member in delete_members(&archive) {
                let original = operation
                    .members
                    .iter_mut()
                    .find(|original| original.identity == member.identity)
                    .context("delete member changed its original identity")?;
                if original.execution == PreparationBinding::Unbound {
                    original.execution = member.execution;
                } else {
                    ensure!(
                        original.execution == member.execution,
                        "delete member rebound its execution endpoint"
                    );
                }
            }
            operation.changed()?;
            self.store.save_thread_delete(&operation).await?;
            if archive.phase == ArchivePhase::Sealed {
                let public = tree
                    .iter()
                    .map(|thread| thread.id.clone())
                    .collect::<Vec<_>>();
                self.retire_archived_thread_tree(&public).await?;
                self.retire_private_archive_members(&mut archive).await?;
            }
            self.archive_save_confirmed(&mut archive).await?;
            self.clean_archive_temps(&mut archive).await?;
            // Worktrees may contain this member's entire execution SessionFiles root.
            for member in &mut operation.members {
                member.execution_removal_started = false;
                member.host_removal_started = false;
                if let PreparationBinding::Bound { identity } = &member.execution {
                    member.execution_deleted = archive
                        .worktrees
                        .iter()
                        .any(|worktree| worktree.cleaned && identity.within(&worktree.identity));
                }
            }
            let _admission = self.store.deletion_storage_admission().await;
            operation.phase = DeletePhase::Removing;
            operation.changed()?;
            self.store.save_thread_delete(&operation).await?;
        }
        if operation.phase == DeletePhase::Removing {
            // No later handle can enter history_for after Removing commits. Existing handles
            // remain registered until their actual pools have released in-flight SQL.
            let histories = {
                let _admission = self.store.deletion_storage_admission().await;
                ids.iter()
                    .filter_map(|id| self.store.thread_persistence().shared_history(id))
                    .collect::<Vec<_>>()
            };
            for id in &ids {
                self.thread_observations
                    .observation_slot(id)
                    .close_readers()
                    .await?;
            }
            for history in histories {
                history.close_for_deletion().await?;
            }
            for id in &ids {
                self.store.thread_persistence().forget_deleted(id)?;
            }
            self.agent_facility
                .product_events
                .drain_directory_writes()
                .await?;
            self.store.calls().delete_threads(&ids).await?;
            self.bots.delete_threads(&ids).await?;
            self.delete_thread_settings(&ids)?;
            for index in 0..operation.members.len() {
                let member = operation.members[index].clone();
                if !member.execution_deleted {
                    self.delete_execution_session(&mut operation, index).await?;
                }
                if !member.host_deleted {
                    let current = self
                        .store
                        .session_paths(&member.identity.workspace_id, &member.identity.thread_id)?;
                    ensure!(
                        current.root() == member.host_session,
                        "delete host session binding changed"
                    );
                    if host_session_exists(&member.host_session).await? {
                        ensure!(
                            !member.host_removal_started,
                            "previous host session removal outcome is unresolved; existing object preserved"
                        );
                        operation.members[index].host_removal_started = true;
                        operation.changed()?;
                        self.store.save_thread_delete(&operation).await?;
                        path_safety::remove_dir_all_no_follow_async(
                            member
                                .host_session
                                .parent()
                                .context("delete session has no parent")?,
                            &member.host_session,
                        )
                        .await?;
                    }
                    operation.members[index].host_deleted = true;
                    operation.changed()?;
                    self.store.save_thread_delete(&operation).await?;
                }
            }
            self.store.delete_thread_product_data(&operation).await?;
            for id in &ids {
                self.agent_facility.worktrees.forget_deleted(id)?;
                self.recovery.delete_thread(id);
            }
            self.agent_facility
                .product_events
                .emit_recovery_state(self.recovery.state());
            operation.phase = DeletePhase::DataDeleted;
            operation.changed()?;
            self.store.save_thread_delete(&operation).await?;
        }
        let next_root = {
            let mut roots = self.store.list_root_threads(&workspace_id).await?;
            roots.retain(|thread| !ids.contains(&thread.id));
            roots.sort_by(|left, right| {
                right
                    .last_user_message_at
                    .unwrap_or(right.created_at)
                    .cmp(&left.last_user_message_at.unwrap_or(left.created_at))
                    .then_with(|| right.id.cmp(&left.id))
            });
            roots.into_iter().next()
        };
        let committed = self
            .agent_facility
            .product_events
            .commit_directory(DirectoryDelta::delete_threads(ids.clone()))
            .await?;
        self.agent_facility
            .product_events
            .drain_directory_writes()
            .await?;
        self.model_performance.delete_session(&root_id).await?;
        operation.phase = DeletePhase::Published;
        operation.members.clear();
        operation.changed()?;
        self.store.save_thread_delete(&operation).await?;
        Ok(Some(DeleteThreadCommandReply {
            result: StudioDeleteThreadResult {
                deleted_root_id: root_id,
                deleted_thread_ids: ids,
                next_root,
            },
            receipt: self.command_receipt(
                operation_id,
                true,
                vec![self.thread_directory_stamp(&committed)?],
                pl_protocol::studio::CommandEffectPoint::Immediate,
                false,
            ),
        }))
    }

    fn delete_thread_settings(&self, ids: &[String]) -> Result<()> {
        let current = self.config_runtime.read()?;
        self.config_runtime.update(current.revision, |desired| {
            let mut next = desired.clone();
            next.ui.pinned_thread_ids.retain(|id| !ids.contains(id));
            Ok(next)
        })?;
        self.publish_settings_state()?;
        Ok(())
    }

    async fn delete_execution_session(
        &self,
        operation: &mut ThreadDeleteOperation,
        index: usize,
    ) -> Result<()> {
        let member = operation.members[index].clone();
        if let PreparationBinding::Bound { identity } = &member.execution {
            match &identity.endpoint {
                WorkspaceEndpoint::Local => {
                    self.remove_bound_execution_session(
                        operation,
                        index,
                        SessionTempBackend::Local(Path::new(&identity.root)),
                    )
                    .await?;
                }
                WorkspaceEndpoint::Ssh { .. } => {
                    let profile = self
                        .ssh_manager
                        .list_servers()
                        .await
                        .into_iter()
                        .find(|entry| {
                            WorkspaceEndpoint::from_profile(Some(&entry.profile))
                                == identity.endpoint
                        })
                        .context("delete frozen SSH endpoint is no longer configured")?
                        .profile;
                    let host = self
                        .ssh_manager
                        .open_workspace_host(&profile.alias, identity.root.clone())
                        .await?;
                    ensure!(
                        WorkspaceEndpoint::from_profile(Some(&host.profile)) == identity.endpoint
                            && host.files.canonical_path() == identity.root,
                        "delete SSH endpoint or canonical root changed"
                    );
                    self.remove_bound_execution_session(
                        operation,
                        index,
                        SessionTempBackend::Ssh(&host.files),
                    )
                    .await?;
                }
            }
        }
        operation.members[index].execution_deleted = true;
        operation.changed()?;
        self.store.save_thread_delete(operation).await
    }

    async fn remove_bound_execution_session(
        &self,
        operation: &mut ThreadDeleteOperation,
        index: usize,
        backend: SessionTempBackend<'_>,
    ) -> Result<()> {
        let files = SessionFiles::new(&operation.members[index].identity.thread_id);
        if backend.session_exists(&files).await? {
            ensure!(
                !operation.members[index].execution_removal_started,
                "previous execution session removal outcome is unresolved; existing object preserved"
            );
            operation.members[index].execution_removal_started = true;
            operation.changed()?;
            self.store.save_thread_delete(operation).await?;
            backend.remove_session(&files).await?;
        }
        Ok(())
    }
}

fn delete_members(archive: &ThreadArchiveOperation) -> Vec<DeleteMember> {
    archive
        .members
        .iter()
        .map(|member| DeleteMember {
            identity: PreparationIdentity {
                thread_id: member.thread_id.clone(),
                workspace_id: member.workspace_id.clone(),
                parent_id: member.parent_id.clone(),
                root_id: member.root_id.clone(),
            },
            host_session: member.host_session.clone(),
            execution: PreparationBinding::Bound {
                identity: member.execution.clone(),
            },
            execution_deleted: false,
            host_deleted: false,
            execution_removal_started: false,
            host_removal_started: false,
        })
        .chain(archive.private_members.iter().map(|member| DeleteMember {
            identity: member.identity.clone(),
            host_session: member.host_session.clone(),
            execution: member.binding.clone(),
            execution_deleted: false,
            host_deleted: false,
            execution_removal_started: false,
            host_removal_started: false,
        }))
        .collect()
}

async fn host_session_exists(session: &Path) -> Result<bool> {
    let anchor = session
        .ancestors()
        .last()
        .context("delete host path has no root")?;
    path_safety::validate_path_for_write_async(anchor, session).await?;
    match tokio::fs::symlink_metadata(session).await {
        Ok(metadata) => {
            ensure!(
                metadata.is_dir() && !path_safety::is_link_or_reparse(&metadata),
                "delete host session is not an original dedicated directory"
            );
            Ok(true)
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(false),
        Err(error) => Err(error.into()),
    }
}

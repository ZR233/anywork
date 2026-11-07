//! Explicit root deletion reuses lifecycle and Git cleanup owners without cold archive repair.
use std::path::Path;

use anyhow::{Context, Result, ensure};
use pl_tool::workspace::{SessionFiles, SessionTempBackend, path_safety};

use super::super::{DeleteThreadCommandReply, StudioDeleteThreadResult, StudioRuntime};
use crate::studio::{
    agent_host::worktree_lease::WorkspaceEndpoint,
    store::{
        directory::DirectoryDelta,
        thread_archive::{ArchiveScope, ThreadArchiveOperation},
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
            let started = std::time::Instant::now();
            match runtime.delete_thread_owned(operation_id, thread_id.clone()).await {
                Ok(reply) => {
                    tracing::info!(%thread_id, elapsed_ms = started.elapsed().as_millis() as u64, "会话永久删除完成");
                    Ok(reply)
                }
                Err(error) => {
                    let stage = error.downcast_ref::<DeleteStage>().map_or("准备删除", |stage| stage.0);
                    let public = deletion_error(&error, stage, &thread_id);
                    tracing::error!(%thread_id, %stage, correlation_id = %public.correlation_id,
                        error_code = public.code.label(), elapsed_ms = started.elapsed().as_millis() as u64,
                        message = %public.message, "会话永久删除失败");
                    Err(error.context(public))
                }
            }
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
                .freeze_thread_removal(ArchiveScope::Thread(root_id.clone()), &tree, &admitted)
                .await?;
            let members = delete_members(&archive);
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
            self.store
                .save_thread_removal_scope(&archive, &operation)
                .await?;
            operation
        };
        let ids = operation.thread_ids.clone();
        let _pins = self.residency.pin_many(ids.iter().cloned());
        self.threads.prepare_deletion(&ids);
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
                .freeze_thread_removal(ArchiveScope::Thread(root_id.clone()), &tree, &admitted)
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
            self.store
                .save_thread_removal_scope(&archive, &operation)
                .await?;
            // Existing owners must really stop/join and release their storage and workspace
            // handles. Cold members have no producer to close and need no checkpoint recovery.
            let identities = operation
                .members
                .iter()
                .map(|member| member.identity.clone())
                .collect::<Vec<_>>();
            self.threads
                .close_tree_for_deletion(&root_id, &identities)
                .await
                .context(DeleteStage("停止会话与释放存储"))?;
            self.retire_private_deleted_members(&archive).await?;
            for id in &ids {
                self.residency.remove(id).await;
            }
            // Git owns worktree removal. Dedicated execution and host roots are removed below
            // as a whole; archive temp migration/cleanup would only traverse them twice.
            deletion_step(
                &root_id,
                "删除专属工作树",
                self.clean_archive_worktrees(&mut archive),
            )
            .await?;
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
            deletion_step(
                &root_id,
                "删除调用记录",
                self.store.calls().delete_threads(&ids),
            )
            .await?;
            self.bots.delete_threads(&ids).await?;
            self.delete_thread_settings(&ids)?;
            let mut remote_hosts = Vec::new();
            for index in 0..operation.members.len() {
                let member = operation.members[index].clone();
                if !member.execution_deleted {
                    deletion_step(
                        &root_id,
                        "删除执行端目录",
                        self.delete_execution_session(&mut operation, index, &mut remote_hosts),
                    )
                    .await?;
                }
                if !member.host_deleted {
                    deletion_step(
                        &root_id,
                        "删除宿主会话目录",
                        self.delete_host_session(&mut operation, index),
                    )
                    .await?;
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

    async fn retire_private_deleted_members(&self, archive: &ThreadArchiveOperation) -> Result<()> {
        for member in &archive.private_members {
            let record = self
                .store
                .thread_preparation(&member.identity.thread_id)
                .await?
                .context("private deletion responsibility is missing")?;
            ensure!(
                record.identity == member.identity && record.binding == member.binding,
                "private deletion original binding changed"
            );
            ensure!(
                record.stopped,
                "private deletion producers have not actually stopped"
            );
            if !record.retired {
                self.thread_factory
                    .retire_deleted_preparation(&record)
                    .await?;
            }
        }
        Ok(())
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
        remote_hosts: &mut Vec<(
            crate::studio::agent_host::worktree_lease::WorkspaceIdentity,
            pl_tool::remote::RemoteWorkspaceHost,
        )>,
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
                    let cached = remote_hosts
                        .iter()
                        .find(|(original, _)| original == identity)
                        .map(|(_, host)| host.clone());
                    let opened = if let Some(host) = cached {
                        Ok(host)
                    } else {
                        self.ssh_manager
                            .open_workspace_host(&profile.alias, identity.root.clone())
                            .await
                    };
                    let host = match opened {
                        Ok(host) => host,
                        Err(pl_tool::remote::RemoteClientError::Remote {
                            code: pl_protocol::remote::RemoteErrorCode::PathNotFound,
                            ..
                        }) => {
                            operation.members[index].execution_deleted = true;
                            operation.changed()?;
                            return self.store.save_thread_delete(operation).await;
                        }
                        Err(error) => return Err(error.into()),
                    };
                    ensure!(
                        WorkspaceEndpoint::from_profile(Some(&host.profile)) == identity.endpoint
                            && host.files.canonical_path() == identity.root,
                        "delete SSH endpoint or canonical root changed"
                    );
                    if !remote_hosts
                        .iter()
                        .any(|(original, _)| original == identity)
                    {
                        remote_hosts.push((identity.clone(), host.clone()));
                    }
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
        if operation.members[index].execution_removal_started {
            ensure!(
                !backend.session_exists(&files).await?,
                unresolved_removal("执行端目录")
            );
            return Ok(());
        }
        operation.members[index].execution_removal_started = true;
        operation.changed()?;
        self.store.save_thread_delete(operation).await?;
        if let Err(error) = backend.remove_session(&files).await {
            if error.definitely_not_started() {
                operation.members[index].execution_removal_started = false;
                operation.changed()?;
                self.store.save_thread_delete(operation).await?;
            }
            return Err(error.into());
        }
        Ok(())
    }

    async fn delete_host_session(
        &self,
        operation: &mut ThreadDeleteOperation,
        index: usize,
    ) -> Result<()> {
        let member = operation.members[index].clone();
        let current = self
            .store
            .session_paths(&member.identity.workspace_id, &member.identity.thread_id)?;
        ensure!(
            current.root() == member.host_session,
            "delete host session binding changed"
        );
        if member.host_removal_started {
            ensure!(
                !host_session_exists(&member.host_session).await?,
                unresolved_removal("宿主会话目录")
            );
        } else {
            operation.members[index].host_removal_started = true;
            operation.changed()?;
            self.store.save_thread_delete(operation).await?;
            let anchor = member
                .host_session
                .ancestors()
                .last()
                .context("delete host path has no root")?;
            if let Err(error) =
                path_safety::remove_dir_all_no_follow_async(anchor, &member.host_session).await
            {
                let absent = matches!(&error, path_safety::PathSafetyError::Io { source, .. } if source.kind() == std::io::ErrorKind::NotFound);
                if !absent {
                    let started = matches!(
                        &error,
                        path_safety::PathSafetyError::Io {
                            removal_started: true,
                            ..
                        }
                    );
                    if !started {
                        operation.members[index].host_removal_started = false;
                        operation.changed()?;
                        self.store.save_thread_delete(operation).await?;
                    }
                    return Err(error.into());
                }
            }
        }
        operation.members[index].host_deleted = true;
        operation.changed()?;
        self.store.save_thread_delete(operation).await
    }
}

#[derive(Debug, thiserror::Error)]
#[error("{0}")]
struct DeleteStage(&'static str);

async fn deletion_step<T>(
    thread_id: &str,
    stage: &'static str,
    operation: impl std::future::Future<Output = Result<T>>,
) -> Result<T> {
    let started = std::time::Instant::now();
    let result = operation.await.context(DeleteStage(stage));
    tracing::info!(%thread_id, %stage, elapsed_ms = started.elapsed().as_millis() as u64, success = result.is_ok(), "会话删除阶段结束");
    result
}

fn unresolved_removal(target: &str) -> pl_protocol::studio::StudioError {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Conflict,
        format!("上次删除{target}的结果无法确认，已保留现存目录，避免误删替换对象"),
        false,
    )
}

fn deletion_error(
    error: &anyhow::Error,
    stage: &str,
    thread_id: &str,
) -> pl_protocol::studio::StudioError {
    use pl_protocol::studio::{StudioError, StudioErrorCode};
    let mut public = if let Some(public) = error.downcast_ref::<StudioError>() {
        public.clone()
    } else if let Some(source) = error
        .chain()
        .find_map(|source| source.downcast_ref::<pl_tool::remote::RemoteClientError>())
    {
        crate::error_mapping::studio_error_from_anyhow_ref(&anyhow::Error::new(source.clone()))
    } else if let Some(source) = error
        .chain()
        .find_map(|source| source.downcast_ref::<std::io::Error>())
    {
        StudioError::new(
            if source.kind() == std::io::ErrorKind::PermissionDenied {
                StudioErrorCode::PermissionDenied
            } else {
                StudioErrorCode::Storage
            },
            format!("文件系统操作失败：{source}"),
            true,
        )
    } else if error.chain().any(|source| {
        matches!(
            source.downcast_ref::<path_safety::PathSafetyError>(),
            Some(
                path_safety::PathSafetyError::OutsideRoot { .. }
                    | path_safety::PathSafetyError::LinkOrReparse { .. }
            )
        )
    }) {
        StudioError::new(
            StudioErrorCode::Conflict,
            "原绑定路径已越界或包含链接，现存目录已保留",
            false,
        )
    } else {
        crate::error_mapping::studio_error_from_anyhow_ref(error)
    };
    if public.code == StudioErrorCode::Internal {
        public.message = "操作未能完成，请查看关联编号对应的诊断记录".into();
    }
    public.message = format!("永久删除在「{stage}」阶段失败：{}", public.message);
    let mut details = match public.details.take().map(|value| *value) {
        Some(serde_json::Value::Object(fields)) => fields,
        Some(value) => serde_json::Map::from_iter([("causeDetails".into(), value)]),
        None => serde_json::Map::new(),
    };
    details.extend(serde_json::Map::from_iter([
        ("operation".into(), "deleteThread".into()),
        ("stage".into(), stage.into()),
        ("threadId".into(), thread_id.into()),
    ]));
    public.with_details(serde_json::Value::Object(details))
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

#[cfg(test)]
mod error_tests {
    use super::*;

    #[test]
    fn deletion_context_preserves_typed_permission_and_original_details() {
        use pl_protocol::studio::{StudioError, StudioErrorCode};
        let original = StudioError::new(StudioErrorCode::PermissionDenied, "合成权限拒绝", false)
            .with_details(serde_json::json!({"reason": "syntheticPermission"}));
        let correlation = original.correlation_id.clone();
        let error = anyhow::Error::new(original).context(DeleteStage("删除执行端目录"));
        let public = deletion_error(&error, "删除执行端目录", "fixture-root");
        assert_eq!(public.code, StudioErrorCode::PermissionDenied);
        assert_eq!(public.correlation_id, correlation);
        assert!(!public.retryable);
        assert_eq!(
            public.details.as_ref().unwrap()["reason"],
            "syntheticPermission"
        );
        let remote = pl_tool::remote::RemoteClientError::AuthenticationFailed(
            pl_tool::remote::SshAuthFailure::new("fixture denied", vec![]),
        );
        let error = anyhow::Error::new(pl_tool::workspace::SessionRemovalError::Remote(remote))
            .context(DeleteStage("删除执行端目录"));
        let public = deletion_error(&error, "删除执行端目录", "fixture-root");
        assert_eq!(public.code, StudioErrorCode::PermissionDenied);
        assert_eq!(
            public.details.as_ref().unwrap()["sshErrorKind"],
            "authenticationFailed"
        );
    }
}

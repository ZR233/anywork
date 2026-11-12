//! Explicit root deletion reuses lifecycle and Git cleanup owners without cold archive repair.
use std::path::Path;

use anyhow::{Context, Result, ensure};
use pl_tool::workspace::{SessionFiles, SessionTempBackend, path_safety};
use tracing::Instrument;

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
        let span =
            tracing::info_span!("permanent_delete", deletion_id = %operation_id, root = %thread_id);
        self.run_thread_lifecycle_operation(async move {
            let started = std::time::Instant::now();
            match runtime.delete_thread_owned(operation_id, thread_id.clone()).await {
                Ok(reply) => {
                    tracing::info!(%thread_id, outcome = "completed", elapsed_ms = started.elapsed().as_millis() as u64, "会话永久删除完成");
                    Ok(reply)
                }
                Err(error) => {
                    let stage = error.downcast_ref::<DeleteStage>().map_or("准备删除", |stage| stage.0);
                    let public = deletion_error(&error, stage, &thread_id);
                    tracing::error!(%thread_id, %stage, correlation_id = %public.correlation_id,
                        error_code = public.code.label(), elapsed_ms = started.elapsed().as_millis() as u64,
                        reason = deletion_reason(&error), outcome = "incomplete", "会话永久删除失败");
                    Err(error.context(public))
                }
            }
        }.instrument(span))
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
        let root = self
            .agent_facility
            .product_events
            .directory_member(&root_id)?
            .or(self.store.directory_member(&root_id)?);
        if let Some(root) = &root {
            ensure!(
                root.parent_thread_id.is_none() && root.root_thread_id == root_id,
                "permanent deletion requires a root Thread"
            );
        } else if previous.is_none() {
            return Ok(None);
        }
        // Removing has already acknowledged every runtime owner. Later publication retries
        // must use the durable deletion responsibility, even after the directory is gone.
        let runtime_scope = if previous
            .as_ref()
            .is_none_or(|operation| operation.phase == DeletePhase::Sealed)
        {
            let session = self.session_for_roots(std::slice::from_ref(&root_id))?;
            let scope = session.seal_archive_scope(std::slice::from_ref(&root_id))?;
            Some((session, scope))
        } else {
            None
        };
        let workspace_id = root
            .as_ref()
            .map(|root| root.session.workspace_id.as_str())
            .or_else(|| {
                previous
                    .as_ref()
                    .and_then(|operation| operation.members.first())
                    .map(|member| member.identity.workspace_id.as_str())
            })
            .context("delete responsibility lost its original workspace")?
            .to_owned();
        let admitted = runtime_scope
            .as_ref()
            .map(|(_, scope)| scope.preparation_identities(&workspace_id))
            .unwrap_or_default();
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
        if let Some((session, scope)) = &runtime_scope {
            session.prepare_deletion(&ids);
            scope.cancel_preparations();
        }
        let _bots = self.bots.quiesce_archive_threads(&ids).await?;
        if operation.phase == DeletePhase::Sealed {
            let (session, scope) = runtime_scope
                .as_ref()
                .context("sealed deletion lost its original runtime responsibility")?;
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
                session.drain_archive_preparations(scope),
            )
            .await
            .context("delete preparations did not join")??;
            let tree = self.store.read_directory_tree(&root_id).await?;
            ensure!(
                tree.iter()
                    .all(|thread| ids.contains(&thread.agent.thread_id)),
                "delete scope gained an unfrozen member"
            );
            let archive = self
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
                ensure!(
                    original.association_only == member.association_only,
                    "delete backend changed"
                );
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
            session
                .close_tree_for_deletion(&root_id, &identities)
                .await
                .context(DeleteStage("停止会话与释放存储"))?;
            deletion_step(
                &root_id,
                "退役私有准备责任",
                self.retire_private_deleted_members(&archive),
            )
            .await?;
            for id in &ids {
                self.residency.remove(id).await;
            }
            // Git owns worktree removal. Dedicated execution and host roots are removed below
            // as a whole; archive temp migration/cleanup would only traverse them twice.
            // Worktrees may contain this member's entire execution SessionFiles root.
            for member in &mut operation.members {
                member.execution_removal_started = false;
                member.host_removal_started = false;
                if member.association_only {
                    member.execution_deleted = true;
                    member.host_deleted = true;
                } else if let PreparationBinding::Bound { identity } = &member.execution {
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
                operation
                    .members
                    .iter()
                    .filter(|member| !member.association_only)
                    .map(|member| &member.identity.thread_id)
                    .filter_map(|id| self.store.thread_persistence().shared_history(id))
                    .collect::<Vec<_>>()
            };
            for id in operation
                .members
                .iter()
                .filter(|member| !member.association_only)
                .map(|member| &member.identity.thread_id)
            {
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
            let mut failures = DeletionFailures::default();
            let mut blocked_worktrees = Vec::new();
            // Worktree progress is retained by its original archive owner. Removing means all
            // producers have joined, not that each independent physical target has disappeared.
            if let Some(mut archive) =
                crate::studio::store::object::load_deletion_aux::<ThreadArchiveOperation>(
                    self.store.database(),
                    &ArchiveScope::Thread(root_id.clone()).key(),
                )
                .await?
            {
                failures.record(
                    "删除专属工作树",
                    self.clean_deleted_worktrees(&mut archive).await,
                );
                blocked_worktrees.extend(
                    archive
                        .worktrees
                        .iter()
                        .filter(|worktree| !worktree.cleaned)
                        .map(|worktree| worktree.identity.clone()),
                );
                for member in &mut operation.members {
                    if let PreparationBinding::Bound { identity } = &member.execution
                        && archive
                            .worktrees
                            .iter()
                            .any(|worktree| worktree.cleaned && identity.within(&worktree.identity))
                    {
                        member.execution_deleted = true;
                    }
                }
                operation.changed()?;
                self.store.save_thread_delete(&operation).await?;
            }
            failures.record(
                "删除调用记录",
                deletion_step(
                    &root_id,
                    "删除调用记录",
                    self.store.calls().delete_threads(&ids),
                )
                .await,
            );
            failures.record(
                "删除机器人关联",
                deletion_step(&root_id, "删除机器人关联", async {
                    self.bots.delete_threads(&ids).await?;
                    Ok(())
                })
                .await,
            );
            failures.record("删除会话设置", self.delete_thread_settings(&ids));
            let mut remote_hosts = Vec::new();
            for index in 0..operation.members.len() {
                let member = operation.members[index].clone();
                if !member.execution_deleted {
                    if matches!(&member.execution, PreparationBinding::Bound { identity }
                        if blocked_worktrees.iter().any(|worktree| identity.within(worktree)))
                    {
                        tracing::warn!(stage = "删除执行端目录", member = %member.identity.thread_id,
                            reason = "worktree_unresolved", decision = "preserve", outcome = "incomplete",
                            "保留未确认工作树内的执行目录");
                        failures.record(
                            "删除执行端目录",
                            Err(anyhow::anyhow!(
                                "original worktree removal remains unresolved"
                            )),
                        );
                    } else {
                        failures.record(
                            "删除执行端目录",
                            deletion_step(
                                &member.identity.thread_id,
                                "删除执行端目录",
                                self.delete_execution_session(
                                    &mut operation,
                                    index,
                                    &mut remote_hosts,
                                ),
                            )
                            .await,
                        );
                    }
                }
                if !member.host_deleted {
                    failures.record(
                        "删除宿主会话目录",
                        deletion_step(
                            &member.identity.thread_id,
                            "删除宿主会话目录",
                            self.delete_host_session(&mut operation, index),
                        )
                        .await,
                    );
                }
            }
            // Product retirement would erase original lease/preparation responsibilities needed
            // by failed physical items. Keep those until all independent work has succeeded.
            failures.finish()?;
            self.store
                .delete_thread_product_data(&operation)
                .await
                .context(DeleteStage("删除产品记录"))?;
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
            let mut roots = self
                .store
                .directory_members_for_project(&workspace_id)?
                .into_iter()
                .filter(|member| member.agent.is_root_agent() && !member.session.archived)
                .map(|member| member.row())
                .collect::<Vec<_>>();
            roots.retain(|thread| !ids.contains(&thread.thread_id));
            roots.sort_by(|left, right| {
                right
                    .last_user_message_at
                    .unwrap_or(right.created_at)
                    .cmp(&left.last_user_message_at.unwrap_or(left.created_at))
                    .then_with(|| right.session_id.cmp(&left.session_id))
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
        #[cfg(test)]
        {
            let mut fault = self
                .s2_delete_publication_failure
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if fault.as_deref() == Some(root_id.as_str()) {
                fault.take();
                anyhow::bail!("injected failure before delete Published persistence");
            }
        }
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
                .thread_preparation_for_deletion(&member.identity.thread_id)
                .await?;
            let Some(record) = record else {
                tracing::info!(stage = "retire_private", member = %member.identity.thread_id,
                    reason = "preparation_unavailable", decision = "use_frozen_binding",
                    outcome = "skipped", "删除跳过不可用的准备记录");
                continue;
            };
            if record.identity != member.identity || record.binding != member.binding {
                tracing::warn!(stage = "退役私有准备责任", member = %member.identity.thread_id,
                    reason = "private_binding_changed", decision = "retain_retry",
                    outcome = "incomplete", "私有准备责任仍未收束");
                return Err(PrivateDeletionError::BindingChanged.into());
            }
            if !record.stopped {
                tracing::warn!(stage = "退役私有准备责任", member = %member.identity.thread_id,
                    reason = "private_producers_not_stopped", decision = "retain_retry",
                    outcome = "incomplete", "私有准备责任仍未收束");
                return Err(PrivateDeletionError::ProducersNotStopped.into());
            }
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
                        Err(error) if error.is_not_found() => {
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
        let mut intent = operation.clone();
        intent.members[index].execution_removal_started = true;
        intent.changed()?;
        self.store.save_thread_delete(&intent).await?;
        *operation = intent;
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
            let mut intent = operation.clone();
            intent.members[index].host_removal_started = true;
            intent.changed()?;
            self.store.save_thread_delete(&intent).await?;
            *operation = intent;
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

#[derive(Debug, thiserror::Error)]
enum PrivateDeletionError {
    #[error("private deletion original binding changed")]
    BindingChanged,
    #[error("private deletion producers have not actually stopped")]
    ProducersNotStopped,
}

pub(super) async fn deletion_step<T>(
    thread_id: &str,
    stage: &'static str,
    operation: impl std::future::Future<Output = Result<T>>,
) -> Result<T> {
    let started = std::time::Instant::now();
    let result = operation.await.context(DeleteStage(stage));
    match &result {
        Ok(_) => tracing::info!(member = %thread_id, %stage,
            elapsed_ms = started.elapsed().as_millis() as u64, reason = "completed",
            decision = "continue", outcome = "completed", "会话删除阶段结束"),
        Err(error) => {
            let io = error
                .chain()
                .find_map(|source| source.downcast_ref::<std::io::Error>());
            let parse = error
                .chain()
                .find_map(|source| source.downcast_ref::<serde_json::Error>());
            tracing::warn!(member = %thread_id, %stage,
                elapsed_ms = started.elapsed().as_millis() as u64,
                reason = deletion_reason(error), decision = "retain_retry", outcome = "incomplete",
                io_kind = ?io.map(std::io::Error::kind),
                os_code = io.and_then(std::io::Error::raw_os_error),
                line = parse.map(serde_json::Error::line),
                column = parse.map(serde_json::Error::column), "会话删除阶段结束");
        }
    }
    result
}

fn deletion_reason(error: &anyhow::Error) -> &'static str {
    if let Some(private) = error.downcast_ref::<PrivateDeletionError>() {
        return match private {
            PrivateDeletionError::BindingChanged => "private_binding_changed",
            PrivateDeletionError::ProducersNotStopped => "private_producers_not_stopped",
        };
    }
    if error.chain().any(|source| source.is::<std::io::Error>()) {
        "filesystem"
    } else if error.chain().any(|source| source.is::<serde_json::Error>()) {
        "decode"
    } else if error
        .chain()
        .any(|source| source.is::<pl_tool::remote::SshError>())
    {
        "remote"
    } else if error
        .chain()
        .any(|source| source.is::<path_safety::PathSafetyError>())
    {
        "path_boundary"
    } else if error.chain().any(|source| source.is::<sea_orm::DbErr>()) {
        "database"
    } else if error.chain().any(|source| {
        matches!(
            source.downcast_ref::<crate::thread_assembler::ThreadAssemblyError>(),
            Some(crate::thread_assembler::ThreadAssemblyError::Preparing(_))
        )
    }) {
        "preparation_owner_remaining"
    } else {
        "owner_or_storage"
    }
}

#[derive(Default)]
pub(super) struct DeletionFailures {
    first: Option<anyhow::Error>,
    incomplete: Vec<(&'static str, &'static str)>,
}

#[derive(Debug, thiserror::Error)]
#[error("permanent deletion has incomplete stages: {0:?}")]
struct IncompleteDeletion(Vec<(&'static str, &'static str)>);

impl DeletionFailures {
    pub(super) fn record(&mut self, stage: &'static str, result: Result<()>) {
        if let Err(error) = result {
            self.incomplete.push((stage, deletion_reason(&error)));
            tracing::warn!(%stage, reason = deletion_reason(&error), decision = "continue_independent",
                outcome = "incomplete", "删除保留未完成责任并继续独立项");
            if self.first.is_none() {
                self.first = Some(error.context(DeleteStage(stage)));
            }
        }
    }

    pub(super) fn finish(self) -> Result<()> {
        match self.first {
            Some(first) => Err(first.context(IncompleteDeletion(self.incomplete))),
            None => Ok(()),
        }
    }
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
        .find_map(|source| source.downcast_ref::<pl_tool::remote::SshError>())
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
            association_only: member.association_only,
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
            association_only: false,
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

    #[tokio::test]
    async fn private_retirement_failure_keeps_stage_and_safe_reason() {
        for (cause, reason) in [
            (
                PrivateDeletionError::BindingChanged,
                "private_binding_changed",
            ),
            (
                PrivateDeletionError::ProducersNotStopped,
                "private_producers_not_stopped",
            ),
        ] {
            let error = deletion_step::<()>("fixture-private", "退役私有准备责任", async {
                Err(cause.into())
            })
            .await
            .unwrap_err();
            let stage = error.downcast_ref::<DeleteStage>().unwrap().0;
            let public = deletion_error(&error, stage, "fixture-root");
            assert_eq!(stage, "退役私有准备责任");
            assert_eq!(deletion_reason(&error), reason);
            assert_eq!(public.details.as_ref().unwrap()["stage"], stage);
            assert!(public.message.contains(stage));
            assert!(!public.message.contains("private deletion"));
        }
    }

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
        let remote = pl_tool::remote::SshError::AuthenticationFailed(
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

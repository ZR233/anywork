//! Freeze stages for an archive or deletion scope.
//!
//! Preservation and deletion share the original-binding freeze, but their
//! predecessor, catalog, and preparation rules stay explicit. This is not the
//! deletion phase machine. The stages stay in this module because each one
//! consumes the previous stage's frozen identity.

use std::path::Path;

use anyhow::{Context, Result, ensure};

use super::super::StudioRuntime;
use super::archive::ArchivePurpose;
use crate::studio::store::object::{list_deletion_aux, load_deletion_aux};
use crate::studio::{
    agent_host::worktree_lease::{WorkspaceEndpoint, WorkspaceIdentity},
    records::DirectoryMember,
    store::thread_archive::{
        ArchiveMember, ArchivePhase, ArchiveScope, PrivateArchiveMember, ThreadArchiveOperation,
    },
    store::thread_delete::ThreadDeleteOperation,
    store::thread_preparation::{PreparationBinding, PreparationDisposition, PreparationIdentity},
};

fn merge_removal_root(
    target: &mut ThreadArchiveOperation,
    source: &ThreadArchiveOperation,
    root: &str,
) -> Result<()> {
    for member in source
        .members
        .iter()
        .filter(|member| member.root_id == root)
    {
        if let Some(original) = target
            .members
            .iter_mut()
            .find(|original| original.thread_id == member.thread_id)
        {
            ensure!(
                original.workspace_id == member.workspace_id
                    && original.parent_id == member.parent_id
                    && original.root_id == member.root_id
                    && original.association_only == member.association_only
                    && original.host_session == member.host_session
                    && original.execution == member.execution,
                "归档与删除的原会话绑定不一致"
            );
            original.host_cleaned |= member.host_cleaned;
            original.execution_cleaned |= member.execution_cleaned;
        } else {
            target.members.push(member.clone());
        }
    }
    for member in source
        .private_members
        .iter()
        .filter(|member| member.identity.root_id == root)
    {
        if let Some(original) = target
            .private_members
            .iter_mut()
            .find(|original| original.identity.thread_id == member.identity.thread_id)
        {
            ensure!(
                original.identity == member.identity
                    && original.host_session == member.host_session,
                "归档与删除的原准备身份不一致"
            );
            if original.binding == PreparationBinding::Unbound {
                original.binding = member.binding.clone();
            } else if member.binding != PreparationBinding::Unbound {
                ensure!(
                    original.binding == member.binding,
                    "归档与删除的原准备绑定不一致"
                );
            }
        } else {
            target.private_members.push(member.clone());
        }
    }
    let ids = target.thread_ids();
    for entry in source
        .worktrees
        .iter()
        .filter(|entry| ids.contains(&entry.lease.owner_thread_id))
    {
        if let Some(original) = target
            .worktrees
            .iter_mut()
            .find(|original| original.lease.owner_thread_id == entry.lease.owner_thread_id)
        {
            ensure!(
                original.identity == entry.identity
                    && (original.common_dir.is_none()
                        || entry.common_dir.is_none()
                        || original.common_dir == entry.common_dir),
                "归档与删除的原工作树绑定不一致"
            );
            if original.common_dir.is_none() {
                original.common_dir = entry.common_dir.clone();
            }
            original.removal_started |= entry.removal_started;
            original.cleaned |= entry.cleaned;
        } else {
            target.worktrees.push(entry.clone());
        }
    }
    Ok(())
}

struct ArchivePredecessor {
    previous: Option<ThreadArchiveOperation>,
    deletion: Option<ThreadDeleteOperation>,
    missing_delete_progress: bool,
    archives: Vec<ThreadArchiveOperation>,
}

impl StudioRuntime {
    pub(super) async fn freeze_archive_scope(
        &self,
        scope: ArchiveScope,
        threads: &[DirectoryMember],
        admitted: &[PreparationIdentity],
        purpose: ArchivePurpose,
    ) -> Result<ThreadArchiveOperation> {
        let loaded = self.load_archive_predecessor(&scope, purpose).await?;
        let catalog = self
            .project_archive_catalog(threads, purpose, &loaded.previous)
            .await?;
        let admitted = self
            .discover_archive_preparations(
                &scope,
                purpose,
                &catalog,
                admitted,
                &loaded.previous,
                &loaded.deletion,
            )
            .await?;
        self.reject_overlapping_archives(
            purpose,
            &scope,
            &loaded.previous,
            &catalog,
            &admitted,
            loaded.archives,
        )?;
        let members = self
            .freeze_public_archive_members(
                purpose,
                &loaded.deletion,
                &catalog,
                &admitted,
                &loaded.previous,
            )
            .await?;
        let private_members = self
            .freeze_private_archive_members(purpose, &loaded.previous, &admitted, &members)
            .await?;
        self.assemble_frozen_archive(
            scope,
            loaded.previous,
            loaded.missing_delete_progress,
            members,
            private_members,
        )
        .await
    }

    async fn load_archive_predecessor(
        &self,
        scope: &ArchiveScope,
        purpose: ArchivePurpose,
    ) -> Result<ArchivePredecessor> {
        let mut previous = if purpose == ArchivePurpose::Delete {
            load_deletion_aux(self.store.database(), &scope.key()).await?
        } else {
            self.store.thread_archive(&scope).await?
        };
        let deletion = if purpose == ArchivePurpose::Delete
            && let ArchiveScope::Thread(root) = scope
        {
            self.store.thread_delete(root).await?
        } else {
            None
        };
        let missing_delete_progress = deletion.is_some() && previous.is_none();
        let archives = if purpose == ArchivePurpose::Delete {
            list_deletion_aux(self.store.database()).await?
        } else {
            self.store.thread_archives().await?
        };
        if purpose == ArchivePurpose::Preserve {
            for deletion in self.store.thread_deletes().await? {
                if deletion.phase == crate::studio::store::thread_delete::DeletePhase::Published {
                    continue;
                }
                let overlaps = match scope {
                    ArchiveScope::Thread(root) => *root == deletion.root_id,
                    ArchiveScope::Workspace(workspace) => deletion
                        .members
                        .iter()
                        .any(|member| member.identity.workspace_id == *workspace),
                };
                ensure!(!overlaps, "会话永久删除尚未完成，请先重试删除");
            }
        } else if let ArchiveScope::Thread(root) = scope {
            let mut original = previous.take().unwrap_or(ThreadArchiveOperation {
                scope: scope.clone(),
                revision: 0,
                members: Vec::new(),
                private_members: Vec::new(),
                worktrees: Vec::new(),
                phase: ArchivePhase::Sealed,
            });
            // A permanent deletion takes over the original bindings and cleanup progress,
            // including private members no longer present in the directory or registry.
            original.phase = ArchivePhase::Sealed;
            for source in &archives {
                if matches!(source.scope, ArchiveScope::Workspace(_)) {
                    merge_removal_root(&mut original, source, root)?;
                }
            }
            if let Some(deletion) = &deletion {
                self.restore_deleted_members(&mut original, deletion)
                    .await?;
            }
            previous = Some(original);
        }
        Ok(ArchivePredecessor {
            previous,
            deletion,
            missing_delete_progress,
            archives,
        })
    }

    async fn project_archive_catalog(
        &self,
        threads: &[DirectoryMember],
        purpose: ArchivePurpose,
        previous: &Option<ThreadArchiveOperation>,
    ) -> Result<Vec<DirectoryMember>> {
        let mut catalog_projection = threads.to_vec();
        if let Some(operation) = previous
            && operation.phase != ArchivePhase::Published
        {
            for id in operation
                .private_members
                .iter()
                .map(|member| &member.identity.thread_id)
                .chain(
                    operation
                        .members
                        .iter()
                        .filter(|_| purpose == ArchivePurpose::Delete)
                        .map(|member| &member.thread_id),
                )
            {
                if !catalog_projection
                    .iter()
                    .any(|thread| thread.agent.thread_id == *id)
                    && let Some(canonical) = self.store.directory_member(id)?
                {
                    // Missing from a filtered tree is not proof of never having a catalog row.
                    // Validate its original identity below even if its current ancestry changed.
                    catalog_projection.push(canonical);
                }
            }
            if purpose == ArchivePurpose::Delete {
                for member in &operation.members {
                    if catalog_projection
                        .iter()
                        .any(|thread| thread.agent.thread_id == member.thread_id)
                    {
                        continue;
                    }
                    // The canonical row is truly absent. Keep the frozen paths, but still
                    // reject conflicting original preparation or execution-binding records.
                    if let Some(record) = self
                        .store
                        .thread_preparation_for_deletion(&member.thread_id)
                        .await?
                    {
                        ensure!(
                            record.identity.workspace_id == member.workspace_id
                                && record.identity.parent_id == member.parent_id
                                && record.identity.root_id == member.root_id,
                            "archive canonical member changed identity"
                        );
                        if let PreparationBinding::Bound { identity } = &record.binding {
                            ensure!(
                                *identity == member.execution,
                                "archive canonical member rebound during preparation"
                            );
                        }
                    }
                    if let Some(current) = self.store.workspace_identity(&member.thread_id).await? {
                        ensure!(
                            current == member.execution,
                            "archive original physical binding changed"
                        );
                    }
                }
            }
        }
        Ok(catalog_projection)
    }

    async fn discover_archive_preparations(
        &self,
        scope: &ArchiveScope,
        purpose: ArchivePurpose,
        threads: &[DirectoryMember],
        admitted: &[PreparationIdentity],
        previous: &Option<ThreadArchiveOperation>,
        deletion: &Option<ThreadDeleteOperation>,
    ) -> Result<Vec<PreparationIdentity>> {
        // These original responsibilities outlive both the registry owner and a failed first
        // threadArchive write. Discover by trusted identity, never by scanning physical paths.
        let mut admitted = admitted.to_vec();
        let preparations = if purpose == ArchivePurpose::Delete {
            list_deletion_aux(self.store.database()).await?
        } else {
            self.store.thread_preparations().await?
        };
        for record in preparations {
            let in_scope = match scope {
                ArchiveScope::Thread(root) => record.identity.root_id == *root,
                ArchiveScope::Workspace(workspace) => record.identity.workspace_id == *workspace,
            };
            if in_scope
                && (purpose == ArchivePurpose::Delete || !record.published)
                && (purpose == ArchivePurpose::Delete
                    || !(record.disposition == PreparationDisposition::Remove && record.retired))
                && !admitted
                    .iter()
                    .any(|identity| identity.thread_id == record.identity.thread_id)
            {
                admitted.push(record.identity);
            }
        }
        if let Some(deletion) = deletion {
            ensure!(
                threads
                    .iter()
                    .all(|thread| deletion.thread_ids.contains(&thread.agent.thread_id))
                    && admitted
                        .iter()
                        .all(|identity| deletion.thread_ids.contains(&identity.thread_id))
                    && previous.as_ref().is_none_or(|operation| operation
                        .thread_ids()
                        .iter()
                        .all(|id| deletion.thread_ids.contains(id))),
                "delete scope gained an unfrozen member"
            );
        }
        Ok(admitted)
    }

    fn reject_overlapping_archives(
        &self,
        purpose: ArchivePurpose,
        scope: &ArchiveScope,
        previous: &Option<ThreadArchiveOperation>,
        threads: &[DirectoryMember],
        admitted: &[PreparationIdentity],
        archives: Vec<ThreadArchiveOperation>,
    ) -> Result<()> {
        if let Some(operation) = previous
            && operation.phase != ArchivePhase::Published
        {
            let required_catalog = operation
                .members
                .iter()
                .map(|member| &member.thread_id)
                .collect::<std::collections::BTreeSet<_>>();
            // Preservation owes public catalog presence. Deletion keeps frozen identities and
            // bindings even after their canonical rows disappear; it never reconstructs them.
            // After save, the catalog and admitted preparation projections cannot grow this union.
            let frozen = required_catalog
                .iter()
                .copied()
                .chain(
                    operation
                        .private_members
                        .iter()
                        .map(|member| &member.identity.thread_id),
                )
                .collect::<std::collections::BTreeSet<_>>();
            let actual = threads
                .iter()
                .map(|thread| &thread.agent.thread_id)
                .collect::<std::collections::BTreeSet<_>>();
            ensure!(
                purpose == ArchivePurpose::Delete || required_catalog.is_subset(&actual),
                "archive scope changed while cleanup was pending"
            );
            ensure!(
                (actual.is_subset(&frozen)
                    && admitted
                        .iter()
                        .all(|identity| frozen.contains(&identity.thread_id)))
                    || operation.phase == ArchivePhase::Sealed,
                "archive gained a member after durable save confirmation"
            );
        }
        for pending in archives {
            if pending.phase != ArchivePhase::Published && pending.scope != *scope {
                if purpose == ArchivePurpose::Delete
                    && matches!(pending.scope, ArchiveScope::Workspace(_))
                {
                    continue; // Responsibility moves atomically with the deletion seal below.
                }
                ensure!(
                    !pending.thread_ids().iter().any(|id| threads
                        .iter()
                        .any(|thread| thread.agent.thread_id == *id)
                        || admitted.iter().any(|member| member.thread_id == *id)),
                    "overlapping archive operation must be retried first"
                );
            }
        }
        Ok(())
    }

    async fn freeze_public_archive_members(
        &self,
        purpose: ArchivePurpose,
        deletion: &Option<ThreadDeleteOperation>,
        threads: &[DirectoryMember],
        admitted: &[PreparationIdentity],
        previous: &Option<ThreadArchiveOperation>,
    ) -> Result<Vec<ArchiveMember>> {
        let mut members = previous
            .as_ref()
            .filter(|operation| operation.phase != ArchivePhase::Published)
            .map(|operation| operation.members.clone())
            .unwrap_or_default();
        for identity in admitted {
            if purpose == ArchivePurpose::Delete {
                // A durable deletion already owns every admitted identity. Recreating a lost
                // preparation would discard its frozen binding and invent a new obligation.
                if deletion.is_none() {
                    self.store
                        .begin_deletion_preparation(
                            identity.clone(),
                            threads
                                .iter()
                                .any(|thread| thread.agent.thread_id == identity.thread_id),
                        )
                        .await?;
                }
            } else {
                self.store
                    .begin_thread_preparation(identity.clone())
                    .await?;
            }
        }
        for thread in threads {
            let preparation = if purpose == ArchivePurpose::Delete {
                load_deletion_aux::<crate::studio::store::thread_preparation::ThreadPreparationRecord>(
                    self.store.database(), &thread.agent.thread_id,
                ).await?
            } else {
                self.store
                    .thread_preparation(&thread.agent.thread_id)
                    .await?
            };
            let public = members
                .iter()
                .find(|member| member.thread_id == thread.agent.thread_id);
            let private = previous
                .as_ref()
                .filter(|operation| operation.phase != ArchivePhase::Published)
                .and_then(|operation| {
                    operation
                        .private_members
                        .iter()
                        .find(|member| member.identity.thread_id == thread.agent.thread_id)
                });
            if let Some(member) = public {
                ensure!(
                    member.workspace_id == thread.session.workspace_id
                        && member.parent_id == thread.parent_thread_id
                        && member.root_id == thread.root_thread_id
                        && member.association_only == !thread.is_native(),
                    "archive canonical member changed identity"
                );
                if let Some(PreparationBinding::Bound { identity }) =
                    preparation.as_ref().map(|record| &record.binding)
                {
                    ensure!(
                        *identity == member.execution,
                        "archive canonical member rebound during preparation"
                    );
                }
            }
            if let Some(member) = private {
                ensure!(
                    member.identity.workspace_id == thread.session.workspace_id
                        && member.identity.parent_id == thread.parent_thread_id
                        && member.identity.root_id == thread.root_thread_id,
                    "archive private catalog projection changed identity"
                );
            }
            let frozen_execution = public.map(|member| &member.execution).or_else(|| {
                private.and_then(|member| match &member.binding {
                    PreparationBinding::Bound { identity } => Some(identity),
                    PreparationBinding::Unbound => None,
                })
            });
            if let Some(original) = frozen_execution
                && let Some(current) = self
                    .store
                    .workspace_identity(&thread.agent.thread_id)
                    .await?
            {
                ensure!(
                    *original == current,
                    "archive original physical binding changed"
                );
            }
            if preparation.as_ref().is_some_and(|record| !record.published) {
                members.retain(|member| member.thread_id != thread.agent.thread_id);
                continue;
            }
            if public.is_some() {
                continue;
            }
            let execution = match self
                .store
                .workspace_identity(&thread.agent.thread_id)
                .await?
            {
                Some(identity) => identity,
                None => {
                    let project = self
                        .store
                        .workspaces()
                        .get(&thread.session.workspace_id)
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
                            .resolve_workspace_identity(
                                &project,
                                Path::new(&thread.session.workspace_path),
                            )
                            .await?
                    } else {
                        WorkspaceIdentity::canonical(
                            WorkspaceEndpoint::Local,
                            thread.session.workspace_path.clone(),
                        )?
                    }
                }
            };
            let session = self
                .store
                .session_paths(&thread.session.workspace_id, &thread.agent.thread_id)?;
            members.push(ArchiveMember {
                association_only: !thread.is_native(),
                thread_id: thread.agent.thread_id.clone(),
                workspace_id: thread.session.workspace_id.clone(),
                parent_id: thread.parent_thread_id.clone(),
                root_id: thread.root_thread_id.clone(),
                host_session: session.root().to_owned(),
                host_temp: session.temp_dir(),
                execution,
                host_cleaned: false,
                execution_cleaned: false,
            });
        }
        Ok(members)
    }

    async fn freeze_private_archive_members(
        &self,
        purpose: ArchivePurpose,
        previous: &Option<ThreadArchiveOperation>,
        admitted: &[PreparationIdentity],
        members: &[ArchiveMember],
    ) -> Result<Vec<PrivateArchiveMember>> {
        let mut private_members = previous
            .as_ref()
            .filter(|operation| operation.phase != ArchivePhase::Published)
            .map(|operation| operation.private_members.clone())
            .unwrap_or_default();
        let mut private_identities = private_members
            .iter()
            .map(|member| member.identity.clone())
            .collect::<Vec<_>>();
        for identity in admitted {
            if !members
                .iter()
                .any(|member| member.thread_id == identity.thread_id)
                && !private_identities
                    .iter()
                    .any(|previous| previous.thread_id == identity.thread_id)
            {
                // A live captured admission cannot start physical preparation before this same
                // typed original-owner record commits. This is not absence-based recovery.
                if purpose == ArchivePurpose::Delete {
                    self.store
                        .begin_deletion_preparation(identity.clone(), false)
                        .await?;
                } else {
                    self.store
                        .begin_thread_preparation(identity.clone())
                        .await?;
                }
                private_identities.push(identity.clone());
            }
        }
        for identity in private_identities {
            let record = if purpose == ArchivePurpose::Delete {
                load_deletion_aux(self.store.database(), &identity.thread_id).await?
            } else {
                self.store.thread_preparation(&identity.thread_id).await?
            };
            let Some(mut record) = record else {
                if purpose == ArchivePurpose::Delete {
                    // Keep any previously frozen private binding. Absence or corruption grants
                    // no authority to reconstruct an execution path or overwrite the bad row.
                    tracing::info!(stage = "freeze_private", member = %identity.thread_id,
                        reason = "preparation_unavailable", decision = "retain_frozen_binding",
                        outcome = "skipped", "删除沿用原冻结责任");
                    continue;
                }
                anyhow::bail!("archive lost its original private preparation responsibility");
            };
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
            if purpose == ArchivePurpose::Preserve
                && record.disposition == PreparationDisposition::Remove
                && record.retired
            {
                private_members.retain(|member| member.identity.thread_id != identity.thread_id);
                continue;
            }
            if (purpose == ArchivePurpose::Preserve || !record.retired)
                && matches!(
                    record.disposition,
                    PreparationDisposition::Pending | PreparationDisposition::Remove
                )
            {
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
        Ok(private_members)
    }

    async fn assemble_frozen_archive(
        &self,
        scope: ArchiveScope,
        previous: Option<ThreadArchiveOperation>,
        missing_delete_progress: bool,
        members: Vec<ArchiveMember>,
        private_members: Vec<PrivateArchiveMember>,
    ) -> Result<ThreadArchiveOperation> {
        let mut phase = previous
            .as_ref()
            .filter(|operation| operation.phase != ArchivePhase::Published)
            .map_or(ArchivePhase::Sealed, |operation| operation.phase);
        let revision = previous.as_ref().map_or(Ok(1), |previous| {
            previous
                .revision
                .checked_add(1)
                .context("archive revision exhausted")
        })?;
        let mut worktrees = previous
            .filter(|operation| operation.phase != ArchivePhase::Published)
            .map(|operation| operation.worktrees)
            .unwrap_or_default();
        let ids = members
            .iter()
            .map(|member| member.thread_id.as_str())
            .chain(
                private_members
                    .iter()
                    .map(|member| member.identity.thread_id.as_str()),
            );
        for id in ids {
            if worktrees
                .iter()
                .any(|entry| entry.lease.owner_thread_id == id)
            {
                continue;
            }
            if let Some(lease) = self.agent_facility.worktrees.get(id) {
                let identity = crate::studio::agent_host::workspace_preparation::cleanup_identity(
                    &self.store,
                    &lease,
                )
                .await?;
                let original = members
                    .iter()
                    .find(|member| member.thread_id == id)
                    .map(|member| &member.execution)
                    .or_else(|| {
                        private_members
                            .iter()
                            .find(|member| member.identity.thread_id == id)
                            .and_then(|member| match &member.binding {
                                PreparationBinding::Bound { identity } => Some(identity),
                                PreparationBinding::Unbound => None,
                            })
                    });
                ensure!(
                    original == Some(&identity),
                    "archive worktree differs from its original member binding"
                );
                worktrees.push(crate::studio::store::thread_archive::ArchiveWorktree {
                    lease,
                    identity,
                    common_dir: None,
                    removal_started: false,
                    cleaned: false,
                });
            }
        }
        ensure!(
            !missing_delete_progress || worktrees.is_empty(),
            "deletion worktree progress has no readable original owner"
        );
        // Before worktree cleanup was part of this operation, Cleaned acknowledged temp only.
        // Keep its original save ACK while completing the newly recorded lease responsibility.
        if phase == ArchivePhase::Cleaned && worktrees.iter().any(|worktree| !worktree.cleaned) {
            phase = ArchivePhase::Saved;
        }
        let operation = ThreadArchiveOperation {
            scope,
            revision,
            members,
            private_members,
            worktrees,
            phase,
        };
        Ok(operation)
    }
}

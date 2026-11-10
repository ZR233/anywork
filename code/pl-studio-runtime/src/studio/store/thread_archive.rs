//! Durable responsibility for disposable files; canonical archive facts remain in the catalog.
use std::path::PathBuf;

use anyhow::{Context, Result, ensure};
use sea_orm::{ColumnTrait, EntityTrait, QueryFilter};
use serde::{Deserialize, Serialize};

use super::thread_preparation::{PreparationBinding, PreparationIdentity, PreparationSave};
use super::{
    StudioStore,
    object::{PersistedStudioObject, decode_object, load_object, put_object},
};
use crate::studio::agent_host::worktree_lease::WorkspaceIdentity;
use crate::studio::agent_host::worktree_lease::WorktreeLease;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio) struct ArchiveWorktree {
    pub lease: WorktreeLease,
    pub identity: WorkspaceIdentity,
    pub common_dir: Option<String>,
    pub removal_started: bool,
    pub cleaned: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "id",
    rename_all = "camelCase",
    deny_unknown_fields
)]
pub(in crate::studio) enum ArchiveScope {
    Thread(String),
    Workspace(String),
}

impl ArchiveScope {
    pub(in crate::studio) fn key(&self) -> String {
        match self {
            Self::Thread(id) => format!("thread:{id}"),
            Self::Workspace(id) => format!("workspace:{id}"),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio) struct ArchiveMember {
    /// Older journals contain only Native members. ACP owns no local transcript files.
    #[serde(default)]
    pub association_only: bool,
    pub thread_id: String,
    pub workspace_id: String,
    pub parent_id: Option<String>,
    pub root_id: String,
    pub host_session: PathBuf,
    pub host_temp: PathBuf,
    pub execution: WorkspaceIdentity,
    pub host_cleaned: bool,
    pub execution_cleaned: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio) struct PrivateArchiveMember {
    pub identity: PreparationIdentity,
    pub host_session: PathBuf,
    pub host_temp: PathBuf,
    pub binding: PreparationBinding,
    pub stopped: bool,
    pub save: PreparationSave,
    pub retired: bool,
    pub host_cleaned: bool,
    pub execution_cleaned: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::studio) enum ArchivePhase {
    Sealed,
    Saved,
    Cleaned,
    Published,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio) struct ThreadArchiveOperation {
    pub scope: ArchiveScope,
    pub revision: u64,
    pub members: Vec<ArchiveMember>,
    pub private_members: Vec<PrivateArchiveMember>,
    #[serde(default)]
    pub worktrees: Vec<ArchiveWorktree>,
    pub phase: ArchivePhase,
}

impl ThreadArchiveOperation {
    pub(in crate::studio) fn thread_ids(&self) -> Vec<String> {
        self.members
            .iter()
            .map(|member| member.thread_id.clone())
            .chain(
                self.private_members
                    .iter()
                    .map(|member| member.identity.thread_id.clone()),
            )
            .collect()
    }
    pub(in crate::studio) fn changed(&mut self) -> Result<()> {
        self.revision = self
            .revision
            .checked_add(1)
            .context("archive revision exhausted")?;
        Ok(())
    }
}

impl PersistedStudioObject for ThreadArchiveOperation {
    type PersistenceDto = Self;
    const OWNER_KIND: &'static str = "archive";
    const OBJECT_KIND: &'static str = "threadArchive";
    const SCHEMA_VERSION: i64 = 2;

    fn revision(&self) -> u64 {
        self.revision
    }
    fn to_persistence_dto(&self) -> Self {
        self.clone()
    }
    fn from_persistence_dto(dto: Self) -> Result<Self> {
        Ok(dto)
    }
    fn validate_owner(&self, owner_id: &str) -> Result<()> {
        ensure!(
            self.scope.key() == owner_id,
            "archive scope identity mismatch"
        );
        let mut ids = std::collections::HashSet::new();
        for member in &self.members {
            ensure!(ids.insert(&member.thread_id), "duplicate archive member");
            ensure!(
                member.host_session.is_absolute()
                    && member.host_temp == member.host_session.join("temp"),
                "archive host temp is not a dedicated session directory"
            );
            WorkspaceIdentity::canonical(
                member.execution.endpoint.clone(),
                member.execution.root.clone(),
            )?;
        }
        for member in &self.private_members {
            ensure!(
                ids.insert(&member.identity.thread_id),
                "duplicate private archive member"
            );
            ensure!(
                !member.identity.workspace_id.is_empty() && !member.identity.root_id.is_empty(),
                "private archive identity is incomplete"
            );
            ensure!(
                member.host_session.is_absolute()
                    && member.host_temp == member.host_session.join("temp"),
                "private archive temp is not a dedicated session directory"
            );
            if let PreparationBinding::Bound { identity } = &member.binding {
                WorkspaceIdentity::canonical(identity.endpoint.clone(), identity.root.clone())?;
            }
            if self.phase != ArchivePhase::Sealed {
                ensure!(
                    member.stopped && member.retired && member.save != PreparationSave::Required,
                    "private preparation has no stop/save/resource ACK"
                );
            }
        }
        let mut worktree_owners = std::collections::HashSet::new();
        for worktree in &self.worktrees {
            ensure!(
                ids.contains(&worktree.lease.owner_thread_id)
                    && worktree_owners.insert(&worktree.lease.owner_thread_id),
                "archive worktree has no unique member owner"
            );
            worktree.lease.validate_identity()?;
            ensure!(
                worktree.identity.matches_root(&worktree.lease.path),
                "archive worktree physical binding differs from lease"
            );
            let original = self
                .members
                .iter()
                .find(|member| member.thread_id == worktree.lease.owner_thread_id)
                .map(|member| &member.execution)
                .or_else(|| {
                    self.private_members
                        .iter()
                        .find(|member| member.identity.thread_id == worktree.lease.owner_thread_id)
                        .and_then(|member| match &member.binding {
                            PreparationBinding::Bound { identity } => Some(identity),
                            PreparationBinding::Unbound => None,
                        })
                });
            ensure!(
                original == Some(&worktree.identity),
                "archive worktree is not the member's original physical binding"
            );
        }
        if matches!(self.phase, ArchivePhase::Cleaned | ArchivePhase::Published) {
            ensure!(
                self.worktrees.iter().all(|worktree| worktree.cleaned),
                "archive worktree cleanup is unfinished"
            );
            ensure!(
                self.members.iter().all(|member| member.association_only
                    || (member.host_cleaned && member.execution_cleaned)),
                "archive phase precedes cleanup"
            );
            ensure!(
                self.private_members
                    .iter()
                    .all(|member| member.host_cleaned && member.execution_cleaned),
                "private archive cleanup is unfinished"
            );
        }
        Ok(())
    }
}

impl StudioStore {
    pub(in crate::studio) async fn thread_archive(
        &self,
        scope: &ArchiveScope,
    ) -> Result<Option<ThreadArchiveOperation>> {
        load_object(self.database(), &scope.key()).await
    }

    pub(in crate::studio) async fn save_thread_archive(
        &self,
        operation: &ThreadArchiveOperation,
    ) -> Result<()> {
        operation.validate_owner(&operation.scope.key())?;
        put_object(
            self.database(),
            &operation.scope.key(),
            operation,
            crate::studio::unix_seconds(),
        )
        .await
    }

    pub(in crate::studio) async fn thread_archives(&self) -> Result<Vec<ThreadArchiveOperation>> {
        use crate::studio::entity::studio_object;
        studio_object::Entity::find()
            .filter(studio_object::Column::OwnerKind.eq(ThreadArchiveOperation::OWNER_KIND))
            .filter(studio_object::Column::ObjectKind.eq(ThreadArchiveOperation::OBJECT_KIND))
            .all(self.database())
            .await?
            .into_iter()
            .map(decode_object::<ThreadArchiveOperation>)
            .collect()
    }

    pub(crate) async fn ensure_archive_execution_allowed(
        &self,
        workspace_id: &str,
        thread_id: Option<&str>,
    ) -> Result<()> {
        self.ensure_delete_execution_allowed(thread_id).await?;
        let root_thread = thread_id
            .map(|id| self.directory_member(id))
            .transpose()?
            .flatten()
            .map(|member| member.root_thread_id);
        for operation in self.thread_archives().await? {
            if operation.phase == ArchivePhase::Published {
                continue;
            }
            let workspace =
                matches!(&operation.scope, ArchiveScope::Workspace(id) if id == workspace_id);
            let member = thread_id.is_some_and(|id| {
                operation
                    .members
                    .iter()
                    .any(|member| member.thread_id == id)
                    || operation
                        .private_members
                        .iter()
                        .any(|member| member.identity.thread_id == id)
                    || matches!(&operation.scope, ArchiveScope::Thread(root)
                        if root_thread.as_ref() == Some(root))
            });
            ensure!(
                !workspace && !member,
                "Thread archive cleanup must be retried before execution"
            );
        }
        // A preserve owner can exit after sealing but before the first threadArchive commit.
        // Its own durable responsibility must keep this original tree closed to execution.
        for preparation in self.thread_preparations().await? {
            if !preparation.published
                && preparation.disposition
                    == super::thread_preparation::PreparationDisposition::ArchivePreserve
                && preparation.identity.workspace_id == workspace_id
                && thread_id.is_some_and(|id| {
                    id == preparation.identity.thread_id
                        || id == preparation.identity.root_id
                        || root_thread.as_deref() == Some(preparation.identity.root_id.as_str())
                })
            {
                anyhow::bail!("Thread archive cleanup must be retried before execution");
            }
        }
        Ok(())
    }
}

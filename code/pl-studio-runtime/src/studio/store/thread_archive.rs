//! Durable responsibility for disposable files; canonical archive facts remain in the catalog.
use std::path::PathBuf;

use anyhow::{Context, Result, ensure};
use sea_orm::{ColumnTrait, EntityTrait, QueryFilter};
use serde::{Deserialize, Serialize};

use super::{
    StudioStore,
    object::{PersistedStudioObject, decode_object, load_object, put_object},
};
use crate::studio::agent_host::worktree_lease::WorkspaceIdentity;

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
    pub thread_id: String,
    pub workspace_id: String,
    pub host_session: PathBuf,
    pub host_temp: PathBuf,
    pub execution: WorkspaceIdentity,
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
    pub phase: ArchivePhase,
}

impl ThreadArchiveOperation {
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
    const SCHEMA_VERSION: i64 = 1;

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
        if matches!(self.phase, ArchivePhase::Cleaned | ArchivePhase::Published) {
            ensure!(
                self.members
                    .iter()
                    .all(|member| member.host_cleaned && member.execution_cleaned),
                "archive phase precedes cleanup"
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

    pub(in crate::studio) async fn ensure_archive_execution_allowed(
        &self,
        workspace_id: &str,
        thread_id: Option<&str>,
    ) -> Result<()> {
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
            });
            ensure!(
                !workspace && !member,
                "Thread archive cleanup must be retried before execution"
            );
        }
        Ok(())
    }
}

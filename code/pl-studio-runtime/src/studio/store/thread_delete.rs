//! A permanent deletion owns its frozen scope until the canonical directory commit.
use anyhow::{Context, Result, ensure};
use sea_orm::{ColumnTrait, EntityTrait, QueryFilter};
use serde::{Deserialize, Serialize};

use super::{
    StudioStore,
    object::{PersistedStudioObject, decode_object, load_object, put_object},
    thread_preparation::{PreparationBinding, PreparationIdentity},
};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio) struct DeleteMember {
    pub identity: PreparationIdentity,
    pub host_session: std::path::PathBuf,
    pub execution: PreparationBinding,
    pub execution_deleted: bool,
    pub host_deleted: bool,
    // A record written before these fences existed cannot prove non-execution. Sealed records
    // can establish Unstarted before Removing commits; already-Removing records stay unknown.
    #[serde(default = "unresolved_removal")]
    pub execution_removal_started: bool,
    #[serde(default = "unresolved_removal")]
    pub host_removal_started: bool,
}

fn unresolved_removal() -> bool {
    true
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::studio) enum DeletePhase {
    Sealed,
    Removing,
    DataDeleted,
    Published,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio) struct ThreadDeleteOperation {
    pub root_id: String,
    pub thread_ids: Vec<String>,
    pub revision: u64,
    pub phase: DeletePhase,
    pub members: Vec<DeleteMember>,
}

impl ThreadDeleteOperation {
    pub fn changed(&mut self) -> Result<()> {
        self.revision = self
            .revision
            .checked_add(1)
            .context("delete revision exhausted")?;
        Ok(())
    }
}

impl PersistedStudioObject for ThreadDeleteOperation {
    type PersistenceDto = Self;
    const OWNER_KIND: &'static str = "deletion";
    const OBJECT_KIND: &'static str = "threadDelete";
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
            self.root_id == owner_id && self.thread_ids.contains(&self.root_id),
            "delete root identity mismatch"
        );
        let ids = self
            .thread_ids
            .iter()
            .collect::<std::collections::BTreeSet<_>>();
        ensure!(
            ids.len() == self.thread_ids.len(),
            "duplicate delete member"
        );
        for member in &self.members {
            ensure!(
                ids.contains(&member.identity.thread_id)
                    && member.identity.root_id == self.root_id
                    && member.host_session.is_absolute(),
                "delete binding identity mismatch"
            );
        }
        ensure!(
            self.phase != DeletePhase::Published || self.members.is_empty(),
            "completed deletion may retain identities only"
        );
        Ok(())
    }
}

impl StudioStore {
    pub(in crate::studio) async fn delete_thread_product_data(
        &self,
        operation: &ThreadDeleteOperation,
    ) -> Result<()> {
        use super::thread_archive::{ArchivePhase, ArchiveScope};
        use sea_orm::{ConnectionTrait, DatabaseBackend, Statement, TransactionTrait};
        // An archived project can retain responsibilities for other roots. Remove only this
        // tree's members, preserving that scope and its unrelated cleanup progress.
        for mut archive in self.thread_archives().await? {
            if archive.scope == ArchiveScope::Thread(operation.root_id.clone()) {
                continue;
            }
            let before = archive.thread_ids().len();
            archive
                .members
                .retain(|member| !operation.thread_ids.contains(&member.thread_id));
            archive
                .private_members
                .retain(|member| !operation.thread_ids.contains(&member.identity.thread_id));
            archive
                .worktrees
                .retain(|member| !operation.thread_ids.contains(&member.lease.owner_thread_id));
            if archive.thread_ids().len() != before {
                ensure!(
                    archive.phase == ArchivePhase::Published,
                    "another unfinished archive owns part of the deleted tree"
                );
                archive.changed()?;
                self.save_thread_archive(&archive).await?;
            }
        }
        let tx = self.database().begin().await?;
        for id in &operation.thread_ids {
            tx.execute_raw(Statement::from_sql_and_values(
                DatabaseBackend::Sqlite,
                "DELETE FROM studio_objects WHERE owner_id=? AND owner_kind IN ('thread','agent')",
                [id.clone().into()],
            ))
            .await?;
            tx.execute_raw(Statement::from_sql_and_values(
                DatabaseBackend::Sqlite,
                "DELETE FROM agent_evaluations WHERE agent_id=? OR parent_agent_id=?",
                [id.clone().into(), id.clone().into()],
            ))
            .await?;
        }
        tx.execute_raw(Statement::from_sql_and_values(DatabaseBackend::Sqlite,
            "DELETE FROM studio_objects WHERE owner_kind='archive' AND owner_id=? AND object_kind='threadArchive'",
            [ArchiveScope::Thread(operation.root_id.clone()).key().into()])).await?;
        tx.commit().await?;
        Ok(())
    }
    pub(in crate::studio) async fn thread_delete(
        &self,
        root: &str,
    ) -> Result<Option<ThreadDeleteOperation>> {
        load_object(self.database(), root).await
    }
    pub(in crate::studio) async fn thread_deletes(&self) -> Result<Vec<ThreadDeleteOperation>> {
        Self::thread_deletes_on(self.database()).await
    }
    pub(in crate::studio) async fn thread_deletes_on(
        db: &impl sea_orm::ConnectionTrait,
    ) -> Result<Vec<ThreadDeleteOperation>> {
        use crate::studio::entity::studio_object;
        studio_object::Entity::find()
            .filter(studio_object::Column::OwnerKind.eq(ThreadDeleteOperation::OWNER_KIND))
            .filter(studio_object::Column::ObjectKind.eq(ThreadDeleteOperation::OBJECT_KIND))
            .all(db)
            .await?
            .into_iter()
            .map(decode_object::<ThreadDeleteOperation>)
            .collect()
    }
    pub(in crate::studio) async fn save_thread_delete(
        &self,
        operation: &ThreadDeleteOperation,
    ) -> Result<()> {
        operation.validate_owner(&operation.root_id)?;
        put_object(
            self.database(),
            &operation.root_id,
            operation,
            crate::studio::unix_seconds(),
        )
        .await
    }
    pub(in crate::studio) async fn ensure_delete_execution_allowed(
        &self,
        thread_id: Option<&str>,
    ) -> Result<()> {
        if let Some(id) = thread_id {
            ensure!(
                !self
                    .thread_deletes()
                    .await?
                    .iter()
                    .any(
                        |operation| operation.thread_ids.iter().any(|member| member == id)
                            || self
                                .catalog()
                                .get(id)
                                .is_some_and(|record| record.root_thread_id == operation.root_id)
                    ),
                "Thread permanent deletion has sealed execution"
            );
        }
        Ok(())
    }
    pub(in crate::studio) async fn ensure_delete_read_allowed(
        &self,
        thread_id: &str,
    ) -> Result<()> {
        ensure!(
            !self
                .thread_deletes()
                .await?
                .iter()
                .any(|operation| operation.phase != DeletePhase::Sealed
                    && operation.thread_ids.iter().any(|id| id == thread_id)),
            "Thread permanent deletion has revoked storage access"
        );
        Ok(())
    }
}

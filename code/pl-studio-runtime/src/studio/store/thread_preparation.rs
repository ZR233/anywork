//! Original private assembly ownership, before catalog publication. Not a second directory.
use super::{
    StudioStore,
    object::{PersistedStudioObject, load_object, put_object},
};
use crate::studio::agent_host::worktree_lease::WorkspaceIdentity;
use anyhow::{Context, Result, ensure};
use sea_orm::TransactionTrait;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct PreparationIdentity {
    pub thread_id: String,
    pub workspace_id: String,
    pub parent_id: Option<String>,
    pub root_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
pub(crate) enum PreparationBinding {
    /// The owner has not acquired authority for physical side effects.
    Unbound,
    Bound {
        identity: WorkspaceIdentity,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) enum PreparationSave {
    Unattached,
    Required,
    Confirmed,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct ThreadPreparationRecord {
    pub identity: PreparationIdentity,
    pub revision: u64,
    pub binding: PreparationBinding,
    pub save: PreparationSave,
    pub stopped: bool,
    pub retired: bool,
    pub published: bool,
}

impl PersistedStudioObject for ThreadPreparationRecord {
    type PersistenceDto = Self;
    const OWNER_KIND: &'static str = "thread";
    const OBJECT_KIND: &'static str = "threadPreparation";
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
    fn validate_owner(&self, owner: &str) -> Result<()> {
        ensure!(
            self.identity.thread_id == owner
                && !self.identity.workspace_id.is_empty()
                && !self.identity.root_id.is_empty(),
            "preparation identity mismatch"
        );
        ensure!(
            self.identity.parent_id.as_deref() != Some(owner),
            "cyclic preparation identity"
        );
        if let PreparationBinding::Bound { identity } = &self.binding {
            WorkspaceIdentity::canonical(identity.endpoint.clone(), identity.root.clone())?;
        }
        ensure!(
            !self.retired || self.stopped,
            "preparation retirement precedes producer ACK"
        );
        ensure!(
            !self.stopped || self.save != PreparationSave::Required,
            "preparation stop precedes save ACK"
        );
        Ok(())
    }
}

impl StudioStore {
    pub(crate) async fn thread_preparation(
        &self,
        id: &str,
    ) -> Result<Option<ThreadPreparationRecord>> {
        load_object(self.database(), id).await
    }

    pub(crate) async fn begin_thread_preparation(
        &self,
        identity: PreparationIdentity,
    ) -> Result<()> {
        // Existing root restoration already has reliable history. Never relabel it as a
        // never-attached private creation merely because this activation has not attached yet.
        let published_root = identity.parent_id.is_none()
            && self
                .history_for(&identity.workspace_id, &identity.thread_id)
                .await?
                .checkpoint()
                .await?
                .is_some();
        let transaction = self.database().begin().await?;
        if let Some(previous) =
            load_object::<ThreadPreparationRecord>(&transaction, &identity.thread_id).await?
        {
            ensure!(
                previous.identity == identity,
                "preparation original owner changed"
            );
        } else {
            let value = ThreadPreparationRecord {
                identity,
                revision: 1,
                binding: PreparationBinding::Unbound,
                save: PreparationSave::Unattached,
                stopped: false,
                retired: false,
                published: published_root,
            };
            value.validate_owner(&value.identity.thread_id)?;
            put_object(
                &transaction,
                &value.identity.thread_id,
                &value,
                crate::studio::unix_seconds(),
            )
            .await?;
        }
        transaction.commit().await?;
        Ok(())
    }

    async fn change_preparation(
        &self,
        id: &str,
        change: impl FnOnce(&mut ThreadPreparationRecord) -> Result<()>,
    ) -> Result<()> {
        let transaction = self.database().begin().await?;
        let mut value = load_object::<ThreadPreparationRecord>(&transaction, id)
            .await?
            .context("private preparation has no durable original owner")?;
        change(&mut value)?;
        value.revision = value
            .revision
            .checked_add(1)
            .context("preparation revision exhausted")?;
        value.validate_owner(id)?;
        put_object(&transaction, id, &value, crate::studio::unix_seconds()).await?;
        transaction.commit().await?;
        Ok(())
    }

    /// Must commit before the first workspace/session/worktree mutation at this binding.
    pub(crate) async fn bind_thread_preparation(
        &self,
        id: &str,
        identity: &WorkspaceIdentity,
    ) -> Result<()> {
        self.change_preparation(id, |value| {
            match &value.binding {
                PreparationBinding::Unbound => {
                    ensure!(
                        !value.stopped,
                        "stopped preparation cannot acquire a physical binding"
                    );
                    value.binding = PreparationBinding::Bound {
                        identity: identity.clone(),
                    };
                }
                PreparationBinding::Bound { identity: previous } => ensure!(
                    previous == identity,
                    "preparation frozen physical binding changed"
                ),
            }
            Ok(())
        })
        .await
    }

    pub(crate) async fn require_preparation_save(&self, id: &str) -> Result<()> {
        self.change_preparation(id, |value| {
            ensure!(
                !value.stopped,
                "stopped private preparation cannot attach execution storage"
            );
            value.save = PreparationSave::Required;
            Ok(())
        })
        .await
    }

    pub(crate) async fn confirm_preparation_save(&self, id: &str) -> Result<()> {
        self.change_preparation(id, |value| {
            if value.save == PreparationSave::Required {
                value.save = PreparationSave::Confirmed;
            }
            Ok(())
        })
        .await
    }

    pub(crate) async fn confirm_preparation_stop(&self, id: &str) -> Result<()> {
        self.change_preparation(id, |value| {
            ensure!(
                value.save != PreparationSave::Required,
                "private checkpoint is still unconfirmed"
            );
            value.stopped = true;
            Ok(())
        })
        .await
    }

    pub(crate) async fn confirm_preparation_retirement(&self, id: &str) -> Result<()> {
        self.change_preparation(id, |value| {
            ensure!(
                value.stopped,
                "private producers have not acknowledged stop"
            );
            value.retired = true;
            Ok(())
        })
        .await
    }

    pub(crate) async fn publish_preparation(&self, id: &str) -> Result<()> {
        self.change_preparation(id, |value| {
            value.published = true;
            Ok(())
        })
        .await
    }
}

//! Original private assembly ownership, before catalog publication. Not a second directory.
use super::{
    StudioStore,
    object::{PersistedStudioObject, checked_bump_revision, list_objects, load_object, put_object},
};
use crate::studio::worktree::worktree_lease::WorkspaceIdentity;
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

/// Physical disposal is independent of producer retirement and of the archive operation's first
/// successful write. Only Remove+retired or TempCleaned proves no disposable responsibility remains.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(crate) enum PreparationDisposition {
    Pending,
    Remove,
    ArchivePreserve,
    TempCleaned,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct PreparationStorage {
    pub incarnation: String,
    pub required_through: u64,
    /// Written only by that incarnation after Closed, its original flush and writer join.
    pub closed_receipt: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct ThreadPreparationRecord {
    pub identity: PreparationIdentity,
    pub revision: u64,
    pub binding: PreparationBinding,
    pub save: PreparationSave,
    pub storage: Option<PreparationStorage>,
    pub disposition: PreparationDisposition,
    pub stopped: bool,
    /// A real stop under the durable deletion scope, independent of any save receipt.
    #[serde(default, skip_serializing_if = "std::ops::Not::not")]
    pub deletion_stopped: bool,
    pub retired: bool,
    pub published: bool,
}

#[derive(Debug, thiserror::Error)]
pub(super) enum PreparationObjectError {
    #[error("preparation identity mismatch")]
    Identity,
    #[error("cyclic preparation identity")]
    Cycle,
    #[error("preparation retirement precedes producer ACK")]
    RetirementAck,
    #[error("preparation stop precedes save ACK")]
    SaveAck,
    #[error("deletion stop ACK is missing")]
    DeletionAck,
    #[error("attached obligation cannot be unattached")]
    Attachment,
    #[error("missing storage incarnation")]
    Incarnation,
    #[error("preparation save does not match its original closed receipt")]
    ClosedReceipt,
    #[error("private save has no original storage obligation")]
    Storage,
    #[error("temp cleanup precedes original resource retirement")]
    Cleanup,
}

impl PreparationObjectError {
    pub(super) fn reason(&self) -> &'static str {
        match self {
            Self::Identity => "preparation_identity",
            Self::Cycle => "preparation_cycle",
            Self::RetirementAck => "preparation_retirement_ack",
            Self::SaveAck => "preparation_save_ack",
            Self::DeletionAck => "preparation_deletion_ack",
            Self::Attachment => "preparation_attachment",
            Self::Incarnation => "preparation_incarnation",
            Self::ClosedReceipt => "preparation_closed_receipt",
            Self::Storage => "preparation_storage",
            Self::Cleanup => "preparation_cleanup",
        }
    }
}

impl PersistedStudioObject for ThreadPreparationRecord {
    type PersistenceDto = Self;
    const OWNER_KIND: &'static str = "thread";
    const OBJECT_KIND: &'static str = "threadPreparation";
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
    fn validate_owner(&self, owner: &str) -> Result<()> {
        ensure!(
            self.identity.thread_id == owner
                && !self.identity.workspace_id.is_empty()
                && !self.identity.root_id.is_empty(),
            PreparationObjectError::Identity
        );
        ensure!(
            self.identity.parent_id.as_deref() != Some(owner),
            PreparationObjectError::Cycle
        );
        if let PreparationBinding::Bound { identity } = &self.binding {
            WorkspaceIdentity::canonical(identity.endpoint.clone(), identity.root.clone())?;
        }
        ensure!(
            !self.retired || self.stopped,
            PreparationObjectError::RetirementAck
        );
        ensure!(
            !self.stopped || self.save != PreparationSave::Required || self.deletion_stopped,
            PreparationObjectError::SaveAck
        );
        ensure!(
            !self.deletion_stopped || self.stopped,
            PreparationObjectError::DeletionAck
        );
        match (&self.storage, self.save) {
            (None, PreparationSave::Unattached) => {}
            (Some(storage), save) => {
                ensure!(
                    save != PreparationSave::Unattached,
                    PreparationObjectError::Attachment
                );
                ensure!(
                    !storage.incarnation.is_empty(),
                    PreparationObjectError::Incarnation
                );
                ensure!(
                    (save == PreparationSave::Confirmed)
                        == storage
                            .closed_receipt
                            .is_some_and(|through| through >= storage.required_through),
                    PreparationObjectError::ClosedReceipt
                );
            }
            _ => anyhow::bail!(PreparationObjectError::Storage),
        }
        ensure!(
            self.disposition != PreparationDisposition::TempCleaned || self.retired,
            PreparationObjectError::Cleanup
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

    pub(crate) async fn thread_preparation_for_deletion(
        &self,
        id: &str,
    ) -> Result<Option<ThreadPreparationRecord>> {
        super::object::load_deletion_aux(self.database(), id).await
    }

    pub(in crate::studio) async fn begin_deletion_preparation(
        &self,
        identity: PreparationIdentity,
        published: bool,
    ) -> Result<()> {
        // An existing unreadable record is not an empty slot. Never replace its owner/binding.
        if super::object::load_object_row::<ThreadPreparationRecord>(
            self.database(),
            &identity.thread_id,
        )
        .await?
        .is_some()
        {
            if let Some(previous) = self
                .thread_preparation_for_deletion(&identity.thread_id)
                .await?
            {
                ensure!(
                    previous.identity == identity,
                    "preparation original owner changed"
                );
            }
            return Ok(());
        }
        self.record_thread_preparation(identity, published).await
    }

    pub(crate) async fn thread_preparations(&self) -> Result<Vec<ThreadPreparationRecord>> {
        list_objects(self.database()).await
    }

    pub(crate) async fn begin_thread_preparation(
        &self,
        identity: PreparationIdentity,
    ) -> Result<()> {
        if let Some(previous) = self.thread_preparation(&identity.thread_id).await? {
            ensure!(
                previous.identity == identity,
                "preparation original owner changed"
            );
            return Ok(());
        }
        // Existing root restoration already has reliable history. Never relabel it as a
        // never-attached private creation merely because this activation has not attached yet.
        let published_root = identity.parent_id.is_none()
            && self
                .state_for(&identity.workspace_id, &identity.thread_id)?
                .load_current()
                .await?
                .is_some();
        self.record_thread_preparation(identity, published_root)
            .await
    }

    /// Records preparation using the caller's known publication baseline, without loading Current.
    pub(in crate::studio) async fn record_thread_preparation(
        &self,
        identity: PreparationIdentity,
        published: bool,
    ) -> Result<()> {
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
                storage: None,
                disposition: PreparationDisposition::Pending,
                stopped: false,
                deletion_stopped: false,
                retired: false,
                published,
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
        checked_bump_revision(&mut value.revision, "preparation")?;
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

    pub(crate) async fn require_preparation_save(
        &self,
        id: &str,
        incarnation: &str,
        through: u64,
    ) -> Result<()> {
        self.change_preparation(id, |value| {
            ensure!(
                !value.stopped,
                "stopped private preparation cannot attach execution storage"
            );
            ensure!(
                value.storage.is_none(),
                "original storage obligation already exists"
            );
            value.save = PreparationSave::Required;
            value.storage = Some(PreparationStorage {
                incarnation: incarnation.into(),
                required_through: through,
                closed_receipt: None,
            });
            Ok(())
        })
        .await
    }

    pub(crate) async fn target_preparation_save(
        &self,
        id: &str,
        incarnation: &str,
        through: u64,
    ) -> Result<()> {
        self.change_preparation(id, |value| {
            let storage = value
                .storage
                .as_mut()
                .context("missing original storage obligation")?;
            ensure!(
                storage.incarnation == incarnation,
                "storage incarnation changed"
            );
            ensure!(
                through >= storage.required_through,
                "original save watermark regressed"
            );
            storage.required_through = through;
            Ok(())
        })
        .await
    }

    pub(crate) async fn confirm_preparation_save(
        &self,
        id: &str,
        incarnation: &str,
        through: u64,
    ) -> Result<()> {
        self.change_preparation(id, |value| {
            let storage = value
                .storage
                .as_mut()
                .context("missing original storage obligation")?;
            ensure!(
                storage.incarnation == incarnation,
                "storage incarnation changed"
            );
            ensure!(
                through >= storage.required_through,
                "original save watermark is unconfirmed"
            );
            storage.closed_receipt = Some(through);
            value.save = PreparationSave::Confirmed;
            Ok(())
        })
        .await
    }

    pub(crate) async fn set_preparation_disposition(
        &self,
        id: &str,
        disposition: PreparationDisposition,
    ) -> Result<()> {
        self.change_preparation(id, |value| {
            ensure!(
                value.disposition != PreparationDisposition::ArchivePreserve
                    || disposition == PreparationDisposition::ArchivePreserve,
                "archive preserve responsibility cannot become ordinary removal"
            );
            ensure!(
                !value.retired
                    || value.disposition == disposition
                    || value.disposition == PreparationDisposition::Pending,
                "completed original disposal cannot change policy"
            );
            ensure!(
                disposition != PreparationDisposition::TempCleaned,
                "cleanup requires both temp ACKs"
            );
            value.disposition = disposition;
            Ok(())
        })
        .await
    }

    pub(crate) async fn confirm_preparation_temp_cleanup(
        &self,
        identity: &PreparationIdentity,
        binding: &PreparationBinding,
    ) -> Result<()> {
        self.change_preparation(&identity.thread_id, |value| {
            ensure!(
                value.identity == *identity && value.binding == *binding,
                "temp cleanup owner changed"
            );
            ensure!(
                value.stopped && value.retired && value.save != PreparationSave::Required,
                "original stop/save/retirement ACK is pending"
            );
            ensure!(
                matches!(
                    value.disposition,
                    PreparationDisposition::ArchivePreserve | PreparationDisposition::TempCleaned
                ),
                "temp cleanup has no archive preserve responsibility"
            );
            value.disposition = PreparationDisposition::TempCleaned;
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

    pub(crate) async fn require_preparation_deletion(
        &self,
        record: &ThreadPreparationRecord,
    ) -> Result<()> {
        let deletion = self
            .thread_delete(&record.identity.root_id)
            .await?
            .context("private stop has no durable deletion scope")?;
        ensure!(
            deletion
                .members
                .iter()
                .any(|member| member.identity == record.identity
                    && (member.execution == record.binding
                        // An admitted preparation may acquire its first immutable binding after
                        // Sealed. The deletion owner freezes that original binding after its join.
                        || (member.execution == PreparationBinding::Unbound
                            && deletion.phase == super::thread_delete::DeletePhase::Sealed))),
            "private deletion binding is outside its durable scope"
        );
        Ok(())
    }

    pub(crate) async fn confirm_preparation_stop_for_deletion(&self, id: &str) -> Result<()> {
        let record = self
            .thread_preparation(id)
            .await?
            .context("private deletion owner missing")?;
        self.require_preparation_deletion(&record).await?;
        self.change_preparation(id, |value| {
            ensure!(
                value.identity == record.identity && value.binding == record.binding,
                "private deletion owner changed"
            );
            value.stopped = true;
            value.deletion_stopped = true;
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
            ensure!(
                !matches!(
                    value.disposition,
                    PreparationDisposition::ArchivePreserve | PreparationDisposition::TempCleaned
                ),
                "archive preserve responsibility cannot be discharged by publication"
            );
            value.published = true;
            Ok(())
        })
        .await
    }
}

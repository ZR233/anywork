//! Lease schemas 2/3 retire branch identity and rebuild grants without touching physical Git.
use anyhow::{Context, Result, ensure};
use pl_core::context::content_hash;
use sea_orm::{
    ActiveModelTrait, ActiveValue::Set, ColumnTrait, DatabaseConnection, EntityTrait,
    IntoActiveModel, QueryFilter, QueryOrder, TransactionTrait,
};
use serde::Deserialize;

use super::{WorktreeLease, WorktreeLeaseOwnerKind, WorktreeLeaseState};
use crate::studio::entity::studio_object;
use crate::studio::store::object::{PersistedStudioObject, decode_object};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct LegacyLease {
    revision: u64,
    state: WorktreeLeaseState,
    owner_kind: WorktreeLeaseOwnerKind,
    owner_thread_id: String,
    root_thread_id: String,
    project_id: String,
    ssh_alias: Option<String>,
    repository_root: String,
    path: String,
    branch: String,
    base_commit: String,
    #[serde(default)]
    restore_authorized_at: Option<i64>,
}

impl LegacyLease {
    fn upgrade(self) -> Result<WorktreeLease> {
        ensure!(
            !self.branch.trim().is_empty(),
            "legacy lease branch is empty"
        );
        let _retired_grant = self.restore_authorized_at;
        Ok(WorktreeLease {
            revision: self.revision,
            state: self.state,
            owner_kind: self.owner_kind,
            owner_thread_id: self.owner_thread_id,
            root_thread_id: self.root_thread_id,
            project_id: self.project_id,
            ssh_alias: self.ssh_alias,
            repository_root: self.repository_root,
            path: self.path,
            base_commit: self.base_commit,
        })
    }
}

pub(super) async fn load(db: &DatabaseConnection) -> Result<Vec<WorktreeLease>> {
    let tx = db.begin().await?;
    let rows = studio_object::Entity::find()
        .filter(studio_object::Column::OwnerKind.eq(WorktreeLease::OWNER_KIND))
        .filter(studio_object::Column::ObjectKind.eq(WorktreeLease::OBJECT_KIND))
        .order_by_asc(studio_object::Column::OwnerId)
        .all(&tx)
        .await?;
    let mut leases = Vec::with_capacity(rows.len());
    for mut row in rows {
        if matches!(row.schema_version, 2 | 3) {
            ensure!(
                content_hash(row.payload_json.as_bytes()) == row.payload_hash,
                "worktree lease {} hash mismatch before migration",
                row.owner_id
            );
            let payload: serde_json::Value = serde_json::from_str(&row.payload_json)
                .context("decode historical worktree lease")?;
            ensure!(
                row.schema_version == 2 || payload.get("restoreAuthorizedAt").is_none(),
                "worktree lease contains a retired schema 2 field"
            );
            let legacy: LegacyLease = serde_json::from_value(payload)
                .context("decode historical worktree lease fields")?;
            let lease = legacy.upgrade()?;
            row.payload_json = serde_json::to_string(&lease)?;
            row.payload_hash = content_hash(row.payload_json.as_bytes());
            row.schema_version = WorktreeLease::SCHEMA_VERSION;
            // Validate owner, identity and revision before writing any upgraded payload. The entire
            // batch commits atomically; a corrupt later record leaves earlier records untouched.
            let decoded = decode_object::<WorktreeLease>(row.clone())?;
            let mut active = row.into_active_model();
            active.schema_version = Set(WorktreeLease::SCHEMA_VERSION);
            let payload = serde_json::to_string(&decoded)?;
            active.payload_hash = Set(content_hash(payload.as_bytes()));
            active.payload_json = Set(payload);
            active.update(&tx).await?;
            leases.push(decoded);
        } else {
            leases.push(decode_object::<WorktreeLease>(row)?);
        }
    }
    tx.commit().await?;
    Ok(leases)
}

#[cfg(test)]
mod tests {
    use super::*;

    async fn insert(
        db: &DatabaseConnection,
        owner: &str,
        state: &str,
        corrupt: bool,
    ) -> Result<()> {
        let payload = serde_json::json!({
            "revision": 17, "state": state, "ownerKind": "child", "ownerThreadId": owner,
            "rootThreadId": "root", "projectId": "project", "sshAlias": null,
            "repositoryRoot": "/repo", "path": format!("/repo/.anywork/worktrees/root/{owner}"),
            "branch": format!("pure-agent-{owner}"), "baseCommit": "frozen-base",
            "restoreAuthorizedAt": 123456
        })
        .to_string();
        studio_object::ActiveModel {
            owner_kind: Set("agent".into()),
            owner_id: Set(owner.into()),
            object_kind: Set("worktreeLease".into()),
            revision: Set(17),
            schema_version: Set(2),
            payload_hash: Set(if corrupt {
                "broken".into()
            } else {
                content_hash(payload.as_bytes())
            }),
            payload_json: Set(payload),
            updated_at: Set(42),
        }
        .insert(db)
        .await?;
        Ok(())
    }

    #[tokio::test]
    async fn upgrade_retires_grants_preserving_identity_revision_and_state() -> Result<()> {
        let store = crate::studio::StudioStore::open_memory().await?;
        let db = store.database().clone();
        insert(&db, "active-child", "active", false).await?;
        insert(&db, "cleaned-child", "cleaned", false).await?;
        insert(&db, "cleanup-requested-child", "cleanupRequested", false).await?;
        let schema_three = studio_object::Entity::find_by_id((
            "agent".to_owned(),
            "cleaned-child".to_owned(),
            "worktreeLease".to_owned(),
        ))
        .one(&db)
        .await?
        .context("schema 3 lease")?;
        let mut payload: serde_json::Value = serde_json::from_str(&schema_three.payload_json)?;
        payload
            .as_object_mut()
            .context("schema 3 payload")?
            .remove("restoreAuthorizedAt");
        let payload = payload.to_string();
        let mut schema_three = schema_three.into_active_model();
        schema_three.payload_hash = Set(content_hash(payload.as_bytes()));
        schema_three.payload_json = Set(payload);
        schema_three.schema_version = Set(3);
        schema_three.update(&db).await?;
        let before = studio_object::Entity::find().all(&db).await?;
        let leases = load(&db).await?;
        assert_eq!(leases.len(), 3);
        let after = studio_object::Entity::find().all(&db).await?;
        for old in before {
            let new = after
                .iter()
                .find(|row| row.owner_id == old.owner_id)
                .context("retained owner")?;
            let mut old_payload: serde_json::Value = serde_json::from_str(&old.payload_json)?;
            old_payload
                .as_object_mut()
                .context("lease object")?
                .remove("restoreAuthorizedAt");
            old_payload
                .as_object_mut()
                .context("lease object")?
                .remove("branch");
            assert_eq!(
                serde_json::from_str::<serde_json::Value>(&new.payload_json)?,
                old_payload
            );
            assert_eq!(new.revision, old.revision);
            assert_eq!(new.updated_at, old.updated_at);
            assert_eq!(new.schema_version, 4);
            assert_eq!(new.payload_hash, content_hash(new.payload_json.as_bytes()));
        }
        assert_eq!(load(&db).await?, leases, "upgrade is idempotent");
        store.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn corrupt_lease_rolls_back_the_entire_upgrade() -> Result<()> {
        for fault in ["hash", "unknown-schema", "unpublished-close-draft"] {
            let store = crate::studio::StudioStore::open_memory().await?;
            let db = store.database().clone();
            insert(&db, "a-valid", "preserved", false).await?;
            insert(&db, "z-corrupt", "cleaned", fault == "hash").await?;
            if fault != "hash" {
                let row = studio_object::Entity::find_by_id((
                    "agent".to_owned(),
                    "z-corrupt".to_owned(),
                    "worktreeLease".to_owned(),
                ))
                .one(&db)
                .await?
                .context("invalid-format lease")?;
                let mut payload: serde_json::Value = serde_json::from_str(&row.payload_json)?;
                if fault == "unpublished-close-draft" {
                    let object = payload.as_object_mut().context("draft object")?;
                    object.remove("branch");
                    object.remove("restoreAuthorizedAt");
                    object.insert("closeDisposition".into(), "cleanup".into());
                }
                let payload = payload.to_string();
                let mut row = row.into_active_model();
                row.schema_version = Set(if fault == "unknown-schema" { 99 } else { 4 });
                row.payload_hash = Set(content_hash(payload.as_bytes()));
                row.payload_json = Set(payload);
                row.update(&db).await?;
            }
            let before = studio_object::Entity::find().all(&db).await?;
            assert!(load(&db).await.is_err(), "{fault} must not be migrated");
            assert_eq!(
                studio_object::Entity::find().all(&db).await?,
                before,
                "{fault} must roll back the preceding valid upgrade"
            );
            store.close().await?;
        }
        Ok(())
    }
}

//! Stable versioned object storage for bounded Studio working state.

use anyhow::{Context, Result, bail};
use pl_core::context::content_hash;
use sea_orm::{ActiveModelTrait, ActiveValue::Set, ConnectionTrait, EntityTrait, IntoActiveModel};
use serde::Serialize;
use serde::de::DeserializeOwned;

use crate::studio::entity::studio_object;

/// A bounded domain value that can be reconstructed from `studio_objects`.
pub(in crate::studio) trait PersistedStudioObject: Sized {
    type PersistenceDto: Serialize + DeserializeOwned;

    const OWNER_KIND: &'static str;
    const OBJECT_KIND: &'static str;
    const SCHEMA_VERSION: i64;

    fn revision(&self) -> u64;
    fn to_persistence_dto(&self) -> Self::PersistenceDto;
    fn from_persistence_dto(dto: Self::PersistenceDto) -> Result<Self>;
    fn validate_owner(&self, _owner_id: &str) -> Result<()> {
        Ok(())
    }
}

pub(in crate::studio) async fn load_object<T>(
    db: &impl ConnectionTrait,
    owner_id: &str,
) -> Result<Option<T>>
where
    T: PersistedStudioObject,
{
    let Some(row) = load_object_row::<T>(db, owner_id).await? else {
        return Ok(None);
    };
    decode_object::<T>(row)
        .map(Some)
        .map_err(crate::studio::startup::input_error)
}

pub(in crate::studio) async fn put_object<T>(
    db: &impl ConnectionTrait,
    owner_id: &str,
    value: &T,
    updated_at: i64,
) -> Result<()>
where
    T: PersistedStudioObject,
{
    let payload_json = serde_json::to_string(&value.to_persistence_dto())?;
    let payload_hash = content_hash(payload_json.as_bytes());
    let revision = i64::try_from(value.revision()).context("object revision exceeds SQLite")?;
    let existing = load_object_row::<T>(db, owner_id).await?;
    if let Some(existing) = existing {
        if existing.revision > revision {
            bail!("{} object {owner_id} revision regressed", T::OBJECT_KIND);
        }
        if existing.revision == revision {
            if existing.payload_hash == payload_hash && existing.payload_json == payload_json {
                return Ok(());
            }
            bail!("{} object {owner_id} revision conflicts", T::OBJECT_KIND);
        }
        let mut active = existing.into_active_model();
        active.revision = Set(revision);
        active.schema_version = Set(T::SCHEMA_VERSION);
        active.payload_json = Set(payload_json);
        active.payload_hash = Set(payload_hash);
        active.updated_at = Set(updated_at);
        active.update(db).await?;
        return Ok(());
    }
    studio_object::ActiveModel {
        owner_kind: Set(T::OWNER_KIND.to_string()),
        owner_id: Set(owner_id.to_string()),
        object_kind: Set(T::OBJECT_KIND.to_string()),
        revision: Set(revision),
        schema_version: Set(T::SCHEMA_VERSION),
        payload_json: Set(payload_json),
        payload_hash: Set(payload_hash),
        updated_at: Set(updated_at),
    }
    .insert(db)
    .await?;
    Ok(())
}

pub(in crate::studio) fn decode_object<T>(row: studio_object::Model) -> Result<T>
where
    T: PersistedStudioObject,
{
    if row.owner_kind != T::OWNER_KIND || row.object_kind != T::OBJECT_KIND {
        bail!("Studio object kind does not match the requested domain type");
    }
    if row.schema_version != T::SCHEMA_VERSION {
        bail!(
            "{} object {} has unsupported schema version {}",
            T::OBJECT_KIND,
            row.owner_id,
            row.schema_version
        );
    }
    let actual_hash = content_hash(row.payload_json.as_bytes());
    if actual_hash != row.payload_hash {
        bail!("{} object {} hash mismatch", T::OBJECT_KIND, row.owner_id);
    }
    let dto = serde_json::from_str::<T::PersistenceDto>(&row.payload_json)?;
    let value = T::from_persistence_dto(dto)?;
    value.validate_owner(&row.owner_id)?;
    let payload_revision =
        i64::try_from(value.revision()).context("object payload revision exceeds SQLite")?;
    if payload_revision != row.revision {
        bail!(
            "{} object {} revision mismatch: row={}, payload={payload_revision}",
            T::OBJECT_KIND,
            row.owner_id,
            row.revision
        );
    }
    Ok(value)
}

pub(in crate::studio) async fn load_object_row<T>(
    db: &impl ConnectionTrait,
    owner_id: &str,
) -> Result<Option<studio_object::Model>>
where
    T: PersistedStudioObject,
{
    Ok(studio_object::Entity::find_by_id((
        T::OWNER_KIND.to_string(),
        owner_id.to_string(),
        T::OBJECT_KIND.to_string(),
    ))
    .one(db)
    .await?)
}

/// Only deletion may ignore an undecodable auxiliary row. Database failures still propagate,
/// and a skipped row is never repaired or overwritten using an inferred identity.
pub(in crate::studio) async fn load_deletion_aux<T>(
    db: &impl ConnectionTrait,
    owner_id: &str,
) -> Result<Option<T>>
where
    T: PersistedStudioObject,
{
    Ok(load_object_row::<T>(db, owner_id)
        .await?
        .and_then(decode_deletion_aux::<T>))
}

pub(in crate::studio) async fn list_deletion_aux<T>(db: &impl ConnectionTrait) -> Result<Vec<T>>
where
    T: PersistedStudioObject,
{
    use sea_orm::{ColumnTrait, QueryFilter};
    Ok(studio_object::Entity::find()
        .filter(studio_object::Column::OwnerKind.eq(T::OWNER_KIND))
        .filter(studio_object::Column::ObjectKind.eq(T::OBJECT_KIND))
        .all(db)
        .await?
        .into_iter()
        .filter_map(decode_deletion_aux::<T>)
        .collect())
}

fn decode_deletion_aux<T: PersistedStudioObject>(row: studio_object::Model) -> Option<T> {
    let started = std::time::Instant::now();
    let owner = row.owner_id.clone();
    let reason = if row.schema_version != T::SCHEMA_VERSION {
        "aux_schema"
    } else if content_hash(row.payload_json.as_bytes()) != row.payload_hash {
        "aux_hash"
    } else {
        "aux_invariant"
    };
    match decode_object::<T>(row) {
        Ok(value) => Some(value),
        Err(error) => {
            let parse = error.downcast_ref::<serde_json::Error>();
            // The allowlist identifies known preparation invariants without formatting a
            // payload-bearing serde/anyhow error. Unknown validation failures stay categorical.
            let reason = if parse.is_some() {
                "aux_json"
            } else {
                match error.to_string().as_str() {
                    "preparation identity mismatch" => "preparation_identity",
                    "cyclic preparation identity" => "preparation_cycle",
                    "preparation retirement precedes producer ACK" => "preparation_retirement_ack",
                    "preparation stop precedes save ACK" => "preparation_save_ack",
                    "deletion stop ACK is missing" => "preparation_deletion_ack",
                    "attached obligation cannot be unattached" => "preparation_attachment",
                    "missing storage incarnation" => "preparation_incarnation",
                    "preparation save does not match its original closed receipt" => {
                        "preparation_closed_receipt"
                    }
                    "private save has no original storage obligation" => "preparation_storage",
                    "temp cleanup precedes original resource retirement" => "preparation_cleanup",
                    _ => reason,
                }
            };
            tracing::warn!(
                stage = "read_aux",
                member = %owner,
                object_kind = T::OBJECT_KIND,
                reason,
                decision = "preserve_unknown_skip",
                outcome = "skipped",
                elapsed_ms = started.elapsed().as_millis() as u64,
                line = parse.map(serde_json::Error::line),
                column = parse.map(serde_json::Error::column),
                "删除跳过不可解码的辅助记录"
            );
            None
        }
    }
}

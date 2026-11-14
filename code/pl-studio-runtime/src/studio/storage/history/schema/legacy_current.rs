//! Frozen current snapshot codec used only by published content migrations.
use super::super::execution_sources as sources;
use super::super::{integer, statement};
use super::legacy_content;
use super::legacy_timeline_types::CurrentProjection;
use super::legacy_timeline_types::FrozenCurrentProjection;
use anyhow::{Context, Result, ensure};
use pl_core::chat::{ChatContent, ChatContentKey, ContentData, ContentDescriptor};
use sea_orm::ConnectionTrait;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

#[cfg(test)]
pub(in crate::studio::storage::history) async fn read_archived(
    db: &impl ConnectionTrait,
) -> Result<CurrentProjection> {
    let row = db
        .query_one_raw(statement(
            "SELECT payload FROM completion_boundary_archive_view_state WHERE singleton_id=1",
            vec![],
        ))
        .await?
        .context("archived current is missing")?;
    let mut current: CurrentProjection =
        serde_json::from_slice(&row.try_get::<Vec<u8>>("", "payload")?)?;
    current.execution_present = false;
    Ok(current)
}
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct EntryPayload {
    owner: String,
    key: String,
    byte_length: u64,
}
#[derive(Debug, Clone)]
pub(crate) struct CurrentEntryWrite {
    pub collection: String,
    pub position: i64,
    pub entry_id: String,
    pub payload: Arc<[u8]>,
}
#[derive(Debug, Clone)]
pub(crate) enum CurrentEntryChange {
    Put(CurrentEntryWrite),
}
#[derive(Debug, Clone)]
pub(crate) struct CurrentContentWrite {
    pub content: Arc<ChatContent>,
    pub sealed: bool,
}
pub(in crate::studio::storage::history) struct LegacyCurrent {
    projection: Arc<FrozenCurrentProjection>,
    changes: Arc<[CurrentEntryChange]>,
    contents: Arc<[CurrentContentWrite]>,
    source_changes: Arc<[pl_protocol::ChatSourceState]>,
    references: Arc<[pl_protocol::ContentRef]>,
}
impl LegacyCurrent {
    pub(in crate::studio::storage::history) fn new(
        projection: Arc<FrozenCurrentProjection>,
        changes: Arc<[CurrentEntryChange]>,
        contents: Arc<[CurrentContentWrite]>,
    ) -> Self {
        let references = references(projection.projection()).cloned().collect();
        Self {
            projection,
            changes,
            contents,
            source_changes: Arc::from([]),
            references,
        }
    }
    fn projection(&self) -> &CurrentProjection {
        self.projection.projection()
    }
    fn frozen_projection(&self) -> &Arc<FrozenCurrentProjection> {
        &self.projection
    }
}

pub(in crate::studio) fn references(
    projection: &CurrentProjection,
) -> impl Iterator<Item = &pl_protocol::ContentRef> {
    projection
        .plan
        .iter()
        .filter_map(|plan| plan.document.as_ref())
        .chain(projection.previews.iter().map(|preview| &preview.reference))
        .chain(
            projection
                .atoms
                .iter()
                .flat_map(|atom| atom.contents.iter().map(|content| &content.reference)),
        )
}

pub(in super::super) fn validate_database(
    projection: &CurrentProjection,
    database_id: &str,
) -> Result<()> {
    for reference in projection
        .collections
        .iter()
        .chain(projection.interactions.iter())
    {
        ensure!(
            reference.database_id == database_id && !reference.collection.is_empty(),
            "current collection belongs to another database or has an empty identity"
        );
    }
    for reference in projection
        .plan
        .iter()
        .filter_map(|plan| plan.document.as_ref())
        .chain(projection.previews.iter().map(|preview| &preview.reference))
        .chain(
            projection
                .atoms
                .iter()
                .flat_map(|atom| atom.contents.iter().map(|content| &content.reference)),
        )
    {
        ensure!(
            reference.database_id == database_id,
            "current content belongs to another database"
        );
    }
    Ok(())
}

pub(crate) async fn apply(
    db: &impl ConnectionTrait,
    write_seq: u64,
    current: &LegacyCurrent,
) -> Result<()> {
    apply_changes(db, write_seq, current).await?;
    write_head(db, current).await
}

pub(in super::super) async fn apply_changes(
    db: &impl ConnectionTrait,
    write_seq: u64,
    current: &LegacyCurrent,
) -> Result<()> {
    ensure!(
        current.projection().source_effect_seq == write_seq,
        "current projection does not belong to the committing effect"
    );
    for write in current.contents.iter() {
        legacy_content::write_content(db, &write.content, write.sealed).await?;
    }
    // The product envelope is bounded; growing facts belong in the collection/content tables.
    ensure!(
        current.frozen_projection().json_bytes() <= u64::from(pl_protocol::CHAT_BATCH_MAX_BYTES),
        "current projection exceeds the product envelope budget"
    );
    for change in current.changes.iter() {
        match change {
            CurrentEntryChange::Put(entry) => {
                ensure!(
                    !entry.collection.is_empty() && !entry.entry_id.is_empty(),
                    "current collection identity is empty"
                );
                let collection = current
                    .projection()
                    .collections
                    .iter()
                    .chain(current.projection().interactions.iter())
                    .find(|reference| reference.collection == entry.collection)
                    .context("current entry has no collection revision")?;
                let owner = pl_protocol::ContentOwner::Current {
                    domain: format!("collection:{}", entry.collection),
                    id: entry.entry_id.clone(),
                    revision: collection.revision,
                };
                let owner = crate::studio::conversation_identity::content_owner_key(&owner)?;
                if let Some(row) = db.query_one_raw(statement(
                    "SELECT payload FROM conversation_view_entries WHERE collection=? AND entry_id=?",
                    vec![entry.collection.clone().into(), entry.entry_id.clone().into()],
                )).await? {
                    let old: EntryPayload = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "payload")?)?;
                    if old.owner != owner.as_str() { retire_owner(db, &old.owner).await?; }
                }
                let key = ChatContentKey {
                    owner: owner.clone(),
                    key: "entry".into(),
                };
                legacy_content::write_content(
                    db,
                    &ChatContent {
                        descriptor: ContentDescriptor {
                            key,
                            byte_length: entry.payload.len() as u64,
                            generation: collection.revision,
                            media_type: Some("application/json".into()),
                        },
                        data: ContentData::Bytes(entry.payload.clone()),
                    },
                    true,
                )
                .await?;
                let payload = serde_json::to_vec(&EntryPayload {
                    owner: owner.as_str().into(),
                    key: "entry".into(),
                    byte_length: entry.payload.len() as u64,
                })?;
                db.execute_raw(statement(
                    "INSERT INTO conversation_view_entries(collection,position,entry_id,payload)
                     VALUES(?,?,?,?) ON CONFLICT(collection,entry_id) DO UPDATE
                     SET position=excluded.position,payload=excluded.payload",
                    vec![
                        entry.collection.clone().into(),
                        entry.position.into(),
                        entry.entry_id.clone().into(),
                        payload.into(),
                    ],
                ))
                .await?;
            }
        }
    }
    validate_references(db, &current.references).await?;
    sources::apply(db, write_seq, &current.source_changes).await?;
    Ok(())
}

async fn validate_references(
    db: &impl ConnectionTrait,
    references: &[pl_protocol::ContentRef],
) -> Result<()> {
    for reference in references {
        let exists = match &reference.target {
            pl_protocol::ContentTarget::ItemPayload { item_id } => db
                .query_one_raw(statement(
                    "SELECT 1 FROM conversation_items WHERE item_id=?",
                    vec![item_id.clone().into()],
                ))
                .await?
                .is_some(),
            pl_protocol::ContentTarget::Body { owner, key } => {
                let owner_key = crate::studio::conversation_identity::content_owner_key(owner)?;
                db.query_one_raw(statement(
                    "SELECT 1 FROM conversation_contents WHERE owner_key=? AND content_key=?",
                    vec![owner_key.as_str().into(), key.clone().into()],
                ))
                .await?
                .is_some()
            }
        };
        ensure!(
            exists,
            "current projection contains an unpublished content reference"
        );
    }
    Ok(())
}

pub(in super::super) async fn write_head(
    db: &impl ConnectionTrait,
    current: &LegacyCurrent,
) -> Result<()> {
    let bytes = serde_json::to_vec(current.projection())?;
    ensure!(
        bytes.len() <= pl_protocol::CHAT_BATCH_MAX_BYTES as usize,
        "current projection exceeds the product envelope budget"
    );
    db.execute_raw(statement(
        "INSERT INTO conversation_view_state(singleton_id,payload) VALUES(1,?)
         ON CONFLICT(singleton_id) DO UPDATE SET payload=excluded.payload",
        vec![bytes.into()],
    ))
    .await?;
    Ok(())
}

pub(crate) async fn read(db: &impl ConnectionTrait) -> Result<CurrentProjection> {
    let row = db
        .query_one_raw(statement(
            "SELECT payload FROM conversation_view_state WHERE singleton_id=1",
            vec![],
        ))
        .await?
        .context("current projection is missing; explicit storage repair is required")?;
    let bytes: Vec<u8> = row.try_get("", "payload")?;
    ensure!(
        bytes.len() <= pl_protocol::CHAT_BATCH_MAX_BYTES as usize,
        "stored current projection exceeds the product envelope budget"
    );
    let mut current: CurrentProjection = serde_json::from_slice(&bytes)?;
    let row = db
        .query_one_raw(statement(
            "SELECT applied_write_seq FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("current projection has no effect watermark")?;
    ensure!(
        integer(current.source_effect_seq)? <= row.try_get::<i64>("", "applied_write_seq")?,
        "current projection exceeds the committed effect prefix"
    );
    // A database snapshot proves logical state, never a resident execution source.
    current.execution_present = false;
    Ok(current)
}

async fn retire_owner(db: &impl ConnectionTrait, owner: &str) -> Result<()> {
    db.execute_raw(statement(
        "DELETE FROM conversation_content_chunks WHERE owner_key=?",
        vec![owner.into()],
    ))
    .await?;
    db.execute_raw(statement(
        "DELETE FROM conversation_contents WHERE owner_key=?",
        vec![owner.into()],
    ))
    .await?;
    Ok(())
}

/// Frozen pre-schema-18 cold-domain validation used by CompletionBoundary only.
pub(in crate::studio::storage::history) async fn validate_cold_domains(
    db: &impl ConnectionTrait,
) -> Result<()> {
    let row = db
        .query_one_raw(statement(
            "SELECT thread_id,database_id,applied_write_seq FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("history identity is missing")?;
    let mut state = pl_core::thread::ThreadSnapshot::default();
    if let Some(fields) = db
        .query_one_raw(statement(
            "SELECT json_extract(payload,'$.state.extensions.\"studio.plan\"') AS plan,
                json_extract(payload,'$.state.permissions') AS permissions,
                json_extract(payload,'$.state.interactions') AS interactions,
                json_extract(payload,'$.state.turns') AS turns,
                json_extract(payload,'$.state.tasks') AS tasks,
                json_extract(payload,'$.state.attempts') AS attempts,
                json_extract(payload,'$.state.lifecycle') AS lifecycle
         FROM session_checkpoint WHERE id=1",
            vec![],
        ))
        .await?
    {
        macro_rules! domain {
            ($field:ident) => {
                if let Some(value) = fields.try_get::<Option<String>>("", stringify!($field))? {
                    state.$field = serde_json::from_str(&value)?;
                }
            };
        }
        if let Some(value) = fields.try_get::<Option<String>>("", "plan")? {
            state.extensions.insert(
                crate::plan_tool::PLAN_EXTENSION.into(),
                serde_json::from_str(&value)?,
            );
        }
        domain!(permissions);
        domain!(interactions);
        domain!(turns);
        domain!(tasks);
        domain!(attempts);
        if let Some(value) = fields.try_get::<Option<String>>("", "lifecycle")? {
            state.lifecycle = serde_json::from_str(&value)?;
        }
    }
    let _state = crate::studio::thread_projection::CurrentState::cold(
        row.try_get("", "database_id")?,
        row.try_get("", "thread_id")?,
        u64::try_from(row.try_get::<i64>("", "applied_write_seq")?)?,
        &state,
    )?;
    Ok(())
}

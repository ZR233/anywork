//! Frozen effect-local current mutations. This module never samples a live execution owner.

use super::*;
use crate::studio::thread_projection::FrozenCurrentProjection;
use pl_core::chat::{ChatContent, ChatContentKey, ChatError, ContentData, ContentDescriptor};
use pl_protocol::{CurrentCollectionRef, CurrentProjection};
use serde::{Deserialize, Serialize};

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
    Clear {
        collection: String,
    },
    Remove {
        collection: String,
        entry_id: String,
    },
    Put(CurrentEntryWrite),
}

#[derive(Debug, Clone)]
pub(crate) struct CurrentContentWrite {
    pub content: Arc<pl_core::chat::ChatContent>,
    /// An active body may append within its generation; sealing makes its bytes immutable.
    pub sealed: bool,
}

#[derive(Debug, Clone)]
pub(crate) struct PreparedTimelineItem {
    /// Payload is always deferred; the atomic completion item remains the only body copy.
    pub item: pl_protocol::TimelineItem,
}

#[derive(Debug, Clone)]
pub(crate) struct PreparedCurrent {
    pub(in crate::studio) timeline_update:
        Arc<crate::studio::thread_projection::timeline::TimelineUpdate>,
    projection: Arc<FrozenCurrentProjection>,
    pub changes: Arc<[CurrentEntryChange]>,
    pub contents: Arc<[CurrentContentWrite]>,
    /// Real source starts/ends from this effect, not group boundaries or presentation state.
    pub source_changes: Arc<[pl_protocol::ChatSourceState]>,
    /// Top-level Timeline display items this effect committed, in history order,
    /// with their ordered member references. Persisted in the same transaction
    /// as the atomic facts and current cut.
    pub timeline: Arc<[PreparedTimelineItem]>,
    /// Source effect at which the committed items above became visible.
    /// Set on publication; zero for effects that committed no display item.
    pub timeline_commit: u64,
}

impl PreparedCurrent {
    pub(in crate::studio) fn new(
        projection: Arc<FrozenCurrentProjection>,
        changes: Arc<[CurrentEntryChange]>,
        contents: Arc<[CurrentContentWrite]>,
    ) -> Self {
        Self {
            timeline_update: Arc::new(Default::default()),
            projection,
            changes,
            contents,
            source_changes: Arc::from([]),
            timeline: Arc::from([]),
            timeline_commit: 0,
        }
    }

    pub fn projection(&self) -> &CurrentProjection {
        self.projection.projection()
    }

    pub(in crate::studio) fn frozen_projection(&self) -> &Arc<FrozenCurrentProjection> {
        &self.projection
    }

    pub(in crate::studio) fn replace_projection(
        &mut self,
        projection: Arc<FrozenCurrentProjection>,
    ) {
        self.projection = projection;
    }

    pub fn projection_retained_bytes(&self) -> u64 {
        self.projection.retained_bytes()
    }
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

/// Must run in the same transaction as the frozen effect, before advancing its watermark.
pub(crate) async fn apply(
    db: &impl ConnectionTrait,
    write_seq: u64,
    current: &PreparedCurrent,
) -> Result<()> {
    ensure!(
        current.projection().source_effect_seq == write_seq,
        "current projection does not belong to the committing effect"
    );
    let mut live_keys = std::collections::BTreeSet::new();
    for write in current.contents.iter() {
        let key = &write.content.descriptor.key;
        live_keys.insert(key.clone());
        super::content::write_content(db, &write.content, write.sealed).await?;
    }
    let bytes = serde_json::to_vec(current.projection())?;
    // The product envelope is bounded; growing facts belong in the collection/content tables.
    ensure!(
        bytes.len() <= pl_protocol::CHAT_BATCH_MAX_BYTES as usize,
        "current projection exceeds the product envelope budget"
    );
    for change in current.changes.iter() {
        match change {
            CurrentEntryChange::Clear { collection } => {
                remove_entries(db, collection, None).await?;
            }
            CurrentEntryChange::Remove {
                collection,
                entry_id,
            } => {
                remove_entries(db, collection, Some(entry_id)).await?;
            }
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
                super::content::write_content(
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
    // Typed heads are bounded. Collection retirement follows explicit mutations; body retirement
    // only visits the current-owner directory prefix in bounded metadata batches.
    for reference in current
        .projection()
        .plan
        .iter()
        .filter_map(|p| p.document.as_ref())
        .chain(current.projection().previews.iter().map(|p| &p.reference))
        .chain(
            current
                .projection()
                .atoms
                .iter()
                .flat_map(|atom: &pl_protocol::ChatAtom| {
                    atom.contents
                        .iter()
                        .map(|content: &pl_protocol::ChatAtomContent| &content.reference)
                }),
        )
        .collect::<Vec<_>>()
    {
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
        if let pl_protocol::ContentTarget::Body { owner, key } = &reference.target {
            live_keys.insert(ChatContentKey {
                owner: crate::studio::conversation_identity::content_owner_key(owner)?,
                key: key.clone(),
            });
        }
    }
    if let Some(row) = db
        .query_one_raw(statement(
            "SELECT payload FROM conversation_view_state WHERE singleton_id=1",
            vec![],
        ))
        .await?
    {
        let old: CurrentProjection =
            serde_json::from_slice(&row.try_get::<Vec<u8>>("", "payload")?)?;
        for reference in old.collections.iter().chain(old.interactions.iter()) {
            if !current
                .projection()
                .collections
                .iter()
                .chain(current.projection().interactions.iter())
                .any(|new| new.collection == reference.collection)
            {
                remove_entries(db, &reference.collection, None).await?;
            }
        }
    }
    retire_current_contents(db, &live_keys).await?;
    retire_unsealed_items(db, &live_keys).await?;
    super::sources::apply(db, write_seq, &current.source_changes).await?;
    db.execute_raw(statement(
        "INSERT INTO conversation_view_state(singleton_id,payload) VALUES(1,?)
         ON CONFLICT(singleton_id) DO UPDATE SET payload=excluded.payload",
        vec![bytes.into()],
    ))
    .await?;
    Ok(())
}

/// Read only the canonical current interaction collection in the caller's snapshot transaction.
pub(crate) async fn pending_interactions(
    db: &impl ConnectionTrait,
    current: &CurrentProjection,
) -> Result<Vec<pl_protocol::InteractionRequest>> {
    let Some(reference) = current.interactions.as_ref() else {
        return Ok(Vec::new());
    };
    let rows = db.query_all_raw(statement(
        "SELECT payload FROM conversation_view_entries WHERE collection=? ORDER BY position,entry_id",
        vec![reference.collection.clone().into()],
    )).await?;
    let mut pending = Vec::new();
    for row in rows {
        let metadata: EntryPayload =
            serde_json::from_slice(&row.try_get::<Vec<u8>>("", "payload")?)?;
        let bytes = super::content::read_body_bytes(
            db,
            &ChatContentKey {
                owner: ChatKey::from_encoded(metadata.owner)?,
                key: metadata.key,
            },
            0,
            usize::try_from(metadata.byte_length)?,
        )
        .await?;
        let interaction: pl_protocol::InteractionRequest = serde_json::from_slice(&bytes)?;
        if interaction.status() == pl_protocol::InteractionStatus::Pending {
            pending.push(interaction);
        }
    }
    Ok(pending)
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

pub(crate) async fn verify(db: &impl ConnectionTrait, current: &PreparedCurrent) -> Result<()> {
    super::sources::verify(
        db,
        current.projection().source_effect_seq,
        &current.source_changes,
    )
    .await?;
    let row = db
        .query_one_raw(statement(
            "SELECT payload FROM conversation_view_state WHERE singleton_id=1",
            vec![],
        ))
        .await?
        .context("retried effect has no committed current projection")?;
    ensure!(
        row.try_get::<Vec<u8>>("", "payload")? == serde_json::to_vec(current.projection())?,
        ChatError::Conflict("retried effect changed its frozen current projection".into())
    );
    for write in current.contents.iter() {
        let stored = super::content::validate_content(db, &write.content)
            .await?
            .context("retried effect is missing committed current content")?;
        let descriptor = &write.content.descriptor;
        ensure!(
            stored.byte_length == descriptor.byte_length
                && stored.generation == descriptor.generation
                && stored.media_type == descriptor.media_type
                && (!write.sealed || stored.sealed),
            ChatError::Conflict("retried effect changed its frozen content descriptor".into())
        );
    }
    let mut changes = std::collections::BTreeMap::<(&str, &str), Option<&CurrentEntryWrite>>::new();
    let mut cleared = std::collections::BTreeSet::new();
    for change in current.changes.iter() {
        match change {
            CurrentEntryChange::Clear { collection } => {
                cleared.insert(collection.as_str());
                changes.retain(|(name, _), _| *name != collection.as_str());
            }
            CurrentEntryChange::Remove {
                collection,
                entry_id,
            } => {
                changes.insert((collection.as_str(), entry_id.as_str()), None);
            }
            CurrentEntryChange::Put(entry) => {
                changes.insert(
                    (entry.collection.as_str(), entry.entry_id.as_str()),
                    Some(entry),
                );
            }
        }
    }
    for collection in cleared {
        let expected: std::collections::BTreeSet<_> = changes
            .iter()
            .filter_map(|((name, id), entry)| {
                (*name == collection && entry.is_some()).then_some(*id)
            })
            .collect();
        let rows = db.query_all_raw(statement(
            "SELECT entry_id FROM conversation_view_entries WHERE collection=? ORDER BY position LIMIT ?",
            vec![collection.into(), integer(expected.len().checked_add(1).context("entry count overflow")?)?.into()],
        )).await?;
        let actual = rows
            .iter()
            .map(|row| row.try_get::<String>("", "entry_id"))
            .collect::<Result<std::collections::BTreeSet<_>, _>>()?;
        ensure!(
            actual
                .iter()
                .map(String::as_str)
                .collect::<std::collections::BTreeSet<_>>()
                == expected,
            ChatError::Conflict("retried effect changed its collection replacement".into())
        );
    }
    for ((collection, id), expected) in changes {
        let row = db.query_one_raw(statement(
            "SELECT position,payload FROM conversation_view_entries WHERE collection=? AND entry_id=?",
            vec![collection.into(), id.into()],
        )).await?;
        let Some(entry) = expected else {
            ensure!(
                row.is_none(),
                ChatError::Conflict("retried effect changed a collection removal".into())
            );
            continue;
        };
        let row = row.context("retried effect is missing a committed current entry")?;
        ensure!(
            row.try_get::<i64>("", "position")? == entry.position,
            ChatError::Conflict("retried effect changed a current entry position".into())
        );
        let metadata: EntryPayload =
            serde_json::from_slice(&row.try_get::<Vec<u8>>("", "payload")?)?;
        let reference = current
            .projection()
            .collections
            .iter()
            .chain(current.projection().interactions.iter())
            .find(|reference| reference.collection == collection)
            .context("retried entry has no revision")?;
        let owner = crate::studio::conversation_identity::content_owner_key(
            &pl_protocol::ContentOwner::Current {
                domain: format!("collection:{collection}"),
                id: id.into(),
                revision: reference.revision,
            },
        )?;
        ensure!(
            metadata.owner == owner.as_str()
                && metadata.key == "entry"
                && metadata.byte_length == entry.payload.len() as u64,
            ChatError::Conflict("retried effect changed a current entry descriptor".into())
        );
        let stored = super::content::validate_content(
            db,
            &ChatContent {
                descriptor: ContentDescriptor {
                    key: ChatContentKey {
                        owner,
                        key: metadata.key,
                    },
                    byte_length: metadata.byte_length,
                    generation: reference.revision,
                    media_type: Some("application/json".into()),
                },
                data: ContentData::Bytes(entry.payload.clone()),
            },
        )
        .await?
        .context("retried effect is missing current entry content")?;
        ensure!(stored.sealed, "committed current entry is unsealed");
    }
    Ok(())
}
pub(crate) fn validate_collection<'a>(
    current: &'a CurrentProjection,
    reference: &CurrentCollectionRef,
) -> Result<&'a CurrentCollectionRef> {
    current
        .collections
        .iter()
        .chain(current.interactions.iter())
        .find(|value| *value == reference)
        .ok_or_else(|| ChatError::StaleContent.into())
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

async fn retire_current_contents(
    db: &impl ConnectionTrait,
    live: &std::collections::BTreeSet<ChatContentKey>,
) -> Result<()> {
    // Derive the indexed domain prefix from Core's encoder, never a second Current-owner codec.
    let sample = ChatKey::new("current", "_")?;
    let prefix = sample
        .as_str()
        .strip_suffix('_')
        .context("current key has no identity suffix")?;
    let upper = format!("{prefix}\u{10ffff}");
    let mut after: Option<(String, String)> = None;
    loop {
        let mut sql = String::from(
            "SELECT owner_key,content_key FROM conversation_contents WHERE owner_key>=? AND owner_key<?",
        );
        let mut values = vec![prefix.into(), upper.clone().into()];
        if let Some((owner, key)) = &after {
            sql.push_str(" AND (owner_key,content_key)>(?,?)");
            values.push(owner.clone().into());
            values.push(key.clone().into());
        }
        sql.push_str(" ORDER BY owner_key,content_key LIMIT 64");
        let rows = db.query_all_raw(statement(&sql, values)).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let owner: String = row.try_get("", "owner_key")?;
            let name: String = row.try_get("", "content_key")?;
            after = Some((owner.clone(), name.clone()));
            let key = ChatContentKey {
                owner: ChatKey::from_encoded(owner.clone())?,
                key: name.clone(),
            };
            let Some(pl_protocol::ContentOwner::Current { domain, .. }) =
                super::content::current_owner(&key.owner)?
            else {
                continue;
            };
            // Entry bodies are retired with their indexed collection mutations. They are not a
            // second active-body snapshot and do not require scanning collection payloads here.
            if domain.starts_with("collection:") && name == "entry" {
                continue;
            }
            if !live.contains(&key) {
                db.execute_raw(statement(
                    "DELETE FROM conversation_content_chunks WHERE owner_key=? AND content_key=?",
                    vec![owner.clone().into(), name.clone().into()],
                ))
                .await?;
                db.execute_raw(statement(
                    "DELETE FROM conversation_contents WHERE owner_key=? AND content_key=?",
                    vec![owner.into(), name.into()],
                ))
                .await?;
            }
        }
    }
    Ok(())
}

async fn retire_unsealed_items(
    db: &impl ConnectionTrait,
    live: &std::collections::BTreeSet<ChatContentKey>,
) -> Result<()> {
    // The partial index contains only active bodies. Never scan the sealed Item history to retire
    // a withdrawn active owner, and never retire a completion sealed earlier in this transaction.
    let sample = ChatKey::new("item", "_")?;
    let prefix = sample
        .as_str()
        .strip_suffix('_')
        .context("item key has no identity suffix")?;
    let upper = format!("{prefix}\u{10ffff}");
    let mut after: Option<(String, String)> = None;
    loop {
        let mut sql = String::from(
            "SELECT owner_key,content_key FROM conversation_contents INDEXED BY conversation_contents_unsealed
             WHERE json_extract(CAST(payload AS TEXT),'$.sealed')=0 AND owner_key>=? AND owner_key<?");
        let mut values = vec![prefix.into(), upper.clone().into()];
        if let Some((owner, key)) = &after {
            sql.push_str(" AND (owner_key,content_key)>(?,?)");
            values.push(owner.clone().into());
            values.push(key.clone().into());
        }
        sql.push_str(" ORDER BY owner_key,content_key LIMIT 64");
        let rows = db.query_all_raw(statement(&sql, values)).await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let owner: String = row.try_get("", "owner_key")?;
            let name: String = row.try_get("", "content_key")?;
            after = Some((owner.clone(), name.clone()));
            let key = ChatContentKey {
                owner: ChatKey::from_encoded(owner.clone())?,
                key: name.clone(),
            };
            if !live.contains(&key) {
                db.execute_raw(statement(
                    "DELETE FROM conversation_content_chunks WHERE owner_key=? AND content_key=?",
                    vec![owner.clone().into(), name.clone().into()],
                ))
                .await?;
                db.execute_raw(statement(
                    "DELETE FROM conversation_contents WHERE owner_key=? AND content_key=?",
                    vec![owner.into(), name.into()],
                ))
                .await?;
            }
        }
    }
    Ok(())
}

async fn remove_entries(
    db: &impl ConnectionTrait,
    collection: &str,
    id: Option<&str>,
) -> Result<()> {
    loop {
        let mut sql = String::from(
            "SELECT entry_id,payload FROM conversation_view_entries WHERE collection=?",
        );
        let mut values = vec![collection.into()];
        if let Some(id) = id {
            sql.push_str(" AND entry_id=?");
            values.push(id.into());
        }
        sql.push_str(" ORDER BY position LIMIT 64");
        let rows = db.query_all_raw(statement(&sql, values)).await?;
        if rows.is_empty() {
            return Ok(());
        }
        for row in rows {
            let entry: EntryPayload =
                serde_json::from_slice(&row.try_get::<Vec<u8>>("", "payload")?)?;
            retire_owner(db, &entry.owner).await?;
            db.execute_raw(statement(
                "DELETE FROM conversation_view_entries WHERE collection=? AND entry_id=?",
                vec![
                    collection.into(),
                    row.try_get::<String>("", "entry_id")?.into(),
                ],
            ))
            .await?;
        }
    }
}

pub(crate) async fn page(
    db: &impl ConnectionTrait,
    reference: &CurrentCollectionRef,
    after: Option<&str>,
    demand: pl_protocol::ReadDemand,
    encode_continuation: &(dyn Fn(String) -> Result<String> + Send + Sync),
) -> Result<pl_protocol::CurrentCollectionPage> {
    demand.validate(1)?;
    let current = read(db).await?;
    validate_collection(&current, reference)?;
    // The Runtime lease binds this boundary to the exact database/collection/revision. Keep the
    // same inner keyset representation as its resident current reader.
    let after = after
        .map(serde_json::from_str::<(i64, String)>)
        .transpose()?;
    let mut sql = String::from(
        "SELECT position,entry_id,payload FROM conversation_view_entries WHERE collection=?",
    );
    let mut values = vec![reference.collection.clone().into()];
    if let Some((position, id)) = after {
        sql.push_str(" AND (position,entry_id)>(?,?)");
        values.push(position.into());
        values.push(id.into());
    }
    sql.push_str(" ORDER BY position LIMIT ?");
    values.push(i64::from(demand.max_items).into());
    let rows = db.query_all_raw(statement(&sql, values)).await?;
    let mut exhausted = rows.len() < demand.max_items as usize;
    let mut page = pl_protocol::CurrentCollectionPage {
        revision: reference.revision,
        entries: Vec::new(),
        continuation: None,
    };
    let mut entry_bytes = 0usize;
    for row in rows {
        let position: i64 = row.try_get("", "position")?;
        let metadata: EntryPayload =
            serde_json::from_slice(&row.try_get::<Vec<u8>>("", "payload")?)?;
        let key = ChatKey::from_encoded(metadata.owner)?;
        let owner = super::content::current_owner(&key)?
            .context("current entry has a non-current owner")?;
        let content_ref = pl_protocol::ContentRef {
            database_id: reference.database_id.clone(),
            target: pl_protocol::ContentTarget::Body {
                owner,
                key: metadata.key.clone(),
            },
        };
        let mut entry = pl_protocol::CurrentCollectionEntry {
            id: row.try_get("", "entry_id")?,
            position,
            payload: pl_protocol::PayloadData::Deferred {
                reference: content_ref,
                byte_length: metadata.byte_length,
            },
        };
        let cursor = encode_continuation(serde_json::to_string(&(position, &entry.id))?)?;
        let fixed = serde_json::to_vec(&pl_protocol::CurrentCollectionPage {
            revision: reference.revision,
            entries: Vec::new(),
            continuation: Some(cursor.clone()),
        })?
        .len();
        let deferred = serde_json::to_vec(&entry)?.len();
        let comma = usize::from(!page.entries.is_empty());
        let remaining = (demand.max_bytes as usize).saturating_sub(fixed + entry_bytes + comma);
        if deferred > remaining {
            exhausted = false;
            break;
        }
        if usize::try_from(metadata.byte_length)
            .ok()
            .and_then(|len| len.checked_mul(4))
            .and_then(|len| len.checked_add(deferred))
            .is_some_and(|cost| cost <= remaining)
        {
            let body = super::content::read_body_bytes(
                db,
                &ChatContentKey {
                    owner: key,
                    key: metadata.key,
                },
                0,
                usize::try_from(metadata.byte_length)?,
            )
            .await?;
            entry.payload = pl_protocol::PayloadData::Inline { bytes: body };
        }
        entry_bytes += comma + serde_json::to_vec(&entry)?.len();
        page.entries.push(entry);
        page.continuation = Some(cursor);
    }
    ensure!(
        exhausted || !page.entries.is_empty(),
        ChatError::InvalidDemand("current entry cannot fit demand".into())
    );
    if exhausted {
        page.continuation = None;
    }
    ensure!(
        serde_json::to_vec(&page)?.len() <= demand.max_bytes as usize,
        ChatError::InvalidDemand("current page envelope exceeds demand".into())
    );
    Ok(page)
}

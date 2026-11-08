//! Published schema-11 container decoding. No current tool or TimelineMeta decoder is used here.

use super::*;
use pl_core::chat::{
    ChatContent, ChatContentKey, ChatContents, ChatDraft, ContentData, ContentDescriptor,
};
use serde::Deserialize;
use serde_json::{Value as Json, json};

pub(in super::super) const CREATE_SCHEMA: &str = "
CREATE TABLE conversation_items (
    seq INTEGER PRIMARY KEY CHECK (seq > 0),
    item_id TEXT NOT NULL UNIQUE,
    query_class TEXT NOT NULL,
    parent_id TEXT,
    payload BLOB NOT NULL
);
CREATE INDEX conversation_items_by_class ON conversation_items(query_class,seq);
CREATE INDEX conversation_items_by_parent_class ON conversation_items(parent_id,query_class,seq);
CREATE TABLE conversation_contents (
    owner_key TEXT NOT NULL, content_key TEXT NOT NULL, payload BLOB NOT NULL,
    PRIMARY KEY(owner_key,content_key)
) WITHOUT ROWID;
CREATE INDEX conversation_contents_unsealed
    ON conversation_contents(owner_key,content_key)
    WHERE json_extract(CAST(payload AS TEXT),'$.sealed')=0;
CREATE TABLE conversation_content_chunks (
    owner_key TEXT NOT NULL, content_key TEXT NOT NULL,
    byte_offset INTEGER NOT NULL CHECK(byte_offset >= 0), data BLOB NOT NULL,
    PRIMARY KEY(owner_key,content_key,byte_offset),
    FOREIGN KEY(owner_key,content_key) REFERENCES conversation_contents(owner_key,content_key)
) WITHOUT ROWID;
CREATE TABLE conversation_view_state (
    singleton_id INTEGER PRIMARY KEY CHECK(singleton_id=1), payload BLOB NOT NULL
);
CREATE TABLE conversation_view_entries (
    collection TEXT NOT NULL, position INTEGER NOT NULL, entry_id TEXT NOT NULL, payload BLOB NOT NULL,
    PRIMARY KEY(collection,position), UNIQUE(collection,entry_id)
) WITHOUT ROWID;
";

const INLINE_BODY_BYTES: usize = 4 * 1024;

fn add_body(
    contents: &mut ChatContents,
    database_id: &str,
    id: &str,
    key: String,
    bytes: Arc<[u8]>,
) -> Result<Json> {
    let owner = ChatKey::new("item", id)?;
    let identity = ChatContentKey {
        owner,
        key: key.clone(),
    };
    let length = bytes.len() as u64;
    ensure!(
        contents
            .insert(
                identity.clone(),
                Arc::new(ChatContent {
                    descriptor: ContentDescriptor {
                        key: identity,
                        byte_length: length,
                        generation: 0,
                        media_type: Some("application/octet-stream".into())
                    },
                    data: ContentData::Bytes(bytes.clone()),
                })
            )
            .is_none(),
        "duplicate legacy content identity"
    );
    let mut body = json!({"key": key, "byteLength": length});
    if bytes.len() <= INLINE_BODY_BYTES {
        body["inline"] = json!(bytes.as_ref());
    } else {
        body["reference"] = json!({"databaseId":database_id, "target":{"kind":"body",
            "owner":{"kind":"item","itemId":id}, "key":key}});
    }
    Ok(body)
}

fn field_key(identity: &Json) -> Option<String> {
    let kind = identity.get("kind")?.as_str()?;
    match kind {
        "body" => Some("body".into()),
        "host" => identity.get("value")?.as_str().map(str::to_owned),
        "outputText" | "reasoningText" | "summaryText" => {
            Some(format!("part.{kind}.{}", identity.get("value")?.as_u64()?))
        }
        _ => None,
    }
}

pub(super) struct LegacyCompletion<'a> {
    pub(super) id: &'a str,
    pub(super) seq: u64,
    pub(super) kind: &'a str,
    pub(super) turn: Option<&'a str>,
    pub(super) source: Option<u64>,
    pub(super) sealed_at: Option<i64>,
    pub(super) original: &'a str,
}

/// Only the published container's optional provenance is typed here, never business metadata.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct LegacyProvenance {
    turn_id: Option<String>,
    source_effect_seq: Option<u64>,
    sealed_at: Option<i64>,
}

/// Index/container conflicts and actual content corruption fail the transaction. Unknown business
/// shape alone is localized to this item, with the exact source container retained as content.
pub(super) fn convert(
    completion: LegacyCompletion<'_>,
    thread_id: &str,
    database_id: &str,
) -> Result<ChatItem> {
    let LegacyCompletion {
        id,
        seq,
        kind,
        turn,
        source,
        sealed_at,
        original,
    } = completion;
    ensure!(
        !id.is_empty() && seq > 0,
        "legacy completion index identity is invalid"
    );
    integer(seq)?;
    ensure!(
        !database_id.is_empty(),
        "legacy completion has no database identity"
    );
    if let Some(source) = source {
        ensure!(source > 0, "legacy source effect is not positive");
        integer(source)?;
    }
    let stored: Json = serde_json::from_str(original)?;
    ensure!(
        stored.get("itemId").and_then(Json::as_str) == Some(id)
            && stored.get("appendSeq").and_then(Json::as_u64) == Some(seq),
        "legacy completion container differs from indexed identity"
    );
    let provenance = LegacyProvenance::deserialize(&stored)
        .context("legacy completion container provenance has invalid field types")?;
    if let Some(sequence) = provenance.source_effect_seq {
        ensure!(
            sequence > 0,
            "legacy completion sourceEffectSeq is not positive"
        );
        integer(sequence).context("legacy completion sourceEffectSeq exceeds the durable range")?;
    }
    ensure!(
        provenance.turn_id.as_deref() == turn
            && provenance.source_effect_seq == source
            && provenance.sealed_at == sealed_at,
        "legacy completion container differs from indexed provenance"
    );
    let meta = stored
        .get("meta")
        .cloned()
        .and_then(|bytes| serde_json::from_value::<Vec<u8>>(bytes).ok())
        .and_then(|bytes| serde_json::from_slice::<Json>(&bytes).ok());
    if let Some(meta) = &meta {
        for (field, expected) in [("id", id), ("threadId", thread_id)] {
            if let Some(actual) = meta.get(field).and_then(Json::as_str) {
                ensure!(
                    actual == expected,
                    "legacy completion metadata differs from indexed ownership"
                );
            }
        }
        if let Some(actual) = meta.get("turnId").and_then(Json::as_str) {
            ensure!(
                Some(actual) == turn,
                "legacy metadata differs from indexed Turn"
            );
        }
    }
    let descriptor = meta.as_ref().and_then(|meta| meta.get("descriptor"));
    let descriptor_kind = descriptor
        .and_then(|value| value.get("kind"))
        .and_then(Json::as_str);
    if let Some(descriptor_kind) = descriptor_kind {
        ensure!(
            descriptor_kind == kind,
            "legacy completion kind differs from its index"
        );
    }
    let data = descriptor.and_then(|value| value.get("data"));
    let mut unsupported = descriptor_kind.is_none()
        || data.is_none()
        || meta.as_ref().is_none_or(|meta| {
            meta.get("id").and_then(Json::as_str).is_none()
                || meta.get("threadId").and_then(Json::as_str).is_none()
        });
    let mut contents = ChatContents::new();
    let mut bodies = Vec::new();
    let mut identities = std::collections::BTreeSet::new();
    let mut keys = std::collections::BTreeSet::new();
    if let Some(fields) = stored.get("fields").and_then(Json::as_array) {
        for field in fields {
            if let Some(identity) = field.get("identity") {
                ensure!(
                    identities.insert(serde_json::to_string(identity)?),
                    "legacy public content contains a duplicate field identity"
                );
            }
            let Some(key) = field.get("identity").and_then(field_key) else {
                unsupported = true;
                continue;
            };
            if !keys.insert(key.clone()) {
                // Distinct old field identities may spell the same new opaque key. Preserve the
                // original container as Unsupported, rather than mislabeling it as corrupt data.
                unsupported = true;
                continue;
            }
            let text = field
                .get("text")
                .and_then(Json::as_str)
                .context("legacy public content has no original text")?;
            bodies.push(add_body(
                &mut contents,
                database_id,
                id,
                key,
                Arc::from(text.as_bytes()),
            )?);
        }
    } else {
        unsupported = true;
    }
    if kind == "tool" && keys.contains("legacy.record") {
        unsupported = true;
    }
    if unsupported {
        bodies.clear();
        // Unknown fields and all opaque source bytes remain recoverable in their original encoding.
        contents.clear();
        let mut body = add_body(
            &mut contents,
            database_id,
            id,
            "legacy.record".into(),
            Arc::from(original.as_bytes()),
        )?;
        body.as_object_mut()
            .context("legacy body is not an object")?
            .remove("inline");
        body["reference"] = json!({"databaseId":database_id, "target":{"kind":"body",
            "owner":{"kind":"item","itemId":id}, "key":"legacy.record"}});
        bodies.push(body);
    } else if kind == "tool" {
        // The old tool contract is deliberately not decoded. Retain its exact container bytes in
        // the declared manifest as well as the original public fields, including JSON spelling,
        // opaque numbers and metadata unknown to this version.
        let mut body = add_body(
            &mut contents,
            database_id,
            id,
            "legacy.record".into(),
            Arc::from(original.as_bytes()),
        )?;
        body.as_object_mut()
            .context("legacy body is not an object")?
            .remove("inline");
        body["reference"] = json!({"databaseId":database_id, "target":{"kind":"body",
            "owner":{"kind":"item","itemId":id}, "key":"legacy.record"}});
        bodies.push(body);
    }
    let resolved_user_input = kind == "tool"
        && data.is_some_and(|data| {
            data.get("userInput")
                .and_then(|input| input.get("state"))
                .and_then(|state| state.get("kind"))
                .and_then(Json::as_str)
                == Some("resolved")
        });
    let class = if matches!(kind, "text" | "raw" | "contextCompaction" | "plan" | "turn")
        || resolved_user_input
    {
        "conversation"
    } else {
        "activity"
    };
    let parent_id = turn.map(|turn| ChatKey::new("turn", turn)).transpose()?;
    let mut payload = json!({
        "contract":"anywork.chat/1",
        "type":kind,
        "data":data.cloned().unwrap_or_else(|| json!({
            "unsupported":{"reason":"Legacy business descriptor is unavailable"}
        })),
        "bodies":bodies,
    });
    if unsupported {
        payload["data"] =
            json!({"unsupported":{"reason":"Legacy business payload is unsupported"}});
    }
    if let Some(turn) = turn {
        payload["turnId"] = turn.into();
        if kind == "turn" {
            payload["childrenParentId"] = ChatKey::new("turn", turn)?.as_str().into();
        }
    }
    if let Some(source) = source {
        payload["sourceEffectSeq"] = source.into();
    }
    if let Some(sealed_at) = sealed_at {
        payload["sealedAt"] = sealed_at.into();
    }
    Ok(ChatItem::complete(
        ChatDraft {
            read_hint: pl_core::chat::ChatReadHint::Hidden,
            metadata: Arc::from([]),
            item_id: id.into(),
            query_class: class.into(),
            parent_id,
            payload: Arc::from(serde_json::to_vec(&payload)?),
            contents: Arc::new(contents),
        },
        seq,
        None,
    ))
}

/// Caller owns the official migration transaction and creates/seeds current before publishing it.
/// One source container at a time bounds payload memory independently of history length.
pub(in super::super) async fn backfill(db: &impl ConnectionTrait, thread_id: &str) -> Result<u64> {
    let row = db
        .query_one_raw(statement(
            "SELECT database_id FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
        .context("legacy completion database identity is missing")?;
    let database_id: String = row.try_get("", "database_id")?;
    let mut after = 0;
    loop {
        let row = db
            .query_one_raw(statement(
                "SELECT append_seq,record_id,turn_id,source_effect_seq,sealed_at,kind,payload
             FROM timeline_records WHERE append_seq>? ORDER BY append_seq LIMIT 1",
                vec![integer(after)?.into()],
            ))
            .await?;
        let Some(row) = row else {
            return Ok(after);
        };
        let seq = u64::try_from(row.try_get::<i64>("", "append_seq")?)?;
        ensure!(
            after.checked_add(1) == Some(seq),
            "legacy completion prefix is not contiguous"
        );
        let id: String = row.try_get("", "record_id")?;
        let turn: Option<String> = row.try_get("", "turn_id")?;
        let kind: String = row.try_get("", "kind")?;
        let source = row
            .try_get::<Option<i64>>("", "source_effect_seq")?
            .map(u64::try_from)
            .transpose()?;
        let payload: String = row.try_get("", "payload")?;
        let item = convert(
            LegacyCompletion {
                id: &id,
                seq,
                kind: &kind,
                turn: turn.as_deref(),
                source,
                sealed_at: row.try_get("", "sealed_at")?,
                original: &payload,
            },
            thread_id,
            &database_id,
        )?;
        append_published(db, &item).await?;
        after = seq;
    }
}

/// Frozen schema-12/13 fixture/import encoder. Ordinary writes use the current metadata column.
pub(in super::super) async fn append_published(
    db: &impl ConnectionTrait,
    item: &ChatItem,
) -> Result<()> {
    let h = &item.header;
    ensure!(
        latest_append_seq(db).await?.checked_add(1) == Some(h.append_seq),
        "legacy completion sequence is not contiguous"
    );
    db.execute_raw(statement(
        "INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload) VALUES(?,?,?,?,?)",
        vec![integer(h.append_seq)?.into(),h.item_id.clone().into(),h.query_class.clone().into(),
            h.parent_id.as_ref().map(|key|key.as_str().to_owned()).into(),item.payload.to_vec().into()],
    )).await?;
    let owner = ChatKey::new("item", &h.item_id)?;
    for (key, content) in item.contents.iter() {
        ensure!(
            key.owner == owner && *key == content.descriptor.key && !key.key.is_empty(),
            "published completion has a foreign content owner"
        );
        super::super::schema::legacy_content::write_content(db, content, true).await?;
    }
    Ok(())
}

/// Frozen schema-13 member directory, separate from its four-content preview window.
pub(in super::super) struct LegacyActiveMember {
    pub id: String,
    pub source_order: Option<u64>,
    pub contents: Vec<pl_protocol::ContentRef>,
}

pub(in super::super) async fn active_members(
    db: &impl ConnectionTrait,
    current: &crate::studio::storage::history::schema::legacy_timeline_types::CurrentProjection,
) -> Result<Vec<LegacyActiveMember>> {
    use pl_protocol::{ContentOwner, ContentRef, ContentTarget};
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase", deny_unknown_fields)]
    struct Entry {
        owner: String,
        key: String,
        byte_length: u64,
    }
    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase", deny_unknown_fields)]
    struct Body {
        reference: ContentRef,
        byte_length: u64,
        generation: u64,
    }
    let Some(collection) = current
        .collections
        .iter()
        .find(|entry| entry.collection == "members")
    else {
        return Ok(Vec::new());
    };
    let mut after: Option<(i64, String)> = None;
    let mut bytes = 0usize;
    let mut members = Vec::new();
    loop {
        let (sql, values) = if let Some((position, id)) = &after {
            (
                "SELECT position,entry_id,payload FROM conversation_view_entries WHERE collection='members' AND (position,entry_id)>(?,?) ORDER BY position,entry_id LIMIT 1",
                vec![(*position).into(), id.clone().into()],
            )
        } else {
            (
                "SELECT position,entry_id,payload FROM conversation_view_entries WHERE collection='members' ORDER BY position,entry_id LIMIT 1",
                vec![],
            )
        };
        let Some(row) = db.query_one_raw(statement(sql, values)).await? else {
            break;
        };
        let id: String = row.try_get("", "entry_id")?;
        let position: i64 = row.try_get("", "position")?;
        let entry: Entry = serde_json::from_slice(&row.try_get::<Vec<u8>>("", "payload")?)?;
        let expected =
            crate::studio::conversation_identity::content_owner_key(&ContentOwner::Current {
                domain: "collection:members".into(),
                id: id.clone(),
                revision: collection.revision,
            })?;
        ensure!(
            entry.owner == expected.as_str() && entry.key == "entry",
            "legacy member entry owner/revision differs"
        );
        ensure!(
            entry.byte_length <= pl_core::chat::MAX_READ_BYTES as u64,
            "legacy member entry exceeds the content read budget; original database preserved"
        );
        let data = super::content::read_body_bytes(
            db,
            &pl_core::chat::ChatContentKey {
                owner: expected,
                key: entry.key,
            },
            0,
            usize::try_from(entry.byte_length)?,
        )
        .await?;
        let bodies: Vec<Body> = serde_json::from_slice(&data)?;
        ensure!(
            !bodies.is_empty(),
            "legacy active member has no content references"
        );
        let mut contents = Vec::with_capacity(bodies.len());
        for body in bodies {
            // Bound retained references by a lower bound on the new current encoding,
            // not by the old directory's larger generation/byteLength wrappers.
            bytes = bytes
                .checked_add(serde_json::to_vec(&body.reference)?.len())
                .context("legacy member metadata size overflow")?;
            ensure!(
                bytes <= pl_protocol::CHAT_BATCH_MAX_BYTES as usize,
                "legacy active members exceed current budget; original database preserved"
            );
            ensure!(
                body.reference.database_id == collection.database_id,
                "legacy member content belongs to another database"
            );
            let ContentTarget::Body {
                owner: ContentOwner::Item { item_id },
                key,
            } = &body.reference.target
            else {
                anyhow::bail!("legacy member has no canonical item body owner");
            };
            ensure!(*item_id == id, "legacy member content owner differs");
            let owner = ChatKey::new("item", &id)?;
            let manifest = db
                .query_one_raw(statement(
                    "SELECT payload FROM conversation_contents WHERE owner_key=? AND content_key=?",
                    vec![owner.as_str().into(), key.clone().into()],
                ))
                .await?
                .context("legacy member content manifest missing")?;
            let descriptor = super::content::descriptor(
                owner.as_str(),
                key.clone(),
                &manifest.try_get::<Vec<u8>>("", "payload")?,
            )?;
            ensure!(
                descriptor.byte_length == body.byte_length
                    && descriptor.generation == body.generation,
                "legacy member content manifest differs"
            );
            contents.push(body.reference);
        }
        members.push(LegacyActiveMember {
            id: id.clone(),
            source_order: u64::try_from(position).ok().filter(|value| *value > 0),
            contents,
        });
        after = Some((position, id));
    }
    Ok(members)
}

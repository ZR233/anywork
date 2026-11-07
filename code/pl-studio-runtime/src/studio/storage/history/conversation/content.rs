use super::current::{CurrentContentOperation, CurrentContentState};
use super::*;
use pl_core::chat::{
    ChatContent, ChatContentKey, ChatContents, ChatError, ContentData, ContentDescriptor,
    ContentManifestPage, ContentManifestRequest,
};
use serde::{Deserialize, Serialize};

pub(super) const CHUNK_BYTES: usize = 64 * 1024;
pub(super) const MANIFEST_BYTES: usize = 8 * 1024;

#[cfg(test)]
#[path = "content/incremental_tests.rs"]
mod incremental_tests;
#[cfg(test)]
#[path = "content/save_work_tests.rs"]
mod save_work_tests;

/// The directory has a single bounded encoding, independent of the item's business payload.
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct Manifest {
    pub byte_length: u64,
    pub generation: u64,
    pub media_type: Option<String>,
    pub sealed: bool,
}

pub(super) async fn read_manifest(
    db: &impl ConnectionTrait,
    key: &ChatContentKey,
) -> Result<Option<(Manifest, Vec<u8>)>> {
    let row = db
        .query_one_raw(statement(
            "SELECT payload FROM conversation_contents WHERE owner_key=? AND content_key=?",
            vec![key.owner.as_str().into(), key.key.clone().into()],
        ))
        .await?;
    row.map(|row| {
        let bytes: Vec<u8> = row.try_get("", "payload")?;
        Ok((manifest(&bytes)?, bytes))
    })
    .transpose()
}

pub(super) fn require_expected(old: &Manifest, expected: &CurrentContentState) -> Result<()> {
    ensure!(
        old.generation == expected.generation
            && old.byte_length == expected.byte_length
            && old.media_type == expected.media_type
            && old.sealed == expected.sealed,
        ChatError::Conflict("prepared content baseline differs from durable manifest".into())
    );
    Ok(())
}

/// SQLite checks every old chunk's structure without returning any body data to the application.
/// The predecessor check is essential: a gap and an overlap can cancel in SUM(length(data)).
pub(super) async fn validate_structure(
    db: &impl ConnectionTrait,
    key: &ChatContentKey,
    byte_length: u64,
) -> Result<()> {
    let row = db
        .query_one_raw(statement(
            "WITH chunks AS (
           SELECT byte_offset,length(data) AS n,
             LAG(byte_offset+length(data),1,0) OVER(ORDER BY byte_offset) AS previous_end
           FROM conversation_content_chunks WHERE owner_key=? AND content_key=?
         )
         SELECT COALESCE(MAX(byte_offset+n),0) AS end_offset,
           COALESCE(SUM(CASE WHEN n<1 OR n>? OR byte_offset<0 OR byte_offset!=previous_end
             THEN 1 ELSE 0 END),0) AS invalid_chunks FROM chunks",
            vec![
                key.owner.as_str().into(),
                key.key.clone().into(),
                (CHUNK_BYTES as i64).into(),
            ],
        ))
        .await?
        .context("content structure query returned no aggregate")?;
    ensure!(
        row.try_get::<i64>("", "invalid_chunks")? == 0,
        "durable content has a chunk gap, overlap or invalid size"
    );
    let end = u64::try_from(row.try_get::<i64>("", "end_offset")?)?;
    ensure!(end <= byte_length, "durable content exceeds its manifest");
    ensure!(end == byte_length, "durable content has missing chunks");
    Ok(())
}

/// Normal reliable writes consume their frozen expected state; replay/full snapshots never use
/// this entry point. The transaction owner supplies only completions written in this same effect.
pub(super) async fn write_operation(
    db: &impl ConnectionTrait,
    content: &ChatContent,
    sealed: bool,
    operation: &CurrentContentOperation,
    completed: Option<&ChatContent>,
) -> Result<()> {
    let h = &content.descriptor;
    ensure!(
        !h.key.key.is_empty() && h.byte_length == content.data.len() as u64 && h.generation > 0,
        ChatError::Conflict("content manifest differs from its data".into())
    );
    integer(h.byte_length)?;
    if let Some(completed) = completed {
        ensure!(
            completed.descriptor == *h,
            ChatError::Conflict("current content differs from its effect completion".into())
        );
        // This exact effect's completion has already gone through the full writer, not merely an
        // arbitrary preexisting sealed key. Revalidate all bytes and preserve monotonic closure.
        return write_content(db, content, sealed).await;
    }
    let stored = read_manifest(db, &h.key).await?;
    let mut offset = 0;
    if let Some(expected) = operation.expected() {
        let (old, _) = stored
            .as_ref()
            .context("prepared content owner is missing")?;
        require_expected(old, expected)?;
        validate_structure(db, &h.key, old.byte_length).await?;
        match operation {
            CurrentContentOperation::Append(_) => {
                ensure!(
                    !old.sealed
                        && h.generation == old.generation
                        && h.media_type == old.media_type
                        && h.byte_length > old.byte_length,
                    ChatError::Conflict("invalid prepared content append".into())
                );
                offset = old.byte_length;
                if sealed {
                    validate_content(db, content).await?;
                }
            }
            CurrentContentOperation::Replace(_) => {
                ensure!(
                    !old.sealed && h.generation > old.generation,
                    ChatError::Conflict("invalid prepared content replacement".into())
                );
            }
            CurrentContentOperation::Seal(_) => {
                ensure!(
                    !old.sealed
                        && sealed
                        && h.generation == old.generation
                        && h.byte_length == old.byte_length
                        && h.media_type == old.media_type,
                    ChatError::Conflict("invalid prepared content seal".into())
                );
                validate_content(db, content).await?;
                offset = old.byte_length;
            }
            CurrentContentOperation::Takeover(_) => {
                validate_content(db, content).await?;
                offset = if old.generation == h.generation {
                    old.byte_length
                } else {
                    0
                };
            }
            CurrentContentOperation::Create => unreachable!("create has no expected state"),
        }
    } else {
        ensure!(
            stored.is_none(),
            ChatError::Conflict("created content owner already exists".into())
        );
        validate_structure(db, &h.key, 0).await?;
    }
    let sealed = sealed || stored.as_ref().is_some_and(|(old, _)| old.sealed);
    let payload = serde_json::to_vec(&Manifest {
        byte_length: h.byte_length,
        generation: h.generation,
        media_type: h.media_type.clone(),
        sealed,
    })?;
    ensure!(
        payload.len() <= MANIFEST_BYTES,
        "oversized content manifest"
    );
    if let Some((old, expected_payload)) = stored {
        let result = db.execute_raw(statement(
            "UPDATE conversation_contents SET payload=? WHERE owner_key=? AND content_key=? AND payload=?",
            vec![payload.into(), h.key.owner.as_str().into(), h.key.key.clone().into(), expected_payload.into()],
        )).await?;
        ensure!(
            result.rows_affected() == 1,
            ChatError::Conflict("prepared content conditional update lost its baseline".into())
        );
        if h.generation != old.generation {
            db.execute_raw(statement(
                "DELETE FROM conversation_content_chunks WHERE owner_key=? AND content_key=?",
                vec![h.key.owner.as_str().into(), h.key.key.clone().into()],
            ))
            .await?;
        }
    } else {
        let result = db
            .execute_raw(statement(
                "INSERT INTO conversation_contents(owner_key,content_key,payload) VALUES(?,?,?)",
                vec![
                    h.key.owner.as_str().into(),
                    h.key.key.clone().into(),
                    payload.into(),
                ],
            ))
            .await?;
        ensure!(
            result.rows_affected() == 1,
            "content creation did not insert its owner"
        );
    }
    write_chunks(db, content, offset).await
}

pub(super) fn descriptor(owner: &str, key: String, bytes: &[u8]) -> Result<ContentDescriptor> {
    let manifest = manifest(bytes)?;
    Ok(ContentDescriptor {
        key: ChatContentKey {
            owner: ChatKey::from_encoded(owner.to_owned())?,
            key,
        },
        byte_length: manifest.byte_length,
        generation: manifest.generation,
        media_type: manifest.media_type,
    })
}

pub(super) fn manifest(bytes: &[u8]) -> Result<Manifest> {
    ensure!(bytes.len() <= MANIFEST_BYTES, "oversized content manifest");
    let manifest: Manifest = serde_json::from_slice(bytes)?;
    integer(manifest.byte_length)?;
    Ok(manifest)
}

pub(in super::super) async fn write_contents(
    db: &impl ConnectionTrait,
    id: &str,
    contents: &ChatContents,
) -> Result<()> {
    let owner = ChatKey::new("item", id)?;
    write_owned_contents(db, &owner, contents).await
}

pub(super) async fn write_owned_contents(
    db: &impl ConnectionTrait,
    owner: &ChatKey,
    contents: &ChatContents,
) -> Result<()> {
    for (key, content) in contents {
        ensure!(
            &key.owner == owner && *key == content.descriptor.key && !key.key.is_empty(),
            "completion content manifest has a foreign or inconsistent owner"
        );
        write_content(db, content, true).await?;
    }
    Ok(())
}

pub(in super::super) async fn validate_content(
    db: &impl ConnectionTrait,
    content: &ChatContent,
) -> Result<Option<Manifest>> {
    let key = &content.descriptor.key;
    ensure!(
        !key.key.is_empty() && content.descriptor.byte_length == content.data.len() as u64,
        ChatError::Conflict("content manifest differs from its data".into())
    );
    integer(content.descriptor.byte_length)?;
    let Some(row) = db
        .query_one_raw(statement(
            "SELECT payload FROM conversation_contents WHERE owner_key=? AND content_key=?",
            vec![key.owner.as_str().into(), key.key.clone().into()],
        ))
        .await?
    else {
        return Ok(None);
    };
    let bytes: Vec<u8> = row.try_get("", "payload")?;
    ensure!(
        bytes.len() <= MANIFEST_BYTES,
        "oversized stored content manifest"
    );
    let old: Manifest = serde_json::from_slice(&bytes)?;
    let incoming = &content.descriptor;
    let replacement = !old.sealed && incoming.generation > old.generation;
    ensure!(
        replacement
            || (old.generation == incoming.generation
                && old.media_type == incoming.media_type
                && if old.sealed {
                    old.byte_length == incoming.byte_length
                } else {
                    old.byte_length <= incoming.byte_length
                }),
        ChatError::Conflict("durable content descriptor changed".into())
    );
    let mut offset = 0u64;
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT byte_offset,data FROM conversation_content_chunks
             WHERE owner_key=? AND content_key=? AND byte_offset>=?
             ORDER BY byte_offset LIMIT 16",
                vec![
                    key.owner.as_str().into(),
                    key.key.clone().into(),
                    integer(offset)?.into(),
                ],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let start = u64::try_from(row.try_get::<i64>("", "byte_offset")?)?;
            let bytes: Vec<u8> = row.try_get("", "data")?;
            #[cfg(test)]
            save_work_tests::materialized(bytes.len());
            ensure!(
                start == offset && !bytes.is_empty() && bytes.len() <= CHUNK_BYTES,
                "durable content has a chunk gap, overlap or invalid size"
            );
            let end = offset
                .checked_add(bytes.len() as u64)
                .context("content size overflow")?;
            ensure!(
                end <= old.byte_length,
                "durable content exceeds its manifest"
            );
            if !replacement {
                ensure!(
                    content.data.range(offset, bytes.len())?.as_bytes() == bytes,
                    ChatError::Conflict("durable content byte prefix changed".into())
                );
            }
            offset = end;
        }
    }
    ensure!(
        offset == old.byte_length,
        "durable content has missing chunks"
    );
    Ok(Some(old))
}

pub(super) async fn write_content(
    db: &impl ConnectionTrait,
    content: &ChatContent,
    sealed: bool,
) -> Result<()> {
    let old = validate_content(db, content).await?;
    // Closure is monotonic. An unchanged active snapshot cannot reopen an already sealed key.
    let sealed = sealed || old.as_ref().is_some_and(|old| old.sealed);
    let h = &content.descriptor;
    let payload = serde_json::to_vec(&Manifest {
        byte_length: h.byte_length,
        generation: h.generation,
        media_type: h.media_type.clone(),
        sealed,
    })?;
    ensure!(
        payload.len() <= MANIFEST_BYTES,
        "oversized content manifest"
    );
    db.execute_raw(statement(
        "INSERT INTO conversation_contents(owner_key,content_key,payload) VALUES(?,?,?)
         ON CONFLICT(owner_key,content_key) DO UPDATE SET payload=excluded.payload",
        vec![
            h.key.owner.as_str().into(),
            h.key.key.clone().into(),
            payload.into(),
        ],
    ))
    .await?;
    let replacement = old
        .as_ref()
        .is_some_and(|old| old.generation != h.generation);
    if replacement {
        // A genuine unsealed replacement advances generation. Readers that already captured the
        // old snapshot may finish; new requests carrying its generation are explicitly stale.
        db.execute_raw(statement(
            "DELETE FROM conversation_content_chunks WHERE owner_key=? AND content_key=?",
            vec![h.key.owner.as_str().into(), h.key.key.clone().into()],
        ))
        .await?;
    }
    let offset = if replacement {
        0
    } else {
        old.map_or(0, |old| old.byte_length)
    };
    write_chunks(db, content, offset).await
}

async fn write_chunks(
    db: &impl ConnectionTrait,
    content: &ChatContent,
    mut offset: u64,
) -> Result<()> {
    let h = &content.descriptor;
    while offset < h.byte_length {
        let bytes = content.data.range(offset, CHUNK_BYTES)?;
        ensure!(!bytes.as_bytes().is_empty(), "nonadvancing content chunk");
        db.execute_raw(statement(
            "INSERT INTO conversation_content_chunks(owner_key,content_key,byte_offset,data) VALUES(?,?,?,?)",
            vec![h.key.owner.as_str().into(), h.key.key.clone().into(), integer(offset)?.into(),
                bytes.as_bytes().to_vec().into()],
        )).await?;
        #[cfg(test)]
        save_work_tests::written(bytes.as_bytes().len());
        offset += bytes.as_bytes().len() as u64;
    }
    Ok(())
}

/// Decode only the generic key container. Encoding is always delegated to the one product mapper.
pub(super) fn current_owner(key: &ChatKey) -> Result<Option<pl_protocol::ContentOwner>> {
    let (length, rest) = key
        .as_str()
        .split_once(':')
        .context("invalid content owner key")?;
    let length: usize = length.parse()?;
    let (domain, id) = rest
        .split_at_checked(length)
        .context("invalid content owner domain")?;
    if domain != "current" {
        return Ok(None);
    }
    let (domain, id, revision): (String, String, u64) = serde_json::from_str(id)?;
    let owner = pl_protocol::ContentOwner::Current {
        domain,
        id,
        revision,
    };
    ensure!(
        crate::studio::conversation_identity::content_owner_key(&owner)? == *key,
        "noncanonical current content owner"
    );
    Ok(Some(owner))
}

pub(super) async fn read_body_bytes(
    db: &impl ConnectionTrait,
    key: &ChatContentKey,
    offset: u64,
    max_bytes: usize,
) -> Result<Vec<u8>> {
    let mut position = offset;
    let mut bytes = Vec::with_capacity(max_bytes);
    while bytes.len() < max_bytes {
        let (sql, boundary) = if position == offset {
            ("SELECT byte_offset,length(data) AS chunk_length,substr(data,?-byte_offset+1,?) AS bytes
              FROM conversation_content_chunks WHERE owner_key=? AND content_key=? AND byte_offset<=?
              ORDER BY byte_offset DESC LIMIT 1", true)
        } else {
            ("SELECT byte_offset,length(data) AS chunk_length,substr(data,?-byte_offset+1,?) AS bytes
              FROM conversation_content_chunks WHERE owner_key=? AND content_key=? AND byte_offset=?", false)
        };
        let row = db
            .query_one_raw(statement(
                sql,
                vec![
                    integer(position)?.into(),
                    integer(max_bytes - bytes.len())?.into(),
                    key.owner.as_str().into(),
                    key.key.clone().into(),
                    integer(position)?.into(),
                ],
            ))
            .await?
            .context("content has a missing range chunk")?;
        let start = u64::try_from(row.try_get::<i64>("", "byte_offset")?)?;
        let size = u64::try_from(row.try_get::<i64>("", "chunk_length")?)?;
        ensure!(
            size > 0
                && size <= CHUNK_BYTES as u64
                && start <= position
                && (boundary || start == position)
                && start.checked_add(size).is_some_and(|end| end > position),
            "content chunk gap, overlap or invalid length"
        );
        let part: Vec<u8> = row.try_get("", "bytes")?;
        let expected = (start + size - position).min((max_bytes - bytes.len()) as u64);
        ensure!(part.len() as u64 == expected, "incomplete content range");
        position += expected;
        bytes.extend_from_slice(&part);
    }
    Ok(bytes)
}
pub(in super::super) async fn read_contents(
    db: &impl ConnectionTrait,
    id: &str,
) -> Result<ChatContents> {
    let owner = ChatKey::new("item", id)?;
    // Only the explicit idempotency API loads a whole manifest/body; normal reads use list/ranges.
    let rows = db.query_all_raw(statement(
        "SELECT content_key,payload FROM conversation_contents WHERE owner_key=? ORDER BY content_key",
        vec![owner.as_str().into()],
    )).await?;
    let mut contents = ChatContents::new();
    for row in rows {
        let key: String = row.try_get("", "content_key")?;
        let descriptor = descriptor(
            owner.as_str(),
            key.clone(),
            &row.try_get::<Vec<u8>>("", "payload")?,
        )?;
        let mut body = Vec::new();
        let mut offset = 0u64;
        loop {
            let rows = db
                .query_all_raw(statement(
                    "SELECT byte_offset,data FROM conversation_content_chunks
                 WHERE owner_key=? AND content_key=? AND byte_offset>=?
                 ORDER BY byte_offset LIMIT 16",
                    vec![
                        owner.as_str().into(),
                        key.clone().into(),
                        integer(offset)?.into(),
                    ],
                ))
                .await?;
            if rows.is_empty() {
                break;
            }
            for row in rows {
                ensure!(
                    u64::try_from(row.try_get::<i64>("", "byte_offset")?)? == offset,
                    "content chunk gap or overlap"
                );
                let chunk: Vec<u8> = row.try_get("", "data")?;
                ensure!(
                    !chunk.is_empty() && chunk.len() <= CHUNK_BYTES,
                    "invalid content chunk length"
                );
                offset = offset
                    .checked_add(chunk.len() as u64)
                    .context("content length overflow")?;
                ensure!(
                    offset <= descriptor.byte_length,
                    "content exceeds manifest length"
                );
                body.extend_from_slice(&chunk);
            }
        }
        ensure!(
            offset == descriptor.byte_length,
            "content differs from manifest length"
        );
        contents.insert(
            descriptor.key.clone(),
            Arc::new(ChatContent {
                descriptor,
                data: ContentData::Bytes(Arc::from(body)),
            }),
        );
    }
    Ok(contents)
}

pub(in super::super) async fn list_contents(
    db: &impl ConnectionTrait,
    request: &ContentManifestRequest,
    budget: &dyn ChatBudget,
) -> Result<ContentManifestPage> {
    request.demand.validate()?;
    let owner = ChatKey::new("item", &request.item_id)?;
    if let Some(after) = &request.after {
        ensure!(
            after.owner == owner,
            "manifest continuation has a foreign owner"
        );
    }
    ensure!(
        db.query_one_raw(statement(
            "SELECT 1 FROM conversation_items WHERE item_id=?
             UNION ALL SELECT 1 FROM conversation_contents WHERE owner_key=? LIMIT 1",
            vec![request.item_id.clone().into(), owner.as_str().into()],
        ))
        .await?
        .is_some(),
        pl_core::chat::ChatError::NotFound(request.item_id.clone())
    );
    let mut sql =
        String::from("SELECT content_key,payload FROM conversation_contents WHERE owner_key=?");
    let mut values = vec![owner.as_str().into()];
    if let Some(after) = &request.after {
        sql.push_str(" AND content_key>?");
        values.push(after.key.clone().into());
    }
    sql.push_str(" ORDER BY content_key LIMIT ?");
    values.push(integer(request.demand.max_items)?.into());
    let rows = db.query_all_raw(statement(&sql, values)).await?;
    let mut exhausted = rows.len() < request.demand.max_items;
    let mut bytes = request.demand.max_bytes;
    let mut entries = Vec::new();
    for row in rows {
        let entry = descriptor(
            owner.as_str(),
            row.try_get("", "content_key")?,
            &row.try_get::<Vec<u8>>("", "payload")?,
        )?;
        let cost = budget.manifest_bytes(&entry);
        if cost > bytes {
            exhausted = false;
            break;
        }
        bytes -= cost;
        entries.push(entry);
    }
    ensure!(
        exhausted || !entries.is_empty(),
        pl_core::chat::ChatError::InvalidDemand("manifest entry cannot fit demand".into())
    );
    let next = if exhausted {
        None
    } else {
        entries.last().map(|entry| entry.key.clone())
    };
    Ok(ContentManifestPage { entries, next })
}

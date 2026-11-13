use super::*;
use pl_core::chat::{
    ChatContent, ChatContentKey, ChatContents, ChatError, ContentData, ContentDescriptor,
    ContentManifestPage, ContentManifestRequest,
};
use serde::{Deserialize, Serialize};

pub(in crate::studio::storage::history) const CHUNK_BYTES: usize = 64 * 1024;
pub(in crate::studio::storage::history) const MANIFEST_BYTES: usize = 8 * 1024;

/// The directory has a single bounded encoding, independent of the item's business payload.
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::studio::storage::history) struct Manifest {
    pub byte_length: u64,
    pub generation: u64,
    pub media_type: Option<String>,
    pub sealed: bool,
}

pub(in crate::studio::storage::history) fn descriptor(
    owner: &str,
    key: String,
    bytes: &[u8],
) -> Result<ContentDescriptor> {
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

pub(in crate::studio::storage::history) fn manifest(bytes: &[u8]) -> Result<Manifest> {
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

pub(in crate::studio::storage::history) async fn write_owned_contents(
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
    ensure!(
        old.sealed
            && old.generation == incoming.generation
            && old.media_type == incoming.media_type
            && old.byte_length == incoming.byte_length,
        ChatError::Conflict("immutable durable content descriptor changed".into())
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
            ensure!(
                content.data.range(offset, bytes.len())?.as_bytes() == bytes,
                ChatError::Conflict("immutable durable content bytes changed".into())
            );
            offset = end;
        }
    }
    ensure!(
        offset == old.byte_length,
        "durable content has missing chunks"
    );
    Ok(Some(old))
}

pub(in crate::studio::storage::history) async fn write_content(
    db: &impl ConnectionTrait,
    content: &ChatContent,
    sealed: bool,
) -> Result<()> {
    ensure!(sealed, "only complete content may enter the normal writer");
    if validate_content(db, content).await?.is_some() {
        return Ok(());
    }
    let h = &content.descriptor;
    ensure!(h.generation > 0, "complete content has no generation");
    let payload = serde_json::to_vec(&Manifest {
        byte_length: h.byte_length,
        generation: h.generation,
        media_type: h.media_type.clone(),
        sealed: true,
    })?;
    ensure!(
        payload.len() <= MANIFEST_BYTES,
        "oversized content manifest"
    );
    db.execute_raw(statement(
        "INSERT INTO conversation_contents(owner_key,content_key,payload) VALUES(?,?,?)",
        vec![
            h.key.owner.as_str().into(),
            h.key.key.clone().into(),
            payload.into(),
        ],
    ))
    .await?;
    write_chunks(db, content, 0).await
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
pub(in crate::studio::storage::history) fn current_owner(
    key: &ChatKey,
) -> Result<Option<pl_protocol::ContentOwner>> {
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

pub(in crate::studio::storage::history) async fn read_body_bytes(
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
    let rows = db
        .query_all_raw(statement(
            "SELECT content_key,payload FROM conversation_contents WHERE owner_key=?
         AND json_type(payload,'$.sealed') IS NOT 'false' ORDER BY content_key",
            vec![owner.as_str().into()],
        ))
        .await?;
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
            "SELECT 1 FROM conversation_items WHERE item_id=?",
            vec![request.item_id.clone().into()],
        ))
        .await?
        .is_some(),
        pl_core::chat::ChatError::NotFound(request.item_id.clone())
    );
    let mut sql = String::from(
        "SELECT content_key,payload FROM conversation_contents WHERE owner_key=?
            AND json_type(payload,'$.sealed') IS NOT 'false'",
    );
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

#[cfg(test)]
mod save_work_tests {
    //! Counters at the actual chunk read/write sites. They retain no body material.
    use super::*;
    use std::cell::RefCell;

    #[derive(Default, Clone)]
    struct BodyWork {
        materialized_old_rows: u64,
        materialized_old_bytes: u64,
        written_chunk_rows: u64,
        written_chunk_bytes: u64,
    }
    thread_local! {
        static WORK: RefCell<Option<BodyWork>> = const { RefCell::new(None) };
    }
    pub(super) fn materialized(bytes: usize) {
        WORK.with_borrow_mut(|work| {
            if let Some(work) = work {
                work.materialized_old_rows += 1;
                work.materialized_old_bytes += bytes as u64;
            }
        });
    }
    pub(super) fn written(bytes: usize) {
        WORK.with_borrow_mut(|work| {
            if let Some(work) = work {
                work.written_chunk_rows += 1;
                work.written_chunk_bytes += bytes as u64;
            }
        });
    }

    #[tokio::test]
    async fn complete_body_is_written_once_and_replay_verifies_every_byte() -> Result<()> {
        let (_dir, db) = super::super::tests::fixture().await?;
        let bytes: Arc<[u8]> = Arc::from(vec![b'x'; CHUNK_BYTES * 2 + 37]);
        let content = ChatContent {
            descriptor: ContentDescriptor {
                key: ChatContentKey {
                    owner: ChatKey::new("item", "whole")?,
                    key: "body".into(),
                },
                byte_length: bytes.len() as u64,
                generation: 1,
                media_type: Some("text/plain".into()),
            },
            data: ContentData::Bytes(bytes.clone()),
        };
        WORK.set(Some(BodyWork::default()));
        write_content(&db, &content, true).await?;
        let initial = WORK.take().unwrap();
        assert_eq!(initial.written_chunk_bytes, bytes.len() as u64);
        assert_eq!(initial.written_chunk_rows, 3);
        assert_eq!(initial.materialized_old_bytes, 0);
        WORK.set(Some(BodyWork::default()));
        write_content(&db, &content, true).await?;
        let replay = WORK.take().unwrap();
        assert_eq!(replay.written_chunk_bytes, 0);
        assert_eq!(replay.materialized_old_rows, 3);
        assert_eq!(replay.materialized_old_bytes, bytes.len() as u64);
        db.execute_raw(statement(
        "UPDATE conversation_content_chunks SET data=? WHERE owner_key=? AND content_key='body' AND byte_offset=0",
        vec![vec![b'y'; CHUNK_BYTES].into(), content.descriptor.key.owner.as_str().into()],
    )).await?;
        assert!(write_content(&db, &content, true).await.is_err());
        Ok(())
    }
}

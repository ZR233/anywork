//! Frozen full-snapshot body writer for the published current migrations only.
use super::super::conversation::content::{CHUNK_BYTES, MANIFEST_BYTES, Manifest};
use super::super::{integer, statement};
use anyhow::{Context, Result, ensure};
use pl_core::chat::{ChatContent, ChatError};
use sea_orm::ConnectionTrait;
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

pub(in crate::studio::storage::history) async fn write_content(
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
        offset += bytes.as_bytes().len() as u64;
    }
    Ok(())
}

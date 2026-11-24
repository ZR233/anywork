//! Frozen schema-24 conversation decoding for the explicit legacy migration boundary.

use super::{integer, statement};
use anyhow::{Context, Result, ensure};
use pl_core::chat::{ChatItem, ChatItemHeader, ChatKey};
use sea_orm::{ConnectionTrait, QueryResult};
use std::sync::Arc;

#[path = "conversation/content.rs"]
pub(in crate::studio::storage::history) mod content;
pub(in crate::studio) mod display;
#[path = "conversation/migration.rs"]
pub(super) mod migration;

pub(super) use content::read_contents;

fn header(row: &QueryResult) -> Result<ChatItemHeader> {
    let metadata: Arc<[u8]> = Arc::from(row.try_get::<Vec<u8>>("", "metadata")?);
    let query_class: String = row.try_get("", "query_class")?;
    let header = ChatItemHeader {
        append_seq: u64::try_from(row.try_get::<i64>("", "seq")?)?,
        item_id: row.try_get("", "item_id")?,
        query_class,
        parent_id: row
            .try_get::<Option<String>>("", "parent_id")?
            .map(ChatKey::from_encoded)
            .transpose()?,
        byte_length: u64::try_from(row.try_get::<i64>("", "byte_length")?)?,
        metadata,
    };
    Ok(header)
}

pub(super) async fn latest_append_seq(db: &impl ConnectionTrait) -> Result<u64> {
    let row = db
        .query_one_raw(statement(
            "SELECT seq FROM conversation_items ORDER BY seq DESC LIMIT 1",
            vec![],
        ))
        .await?;
    row.map(|row| Ok(u64::try_from(row.try_get::<i64>("", "seq")?)?))
        .unwrap_or(Ok(0))
}

/// This complete read is for publication idempotency, not normal pages or range reads.
pub(super) async fn read_item(db: &impl ConnectionTrait, id: &str) -> Result<Option<ChatItem>> {
    let Some(row) = db
        .query_one_raw(statement(
            "SELECT seq,item_id,query_class,parent_id,metadata,length(payload) AS byte_length,payload
         FROM conversation_items WHERE item_id=?",
            vec![id.into()],
        ))
        .await?
    else {
        return Ok(None);
    };
    let header = header(&row)?;
    Ok(Some(ChatItem {
        header,
        payload: Arc::from(row.try_get::<Vec<u8>>("", "payload")?),
        contents: Arc::new(read_contents(db, id).await?),
    }))
}

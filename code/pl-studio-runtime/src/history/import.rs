//! Bounded schema-24 conversion primitives. Production replacement, backups and current extraction
//! remain at the explicit upgrade boundary in issue #470.

use super::{
    db::{self, statement},
    *,
};
use sea_orm::{ConnectionTrait, DatabaseConnection, DatabaseTransaction, TransactionTrait};
use sha2::{Digest, Sha256};
use std::{path::Path, sync::Arc};

/// A fixed-range source. Migration hashes and copies it in 64 KiB windows; it never requires
/// materializing a complete historical body. The source must retain one immutable read snapshot.
pub trait HistoryBodySource: Send + Sync {
    fn byte_length(&self) -> u64;
    fn read(&self, offset: u64, max_bytes: u32) -> impl Future<Output = Result<Vec<u8>>> + Send;
}

pub struct HistoryImportBody {
    pub body_id: String,
    pub owner_event_id: String,
    pub ordinal: u64,
    pub body_key: String,
    pub role: HistoryBodyRole,
    pub media_type: Option<String>,
}

/// Used only while the caller holds the explicit upgrade transaction and owns the target file.
/// It does not publish live cuts or touch current state. The caller commits only after finish().
pub struct HistoryImport<'a> {
    tx: &'a DatabaseTransaction,
    database_id: String,
    sequence: u64,
}
impl<'a> HistoryImport<'a> {
    pub async fn new(tx: &'a DatabaseTransaction, database_id: String) -> Result<Self> {
        let row = tx
            .query_one_raw(statement(
                "SELECT database_id,schema_version FROM history_store_meta WHERE singleton=1",
                vec![],
            ))
            .await?
            .ok_or_else(|| HistoryError::Integrity("import target identity is missing".into()))?;
        if row.try_get::<String>("", "database_id")? != database_id
            || row.try_get::<i64>("", "schema_version")? != 25
        {
            return Err(HistoryError::Integrity(
                "import target identity differs".into(),
            ));
        }
        let row = tx
            .query_one_raw(statement(
                "SELECT COALESCE(MAX(seq),0) AS seq FROM history_events",
                vec![],
            ))
            .await?
            .ok_or_else(|| HistoryError::Integrity("import sequence is missing".into()))?;
        let sequence = u64::try_from(row.try_get::<i64>("", "seq")?)
            .map_err(|_| HistoryError::Integrity("negative import sequence".into()))?;
        Ok(Self {
            tx,
            database_id,
            sequence,
        })
    }
    pub async fn copy_body(
        &mut self,
        body: HistoryImportBody,
        source: &impl HistoryBodySource,
    ) -> Result<HistoryEventBodyRef> {
        let uuid = uuid::Uuid::parse_str(&body.body_id)
            .map_err(|_| HistoryError::InvalidEvent("import body ID must be UUIDv4".into()))?;
        if uuid.get_version_num() != 4 || body.owner_event_id.is_empty() || body.body_key.is_empty()
        {
            return Err(HistoryError::InvalidEvent(
                "invalid import body identity".into(),
            ));
        }
        db::number(source.byte_length())?;
        let mut hash = Sha256::new();
        let mut offset = 0;
        while offset < source.byte_length() {
            let bytes = source_window(source, offset).await?;
            hash.update(&bytes);
            offset += bytes.len() as u64;
        }
        let metadata = db::Body {
            id: body.body_id,
            owner: body.owner_event_id,
            ordinal: body.ordinal,
            key: body.body_key,
            role: body.role,
            length: source.byte_length(),
            media_type: body.media_type,
            digest: hash.finalize().to_vec(),
        };
        db::insert_body_header(self.tx, &metadata).await?;
        let mut verify = Sha256::new();
        let mut offset = 0u64;
        let mut chunk = 0i64;
        while offset < source.byte_length() {
            let bytes = source_window(source, offset).await?;
            verify.update(&bytes);
            offset += bytes.len() as u64;
            self.tx
                .execute_raw(statement(
                    "INSERT INTO history_body_chunks(body_id,chunk_no,data) VALUES(?,?,?)",
                    vec![metadata.id.clone().into(), chunk.into(), bytes.into()],
                ))
                .await?;
            chunk += 1;
        }
        if verify.finalize().as_slice() != metadata.digest {
            return Err(HistoryError::Integrity(
                "source body changed while being imported".into(),
            ));
        }
        Ok(metadata.reference(&self.database_id))
    }
    /// Header and body insertion are separate solely for bounded migration. All body ownership
    /// and payload links close inside the caller's deferred-FK transaction.
    pub async fn insert_event(&mut self, mut event: HistoryEvent) -> Result<u64> {
        if !event.bodies.is_empty() || event.header.seq != 0 {
            return Err(HistoryError::InvalidEvent(
                "streamed import accepts unnumbered metadata only".into(),
            ));
        }
        let mut header_check = event.clone();
        header_check.payload_body_id = None;
        header_check.header.original = None;
        validate::event(&header_check)?;
        if db::event(self.tx, &event.header.event_id).await?.is_some() {
            return Err(HistoryError::Conflict(event.header.event_id));
        }
        if let Some(payload) = &event.payload_body_id {
            let body = db::body(self.tx, payload)
                .await?
                .ok_or_else(|| HistoryError::Integrity("import payload body is missing".into()))?;
            if body.owner != event.header.event_id || body.role != HistoryBodyRole::CanonicalPayload
            {
                return Err(HistoryError::InvalidEvent(
                    "import payload ownership differs".into(),
                ));
            }
        }
        if let Some(original) = &event.header.original {
            if event.payload_body_id.is_none() || original.query_class.is_empty() {
                return Err(HistoryError::InvalidEvent(
                    "canonical import has no payload or class".into(),
                ));
            }
            let head = match &event.head {
                Some(HistoryRowHead::Single(head) | HistoryRowHead::Member(head)) => head.clone(),
                _ => {
                    let bodies = db::bodies(self.tx, &event.header.event_id, None, 512).await?;
                    let metadata = bodies
                        .into_iter()
                        .find(|body| body.role == HistoryBodyRole::CanonicalMetadata)
                        .ok_or_else(|| {
                            HistoryError::InvalidEvent(
                                "canonical import has no typed metadata".into(),
                            )
                        })?;
                    if metadata.length > HEAD_MAX_BYTES as u64 {
                        return Err(HistoryError::InvalidEvent(
                            "canonical import metadata is not bounded".into(),
                        ));
                    }
                    serde_json::from_slice::<HistoryEntityHead>(
                        &db::window(self.tx, &metadata, 0, metadata.length as usize).await?,
                    )?
                }
            };
            if Some(&head.entity_id) != event.header.entity_id.as_ref()
                || head.kind != original.original_kind
                || head.tool.as_ref().map(|tool| &tool.name) != original.tool_name.as_ref()
            {
                return Err(HistoryError::InvalidEvent(
                    "canonical import indexes differ".into(),
                ));
            }
        }
        self.sequence = self
            .sequence
            .checked_add(1)
            .filter(|seq| *seq <= i64::MAX as u64)
            .ok_or_else(|| HistoryError::InvalidEvent("import sequence exhausted".into()))?;
        event.header.seq = self.sequence;
        db::insert_event(self.tx, &event).await?;
        Ok(self.sequence)
    }
    pub async fn finish(self) -> Result<()> {
        if !self
            .tx
            .query_all_raw(statement("PRAGMA foreign_key_check", vec![]))
            .await?
            .is_empty()
        {
            return Err(HistoryError::Integrity(
                "import has unresolved body ownership".into(),
            ));
        }
        if self.tx.query_one_raw(statement("SELECT row_key FROM history_events AS e WHERE row_key IS NOT NULL AND NOT EXISTS(SELECT 1 FROM history_events AS a WHERE a.row_key=e.row_key AND a.is_anchor=1) LIMIT 1", vec![])).await?.is_some() { return Err(HistoryError::Integrity("import row has no anchor".into())); }
        Ok(())
    }
}
async fn source_window(source: &impl HistoryBodySource, offset: u64) -> Result<Vec<u8>> {
    let length = (source.byte_length() - offset).min(BODY_CHUNK_BYTES as u64) as u32;
    let bytes = source.read(offset, length).await?;
    if bytes.len() != length as usize {
        return Err(HistoryError::Integrity(
            "import source has a gap or short range".into(),
        ));
    }
    Ok(bytes)
}

struct V24Inner {
    connection: DatabaseConnection,
    tx: DatabaseTransaction,
}
#[derive(Clone)]
pub struct V24HistorySource {
    inner: Arc<V24Inner>,
}

#[derive(Debug, Clone)]
pub struct V24Original {
    pub seq: u64,
    pub item_id: String,
    pub query_class: String,
    pub parent_id: Option<String>,
    pub payload_bytes: u64,
    pub metadata_bytes: u64,
}
#[derive(Debug, Clone)]
pub enum V24Body {
    Payload {
        item_id: String,
    },
    Metadata {
        item_id: String,
    },
    Content {
        owner_key: String,
        content_key: String,
    },
}
pub struct V24BodyReader {
    source: V24HistorySource,
    body: V24Body,
    length: u64,
}
impl V24HistorySource {
    /// Pins one read-only source snapshot. This never performs a published-format upgrade.
    pub async fn open(path: impl AsRef<Path>, thread_id: &str) -> Result<Self> {
        let connection = schema::connect(path.as_ref(), true, false).await?;
        let tx = connection.begin().await?;
        let meta = tx
            .query_one_raw(statement(
                "SELECT schema_version,thread_id FROM history_meta WHERE id=1",
                vec![],
            ))
            .await?
            .ok_or_else(|| HistoryError::Integrity("schema 24 identity is missing".into()))?;
        if meta.try_get::<i64>("", "schema_version")? != 24
            || meta.try_get::<String>("", "thread_id")? != thread_id
        {
            return Err(HistoryError::Integrity(
                "expected this Thread's schema 24 source".into(),
            ));
        }
        Ok(Self {
            inner: Arc::new(V24Inner { connection, tx }),
        })
    }
    pub async fn originals_page(&self, after: u64, max_rows: u32) -> Result<Vec<V24Original>> {
        if !(1..=128).contains(&max_rows) {
            return Err(HistoryError::InvalidDemand(
                "legacy page must contain 1..128 rows".into(),
            ));
        }
        let rows = self.inner.tx.query_all_raw(statement("SELECT seq,item_id,query_class,parent_id,length(payload) AS payload_bytes,length(metadata) AS metadata_bytes FROM conversation_items WHERE seq>? ORDER BY seq LIMIT ?", vec![db::number(after)?.into(), i64::from(max_rows).into()])).await?;
        rows.into_iter()
            .map(|row| {
                Ok(V24Original {
                    seq: u64::try_from(row.try_get::<i64>("", "seq")?)
                        .map_err(|_| HistoryError::Integrity("negative legacy sequence".into()))?,
                    item_id: row.try_get("", "item_id")?,
                    query_class: row.try_get("", "query_class")?,
                    parent_id: row.try_get("", "parent_id")?,
                    payload_bytes: u64::try_from(row.try_get::<i64>("", "payload_bytes")?)
                        .map_err(|_| {
                            HistoryError::Integrity("negative legacy payload length".into())
                        })?,
                    metadata_bytes: u64::try_from(row.try_get::<i64>("", "metadata_bytes")?)
                        .map_err(|_| {
                            HistoryError::Integrity("negative legacy metadata length".into())
                        })?,
                })
            })
            .collect()
    }
    pub async fn body(&self, body: V24Body) -> Result<V24BodyReader> {
        let length = match &body {
            V24Body::Payload { item_id } | V24Body::Metadata { item_id } => {
                let column = if matches!(body, V24Body::Payload { .. }) {
                    "payload"
                } else {
                    "metadata"
                };
                let row = self.inner.tx.query_one_raw(statement(&format!("SELECT length({column}) AS bytes FROM conversation_items WHERE item_id=?"), vec![item_id.clone().into()])).await?.ok_or_else(|| HistoryError::NotFound(item_id.clone()))?;
                u64::try_from(row.try_get::<i64>("", "bytes")?)
                    .map_err(|_| HistoryError::Integrity("negative legacy body length".into()))?
            }
            V24Body::Content {
                owner_key,
                content_key,
            } => {
                let row = self.inner.tx.query_one_raw(statement("SELECT payload FROM conversation_contents WHERE owner_key=? AND content_key=?", vec![owner_key.clone().into(), content_key.clone().into()])).await?.ok_or_else(|| HistoryError::NotFound(content_key.clone()))?;
                let manifest: serde_json::Value =
                    serde_json::from_slice(&row.try_get::<Vec<u8>>("", "payload")?)?;
                manifest
                    .get("byteLength")
                    .and_then(serde_json::Value::as_u64)
                    .ok_or_else(|| HistoryError::Integrity("invalid legacy body manifest".into()))?
            }
        };
        Ok(V24BodyReader {
            source: self.clone(),
            body,
            length,
        })
    }
    pub async fn close(self) -> Result<()> {
        let inner = Arc::try_unwrap(self.inner)
            .map_err(|_| HistoryError::Conflict("legacy body readers are still open".into()))?;
        inner.tx.rollback().await?;
        inner.connection.close().await?;
        Ok(())
    }
}
impl HistoryBodySource for V24BodyReader {
    fn byte_length(&self) -> u64 {
        self.length
    }
    async fn read(&self, offset: u64, max_bytes: u32) -> Result<Vec<u8>> {
        if max_bytes == 0 || max_bytes as usize > BODY_CHUNK_BYTES || offset > self.length {
            return Err(HistoryError::InvalidDemand(
                "invalid legacy body range".into(),
            ));
        }
        let length = (self.length - offset).min(max_bytes as u64);
        if length == 0 {
            return Ok(Vec::new());
        }
        match &self.body {
            V24Body::Payload { item_id } | V24Body::Metadata { item_id } => {
                let column = if matches!(self.body, V24Body::Payload { .. }) {
                    "payload"
                } else {
                    "metadata"
                };
                let row = self.source.inner.tx.query_one_raw(statement(&format!("SELECT substr({column},?,?) AS bytes FROM conversation_items WHERE item_id=?"), vec![db::number(offset + 1)?.into(), db::number(length)?.into(), item_id.clone().into()])).await?.ok_or_else(|| HistoryError::NotFound(item_id.clone()))?;
                Ok(row.try_get("", "bytes")?)
            }
            V24Body::Content {
                owner_key,
                content_key,
            } => {
                let first = offset / BODY_CHUNK_BYTES as u64 * BODY_CHUNK_BYTES as u64;
                let last =
                    (offset + length - 1) / BODY_CHUNK_BYTES as u64 * BODY_CHUNK_BYTES as u64;
                let rows = self.source.inner.tx.query_all_raw(statement("SELECT byte_offset,data FROM conversation_content_chunks WHERE owner_key=? AND content_key=? AND byte_offset BETWEEN ? AND ? ORDER BY byte_offset", vec![owner_key.clone().into(), content_key.clone().into(), db::number(first)?.into(), db::number(last)?.into()])).await?;
                if rows.len() as u64 != (last - first) / BODY_CHUNK_BYTES as u64 + 1 {
                    return Err(HistoryError::Integrity(
                        "legacy body chunk is missing".into(),
                    ));
                }
                let mut result = Vec::with_capacity(length as usize);
                for (index, row) in rows.into_iter().enumerate() {
                    let start = first + index as u64 * BODY_CHUNK_BYTES as u64;
                    let bytes: Vec<u8> = row.try_get("", "data")?;
                    if row.try_get::<i64>("", "byte_offset")? != db::number(start)?
                        || bytes.len() as u64 != (self.length - start).min(BODY_CHUNK_BYTES as u64)
                    {
                        return Err(HistoryError::Integrity(
                            "invalid legacy chunk layout".into(),
                        ));
                    }
                    let low = offset.saturating_sub(start) as usize;
                    let high = (offset + length - start).min(bytes.len() as u64) as usize;
                    result.extend_from_slice(&bytes[low..high]);
                }
                Ok(result)
            }
        }
    }
}

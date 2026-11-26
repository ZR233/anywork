//! Bounded schema-24 conversion primitives. Production replacement, backups and current extraction
//! remain at the explicit upgrade boundary in issue #470.

use super::{
    db::{self, statement},
    *,
};
use sea_orm::QueryResult;
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
pub struct HistoryImport<'a, C: ConnectionTrait> {
    connection: &'a C,
    database_id: String,
    sequence: u64,
}
impl<'a, C: ConnectionTrait> HistoryImport<'a, C> {
    pub async fn new(connection: &'a C, database_id: String) -> Result<Self> {
        let row = connection
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
        let row = connection
            .query_one_raw(statement(
                "SELECT COALESCE(MAX(seq),0) AS seq FROM history_events",
                vec![],
            ))
            .await?
            .ok_or_else(|| HistoryError::Integrity("import sequence is missing".into()))?;
        let sequence = u64::try_from(row.try_get::<i64>("", "seq")?)
            .map_err(|_| HistoryError::Integrity("negative import sequence".into()))?;
        Ok(Self {
            connection,
            database_id,
            sequence,
        })
    }
    pub async fn copy_body(
        &mut self,
        body: HistoryImportBody,
        source: &impl HistoryBodySource,
    ) -> Result<HistoryEventBodyRef> {
        let runtime_uuid = uuid::Uuid::parse_str(&body.body_id)
            .ok()
            .filter(|uuid| uuid.get_version_num() == 4);
        let legacy_digest = body
            .body_id
            .strip_prefix("legacy:v24:body:")
            .filter(|digest| crate::studio::paths::is_sha256_hex(digest));
        if (runtime_uuid.is_none() && legacy_digest.is_none())
            || body.owner_event_id.is_empty()
            || body.body_key.is_empty()
        {
            return Err(HistoryError::InvalidEvent(
                "invalid import body identity; runtime IDs remain UUIDv4".into(),
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
        db::insert_body_header(self.connection, &metadata).await?;
        let mut verify = Sha256::new();
        let mut offset = 0u64;
        let mut chunk = 0i64;
        while offset < source.byte_length() {
            let bytes = source_window(source, offset).await?;
            verify.update(&bytes);
            offset += bytes.len() as u64;
            self.connection
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
    pub(in crate::history) async fn insert_event(
        &mut self,
        mut event: super::upgrade::HistoryEventV25,
    ) -> Result<u64> {
        if !event.bodies.is_empty() || event.header.seq != 0 {
            return Err(HistoryError::InvalidEvent(
                "streamed import accepts unnumbered metadata only".into(),
            ));
        }
        let mut header_check = event.clone();
        header_check.payload_body_id = None;
        header_check.header.original = None;
        super::upgrade::validate_v25_event(&header_check)?;
        if self
            .connection
            .query_one_raw(statement(
                "SELECT 1 FROM history_events WHERE event_id=? LIMIT 1",
                vec![event.header.event_id.clone().into()],
            ))
            .await?
            .is_some()
        {
            return Err(HistoryError::Conflict(event.header.event_id));
        }
        if let Some(payload) = &event.payload_body_id {
            let body = db::body(self.connection, payload)
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
                Some(
                    super::upgrade::HistoryRowHeadV25::Single(head)
                    | super::upgrade::HistoryRowHeadV25::Member(head),
                ) => head.clone(),
                _ => {
                    let bodies =
                        db::bodies(self.connection, &event.header.event_id, None, 512).await?;
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
                    let read_len = u32::try_from(metadata.length).map_err(|_| {
                        HistoryError::InvalidEvent(
                            "canonical import metadata length overflow".into(),
                        )
                    })?;
                    serde_json::from_slice::<super::upgrade::HistoryEntityHeadV25>(
                        &db::window(self.connection, &metadata, 0, read_len).await?,
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
        super::upgrade::insert_v25_event(self.connection, &event).await?;
        Ok(self.sequence)
    }
    pub async fn validate_body_reference(&self, reference: &HistoryEventBodyRef) -> Result<()> {
        let body = db::body(self.connection, &reference.body_id)
            .await?
            .ok_or_else(|| HistoryError::Integrity("typed reference body is missing".into()))?;
        if reference.database_id != self.database_id
            || body.owner != reference.owner_event_id
            || body.key != reference.body_key
            || reference.byte_start != 0
            || reference
                .byte_start
                .checked_add(reference.byte_length)
                .is_none_or(|end| end > body.length)
        {
            return Err(HistoryError::Integrity(
                "typed reference differs from its imported body".into(),
            ));
        }
        Ok(())
    }
    pub async fn finish(self) -> Result<()> {
        if !self
            .connection
            .query_all_raw(statement("PRAGMA foreign_key_check", vec![]))
            .await?
            .is_empty()
        {
            return Err(HistoryError::Integrity(
                "import has unresolved body ownership".into(),
            ));
        }
        if self.connection.query_one_raw(statement("SELECT row_key FROM history_events AS e WHERE row_key IS NOT NULL AND NOT EXISTS(SELECT 1 FROM history_events AS a WHERE a.row_key=e.row_key AND a.is_anchor=1) LIMIT 1", vec![])).await?.is_some() { return Err(HistoryError::Integrity("import row has no anchor".into())); }
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
pub struct V24ColumnReader {
    source: V24HistorySource,
    table: &'static str,
    key_columns: &'static [&'static str],
    key_values: Vec<String>,
    column: &'static str,
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
        let rows = self.inner.tx.query_all_raw(statement("SELECT seq,item_id,query_class,parent_id FROM conversation_items WHERE seq>? ORDER BY seq LIMIT ?", vec![db::number(after)?.into(), i64::from(max_rows).into()])).await?;
        rows.into_iter()
            .map(|row| {
                Ok(V24Original {
                    seq: u64::try_from(row.try_get::<i64>("", "seq")?)
                        .map_err(|_| HistoryError::Integrity("negative legacy sequence".into()))?,
                    item_id: row.try_get("", "item_id")?,
                    query_class: row.try_get("", "query_class")?,
                    parent_id: row.try_get("", "parent_id")?,
                })
            })
            .collect()
    }
    pub(super) async fn query_one(
        &self,
        sql: &str,
        values: Vec<sea_orm::Value>,
    ) -> Result<Option<QueryResult>> {
        Ok(self.inner.tx.query_one_raw(statement(sql, values)).await?)
    }
    pub(super) async fn query_all(
        &self,
        sql: &str,
        values: Vec<sea_orm::Value>,
    ) -> Result<Vec<QueryResult>> {
        Ok(self.inner.tx.query_all_raw(statement(sql, values)).await?)
    }
    /// Migration-only strict checkpoint/context decoder. It deliberately mirrors the schema-24
    /// read checks without making the retired recovery table part of schema 25.
    pub(crate) async fn checkpoint(
        &self,
        thread_id: &str,
    ) -> Result<Option<Box<crate::studio::storage::legacy_checkpoint::ThreadCheckpoint>>> {
        use crate::studio::storage::legacy_checkpoint::ThreadCheckpoint;
        use pl_core::context::content_hash;
        let Some(row) = self
            .query_one(
                "SELECT revision,context_revision,context_count,payload,payload_hash FROM session_checkpoint WHERE id=1",
                Vec::new(),
            )
            .await?
        else {
            let orphan = self
                .query_one("SELECT 1 FROM current_context LIMIT 1", Vec::new())
                .await?;
            if orphan.is_some() {
                return Err(HistoryError::Integrity(
                    "schema 24 has context without a checkpoint".into(),
                ));
            }
            return Ok(None);
        };
        let payload: String = row.try_get("", "payload")?;
        if content_hash(payload.as_bytes()) != row.try_get::<String>("", "payload_hash")? {
            return Err(HistoryError::Integrity(
                "schema 24 checkpoint hash mismatch".into(),
            ));
        }
        let mut checkpoint: Box<ThreadCheckpoint> = serde_json::from_str(&payload)?;
        let fence = self
            .query_one(
                "SELECT applied_write_seq FROM history_meta WHERE id=1",
                Vec::new(),
            )
            .await?
            .ok_or_else(|| HistoryError::Integrity("schema 24 fence is missing".into()))?
            .try_get::<i64>("", "applied_write_seq")?;
        let count = usize::try_from(row.try_get::<i64>("", "context_count")?)
            .map_err(|_| HistoryError::Integrity("negative context count".into()))?;
        if checkpoint.thread_id != thread_id
            || checkpoint.schema_version != ThreadCheckpoint::SCHEMA_VERSION
            || !checkpoint.state.context.records.is_empty()
            || checkpoint.state_revision != checkpoint.state.commit_sequence
            || db::number(checkpoint.state_revision)? != row.try_get::<i64>("", "revision")?
            || db::number(checkpoint.state.context.revision)?
                != row.try_get::<i64>("", "context_revision")?
            || db::number(checkpoint.history_fence)? != fence
        {
            return Err(HistoryError::Integrity(
                "schema 24 checkpoint identity, fence or context mismatch".into(),
            ));
        }
        let rows = self
            .query_all(
                "SELECT ordinal,record_id,payload,payload_hash FROM current_context ORDER BY ordinal",
                Vec::new(),
            )
            .await?;
        if rows.len() != count {
            return Err(HistoryError::Integrity(
                "schema 24 context count mismatch".into(),
            ));
        }
        let mut records = Vec::with_capacity(count);
        for (ordinal, row) in rows.into_iter().enumerate() {
            let context_payload: String = row.try_get("", "payload")?;
            if db::number(ordinal as u64)? != row.try_get::<i64>("", "ordinal")?
                || content_hash(context_payload.as_bytes())
                    != row.try_get::<String>("", "payload_hash")?
            {
                return Err(HistoryError::Integrity(
                    "schema 24 context order or hash mismatch".into(),
                ));
            }
            let record: pl_core::context::ContextRecord = serde_json::from_str(&context_payload)?;
            if record.id != row.try_get::<String>("", "record_id")? {
                return Err(HistoryError::Integrity(
                    "schema 24 context identity mismatch".into(),
                ));
            }
            records.push(record);
        }
        checkpoint.state.context.records = records.into();
        Ok(Some(checkpoint))
    }
    pub(super) async fn column_body(
        &self,
        table: &'static str,
        key_columns: &'static [&'static str],
        key_values: Vec<String>,
        column: &'static str,
    ) -> Result<V24ColumnReader> {
        if key_columns.len() != key_values.len()
            || !matches!(
                table,
                "execution_lifecycle"
                    | "history_turns"
                    | "conversation_sources"
                    | "history_tool_tasks"
                    | "history_input_identities"
                    | "history_message_identities"
                    | "history_fact_receipts"
                    | "session_costs"
                    | "session_checkpoint"
                    | "conversation_items"
            )
            || !matches!(column, "payload" | "task_payload" | "delivery_payload")
        {
            return Err(HistoryError::InvalidDemand(
                "unsupported legacy column body".into(),
            ));
        }
        let predicates = key_columns
            .iter()
            .enumerate()
            .map(|(index, column)| format!("{column}=?{}", index + 1))
            .collect::<Vec<_>>()
            .join(" AND ");
        let sql = format!(
            "SELECT length(CAST({column} AS BLOB)) AS bytes FROM {table} WHERE {predicates}"
        );
        let values = key_values
            .iter()
            .map(|value| value.as_str().into())
            .collect();
        let row = self
            .query_one(&sql, values)
            .await?
            .ok_or_else(|| HistoryError::NotFound(format!("{table} body")))?;
        let length = u64::try_from(row.try_get::<i64>("", "bytes")?)
            .map_err(|_| HistoryError::Integrity("negative legacy column length".into()))?;
        Ok(V24ColumnReader {
            source: self.clone(),
            table,
            key_columns,
            key_values,
            column,
            length,
        })
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
impl HistoryBodySource for V24ColumnReader {
    fn byte_length(&self) -> u64 {
        self.length
    }
    async fn read(&self, offset: u64, max_bytes: u32) -> Result<Vec<u8>> {
        if max_bytes == 0 || max_bytes as usize > BODY_CHUNK_BYTES || offset > self.length {
            return Err(HistoryError::InvalidDemand(
                "invalid legacy column range".into(),
            ));
        }
        let length = (self.length - offset).min(max_bytes as u64);
        if length == 0 {
            return Ok(Vec::new());
        }
        let predicates = self
            .key_columns
            .iter()
            .map(|column| format!("{column}=?"))
            .collect::<Vec<_>>()
            .join(" AND ");
        let mut values = Vec::with_capacity(self.key_values.len() + 2);
        values.push(db::number(offset + 1)?.into());
        values.push(db::number(length)?.into());
        for key in &self.key_values {
            values.push(key.as_str().into());
        }
        let sql = format!(
            "SELECT substr(CAST({column} AS BLOB),?,?) AS bytes FROM {table} WHERE {predicates}",
            column = self.column,
            table = self.table
        );
        let row = self
            .source
            .query_one(&sql, values)
            .await?
            .ok_or_else(|| HistoryError::NotFound(format!("{} body", self.table)))?;
        Ok(row.try_get("", "bytes")?)
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
                let start = offset;
                let end = offset + length;
                // Schema 24 chunks need not share schema 25's 64 KiB boundaries. Read only the
                // overlapping slice from each chunk and verify that those slices are contiguous.
                let rows = self
                    .source
                    .inner
                    .tx
                    .query_all_raw(statement(
                        "SELECT byte_offset,substr(data,max(1,?-byte_offset+1),?) AS data \
                         FROM conversation_content_chunks \
                         WHERE owner_key=? AND content_key=? AND byte_offset<? \
                           AND byte_offset+length(data)>? ORDER BY byte_offset",
                        vec![
                            db::number(start)?.into(),
                            db::number(length)?.into(),
                            owner_key.clone().into(),
                            content_key.clone().into(),
                            db::number(end)?.into(),
                            db::number(start)?.into(),
                        ],
                    ))
                    .await?;
                let mut result = Vec::with_capacity(length as usize);
                let mut cursor = start;
                for row in rows {
                    let chunk_start = u64::try_from(row.try_get::<i64>("", "byte_offset")?)
                        .map_err(|_| {
                            HistoryError::Integrity("negative legacy chunk offset".into())
                        })?;
                    let bytes: Vec<u8> = row.try_get("", "data")?;
                    if chunk_start > cursor {
                        return Err(HistoryError::Integrity(
                            "legacy body chunk contains a gap".into(),
                        ));
                    }
                    let data_start = chunk_start.max(start);
                    let low = cursor.saturating_sub(data_start) as usize;
                    let high = (end - data_start).min(bytes.len() as u64) as usize;
                    if high <= low {
                        continue;
                    }
                    result.extend_from_slice(&bytes[low..high]);
                    cursor += (high - low) as u64;
                    if cursor >= end {
                        break;
                    }
                }
                if cursor < end {
                    return Err(HistoryError::Integrity(
                        "legacy body chunk is missing".into(),
                    ));
                }
                Ok(result)
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sea_orm::{Database, DatabaseBackend, Statement, TransactionTrait};

    async fn test_sqlite(path: &std::path::Path) -> Result<sea_orm::DatabaseConnection> {
        let mut options = sea_orm::ConnectOptions::new("sqlite:");
        let buf = path.to_path_buf();
        options.map_sqlx_sqlite_opts(move |opts| {
            opts.filename(&buf)
                .foreign_keys(true)
                .create_if_missing(true)
        });
        Ok(Database::connect(options).await?)
    }

    #[tokio::test]
    async fn streaming_conversion_copies_v24_original_bytes_without_activating_or_mutating_source()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let source_path = temp.path().join("v24.sqlite");
        let target_path = temp.path().join("v25.sqlite");

        let source_db = test_sqlite(&source_path).await?;
        source_db
            .execute_unprepared(
                "CREATE TABLE history_meta(id INTEGER PRIMARY KEY,schema_version INTEGER,thread_id TEXT);\
                 INSERT INTO history_meta VALUES(1,24,'import');\
                 CREATE TABLE conversation_items(seq INTEGER PRIMARY KEY,item_id TEXT UNIQUE,query_class TEXT,parent_id TEXT,payload BLOB,metadata BLOB);",
            )
            .await?;
        let payload = b"preserved binary original".repeat(7000);
        source_db
            .execute_raw(Statement::from_sql_and_values(
                DatabaseBackend::Sqlite,
                "INSERT INTO conversation_items VALUES(7,'original','conversation',NULL,?,?)",
                vec![
                    payload.clone().into(),
                    b"typed legacy metadata".to_vec().into(),
                ],
            ))
            .await?;
        source_db.close().await?;
        let source_before = std::fs::read(&source_path)?;

        let database_id = uuid::Uuid::new_v4().to_string();
        let target_db = test_sqlite(&target_path).await?;
        target_db
            .execute_unprepared(include_str!("upgrade/schema_v25.sql"))
            .await?;
        target_db
            .execute_unprepared(
                "CREATE TABLE IF NOT EXISTS seaql_migrations (version TEXT PRIMARY KEY NOT NULL, applied_at INTEGER NOT NULL);",
            )
            .await?;
        target_db
            .execute_raw(Statement::from_sql_and_values(
                DatabaseBackend::Sqlite,
                "INSERT INTO seaql_migrations(version, applied_at) VALUES(?, 1)",
                vec![super::super::schema::MIGRATION_V25.into()],
            ))
            .await?;
        target_db
            .execute_raw(Statement::from_sql_and_values(
                DatabaseBackend::Sqlite,
                "INSERT INTO history_store_meta(singleton,schema_version,database_id,thread_id) VALUES(1,25,?,'import')",
                vec![database_id.clone().into()],
            ))
            .await?;

        let tx = target_db.begin().await?;
        let mut importer = HistoryImport::new(&tx, database_id).await?;
        let source = V24HistorySource::open(&source_path, "import").await?;
        let originals = source.originals_page(0, 128).await?;
        assert_eq!(originals.len(), 1);
        let body = source
            .body(V24Body::Payload {
                item_id: "original".into(),
            })
            .await?;
        let reference = importer
            .copy_body(
                HistoryImportBody {
                    body_id: uuid::Uuid::new_v4().to_string(),
                    owner_event_id: "original".into(),
                    ordinal: 0,
                    body_key: "body".into(),
                    role: HistoryBodyRole::Body,
                    media_type: None,
                },
                &body,
            )
            .await?;
        let event = super::super::upgrade::HistoryEventV25::new(
            "original",
            super::super::upgrade::HistoryEventKindV25::LegacyObserved,
            0,
        );
        importer.insert_event(event).await?;
        importer.finish().await?;
        tx.commit().await?;
        target_db.close().await?;
        drop(body);
        source.close().await?;
        assert_eq!(std::fs::read(&source_path)?, source_before);

        let report =
            super::super::upgrade::upgrade_history(&target_path, "import", temp.path()).await?;
        assert_eq!(
            report.status,
            super::super::upgrade::UpgradeStatus::Upgraded
        );
        let reopened = HistoryStore::open(&target_path, "import", HistoryLimits::default()).await?;
        let reader = reopened.reader();
        let event_rec = reader
            .read_event("original".into(), HistoryDemand::default())
            .await?;
        assert_eq!(event_rec.payload_schema, "anywork.business/1");
        let env: super::body::BusinessFactEnvelope = serde_json::from_str(&event_rec.payload_json)?;
        assert_eq!(env.bodies.len(), 1);
        let upgraded_ref = env.bodies[0]
            .reference
            .clone()
            .expect("large streamed v24 body remains external BLOB");
        assert_eq!(upgraded_ref.body_id, reference.body_id);
        reader.verify_body(upgraded_ref.clone()).await?;
        let mut actual = Vec::new();
        while actual.len() < payload.len() {
            actual.extend(
                reader
                    .read_body(upgraded_ref.clone(), actual.len() as u64, 65_536)
                    .await?
                    .bytes,
            );
        }
        assert_eq!(actual, payload);
        reader.close().await;
        reopened.close().await?;
        Ok(())
    }
}

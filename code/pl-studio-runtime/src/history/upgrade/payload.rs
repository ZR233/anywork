//! SQLite JSON1 rewriting for frozen schema-24 producer envelopes.
//!
//! Product JSON remains in SQLite while migration rewrites only producer-declared body
//! references. Body plans and inline bytes are likewise staged in temporary SQLite tables so a
//! large manifest is never accumulated in Rust.

use super::{
    BODY_CHUNK_BYTES, ContentRef, ContentTarget, HistoryBodyRole, HistoryBodySource, HistoryError,
    HistoryEventBodyRef, HistoryImport, HistoryImportBody, Result, V24Body, V24BodyReader,
    V24HistorySource,
    db::{self, statement},
    deterministic_body_id, legacy_content_role, plan_identity, validate_typed_reference,
};
use crate::PayloadData;
use sea_orm::ConnectionTrait;
const DECLARATION_PAGE: i64 = 128;

struct BodyDeclaration {
    key: String,
    byte_length: u64,
    reference: Option<ContentRef>,
    inline_kind: Option<String>,
}

pub(super) async fn create_staging<C: ConnectionTrait>(connection: &C) -> Result<()> {
    for sql in [
        "DROP TABLE IF EXISTS legacy_payload_rewrite",
        "DROP TABLE IF EXISTS legacy_body_plans",
        "DROP TABLE IF EXISTS legacy_inline_body_chunks",
        "CREATE TEMP TABLE legacy_payload_rewrite(payload BLOB NOT NULL)",
        "CREATE TEMP TABLE legacy_body_plans(\
           source_ref TEXT PRIMARY KEY,owner_event_id TEXT NOT NULL,body_key TEXT NOT NULL,\
           role TEXT NOT NULL,source_kind TEXT NOT NULL,byte_length INTEGER NOT NULL,\
           media_type TEXT,copied INTEGER NOT NULL DEFAULT 0,ordinal INTEGER,\
           UNIQUE(owner_event_id,body_key),\
           CHECK(source_kind IN ('content','inline'))\
         )",
        "CREATE TEMP TABLE legacy_inline_body_chunks(\
           source_ref TEXT NOT NULL,chunk_no INTEGER NOT NULL,data BLOB NOT NULL,\
           PRIMARY KEY(source_ref,chunk_no)\
         )",
    ] {
        connection.execute_raw(statement(sql, Vec::new())).await?;
    }
    Ok(())
}

pub(super) async fn drop_staging<C: ConnectionTrait>(connection: &C) -> Result<()> {
    for sql in [
        "DROP TABLE IF EXISTS legacy_payload_rewrite",
        "DROP TABLE IF EXISTS legacy_body_plans",
        "DROP TABLE IF EXISTS legacy_inline_body_chunks",
    ] {
        connection.execute_raw(statement(sql, Vec::new())).await?;
    }
    Ok(())
}

async fn clear_payload<C: ConnectionTrait>(connection: &C) -> Result<()> {
    connection
        .execute_raw(statement("DELETE FROM legacy_payload_rewrite", Vec::new()))
        .await?;
    Ok(())
}

pub(super) struct StagedPayload<'a, C: ConnectionTrait> {
    connection: &'a C,
    length: u64,
}

impl<'a, C: ConnectionTrait> StagedPayload<'a, C> {
    pub(super) async fn from_item(connection: &'a C, item_id: &str) -> Result<Self> {
        clear_payload(connection).await?;
        connection
            .execute_raw(statement(
                "INSERT INTO legacy_payload_rewrite(payload) \
                 SELECT CAST(payload AS BLOB) FROM conversation_items WHERE item_id=?",
                vec![item_id.to_owned().into()],
            ))
            .await?;
        Self::new(connection).await
    }

    pub(super) async fn from_body(
        connection: &'a C,
        source: &V24HistorySource,
        body: V24Body,
    ) -> Result<Self> {
        clear_payload(connection).await?;
        connection
            .execute_raw(statement(
                "INSERT INTO legacy_payload_rewrite(payload) VALUES(X'')",
                Vec::new(),
            ))
            .await?;
        let reader = source.body(body).await?;
        let mut offset = 0u64;
        while offset < reader.byte_length() {
            let length = (reader.byte_length() - offset).min(BODY_CHUNK_BYTES as u64) as u32;
            let bytes = reader.read(offset, length).await?;
            connection
                .execute_raw(statement(
                    "UPDATE legacy_payload_rewrite \
                     SET payload=CAST(payload AS BLOB)||CAST(? AS BLOB)",
                    vec![bytes.clone().into()],
                ))
                .await?;
            offset += bytes.len() as u64;
        }
        Self::new(connection).await
    }

    async fn new(connection: &'a C) -> Result<Self> {
        let row = connection
            .query_one_raw(statement(
                "SELECT length(CAST(payload AS BLOB)) AS bytes FROM legacy_payload_rewrite",
                Vec::new(),
            ))
            .await?
            .ok_or_else(|| HistoryError::Integrity("payload staging is empty".into()))?;
        let length = u64::try_from(row.try_get::<i64>("", "bytes")?)
            .map_err(|_| HistoryError::Integrity("negative staged payload length".into()))?;
        Ok(Self { connection, length })
    }

    pub(super) async fn rewrite_declarations(
        &mut self,
        source: &V24HistorySource,
        database_id: &str,
        owner_event_id: &str,
        source_order: Option<u64>,
    ) -> Result<()> {
        self.validate_envelope().await?;
        self.connection
            .execute_raw(statement("DELETE FROM legacy_body_plans", Vec::new()))
            .await?;
        self.connection
            .execute_raw(statement(
                "DELETE FROM legacy_inline_body_chunks",
                Vec::new(),
            ))
            .await?;
        let mut after = -1i64;
        loop {
            let rows = self
                .connection
                .query_all_raw(statement(
                    "SELECT CAST(je.key AS INTEGER) AS ordinal,\
                            json_extract(je.value,'$.key') AS body_key,\
                            json_extract(je.value,'$.byteLength') AS byte_length,\
                            CASE WHEN json_type(je.value,'$.reference')='object' \
                                 THEN json_extract(je.value,'$.reference') END AS reference,\
                            json_type(je.value,'$.inline') AS inline_kind \
                     FROM legacy_payload_rewrite,json_each(\
                         CAST(legacy_payload_rewrite.payload AS TEXT),'$.bodies'\
                     ) AS je \
                     WHERE CAST(je.key AS INTEGER)>? ORDER BY je.key LIMIT ?",
                    vec![after.into(), DECLARATION_PAGE.into()],
                ))
                .await?;
            if rows.is_empty() {
                break;
            }
            for row in &rows {
                after = row.try_get::<i64>("", "ordinal")?;
                let reference = row
                    .try_get::<Option<String>>("", "reference")?
                    .map(|value| serde_json::from_str::<ContentRef>(&value))
                    .transpose()?;
                let declaration = BodyDeclaration {
                    key: row.try_get("", "body_key")?,
                    byte_length: row
                        .try_get::<i64>("", "byte_length")?
                        .try_into()
                        .map_err(|_| HistoryError::Integrity("negative body length".into()))?,
                    reference,
                    inline_kind: row.try_get("", "inline_kind")?,
                };
                let plan = self
                    .plan_declaration(source, declaration, database_id, owner_event_id, after)
                    .await?;
                self.replace_declaration(after, &plan, database_id).await?;
            }
            if (rows.len() as i64) < DECLARATION_PAGE {
                break;
            }
        }
        let values = match source_order {
            Some(order) => vec![1i64.into(), db::number(order)?.into()],
            None => vec![0i64.into(), 0i64.into()],
        };
        self.connection
            .execute_raw(statement(
                "UPDATE legacy_payload_rewrite \
                 SET payload=CASE WHEN ?1 THEN json_set(payload,'$.sourceOrder',?2) \
                                  ELSE json_remove(payload,'$.sourceOrder') END",
                values,
            ))
            .await?;
        self.length = Self::new(self.connection).await?.length;
        Ok(())
    }

    async fn validate_envelope(&self) -> Result<()> {
        let row = self
            .connection
            .query_one_raw(statement(
                "SELECT json_extract(CAST(payload AS TEXT),'$.contract') AS contract,\
                        json_type(CAST(payload AS TEXT),'$.bodies') AS bodies \
                 FROM legacy_payload_rewrite",
                Vec::new(),
            ))
            .await?
            .ok_or_else(|| HistoryError::Integrity("payload staging is empty".into()))?;
        if row.try_get::<String>("", "contract")? != "anywork.chat/1"
            || row.try_get::<String>("", "bodies")? != "array"
        {
            return Err(HistoryError::Integrity(
                "unsupported schema 24 producer payload envelope".into(),
            ));
        }
        Ok(())
    }

    async fn plan_declaration(
        &self,
        source: &V24HistorySource,
        declaration: BodyDeclaration,
        database_id: &str,
        owner_event_id: &str,
        ordinal: i64,
    ) -> Result<HistoryEventBodyRef> {
        if declaration.key.is_empty() {
            return Err(HistoryError::Integrity(
                "schema 24 producer body key is empty".into(),
            ));
        }
        let source_ref = match (declaration.reference, declaration.inline_kind) {
            (Some(reference), None) => {
                validate_typed_reference(&reference, database_id)?;
                let (owner, body_key, role) = plan_identity(&reference.target, owner_event_id)?;
                let reader = content_reader(source, &reference).await?;
                if declaration.byte_length != reader.byte_length() {
                    return Err(HistoryError::Integrity(
                        "schema 24 declaration length differs from its durable body".into(),
                    ));
                }
                let media_type = content_media_type(source, &reference.target).await?;
                self.insert_content_plan(
                    &reference,
                    owner,
                    body_key,
                    role,
                    declaration.byte_length,
                    media_type,
                )
                .await?
            }
            (None, Some(kind)) if kind == "array" => {
                let source_ref = format!("inline:{owner_event_id}:{}", declaration.key);
                let actual = self.stage_inline(ordinal, &source_ref).await?;
                if actual != declaration.byte_length {
                    return Err(HistoryError::Integrity(
                        "schema 24 inline declaration length differs from its bytes".into(),
                    ));
                }
                let body_key = format!("legacy-content:{}", declaration.key);
                let role = legacy_content_role(&declaration.key);
                self.insert_inline_plan(&source_ref, owner_event_id, body_key, role, actual)
                    .await?;
                source_ref
            }
            _ => {
                return Err(HistoryError::Integrity(
                    "schema 24 producer body must declare exactly one material".into(),
                ));
            }
        };
        self.plan_reference(database_id, &source_ref).await
    }

    async fn stage_inline(&self, ordinal: i64, source_ref: &str) -> Result<u64> {
        let path = format!("$.bodies[{ordinal}].inline");
        let mut after = -1i64;
        let mut total = 0u64;
        let mut chunk = Vec::with_capacity(BODY_CHUNK_BYTES);
        loop {
            let rows = self
                .connection
                .query_all_raw(statement(
                    &format!(
                        "SELECT CAST(je.key AS INTEGER) AS position,je.value \
                         FROM legacy_payload_rewrite,json_each(\
                             CAST(legacy_payload_rewrite.payload AS TEXT),'{path}'\
                         ) AS je WHERE CAST(je.key AS INTEGER)>? ORDER BY je.key LIMIT ?"
                    ),
                    vec![after.into(), (BODY_CHUNK_BYTES as i64).into()],
                ))
                .await?;
            if rows.is_empty() {
                break;
            }
            for row in rows {
                after = row.try_get::<i64>("", "position")?;
                let value = row.try_get::<i64>("", "value")?;
                let byte = u8::try_from(value)
                    .map_err(|_| HistoryError::Integrity("inline body byte is invalid".into()))?;
                let chunk_no = total / BODY_CHUNK_BYTES as u64;
                chunk.push(byte);
                total += 1;
                if chunk.len() == BODY_CHUNK_BYTES {
                    self.insert_inline_chunk(source_ref, chunk_no, &chunk)
                        .await?;
                    chunk.clear();
                }
            }
        }
        if !chunk.is_empty() {
            let chunk_no = total / BODY_CHUNK_BYTES as u64;
            self.insert_inline_chunk(source_ref, chunk_no, &chunk)
                .await?;
        }
        Ok(total)
    }

    async fn insert_inline_chunk(
        &self,
        source_ref: &str,
        chunk_no: u64,
        bytes: &[u8],
    ) -> Result<()> {
        self.connection
            .execute_raw(statement(
                "INSERT INTO legacy_inline_body_chunks(source_ref,chunk_no,data) VALUES(?,?,?)",
                vec![
                    source_ref.into(),
                    db::number(chunk_no)?.into(),
                    bytes.to_vec().into(),
                ],
            ))
            .await?;
        Ok(())
    }

    async fn insert_content_plan(
        &self,
        reference: &ContentRef,
        owner_event_id: String,
        body_key: String,
        role: HistoryBodyRole,
        byte_length: u64,
        media_type: Option<String>,
    ) -> Result<String> {
        let source_ref = serde_json::to_string(reference)?;
        self.connection
            .execute_raw(statement(
                "INSERT OR IGNORE INTO legacy_body_plans(\
                     source_ref,owner_event_id,body_key,role,source_kind,byte_length,media_type\
                 ) VALUES(?,?,?,?, 'content',?,?)",
                vec![
                    source_ref.clone().into(),
                    owner_event_id.into(),
                    body_key.into(),
                    role.as_str().into(),
                    db::number(byte_length)?.into(),
                    media_type.into(),
                ],
            ))
            .await?;
        Ok(source_ref)
    }

    async fn insert_inline_plan(
        &self,
        source_ref: &str,
        owner_event_id: &str,
        body_key: String,
        role: HistoryBodyRole,
        byte_length: u64,
    ) -> Result<()> {
        self.connection
            .execute_raw(statement(
                "INSERT INTO legacy_body_plans(\
                     source_ref,owner_event_id,body_key,role,source_kind,byte_length\
                 ) VALUES(?,?,?,?,'inline',?)",
                vec![
                    source_ref.into(),
                    owner_event_id.into(),
                    body_key.into(),
                    role.as_str().into(),
                    db::number(byte_length)?.into(),
                ],
            ))
            .await?;
        Ok(())
    }

    async fn plan_reference(
        &self,
        database_id: &str,
        source_ref: &str,
    ) -> Result<HistoryEventBodyRef> {
        let row = self
            .connection
            .query_one_raw(statement(
                "SELECT owner_event_id,body_key,byte_length FROM legacy_body_plans \
                 WHERE source_ref=?",
                vec![source_ref.into()],
            ))
            .await?
            .ok_or_else(|| HistoryError::Integrity("body plan vanished".into()))?;
        Ok(HistoryEventBodyRef {
            database_id: database_id.to_owned(),
            owner_event_id: row.try_get("", "owner_event_id")?,
            body_key: row.try_get("", "body_key")?,
            body_id: deterministic_body_id(
                &row.try_get::<String>("", "owner_event_id")?,
                &row.try_get::<String>("", "body_key")?,
            ),
            byte_start: 0,
            byte_length: db_u64(row.try_get::<i64>("", "byte_length")?),
        })
    }

    async fn replace_declaration(
        &self,
        ordinal: i64,
        plan: &HistoryEventBodyRef,
        database_id: &str,
    ) -> Result<()> {
        if database_id != plan.database_id {
            return Err(HistoryError::Integrity("body plan database differs".into()));
        }
        let path = format!("$.bodies[{ordinal}]");
        self.connection
            .execute_raw(statement(
                &format!(
                    "UPDATE legacy_payload_rewrite \
                     SET payload=json_set(json_remove(CAST(payload AS TEXT),'{path}.inline'),\
                         '{path}.reference',json(?1),'{path}.byteLength',CAST(?2 AS INTEGER))"
                ),
                vec![
                    serde_json::to_string(plan)?.into(),
                    db::number(plan.byte_length)?.into(),
                ],
            ))
            .await?;
        Ok(())
    }
}

impl<C: ConnectionTrait> HistoryBodySource for StagedPayload<'_, C> {
    fn byte_length(&self) -> u64 {
        self.length
    }

    async fn read(&self, offset: u64, max_bytes: u32) -> Result<Vec<u8>> {
        if max_bytes == 0 || max_bytes as usize > BODY_CHUNK_BYTES || offset > self.length {
            return Err(HistoryError::InvalidDemand(
                "invalid staged payload range".into(),
            ));
        }
        let length = (self.length - offset).min(max_bytes as u64);
        if length == 0 {
            return Ok(Vec::new());
        }
        let row = self
            .connection
            .query_one_raw(statement(
                "SELECT substr(CAST(payload AS BLOB),?,?) AS bytes \
                 FROM legacy_payload_rewrite",
                vec![db::number(offset + 1)?.into(), db::number(length)?.into()],
            ))
            .await?
            .ok_or_else(|| HistoryError::Integrity("payload staging is empty".into()))?;
        Ok(row.try_get("", "bytes")?)
    }
}

struct InlineBodySource<'a, C: ConnectionTrait> {
    connection: &'a C,
    source_ref: String,
    length: u64,
}

impl<C: ConnectionTrait> HistoryBodySource for InlineBodySource<'_, C> {
    fn byte_length(&self) -> u64 {
        self.length
    }

    async fn read(&self, offset: u64, max_bytes: u32) -> Result<Vec<u8>> {
        let end = offset
            .checked_add(max_bytes as u64)
            .filter(|end| *end <= self.length)
            .ok_or_else(|| HistoryError::InvalidDemand("invalid inline body range".into()))?;
        let rows = self
            .connection
            .query_all_raw(statement(
                "SELECT chunk_no*?1 AS chunk_offset,data FROM legacy_inline_body_chunks \
                 WHERE source_ref=?2 AND chunk_no*?1<?3 AND (chunk_no+1)*?1>?4 \
                 ORDER BY chunk_no",
                vec![
                    db::number(BODY_CHUNK_BYTES as u64)?.into(),
                    self.source_ref.clone().into(),
                    db::number(end)?.into(),
                    db::number(offset)?.into(),
                ],
            ))
            .await?;
        let mut result = Vec::with_capacity((end - offset) as usize);
        let mut cursor = offset;
        for row in rows {
            let chunk_offset = db_u64(row.try_get::<i64>("", "chunk_offset")?);
            let bytes: Vec<u8> = row.try_get("", "data")?;
            let low = cursor.saturating_sub(chunk_offset) as usize;
            let high = (end - chunk_offset).min(bytes.len() as u64) as usize;
            if high <= low {
                continue;
            }
            result.extend_from_slice(&bytes[low..high]);
            cursor += (high - low) as u64;
        }
        if cursor != end {
            return Err(HistoryError::Integrity("inline body chunk gap".into()));
        }
        Ok(result)
    }
}

pub(super) async fn copy_planned_bodies<C: ConnectionTrait>(
    connection: &C,
    import: &mut HistoryImport<'_, C>,
    source: &V24HistorySource,
) -> Result<()> {
    loop {
        let rows = connection
            .query_all_raw(statement(
                "SELECT source_ref,owner_event_id,body_key,role,source_kind,byte_length,media_type \
                 FROM legacy_body_plans WHERE copied=0 \
                 ORDER BY owner_event_id,body_key LIMIT 128",
                Vec::new(),
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            let source_ref: String = row.try_get("", "source_ref")?;
            let owner_event_id: String = row.try_get("", "owner_event_id")?;
            let body_key: String = row.try_get("", "body_key")?;
            let role = HistoryBodyRole::from_string(row.try_get("", "role")?);
            let source_kind: String = row.try_get("", "source_kind")?;
            let byte_length = db_u64(row.try_get::<i64>("", "byte_length")?);
            let media_type: Option<String> = row.try_get("", "media_type")?;
            let ordinal = next_body_ordinal(connection, &owner_event_id).await?;
            connection
                .execute_raw(statement(
                    "UPDATE legacy_body_plans SET ordinal=? WHERE source_ref=?",
                    vec![db::number(ordinal)?.into(), source_ref.clone().into()],
                ))
                .await?;
            let body_id = deterministic_body_id(&owner_event_id, &body_key);
            if source_kind == "content" {
                let reference: ContentRef = serde_json::from_str(&source_ref)?;
                if matches!(reference.target, ContentTarget::ItemPayload { .. }) {
                    connection
                        .execute_raw(statement(
                            "UPDATE legacy_body_plans SET copied=1 WHERE source_ref=?",
                            vec![source_ref.into()],
                        ))
                        .await?;
                    continue;
                }
                let reader = content_reader(source, &reference).await?;
                import
                    .copy_body(
                        HistoryImportBody {
                            body_id,
                            owner_event_id,
                            ordinal,
                            body_key,
                            role,
                            media_type,
                        },
                        &reader,
                    )
                    .await?;
            } else {
                let inline = InlineBodySource {
                    connection,
                    source_ref: source_ref.clone(),
                    length: byte_length,
                };
                import
                    .copy_body(
                        HistoryImportBody {
                            body_id,
                            owner_event_id,
                            ordinal,
                            body_key,
                            role,
                            media_type,
                        },
                        &inline,
                    )
                    .await?;
            }
            connection
                .execute_raw(statement(
                    "UPDATE legacy_body_plans SET copied=1 WHERE source_ref=?",
                    vec![source_ref.into()],
                ))
                .await?;
        }
    }
    Ok(())
}

pub(super) async fn plan_content_reference<C: ConnectionTrait>(
    connection: &C,
    source: &V24HistorySource,
    database_id: &str,
    owner_event_id: &str,
    reference: &ContentRef,
) -> Result<()> {
    validate_typed_reference(reference, database_id)?;
    let (owner, body_key, role) = plan_identity(&reference.target, owner_event_id)?;
    let reader = content_reader(source, reference).await?;
    StagedPayload::new(connection)
        .await?
        .insert_content_plan(
            reference,
            owner,
            body_key,
            role,
            reader.byte_length(),
            content_media_type(source, &reference.target).await?,
        )
        .await?;
    Ok(())
}

pub(super) async fn render_rewritten_atom<C: ConnectionTrait>(
    connection: &C,
    atom: &super::ChatAtom,
    database_id: &str,
    fallback_owner: &str,
) -> Result<serde_json::Value> {
    let mut value = serde_json::to_value(atom)?;
    for (index, content) in atom.contents.iter().enumerate() {
        let plan =
            reference_plan(connection, &content.reference, database_id, fallback_owner).await?;
        *value
            .get_mut("contents")
            .and_then(serde_json::Value::as_array_mut)
            .and_then(|contents| contents.get_mut(index))
            .and_then(|content| content.get_mut("reference"))
            .ok_or_else(|| {
                HistoryError::Integrity("typed atom content reference path is missing".into())
            })? = serde_json::to_value(plan)?;
    }
    if let Some(PayloadData::Deferred { reference, .. }) = &atom.payload {
        let plan = reference_plan(connection, reference, database_id, fallback_owner).await?;
        let payload = value
            .get_mut("payload")
            .and_then(serde_json::Value::as_object_mut)
            .ok_or_else(|| {
                HistoryError::Integrity("typed atom deferred payload is missing".into())
            })?;
        payload.insert("reference".into(), serde_json::to_value(&plan)?);
        payload.insert("byteLength".into(), plan.byte_length.into());
    }
    Ok(value)
}

pub(super) async fn reference_plan<C: ConnectionTrait>(
    connection: &C,
    reference: &ContentRef,
    database_id: &str,
    fallback_owner: &str,
) -> Result<HistoryEventBodyRef> {
    validate_typed_reference(reference, database_id)?;
    let source_ref = serde_json::to_string(reference)?;
    // An inline producer declaration and its typed metadata name the same
    // owner/key with different source encodings. Resolve that shared identity
    // before bytes are copied; do not require a second copy of the body.
    let (owner_event_id, body_key, _) = plan_identity(&reference.target, fallback_owner)?;
    let row = connection
        .query_one_raw(statement(
            "SELECT owner_event_id,body_key,byte_length FROM legacy_body_plans \
             WHERE source_ref=? OR (owner_event_id=? AND body_key=?)",
            vec![source_ref.into(), owner_event_id.into(), body_key.into()],
        ))
        .await?
        .ok_or_else(|| {
            HistoryError::Integrity("typed atom reference has no imported body plan".into())
        })?;
    let owner_event_id: String = row.try_get("", "owner_event_id")?;
    let body_key: String = row.try_get("", "body_key")?;
    let body_id = deterministic_body_id(&owner_event_id, &body_key);
    Ok(HistoryEventBodyRef {
        database_id: database_id.to_owned(),
        owner_event_id,
        body_key,
        body_id,
        byte_start: 0,
        byte_length: db_u64(row.try_get::<i64>("", "byte_length")?),
    })
}

async fn next_body_ordinal<C: ConnectionTrait>(
    connection: &C,
    owner_event_id: &str,
) -> Result<u64> {
    let row = connection
        .query_one_raw(statement(
            "SELECT COALESCE(MAX(ordinal),-1)+1 AS ordinal FROM (
                 SELECT ordinal FROM history_bodies WHERE owner_event_id=? AND ordinal IS NOT NULL
                 UNION ALL
                 SELECT ordinal FROM legacy_body_plans
                 WHERE owner_event_id=? AND copied=1 AND ordinal IS NOT NULL
             )",
            vec![owner_event_id.into(), owner_event_id.into()],
        ))
        .await?
        .ok_or_else(|| HistoryError::Integrity("body ordinal query failed".into()))?;
    u64::try_from(row.try_get::<i64>("", "ordinal")?)
        .map_err(|_| HistoryError::Integrity("history body ordinal is negative".into()))
}

async fn content_reader(
    source: &V24HistorySource,
    reference: &ContentRef,
) -> Result<V24BodyReader> {
    source
        .body(match reference.target.clone() {
            ContentTarget::ItemPayload { item_id } => V24Body::Payload { item_id },
            ContentTarget::Body { owner, key } => {
                let owner_key = crate::studio::conversation_identity::content_owner_key(&owner)
                    .map_err(|error| HistoryError::Storage(error.into()))?;
                V24Body::Content {
                    owner_key: owner_key.as_str().to_owned(),
                    content_key: key,
                }
            }
        })
        .await
}

async fn content_media_type(
    source: &V24HistorySource,
    target: &ContentTarget,
) -> Result<Option<String>> {
    let ContentTarget::Body { owner, key } = target else {
        return Ok(None);
    };
    let owner_key = crate::studio::conversation_identity::content_owner_key(owner)
        .map_err(|error| HistoryError::Storage(error.into()))?;
    let row = source
        .query_one(
            "SELECT json_extract(CAST(payload AS TEXT),'$.mediaType') AS media_type \
             FROM conversation_contents WHERE owner_key=? AND content_key=?",
            vec![owner_key.as_str().into(), key.into()],
        )
        .await?
        .ok_or_else(|| HistoryError::NotFound(key.clone()))?;
    Ok(row.try_get("", "media_type")?)
}

fn db_u64(value: i64) -> u64 {
    u64::try_from(value).unwrap_or_default()
}

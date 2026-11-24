//! 已完成正式迁移的只读残余证据导出；正常执行恢复不解码这些旧记录。
use super::schema::v24_presentation_types::LegacyExecutionEvidence;
use super::*;
use crate::{ContentRange, ContentWindow};
use pl_core::chat::ChatError;

impl HistoryStore {
    pub(in crate::studio) async fn legacy_evidence_heads(
        &self,
        after: Option<(&str, u64)>,
        limit: usize,
    ) -> Result<Vec<LegacyExecutionEvidence>> {
        ensure!(
            (1..=4096).contains(&limit),
            "legacy evidence page limit is invalid"
        );
        let Some(connection) = self.reader().await? else {
            return Ok(Vec::new());
        };
        let (id, revision) = after.unwrap_or(("", 0));
        connection.db.query_all_raw(statement(
            "SELECT item_id,revision,json_extract(payload,'$.recordId') AS record_id,
             json_extract(payload,'$.kind') AS original_kind,json_extract(payload,'$.sourceSchema') AS source_schema,
             json_extract(payload,'$.sourceTable') AS source_table,json_extract(payload,'$.sourceRow') AS source_row,
             json_extract(payload,'$.byteLength') AS byte_length,json_extract(payload,'$.rawDigest') AS raw_digest
             FROM history_fact_receipts WHERE kind='legacy_execution_record' AND (item_id,revision)>(?,?)
             ORDER BY item_id,revision LIMIT ?",
            vec![id.into(),integer(revision)?.into(),integer(limit)?.into()],
        )).await?.into_iter().map(|row| Ok(LegacyExecutionEvidence {
            evidence_id: row.try_get("","item_id")?,record_id: row.try_get("","record_id")?,
            revision: u64::try_from(row.try_get::<i64>("","revision")?)?,kind: row.try_get("","original_kind")?,
            source_schema: u32::try_from(row.try_get::<i64>("","source_schema")?)?,
            source_table:row.try_get("","source_table")?,source_row:serde_json::from_str(&row.try_get::<String>("","source_row")?)?,
            byte_length: u64::try_from(row.try_get::<i64>("","byte_length")?)?,raw_digest: row.try_get("","raw_digest")?,
        })).collect()
    }

    pub(in crate::studio) async fn read_legacy_evidence(
        &self,
        id: &str,
        revision: u64,
        range: ContentRange,
    ) -> Result<ContentWindow> {
        let Some(connection) = self.reader().await? else {
            anyhow::bail!(ChatError::NotFound(id.into()))
        };
        let row = connection.db.query_one_raw(statement(
            "SELECT json_extract(payload,'$.byteLength') AS byte_length,json_extract(payload,'$.rawDigest') AS raw_digest,
             json_extract(payload,'$.originalOwner') AS original_owner,json_extract(payload,'$.originalKey') AS original_key
             FROM history_fact_receipts WHERE item_id=? AND revision=? AND kind='legacy_execution_record'",
            vec![id.into(),integer(revision)?.into()],
        )).await?.context(ChatError::NotFound(id.into()))?;
        let length = u64::try_from(row.try_get::<i64>("", "byte_length")?)?;
        let key = pl_core::chat::ChatContentKey {
            owner: pl_core::chat::ChatKey::from_encoded(
                row.try_get::<String>("", "original_owner")?,
            )?,
            key: row.try_get("", "original_key")?,
        };
        let manifest_row = connection
            .db
            .query_one_raw(statement(
                "SELECT payload FROM conversation_contents WHERE owner_key=? AND content_key=?",
                vec![key.owner.as_str().into(), key.key.clone().into()],
            ))
            .await?
            .context(ChatError::NotFound(key.key.clone()))?;
        let manifest =
            conversation::content::manifest(&manifest_row.try_get::<Vec<u8>>("", "payload")?)?;
        ensure!(
            manifest.sealed && manifest.byte_length == length,
            "legacy original content manifest differs from its receipt"
        );
        let remaining = length
            .checked_sub(range.offset)
            .context("legacy evidence offset exceeds its receipt")?;
        let take = (range.max_bytes as u64).min(remaining);
        ensure!(take > 0, "legacy evidence range is empty");
        let bytes = conversation::content::read_body_bytes(
            &connection.db,
            &key,
            range.offset,
            usize::try_from(take)?,
        )
        .await?;
        Ok(ContentWindow {
            offset: range.offset,
            bytes,
            generation: row.try_get("", "raw_digest")?,
            available_through: length,
            sealed: true,
        })
    }
}

use super::*;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SendRecordStatus {
    Succeeded,
    Partial,
    Rejected,
    Unknown,
}

impl SendRecordStatus {
    fn as_str(self) -> &'static str {
        match self {
            Self::Succeeded => "succeeded",
            Self::Partial => "partial",
            Self::Rejected => "rejected",
            Self::Unknown => "unknown",
        }
    }

    /// 显式接受 `unknown`；其它未知串属于坏持久记录，不能当合法 Unknown 走重放。
    fn parse(value: &str) -> Result<Self, FeishuError> {
        match value {
            "succeeded" => Ok(Self::Succeeded),
            "partial" => Ok(Self::Partial),
            "rejected" => Ok(Self::Rejected),
            "unknown" => Ok(Self::Unknown),
            _ => Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "send record state is unreadable; local recovery required",
                false,
                None,
            )),
        }
    }
}

#[derive(Debug, Clone)]
pub struct SendRecord {
    pub operation_id: String,
    pub bot_id: String,
    pub chat_id: String,
    pub content_hash: String,
    pub status: SendRecordStatus,
    pub platform_message_ids: Vec<String>,
    pub segments: Vec<SendSegmentFact>,
    pub facts_complete: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SendSegmentFact {
    pub index: u32,
    pub uuid: String,
    pub status: SendRecordStatus,
    pub platform_message_id: Option<String>,
    pub diagnostic: Option<String>,
    /// Added in the current JSON facts encoding. Missing on preserved text records.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub file_delivery: Option<crate::bots::files::FileDeliveryFact>,
}

impl BotStateStore {
    /// 只读发送记录：首次认领的权威判定在准入内用它区分“首次”与“已持久同操作”。
    pub(crate) async fn load_send(
        &self,
        operation_id: &str,
    ) -> Result<Option<SendRecord>, FeishuError> {
        let db = self.db().await?;
        let row = db
            .query_one_raw(statement(
                "SELECT operation_id, bot_id, chat_id, content_hash, status, platform_message_ids, segment_facts
                 FROM send_operations WHERE operation_id=?",
                vec![operation_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        let Some(row) = row else {
            return Ok(None);
        };
        Ok(Some(send_record_from_row(row)?))
    }

    /// 该操作是否已有持久记录：只读存在性，不解码整条事实、不跨后续等待保留材料。
    pub(crate) async fn send_exists(&self, operation_id: &str) -> Result<bool, FeishuError> {
        let db = self.db().await?;
        let row = db
            .query_one_raw(statement(
                "SELECT 1 AS present FROM send_operations WHERE operation_id=?",
                vec![operation_id.to_string().into()],
            ))
            .await
            .map_err(storage)?;
        Ok(row.is_some())
    }

    pub async fn claim_send(&self, record: &SendRecord) -> Result<Option<SendRecord>, FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let existing = tx
            .query_one_raw(statement(
                "SELECT operation_id, bot_id, chat_id, content_hash, status, platform_message_ids, segment_facts
                 FROM send_operations WHERE operation_id=?",
                vec![record.operation_id.clone().into()],
            ))
            .await
            .map_err(storage)?;
        if let Some(row) = existing {
            // 先提交只读事务再解码：既有结果的长事实不与本次 initial 同时跨提交等待。
            tx.commit().await.map_err(storage)?;
            let existing = send_record_from_row(row)?;
            return conflict_or_existing(record, existing).map(Some);
        }
        let inserted = tx
            .execute_raw(statement(
                "INSERT OR IGNORE INTO send_operations(operation_id, bot_id, chat_id, content_hash, status, platform_message_ids, segment_facts, updated_at)
                 VALUES(?,?,?,?,?,?,?,?)",
                vec![
                    record.operation_id.clone().into(),
                    record.bot_id.clone().into(),
                    record.chat_id.clone().into(),
                    record.content_hash.clone().into(),
                    record.status.as_str().to_string().into(),
                    record.platform_message_ids.join(",").into(),
                    encode_segment_facts(&record.segments)?.into(),
                    unix_seconds().into(),
                ],
            ))
            .await
            .map_err(storage)?;
        if inserted.rows_affected() == 1 {
            tx.commit().await.map_err(storage)?;
            return Ok(None);
        }
        let Some(row) = tx
            .query_one_raw(statement(
                "SELECT operation_id, bot_id, chat_id, content_hash, status, platform_message_ids, segment_facts
                 FROM send_operations WHERE operation_id=?",
                vec![record.operation_id.clone().into()],
            ))
            .await
            .map_err(storage)?
        else {
            tx.commit().await.map_err(storage)?;
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "send operation claim raced without a persisted record",
                true,
                None,
            ));
        };
        // 同理：提交完成后再解码已存事实，避免长材料跨提交等待。
        tx.commit().await.map_err(storage)?;
        let existing = send_record_from_row(row)?;
        conflict_or_existing(record, existing).map(Some)
    }

    /// 身份核对与 upsert 必须共享同一事务快照，否则两次调用之间可能被另一写者
    /// 插入或覆盖（TOCTOU）。WAL 下若快照已被其他写者推进，升级为写会以
    /// `SQLITE_BUSY_SNAPSHOT` 失败而不是基于过期读取静默覆盖；busy_timeout 只
    /// 覆盖真实的锁等待。编码在事务外完成，事务内只保留一次读取与一次写入。
    pub async fn save_send(&self, record: &SendRecord) -> Result<(), FeishuError> {
        let segment_facts = encode_segment_facts(&record.segments)?;
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        if let Some(row) = tx
            .query_one_raw(statement(
                "SELECT operation_id, bot_id, chat_id, content_hash, status, platform_message_ids, segment_facts
                 FROM send_operations WHERE operation_id=?",
                vec![record.operation_id.clone().into()],
            ))
            .await
            .map_err(storage)?
        {
            conflict_or_existing(record, send_record_from_row(row)?)?;
        }
        tx.execute_raw(statement(
            "INSERT INTO send_operations(operation_id, bot_id, chat_id, content_hash, status, platform_message_ids, segment_facts, updated_at)
             VALUES(?,?,?,?,?,?,?,?)
             ON CONFLICT(operation_id) DO UPDATE SET
               status=excluded.status,
               platform_message_ids=excluded.platform_message_ids,
               segment_facts=excluded.segment_facts,
               updated_at=excluded.updated_at",
            vec![
                record.operation_id.clone().into(),
                record.bot_id.clone().into(),
                record.chat_id.clone().into(),
                record.content_hash.clone().into(),
                record.status.as_str().to_string().into(),
                record.platform_message_ids.join(",").into(),
                segment_facts.into(),
                unix_seconds().into(),
            ],
        ))
        .await
        .map_err(storage)?;
        tx.commit().await.map_err(storage)?;
        Ok(())
    }
}

fn encode_segment_facts(segments: &[SendSegmentFact]) -> Result<String, FeishuError> {
    serde_json::to_string(segments).map_err(|error| {
        FeishuError::new(
            FeishuErrorKind::Unavailable,
            format!("failed to persist send segment facts: {error}"),
            true,
            None,
        )
    })
}

/// 分段事实 JSON 参数的 UTF-8 长度（与持久化编码同一实现），供占用冻结计权使用。
pub(crate) fn segment_facts_bytes(segments: &[SendSegmentFact]) -> Result<usize, FeishuError> {
    Ok(encode_segment_facts(segments)?.len())
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub(super) struct ImportedSegments {
    pub(super) legacy_segments: Vec<SendSegmentFact>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum StoredSegmentFacts {
    Complete(Vec<SendSegmentFact>),
    Imported(ImportedSegments),
}

fn decode_segment_facts(raw: &str) -> Result<(Vec<SendSegmentFact>, bool), FeishuError> {
    let facts = serde_json::from_str(raw).map_err(|error| {
        FeishuError::new(
            FeishuErrorKind::Unavailable,
            format!("stored send segment facts are unreadable: {error}"),
            false,
            None,
        )
    })?;
    Ok(match facts {
        StoredSegmentFacts::Complete(facts) => (facts, true),
        StoredSegmentFacts::Imported(facts) => (facts.legacy_segments, false),
    })
}

pub(super) fn platform_message_ids(raw: &str) -> Vec<String> {
    if raw.is_empty() {
        Vec::new()
    } else {
        raw.split(',').map(str::to_string).collect()
    }
}

fn send_record_from_row(row: sea_orm::QueryResult) -> Result<SendRecord, FeishuError> {
    let ids = platform_message_ids(&stored_text(&row, "platform_message_ids")?);
    let facts_raw = stored_text(&row, "segment_facts")?;
    let status = SendRecordStatus::parse(&stored_text(&row, "status")?)?;
    let (segments, facts_complete) = decode_segment_facts(&facts_raw)?;
    Ok(SendRecord {
        operation_id: stored_text(&row, "operation_id")?,
        bot_id: stored_text(&row, "bot_id")?,
        chat_id: stored_text(&row, "chat_id")?,
        content_hash: stored_text(&row, "content_hash")?,
        status,
        platform_message_ids: ids,
        segments,
        facts_complete,
    })
}

fn conflict_or_existing(
    record: &SendRecord,
    existing: SendRecord,
) -> Result<SendRecord, FeishuError> {
    verify_send_identity(
        &existing,
        &record.operation_id,
        &record.bot_id,
        &record.chat_id,
        &record.content_hash,
    )?;
    Ok(existing)
}

/// 已持久发送记录与本次请求的严格身份核验：相同 operationId 只能是同一机器人、
/// 同一会话与同一正文。只读本地指纹，不涉及联网或凭据。
pub(crate) fn verify_send_identity(
    existing: &SendRecord,
    operation_id: &str,
    bot_id: &str,
    chat_id: &str,
    content_hash: &str,
) -> Result<(), FeishuError> {
    if existing.operation_id == operation_id
        && existing.bot_id == bot_id
        && existing.chat_id == chat_id
        && existing.content_hash == content_hash
    {
        return Ok(());
    }
    Err(FeishuError::new(
        FeishuErrorKind::Conflict,
        "operationId already used with different content",
        false,
        None,
    ))
}

#[cfg(test)]
mod tests;

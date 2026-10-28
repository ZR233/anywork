//! Saturated counters probe each matching fact of the **single current ledger**, never a sample.
//! Legacy observations, cards and unfinished inputs are counted after migration only through their
//! current `LegacyFinal` obligations, so old and new facts are never added twice.

use super::unreadable;
use crate::bots::protocol::error::FeishuError;
use crate::bots::storage::{BotStateStore, statement, storage, strict_watermark};
use sea_orm::ConnectionTrait;

const CAP: u64 = pl_protocol::BOT_DELIVERY_SUMMARY_COUNT_LIMIT as u64;
const UNEXPECTED_WORK: &str = "SELECT 1 FROM inbound_work w
 WHERE (w.status IS NULL OR w.status NOT IN ('pending','claimed','failed','needs_attention','completed'))
   AND (w.creation_id=?1 OR w.chat_id=?2) LIMIT 1";

/// 九号索引：迁移来源仍按原声明校验与安装，当前结构不再要求。
pub(super) const INDEXES: &[(&str, &str)] = &[
    (
        "bot_delivery_pending_count",
        "CREATE INDEX bot_delivery_pending_count ON bot_delivery_items(thread_id) WHERE json_extract(state_json,'$.pending')=1",
    ),
    (
        "bot_delivery_incomplete_count",
        "CREATE INDEX bot_delivery_incomplete_count ON bot_delivery_items(thread_id) WHERE json_extract(state_json,'$.incomplete')=1",
    ),
    (
        "bot_delivery_unknown_card_count",
        "CREATE INDEX bot_delivery_unknown_card_count ON bot_delivery_items(thread_id) WHERE json_extract(state_json,'$.ledger.platform.kind')='card' AND json_extract(state_json,'$.ledger.platform.latestOperation.result.kind')='unknown'",
    ),
    (
        "bot_delivery_unknown_upload_count",
        "CREATE INDEX bot_delivery_unknown_upload_count ON bot_delivery_items(thread_id) WHERE json_extract(state_json,'$.ledger.platform.kind')='file' AND json_extract(state_json,'$.ledger.platform.upload.kind')='unknown'",
    ),
    (
        "bot_delivery_unknown_message_count",
        "CREATE INDEX bot_delivery_unknown_message_count ON bot_delivery_items(thread_id) WHERE json_extract(state_json,'$.ledger.platform.kind')='file' AND json_extract(state_json,'$.ledger.platform.message.kind')='unknown'",
    ),
    (
        "bot_legacy_unfinished_count",
        "CREATE INDEX bot_legacy_unfinished_count ON bot_card_streams(thread_id,identity) WHERE json_extract(state_json,'$.lifecycle') NOT IN ('completed','cancelled','failed','budgetLimited','interactionEnded','noFinalReply')",
    ),
    (
        "bot_legacy_unknown_count",
        "CREATE INDEX bot_legacy_unknown_count ON bot_card_streams(thread_id) WHERE json_extract(state_json,'$.lastOperation.status')='unknown'",
    ),
    (
        "bot_legacy_attention_count",
        "CREATE INDEX bot_legacy_attention_count ON bot_card_streams(thread_id) WHERE json_extract(state_json,'$.lifecycle')='needsAttention' OR json_extract(state_json,'$.lastOperation.status')='intent'",
    ),
    (
        "bot_origin_creation_lookup",
        "CREATE INDEX bot_origin_creation_lookup ON bot_audience_origins(creation_id)",
    ),
    (
        "bot_binding_creation_lookup",
        "CREATE INDEX bot_binding_creation_lookup ON binding_operations(creation_id)",
    ),
    (
        "bot_legacy_work_scope",
        "CREATE INDEX bot_legacy_work_scope ON inbound_work(status,chat_id,creation_id)",
    ),
    (
        "bot_legacy_unreadable_work",
        "CREATE INDEX bot_legacy_unreadable_work ON inbound_work(chat_id,creation_id) WHERE status IS NULL OR status NOT IN ('pending','claimed','failed','needs_attention','completed')",
    ),
    (
        "bot_legacy_identity_scope",
        "CREATE INDEX bot_legacy_identity_scope ON inbound_identities(chat_id,identity)",
    ),
];

/// 当前（十号）结构仍使用的差异索引：不引用已重整的实体账本旧列，也不引用退役卡片表。
pub(super) const CURRENT_INDEXES: &[(&str, &str)] = &[
    (
        "bot_origin_creation_lookup",
        "CREATE INDEX bot_origin_creation_lookup ON bot_audience_origins(creation_id)",
    ),
    (
        "bot_binding_creation_lookup",
        "CREATE INDEX bot_binding_creation_lookup ON binding_operations(creation_id)",
    ),
    (
        "bot_legacy_work_scope",
        "CREATE INDEX bot_legacy_work_scope ON inbound_work(status,chat_id,creation_id)",
    ),
    (
        "bot_legacy_unreadable_work",
        "CREATE INDEX bot_legacy_unreadable_work ON inbound_work(chat_id,creation_id) WHERE status IS NULL OR status NOT IN ('pending','claimed','failed','needs_attention','completed')",
    ),
    (
        "bot_legacy_identity_scope",
        "CREATE INDEX bot_legacy_identity_scope ON inbound_identities(chat_id,identity)",
    ),
];

/// 九号 open：只安装该边界仍存在的次级索引；必需结构与约束不在普通打开时补建。
pub(in crate::bots::storage) async fn prepare_indexes<C: ConnectionTrait>(
    db: &C,
) -> anyhow::Result<()> {
    install(
        db,
        INDEXES
            .iter()
            .copied()
            .chain(super::proof::INDEXES.iter().copied())
            .chain(super::proof::INHERITED_INDEXES.iter().copied()),
    )
    .await
}

/// 十号 open：安装当前结构仍需要的次级索引（幂等，不改写既有声明）。
pub(in crate::bots::storage) async fn prepare_current_indexes<C: ConnectionTrait>(
    db: &C,
) -> anyhow::Result<()> {
    install(
        db,
        CURRENT_INDEXES
            .iter()
            .copied()
            .chain(super::proof::CURRENT_INDEXES.iter().copied())
            .chain(super::proof::INHERITED_INDEXES.iter().copied()),
    )
    .await
}

async fn install<C: ConnectionTrait>(
    db: &C,
    indexes: impl Iterator<Item = (&'static str, &'static str)>,
) -> anyhow::Result<()> {
    for (name, ddl) in indexes {
        if db
            .query_one_raw(statement(
                "SELECT name FROM sqlite_schema WHERE name=?",
                vec![name.into()],
            ))
            .await?
            .is_none()
        {
            db.execute_unprepared(ddl).await?;
        }
    }
    Ok(())
}

async fn count<C: ConnectionTrait>(db: &C, select: &str, thread: &str) -> Result<u64, FeishuError> {
    let row = db
        .query_one_raw(statement(
            &format!("SELECT COUNT(*) AS n FROM ({select} LIMIT 16385)"),
            vec![thread.into()],
        ))
        .await
        .map_err(storage)?
        .ok_or_else(unreadable)?;
    strict_watermark(&row, "n")
}

/// 未知工作状态与缺少工作行的身份仍是恢复义务：它们没有可投影的当前作用域，摘要必须
/// 明确不可用，而不是给出“零未完成”。未知状态工作本身已在迁移时进入当前 `LegacyFinal`。
async fn require_legacy_coverage<C: ConnectionTrait>(
    db: &C,
    thread: &str,
) -> Result<(), FeishuError> {
    let origin = super::read::read_origin(db, thread)
        .await?
        .ok_or_else(unreadable)?;
    let orphan = db
        .query_one_raw(statement(
            "SELECT 1 FROM inbound_identities i WHERE (i.chat_id=?1 OR i.chat_id IS NULL OR i.chat_id='')
             AND NOT EXISTS(SELECT 1 FROM inbound_work w WHERE w.identity=i.identity) LIMIT 1",
            vec![origin.chat_id.into()],
        ))
        .await
        .map_err(storage)?;
    if orphan.is_some() {
        return Err(unreadable());
    }
    Ok(())
}

/// 未知状态工作行仍必须让旧有限摘要显示需处理，不能被当成“没有未完成”。
async fn unexpected_work<C: ConnectionTrait>(db: &C, thread: &str) -> Result<bool, FeishuError> {
    let origin = super::read::read_origin(db, thread)
        .await?
        .ok_or_else(unreadable)?;
    Ok(db
        .query_one_raw(statement(
            UNEXPECTED_WORK,
            vec![origin.creation_id.into(), origin.chat_id.into()],
        ))
        .await
        .map_err(storage)?
        .is_some())
}

impl BotStateStore {
    pub(in crate::bots) async fn audience_counts(
        &self,
        thread: &str,
        version: u64,
    ) -> Result<
        (
            pl_protocol::BotDeliverySummary,
            pl_protocol::BotLegacyFinalSummary,
        ),
        FeishuError,
    > {
        let db = self.audience_db()?;
        require_legacy_coverage(db, thread).await?;
        let pending = count(
            db,
            "SELECT 1 FROM bot_delivery_items i
               JOIN bot_delivery_scopes s ON s.scope_key=i.scope_key
             WHERE s.thread_id=?1 AND s.kind='frontend'
               AND i.delivered=0 AND i.removed=0 AND i.incomplete=0 AND i.attention=0 AND i.unknown=0",
            thread,
        )
        .await?;
        let incomplete = count(
            db,
            "SELECT 1 FROM bot_delivery_items i
               JOIN bot_delivery_scopes s ON s.scope_key=i.scope_key
             WHERE s.thread_id=?1 AND s.kind='frontend' AND i.incomplete=1",
            thread,
        )
        .await?;
        // 一个文件实体可以保留两个不同未知 HTTP 阶段：upload 与 message 分别计数。
        let unknown = count(
            db,
            "SELECT 1 FROM bot_delivery_items i
               JOIN bot_delivery_scopes s ON s.scope_key=i.scope_key
             WHERE s.thread_id=?1 AND s.kind='frontend' AND i.unknown=1
               AND json_extract(i.state_json,'$.fileOperation.operationId') IS NULL
               AND json_extract(i.state_json,'$.content.kind')<>'unresolved'
             UNION ALL SELECT 1 FROM bot_delivery_items i
               JOIN bot_delivery_scopes s ON s.scope_key=i.scope_key
               JOIN send_operations o ON o.operation_id=json_extract(i.state_json,'$.fileOperation.operationId')
             WHERE s.thread_id=?1 AND s.kind='frontend'
               AND json_extract(o.segment_facts,'$[0].upload.kind')='unknown'
             UNION ALL SELECT 1 FROM bot_delivery_items i
               JOIN bot_delivery_scopes s ON s.scope_key=i.scope_key
               JOIN send_operations o ON o.operation_id=json_extract(i.state_json,'$.fileOperation.operationId')
             WHERE s.thread_id=?1 AND s.kind='frontend'
               AND json_extract(o.segment_facts,'$[0].messageStage')='unknown'
             UNION ALL SELECT 1 FROM bot_delivery_items i
               JOIN bot_delivery_scopes s ON s.scope_key=i.scope_key
             WHERE s.thread_id=?1 AND s.kind='frontend'
               AND json_extract(i.state_json,'$.content.unresolved.observation.platform.latestOperation.result.kind')='unknown'
             UNION ALL SELECT 1 FROM bot_delivery_items i
               JOIN bot_delivery_scopes s ON s.scope_key=i.scope_key
             WHERE s.thread_id=?1 AND s.kind='frontend'
               AND json_extract(i.state_json,'$.content.unresolved.observation.platform.upload.kind')='unknown'
             UNION ALL SELECT 1 FROM bot_delivery_items i
               JOIN bot_delivery_scopes s ON s.scope_key=i.scope_key
             WHERE s.thread_id=?1 AND s.kind='frontend'
               AND json_extract(i.state_json,'$.content.unresolved.observation.platform.message.kind')='unknown'",
            thread,
        )
        .await?;
        let chains = count(
            db,
            "SELECT 1 FROM bot_delivery_items i
               JOIN bot_delivery_scopes s ON s.scope_key=i.scope_key
             WHERE s.thread_id=?1 AND s.kind='legacyFinal'
               AND i.delivered=0 AND i.removed=0",
            thread,
        )
        .await?;
        let legacy_unknown = count(
            db,
            "SELECT 1 FROM bot_delivery_items i
               JOIN bot_delivery_scopes s ON s.scope_key=i.scope_key
             WHERE s.thread_id=?1 AND s.kind='legacyFinal' AND i.unknown=1",
            thread,
        )
        .await?;
        let attention = db
            .query_one_raw(statement(
                "SELECT 1 FROM bot_delivery_items i
                   JOIN bot_delivery_scopes s ON s.scope_key=i.scope_key
                 WHERE s.thread_id=?1 AND s.kind='legacyFinal' AND i.attention=1 LIMIT 1",
                vec![thread.into()],
            ))
            .await
            .map_err(storage)?
            .is_some();
        let needs_attention =
            attention || legacy_unknown > 0 || unexpected_work(db, thread).await?;
        Ok((
            pl_protocol::BotDeliverySummary {
                version,
                pending_items: pending.min(CAP) as u32,
                unknown_operations: unknown.min(CAP) as u32,
                incomplete_items: incomplete.min(CAP) as u32,
                counts_capped: pending > CAP || unknown > CAP || incomplete > CAP,
            },
            pl_protocol::BotLegacyFinalSummary {
                unfinished_chains: chains.min(CAP) as u32,
                unknown_operations: legacy_unknown.min(CAP) as u32,
                needs_attention,
                counts_capped: chains > CAP || legacy_unknown > CAP,
            },
        ))
    }
}

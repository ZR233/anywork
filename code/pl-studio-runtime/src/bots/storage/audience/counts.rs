//! Saturated counters probe each matching fact, never a sample of all items. The partial indexes
//! contain only body-free state/identity; no query materializes delivery or legacy card bodies.

use super::unreadable;
use crate::bots::protocol::error::FeishuError;
use crate::bots::storage::{BotStateStore, statement, storage, strict_watermark};
use sea_orm::ConnectionTrait;

const CAP: u64 = pl_protocol::BOT_DELIVERY_SUMMARY_COUNT_LIMIT as u64;
const CARD_UNFINISHED: &str = "json_extract(state_json,'$.lifecycle') NOT IN ('completed','cancelled','failed','budgetLimited','interactionEnded','noFinalReply')";
const WORK_UNFINISHED: &str = "w.status IN ('pending','claimed','failed','needs_attention')";
const WORK_UNREADABLE: &str = "w.status IS NULL OR w.status NOT IN ('pending','claimed','failed','needs_attention','completed')";
const NO_CARD: &str = "NOT EXISTS(SELECT 1 FROM bot_card_streams c WHERE c.identity=w.identity)";

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

/// Only secondary, non-unique performance indexes may be installed on an existing nine. Required
/// authority tables/keys/constraints still pass the original exact validator; none are repaired.
pub(in crate::bots::storage) async fn prepare_indexes<C: ConnectionTrait>(
    db: &C,
) -> anyhow::Result<()> {
    for (name, ddl) in INDEXES
        .iter()
        .chain(super::proof::INDEXES)
        .chain(super::proof::INHERITED_INDEXES)
    {
        if db
            .query_one_raw(statement(
                "SELECT name FROM sqlite_schema WHERE name=?",
                vec![(*name).into()],
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

/// A known zero requires coverage of recovery facts, not just the recognized unfinished states.
/// Only an immutable, non-empty creation identity can rule an unscoped row out as another chat;
/// neither the current route nor the encoded input key supplies missing historical ownership.
async fn require_legacy_coverage<C: ConnectionTrait>(
    db: &C,
    thread: &str,
) -> Result<(), FeishuError> {
    let origin = super::read::read_origin(db, thread)
        .await?
        .ok_or_else(unreadable)?;
    let unknown = db.query_one_raw(statement(&format!(
        "SELECT 1 FROM inbound_work w WHERE ({WORK_UNREADABLE}) AND (
         w.creation_id=?1 OR w.chat_id=?2 OR ((w.chat_id IS NULL OR w.chat_id='') AND (
           w.creation_id IS NULL OR w.creation_id=''
           OR NOT EXISTS(SELECT 1 FROM bot_audience_origins known WHERE known.creation_id=w.creation_id)
           OR EXISTS(SELECT 1 FROM bot_audience_origins known WHERE known.creation_id=w.creation_id AND known.chat_id=?2)))) LIMIT 1"
    ), vec![origin.creation_id.into(),origin.chat_id.clone().into()])).await.map_err(storage)?;
    if unknown.is_some() {
        return Err(unreadable());
    }
    // An identity without its work row is a recovery obligation even when no card was created.
    // Missing chat evidence is not a license to assume completion or reconstruct a Thread.
    let orphan = db.query_one_raw(statement(
        "SELECT 1 FROM inbound_identities i WHERE (i.chat_id=?1 OR i.chat_id IS NULL OR i.chat_id='')
         AND NOT EXISTS(SELECT 1 FROM inbound_work w WHERE w.identity=i.identity) LIMIT 1",
        vec![origin.chat_id.into()],
    )).await.map_err(storage)?;
    if orphan.is_some() {
        return Err(unreadable());
    }
    Ok(())
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
        let pending = count(db, "SELECT 1 FROM bot_delivery_items WHERE thread_id=?1 AND json_extract(state_json,'$.pending')=1", thread).await?;
        let incomplete = count(db, "SELECT 1 FROM bot_delivery_items WHERE thread_id=?1 AND json_extract(state_json,'$.incomplete')=1", thread).await?;
        // One item can retain two distinct unknown HTTP operations: upload and message. UNION ALL
        // deliberately counts both, while a card contributes only its latest recovery operation.
        let unknown = count(db, "SELECT 1 FROM bot_delivery_items WHERE thread_id=?1 AND json_extract(state_json,'$.ledger.platform.kind')='card' AND json_extract(state_json,'$.ledger.platform.latestOperation.result.kind')='unknown'
            UNION ALL SELECT 1 FROM bot_delivery_items WHERE thread_id=?1 AND json_extract(state_json,'$.ledger.platform.kind')='file' AND json_extract(state_json,'$.ledger.platform.upload.kind')='unknown'
            UNION ALL SELECT 1 FROM bot_delivery_items WHERE thread_id=?1 AND json_extract(state_json,'$.ledger.platform.kind')='file' AND json_extract(state_json,'$.ledger.platform.message.kind')='unknown'", thread).await?;
        let no_card = format!(
            "SELECT 1 FROM inbound_work w WHERE w.creation_id=(SELECT creation_id FROM bot_audience_origins WHERE thread_id=?1) AND {WORK_UNFINISHED} AND {NO_CARD}"
        );
        let chains = count(db, &format!("SELECT 1 FROM bot_card_streams WHERE thread_id=?1 AND {CARD_UNFINISHED} UNION ALL {no_card}"), thread).await?;
        let legacy_unknown = count(db, "SELECT 1 FROM bot_card_streams WHERE thread_id=?1 AND json_extract(state_json,'$.lastOperation.status')='unknown'", thread).await?;
        let attention = db.query_one_raw(statement(&format!(
            "SELECT 1 FROM bot_card_streams WHERE thread_id=?1 AND (json_extract(state_json,'$.lifecycle')='needsAttention' OR json_extract(state_json,'$.lastOperation.status')='intent')
             UNION ALL {no_card}
             UNION ALL SELECT 1 FROM inbound_work w WHERE {WORK_UNFINISHED}
             AND (w.chat_id='' OR w.chat_id=(SELECT chat_id FROM bot_audience_origins WHERE thread_id=?1))
             AND NOT EXISTS(SELECT 1 FROM bot_audience_origins o WHERE o.creation_id=w.creation_id)
             AND NOT EXISTS(SELECT 1 FROM binding_operations b WHERE b.creation_id=w.creation_id AND b.thread_id<>'') LIMIT 1"
        ), vec![thread.into()])).await.map_err(storage)?.is_some();
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
                needs_attention: attention || legacy_unknown > 0,
                counts_capped: chains > CAP || legacy_unknown > CAP,
            },
        ))
    }
}

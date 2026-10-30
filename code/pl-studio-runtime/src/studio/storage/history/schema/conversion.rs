//! Historical v2 data conversions, called only from the named official migrations.
use super::*;

/// The historical context-source step reads only its own frozen envelope view. Checkpoint
/// layout conversion belongs exclusively to CheckpointV5; this step never rewrites its envelope.
#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct ContextEnvelope {
    thread_id: String,
    state_revision: u64,
    history_fence: u64,
    state: ContextState,
}
#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct ContextState {
    commit_sequence: u64,
}

pub(super) async fn migrate_context_sources(
    tx: &impl ConnectionTrait,
    thread_id: &str,
) -> Result<()> {
    use pl_core::{context::content_hash, thread::ThreadCheckpoint};
    let Some(row) = tx
        .query_one_raw(statement(
            "SELECT payload,payload_hash FROM session_checkpoint WHERE id=1",
            vec![],
        ))
        .await?
    else {
        return Ok(());
    };
    let payload: String = row.try_get("", "payload")?;
    ensure!(
        content_hash(payload.as_bytes()) == row.try_get::<String>("", "payload_hash")?,
        "checkpoint migration hash mismatch"
    );
    let envelope: ContextEnvelope = serde_json::from_str(&payload)?;
    ensure!(
        envelope.thread_id == thread_id
            && envelope.state_revision == envelope.state.commit_sequence
            && envelope.history_fence <= envelope.state_revision,
        "checkpoint migration ownership mismatch"
    );
    let rows = tx
        .query_all_raw(statement(
            "SELECT ordinal,record_id,payload,payload_hash FROM current_context ORDER BY ordinal",
            vec![],
        ))
        .await?;
    let mut records = Vec::new();
    let mut originals = Vec::new();
    for (index, row) in rows.iter().enumerate() {
        ensure!(
            row.try_get::<i64>("", "ordinal")? == i64::try_from(index)?,
            "context migration ordinal mismatch"
        );
        let bytes: String = row.try_get("", "payload")?;
        ensure!(
            content_hash(bytes.as_bytes()) == row.try_get::<String>("", "payload_hash")?,
            "context migration hash mismatch"
        );
        let raw: serde_json::Value = serde_json::from_str(&bytes)?;
        let record: pl_core::context::ContextRecord = serde_json::from_value(raw.clone())?;
        ensure!(
            record.id == row.try_get::<String>("", "record_id")?,
            "context migration identity mismatch"
        );
        originals.push((raw, record.clone()));
        records.push(record);
    }
    // Reuse core's one historical source decoder, but persist only its context result. The
    // original checkpoint envelope (including its format number) belongs to CheckpointV5.
    let mut context_view: serde_json::Value = serde_json::from_str(&payload)?;
    context_view["state"]["context"]["records"] = serde_json::to_value(&records)?;
    let mut checkpoint: ThreadCheckpoint = if context_view["schemaVersion"].as_u64()
        == Some(u64::from(ThreadCheckpoint::SCHEMA_VERSION))
    {
        serde_json::from_value(context_view)?
    } else {
        ThreadCheckpoint::decode_legacy(&serde_json::to_string(&context_view)?)?
    };
    crate::compaction::migrate_checkpoint_sources(&mut checkpoint)?;
    for (index, ((mut raw, previous), current)) in originals
        .into_iter()
        .zip(checkpoint.state.context.records.iter())
        .enumerate()
    {
        if previous.source == current.source && previous.content == current.content {
            continue;
        }
        if previous.source != current.source {
            raw["source"] = serde_json::to_value(&current.source)?;
        }
        if previous.content != current.content {
            raw["content"] = serde_json::to_value(&current.content)?;
        }
        let encoded = serde_json::to_string(&raw)?;
        tx.execute_raw(statement(
            "UPDATE current_context SET payload=?,payload_hash=? WHERE ordinal=? AND record_id=?",
            vec![
                encoded.clone().into(),
                content_hash(encoded.as_bytes()).into(),
                i64::try_from(index)?.into(),
                current.id.clone().into(),
            ],
        ))
        .await?;
    }
    Ok(())
}

/// The old projection inferred input bindings from running Turns before model admission. A Turn
/// naming the input proves its identity; absence from the transactionally maintained terminal
/// ledger proves it was not consumed or discarded at this durable watermark.
pub(super) async fn migrate_unconsumed_input_bindings(db: &impl ConnectionTrait) -> Result<()> {
    let mut cursor = 0_i64;
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT i.ordinal,i.payload,t.payload AS turn_payload FROM history_items i
             JOIN history_items t ON t.turn_id=i.turn_id AND t.kind='turn'
             LEFT JOIN history_input_identities identity ON identity.item_id=i.item_id
             WHERE i.ordinal>? AND i.turn_id!='' AND i.kind!='turn' AND identity.item_id IS NULL
             ORDER BY i.ordinal LIMIT 400",
                vec![cursor.into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            cursor = row.try_get("", "ordinal")?;
            let mut item: ThreadItem =
                serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
            let turn_item: ThreadItem =
                serde_json::from_str(&row.try_get::<String>("", "turn_payload")?)?;
            let ThreadItemState::Turn(turn) = turn_item.state() else {
                continue;
            };
            if turn.input_id() != Some(item.id.as_str()) {
                continue;
            }
            let old_turn = std::mem::take(&mut item.turn_id);
            item.revision = item
                .revision
                .checked_add(1)
                .context("migrated input revision overflow")?;
            db.execute_raw(statement(
                "UPDATE history_items SET turn_id='',revision=?,payload=? WHERE item_id=?",
                vec![
                    integer(item.revision)?.into(),
                    serde_json::to_string(&item)?.into(),
                    item.id.into(),
                ],
            ))
            .await?;
            db.execute_raw(statement(
                "UPDATE history_turns SET first_ordinal=(SELECT MIN(ordinal) FROM history_items WHERE turn_id=?) WHERE turn_id=?",
                vec![old_turn.clone().into(), old_turn.into()],
            )).await?;
        }
    }
    Ok(())
}

/// Legacy v2 rows have no presentation. Only a resolved interaction receipt that names the
/// continuation and records a hidden product option proves why its timeline row is absent.
pub(super) async fn backfill_legacy_hidden_inputs(db: &impl ConnectionTrait) -> Result<()> {
    use pl_core::thread::interactions::{InteractionRecord, InteractionState};
    let mut cursor = 0_i64;
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT rowid,payload FROM history_fact_receipts \
             WHERE kind='interaction' AND rowid>? ORDER BY rowid LIMIT 100",
                vec![cursor.into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            cursor = row.try_get("", "rowid")?;
            let record: InteractionRecord =
                serde_json::from_str(&row.try_get::<String>("", "payload")?)
                    .context("legacy interaction receipt cannot be decoded")?;
            let Some(id) = record.continuation_id.as_deref() else {
                continue;
            };
            ensure!(
                id == format!("interaction:{}:continuation", record.request.id),
                "legacy interaction continuation identity conflicts with its receipt"
            );
            if !matches!(record.state, InteractionState::Resolved(_))
                || record.request.payload.version() != 1
            {
                continue;
            }
            let hidden = match record.request.payload.format() {
                "pl.tool.user-input" => true,
                crate::plan_tool::PLAN_CONFIRMATION_FORMAT => {
                    let prompt: crate::plan_tool::PlanConfirmationPrompt =
                        serde_json::from_str(record.request.payload.content())
                            .context("legacy Plan confirmation cannot be decoded")?;
                    prompt.presentation == pl_protocol::MessagePresentation::Hidden
                }
                _ => false,
            };
            if !hidden {
                continue;
            }
            let identity = db
                .query_one_raw(statement(
                    "SELECT presentation FROM history_input_identities WHERE item_id=?",
                    vec![id.to_owned().into()],
                ))
                .await?;
            let Some(identity) = identity else {
                continue;
            };
            let presentation: Option<String> = identity.try_get("", "presentation")?;
            ensure!(
                presentation
                    .as_deref()
                    .is_none_or(|value| value == "hidden"),
                "legacy hidden continuation conflicts with its input identity"
            );
            ensure!(
                db.query_one_raw(statement(
                    "SELECT item_id FROM history_items WHERE item_id=?",
                    vec![id.to_owned().into()],
                ))
                .await?
                .is_none(),
                "legacy hidden continuation has a visible timeline item"
            );
            db.execute_raw(statement(
                "UPDATE history_input_identities SET presentation='hidden' WHERE item_id=?",
                vec![id.to_owned().into()],
            ))
            .await?;
        }
    }
    Ok(())
}

/// Attaches the accepted user-input history to the tool item that raised it in already-written
/// history.
///
/// A version-7 or older database stored the questions and the answer only in the interaction fact,
/// because the timeline row was written before the tool item carried a typed projection. That covers
/// the ordinary question tool and the Plan confirmation a `plan_submit` call raises: both are the
/// same canonical interaction fact on the call's own item. The receipts are the durable evidence of
/// that fact, so the migration re-derives the projection from them and updates the calling item **in
/// place**: the row keeps its `item_id`, ordinal, Turn binding, creation time, content revision and
/// body, and only gains the typed history. Nothing is replayed, no tool runs again, no model context
/// changes and the private answer receipt is never rewritten, so an already resolved question or
/// Plan decision cannot be answered twice, lose an answer or be re-derived from the current Plan. A
/// repeated open re-reads a database that already carries the projection and changes nothing.
pub(super) async fn backfill_tool_user_input(
    db: &impl ConnectionTrait,
    thread_id: &str,
) -> Result<()> {
    use crate::studio::thread_projection::{
        attach_tool_user_input, order, project_tool_user_input,
    };
    use pl_core::thread::interactions::InteractionRecord;

    let mut cursor = 0_i64;
    loop {
        let rows = db
            .query_all_raw(statement(
                "SELECT rowid,item_id,payload FROM history_fact_receipts \
             WHERE kind='interaction' AND rowid>? ORDER BY rowid LIMIT 100",
                vec![cursor.into()],
            ))
            .await?;
        if rows.is_empty() {
            break;
        }
        for row in rows {
            cursor = row.try_get("", "rowid")?;
            let record: InteractionRecord =
                serde_json::from_str(&row.try_get::<String>("", "payload")?)
                    .context("legacy interaction receipt cannot be decoded")?;
            let receipt: String = row.try_get("", "item_id")?;
            ensure!(
                receipt == order::receipt_id("interaction", &record.request.id),
                "legacy interaction receipt identity conflicts with its payload"
            );
            let Some(user_input) = project_tool_user_input(thread_id, &record)? else {
                continue;
            };
            // Receipts are appended per revision, so an identity's newest row is applied last and
            // wins: the settled answer supersedes the pending projection, never the other way round.
            let call_id =
                pl_core::tool::opaque::interaction_tool_call_id(user_input.interaction_id())
                    .context("user-input interaction names no tool call")?;
            let tool_id = order::tool_id(call_id);
            let row = db
                .query_one_raw(statement(
                    "SELECT revision,payload FROM history_items WHERE item_id=?",
                    vec![tool_id.clone().into()],
                ))
                .await?
                .with_context(|| {
                    format!("user-input history `{tool_id}` has no durable tool item")
                })?;
            let stored_revision: i64 = row.try_get("", "revision")?;
            let mut item: ThreadItem = serde_json::from_str(&row.try_get::<String>("", "payload")?)
                .with_context(|| format!("tool item `{tool_id}` cannot be decoded"))?;
            if item.tool().and_then(|tool| tool.user_input()) == Some(&user_input) {
                continue;
            }
            attach_tool_user_input(&mut item, user_input)?;
            // 迁移只原位改载荷，不推进内容版本：schema 升级在读基线之前完成，下一次内容变化仍由
            // 既有版本机制推进一次。迁移自己推进 revision 会让紧接的提交撞上同一版本的不同载荷，
            // 或把真实内容版本挤到迁移伪造的版本域之下。
            ensure!(
                integer(item.revision)? == stored_revision,
                "tool item `{tool_id}` row and payload versions disagree"
            );
            db.execute_raw(statement(
                "UPDATE history_items SET payload=? WHERE item_id=? AND revision=?",
                vec![
                    serde_json::to_string(&item)?.into(),
                    item.id.clone().into(),
                    stored_revision.into(),
                ],
            ))
            .await?;
        }
    }
    Ok(())
}

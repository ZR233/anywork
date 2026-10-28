//! Full readiness checks used by initialization, not by bounded cold history queries.

use super::*;
use pl_core::{context::content_hash, thread::ThreadCheckpoint};

pub(super) async fn prove_empty(db: &impl ConnectionTrait) -> Result<()> {
    ensure!(
        applied_write_seq(db).await? == 0,
        "history without checkpoint has a nonzero watermark"
    );
    for table in schema::tables().filter(|name| *name != "history_meta") {
        ensure!(
            db.query_one_raw(statement(&format!("SELECT 1 FROM {table} LIMIT 1"), vec![]))
                .await?
                .is_none(),
            "history without checkpoint has authoritative rows in {table}"
        );
    }
    Ok(())
}

pub(super) async fn contents(db: &impl ConnectionTrait, thread_id: &str) -> Result<()> {
    for row in db
        .query_all_raw(statement("PRAGMA quick_check", vec![]))
        .await?
    {
        ensure!(
            row.try_get_by_index::<String>(0)? == "ok",
            "history quick_check failed"
        );
    }
    ensure!(
        db.query_one_raw(statement("PRAGMA foreign_key_check", vec![]))
            .await?
            .is_none(),
        "history foreign_key_check failed"
    );
    schema::verify_authoritative_objects(db).await?;
    let meta = db
        .query_one_raw(statement(
            "SELECT COUNT(*) AS count FROM history_meta",
            vec![],
        ))
        .await?
        .context("history metadata is absent")?;
    ensure!(
        meta.try_get::<i64>("", "count")? == 1,
        "history has multiple identity rows"
    );
    let fence = applied_write_seq(db).await?;
    ensure!(fence >= 0, "history watermark is negative");
    let mut cursor = None;
    while let Some(row) = import::next_row(db, "history_items", cursor).await? {
        let item: ThreadItem = serde_json::from_str(&row.try_get::<String>("", "payload")?)
            .context("history item has an unsupported representation")?;
        ensure!(
            item.thread_id == thread_id
                && !item.id.is_empty()
                && item.ordinal > 0
                && item.revision > 0
                && item.id == row.try_get::<String>("", "item_id")?
                && integer(item.ordinal)? == row.try_get::<i64>("", "ordinal")?
                && integer(item.revision)? == row.try_get::<i64>("", "revision")?
                && item.turn_id == row.try_get::<String>("", "turn_id")?
                && kind_label(item.kind()) == row.try_get::<String>("", "kind")?
                && item.created_at == row.try_get::<i64>("", "created_at")?
                && item.updated_at == row.try_get::<i64>("", "updated_at")?
                && (if item.is_terminal() {
                    "terminal"
                } else {
                    "open"
                }) == row.try_get::<String>("", "lifecycle")?,
            "history item payload disagrees with its immutable row identity"
        );
        check_sequence(&row, fence)?;
        cursor = Some(row.try_get("", "__source_rowid")?);
    }
    let mut cursor = None;
    while let Some(row) = import::next_row(db, "history_turns", cursor).await? {
        let turn: TimelineTurn = serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
        ensure!(
            turn.turn.id == row.try_get::<String>("", "turn_id")?
                && turn.turn.thread_id == thread_id
                && integer(turn.turn.revision)? == row.try_get::<i64>("", "revision")?,
            "history Turn identity mismatch"
        );
        let bounds = db.query_one_raw(statement(
            "SELECT MIN(ordinal) AS first,MAX(ordinal) AS last FROM history_items WHERE turn_id=?",
            vec![turn.turn.id.clone().into()],
        )).await?.context("history Turn bounds are absent")?;
        ensure!(
            bounds.try_get::<Option<i64>>("", "first")? == Some(row.try_get("", "first_ordinal")?)
                && bounds.try_get::<Option<i64>>("", "last")?
                    == Some(row.try_get("", "last_ordinal")?),
            "history Turn bounds disagree with committed items"
        );
        check_sequence(&row, fence)?;
        cursor = Some(row.try_get("", "__source_rowid")?);
    }
    let mut cursor = None;
    while let Some(row) = import::next_row(db, "history_input_identities", cursor).await? {
        let entry: super::super::state::InputIdentityEntry =
            serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
        ensure!(
            !entry.id.is_empty()
                && !entry.digest.is_empty()
                && entry.revision > 0
                && entry.id == row.try_get::<String>("", "item_id")?
                && integer(entry.ordinal)? == row.try_get::<i64>("", "ordinal")?
                && integer(entry.revision)? == row.try_get::<i64>("", "revision")?
                && entry.digest == row.try_get::<String>("", "digest")?
                && entry.accepted_sequence > 0
                && integer(entry.accepted_sequence)? <= fence,
            "history input identity disagrees with its receipt"
        );
        if entry.purpose == pl_core::thread::input::InputPurpose::Continuation {
            ensure!(
                entry
                    .continuation_admission_revision
                    .is_none_or(|revision| revision <= entry.revision),
                "control input first-admission proof exceeds its current revision"
            );
        }
        check_sequence(&row, fence)?;
        cursor = Some(row.try_get("", "__source_rowid")?);
    }
    let mut cursor = None;
    while let Some(row) = import::next_row(db, "history_fact_receipts", cursor).await? {
        let payload: String = row.try_get("", "payload")?;
        ensure!(
            content_hash(payload.as_bytes()) == row.try_get::<String>("", "digest")?
                && row.try_get::<i64>("", "revision")? > 0
                && !row.try_get::<String>("", "item_id")?.is_empty()
                && !row.try_get::<String>("", "kind")?.is_empty(),
            "history fact receipt digest or identity mismatch"
        );
        check_sequence(&row, fence)?;
        cursor = Some(row.try_get("", "__source_rowid")?);
    }
    let mut cursor = None;
    while let Some(row) = import::next_row(db, "history_message_identities", cursor).await? {
        ensure!(
            !row.try_get::<String>("", "message_id")?.is_empty()
                && !row.try_get::<String>("", "item_id")?.is_empty()
                && row.try_get::<i64>("", "sequence")? > 0
                && row.try_get::<i64>("", "sequence")? <= fence,
            "history message admission identity mismatch"
        );
        check_sequence(&row, fence)?;
        cursor = Some(row.try_get("", "__source_rowid")?);
    }
    let mut cursor = None;
    while let Some(row) = import::next_row(db, "history_tool_tasks", cursor).await? {
        let task: pl_core::thread::task::TaskRecord =
            serde_json::from_str(&row.try_get::<String>("", "task_payload")?)?;
        ensure!(
            task.call_id == row.try_get::<String>("", "call_id")?
                && integer(task.revision)? == row.try_get::<i64>("", "revision")?
                && task.id == format!("task:{}", task.call_id),
            "history task identity mismatch"
        );
        if let Some(payload) = row.try_get::<Option<String>>("", "delivery_payload")? {
            let delivery: pl_core::thread::ToolDelivery = serde_json::from_str(&payload)?;
            ensure!(
                delivery.call_id == task.call_id && delivery.tool_id == task.tool_id,
                "history task delivery belongs to a different call or Turn"
            );
        }
        check_sequence(&row, fence)?;
        cursor = Some(row.try_get("", "__source_rowid")?);
    }
    let checkpoint = checkpoint::read(db, thread_id).await?;
    if let Some(checkpoint) = checkpoint {
        verify_accounting(db, &checkpoint).await?;
    } else {
        prove_empty(db).await?;
    }
    Ok(())
}

fn check_sequence(row: &sea_orm::QueryResult, fence: i64) -> Result<()> {
    let sequence: i64 = row.try_get("", "last_write_seq")?;
    ensure!(
        sequence > 0 && sequence <= fence,
        "history row exceeds the committed watermark"
    );
    Ok(())
}

async fn verify_accounting(db: &impl ConnectionTrait, checkpoint: &ThreadCheckpoint) -> Result<()> {
    let mut currencies = std::collections::BTreeMap::<String, f64>::new();
    let mut cursor = None;
    while let Some(row) = import::next_row(db, "session_costs", cursor).await? {
        let purpose: String = row.try_get("", "purpose")?;
        serde_json::from_str::<Option<String>>(&purpose)
            .context("history cost purpose is malformed")?;
        let currency: String = row.try_get("", "currency")?;
        let amount: f64 = row.try_get("", "amount")?;
        ensure!(
            !currency.is_empty() && amount.is_finite() && amount >= 0.0,
            "history cost is invalid"
        );
        let total = currencies.entry(currency).or_default();
        *total += amount;
        ensure!(total.is_finite(), "history costs overflow");
        cursor = Some(row.try_get("", "__source_rowid")?);
    }
    for total in &checkpoint.state.usage_summary.estimated_costs {
        ensure!(
            total.amount.is_finite() && total.amount >= 0.0,
            "checkpoint cost is invalid"
        );
        let amount = currencies.remove(&total.currency).unwrap_or_default();
        ensure!(
            (amount - total.amount).abs() <= 1e-8 * total.amount.abs().max(1.0),
            "history cost projection differs from reliable checkpoint accounting"
        );
    }
    ensure!(
        currencies.values().all(|amount| *amount == 0.0),
        "history has costs absent from its checkpoint"
    );
    Ok(())
}

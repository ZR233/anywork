//! The latest recovery state shares the history transaction; context records are incremental.

use super::{HistoryStore, applied_write_seq, begin_write, integer, statement};
use anyhow::{Context, Result, ensure};
use pl_core::{
    context::{ContextRecord, content_hash},
    thread::ThreadCheckpoint,
};
use sea_orm::{ConnectionTrait, TransactionTrait};

impl HistoryStore {
    /// Reads one consistent checkpoint/context/history generation without creating a database.
    pub(crate) async fn checkpoint(&self) -> Result<Option<ThreadCheckpoint>> {
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        let tx = connection.db.begin().await?;
        let result = read(&tx, &self.state.thread_id).await?;
        tx.commit().await?;
        Ok(result.map(|checkpoint| *checkpoint))
    }

    /// The only import boundary for a validated, fully materialized v2 TOML checkpoint.
    pub(crate) async fn import_checkpoint(
        &self,
        checkpoint: &ThreadCheckpoint,
        legacy_costs: &[super::super::calls::PurposeUsageProjection],
    ) -> Result<()> {
        // Schema preparation may have completed on the empty database before TOML is loaded.
        // Normalize at this import boundary as well, using exactly the SQLite conversion rules.
        let mut normalized = checkpoint.clone();
        crate::studio::producer_migration::checkpoint(&mut normalized)?;
        crate::studio::model_route::migration::upgrade(&mut normalized.state)?;
        if let Some(mapping) = crate::studio::startup::storage_layout::bot_roots::for_history(
            &self.state.path,
            &self.state.thread_id,
        )
        .await?
        {
            crate::studio::producer_migration::relocate_bot_checkpoint(&mut normalized, &mapping)?;
        }
        let checkpoint = &normalized;
        ensure!(
            checkpoint.thread_id == self.state.thread_id,
            "checkpoint belongs to another Thread"
        );
        ensure!(
            self.watermark().await? == checkpoint.history_fence,
            "legacy history watermark does not match checkpoint fence"
        );
        let tx = begin_write(&self.writer().await?.db).await?;
        ensure!(
            applied_write_seq(&tx).await? == integer(checkpoint.history_fence)?,
            "history changed while importing checkpoint"
        );
        if read(&tx, &self.state.thread_id).await?.is_none() {
            let mut checkpoint = checkpoint.clone();
            for row in tx
                .query_all_raw(statement(
                    "SELECT DISTINCT attempt_id,turn_id FROM execution_lifecycle WHERE attempt_id IS NOT NULL AND turn_id IS NOT NULL",
                    vec![],
                ))
                .await?
            {
                checkpoint.state.attempt_ids.insert(row.try_get("", "attempt_id")?, row.try_get("", "turn_id")?);
            }
            for row in tx
                .query_all_raw(statement(
                    "SELECT task_payload FROM history_tool_tasks",
                    vec![],
                ))
                .await?
            {
                let task: pl_core::thread::task::TaskRecord =
                    serde_json::from_str(&row.try_get::<String>("", "task_payload")?)?;
                checkpoint
                    .state
                    .live_calls
                    .insert(task.call_id, task.turn_id);
            }
            // Older checkpoints excluded title/review generation; other usage already belongs to
            // the checkpoint. Reconcile by purpose/currency, never add two overlapping totals.
            let mut remaining: std::collections::BTreeMap<String, f64> = checkpoint
                .state
                .usage_summary
                .pricing
                .estimated_costs
                .iter()
                .map(|cost| (cost.currency.clone(), cost.amount))
                .collect();
            for purpose in legacy_costs {
                for cost in &purpose.estimated_costs {
                    ensure!(
                        cost.amount.is_finite() && cost.amount >= 0.0,
                        "invalid legacy cost"
                    );
                    if matches!(purpose.purpose.as_deref(), Some("title" | "review")) {
                        if let Some(total) = checkpoint
                            .state
                            .usage_summary
                            .pricing
                            .estimated_costs
                            .iter_mut()
                            .find(|total| total.currency == cost.currency)
                        {
                            total.amount += cost.amount;
                        } else {
                            checkpoint.state.usage_summary.pricing.estimated_costs.push(
                                pl_core::thread::UsageCost {
                                    currency: cost.currency.clone(),
                                    amount: cost.amount,
                                },
                            );
                        }
                    } else {
                        let total = remaining.entry(cost.currency.clone()).or_default();
                        ensure!(
                            *total + 1e-9 >= cost.amount,
                            "legacy cost exceeds reliable checkpoint total"
                        );
                        *total = (*total - cost.amount).max(0.0);
                    }
                    add_cost(&tx, purpose.purpose.as_deref(), &cost.currency, cost.amount).await?;
                }
            }
            for (currency, amount) in remaining {
                if amount > 0.0 {
                    add_cost(&tx, None, &currency, amount).await?;
                }
            }
            // read() proved that no checkpoint exists while this write transaction is held.
            write(&tx, &checkpoint).await?;
            // Keep this marker as migration evidence. Source TOML files and checkpoint bodies are
            // user-owned originals and are never removed by the importer.
            tx.execute_unprepared("UPDATE session_checkpoint SET legacy_cleanup=1 WHERE id=1")
                .await?;
        }
        tx.commit().await?;
        let restored = self
            .checkpoint()
            .await?
            .context("imported checkpoint is absent")?;
        ensure!(
            restored.state_revision == checkpoint.state_revision
                && restored.state.context == checkpoint.state.context,
            "imported checkpoint verification failed"
        );
        Ok(())
    }
}

/// Representation migrations update only the extension portion of the original JSON. Context
/// rows, unknown producer fields, history watermarks and usage facts keep their stored encoding.
pub(super) async fn write_representation(
    tx: &impl ConnectionTrait,
    original: &ThreadCheckpoint,
    migrated: &ThreadCheckpoint,
) -> Result<()> {
    {
        // The validation clone is synchronous scratch, not state needed during the SQL writes.
        let mut unchanged = migrated.clone();
        unchanged.state.extensions = original.state.extensions.clone();
        unchanged.state.extension_sequence = original.state.extension_sequence;
        ensure!(
            serde_json::to_vec(&unchanged)? == serde_json::to_vec(original)?,
            "representation migration changed checkpoint business state"
        );
    }
    if migrated.state.extensions == original.state.extensions
        && migrated.state.extension_sequence == original.state.extension_sequence
    {
        return Ok(());
    }
    let row = tx
        .query_one_raw(statement(
            "SELECT payload FROM session_checkpoint WHERE id=1",
            vec![],
        ))
        .await?
        .context("recovery checkpoint is absent")?;
    let mut payload: serde_json::Value =
        serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
    let extensions = payload["state"]
        .as_object_mut()
        .context("checkpoint state is not an object")?
        .entry("extensions")
        .or_insert_with(|| serde_json::json!({}))
        .as_object_mut()
        .context("checkpoint extensions are not an object")?;
    for (key, record) in &migrated.state.extensions {
        match original.state.extensions.get(key) {
            Some(previous) if previous == record => {}
            Some(previous) => {
                let saved = extensions
                    .get_mut(key)
                    .context("saved extension is absent")?;
                if previous.revision != record.revision {
                    saved["revision"] = record.revision.into();
                }
                if previous.payload != record.payload {
                    saved["payload"]["format"] = record.payload.format().into();
                    saved["payload"]["version"] = record.payload.version().into();
                    saved["payload"]["content"] = record.payload.content().into();
                }
            }
            None => {
                extensions.insert(key.clone(), serde_json::to_value(record)?);
            }
        }
    }
    for key in original.state.extensions.keys() {
        if !migrated.state.extensions.contains_key(key) {
            extensions.remove(key);
        }
    }
    if original.state.extension_sequence != migrated.state.extension_sequence {
        payload["state"]["extensionSequence"] = migrated.state.extension_sequence.into();
    }
    let payload = serde_json::to_string(&payload)?;
    let hash = content_hash(payload.as_bytes());
    tx.execute_raw(statement(
        "UPDATE session_checkpoint SET payload=?,payload_hash=? WHERE id=1",
        vec![payload.into(), hash.into()],
    ))
    .await?;
    // Only explicit representation maintenance can run before the head's schema step.
    // Ordinary writers always require the current columns, never a missing-column fallback.
    if super::schema::version(tx).await? == super::HISTORY_SCHEMA_VERSION {
        write_model_route_head(tx, &migrated.state).await?;
    }
    Ok(())
}

fn model_route_head(
    state: &pl_core::thread::ThreadSnapshot,
) -> Result<(Option<String>, Option<String>)> {
    let json = crate::studio::model_route::saved(state)?
        .map(|route| serde_json::to_string(&route))
        .transpose()?;
    let hash = json.as_ref().map(|json| content_hash(json.as_bytes()));
    Ok((json, hash))
}

/// Mechanical projection used only inside the original checkpoint/migration transaction.
pub(super) async fn write_model_route_head(
    db: &impl ConnectionTrait,
    state: &pl_core::thread::ThreadSnapshot,
) -> Result<()> {
    let (json, hash) = model_route_head(state)?;
    let result = db
        .execute_raw(statement(
            "UPDATE history_meta SET model_route_json=?,model_route_hash=? WHERE id=1",
            vec![json.into(), hash.into()],
        ))
        .await?;
    ensure!(
        result.rows_affected() == 1,
        "history metadata is missing while writing model route head"
    );
    Ok(())
}

/// Cold reads validate only the narrow header; recovery payload/context are not selected.
pub(super) async fn read_model_route_head(
    db: &impl ConnectionTrait,
) -> Result<Option<crate::studio::model_route::SavedModelRoute>> {
    let Some(row) = db
        .query_one_raw(statement(
            "SELECT model_route_json,model_route_hash FROM history_meta WHERE id=1",
            vec![],
        ))
        .await?
    else {
        anyhow::bail!("history metadata is missing while reading model route head");
    };
    let json: Option<String> = row.try_get("", "model_route_json")?;
    let hash: Option<String> = row.try_get("", "model_route_hash")?;
    match (json, hash) {
        (None, None) => Ok(None),
        (Some(json), Some(hash)) => {
            ensure!(
                content_hash(json.as_bytes()) == hash,
                "checkpoint model route head hash mismatch"
            );
            Ok(Some(serde_json::from_str(&json)?))
        }
        _ => anyhow::bail!("checkpoint model route head/hash must be paired"),
    }
}

/// Rewrites the complete legacy checkpoint within the TOML import transaction.
async fn write(tx: &impl ConnectionTrait, checkpoint: &ThreadCheckpoint) -> Result<()> {
    ensure!(
        checkpoint.is_materialized(),
        "checkpoint still references external legacy bodies"
    );
    ensure!(
        checkpoint.state_revision == checkpoint.state.commit_sequence
            && checkpoint.history_fence <= checkpoint.state_revision,
        "checkpoint revision is inconsistent"
    );
    let records = &checkpoint.state.context.records;
    tx.execute_unprepared("DELETE FROM current_context").await?;
    for (ordinal, record) in records.iter().enumerate() {
        let payload = serde_json::to_string(record)?;
        let hash = content_hash(payload.as_bytes());
        tx.execute_raw(statement(
            "INSERT INTO current_context(ordinal,record_id,payload,payload_hash) VALUES(?,?,?,?)",
            vec![
                integer(ordinal)?.into(),
                record.id.clone().into(),
                payload.into(),
                hash.into(),
            ],
        ))
        .await?;
    }
    let mut metadata = checkpoint.pruned()?;
    metadata.state.context.records = Default::default();
    let payload = serde_json::to_string(&metadata)?;
    let hash = content_hash(payload.as_bytes());
    tx.execute_raw(statement(
        "INSERT INTO session_checkpoint(id,revision,context_revision,context_count,payload,payload_hash)
         VALUES(1,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET revision=excluded.revision,
         context_revision=excluded.context_revision,context_count=excluded.context_count,
         payload=excluded.payload,payload_hash=excluded.payload_hash",
        vec![integer(checkpoint.state_revision)?.into(), integer(checkpoint.state.context.revision)?.into(),
            integer(records.len())?.into(), payload.into(), hash.into()],
    )).await?;
    write_model_route_head(tx, &checkpoint.state).await?;
    Ok(())
}

// Migration steps and transaction owners keep the decoded state across awaits. Share this
// heap-owned read boundary; only the outer HistoryStore methods unwrap after committing.
pub(super) async fn read(
    tx: &impl ConnectionTrait,
    thread_id: &str,
) -> Result<Option<Box<ThreadCheckpoint>>> {
    read_with(tx, thread_id, ThreadCheckpoint::SCHEMA_VERSION, |payload| {
        Ok(serde_json::from_str(payload)?)
    })
    .await
}

/// The schema step shares every hash, identity, context and fence check with ordinary reads.
/// Only this explicit writer boundary can decode a retired envelope.
pub(super) async fn migrate_envelope(tx: &impl ConnectionTrait, thread_id: &str) -> Result<()> {
    #[derive(serde::Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct Header {
        schema_version: u32,
    }
    let mut upgraded = false;
    let mut retained_envelope = None;
    let checkpoint = read_with(tx, thread_id, ThreadCheckpoint::SCHEMA_VERSION, |payload| {
        let header: Header = serde_json::from_str(payload)?;
        if header.schema_version == ThreadCheckpoint::SCHEMA_VERSION {
            return Ok(serde_json::from_str(payload)?);
        }
        let current = Box::new(ThreadCheckpoint::decode_legacy(payload)?);
        if header.schema_version >= 4 {
            // These envelopes differ only in their usage layout. Preserve all other original
            // fields and opaque producer bytes; no re-aggregation or execution replay occurs.
            use crate::studio::producer_migration::{RawObject, edit};
            use serde_json::value::to_raw_value;
            let mut raw: RawObject = serde_json::from_str(payload)?;
            raw.insert(
                "schemaVersion".into(),
                to_raw_value(&ThreadCheckpoint::SCHEMA_VERSION)?,
            );
            edit(&mut raw, "state", |state| {
                state.insert(
                    "usageSummary".into(),
                    to_raw_value(&current.state.usage_summary)?,
                );
                Ok(())
            })?;
            retained_envelope = Some(serde_json::to_string(&raw)?);
        }
        upgraded = true;
        Ok(current)
    })
    .await?;
    let Some(mut checkpoint) = checkpoint.filter(|_| upgraded) else {
        return Ok(());
    };
    checkpoint.state.context.records = Default::default();
    let payload = match retained_envelope {
        Some(payload) => payload,
        None => serde_json::to_string(&checkpoint)?,
    };
    let hash = content_hash(payload.as_bytes());
    tx.execute_raw(statement(
        "UPDATE session_checkpoint SET payload=?,payload_hash=? WHERE id=1",
        vec![payload.into(), hash.into()],
    ))
    .await?;
    Ok(())
}

async fn read_with(
    tx: &impl ConnectionTrait,
    thread_id: &str,
    expected_schema: u32,
    decode: impl FnOnce(&str) -> Result<Box<ThreadCheckpoint>>,
) -> Result<Option<Box<ThreadCheckpoint>>> {
    let Some(ValidatedEnvelope {
        mut checkpoint,
        context_count: count,
    }) = read_envelope_with(tx, thread_id, expected_schema, decode).await?
    else {
        return Ok(None);
    };
    let rows = tx
        .query_all_raw(statement(
            "SELECT ordinal,record_id,payload,payload_hash FROM current_context ORDER BY ordinal",
            vec![],
        ))
        .await?;
    ensure!(rows.len() == count, "current context record count mismatch");
    tracing::debug!(
        target: "conversation_work",
        thread_id,
        full_context_rows = rows.len(),
        "execution context read"
    );
    let mut records = Vec::with_capacity(count);
    for (ordinal, row) in rows.into_iter().enumerate() {
        let payload: String = row.try_get("", "payload")?;
        ensure!(
            integer(ordinal)? == row.try_get::<i64>("", "ordinal")?
                && content_hash(payload.as_bytes()) == row.try_get::<String>("", "payload_hash")?,
            "current context ordering or hash mismatch"
        );
        let record: ContextRecord = serde_json::from_str(&payload)?;
        ensure!(
            record.id == row.try_get::<String>("", "record_id")?,
            "current context identity mismatch"
        );
        records.push(record);
    }
    checkpoint.state.context.records = records.into();
    Ok(Some(checkpoint))
}

struct ValidatedEnvelope {
    checkpoint: Box<ThreadCheckpoint>,
    context_count: usize,
}

async fn read_envelope_with(
    tx: &impl ConnectionTrait,
    thread_id: &str,
    expected_schema: u32,
    decode: impl FnOnce(&str) -> Result<Box<ThreadCheckpoint>>,
) -> Result<Option<ValidatedEnvelope>> {
    let Some(row) = tx.query_one_raw(statement(
        "SELECT revision,context_revision,context_count,payload,payload_hash FROM session_checkpoint WHERE id=1", vec![],
    )).await? else { return Ok(None) };
    let payload: String = row.try_get("", "payload")?;
    ensure!(
        content_hash(payload.as_bytes()) == row.try_get::<String>("", "payload_hash")?,
        "checkpoint content hash mismatch"
    );
    let checkpoint = decode(&payload)?;
    ensure!(
        checkpoint.thread_id == thread_id
            && checkpoint.schema_version == expected_schema
            && checkpoint.is_materialized()
            && checkpoint.state.context.records.is_empty()
            && checkpoint.state_revision == checkpoint.state.commit_sequence
            && integer(checkpoint.state_revision)? == row.try_get::<i64>("", "revision")?
            && integer(checkpoint.state.context.revision)?
                == row.try_get::<i64>("", "context_revision")?
            && integer(checkpoint.history_fence)? == applied_write_seq(tx).await?,
        "checkpoint identity or history fence mismatch"
    );
    Ok(Some(ValidatedEnvelope {
        checkpoint,
        context_count: usize::try_from(row.try_get::<i64>("", "context_count")?)?,
    }))
}

async fn add_cost(
    tx: &impl ConnectionTrait,
    purpose: Option<&str>,
    currency: &str,
    amount: f64,
) -> Result<()> {
    let purpose = serde_json::to_string(&purpose)?;
    let previous = tx
        .query_one_raw(statement(
            "SELECT amount FROM session_costs WHERE purpose=? AND currency=?",
            vec![purpose.clone().into(), currency.into()],
        ))
        .await?
        .map(|row| row.try_get::<f64>("", "amount"))
        .transpose()?
        .unwrap_or(0.0);
    let total = previous + amount;
    ensure!(
        amount.is_finite() && total.is_finite(),
        "session accounting overflow"
    );
    tx.execute_raw(statement(
        "INSERT INTO session_costs(purpose,currency,amount) VALUES(?,?,?)
         ON CONFLICT(purpose,currency) DO UPDATE SET amount=excluded.amount",
        vec![purpose.into(), currency.into(), total.into()],
    ))
    .await?;
    Ok(())
}

impl HistoryStore {}

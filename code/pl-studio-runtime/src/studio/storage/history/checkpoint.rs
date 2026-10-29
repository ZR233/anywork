//! The latest recovery state shares the history transaction; context records are incremental.

use super::{HistoryStore, applied_write_seq, begin_write, integer, statement};
use anyhow::{Context, Result, ensure};
use pl_core::{
    context::{ContextRecord, content_hash},
    thread::{ThreadCheckpoint, journal::ContextChange},
};
use sea_orm::{ConnectionTrait, TransactionTrait};

impl HistoryStore {
    /// Reads canonical recovery facts and the latest admitted Turn in one strictly read-only
    /// snapshot, even if a timeline observer still retains this owner's initialized writer.
    pub(crate) async fn read_only_checkpoint_with_latest_turn(
        &self,
    ) -> Result<Option<(ThreadCheckpoint, Option<pl_protocol::Turn>)>> {
        let connection = {
            let _initializing = self.state.init.read().await;
            self.read_only_connection().await?
        };
        let Some(connection) = connection else {
            return Ok(None);
        };
        let tx = connection.db.begin().await?;
        // A shared read-only connection can predate an explicit writer upgrade. Validate the
        // current transaction's identity/schema, not a cached version or the writer fast path.
        let (database_id, _) = super::validate_existing(&tx, &self.state.thread_id).await?;
        ensure!(
            database_id == connection.database_id,
            "canonical history identity changed"
        );
        let result = if let Some(checkpoint) = read(&tx, &self.state.thread_id).await? {
            let turn =
                super::read_latest_turn_at(&tx, &self.state.thread_id, checkpoint.history_fence)
                    .await?;
            Some((checkpoint, turn))
        } else {
            None
        };
        tx.commit().await?;
        Ok(result)
    }

    /// Reads one consistent checkpoint/context/history generation without creating a database.
    pub(crate) async fn checkpoint(&self) -> Result<Option<ThreadCheckpoint>> {
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        let tx = connection.db.begin().await?;
        let result = read(&tx, &self.state.thread_id).await?;
        tx.commit().await?;
        Ok(result)
    }

    /// Advances the same Migrator after the v2 TOML import boundary has finished.
    pub(crate) async fn prepare_model_access(&self) -> Result<Option<ThreadCheckpoint>> {
        super::schema::prepare(
            &self.writer().await?.db,
            &self.state.thread_id,
            super::schema::Preparation::ModelAccess,
            None,
        )
        .await?;
        self.checkpoint().await
    }

    /// The owner supplies verified Mode/Agent facts; SeaORM commits this named migration and its
    /// completion record together. Candidate construction has no storage or external side effects.
    pub(crate) async fn prepare_execution_identity(
        &self,
        migrate: impl FnOnce(&mut pl_core::thread::ThreadSnapshot) -> Result<()>,
    ) -> Result<ThreadCheckpoint> {
        let original = self
            .prepare_model_access()
            .await?
            .context("recovery checkpoint is absent")?;
        let mut migrated = original.clone();
        migrate(&mut migrated.state).map_err(|error| {
            crate::studio::startup::migration_error(
                "history",
                super::schema::EXECUTION_IDENTITY,
                error,
            )
        })?;
        super::schema::prepare(
            &self.writer().await?.db,
            &self.state.thread_id,
            super::schema::Preparation::ExecutionIdentity,
            Some((original, migrated)),
        )
        .await?;
        self.checkpoint()
            .await?
            .context("prepared checkpoint is absent")
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
                    "SELECT payload FROM history_items WHERE kind='inference' ORDER BY ordinal",
                    vec![],
                ))
                .await?
            {
                let item: pl_protocol::ThreadItem =
                    serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
                if let pl_protocol::ThreadItemState::Inference(inference) = item.state() {
                    checkpoint
                        .state
                        .attempt_ids
                        .insert(inference.inference_id().to_owned(), item.turn_id.clone());
                }
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
            write(&tx, &checkpoint, None).await?;
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

    pub(crate) async fn legacy_cleanup_pending(&self) -> Result<bool> {
        let Some(connection) = self.reader().await? else {
            return Ok(false);
        };
        let row = connection
            .db
            .query_one_raw(statement(
                "SELECT legacy_cleanup FROM session_checkpoint WHERE id=1",
                vec![],
            ))
            .await?;
        Ok(row
            .map(|row| row.try_get::<i64>("", "legacy_cleanup"))
            .transpose()?
            .unwrap_or(0)
            != 0)
    }

    pub(crate) async fn finish_legacy_cleanup(&self) -> Result<()> {
        self.writer()
            .await?
            .db
            .execute_unprepared("UPDATE session_checkpoint SET legacy_cleanup=0 WHERE id=1")
            .await?;
        Ok(())
    }
}

pub(super) async fn verify_committed(
    tx: &impl ConnectionTrait,
    checkpoint: &ThreadCheckpoint,
    watermark: i64,
) -> Result<()> {
    let row = tx
        .query_one_raw(statement(
            "SELECT revision FROM session_checkpoint WHERE id=1",
            vec![],
        ))
        .await?
        .context("durable history has no checkpoint")?;
    ensure!(
        row.try_get::<i64>("", "revision")? == watermark
            && watermark >= integer(checkpoint.state_revision)?,
        "durable checkpoint does not cover retried history"
    );
    Ok(())
}

/// Representation migrations update only the extension portion of the original JSON. Context
/// rows, unknown producer fields, history watermarks and usage facts keep their stored encoding.
pub(super) async fn write_representation(
    tx: &impl ConnectionTrait,
    original: &ThreadCheckpoint,
    migrated: &ThreadCheckpoint,
) -> Result<()> {
    let mut unchanged = migrated.clone();
    unchanged.state.extensions = original.state.extensions.clone();
    unchanged.state.extension_sequence = original.state.extension_sequence;
    ensure!(
        serde_json::to_vec(&unchanged)? == serde_json::to_vec(original)?,
        "representation migration changed checkpoint business state"
    );
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
    Ok(())
}

pub(super) async fn write(
    tx: &impl ConnectionTrait,
    checkpoint: &ThreadCheckpoint,
    change: Option<&ContextChange>,
) -> Result<()> {
    ensure!(
        checkpoint.is_materialized(),
        "checkpoint still references external legacy bodies"
    );
    ensure!(
        checkpoint.state_revision == checkpoint.state.commit_sequence
            && checkpoint.history_fence <= checkpoint.state_revision,
        "checkpoint revision is inconsistent"
    );
    let prior = tx
        .query_one_raw(statement(
            "SELECT revision,context_revision,context_count FROM session_checkpoint WHERE id=1",
            vec![],
        ))
        .await?;
    let records = &checkpoint.state.context.records;
    let previous_count = prior
        .as_ref()
        .map(|row| row.try_get::<i64>("", "context_count"))
        .transpose()?;
    let append = match (prior.as_ref(), change) {
        (
            Some(row),
            Some(ContextChange::Append {
                revision,
                records: added,
            }),
        ) => {
            ensure!(
                *revision == checkpoint.state.context.revision,
                "context append revision mismatch"
            );
            let count = usize::try_from(row.try_get::<i64>("", "context_count")?)?;
            ensure!(
                count.checked_add(added.len()) == Some(records.len())
                    && records[count..] == **added,
                "context append does not match checkpoint"
            );
            Some((count, added.as_ref()))
        }
        (Some(row), None) => {
            ensure!(
                row.try_get::<i64>("", "context_revision")?
                    == integer(checkpoint.state.context.revision)?
                    && previous_count == Some(integer(records.len())?),
                "context changed without a mutation"
            );
            Some((records.len(), &[][..]))
        }
        _ => None,
    };
    let (start, changed) = match append {
        Some(value) => value,
        None => {
            tx.execute_unprepared("DELETE FROM current_context").await?;
            (0, records.as_ref())
        }
    };
    for (offset, record) in changed.iter().enumerate() {
        let payload = serde_json::to_string(record)?;
        let hash = content_hash(payload.as_bytes());
        tx.execute_raw(statement(
            "INSERT INTO current_context(ordinal,record_id,payload,payload_hash) VALUES(?,?,?,?)",
            vec![
                integer(start + offset)?.into(),
                record.id.clone().into(),
                payload.into(),
                hash.into(),
            ],
        ))
        .await?;
    }
    let mut metadata = checkpoint.pruned();
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
    Ok(())
}

pub(super) async fn read(
    tx: &impl ConnectionTrait,
    thread_id: &str,
) -> Result<Option<ThreadCheckpoint>> {
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
        let current = ThreadCheckpoint::decode_legacy(payload)?;
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
    decode: impl FnOnce(&str) -> Result<ThreadCheckpoint>,
) -> Result<Option<ThreadCheckpoint>> {
    let Some(row) = tx.query_one_raw(statement(
        "SELECT revision,context_revision,context_count,payload,payload_hash FROM session_checkpoint WHERE id=1", vec![],
    )).await? else { return Ok(None) };
    let payload: String = row.try_get("", "payload")?;
    ensure!(
        content_hash(payload.as_bytes()) == row.try_get::<String>("", "payload_hash")?,
        "checkpoint content hash mismatch"
    );
    let mut checkpoint = decode(&payload)?;
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
    let count = usize::try_from(row.try_get::<i64>("", "context_count")?)?;
    let rows = tx
        .query_all_raw(statement(
            "SELECT ordinal,record_id,payload,payload_hash FROM current_context ORDER BY ordinal",
            vec![],
        ))
        .await?;
    ensure!(rows.len() == count, "current context record count mismatch");
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

/// Accounting is reliable state, independent from the lossy log writer.
pub(super) async fn fold_costs(
    tx: &impl ConnectionTrait,
    accounting: &crate::studio::thread_projection::PreparedAccounting,
) -> Result<()> {
    for fact in accounting.facts.iter() {
        for cost in fact.record.accounting.estimated_costs() {
            add_cost(
                tx,
                fact.record.purpose.as_deref(),
                &cost.currency,
                cost.amount,
            )
            .await?;
        }
    }
    Ok(())
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

/// A compact absolute projection; no context or historical body is read.
pub(crate) struct SessionAccounting {
    pub revision: u64,
    pub has_unpriced_usage: bool,
    pub purpose_costs: Vec<(Option<String>, Vec<pl_protocol::RuntimeCostAmount>)>,
}

impl HistoryStore {
    pub(crate) async fn accounting(&self) -> Result<Option<SessionAccounting>> {
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        let tx = connection.db.begin().await?;
        let result = read_accounting(&tx, &self.state.thread_id).await?;
        tx.commit().await?;
        Ok(result)
    }
}

pub(super) async fn read_accounting(
    tx: &impl ConnectionTrait,
    thread_id: &str,
) -> Result<Option<SessionAccounting>> {
    let Some(row) = tx
        .query_one_raw(statement(
            "SELECT revision,payload,payload_hash FROM session_checkpoint WHERE id=1",
            vec![],
        ))
        .await?
    else {
        return Ok(None);
    };
    let payload: String = row.try_get("", "payload")?;
    ensure!(
        content_hash(payload.as_bytes()) == row.try_get::<String>("", "payload_hash")?,
        "accounting checkpoint hash mismatch"
    );
    let checkpoint: ThreadCheckpoint = serde_json::from_str(&payload)?;
    ensure!(
        checkpoint.schema_version == ThreadCheckpoint::SCHEMA_VERSION
            && checkpoint.thread_id == thread_id,
        "accounting checkpoint requires explicit storage preparation or has a foreign identity"
    );
    Ok(Some(SessionAccounting {
        revision: checkpoint.state_revision,
        has_unpriced_usage: checkpoint.state.usage_summary.pricing.incomplete,
        purpose_costs: read_purpose_costs(tx).await?,
    }))
}

pub(super) async fn read_purpose_costs(
    tx: &impl ConnectionTrait,
) -> Result<Vec<(Option<String>, Vec<pl_protocol::RuntimeCostAmount>)>> {
    let mut purposes =
        std::collections::BTreeMap::<Option<String>, Vec<pl_protocol::RuntimeCostAmount>>::new();
    for row in tx
        .query_all_raw(statement(
            "SELECT purpose,currency,amount FROM session_costs ORDER BY purpose,currency",
            vec![],
        ))
        .await?
    {
        let purpose = serde_json::from_str(&row.try_get::<String>("", "purpose")?)?;
        purposes
            .entry(purpose)
            .or_default()
            .push(pl_protocol::RuntimeCostAmount {
                currency: row.try_get("", "currency")?,
                amount: row.try_get("", "amount")?,
            });
    }
    Ok(purposes.into_iter().collect())
}

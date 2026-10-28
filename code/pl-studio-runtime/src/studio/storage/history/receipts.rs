//! Exact immutable receipt reads, fenced by the same SQLite statement as history ownership.

use anyhow::{Context, Result, ensure};
use sea_orm::ConnectionTrait;

use super::{HistoryStore, integer, statement};

pub(crate) struct VerifiedFactReceipt {
    pub payload: String,
    pub write_sequence: u64,
}

impl HistoryStore {
    /// Reads one exact revision without activating a writer or filling missing historical proofs.
    /// Missing history/receipt means that no durable proof is available, not that an operation was
    /// rejected or never committed in core. Storage/identity/digest failures remain errors.
    pub(crate) async fn verified_fact_receipt(
        &self,
        item_id: &str,
        revision: u64,
        kind: &str,
    ) -> Result<Option<VerifiedFactReceipt>> {
        ensure!(
            !item_id.is_empty() && revision > 0 && !kind.is_empty(),
            "invalid immutable receipt identity"
        );
        self.wait_for_initialization().await?;
        let _initializing = self.state.init.read().await;
        let Some(connection) = self.read_only_connection().await? else {
            return Ok(None);
        };
        // A single SELECT gives ownership, the committed watermark and the receipt one read
        // snapshot. Separate queries could bless a row using another transaction's coverage.
        let row = connection
            .db
            .query_one_raw(statement(
                "SELECT m.database_id,m.thread_id,m.applied_write_seq,
                        r.item_id,r.revision,r.kind,r.digest,r.payload,r.last_write_seq
                 FROM history_meta m LEFT JOIN history_fact_receipts r
                 ON r.item_id=? AND r.revision=? WHERE m.id=1",
                vec![item_id.to_owned().into(), integer(revision)?.into()],
            ))
            .await?
            .context("history metadata is missing for immutable receipt")?;
        ensure!(
            row.try_get::<String>("", "database_id")? == connection.database_id
                && row.try_get::<String>("", "thread_id")? == self.state.thread_id,
            "immutable receipt history ownership changed"
        );
        let watermark = u64::try_from(row.try_get::<i64>("", "applied_write_seq")?)?;
        let Some(stored_id) = row.try_get::<Option<String>>("", "item_id")? else {
            return Ok(None);
        };
        ensure!(
            stored_id == item_id
                && u64::try_from(row.try_get::<i64>("", "revision")?)? == revision
                && row.try_get::<String>("", "kind")? == kind,
            "immutable receipt identity conflicts with its requested fact"
        );
        let write_sequence = u64::try_from(row.try_get::<i64>("", "last_write_seq")?)?;
        ensure!(
            write_sequence > 0 && write_sequence <= watermark,
            "immutable receipt is not covered by durable history"
        );
        let payload: String = row.try_get("", "payload")?;
        ensure!(
            pl_core::context::content_hash(payload.as_bytes())
                == row.try_get::<String>("", "digest")?,
            "immutable receipt payload digest mismatch"
        );
        Ok(Some(VerifiedFactReceipt {
            payload,
            write_sequence,
        }))
    }
}

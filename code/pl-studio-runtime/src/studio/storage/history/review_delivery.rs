//! Immutable review-delivery originals in the existing ordered history transaction.
use super::{HistoryStore, applied_write_seq, statement};
use crate::thread_assembler::review_delivery::{FACT_FORMAT, ReviewDeliveryFact};
use anyhow::{Result, ensure};
use pl_core::context::OpaquePayload;
use sea_orm::{ConnectionTrait, QueryResult};

fn decode(row: QueryResult, thread: &str, through: i64) -> Result<ReviewDeliveryFact> {
    let payload: String = row.try_get("", "payload")?;
    ensure!(
        row.try_get::<String>("", "kind")? == "reviewDeliveryException"
            && row.try_get::<i64>("", "revision")? == 1
            && row.try_get::<String>("", "digest")?
                == pl_core::context::content_hash(payload.as_bytes()),
        crate::thread_assembler::review_dispatch::TerminalIntegrityError(
            "review delivery receipt integrity mismatch"
        )
    );
    let fact = ReviewDeliveryFact::decode(&OpaquePayload::new(FACT_FORMAT, 1, payload)?)?;
    let source: i64 = row.try_get("", "last_write_seq")?;
    ensure!(
        row.try_get::<String>("", "item_id")? == fact.message.id
            && fact.message.source_id == format!("studio.review:{thread}")
            && source > i64::try_from(fact.terminal_sequence)?
            && source <= through,
        crate::thread_assembler::review_dispatch::TerminalIntegrityError(
            "review delivery receipt provenance mismatch"
        )
    );
    Ok(fact)
}

impl HistoryStore {
    pub(crate) async fn review_finish_bytes(&self, turn: &str) -> Result<u64> {
        let Some(connection) = self.reader().await? else {
            return Ok(0);
        };
        let row = connection.db.query_one_raw(statement(
            "SELECT COALESCE((SELECT length(CAST(payload AS BLOB)) FROM history_items WHERE turn_id=? AND kind='tool' ORDER BY ordinal DESC LIMIT 1),0)+COALESCE((SELECT MAX(length(CAST(delivery_payload AS BLOB))) FROM history_tool_tasks WHERE json_extract(task_payload,'$.turnId')=? AND json_extract(task_payload,'$.toolId')=?),0) AS bytes",
            vec![turn.to_owned().into(), turn.to_owned().into(), pl_tool::finish_turn::TOOL_FINISH_TURN.to_owned().into()],
        )).await?;
        row.map(|row| Ok(u64::try_from(row.try_get::<i64>("", "bytes")?)?))
            .unwrap_or(Ok(0))
    }
    /// Recovery needs the calling finish receipt, not all findings/reasoning in a possibly very
    /// long Turn. Read one canonical tool item and then use the existing exact delivery lookup.
    pub(crate) async fn review_finish_call(&self, turn: &str) -> Result<Option<String>> {
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        let Some(row) = connection.db.query_one_raw(statement(
            "SELECT payload FROM history_items WHERE turn_id=? AND kind='tool' ORDER BY ordinal DESC LIMIT 1",
            vec![turn.to_owned().into()],
        )).await? else { return Ok(None); };
        let item: pl_protocol::ThreadItem =
            serde_json::from_str(&row.try_get::<String>("", "payload")?)?;
        ensure!(
            item.turn_id == turn,
            crate::thread_assembler::review_dispatch::TerminalIntegrityError(
                "review finish item belongs to another Turn"
            )
        );
        let pl_protocol::ThreadItemState::Tool(tool) = item.state() else {
            anyhow::bail!(
                crate::thread_assembler::review_dispatch::TerminalIntegrityError(
                    "review finish item kind mismatch"
                )
            );
        };
        Ok(
            (tool.invocation().name() == pl_tool::finish_turn::TOOL_FINISH_TURN
                && tool.terminal_output().is_some())
            .then(|| tool.invocation().tool_call_id().to_owned()),
        )
    }

    pub(crate) async fn review_delivery_exception(
        &self,
        id: &str,
    ) -> Result<Option<ReviewDeliveryFact>> {
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        let through = applied_write_seq(&connection.db).await?;
        connection.db.query_one_raw(statement(
            "SELECT item_id,kind,payload,digest,revision,last_write_seq FROM history_fact_receipts WHERE item_id=? ORDER BY revision DESC LIMIT 1",
            vec![id.to_owned().into()],
        )).await?.map(|row| decode(row, &self.state.thread_id, through)).transpose()
    }

    /// Keyset enumeration bounds both SQL residency and each close/recovery obligation window.
    pub(crate) async fn review_delivery_exceptions(
        &self,
        after: &str,
    ) -> Result<Vec<ReviewDeliveryFact>> {
        let Some(connection) = self.reader().await? else {
            return Ok(Vec::new());
        };
        let through = applied_write_seq(&connection.db).await?;
        connection.db.query_all_raw(statement(
            "SELECT item_id,kind,payload,digest,revision,last_write_seq FROM history_fact_receipts WHERE kind='reviewDeliveryException' AND item_id>? ORDER BY item_id LIMIT 16",
            vec![after.to_owned().into()],
        )).await?.into_iter().map(|row| decode(row, &self.state.thread_id, through)).collect()
    }
}

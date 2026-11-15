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
        let parent = pl_core::chat::ChatKey::new("turn", turn)?;
        let row = connection.db.query_one_raw(statement(
            "SELECT length(c.payload)+length(c.metadata)+COALESCE(length(CAST(t.task_payload AS BLOB)),0)+COALESCE(length(CAST(t.delivery_payload AS BLOB)),0) AS bytes
             FROM conversation_items c LEFT JOIN history_tool_tasks t ON t.call_id=json_extract(c.metadata,'$.tool.callId')
             WHERE c.parent_id=? AND json_extract(c.metadata,'$.tool.name')=? ORDER BY c.seq DESC LIMIT 1",
            vec![parent.as_str().into(),pl_tool::finish_turn::TOOL_FINISH_TURN.into()],
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
        let parent = pl_core::chat::ChatKey::new("turn", turn)?;
        let Some(row) = connection.db.query_one_raw(statement(
            "SELECT metadata FROM conversation_items WHERE parent_id=? AND json_extract(metadata,'$.tool.name')=? ORDER BY seq DESC LIMIT 1",
            vec![parent.as_str().into(),pl_tool::finish_turn::TOOL_FINISH_TURN.into()],
        )).await? else { return Ok(None) };
        let atom: pl_protocol::ChatAtom =
            serde_json::from_slice(&row.try_get::<Vec<u8>>("", "metadata")?)?;
        ensure!(
            atom.turn_id.as_deref() == Some(turn)
                && matches!(
                    atom.lifecycle,
                    pl_protocol::ChatAtomLifecycle::Terminal { .. }
                ),
            crate::thread_assembler::review_dispatch::TerminalIntegrityError(
                "review finish original provenance mismatch"
            )
        );
        Ok(atom
            .tool
            .filter(|tool| tool.name == pl_tool::finish_turn::TOOL_FINISH_TURN)
            .map(|tool| tool.call_id))
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

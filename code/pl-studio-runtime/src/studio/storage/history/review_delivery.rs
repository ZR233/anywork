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

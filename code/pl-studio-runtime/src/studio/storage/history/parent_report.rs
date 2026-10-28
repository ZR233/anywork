//! The original terminal notification lives with the child history until its parent ACKs it.
use super::{HistoryStore, integer, statement};
use anyhow::{Result, ensure};
use pl_core::thread::inbox::ThreadMessage;
use sea_orm::ConnectionTrait;

impl HistoryStore {
    pub(crate) async fn parent_report_bytes(&self, sequence: u64) -> Result<u64> {
        let Some(connection) = self.reader().await? else {
            return Ok(0);
        };
        let id = crate::studio::agent_close::terminal_report_id(&self.state.thread_id, sequence);
        let row = connection.db.query_one_raw(statement("SELECT length(CAST(payload AS BLOB)) AS bytes FROM history_fact_receipts WHERE item_id=? AND revision=1", vec![id.into()])).await?;
        row.map(|row| Ok(u64::try_from(row.try_get::<i64>("", "bytes")?)?))
            .unwrap_or(Ok(0))
    }
    /// A missing original is never reconstructed from a later checkpoint's permissions/inbox.
    pub(crate) async fn parent_report(
        &self,
        terminal_sequence: u64,
    ) -> Result<Option<ThreadMessage>> {
        let id = crate::studio::agent_close::terminal_report_id(
            &self.state.thread_id,
            terminal_sequence,
        );
        let Some(connection) = self.reader().await? else {
            return Ok(None);
        };
        let Some(row) = connection.db.query_one_raw(statement(
            "SELECT kind,payload,digest,revision,last_write_seq FROM history_fact_receipts WHERE item_id=? ORDER BY revision DESC LIMIT 1",
            vec![id.clone().into()],
        )).await? else { return Ok(None); };
        let payload: String = row.try_get("", "payload")?;
        ensure!(
            row.try_get::<String>("", "kind")? == "parentReport"
                && row.try_get::<i64>("", "revision")? == 1
                && row.try_get::<i64>("", "last_write_seq")? == integer(terminal_sequence)?
                && row.try_get::<String>("", "digest")?
                    == pl_core::context::content_hash(payload.as_bytes()),
            crate::thread_assembler::review_dispatch::TerminalIntegrityError(
                "parent report receipt integrity or provenance mismatch"
            )
        );
        let message: ThreadMessage = serde_json::from_str(&payload)?;
        ensure!(
            message.id == id,
            crate::thread_assembler::review_dispatch::TerminalIntegrityError(
                "parent report receipt identity mismatch"
            )
        );
        ensure!(
            message.kind == pl_core::context::AgentMessageKind::Report
                && message.source_id == format!("studio.child:{}", self.state.thread_id)
                && message.payload.format() == "pl.studio.turn-report"
                && matches!(message.payload.version(), 1..=3),
            crate::thread_assembler::review_dispatch::TerminalIntegrityError(
                "parent report receipt source or encoding mismatch"
            )
        );
        Ok(Some(message))
    }
}

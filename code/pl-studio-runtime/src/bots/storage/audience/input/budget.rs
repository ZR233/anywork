//! One readiness call, one read snapshot and one cumulative source-record budget. Overlapping
//! selectors are deliberately charged again; no accepted prefix stands in for a complete proof.

use super::super::{ThreadOrigin, proof, read, unreadable};
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::bots::storage::{statement, storage, strict_watermark};
use sea_orm::{ConnectionTrait, DatabaseTransaction};

const SOURCE_RECORD_LIMIT: u64 = 16_384;

pub(super) struct SourceBudget<'tx> {
    pub(super) db: &'tx DatabaseTransaction,
    remaining: u64,
}

impl<'tx> SourceBudget<'tx> {
    pub(super) fn new(db: &'tx DatabaseTransaction) -> Self {
        Self {
            db,
            remaining: SOURCE_RECORD_LIMIT,
        }
    }

    pub(super) async fn proven_origin(
        &mut self,
        thread: &str,
        bot: &str,
    ) -> Result<Option<ThreadOrigin>, FeishuError> {
        self.charge(
            "SELECT COUNT(*) AS source_count FROM (
             SELECT 1 FROM bot_audience_origins WHERE thread_id=?1 LIMIT ?2)",
            thread,
        )
        .await?;
        let Some(origin) = read::read_origin(self.db, thread).await? else {
            return Ok(None);
        };
        // An incomplete origin is an error, not permission to scan unrelated empty-key history.
        if origin.project_id.is_empty()
            || origin.creation_id.is_empty()
            || origin.binding_revision == 0
        {
            return Err(unreadable());
        }
        self.provenance(thread, &origin.creation_id).await?;
        if !proof::check_known(self.db, &origin, bot).await? {
            return Err(unreadable());
        }
        Ok(Some(origin))
    }

    pub(super) async fn creating(&mut self, thread: &str) -> Result<(), FeishuError> {
        self.provenance(thread, thread).await?;
        self.authorizations(thread).await
    }

    pub(super) async fn authorizations(&mut self, thread: &str) -> Result<(), FeishuError> {
        self.charge(
            "SELECT COUNT(*) AS source_count FROM (
             SELECT 1 FROM bot_authorizations INDEXED BY bot_authorizations_thread
             WHERE thread_id=?1 LIMIT ?2)",
            thread,
        )
        .await
    }

    pub(super) async fn route(&mut self, chat: &str) -> Result<(), FeishuError> {
        self.charge(
            "SELECT COUNT(*) AS source_count FROM (
             SELECT 1 FROM thread_bindings WHERE chat_id=?1 LIMIT ?2)",
            chat,
        )
        .await
    }

    pub(super) async fn head(&mut self, chat: &str) -> Result<(), FeishuError> {
        self.charge(
            "SELECT COUNT(*) AS source_count FROM (
             SELECT 1 FROM bot_authorizations WHERE chat_id=?1
             ORDER BY generation DESC LIMIT MIN(1,?2))",
            chat,
        )
        .await
    }

    async fn provenance(&mut self, thread: &str, creation: &str) -> Result<(), FeishuError> {
        for sql in [
            "SELECT COUNT(*) AS source_count FROM (
             SELECT 1 FROM thread_bindings INDEXED BY bot_route_thread_lookup
             WHERE thread_id=?1 LIMIT ?2)",
            "SELECT COUNT(*) AS source_count FROM (
             SELECT 1 FROM binding_operations INDEXED BY bot_binding_thread_lookup
             WHERE thread_id=?1 LIMIT ?2)",
            "SELECT COUNT(*) AS source_count FROM (
             SELECT 1 FROM bot_card_streams INDEXED BY bot_card_thread_lookup
             WHERE thread_id=?1 LIMIT ?2)",
            // The outer card candidates have already been admitted. The validated work identity
            // is unique, so each lookup adds at most one source record, including missing joins.
            "SELECT COUNT(*) AS source_count FROM (
             SELECT 1 FROM bot_card_streams c INDEXED BY bot_card_thread_lookup
             WHERE c.thread_id=?1 AND EXISTS(
                 SELECT 1 FROM inbound_work w WHERE w.identity=c.identity) LIMIT ?2)",
        ] {
            self.charge(sql, thread).await?;
        }
        for sql in [
            "SELECT COUNT(*) AS source_count FROM (
             SELECT 1 FROM bot_audience_origins INDEXED BY bot_origin_creation_lookup
             WHERE creation_id=?1 LIMIT ?2)",
            "SELECT COUNT(*) AS source_count FROM (
             SELECT 1 FROM thread_bindings INDEXED BY bot_route_creation_lookup
             WHERE creation_id=?1 LIMIT ?2)",
            "SELECT COUNT(*) AS source_count FROM (
             SELECT 1 FROM binding_operations INDEXED BY bot_binding_creation_lookup
             WHERE creation_id=?1 LIMIT ?2)",
            "SELECT COUNT(*) AS source_count FROM (
             SELECT 1 FROM inbound_work INDEXED BY inbound_source_creation
             WHERE creation_id=?1 LIMIT ?2)",
            // Likewise, admit work candidates before the unique card-identity side. EXISTS
            // cannot visit unbounded unrelated cards or fan out a single work identity.
            "SELECT COUNT(*) AS source_count FROM (
             SELECT 1 FROM inbound_work w INDEXED BY inbound_source_creation
             WHERE w.creation_id=?1 AND EXISTS(
                 SELECT 1 FROM bot_card_streams c WHERE c.identity=w.identity) LIMIT ?2)",
        ] {
            self.charge(sql, creation).await?;
        }
        Ok(())
    }

    async fn charge(&mut self, sql: &'static str, scope: &str) -> Result<(), FeishuError> {
        // Only these fixed, indexed selectors reach this method. LIMIT belongs to the inner
        // candidate query, not the aggregate or the later conflict result. One sentinel proves
        // exhaustion; its unverified payload can never make the result Ready or Preparing.
        let sentinel = i64::try_from(self.remaining + 1).map_err(|_| unreadable())?;
        let row = self
            .db
            .query_one_raw(statement(sql, vec![scope.into(), sentinel.into()]))
            .await
            .map_err(storage)?
            .ok_or_else(unreadable)?;
        let records = strict_watermark(&row, "source_count")?;
        self.remaining = self.remaining.checked_sub(records).ok_or_else(|| {
            FeishuError::new(
                FeishuErrorKind::Unavailable,
                format!(
                    "bot input readiness exceeds {SOURCE_RECORD_LIMIT} related source records; operator handling required"
                ),
                false,
                None,
            )
        })?;
        Ok(())
    }
}

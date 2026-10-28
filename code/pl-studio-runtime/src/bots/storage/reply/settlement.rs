//! Unstarted retirement needs the original live worker; started results need only their attempt.

use super::*;
use crate::bots::send::verify_inbound_notice_record;
use crate::bots::storage::{
    MarkOutcome, MessageStage, WorkKeys, corrupt_send, write_send_progress_in,
};
use sea_orm::TransactionTrait;

impl BotStateStore {
    pub(in crate::bots) async fn retire_inbound_notice(
        &self,
        retirement: &mut InboundNoticeRetirement,
    ) -> Result<InboundNoticeSettlement, FeishuError> {
        if retirement.request_started {
            return Err(operation::conflict());
        }
        operation::validate_ready(&retirement.proof)?;
        let tx = self.db().await?.begin().await.map_err(storage)?;
        let mut record = operation::load(&tx, &retirement.record.operation_id)
            .await?
            .ok_or_else(corrupt_send)?;
        if !operation::same_attempt(&record, &retirement.record)? {
            return Ok(InboundNoticeSettlement::Superseded);
        }
        if operation::stage(&record)? == MessageStage::NotStarted {
            retirement.consumed = true;
            return Ok(InboundNoticeSettlement::AlreadySettled(record));
        }
        if retirement.consumed || operation::stage(&record)? != MessageStage::InFlight {
            return Ok(InboundNoticeSettlement::Superseded);
        }
        authority::work(&tx, &retirement.proof.identity).await?;
        if !authority::live(&tx, &retirement.proof.identity, &retirement.proof.worker_id).await? {
            return Ok(InboundNoticeSettlement::Superseded);
        }
        record.segments[0].message_stage = Some(MessageStage::NotStarted);
        verify_inbound_notice_record(&record, &retirement.proof.identity)?;
        write_send_progress_in(&tx, &record).await?;
        tx.commit().await.map_err(storage)?;
        retirement.consumed = true;
        Ok(InboundNoticeSettlement::Applied(record))
    }

    pub(in crate::bots) async fn settle_inbound_notice(
        &self,
        attempt: &mut ConfirmedInboundNoticeAttempt,
        progress: &InboundNoticeProgress,
    ) -> Result<InboundNoticeSettlement, FeishuError> {
        let original = &attempt.retirement;
        if !original.request_started {
            return Err(operation::conflict());
        }
        let tx = self.db().await?.begin().await.map_err(storage)?;
        let mut record = operation::load(&tx, &original.record.operation_id)
            .await?
            .ok_or_else(corrupt_send)?;
        if !operation::same_attempt(&record, &original.record)? {
            return Ok(InboundNoticeSettlement::Superseded);
        }
        if !operation::apply_message_progress(&mut record, progress)? {
            return Ok(InboundNoticeSettlement::AlreadySettled(record));
        }
        verify_inbound_notice_record(&record, &original.proof.identity)?;
        write_send_progress_in(&tx, &record).await?;
        tx.commit().await.map_err(storage)?;
        Ok(InboundNoticeSettlement::Applied(record))
    }
}

/// Joins the caller's work transaction. An observed pause is not a control-revision CAS.
pub(in crate::bots::storage) async fn finish_notice_pause_in<C: ConnectionTrait>(
    db: &C,
    keys: &WorkKeys<'_>,
    worker_id: &str,
    paused: &InboundNoticePaused,
    now: i64,
) -> Result<MarkOutcome, FeishuError> {
    let s = &paused.identity.source;
    if paused.worker_id != worker_id
        || keys.identity != inbound_identity(&s.bot_id, &s.chat_id, &s.message_id)
        || keys.bot_id != s.bot_id
        || keys.chat_id != s.chat_id
        || keys.message_id != s.message_id
        || !matches!(&paused.identity.authorization,NoticeAuthorization::Bound { start } if start.intent.authorization == paused.observed_control.id)
        || paused.observed_control.revision == 0
    {
        return Err(corrupt_send());
    }
    authority::work(db, &paused.identity).await?;
    if !authority::live(db, &paused.identity, worker_id).await? {
        return Ok(MarkOutcome::LostClaim);
    }
    let operation_id =
        crate::bots::send::inbound_notice_operation_id(&s.bot_id, &s.chat_id, &s.message_id)?;
    let record = operation::load(db, &operation_id)
        .await?
        .ok_or_else(corrupt_send)?;
    verify_inbound_notice_record(&record, &paused.identity)?;
    if operation::stage(&record)? != MessageStage::NotStarted {
        return Err(operation::conflict());
    }
    let (status, next_attempt_at, diagnostic) = match authority::scope(db, &paused.identity).await?
    {
        authority::Scope::Active(_) => ("pending", now, ""),
        authority::Scope::Paused(_) => {
            ("pending", now.checked_add(15).ok_or_else(corrupt_send)?, "")
        }
        authority::Scope::Closed => ("needs_attention", 0, "original notice scope is closed"),
    };
    let updated = db.execute_raw(statement(
        "UPDATE inbound_work SET status=?,next_attempt_at=?,diagnostic=?,claimed_by='',claimed_at=0,updated_at=?
         WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=?
           AND status='claimed' AND claimed_by=? AND claimed_at>?",
        vec![status.into(),next_attempt_at.into(),diagnostic.into(),now.into(),keys.identity.clone().into(),
            keys.bot_id.into(),keys.chat_id.into(),keys.message_id.into(),worker_id.into(),
            now.saturating_sub(INBOUND_CLAIM_TTL_SECONDS).into()],
    )).await.map_err(storage)?;
    Ok(if updated.rows_affected() == 1 {
        MarkOutcome::Applied
    } else {
        MarkOutcome::LostClaim
    })
}

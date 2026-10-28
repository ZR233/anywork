//! Each new attempt is minted exactly once, and only after a confirmed commit.

use super::*;
use crate::bots::send::{SendIdentity, inbound_notice_operation_id, verify_inbound_notice_record};
use crate::bots::storage::{
    FrozenInbound, MessageStage, corrupt_send, work_needs_recovery, write_send_progress_in,
};
use sea_orm::TransactionTrait;

impl BotStateStore {
    pub(in crate::bots) async fn read_inbound_notice(
        &self,
        inbound: &FrozenInbound,
        worker_id: &str,
    ) -> Result<InboundNoticeRead, FeishuError> {
        let tx = self.audience_db()?.begin().await.map_err(storage)?;
        authority::original(&tx, inbound).await?;
        let operation_id =
            inbound_notice_operation_id(&inbound.bot_id, &inbound.chat_id, &inbound.message_id)?;
        let Some(record) = operation::load(&tx, &operation_id).await? else {
            return Ok(InboundNoticeRead::Unavailable(
                InboundNoticeUnavailable::NoFrozenNotice,
            ));
        };
        if record.bot_id != inbound.bot_id || record.chat_id != inbound.chat_id {
            return Err(corrupt_send());
        }
        let SendIdentity::InboundNotice { identity, .. } = &record.identity else {
            if let Some(source) = &record.source {
                let original = format!(
                    "bot:{}:{}:{}",
                    inbound.bot_id, inbound.chat_id, inbound.message_id
                );
                if source.bot_id != inbound.bot_id
                    || source.chat_id != inbound.chat_id
                    || source.message_id != inbound.message_id
                    || source.app_id != inbound.app_id
                    || source.project_id != inbound.project_id
                    || source.creation_id != inbound.creation_id
                    || source.binding_revision != inbound.binding_revision
                    || source.open_id != inbound.open_id
                    || source.chat_kind != inbound.chat_kind
                    || source.original_input_id != original
                {
                    return Err(corrupt_send());
                }
            }
            return Ok(InboundNoticeRead::Receipt(record));
        };
        let work = authority::work(&tx, identity).await?;
        if work != *inbound {
            return Err(work_needs_recovery());
        }
        if operation::stage(&record)? != MessageStage::NotStarted {
            return Ok(InboundNoticeRead::Receipt(record));
        }
        let state = current(&tx, identity, worker_id).await?;
        let result = match state {
            InboundNoticeStartCheck::Ready => {
                let authority::Scope::Active(control) = authority::scope(&tx, identity).await?
                else {
                    return Err(corrupt_send());
                };
                let proof = InboundNoticeReady {
                    identity: identity.as_ref().clone(),
                    worker_id: worker_id.into(),
                    control,
                };
                InboundNoticeRead::Ready { record, proof }
            }
            InboundNoticeStartCheck::Paused(paused) => InboundNoticeRead::Paused(paused),
            InboundNoticeStartCheck::Unavailable(reason) => InboundNoticeRead::Unavailable(reason),
        };
        tx.commit().await.map_err(storage)?;
        Ok(result)
    }

    pub(in crate::bots) async fn begin_inbound_notice(
        &self,
        proof: &InboundNoticeReady,
    ) -> Result<InboundNoticeAdmission, FeishuError> {
        operation::validate_ready(proof)?;
        let tx = self.db().await?.begin().await.map_err(storage)?;
        let source = &proof.identity.source;
        let op = inbound_notice_operation_id(&source.bot_id, &source.chat_id, &source.message_id)?;
        let mut record = operation::load(&tx, &op).await?.ok_or_else(corrupt_send)?;
        verify_inbound_notice_record(&record, &proof.identity)?;
        authority::work(&tx, &proof.identity).await?;
        if operation::stage(&record)? != MessageStage::NotStarted {
            return Ok(InboundNoticeAdmission::Receipt(record));
        }
        match current(&tx, &proof.identity, &proof.worker_id).await? {
            InboundNoticeStartCheck::Ready => {}
            InboundNoticeStartCheck::Paused(paused) => {
                return Ok(InboundNoticeAdmission::Paused(paused));
            }
            InboundNoticeStartCheck::Unavailable(reason) => {
                return Ok(InboundNoticeAdmission::Unavailable(reason));
            }
        }
        let next = operation::counter(&record)?
            .checked_add(1)
            .ok_or_else(corrupt_send)?;
        record.segments[0].notice_attempt = Some(next);
        record.segments[0].message_stage = Some(MessageStage::InFlight);
        verify_inbound_notice_record(&record, &proof.identity)?;
        write_send_progress_in(&tx, &record).await?;
        let authority::Scope::Active(control) = authority::scope(&tx, &proof.identity).await?
        else {
            return Err(corrupt_send());
        };
        let retirement = InboundNoticeRetirement {
            proof: InboundNoticeReady {
                identity: proof.identity.clone(),
                worker_id: proof.worker_id.clone(),
                control,
            },
            record,
            request_started: false,
            consumed: false,
        };
        Ok(match tx.commit().await {
            Ok(()) => {
                InboundNoticeAdmission::Confirmed(ConfirmedInboundNoticeAttempt { retirement })
            }
            Err(error) => InboundNoticeAdmission::Unconfirmed {
                retirement,
                error: storage(error),
            },
        })
    }

    pub(in crate::bots) async fn verify_inbound_notice_start(
        &self,
        attempt: &ConfirmedInboundNoticeAttempt,
    ) -> Result<InboundNoticeStartCheck, FeishuError> {
        let original = &attempt.retirement;
        operation::validate_ready(&original.proof)?;
        if original.request_started || original.consumed {
            return Err(corrupt_send());
        }
        let tx = self.audience_db()?.begin().await.map_err(storage)?;
        let record = operation::load(&tx, &original.record.operation_id)
            .await?
            .ok_or_else(corrupt_send)?;
        if !operation::same_attempt(&record, &original.record)?
            || operation::stage(&record)? != MessageStage::InFlight
        {
            return Ok(InboundNoticeStartCheck::Unavailable(
                InboundNoticeUnavailable::SupersededAttempt,
            ));
        }
        authority::work(&tx, &original.proof.identity).await?;
        let result = current(&tx, &original.proof.identity, &original.proof.worker_id).await?;
        tx.commit().await.map_err(storage)?;
        Ok(result)
    }
}

async fn current<C: ConnectionTrait>(
    db: &C,
    identity: &InboundNoticeIdentity,
    worker: &str,
) -> Result<InboundNoticeStartCheck, FeishuError> {
    if !authority::live(db, identity, worker).await? {
        return Ok(InboundNoticeStartCheck::Unavailable(
            InboundNoticeUnavailable::LostClaim,
        ));
    }
    Ok(match authority::scope(db, identity).await? {
        authority::Scope::Active(_) => InboundNoticeStartCheck::Ready,
        authority::Scope::Paused(observed_control) => {
            InboundNoticeStartCheck::Paused(InboundNoticePaused {
                identity: identity.clone(),
                worker_id: worker.into(),
                observed_control,
            })
        }
        authority::Scope::Closed => {
            InboundNoticeStartCheck::Unavailable(InboundNoticeUnavailable::OriginalScopeClosed)
        }
    })
}

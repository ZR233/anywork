//! Only the original row is mutable. Immutable materials are verified by the send owner.

use super::*;
use crate::bots::send::{SendIdentity, verify_inbound_notice_record};
use crate::bots::storage::{MessageStage, SendRecordStatus, corrupt_send, send_record_from_row};

pub(in crate::bots::storage) fn validate_stored_notice_record(
    record: &SendRecord,
) -> Result<(), FeishuError> {
    match &record.identity {
        SendIdentity::InboundNotice { identity, .. } => {
            verify_inbound_notice_record(record, identity)
        }
        _ if record
            .segments
            .iter()
            .any(|fact| fact.notice_attempt.is_some()) =>
        {
            Err(corrupt_send())
        }
        _ => Ok(()),
    }
}

pub(super) async fn load<C: ConnectionTrait>(
    db: &C,
    operation_id: &str,
) -> Result<Option<SendRecord>, FeishuError> {
    db.query_one_raw(statement(
        "SELECT operation_id,bot_id,chat_id,content_hash,status,platform_message_ids,
                segment_facts,send_identity,send_source FROM send_operations WHERE operation_id=?",
        vec![operation_id.into()],
    ))
    .await
    .map_err(storage)?
    .map(send_record_from_row)
    .transpose()
}

pub(super) fn identity(record: &SendRecord) -> Result<&InboundNoticeIdentity, FeishuError> {
    let SendIdentity::InboundNotice { identity, .. } = &record.identity else {
        return Err(corrupt_send());
    };
    verify_inbound_notice_record(record, identity)?;
    Ok(identity)
}

pub(super) fn counter(record: &SendRecord) -> Result<u64, FeishuError> {
    record
        .segments
        .first()
        .and_then(|fact| fact.notice_attempt)
        .ok_or_else(corrupt_send)
}

pub(super) fn stage(record: &SendRecord) -> Result<MessageStage, FeishuError> {
    record
        .segments
        .first()
        .and_then(|fact| fact.message_stage)
        .ok_or_else(corrupt_send)
}

pub(super) fn same_attempt(
    record: &SendRecord,
    original: &SendRecord,
) -> Result<bool, FeishuError> {
    verify_inbound_notice_record(record, identity(original)?)?;
    Ok(counter(record)? == counter(original)?)
}

pub(super) fn validate_ready(proof: &InboundNoticeReady) -> Result<(), FeishuError> {
    let matches = match (&proof.identity.authorization, &proof.control) {
        (NoticeAuthorization::NoHead {}, NoticeControl::NoHead) => true,
        (NoticeAuthorization::Bound { start }, NoticeControl::Bound { reference }) => {
            reference.id == start.intent.authorization && reference.revision > 0
        }
        _ => false,
    };
    if !matches || proof.worker_id.is_empty() {
        return Err(corrupt_send());
    }
    Ok(())
}

/// Shared message-only merge. File upload prerequisites remain in the file caller; a notice
/// never invents an upload fact to reuse this merge. Terminal results cannot be weakened.
pub(in crate::bots::storage) fn apply_message_progress(
    record: &mut SendRecord,
    progress: &InboundNoticeProgress,
) -> Result<bool, FeishuError> {
    let fact = record.segments.first_mut().ok_or_else(corrupt_send)?;
    let before = fact.clone();
    match progress {
        InboundNoticeProgress::Sent { message_id } => {
            if message_id.trim().is_empty() {
                return Err(conflict());
            }
            match fact.message_stage {
                Some(MessageStage::Accepted)
                    if fact.platform_message_id.as_ref() == Some(message_id) =>
                {
                    return Ok(false);
                }
                Some(MessageStage::InFlight | MessageStage::Unknown) => {}
                _ => return Err(conflict()),
            }
            fact.message_stage = Some(MessageStage::Accepted);
            fact.platform_message_id = Some(message_id.clone());
            record.platform_message_ids = vec![message_id.clone()];
            fact.stop_reason = None;
            fact.diagnostic = None;
            fact.platform_diagnostic = None;
            fact.status = SendRecordStatus::Succeeded;
        }
        InboundNoticeProgress::Rejected { diagnostic } => {
            match fact.message_stage {
                Some(MessageStage::Rejected)
                    if fact.platform_diagnostic.as_ref() == Some(diagnostic) =>
                {
                    return Ok(false);
                }
                Some(MessageStage::InFlight | MessageStage::Unknown) => {}
                _ => return Err(conflict()),
            }
            fact.message_stage = Some(MessageStage::Rejected);
            fact.diagnostic = Some(diagnostic.message.clone());
            fact.platform_diagnostic = Some(diagnostic.clone());
            fact.status = SendRecordStatus::Rejected;
        }
        InboundNoticeProgress::Unknown { diagnostic } => {
            match fact.message_stage {
                Some(MessageStage::Accepted | MessageStage::Rejected) => return Ok(false),
                Some(MessageStage::InFlight | MessageStage::Unknown) => {}
                _ => return Err(conflict()),
            }
            fact.message_stage = Some(MessageStage::Unknown);
            if let Some(diagnostic) = diagnostic {
                fact.diagnostic = Some(diagnostic.message.clone());
                fact.platform_diagnostic = Some(diagnostic.clone());
            }
            fact.status = SendRecordStatus::Unknown;
        }
    }
    record.status = fact.status;
    Ok(*fact != before)
}

pub(super) fn conflict() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "message result conflicts with the original send stage",
        false,
        None,
    )
}

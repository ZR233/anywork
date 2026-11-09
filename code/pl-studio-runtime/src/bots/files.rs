//! File progress lives in the original send ledger, under the original reply owner.

use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::send::SendRate;
use super::storage::{BotStateStore, SendRecord, SendRecordStatus, SendSegmentFact};
use super::{
    SendAuthority,
    owner::BotRuntime,
    storage::{ClaimLease, FrozenInbound},
};
use crate::channel_output::{
    ChannelDeliveryResult, ChannelOutputBinding, ChannelOutputPort, PlatformMessageId,
};
use crate::channel_output::{
    ChannelError, ChannelRegistry, ChannelTarget, FileDelivery, UploadHandle,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio_util::sync::CancellationToken;

#[cfg(test)]
mod tests;

/// Source assembly for today's Feishu inbound owner. No credential access or HTTP
/// occurs here; another source chooses its own binding at this same boundary.
pub(super) fn feishu_reply_binding(
    runtime: BotRuntime,
    inbound: &FrozenInbound,
    worker_id: &str,
) -> ChannelOutputBinding {
    ChannelOutputBinding::new(
        ChannelTarget {
            adapter: "feishu".into(),
            account_id: inbound.bot_id.clone(),
            conversation_id: inbound.chat_id.clone(),
        },
        FeishuOutputPort {
            runtime,
            bot_id: inbound.bot_id.clone(),
            chat_id: inbound.chat_id.clone(),
            message_id: inbound.message_id.clone(),
            worker_id: worker_id.into(),
        },
    )
}

struct FeishuOutputPort {
    runtime: BotRuntime,
    bot_id: String,
    chat_id: String,
    message_id: String,
    worker_id: String,
}

impl FeishuOutputPort {
    async fn authorize(
        &self,
        target: &ChannelTarget,
        cancel: &CancellationToken,
    ) -> Result<(), ChannelDeliveryResult> {
        if cancel.is_cancelled()
            || target.adapter != "feishu"
            || target.account_id != self.bot_id
            || target.conversation_id != self.chat_id
        {
            return Err(ChannelDeliveryResult::Rejected {
                diagnostic: "file output source is cancelled or target conflicts with its binding"
                    .into(),
                retryable: false,
            });
        }
        let managed = self
            .runtime
            .managed(&self.bot_id)
            .await
            .map_err(preflight_error)?;
        match managed
            .store
            .renew_inbound_claim(
                &self.bot_id,
                &self.chat_id,
                &self.message_id,
                &self.worker_id,
            )
            .await
            .map_err(preflight_error)?
        {
            ClaimLease::Renewed => Ok(()),
            ClaimLease::LostClaim => Err(ChannelDeliveryResult::Rejected {
                diagnostic: "file output source no longer holds its inbound claim".into(),
                retryable: false,
            }),
        }
    }

    async fn failed_send(&self, operation: &str, error: FeishuError) -> ChannelDeliveryResult {
        if !error.acceptance_unknown() {
            return preflight_error(error);
        }
        // Credential/token preparation can fail before a durable send intent.
        // Preserve its retryability without labelling a known unattempted send Unknown.
        // Once an intent exists (or cannot be read), do not claim non-acceptance.
        if let Ok(managed) = self.runtime.managed(&self.bot_id).await
            && matches!(managed.store.send_exists(operation).await, Ok(false))
        {
            return preflight_error(error);
        }
        ChannelDeliveryResult::Unknown {
            diagnostic: error.to_string(),
        }
    }
}

fn preflight_error(error: FeishuError) -> ChannelDeliveryResult {
    ChannelDeliveryResult::Rejected {
        diagnostic: error.to_string(),
        retryable: error.retryable(),
    }
}

impl ChannelOutputPort for FeishuOutputPort {
    async fn send_caption(
        &self,
        target: &ChannelTarget,
        operation: &str,
        caption: &str,
        cancel: &CancellationToken,
    ) -> ChannelDeliveryResult {
        if let Err(result) = self.authorize(target, cancel).await {
            return result;
        }
        match self
            .runtime
            .send_message_as(
                operation.into(),
                target.account_id.clone(),
                target.conversation_id.clone(),
                caption.into(),
                "auto-reply",
                SendAuthority::AutoReply,
            )
            .await
        {
            Ok(result) => match result.status {
                pl_protocol::studio::BotSendStatus::Succeeded => ChannelDeliveryResult::Confirmed {
                    message_ids: result
                        .segments
                        .into_iter()
                        .filter_map(|segment| segment.platform_message_id)
                        .map(PlatformMessageId)
                        .collect(),
                },
                pl_protocol::studio::BotSendStatus::Unknown => ChannelDeliveryResult::Unknown {
                    diagnostic: "caption message acceptance is unknown".into(),
                },
                pl_protocol::studio::BotSendStatus::Rejected
                | pl_protocol::studio::BotSendStatus::Partial => ChannelDeliveryResult::Rejected {
                    diagnostic: "caption delivery was rejected or only partially confirmed".into(),
                    retryable: false,
                },
            },
            Err(error) => self.failed_send(operation, error).await,
        }
    }

    async fn send_file(
        &self,
        target: &ChannelTarget,
        operation: &str,
        file: &FileDelivery,
        bytes: Vec<u8>,
        cancel: &CancellationToken,
    ) -> ChannelDeliveryResult {
        if let Err(result) = self.authorize(target, cancel).await {
            return result;
        }
        match self
            .runtime
            .send_file_as(
                operation.into(),
                target.clone(),
                file.clone(),
                bytes,
                cancel,
            )
            .await
        {
            Ok(record) => match record.status {
                SendRecordStatus::Succeeded => ChannelDeliveryResult::Confirmed {
                    message_ids: record
                        .platform_message_ids
                        .into_iter()
                        .map(PlatformMessageId)
                        .collect(),
                },
                SendRecordStatus::Unknown => ChannelDeliveryResult::Unknown {
                    diagnostic: "file upload or message acceptance is unknown".into(),
                },
                SendRecordStatus::Rejected | SendRecordStatus::Partial => {
                    ChannelDeliveryResult::Rejected {
                        diagnostic: "file delivery was rejected or only partially confirmed".into(),
                        retryable: false,
                    }
                }
            },
            Err(error) => self.failed_send(operation, error).await,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) enum DeliveryStage {
    Planned,
    /// Durable before polling HTTP. A crash/cancellation never resets it to Planned.
    Unknown,
    Confirmed,
    Rejected,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct FileDeliveryFact {
    pub target: ChannelTarget,
    pub file: FileDelivery,
    pub upload: DeliveryStage,
    pub uploaded: Option<UploadHandle>,
    pub message: DeliveryStage,
}

pub(crate) fn initial_record(
    operation: String,
    target: ChannelTarget,
    file: FileDelivery,
) -> Result<SendRecord, FeishuError> {
    let fingerprint = serde_json::to_vec(&(&operation, &target, &file))
        .map_err(|error| local_error(error.to_string()))?;
    Ok(SendRecord {
        operation_id: operation.clone(),
        bot_id: target.account_id.clone(),
        chat_id: target.conversation_id.clone(),
        content_hash: hex::encode(Sha256::digest(fingerprint)),
        status: SendRecordStatus::Unknown,
        platform_message_ids: Vec::new(),
        segments: vec![SendSegmentFact {
            index: 0,
            uuid: operation,
            status: SendRecordStatus::Unknown,
            platform_message_id: None,
            diagnostic: None,
            file_delivery: Some(FileDeliveryFact {
                target,
                file,
                upload: DeliveryStage::Planned,
                uploaded: None,
                message: DeliveryStage::Planned,
            }),
        }],
        facts_complete: true,
    })
}

pub(crate) fn resumable(record: &SendRecord) -> bool {
    record
        .segments
        .first()
        .and_then(|fact| fact.file_delivery.as_ref())
        .is_some_and(|fact| {
            fact.upload == DeliveryStage::Planned
                || fact.upload == DeliveryStage::Confirmed && fact.message == DeliveryStage::Planned
        })
}

pub(crate) fn validate_record(record: &SendRecord) -> Result<(), FeishuError> {
    let [segment] = record.segments.as_slice() else {
        return Err(local_error(
            "file delivery must have exactly one ledger segment",
        ));
    };
    let fact = segment
        .file_delivery
        .as_ref()
        .ok_or_else(|| local_error("missing file delivery facts"))?;
    let expected = initial_record(
        record.operation_id.clone(),
        fact.target.clone(),
        fact.file.clone(),
    )?;
    if record.bot_id != expected.bot_id
        || record.chat_id != expected.chat_id
        || record.content_hash != expected.content_hash
        || segment.uuid != record.operation_id
        || fact.upload == DeliveryStage::Confirmed
            && fact
                .uploaded
                .as_ref()
                .is_none_or(|handle| handle.0.is_empty())
        || fact.message != DeliveryStage::Planned && fact.upload != DeliveryStage::Confirmed
        || record.status == SendRecordStatus::Succeeded && fact.message != DeliveryStage::Confirmed
    {
        return Err(local_error(
            "file delivery ledger fingerprint or stage conflict",
        ));
    }
    Ok(())
}

pub(crate) async fn deliver(
    registry: &ChannelRegistry,
    store: &BotStateStore,
    mut record: SendRecord,
    bytes: Vec<u8>,
    rate: &SendRate,
    cancel: &CancellationToken,
) -> Result<SendRecord, FeishuError> {
    validate_record(&record)?;
    if !resumable(&record) || cancel.is_cancelled() {
        return Ok(record);
    }
    let mut fact = record.segments[0]
        .file_delivery
        .clone()
        .ok_or_else(|| local_error("missing file delivery facts"))?;
    if fact.upload == DeliveryStage::Planned {
        if let Err(error) = fact.file.resource.verify(&bytes) {
            fact.upload = DeliveryStage::Rejected;
            apply_error(&mut record, ChannelError::Rejected(error.to_string()));
            record.segments[0].file_delivery = Some(fact);
            store.save_send(&record).await?;
            return Ok(record);
        }
        // No automatic retry after this durable write, even if the process stops
        // before the request reaches the peer.
        let permit = tokio::select! {
            biased;
            _ = cancel.cancelled() => return Ok(record),
            permit = rate.acquire() => permit,
        };
        fact.upload = DeliveryStage::Unknown;
        record.segments[0].file_delivery = Some(fact.clone());
        store.save_send(&record).await?;
        permit.start();
        let result = tokio::select! {
            biased;
            _ = cancel.cancelled() => Err(ChannelError::Unknown("upload cancelled after intent".into())),
            result = registry.upload(&fact.target, &record.operation_id, &fact.file, bytes) => result,
        };
        match result {
            Ok(handle) => {
                fact.upload = DeliveryStage::Confirmed;
                fact.uploaded = Some(handle);
            }
            Err(error) => {
                if matches!(error, ChannelError::Rejected(_)) {
                    fact.upload = DeliveryStage::Rejected;
                }
                apply_error(&mut record, error);
                record.segments[0].file_delivery = Some(fact);
                store.save_send(&record).await?;
                return Ok(record);
            }
        }
        record.segments[0].file_delivery = Some(fact.clone());
        // Upload confirmation is durable independently of the send intent.
        store.save_send(&record).await?;
    }
    if cancel.is_cancelled() {
        return Ok(record);
    }
    let handle = fact
        .uploaded
        .as_ref()
        .ok_or_else(|| local_error("confirmed upload lacks adapter handle"))?;
    let permit = tokio::select! {
        biased;
        _ = cancel.cancelled() => return Ok(record),
        permit = rate.acquire() => permit,
    };
    fact.message = DeliveryStage::Unknown;
    record.segments[0].file_delivery = Some(fact.clone());
    store.save_send(&record).await?;
    permit.start();
    let result = tokio::select! {
        biased;
        _ = cancel.cancelled() => Err(ChannelError::Unknown("message cancelled after intent".into())),
        result = registry.send(&fact.target, &record.operation_id, &fact.file, handle) => result,
    };
    match result {
        Ok(id) => {
            fact.message = DeliveryStage::Confirmed;
            record.status = SendRecordStatus::Succeeded;
            record.platform_message_ids = vec![id.0.clone()];
            record.segments[0].status = SendRecordStatus::Succeeded;
            record.segments[0].platform_message_id = Some(id.0);
        }
        Err(error) => {
            if matches!(error, ChannelError::Rejected(_)) {
                fact.message = DeliveryStage::Rejected;
            }
            apply_error(&mut record, error);
        }
    }
    record.segments[0].file_delivery = Some(fact);
    // Drained even on cancellation: the caller owns this future until completion.
    store.save_send(&record).await?;
    Ok(record)
}

fn apply_error(record: &mut SendRecord, error: ChannelError) {
    record.status = match &error {
        ChannelError::Rejected(_) => SendRecordStatus::Rejected,
        ChannelError::Unknown(_) => SendRecordStatus::Unknown,
    };
    record.segments[0].status = record.status;
    record.segments[0].diagnostic = Some(error.to_string());
}

pub(crate) fn local_error(message: impl Into<String>) -> FeishuError {
    FeishuError::new(FeishuErrorKind::Unavailable, message, false, None)
}

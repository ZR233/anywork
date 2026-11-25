use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::bots::send::{SendPermit, SendRate};
use crate::bots::storage::{BotStateStore, SendRecord, SendRecordStatus, SendSegmentFact};
use crate::channel_output::{
    ChannelError, ChannelRegistry, ChannelTarget, FileDelivery, UploadHandle,
};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::future::Future;
use tokio_util::sync::CancellationToken;

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
    record: SendRecord,
    bytes: Vec<u8>,
    rate: &SendRate,
    cancel: &CancellationToken,
) -> Result<SendRecord, FeishuError> {
    FileDeliveryDriver {
        registry,
        store,
        rate,
        cancel,
    }
    .deliver(record, bytes)
    .await
}

struct FileDeliveryDriver<'a> {
    registry: &'a ChannelRegistry,
    store: &'a BotStateStore,
    rate: &'a SendRate,
    cancel: &'a CancellationToken,
}

#[derive(Clone, Copy)]
enum Stage {
    Upload,
    Message,
}

impl Stage {
    fn intent(self, fact: &mut FileDeliveryFact) -> &mut DeliveryStage {
        match self {
            Self::Upload => &mut fact.upload,
            Self::Message => &mut fact.message,
        }
    }

    fn cancelled(self) -> ChannelError {
        let detail = match self {
            Self::Upload => "upload cancelled after intent",
            Self::Message => "message cancelled after intent",
        };
        ChannelError::Unknown(detail.into())
    }
}

impl FileDeliveryDriver<'_> {
    async fn deliver(
        &self,
        mut record: SendRecord,
        bytes: Vec<u8>,
    ) -> Result<SendRecord, FeishuError> {
        validate_record(&record)?;
        if !resumable(&record) || self.cancel.is_cancelled() {
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
                self.save_progress(&mut record, fact).await?;
                return Ok(record);
            }
            let Some(permit) = self.begin(&mut record, &mut fact, Stage::Upload).await? else {
                return Ok(record);
            };
            permit.start();
            let response = self
                .await_stage(
                    Stage::Upload,
                    self.registry
                        .upload(&fact.target, &record.operation_id, &fact.file, bytes),
                )
                .await;
            if let Some(handle) = record_stage(&mut record, &mut fact, Stage::Upload, response) {
                fact.uploaded = Some(handle);
                self.save_progress(&mut record, fact.clone()).await?;
            } else {
                self.save_progress(&mut record, fact).await?;
                return Ok(record);
            }
        }
        let Some(permit) = self.begin(&mut record, &mut fact, Stage::Message).await? else {
            return Ok(record);
        };
        let handle = fact
            .uploaded
            .as_ref()
            .ok_or_else(|| local_error("confirmed upload lacks adapter handle"))?;
        permit.start();
        let response = self
            .await_stage(
                Stage::Message,
                self.registry
                    .send(&fact.target, &record.operation_id, &fact.file, handle),
            )
            .await;
        if let Some(id) = record_stage(&mut record, &mut fact, Stage::Message, response) {
            record.status = SendRecordStatus::Succeeded;
            record.platform_message_ids = vec![id.0.clone()];
            record.segments[0].status = SendRecordStatus::Succeeded;
            record.segments[0].platform_message_id = Some(id.0);
        }
        // Drained even on cancellation: the caller owns this future until completion.
        self.save_progress(&mut record, fact).await?;
        Ok(record)
    }

    async fn begin(
        &self,
        record: &mut SendRecord,
        fact: &mut FileDeliveryFact,
        stage: Stage,
    ) -> Result<Option<SendPermit<'_>>, FeishuError> {
        let permit = tokio::select! {
            biased;
            _ = self.cancel.cancelled() => return Ok(None),
            permit = self.rate.acquire() => permit,
        };
        // A durable intent fences replay even if the process stops before HTTP.
        *stage.intent(fact) = DeliveryStage::Unknown;
        self.save_progress(record, fact.clone()).await?;
        Ok(Some(permit))
    }

    async fn await_stage<T>(
        &self,
        stage: Stage,
        request: impl Future<Output = Result<T, ChannelError>>,
    ) -> Result<T, ChannelError> {
        tokio::select! {
            biased;
            _ = self.cancel.cancelled() => Err(stage.cancelled()),
            result = request => result,
        }
    }

    async fn save_progress(
        &self,
        record: &mut SendRecord,
        fact: FileDeliveryFact,
    ) -> Result<(), FeishuError> {
        record.segments[0].file_delivery = Some(fact);
        self.store.save_send(record).await
    }
}

fn record_stage<T>(
    record: &mut SendRecord,
    fact: &mut FileDeliveryFact,
    stage: Stage,
    response: Result<T, ChannelError>,
) -> Option<T> {
    match response {
        Ok(result) => {
            *stage.intent(fact) = DeliveryStage::Confirmed;
            Some(result)
        }
        Err(error) => {
            if matches!(error, ChannelError::Rejected(_)) {
                *stage.intent(fact) = DeliveryStage::Rejected;
            }
            apply_error(record, error);
            None
        }
    }
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

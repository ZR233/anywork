//! One claimed operation owns upload/message facts. Local stops never invent platform rejection.
use super::BotRuntime;
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::protocol::http::{PostFailure, PreparedPost};
use super::protocol::im::{FeishuIm, MessageContent};
use super::send::{SendContent, SendIdentity};
use super::storage::{BotStateStore, MessageStage, SendRecord, SendRecordStatus, UploadFact};
use crate::resource_store::FileResourceStore;
use pl_core::context::{ResourceReader, ResourceReference};
use pl_protocol::studio::*;
use tokio_util::sync::CancellationToken;

impl BotRuntime {
    pub(super) fn send_resources(&self, bot_id: &str) -> FileResourceStore {
        FileResourceStore::beneath(
            self.inner.paths.home().to_owned(),
            self.inner.paths.bot_dir(bot_id).join("send-resources"),
        )
    }

    /// Covers source/read/Arc/multipart copies without putting file bytes in occupancy.
    pub(super) fn reserve_send_bytes(
        &self,
        bytes: usize,
    ) -> Result<tokio::sync::OwnedSemaphorePermit, FeishuError> {
        let amount = bytes
            .checked_mul(3)
            .and_then(|n| u32::try_from(n).ok())
            .ok_or_else(super::occupancy::freeze_budget_error)?;
        self.inner
            .send_bytes
            .clone()
            .try_acquire_many_owned(amount)
            .map_err(|_| {
                FeishuError::new(
                    FeishuErrorKind::Busy,
                    "outgoing file byte budget is full",
                    true,
                    None,
                )
            })
    }

    pub(super) async fn deliver_claimed(
        &self,
        token: &str,
        store: &BotStateStore,
        record: SendRecord,
        cancel: &CancellationToken,
    ) -> Result<BotSendResult, FeishuError> {
        Delivery {
            runtime: self,
            token,
            store,
            record,
            cancel,
        }
        .run()
        .await
    }
}

struct Delivery<'a> {
    runtime: &'a BotRuntime,
    token: &'a str,
    store: &'a BotStateStore,
    record: SendRecord,
    cancel: &'a CancellationToken,
}

#[derive(Clone, Copy)]
enum Action {
    Upload,
    Message,
}

enum Attempt<T> {
    Response(Result<T, PostFailure>),
    Cancelled,
}

impl Delivery<'_> {
    async fn run(mut self) -> Result<BotSendResult, FeishuError> {
        let im = FeishuIm::new(self.runtime.inner.http.clone());
        for index in 0..self.record.segments.len() {
            if self.runtime.check_send_active(self.cancel).is_err() {
                self.local_stop(
                    index,
                    BotSendStopReason::Cancelled,
                    "send cancelled before the next network request",
                );
                self.persist().await?;
                return Ok(replay_send(self.record));
            }
            let content = self.record.segments[index].content.clone();
            let prepared = match content {
                Some(SendContent::Markdown { text }) => im.prepare_content(
                    self.token,
                    &self.record.chat_id,
                    MessageContent::Markdown(&text),
                    &self.record.segments[index].uuid,
                ),
                Some(SendContent::File {
                    upload_filename,
                    resource,
                    ..
                }) => {
                    let Some(file_key) = self.upload(index, &upload_filename, resource).await?
                    else {
                        return Ok(replay_send(self.record));
                    };
                    im.prepare_content(
                        self.token,
                        &self.record.chat_id,
                        MessageContent::File {
                            file_key: &file_key,
                        },
                        &self.record.segments[index].uuid,
                    )
                }
                None => Err(FeishuError::new(
                    FeishuErrorKind::Protocol,
                    "new send is missing frozen content",
                    false,
                    None,
                )),
            };
            let prepared = match prepared {
                Ok(prepared) => prepared,
                Err(error) => {
                    self.local_stop(
                        index,
                        BotSendStopReason::LocalFailure,
                        &error.diagnostic().message,
                    );
                    self.persist().await?;
                    return Ok(replay_send(self.record));
                }
            };
            if !self.begin(index, Action::Message).await? {
                return Ok(replay_send(self.record));
            }
            match attempt(
                im.send_prepared(prepared),
                self.cancel,
                &self.runtime.inner.reply_cancel,
            )
            .await
            {
                Attempt::Response(Ok(sent)) => {
                    self.record
                        .platform_message_ids
                        .push(sent.message_id.clone());
                    let fact = &mut self.record.segments[index];
                    fact.status = SendRecordStatus::Succeeded;
                    fact.message_stage = Some(MessageStage::Accepted);
                    fact.platform_message_id = Some(sent.message_id);
                    self.record.status = if index + 1 == self.record.segments.len() {
                        SendRecordStatus::Succeeded
                    } else {
                        SendRecordStatus::Partial
                    };
                }
                Attempt::Response(Err(error)) => {
                    self.platform_failure(index, Action::Message, error);
                    self.persist().await?;
                    return Ok(replay_send(self.record));
                }
                Attempt::Cancelled => {
                    self.set_unknown(index, Action::Message);
                    self.local_stop(
                        index,
                        BotSendStopReason::Cancelled,
                        "message request cancelled in flight; result is unknown",
                    );
                    self.persist().await?;
                    return Ok(replay_send(self.record));
                }
            }
            self.persist().await?;
        }
        let mut result = replay_send(self.record);
        result.receipt.disposition = CommandDisposition::Applied;
        Ok(result)
    }

    async fn upload(
        &mut self,
        index: usize,
        filename: &str,
        resource: ResourceReference,
    ) -> Result<Option<String>, FeishuError> {
        // All local IO, byte/MIME checks and request construction precede InFlight.
        let prepared = self.prepare_upload(filename, &resource).await;
        let (prepared, _bytes_budget) = match prepared {
            Ok(prepared) => prepared,
            Err(error) => {
                let reason = if self.runtime.check_send_active(self.cancel).is_err() {
                    BotSendStopReason::Cancelled
                } else {
                    BotSendStopReason::LocalFailure
                };
                self.local_stop(index, reason, &error.diagnostic().message);
                self.persist().await?;
                return Ok(None);
            }
        };
        if !self.begin(index, Action::Upload).await? {
            return Ok(None);
        }
        match attempt(
            self.runtime.inner.http.upload_file(prepared),
            self.cancel,
            &self.runtime.inner.reply_cancel,
        )
        .await
        {
            Attempt::Response(Ok(file_key)) => {
                self.record.segments[index].upload = Some(UploadFact::Accepted {
                    file_key: file_key.clone(),
                });
                self.persist().await?;
                Ok(Some(file_key))
            }
            Attempt::Response(Err(error)) => {
                self.platform_failure(index, Action::Upload, error);
                self.persist().await?;
                Ok(None)
            }
            Attempt::Cancelled => {
                self.set_unknown(index, Action::Upload);
                self.local_stop(
                    index,
                    BotSendStopReason::Cancelled,
                    "upload request cancelled in flight; result is unknown",
                );
                self.persist().await?;
                Ok(None)
            }
        }
    }

    async fn prepare_upload(
        &self,
        filename: &str,
        resource: &ResourceReference,
    ) -> Result<(PreparedPost, tokio::sync::OwnedSemaphorePermit), FeishuError> {
        let budget = self
            .runtime
            .reserve_send_bytes(resource.byte_len() as usize)?;
        let bytes = self
            .runtime
            .send_resources(&self.record.bot_id)
            .read(resource.clone(), self.cancel.clone())
            .await
            .map_err(|_| {
                FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    "retained send resource is unavailable or invalid",
                    false,
                    None,
                )
            })?;
        let request = self.runtime.inner.http.prepare_file_upload(
            self.token,
            filename,
            resource.media_type(),
            bytes,
        )?;
        Ok((request, budget))
    }

    async fn begin(&mut self, index: usize, action: Action) -> Result<bool, FeishuError> {
        if self.runtime.check_send_active(self.cancel).is_err() {
            self.local_stop(
                index,
                BotSendStopReason::Cancelled,
                "send cancelled before the next network request",
            );
            self.persist().await?;
            return Ok(false);
        }
        match action {
            Action::Upload => self.record.segments[index].upload = Some(UploadFact::InFlight),
            Action::Message => {
                self.record.segments[index].message_stage = Some(MessageStage::InFlight)
            }
        }
        if let Err(error) = self.persist().await {
            self.set_not_started(index, action);
            self.local_stop(
                index,
                BotSendStopReason::LocalFailure,
                "could not persist request admission; network request was not started",
            );
            return Err(error.with_observed_send(replay_send(self.record.clone())));
        }
        // Cancellation during the durable admission wait is still before HTTP execution.
        if self.runtime.check_send_active(self.cancel).is_err() {
            self.set_not_started(index, action);
            self.local_stop(
                index,
                BotSendStopReason::Cancelled,
                "send cancelled before the next network request",
            );
            self.persist().await?;
            return Ok(false);
        }
        Ok(true)
    }

    fn set_not_started(&mut self, index: usize, action: Action) {
        match action {
            Action::Upload => self.record.segments[index].upload = Some(UploadFact::NotStarted),
            Action::Message => {
                self.record.segments[index].message_stage = Some(MessageStage::NotStarted)
            }
        }
    }

    fn set_unknown(&mut self, index: usize, action: Action) {
        match action {
            Action::Upload => self.record.segments[index].upload = Some(UploadFact::Unknown),
            Action::Message => {
                self.record.segments[index].message_stage = Some(MessageStage::Unknown)
            }
        }
    }

    fn local_stop(&mut self, index: usize, reason: BotSendStopReason, message: &str) {
        for fact in self.record.segments.iter_mut().skip(index) {
            fact.stop_reason = Some(reason);
            fact.diagnostic = Some(message.into());
            fact.status = if fact_unknown(fact) {
                SendRecordStatus::Unknown
            } else {
                SendRecordStatus::Rejected
            };
        }
        self.aggregate_stop();
    }

    fn platform_failure(&mut self, index: usize, action: Action, failure: PostFailure) {
        let (unknown, error) = match failure {
            PostFailure::Rejected(error) => (false, error),
            PostFailure::Unknown(error) => (true, error),
        };
        let fact = &mut self.record.segments[index];
        match action {
            Action::Upload => {
                fact.upload = Some(if unknown {
                    UploadFact::Unknown
                } else {
                    UploadFact::Rejected
                })
            }
            Action::Message => {
                fact.message_stage = Some(if unknown {
                    MessageStage::Unknown
                } else {
                    MessageStage::Rejected
                })
            }
        }
        fact.status = if unknown {
            SendRecordStatus::Unknown
        } else {
            SendRecordStatus::Rejected
        };
        fact.diagnostic = Some(error.diagnostic().message);
        fact.platform_diagnostic = Some(error.diagnostic());
        self.aggregate_stop();
    }

    fn aggregate_stop(&mut self) {
        self.record.status = if self.record.segments.iter().any(fact_unknown) {
            SendRecordStatus::Unknown
        } else if self.record.platform_message_ids.is_empty() {
            SendRecordStatus::Rejected
        } else {
            SendRecordStatus::Partial
        };
    }

    async fn persist(&self) -> Result<(), FeishuError> {
        self.store
            .save_send(&self.record)
            .await
            .map_err(|error| error.with_observed_send(replay_send(self.record.clone())))
    }
}

// Poll the prepared HTTP action first. Once polled, cancellation is an uncertain attempted POST;
// cancellations before execution are handled by begin(), retaining NotStarted.
async fn attempt<T>(
    future: impl std::future::Future<Output = Result<T, PostFailure>>,
    cancel: &CancellationToken,
    runtime_cancel: &CancellationToken,
) -> Attempt<T> {
    tokio::select! { biased; result = future => Attempt::Response(result), _ = cancel.cancelled() => Attempt::Cancelled, _ = runtime_cancel.cancelled() => Attempt::Cancelled }
}

fn fact_unknown(fact: &super::storage::SendSegmentFact) -> bool {
    matches!(
        fact.upload,
        Some(UploadFact::InFlight | UploadFact::Unknown)
    ) || matches!(
        fact.message_stage,
        Some(MessageStage::InFlight | MessageStage::Unknown)
    )
}

pub(super) fn replay_send(existing: SendRecord) -> BotSendResult {
    let uncertain_stage = existing.segments.iter().any(|fact| {
        fact.upload == Some(UploadFact::InFlight)
            || fact.message_stage == Some(MessageStage::InFlight)
    });
    let facts_complete = existing.facts_complete;
    let is_file_operation = matches!(existing.identity, SendIdentity::File { .. });
    let operation_id = existing.operation_id;
    BotSendResult {
        operation_id: operation_id.clone(),
        bot_id: existing.bot_id,
        chat_id: existing.chat_id,
        status: if uncertain_stage {
            BotSendStatus::Unknown
        } else {
            product_status(existing.status)
        },
        segments: existing
            .segments
            .into_iter()
            .map(|fact| {
                let in_flight = matches!(fact.upload, Some(UploadFact::InFlight))
                    || fact.message_stage == Some(MessageStage::InFlight);
                let upload_stage = match &fact.upload {
                    Some(UploadFact::NotStarted) => Some(BotSendStage::NotStarted),
                    Some(UploadFact::Accepted { .. }) => Some(BotSendStage::Accepted),
                    Some(UploadFact::Rejected) => Some(BotSendStage::Rejected),
                    Some(UploadFact::InFlight | UploadFact::Unknown) => Some(BotSendStage::Unknown),
                    None if is_file_operation
                        || matches!(fact.content, Some(SendContent::File { .. })) =>
                    {
                        Some(BotSendStage::Unknown)
                    }
                    None => None,
                };
                let message_stage = match fact.message_stage {
                    Some(MessageStage::NotStarted) => BotSendStage::NotStarted,
                    Some(MessageStage::Accepted) => BotSendStage::Accepted,
                    Some(MessageStage::Rejected) => BotSendStage::Rejected,
                    Some(MessageStage::InFlight | MessageStage::Unknown) => BotSendStage::Unknown,
                    None if fact
                        .platform_message_id
                        .as_ref()
                        .is_some_and(|id| !id.is_empty()) =>
                    {
                        BotSendStage::Accepted
                    }
                    None => BotSendStage::Unknown,
                };
                let diagnostic = fact.platform_diagnostic.or_else(|| {
                    let message = if in_flight {
                        Some("上传或消息请求结果未知；不会自动重新 POST".into())
                    } else {
                        fact.diagnostic
                    }?;
                    Some(BotDiagnostic {
                        code: "sendSegment".into(),
                        message,
                        retryable: false,
                        platform_code: None,
                        guidance: (!facts_complete).then(|| "legacySegmentFactsUnproven".into()),
                    })
                });
                BotSendSegment {
                    index: fact.index,
                    status: if in_flight {
                        BotSendStatus::Unknown
                    } else {
                        product_status(fact.status)
                    },
                    upload_stage,
                    message_stage,
                    stop_reason: fact.stop_reason,
                    platform_message_id: fact.platform_message_id,
                    diagnostic,
                }
            })
            .collect(),
        receipt: StudioCommandReceipt {
            operation_id,
            disposition: CommandDisposition::NoChange,
            targets: Vec::new(),
            effect: CommandEffectPoint::Immediate,
            effective: true,
            durable: true,
            requires_identity_observation: false,
        },
    }
}

fn product_status(status: SendRecordStatus) -> BotSendStatus {
    match status {
        SendRecordStatus::Succeeded => BotSendStatus::Succeeded,
        SendRecordStatus::Partial => BotSendStatus::Partial,
        SendRecordStatus::Rejected => BotSendStatus::Rejected,
        SendRecordStatus::Unknown => BotSendStatus::Unknown,
    }
}

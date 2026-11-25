use crate::bots::protocol::error::FeishuError;
use crate::bots::{
    SendAuthority,
    owner::BotRuntime,
    storage::{ClaimLease, FrozenInbound, SendRecordStatus},
};
use crate::channel_output::{
    ChannelDeliveryResult, ChannelOutputBinding, ChannelOutputPort, ChannelTarget, FileDelivery,
    PlatformMessageId,
};
use tokio_util::sync::CancellationToken;

/// Source assembly for today's Feishu inbound owner. No credential access or HTTP
/// occurs here; another source chooses its own binding at this same boundary.
pub(in crate::bots) fn feishu_reply_binding(
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
    fn deferred_file_limit(&self) -> Option<u64> {
        Some(crate::bots::protocol::files::FILE_UPLOAD_MAX_BYTES)
    }

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
                crate::BotSendStatus::Succeeded => ChannelDeliveryResult::Confirmed {
                    message_ids: result
                        .segments
                        .into_iter()
                        .filter_map(|segment| segment.platform_message_id)
                        .map(PlatformMessageId)
                        .collect(),
                },
                crate::BotSendStatus::Unknown => ChannelDeliveryResult::Unknown {
                    diagnostic: "caption message acceptance is unknown".into(),
                },
                crate::BotSendStatus::Rejected | crate::BotSendStatus::Partial => {
                    ChannelDeliveryResult::Rejected {
                        diagnostic: "caption delivery was rejected or only partially confirmed"
                            .into(),
                        retryable: false,
                    }
                }
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

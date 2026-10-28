//! Authorized inbound resource download and handoff to the existing attachment admission.
use super::{
    BotRuntime,
    inbound::InboundAttachment,
    protocol::error::{FeishuError, FeishuErrorKind},
};
use crate::studio::StudioRuntime;

impl BotRuntime {
    pub(crate) async fn prepare_inbound_attachments(
        &self,
        runtime: &StudioRuntime,
        bot_id: &str,
        _thread_id: &str,
        message_id: &str,
        attachments: &[InboundAttachment],
        cancel: &tokio_util::sync::CancellationToken,
    ) -> Result<Vec<String>, FeishuError> {
        let resource_count = attachments
            .iter()
            .filter(|item| item.key().is_some())
            .count();
        if resource_count == 0 {
            return Ok(Vec::new());
        }
        if resource_count > pl_protocol::studio::ATTACHMENT_MAX_BATCH_FILES {
            return Err(media_error("消息附件超过批次文件数预算"));
        }
        let managed = self.managed(bot_id).await?;
        let _download_budget = self
            .inner
            .download_batch
            .clone()
            .try_acquire_owned()
            .map_err(|_| {
                FeishuError::new(
                    FeishuErrorKind::Busy,
                    "inbound resource batch byte budget is full",
                    true,
                    None,
                )
            })?;
        let config = managed.config.lock().await.clone();
        let token = self.token(&managed, &config).await?;
        let mut files = Vec::with_capacity(resource_count);
        let mut remaining = pl_protocol::studio::ATTACHMENT_MAX_BATCH_BYTES;
        for attachment in attachments {
            if cancel.is_cancelled() {
                return Err(media_error("附件下载已取消"));
            }
            let (kind, filename) = match attachment {
                InboundAttachment::Image { .. } => ("image", "image".to_owned()),
                InboundAttachment::File { filename, .. } => {
                    let name = std::path::Path::new(filename)
                        .file_name()
                        .and_then(|name| name.to_str())
                        .filter(|name| !name.is_empty() && *name != "." && *name != "..")
                        .ok_or_else(|| media_error("消息附件缺少有效文件名"))?;
                    let safe: String = name
                        .chars()
                        .map(|ch| {
                            if ch.is_control() || "<>:\"/\\|?*".contains(ch) {
                                '_'
                            } else {
                                ch
                            }
                        })
                        .collect();
                    ("file", safe)
                }
                // Unknown post elements already have explicit inline notices. They never stand
                // in for a file and must not discard the other real resources in this batch.
                InboundAttachment::Unsupported { .. } => continue,
            };
            let key = attachment
                .key()
                .ok_or_else(|| media_error("资源不支持下载"))?;
            let bytes = tokio::select! {
                    _ = cancel.cancelled() => return Err(media_error("附件下载已取消")),
                result = self.inner.http.download_message_resource(&token, message_id, key, kind, remaining) => result?,
            };
            remaining = remaining
                .checked_sub(bytes.len() as u64)
                .ok_or_else(|| media_error("消息附件超过批次字节预算"))?;
            files.push((filename, bytes));
        }
        let drafts = runtime
            .admit_attachment_bytes(files)
            .await
            .map_err(|error| {
                FeishuError::history_read("inbound attachment draft admission failed", error)
            })?;
        Ok(drafts
            .drafts
            .into_iter()
            .map(|draft| draft.draft_id)
            .collect())
    }
}

fn media_error(message: impl Into<String>) -> FeishuError {
    FeishuError::new(FeishuErrorKind::Rejected, message, false, None)
}

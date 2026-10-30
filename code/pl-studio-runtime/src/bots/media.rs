//! Authorized inbound resource download and handoff to the existing attachment admission.
use super::{
    BotRuntime,
    inbound::InboundAttachment,
    protocol::error::{FeishuError, FeishuErrorKind},
};
use crate::studio::StudioRuntime;
use sha2::{Digest, Sha256};

impl BotRuntime {
    pub(crate) async fn prepare_inbound_attachments(
        &self,
        runtime: &StudioRuntime,
        bot_id: &str,
        thread_id: &str,
        message_id: &str,
        attachments: &[InboundAttachment],
        cancel: &tokio_util::sync::CancellationToken,
    ) -> Result<Vec<String>, FeishuError> {
        if attachments.is_empty() {
            return Ok(Vec::new());
        }
        let managed = self.managed(bot_id).await?;
        let config = managed.config.lock().await.clone();
        let token = self.token(&managed, &config).await?;
        let uploads = self
            .inner
            .paths
            .bot_dir(bot_id)
            .join("workspace")
            .join(pl_tool::workspace::SessionFiles::new(thread_id).uploads())
            .join(hex::encode(Sha256::digest(message_id.as_bytes())));
        let mut sources = Vec::new();
        for attachment in attachments {
            if cancel.is_cancelled() {
                return Err(media_error("附件下载已取消"));
            }
            let (kind, filename) = match attachment {
                InboundAttachment::Image { .. } => ("image", "image.png".to_owned()),
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
                    ("file", format!("file-{safe}"))
                }
            };
            let path = uploads
                .join(hex::encode(Sha256::digest(attachment.key().as_bytes())))
                .join(filename);
            if !path.is_file() {
                tokio::select! {
                    _ = cancel.cancelled() => return Err(media_error("附件下载已取消")),
                    result = self.inner
                    .http
                    .download_message_resource(&token, message_id, attachment.key(), kind, &path)
                    => result?,
                }
            }
            sources.push(
                pl_protocol::studio::StudioAttachmentDraftSource::LocalFile {
                    path: path.to_string_lossy().into_owned(),
                },
            );
        }
        let drafts = runtime
            .prepare_bot_attachment_drafts(thread_id, sources)
            .await
            .map_err(|error| media_error(error.to_string()))?;
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

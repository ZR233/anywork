//! Feishu IM multipart upload and image/file message adapter.
//!
//! Contract sources: official IM image/create, file/create and message/create;
//! https://open.feishu.cn/document/server-docs/im-v1/image/create
//! https://open.feishu.cn/document/server-docs/im-v1/file/create
//! Upload limits are 10 MiB for images and 30 MiB for files, not download limits.
//! Official Node SDK `code-gen/projects/im.ts`, revision
//! `b188be60134d409b61259546bcf69c731d2b0b7c`, lines 4750-4785 and 10737-10770
//! confirms `image_type=message`, `file_type=stream`, form names and limits.

use super::http::FeishuHttp;
use crate::channel_output::{
    ChannelAdapter, ChannelError, ChannelTarget, FileCapabilities, FileDelivery, PlatformMessageId,
    UploadHandle,
};
use pl_protocol::AttachmentModality;
use reqwest::{
    Method,
    multipart::{Form, Part},
};
use serde::Deserialize;
use sha2::{Digest, Sha256};

pub(crate) struct FeishuFileAdapter {
    pub http: FeishuHttp,
    pub token: String,
}

pub(super) fn channel_error(error: super::error::FeishuError) -> ChannelError {
    if error.acceptance_unknown() {
        ChannelError::Unknown(error.to_string())
    } else {
        ChannelError::Rejected(error.to_string())
    }
}

impl ChannelAdapter for FeishuFileAdapter {
    fn capabilities(&self) -> FileCapabilities {
        FileCapabilities {
            image_max_bytes: Some(10 * 1024 * 1024),
            file_max_bytes: Some(30 * 1024 * 1024),
        }
    }

    async fn upload(
        &self,
        _target: &ChannelTarget,
        _operation_id: &str,
        file: &FileDelivery,
        bytes: Vec<u8>,
    ) -> Result<UploadHandle, ChannelError> {
        let image = file.modality == AttachmentModality::Image;
        let limit = if image {
            10 * 1024 * 1024
        } else {
            30 * 1024 * 1024
        };
        if bytes.is_empty() || bytes.len() > limit {
            return Err(ChannelError::Rejected(
                "file exceeds Feishu upload size limit or is empty".into(),
            ));
        }
        // Feishu validates supported encodings (including HEIC) and dimensions:
        // GIF <= 2000x2000, others <= 12000x12000. Preserve its explicit rejection
        // instead of transcoding originals or imposing our decoder's format subset.
        let part = Part::bytes(bytes)
            .file_name(file.filename.clone())
            .mime_str(file.resource.media_type())
            .map_err(|_| ChannelError::Rejected("invalid resource media type".into()))?;
        let (path, form) = if image {
            (
                "/open-apis/im/v1/images",
                Form::new()
                    .text("image_type", "message")
                    .part("image", part),
            )
        } else {
            (
                "/open-apis/im/v1/files",
                Form::new()
                    .text("file_type", "stream")
                    .text("file_name", file.filename.clone())
                    .part("file", part),
            )
        };
        #[derive(Deserialize)]
        struct Uploaded {
            image_key: Option<String>,
            file_key: Option<String>,
        }
        let uploaded: Uploaded = self
            .http
            .open_multipart(path, &self.token, form)
            .await
            .map_err(channel_error)?;
        let key = if image {
            uploaded.image_key
        } else {
            uploaded.file_key
        };
        key.filter(|key| !key.is_empty())
            .map(UploadHandle)
            .ok_or_else(|| ChannelError::Unknown("upload confirmation lacks resource key".into()))
    }

    async fn send(
        &self,
        target: &ChannelTarget,
        operation_id: &str,
        file: &FileDelivery,
        uploaded: &UploadHandle,
    ) -> Result<PlatformMessageId, ChannelError> {
        let image = file.modality == AttachmentModality::Image;
        let content = if image {
            serde_json::json!({"image_key": uploaded.0})
        } else {
            serde_json::json!({"file_key": uploaded.0})
        };
        let uuid = hex::encode(&Sha256::digest(operation_id.as_bytes())[..16]);
        let body = serde_json::json!({
            "receive_id": target.conversation_id,
            "msg_type": if image { "image" } else { "file" },
            "content": content.to_string(),
            "uuid": uuid,
        });
        #[derive(Deserialize)]
        struct Sent {
            message_id: Option<String>,
        }
        let sent: Sent = self
            .http
            .open_json(
                Method::POST,
                super::IM_MESSAGES_PATH,
                Some(&self.token),
                &[("receive_id_type", "chat_id")],
                Some(&body),
            )
            .await
            .map_err(channel_error)?;
        sent.message_id
            .filter(|id| !id.is_empty())
            .map(PlatformMessageId)
            .ok_or_else(|| ChannelError::Unknown("message confirmation lacks message id".into()))
    }
}

//! Immutable send plans. Paths are request identities, never deferred byte sources.
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::protocol::im::markdown_request_len;
use super::protocol::{FILE_UPLOAD_LIMIT_BYTES, POST_CONTENT_LIMIT_BYTES};
use crate::resource_store::{DirectorySyncOutcome, FileResourceStore, ResourceRetention};
use pl_core::context::ResourceReference;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::sync::Arc;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    tag = "kind"
)]
pub enum SendContent {
    Markdown {
        text: String,
    },
    File {
        filename: String,
        /// A missing extension gets `.bin` only for the platform's display requirement. This
        /// is not a conversion; the original filename and exact byte identity stay frozen.
        upload_filename: String,
        resource: ResourceReference,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    tag = "kind"
)]
pub enum SendIdentity {
    /// Only records decoded by the version migration may use the pre-Markdown text hash.
    LegacyText,
    Markdown {
        request_hash: String,
    },
    File {
        request_hash: String,
    },
}

/// Host-created source grant, not a deserializable tool argument. The stored copy only provides
/// provenance; every tool invocation must prove it again from canonical Thread facts.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SendSource {
    pub bot_id: String,
    pub chat_id: String,
    pub app_id: String,
    pub project_id: String,
    pub thread_id: String,
    pub input_id: String,
    pub original_input_id: String,
    pub message_id: String,
    pub open_id: String,
    pub chat_kind: String,
    pub creation_id: String,
    pub binding_revision: u64,
}

pub struct SendPlan {
    pub content_hash: String,
    pub identity: SendIdentity,
    pub source: Option<SendSource>,
    pub segments: Vec<SendContent>,
    pub uuids: Vec<String>,
    /// Ephemeral proof from this production pass, not a new persistent reference source.
    pub(super) retention: Option<DirectorySyncOutcome>,
}

pub fn markdown_hash(
    operation_id: &str,
    bot_id: &str,
    chat_id: &str,
    text: &str,
) -> Result<String, FeishuError> {
    fingerprint(&("markdown", operation_id, bot_id, chat_id, text))
}

pub async fn plan_markdown(
    resources: &FileResourceStore,
    operation_id: &str,
    bot_id: &str,
    chat_id: &str,
    text: String,
) -> Result<SendPlan, FeishuError> {
    if text.trim().is_empty() {
        return Err(rejected("message Markdown is required"));
    }
    if text.len() > FILE_UPLOAD_LIMIT_BYTES {
        return Err(rejected(
            "Markdown exceeds the complete-file delivery limit",
        ));
    }
    let request_hash = markdown_hash(operation_id, bot_id, chat_id, &text)?;
    let fits_post = markdown_fits(operation_id, bot_id, chat_id, &text)?;
    let (segments, retention) = if fits_post {
        (vec![SendContent::Markdown { text }], None)
    } else {
        // No character/AST splitting: fences, links and tables retain their exact UTF-8 source.
        let (resource, outcome) = resources
            .retain_bytes_with_receipt(Arc::from(text.into_bytes()), "text/markdown; charset=utf-8")
            .await
            .map_err(FeishuError::send_resource)?
            .into_parts();
        let filename = "reply.md";
        (
            vec![
                SendContent::File {
                    filename: filename.into(),
                    upload_filename: filename.into(),
                    resource,
                },
                // Only an accepted complete file message permits the subsequent delivery notice.
                SendContent::Markdown {
                    text: format!(
                        "正文超过飞书富文本大小限制，完整 Markdown 原文已作为 UTF-8 文件 `{filename}` 交付，可下载查看。"
                    ),
                },
            ],
            Some(outcome),
        )
    };
    let content_hash = fingerprint(&(
        "markdown-plan",
        operation_id,
        bot_id,
        chat_id,
        &request_hash,
        &segments,
    ))?;
    let mut plan = plan(
        operation_id,
        bot_id,
        chat_id,
        content_hash,
        SendIdentity::Markdown { request_hash },
        None,
        segments,
    )?;
    plan.retention = retention;
    Ok(plan)
}

pub(super) fn markdown_fits(
    operation_id: &str,
    bot_id: &str,
    chat_id: &str,
    text: &str,
) -> Result<bool, FeishuError> {
    Ok(text.len() <= POST_CONTENT_LIMIT_BYTES
        && markdown_request_len(chat_id, text, &send_uuid(operation_id, bot_id, chat_id, 0)?)?
            <= POST_CONTENT_LIMIT_BYTES)
}

pub(super) fn plan_file(
    operation_id: &str,
    request_hash: String,
    source: SendSource,
    filename: String,
    retained: ResourceRetention,
) -> Result<SendPlan, FeishuError> {
    let (resource, outcome) = retained.into_parts();
    if resource.byte_len() == 0 || resource.byte_len() > FILE_UPLOAD_LIMIT_BYTES as u64 {
        return Err(rejected("file upload requires 1..=30,000,000 bytes"));
    }
    let upload_filename = if std::path::Path::new(&filename).extension().is_none() {
        format!("{filename}.bin")
    } else {
        filename.clone()
    };
    let segments = vec![SendContent::File {
        filename,
        upload_filename,
        resource,
    }];
    let content_hash = fingerprint(&("file", operation_id, &source, &request_hash, &segments))?;
    let mut plan = plan(
        operation_id,
        &source.bot_id.clone(),
        &source.chat_id.clone(),
        content_hash,
        SendIdentity::File { request_hash },
        Some(source),
        segments,
    )?;
    plan.retention = Some(outcome);
    Ok(plan)
}

fn plan(
    operation_id: &str,
    bot_id: &str,
    chat_id: &str,
    content_hash: String,
    identity: SendIdentity,
    source: Option<SendSource>,
    segments: Vec<SendContent>,
) -> Result<SendPlan, FeishuError> {
    let uuids = (0..segments.len())
        .map(|index| send_uuid(operation_id, bot_id, chat_id, index))
        .collect::<Result<Vec<_>, _>>()?;
    for (segment, uuid) in segments.iter().zip(&uuids) {
        if let SendContent::Markdown { text } = segment
            && markdown_request_len(chat_id, text, uuid)? > POST_CONTENT_LIMIT_BYTES
        {
            return Err(rejected(
                "target and Markdown notice exceed the complete message JSON budget",
            ));
        }
    }
    Ok(SendPlan {
        content_hash,
        identity,
        source,
        segments,
        uuids,
        retention: None,
    })
}

pub fn file_request_hash(path: &str, filename: Option<&str>) -> Result<String, FeishuError> {
    fingerprint(&(path, filename))
}

fn send_uuid(
    operation_id: &str,
    bot_id: &str,
    chat_id: &str,
    index: usize,
) -> Result<String, FeishuError> {
    fingerprint(&(operation_id, bot_id, chat_id, index)).map(|hash| hash[..32].to_owned())
}

fn fingerprint(value: &impl Serialize) -> Result<String, FeishuError> {
    // Stream serde's canonical typed encoding into the digest; escaping a long Markdown body
    // must not allocate an additional potentially 6x-sized JSON copy just to fingerprint it.
    struct HashWriter(Sha256);
    impl std::io::Write for HashWriter {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            self.0.update(bytes);
            Ok(bytes.len())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }
    let mut writer = HashWriter(Sha256::new());
    serde_json::to_writer(&mut writer, value)
        .map_err(|_| rejected("could not encode send identity"))?;
    Ok(hex::encode(writer.0.finalize()))
}

pub fn safe_filename(filename: &str) -> Result<String, FeishuError> {
    if filename.is_empty()
        || matches!(filename, "." | "..")
        || filename.chars().count() > 180
        || filename
            .chars()
            .any(|ch| ch.is_control() || "<>:\"/\\|?*".contains(ch))
        || filename.ends_with(['.', ' '])
    {
        return Err(rejected("filename must be a safe display name, not a path"));
    }
    Ok(filename.to_owned())
}

pub(crate) fn rejected(message: &str) -> FeishuError {
    FeishuError::new(FeishuErrorKind::Rejected, message, false, None)
}

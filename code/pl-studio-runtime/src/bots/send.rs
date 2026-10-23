use super::protocol::TEXT_SEGMENT_LIMIT_BYTES;
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::protocol::im::content_hash;
use super::protocol::im::markdown_request_bytes;
use sha2::{Digest, Sha256};
use std::time::Duration;
use tokio::time::Instant;

/// One bounded owner per bot, deliberately stricter than per-target 5 QPS.
/// It stores no target map and releases the scheduling lock before HTTP starts.
pub(crate) struct SendRate(tokio::sync::Mutex<Instant>);

pub(crate) struct SendPermit<'a>(tokio::sync::MutexGuard<'a, Instant>);

impl SendRate {
    pub(crate) fn new() -> Self {
        Self(tokio::sync::Mutex::new(Instant::now()))
    }

    pub(crate) async fn acquire(&self) -> SendPermit<'_> {
        let next = self.0.lock().await;
        tokio::time::sleep_until(*next).await;
        SendPermit(next)
    }
}

impl SendPermit<'_> {
    /// Keep eligibility through the short durable-intent write, then measure
    /// spacing at HTTP dispatch. No scheduling/admission lock crosses HTTP.
    pub(crate) fn start(mut self) {
        *self.0 = Instant::now() + Duration::from_millis(200);
    }
}

pub struct SendPlan {
    pub content_hash: String,
    pub segments: Vec<String>,
    pub uuids: Vec<String>,
}

pub fn plan_text(
    operation_id: &str,
    bot_id: &str,
    chat_id: &str,
    text: &str,
) -> Result<SendPlan, FeishuError> {
    if text.trim().is_empty() {
        return Err(FeishuError::new(
            FeishuErrorKind::Rejected,
            "message text is required",
            false,
            None,
        ));
    }
    let segments = split_text(chat_id, text)?;
    let uuids = segments
        .iter()
        .enumerate()
        .map(|(index, _)| send_uuid(operation_id, bot_id, chat_id, index))
        .collect::<Result<Vec<_>, _>>()?;
    Ok(SendPlan {
        content_hash: content_hash(operation_id, chat_id, text),
        segments,
        uuids,
    })
}

const MAX_SEND_SEGMENTS: usize = 32;
const MAX_SEND_CHARS: usize = 200_000;

fn split_text(chat_id: &str, text: &str) -> Result<Vec<String>, FeishuError> {
    if text.chars().count() > MAX_SEND_CHARS {
        return Err(FeishuError::new(
            FeishuErrorKind::Rejected,
            "message text exceeds the send size bound",
            false,
            None,
        ));
    }
    // UUIDs retain their historical identity and fixed width. Measure the complete wire
    // request, including both levels of escaping in the JSON-string `content` field.
    let uuid = "0".repeat(32);
    let mut segments = Vec::new();
    let mut rest = text;
    while !rest.is_empty() {
        if segments.len() == MAX_SEND_SEGMENTS {
            return Err(size_error("message requires more segments than allowed"));
        }
        let mut lower = 0;
        let mut upper = rest.len();
        while lower < upper {
            let mut end = lower + (upper - lower).div_ceil(2);
            while !rest.is_char_boundary(end) {
                end += 1;
            }
            if markdown_request_bytes(chat_id, &rest[..end], &uuid) <= TEXT_SEGMENT_LIMIT_BYTES {
                lower = end;
            } else {
                upper = end - 1;
                while !rest.is_char_boundary(upper) {
                    upper -= 1;
                }
            }
        }
        if lower == 0 {
            return Err(size_error("message envelope exceeds the send size bound"));
        }
        let end = if lower == rest.len() {
            lower
        } else {
            let prefix = &rest[..lower];
            prefix
                .rfind("\n\n")
                .map(|position| position + 2)
                .or_else(|| prefix.rfind('\n').map(|position| position + 1))
                .unwrap_or(lower)
        };
        segments.push(rest[..end].to_string());
        rest = &rest[end..];
    }
    Ok(segments)
}

fn size_error(message: &str) -> FeishuError {
    FeishuError::new(FeishuErrorKind::Rejected, message, false, None)
}

fn send_uuid(
    operation_id: &str,
    bot_id: &str,
    chat_id: &str,
    index: usize,
) -> Result<String, FeishuError> {
    let mut hasher = Sha256::new();
    hasher.update(operation_id.as_bytes());
    hasher.update(bot_id.as_bytes());
    hasher.update(chat_id.as_bytes());
    hasher.update(index.to_le_bytes());
    let digest = hasher.finalize();
    let uuid = hex::encode(&digest[..16]);
    if uuid.chars().count() > 50 {
        return Err(FeishuError::new(
            FeishuErrorKind::Protocol,
            "constructed send uuid exceeds 50 characters",
            false,
            None,
        ));
    }
    Ok(uuid)
}

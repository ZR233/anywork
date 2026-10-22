use super::protocol::TEXT_SEGMENT_LIMIT_BYTES;
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::protocol::im::content_hash;
use sha2::{Digest, Sha256};

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
    let segments = split_text(text)?;
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

fn split_text(text: &str) -> Result<Vec<String>, FeishuError> {
    if text.chars().count() > MAX_SEND_CHARS {
        return Err(FeishuError::new(
            FeishuErrorKind::Rejected,
            "message text exceeds the send size bound",
            false,
            None,
        ));
    }
    let overhead = encoded_len("");
    let budget = TEXT_SEGMENT_LIMIT_BYTES.saturating_sub(overhead.max(1));
    if text.len() <= budget {
        return Ok(vec![text.to_string()]);
    }
    let mut segments = Vec::new();
    let mut current = String::new();
    for ch in text.chars() {
        let extra = ch.len_utf8();
        if !current.is_empty() && current.len() + extra > budget {
            segments.push(std::mem::take(&mut current));
            if segments.len() >= MAX_SEND_SEGMENTS {
                return Err(FeishuError::new(
                    FeishuErrorKind::Rejected,
                    "message requires more segments than allowed",
                    false,
                    None,
                ));
            }
        }
        current.push(ch);
    }
    if !current.is_empty() {
        segments.push(current);
    }
    if segments.len() > MAX_SEND_SEGMENTS {
        return Err(FeishuError::new(
            FeishuErrorKind::Rejected,
            "message requires more segments than allowed",
            false,
            None,
        ));
    }
    Ok(segments)
}

fn encoded_len(text: &str) -> usize {
    serde_json::json!({ "text": text }).to_string().len()
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

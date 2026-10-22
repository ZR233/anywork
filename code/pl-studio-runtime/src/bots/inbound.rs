use super::config::BotConfigFile;
use super::protocol::error::FeishuError;
use super::protocol::im::{content_hash, extract_post_text, extract_text};
use serde::Deserialize;
use serde_json::Value;

#[derive(Debug, Clone)]
pub enum InboundDecision {
    Ignore,
    Pairing {
        open_id: String,
        chat_id: String,
        display_name: Option<String>,
        chat_kind: ChatKind,
    },
    Execute {
        message_id: String,
        chat_id: String,
        open_id: String,
        text: String,
        content_hash: String,
        chat_kind: ChatKind,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChatKind {
    Direct,
    Group,
}

pub trait InboundHost: Send + Sync {
    fn is_current(&self) -> bool;
    fn admit(
        &self,
        bot_id: &str,
        decision: InboundDecision,
    ) -> impl std::future::Future<Output = Result<(), FeishuError>> + Send;
}

#[derive(Debug, Deserialize)]
struct ReceiveEnvelope {
    #[serde(default)]
    header: Option<EventHeader>,
    #[serde(default)]
    event: Option<MessageReceiveEvent>,
    #[serde(rename = "type", default)]
    event_alias: Option<String>,
}

#[derive(Debug, Deserialize)]
struct EventHeader {
    #[serde(default)]
    event_type: Option<String>,
}

#[derive(Debug, Deserialize)]
struct MessageReceiveEvent {
    #[serde(default)]
    sender: Option<EventSender>,
    #[serde(default)]
    message: Option<EventMessage>,
}

#[derive(Debug, Deserialize)]
struct EventSender {
    #[serde(default)]
    sender_id: Option<UserIdSet>,
    #[serde(default)]
    sender_type: Option<String>,
}

#[derive(Debug, Deserialize)]
struct UserIdSet {
    #[serde(default)]
    open_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct EventMessage {
    #[serde(default)]
    message_id: Option<String>,
    #[serde(default)]
    chat_id: Option<String>,
    #[serde(default)]
    chat_type: Option<String>,
    #[serde(default)]
    message_type: Option<String>,
    #[serde(default)]
    content: Option<String>,
    #[serde(default)]
    mentions: Option<Vec<EventMention>>,
}

#[derive(Debug, Deserialize)]
struct EventMention {
    #[serde(default)]
    key: Option<String>,
    #[serde(default)]
    id: Option<MentionId>,
}

#[derive(Debug, Deserialize)]
#[serde(untagged)]
enum MentionId {
    Ids(UserIdSet),
}

pub fn classify_event(
    config: &BotConfigFile,
    payload: &Value,
    bot_open_id: Option<&str>,
) -> InboundDecision {
    let Ok(envelope) = serde_json::from_value::<ReceiveEnvelope>(payload.clone()) else {
        return InboundDecision::Ignore;
    };
    let event_type = envelope
        .header
        .as_ref()
        .and_then(|header| header.event_type.as_deref())
        .or(envelope.event_alias.as_deref())
        .unwrap_or_default();
    if event_type != "im.message.receive_v1" {
        return InboundDecision::Ignore;
    }
    let Some(event) = envelope.event else {
        return InboundDecision::Ignore;
    };
    let Some(sender) = event.sender else {
        return InboundDecision::Ignore;
    };
    if sender.sender_type.as_deref() != Some("user") {
        return InboundDecision::Ignore;
    }
    let Some(open_id) = sender
        .sender_id
        .and_then(|ids| ids.open_id)
        .filter(|value| !value.is_empty())
    else {
        return InboundDecision::Ignore;
    };
    let Some(message) = event.message else {
        return InboundDecision::Ignore;
    };
    let Some(chat_id) = message.chat_id.filter(|value| !value.is_empty()) else {
        return InboundDecision::Ignore;
    };
    let Some(message_id) = message.message_id.filter(|value| !value.is_empty()) else {
        return InboundDecision::Ignore;
    };
    let chat_kind = match message.chat_type.as_deref() {
        Some("group") => ChatKind::Group,
        Some("p2p") | None => ChatKind::Direct,
        Some(_) => return InboundDecision::Ignore,
    };
    let content = message.content.as_deref().unwrap_or("");
    let text = match message.message_type.as_deref().unwrap_or("text") {
        "text" => extract_text(content).unwrap_or_default(),
        "post" => extract_post_text(content),
        _ => String::new(),
    };
    let hash = content_hash(&message_id, &chat_id, content);
    if chat_kind == ChatKind::Group {
        if !config.trusted_chat_ids.contains(&chat_id) {
            return InboundDecision::Ignore;
        }
        if !mentions_current_bot(message.mentions.as_deref().unwrap_or(&[]), bot_open_id) {
            return InboundDecision::Ignore;
        }
        if text.is_empty() {
            return InboundDecision::Ignore;
        }
        return InboundDecision::Execute {
            message_id,
            chat_id,
            open_id,
            text,
            content_hash: hash,
            chat_kind,
        };
    }
    if !config.trusted_open_ids.contains(&open_id) {
        return InboundDecision::Pairing {
            open_id,
            chat_id,
            display_name: None,
            chat_kind,
        };
    }
    if text.is_empty() {
        return InboundDecision::Ignore;
    }
    InboundDecision::Execute {
        message_id,
        chat_id,
        open_id,
        text,
        content_hash: hash,
        chat_kind,
    }
}

fn mentions_current_bot(mentions: &[EventMention], bot_open_id: Option<&str>) -> bool {
    let Some(bot_open_id) = bot_open_id.filter(|value| !value.is_empty()) else {
        return false;
    };
    mentions.iter().any(|mention| {
        if is_all_mention(mention) {
            return false;
        }
        mention_open_id(mention).as_deref() == Some(bot_open_id)
    })
}

fn is_all_mention(mention: &EventMention) -> bool {
    let key = mention.key.as_deref().unwrap_or_default();
    key.eq_ignore_ascii_case("@_all")
}

fn mention_open_id(mention: &EventMention) -> Option<String> {
    match &mention.id {
        Some(MentionId::Ids(ids)) => ids.open_id.clone().filter(|value| !value.is_empty()),
        _ => None,
    }
}

use super::error::{FeishuError, FeishuErrorKind};
use super::http::FeishuHttp;
use super::{BOT_INFO_PATH, IM_CHATS_PATH, IM_MESSAGES_PATH};
use pl_protocol::studio::{BotConversationKind, BotMessage, BotMessageBody};
use reqwest::Method;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

pub struct FeishuIm {
    http: FeishuHttp,
}

#[derive(Debug, Clone)]
pub struct FeishuChat {
    pub chat_id: String,
    pub name: Option<String>,
    pub kind: BotConversationKind,
}

#[derive(Debug, Clone)]
pub struct ChatListPage {
    pub chats: Vec<FeishuChat>,
    pub page_token: Option<String>,
    pub has_more: bool,
}

#[derive(Debug, Clone)]
pub struct FeishuMessage {
    pub message_id: String,
    pub chat_id: String,
    pub sender_open_id: Option<String>,
    pub created_at: i64,
    pub body: BotMessageBody,
}

#[derive(Debug, Clone)]
pub struct SendMessageOutcome {
    pub message_id: String,
}

#[derive(Debug, Deserialize)]
struct ChatListData {
    #[serde(default)]
    items: Vec<ChatItem>,
    #[serde(default)]
    page_token: Option<String>,
    #[serde(default)]
    has_more: bool,
}

#[derive(Debug, Deserialize)]
struct ChatItem {
    chat_id: Option<String>,
    #[serde(default)]
    name: Option<String>,
}

#[derive(Debug, Deserialize)]
struct MessageListData {
    #[serde(default)]
    items: Vec<RawMessage>,
    #[serde(default)]
    page_token: Option<String>,
    #[serde(default)]
    has_more: bool,
}

#[derive(Debug, Deserialize)]
struct MessageCreateData {
    message_id: Option<String>,
}

#[derive(Debug, Deserialize)]
struct RawMessage {
    message_id: Option<String>,
    #[serde(default)]
    chat_id: Option<String>,
    #[serde(default)]
    create_time: Option<String>,
    #[serde(default)]
    msg_type: Option<String>,
    #[serde(default)]
    body: Option<RawBody>,
    #[serde(default)]
    sender: Option<RawSender>,
}

#[derive(Debug, Deserialize)]
struct RawBody {
    #[serde(default)]
    content: Option<String>,
}

#[derive(Debug, Deserialize)]
struct RawSender {
    #[serde(default)]
    id: Option<String>,
    #[serde(default)]
    sender_type: Option<String>,
}

#[derive(Serialize)]
struct SendBody<'a> {
    receive_id: &'a str,
    msg_type: &'a str,
    content: String,
    uuid: &'a str,
}

impl FeishuIm {
    pub fn new(http: FeishuHttp) -> Self {
        Self { http }
    }

    pub async fn bot_open_id(&self, token: &str) -> Result<String, FeishuError> {
        #[derive(Deserialize)]
        struct BotInfoResponse {
            code: i64,
            #[serde(default)]
            msg: Option<String>,
            #[serde(default)]
            bot: Option<BotInfoBody>,
        }
        #[derive(Deserialize)]
        struct BotInfoBody {
            open_id: Option<String>,
        }
        let parsed: BotInfoResponse = self
            .http
            .open_typed(Method::GET, BOT_INFO_PATH, Some(token), &[], None::<&()>)
            .await?;
        let code = parsed.code;
        if code != 0 {
            return Err(super::http::classify_open_api(code, parsed.msg.as_deref()));
        }
        parsed
            .bot
            .and_then(|bot| bot.open_id)
            .filter(|value| !value.is_empty())
            .ok_or_else(|| {
                FeishuError::new(
                    FeishuErrorKind::Protocol,
                    "bot info missing open_id",
                    false,
                    Some(code.to_string()),
                )
            })
    }

    pub async fn list_chats(
        &self,
        token: &str,
        page_token: Option<&str>,
        page_size: u32,
    ) -> Result<ChatListPage, FeishuError> {
        let size = page_size.clamp(1, 50).to_string();
        let mut query = vec![("page_size", size.as_str())];
        if let Some(token_value) = page_token.filter(|value| !value.is_empty()) {
            query.push(("page_token", token_value));
        }
        let data: ChatListData = self
            .http
            .open_json(Method::GET, IM_CHATS_PATH, Some(token), &query, None::<&()>)
            .await?;
        Ok(ChatListPage {
            chats: data
                .items
                .into_iter()
                .filter_map(|item| {
                    let chat_id = item.chat_id.filter(|value| !value.is_empty())?;
                    Some(FeishuChat {
                        chat_id,
                        name: item.name.filter(|value| !value.is_empty()),
                        kind: BotConversationKind::Group,
                    })
                })
                .collect(),
            page_token: data.page_token.filter(|value| !value.is_empty()),
            has_more: data.has_more,
        })
    }

    pub async fn list_messages(
        &self,
        token: &str,
        chat_id: &str,
        start_time: Option<i64>,
        end_time: Option<i64>,
        page_token: Option<&str>,
        page_size: u32,
    ) -> Result<(Vec<FeishuMessage>, Option<String>), FeishuError> {
        let size = page_size.clamp(1, 50).to_string();
        let start = start_time.map(|value| value.to_string());
        let end = end_time.map(|value| value.to_string());
        let mut query = vec![
            ("container_id_type", "chat"),
            ("container_id", chat_id),
            ("page_size", size.as_str()),
            ("sort_type", "ByCreateTimeDesc"),
        ];
        if let Some(value) = start.as_deref() {
            query.push(("start_time", value));
        }
        if let Some(value) = end.as_deref() {
            query.push(("end_time", value));
        }
        if let Some(value) = page_token.filter(|value| !value.is_empty()) {
            query.push(("page_token", value));
        }
        let data: MessageListData = self
            .http
            .open_json(
                Method::GET,
                IM_MESSAGES_PATH,
                Some(token),
                &query,
                None::<&()>,
            )
            .await?;
        let next = if data.has_more {
            data.page_token.filter(|value| !value.is_empty())
        } else {
            None
        };
        Ok((
            data.items
                .into_iter()
                .map(|item| decode_message(item, chat_id))
                .collect::<Result<Vec<_>, _>>()?,
            next,
        ))
    }

    pub async fn send_text(
        &self,
        token: &str,
        chat_id: &str,
        text: &str,
        uuid: &str,
    ) -> Result<SendMessageOutcome, FeishuError> {
        if uuid.chars().count() > 50 {
            return Err(FeishuError::new(
                FeishuErrorKind::Rejected,
                "send uuid exceeds 50 characters",
                false,
                None,
            ));
        }
        let content = serde_json::json!({ "text": text }).to_string();
        let body = SendBody {
            receive_id: chat_id,
            msg_type: "text",
            content,
            uuid,
        };
        let data: MessageCreateData = self
            .http
            .open_json(
                Method::POST,
                IM_MESSAGES_PATH,
                Some(token),
                &[("receive_id_type", "chat_id")],
                Some(&body),
            )
            .await?;
        let message_id = data
            .message_id
            .filter(|value| !value.is_empty())
            .ok_or_else(|| {
                FeishuError::new(
                    FeishuErrorKind::Protocol,
                    "send response missing message_id",
                    true,
                    None,
                )
            })?;
        Ok(SendMessageOutcome { message_id })
    }
}

fn decode_message(item: RawMessage, fallback_chat: &str) -> Result<FeishuMessage, FeishuError> {
    let message_id = item
        .message_id
        .filter(|value| !value.is_empty())
        .ok_or_else(|| {
            FeishuError::new(
                FeishuErrorKind::Protocol,
                "history message missing message_id",
                false,
                None,
            )
        })?;
    let chat_id = item
        .chat_id
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| fallback_chat.to_string());
    let created_at = item
        .create_time
        .as_deref()
        .map(parse_create_time_millis)
        .transpose()?
        .ok_or_else(|| {
            FeishuError::new(
                FeishuErrorKind::Protocol,
                "history message missing create_time",
                false,
                None,
            )
        })?;
    let sender_open_id = item.sender.and_then(|sender| {
        if sender.sender_type.as_deref() == Some("user") {
            sender.id.filter(|value| !value.is_empty())
        } else {
            None
        }
    });
    let raw_content = item.body.and_then(|body| body.content).unwrap_or_default();
    let body = decode_body(item.msg_type.as_deref().unwrap_or("unknown"), &raw_content);
    Ok(FeishuMessage {
        message_id,
        chat_id,
        sender_open_id,
        created_at,
        body,
    })
}

fn decode_body(msg_type: &str, content: &str) -> BotMessageBody {
    match msg_type {
        "text" => BotMessageBody::Text {
            text: extract_text(content).unwrap_or_default(),
        },
        "post" => BotMessageBody::Post {
            text: extract_post_text(content),
        },
        other => BotMessageBody::Unsupported {
            msg_type: other.to_string(),
            notice: "unsupportedMedia".to_string(),
        },
    }
}

pub fn extract_text(content: &str) -> Option<String> {
    let value: serde_json::Value = serde_json::from_str(content).ok()?;
    value
        .get("text")
        .and_then(serde_json::Value::as_str)
        .map(str::to_string)
}

pub fn extract_post_text(content: &str) -> String {
    let Ok(value) = serde_json::from_str::<PostContent>(content) else {
        return String::new();
    };
    let language = value
        .language
        .as_deref()
        .filter(|item| !item.is_empty())
        .or_else(|| value.content.keys().next().map(String::as_str))
        .unwrap_or("zh_cn");
    let Some(blocks) = value
        .content
        .get(language)
        .or_else(|| value.content.values().next())
    else {
        return String::new();
    };
    let mut parts = Vec::new();
    for paragraph in blocks {
        for node in paragraph {
            if let Some(text) = node.text.as_deref().filter(|item| !item.is_empty()) {
                parts.push(text.to_string());
            }
        }
    }
    parts.join("")
}

#[derive(Deserialize)]
struct PostContent {
    #[serde(default)]
    language: Option<String>,
    #[serde(default)]
    content: std::collections::BTreeMap<String, Vec<Vec<PostNode>>>,
}

#[derive(Deserialize)]
struct PostNode {
    #[serde(default)]
    text: Option<String>,
}

fn parse_create_time_millis(value: &str) -> Result<i64, FeishuError> {
    let millis = value.parse::<i64>().map_err(|_| {
        FeishuError::new(
            FeishuErrorKind::Protocol,
            "history create_time is not a millisecond timestamp",
            false,
            None,
        )
    })?;
    Ok(millis / 1000)
}

pub fn content_hash(message_id: &str, chat_id: &str, content: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(message_id.as_bytes());
    hasher.update(0u8.to_le_bytes());
    hasher.update(chat_id.as_bytes());
    hasher.update(0u8.to_le_bytes());
    hasher.update(content.as_bytes());
    hex::encode(hasher.finalize())
}

pub fn to_product_message(message: &FeishuMessage) -> BotMessage {
    BotMessage {
        message_id: message.message_id.clone(),
        chat_id: message.chat_id.clone(),
        sender_open_id: message.sender_open_id.clone(),
        created_at: message.created_at,
        body: message.body.clone(),
    }
}

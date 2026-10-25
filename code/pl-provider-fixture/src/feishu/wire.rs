//! Official Feishu wire samples owned by this environment crate.
//!
//! pbbp2 field numbers follow larksuite/node-sdk `ws-client/proto-buf/pbbp2.js`
//! at revision `b188be60134d409b61259546bcf69c731d2b0b7c` (MIT). Addons encoding
//! follows `scene/registration/addons.ts`: JSON → gzip → base64url (no pad).
//! These types are fixture samples, not production adapter definitions.

use std::collections::BTreeSet;
use std::io::Read;

use anyhow::{Context, Result, bail, ensure};
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use flate2::Compression;
use flate2::read::GzDecoder;
use flate2::write::GzEncoder;
use prost::Message;
use serde::{Deserialize, Serialize};

use super::types::{
    ChatType, EventBody, Mention, SenderKind, SyntheticEvent, TRUSTED_USER_OPEN_ID,
};

pub const REQUIRED_TENANT_SCOPES: [&str; 8] = [
    "im:message:send_as_bot",
    "im:message.p2p_msg:readonly",
    "im:message.group_at_msg:readonly",
    "im:chat:readonly",
    "im:message:readonly",
    "im:resource:upload",
    // Current image/file receiving capability. Adding CardKit must not drop an
    // in-service receiving scope.
    "im:resource",
    // Official CardKit entity create/update scope. The fixture rejects the
    // broad `im:message` scope and any extra scope, so a wider grant cannot be
    // mistaken for a passing template.
    "cardkit:card:write",
];
pub const REQUIRED_TENANT_EVENTS: [&str; 1] = ["im.message.receive_v1"];

pub const FRAME_TYPE_CONTROL: i32 = 0;
pub const FRAME_TYPE_DATA: i32 = 1;
pub const HEADER_TYPE: &str = "type";
pub const HEADER_MESSAGE_ID: &str = "message_id";
pub const HEADER_SUM: &str = "sum";
pub const HEADER_SEQ: &str = "seq";
pub const HEADER_TRACE_ID: &str = "trace_id";
pub const HEADER_BIZ_RT: &str = "biz_rt";
pub const HEADER_HANDSHAKE_STATUS: &str = "handshake-status";
pub const HEADER_HANDSHAKE_MSG: &str = "handshake-msg";
pub const HEADER_HANDSHAKE_AUTHERRCODE: &str = "handshake-autherrcode";
pub const MESSAGE_TYPE_EVENT: &str = "event";
pub const MESSAGE_TYPE_PING: &str = "ping";
pub const MESSAGE_TYPE_PONG: &str = "pong";
/// Fixed illegal pbbp2 stimulus. Not a general codec.
pub const ILLEGAL_PBBP2: &[u8] = b"not-pbbp2";

#[derive(Clone, PartialEq, Message)]
pub struct Pbbp2Header {
    #[prost(string, tag = "1")]
    pub key: String,
    #[prost(string, tag = "2")]
    pub value: String,
}

#[derive(Clone, PartialEq, Message)]
pub struct Pbbp2Frame {
    #[prost(uint64, tag = "1")]
    pub seq_id: u64,
    #[prost(uint64, tag = "2")]
    pub log_id: u64,
    #[prost(int32, tag = "3")]
    pub service: i32,
    #[prost(int32, tag = "4")]
    pub method: i32,
    #[prost(message, repeated, tag = "5")]
    pub headers: Vec<Pbbp2Header>,
    #[prost(string, optional, tag = "6")]
    pub payload_encoding: Option<String>,
    #[prost(string, optional, tag = "7")]
    pub payload_type: Option<String>,
    #[prost(bytes = "vec", optional, tag = "8")]
    pub payload: Option<Vec<u8>>,
    #[prost(string, optional, tag = "9")]
    pub log_id_new: Option<String>,
}

impl Pbbp2Frame {
    pub fn header(&self, key: &str) -> Option<&str> {
        self.headers
            .iter()
            .find(|header| header.key == key)
            .map(|header| header.value.as_str())
    }

    pub fn encode_vec(&self) -> Vec<u8> {
        self.encode_to_vec()
    }

    pub fn decode_slice(bytes: &[u8]) -> Result<Self> {
        Self::decode(bytes).context("pbbp2 frame decode")
    }

    pub fn ping(service: i32) -> Self {
        Self {
            seq_id: 0,
            log_id: 0,
            service,
            method: FRAME_TYPE_CONTROL,
            headers: vec![header(HEADER_TYPE, MESSAGE_TYPE_PING)],
            payload_encoding: None,
            payload_type: None,
            payload: None,
            log_id_new: None,
        }
    }

    pub fn pong(service: i32, payload: &[u8]) -> Self {
        Self {
            seq_id: 0,
            log_id: 0,
            service,
            method: FRAME_TYPE_CONTROL,
            headers: vec![header(HEADER_TYPE, MESSAGE_TYPE_PONG)],
            payload_encoding: None,
            payload_type: None,
            payload: Some(payload.to_vec()),
            log_id_new: None,
        }
    }

    pub fn handshake_reject(status: u16, auth_err_code: i32, message: &str) -> Self {
        Self {
            seq_id: 0,
            log_id: 0,
            service: 0,
            method: FRAME_TYPE_CONTROL,
            headers: vec![
                header(HEADER_HANDSHAKE_STATUS, &status.to_string()),
                header(HEADER_HANDSHAKE_MSG, message),
                header(HEADER_HANDSHAKE_AUTHERRCODE, &auth_err_code.to_string()),
            ],
            payload_encoding: None,
            payload_type: None,
            payload: None,
            log_id_new: None,
        }
    }

    pub fn event_fragment(
        service: i32,
        message_id: &str,
        trace_id: &str,
        sum: u32,
        seq: u32,
        payload: &[u8],
    ) -> Self {
        Self {
            seq_id: 0,
            log_id: 0,
            service,
            method: FRAME_TYPE_DATA,
            headers: vec![
                header(HEADER_TYPE, MESSAGE_TYPE_EVENT),
                header(HEADER_MESSAGE_ID, message_id),
                header(HEADER_SUM, &sum.to_string()),
                header(HEADER_SEQ, &seq.to_string()),
                header(HEADER_TRACE_ID, trace_id),
            ],
            payload_encoding: None,
            payload_type: None,
            payload: Some(payload.to_vec()),
            log_id_new: None,
        }
    }
}

pub fn header(key: &str, value: &str) -> Pbbp2Header {
    Pbbp2Header {
        key: key.to_owned(),
        value: value.to_owned(),
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Addons {
    #[serde(default)]
    pub preset: Option<bool>,
    #[serde(default)]
    pub scopes: Option<AddonsScopes>,
    #[serde(default)]
    pub events: Option<AddonsEvents>,
    #[serde(default)]
    pub callbacks: Option<AddonsCallbacks>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AddonsScopes {
    #[serde(default)]
    pub tenant: Option<Vec<String>>,
    #[serde(default)]
    pub user: Option<Vec<String>>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AddonsEvents {
    #[serde(default)]
    pub items: Option<AddonsEventItems>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AddonsEventItems {
    #[serde(default)]
    pub tenant: Option<Vec<String>>,
    #[serde(default)]
    pub user: Option<Vec<String>>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AddonsCallbacks {
    #[serde(default)]
    pub items: Option<Vec<String>>,
}

pub fn required_addons() -> Addons {
    Addons {
        preset: Some(false),
        scopes: Some(AddonsScopes {
            tenant: Some(
                REQUIRED_TENANT_SCOPES
                    .iter()
                    .map(|scope| (*scope).to_owned())
                    .collect(),
            ),
            user: None,
        }),
        events: Some(AddonsEvents {
            items: Some(AddonsEventItems {
                tenant: Some(
                    REQUIRED_TENANT_EVENTS
                        .iter()
                        .map(|event| (*event).to_owned())
                        .collect(),
                ),
                user: None,
            }),
        }),
        callbacks: None,
    }
}

pub fn encode_addons(addons: &Addons) -> Result<String> {
    let json = serde_json::to_vec(addons).context("addons json")?;
    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    std::io::Write::write_all(&mut encoder, &json).context("addons gzip")?;
    let gz = encoder.finish().context("addons gzip finish")?;
    Ok(URL_SAFE_NO_PAD.encode(gz))
}

pub fn decode_addons(encoded: &str) -> Result<Addons> {
    ensure!(!encoded.is_empty(), "addons is empty");
    let gz = URL_SAFE_NO_PAD
        .decode(encoded.trim())
        .context("addons base64url")?;
    let mut decoder = GzDecoder::new(gz.as_slice());
    let mut json = String::new();
    decoder.read_to_string(&mut json).context("addons gzip")?;
    serde_json::from_str(&json).context("addons json")
}

pub fn validate_required_addons(addons: &Addons) -> Result<()> {
    match addons.preset {
        Some(false) => {}
        Some(true) => bail!("addons preset must be false"),
        None => bail!("addons preset is missing"),
    }

    let scopes = addons
        .scopes
        .as_ref()
        .context("addons scopes are missing")?;
    let tenant_scopes = scopes
        .tenant
        .as_ref()
        .context("addons tenant scopes are missing")?;
    ensure!(
        tenant_scopes.len() == REQUIRED_TENANT_SCOPES.len(),
        "addons tenant scopes must have exactly {} entries",
        REQUIRED_TENANT_SCOPES.len()
    );
    let mut seen_scopes = BTreeSet::new();
    for scope in tenant_scopes {
        ensure!(
            seen_scopes.insert(scope.as_str()),
            "addons duplicate tenant scope"
        );
        ensure!(
            REQUIRED_TENANT_SCOPES.contains(&scope.as_str()),
            "addons extra tenant scope"
        );
    }
    for required in REQUIRED_TENANT_SCOPES {
        ensure!(
            seen_scopes.contains(required),
            "addons missing tenant scope {required}"
        );
    }
    match scopes.user.as_deref() {
        None | Some([]) => {}
        Some(_) => bail!("addons user scopes must be empty"),
    }

    let events = addons
        .events
        .as_ref()
        .context("addons events are missing")?;
    let items = events
        .items
        .as_ref()
        .context("addons event items are missing")?;
    let tenant_events = items
        .tenant
        .as_ref()
        .context("addons tenant events are missing")?;
    ensure!(
        tenant_events.len() == REQUIRED_TENANT_EVENTS.len(),
        "addons tenant events must have exactly {} entries",
        REQUIRED_TENANT_EVENTS.len()
    );
    let mut seen_events = BTreeSet::new();
    for event in tenant_events {
        ensure!(
            seen_events.insert(event.as_str()),
            "addons duplicate tenant event"
        );
        ensure!(
            REQUIRED_TENANT_EVENTS.contains(&event.as_str()),
            "addons extra tenant event"
        );
    }
    for required in REQUIRED_TENANT_EVENTS {
        ensure!(
            seen_events.contains(required),
            "addons missing tenant event {required}"
        );
    }
    match items.user.as_deref() {
        None | Some([]) => {}
        Some(_) => bail!("addons user events must be empty"),
    }

    match addons.callbacks.as_ref() {
        None => {}
        Some(callbacks) => match callbacks.items.as_deref() {
            None | Some([]) => {}
            Some(_) => bail!("addons callbacks must be empty"),
        },
    }
    Ok(())
}

pub fn parse_form(body: &[u8]) -> std::collections::HashMap<String, String> {
    url::form_urlencoded::parse(body).into_owned().collect()
}

pub fn event_payload(event: &SyntheticEvent, app_id: &str, bot_open_id: &str) -> serde_json::Value {
    let (message_type, content) = match &event.body {
        EventBody::Text(text) => ("text", serde_json::json!({"text": text}).to_string()),
        EventBody::Post(value) => ("post", serde_json::json!(value).to_string()),
        EventBody::Image { image_key } => ("image", serde_json::json!({"image_key": image_key}).to_string()),
        EventBody::File { file_key, file_name } => ("file", serde_json::json!({"file_key": file_key, "file_name": file_name}).to_string()),
        EventBody::Audio { file_key, duration } => ("audio", serde_json::json!({"file_key": file_key, "duration": duration}).to_string()),
        EventBody::Media { file_key, image_key, file_name, duration } => ("media", serde_json::json!({"file_key": file_key, "image_key": image_key, "file_name": file_name, "duration": duration}).to_string()),
        EventBody::Raw {
            message_type,
            content,
        } => (message_type.as_str(), content.clone()),
    };
    let chat_type = match event.chat_type {
        ChatType::P2p => "p2p",
        ChatType::Group => "group",
    };
    let sender_type = match event.sender {
        SenderKind::User => "user",
        SenderKind::App | SenderKind::Bot => "bot",
        SenderKind::Unknown => "unknown",
    };
    let mentions: Vec<serde_json::Value> = event.mentions.iter().map(mention_json).collect();
    serde_json::json!({
        "schema": "2.0",
        "header": {
            "event_id": format!("evt_{}", event.message_id),
            "event_type": "im.message.receive_v1",
            "create_time": event.create_time_ms,
            "token": "anywork-fixture-event-token",
            "app_id": app_id,
            "tenant_key": "anywork_fixture_tenant"
        },
        "event": {
            "sender": {
                "sender_id": {
                    "open_id": event.sender_open_id,
                    "union_id": format!("on_{}", event.sender_open_id),
                    "user_id": format!("u_{}", event.sender_open_id)
                },
                "sender_type": sender_type,
                "tenant_key": "anywork_fixture_tenant"
            },
            "message": {
                "message_id": event.message_id,
                "create_time": event.create_time_ms,
                "update_time": event.create_time_ms,
                "chat_id": event.chat_id,
                "chat_type": chat_type,
                "message_type": message_type,
                "content": content,
                "mentions": mentions
            }
        },
        "bot_open_id": bot_open_id
    })
}

fn mention_json(mention: &Mention) -> serde_json::Value {
    serde_json::json!({
        "key": mention.key,
        "id": {
            "open_id": mention.id.open_id,
            "union_id": mention.id.union_id,
            "user_id": mention.id.user_id
        },
        "name": mention.name,
        "tenant_key": "anywork_fixture_tenant",
        "mentioned_type": mention.mentioned_type
    })
}

pub fn split_payload(bytes: &[u8], parts: usize) -> Result<Vec<Vec<u8>>> {
    ensure!(parts >= 1, "event parts must be >= 1");
    if parts == 1 {
        return Ok(vec![bytes.to_vec()]);
    }
    let chunk = bytes.len().div_ceil(parts).max(1);
    let mut out = Vec::new();
    let mut index = 0;
    while index < bytes.len() {
        let end = (index + chunk).min(bytes.len());
        out.push(bytes[index..end].to_vec());
        index = end;
    }
    while out.len() < parts {
        out.push(Vec::new());
    }
    if out.len() != parts {
        bail!("cannot split payload into {parts} parts");
    }
    Ok(out)
}

pub fn trusted_user_mention(bot_open_id: &str) -> Mention {
    Mention {
        key: "@_user_1".into(),
        id: super::types::MentionId {
            open_id: bot_open_id.to_owned(),
            union_id: None,
            user_id: None,
        },
        name: "fixture-bot".into(),
        mentioned_type: "bot".into(),
    }
}

pub fn all_mention() -> Mention {
    Mention {
        key: "@_all".into(),
        id: super::types::MentionId {
            open_id: "all".into(),
            union_id: None,
            user_id: None,
        },
        name: "all".into(),
        mentioned_type: "all".into(),
    }
}

pub fn other_bot_mention(open_id: &str) -> Mention {
    Mention {
        key: "@_user_1".into(),
        id: super::types::MentionId {
            open_id: open_id.to_owned(),
            union_id: None,
            user_id: None,
        },
        name: "other-bot".into(),
        mentioned_type: "bot".into(),
    }
}

pub fn default_create_time_ms() -> String {
    "1710000000000".into()
}

pub fn text_event(
    message_id: impl Into<String>,
    chat_id: impl Into<String>,
    chat_type: ChatType,
    sender: SenderKind,
    sender_open_id: impl Into<String>,
    text: impl Into<String>,
    mentions: Vec<Mention>,
) -> SyntheticEvent {
    SyntheticEvent {
        message_id: message_id.into(),
        chat_id: chat_id.into(),
        chat_type,
        sender,
        sender_open_id: sender_open_id.into(),
        mentions,
        body: EventBody::Text(text.into()),
        create_time_ms: default_create_time_ms(),
    }
}

pub fn trusted_direct(message_id: &str, text: &str) -> SyntheticEvent {
    text_event(
        message_id,
        super::types::DIRECT_CHAT_ID,
        ChatType::P2p,
        SenderKind::User,
        TRUSTED_USER_OPEN_ID,
        text,
        Vec::new(),
    )
}

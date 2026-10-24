//! Public control, evidence, and synthetic-event types for the Feishu peer.
//!
//! Secrets, device codes, and verification URLs stay out of ordinary logs and
//! [`std::fmt::Debug`] of runtime options. Evidence structs record presence and
//! redacted summaries, not usable credentials.

use std::net::SocketAddr;

use serde::{Deserialize, Serialize};

/// Synthetic App ID prefix required by debug isolation transport.
pub const APP_ID_PREFIX: &str = "cli_anywork_fixture_";
/// Default App ID for connecting an already-known synthetic bot.
pub const DEFAULT_APP_ID: &str = "cli_anywork_fixture_manual";
/// App ID returned by a completed native registration poll.
pub const REGISTERED_APP_ID: &str = "cli_anywork_fixture_registered";
/// Obviously synthetic App Secret. Never a real credential.
pub const DEFAULT_APP_SECRET: &str = "anywork-fixture-secret-not-real";
/// Secret returned by completed registration.
pub const REGISTERED_APP_SECRET: &str = "anywork-fixture-registered-secret-not-real";
/// Bot `open_id`. Distinct from App ID; products must not treat them as equal.
pub const BOT_OPEN_ID: &str = "ou_anywork_fixture_bot";
/// Trusted human user `open_id`.
pub const TRUSTED_USER_OPEN_ID: &str = "ou_anywork_fixture_user";
/// Unknown human user used for pairing-only inbound.
pub const UNKNOWN_USER_OPEN_ID: &str = "ou_anywork_fixture_unknown";
/// Another bot's `open_id` (not this app).
pub const OTHER_BOT_OPEN_ID: &str = "ou_anywork_fixture_other_bot";
/// Synthetic group `chat_id`. Never mixed into a DM directory.
pub const GROUP_CHAT_ID: &str = "oc_anywork_fixture_group";
/// Synthetic observed DM `chat_id`. Not listed by GET /chats.
pub const DIRECT_CHAT_ID: &str = "oc_anywork_fixture_p2p";
/// Synthetic pairing-only DM `chat_id` for the extra environment user. Not
/// listed by GET /chats and never part of a group directory.
pub const PAIRING_DIRECT_CHAT_ID: &str = "oc_anywork_fixture_env_direct";
/// Issued tenant token. Memory-only on the product side; fixture evidence redacts it.
pub const TENANT_ACCESS_TOKEN: &str = "t-anywork-fixture-tenant-token";

/// Loopback bind options for [`super::FeishuPeer::start`].
#[derive(Clone)]
pub struct FeishuPeerOptions {
    /// Bind this loopback port. `None` uses an ephemeral port. Port 1420 is rejected.
    pub bind_port: Option<u16>,
    pub app_id: String,
    pub app_secret: String,
    pub registered_app_id: String,
    pub registered_app_secret: String,
    pub bot_open_id: String,
}

impl Default for FeishuPeerOptions {
    fn default() -> Self {
        Self {
            bind_port: None,
            app_id: DEFAULT_APP_ID.to_owned(),
            app_secret: DEFAULT_APP_SECRET.to_owned(),
            registered_app_id: REGISTERED_APP_ID.to_owned(),
            registered_app_secret: REGISTERED_APP_SECRET.to_owned(),
            bot_open_id: BOT_OPEN_ID.to_owned(),
        }
    }
}

impl std::fmt::Debug for FeishuPeerOptions {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("FeishuPeerOptions")
            .field("bind_port", &self.bind_port)
            .field("app_id", &self.app_id)
            .field("app_secret", &"<redacted>")
            .field("registered_app_id", &self.registered_app_id)
            .field("registered_app_secret", &"<redacted>")
            .field("bot_open_id", &self.bot_open_id)
            .finish()
    }
}

/// Independent endpoint kinds. Concurrent kinds are not globally ordered.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum CallKind {
    RegistrationBegin,
    RegistrationPoll,
    TenantToken,
    BotInfo,
    WsEndpoint,
    WsUpgrade,
    ChatList,
    ChatGet,
    ChatMembers,
    MessageList,
    MessageRead,
    MessageSend,
    FileUpload,
    ResourceDownload,
}

/// Count bounds for a required or forbidden kind. Independent of other kinds.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CallBound {
    pub kind: CallKind,
    pub min: usize,
    pub max: Option<usize>,
}

/// Scripted `action=begin` response fields.
///
/// Frozen for a request when that begin enters the handler, before
/// `begin_hang` wait. Replacing these options, or hang/release of begin,
/// cannot swap another attempt's settings onto an in-flight response.
/// Continue still allocates the generation and waits outside the shared
/// lock.
///
/// `verification_url: None` keeps the peer-bound complete URI
/// `{origin}/verify?user_code=ANYWORK`. `Some` is copied verbatim into
/// `verification_uri_complete` only; `verification_uri` stays
/// `{origin}/verify`. Interval and expires are written exactly. The peer
/// never fetches, follows, or opens the URL. [`std::fmt::Debug`] reports
/// only whether a URL override is present.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RegistrationBeginOptions {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub verification_url: Option<String>,
    pub interval_seconds: u32,
    pub expires_in_seconds: u32,
}

impl Default for RegistrationBeginOptions {
    fn default() -> Self {
        Self {
            verification_url: None,
            interval_seconds: 5,
            expires_in_seconds: 600,
        }
    }
}

impl std::fmt::Debug for RegistrationBeginOptions {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("RegistrationBeginOptions")
            .field(
                "verification_url_override",
                &self.verification_url.is_some(),
            )
            .field("interval_seconds", &self.interval_seconds)
            .field("expires_in_seconds", &self.expires_in_seconds)
            .finish()
    }
}

/// Official lowercase `user_info.tenant_brand` on a Completed poll.
///
/// Independent of [`RegistrationPollScript`]. `None` on the control field
/// preserves historical wire: `"feishu"` only when `include_open_id` is
/// true, and no `user_info` otherwise. `Some` is read when the Completed
/// body is emitted (after poll hang/release), the same moment as the late
/// script. A brand without `include_open_id` must not mint `open_id`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RegistrationTenantBrand {
    Feishu,
    Lark,
}

impl RegistrationTenantBrand {
    pub(crate) fn as_wire(self) -> &'static str {
        match self {
            Self::Feishu => "feishu",
            Self::Lark => "lark",
        }
    }
}

/// Scripted native-registration poll result (RFC 8628 / official SDK).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum RegistrationPollScript {
    Pending,
    SlowDown,
    Completed {
        include_open_id: bool,
    },
    Denied,
    Expired,
    Cancelled,
    /// Hold the HTTP request until [`super::FeishuControl::release_registration`] or shutdown.
    Hang,
}

/// Scripted tenant-token outcome. Never defaults to success when set to an error.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TokenScript {
    Success { expire_seconds: i32 },
    AuthError,
    PermissionError,
    RateLimited,
    HttpError { status: u16 },
    Hang,
}

/// WebSocket discovery / upgrade behaviour.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum WsDiscoveryScript {
    Success,
    AuthFailed,
    Forbidden,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum WsUpgradeScript {
    Accept,
    HttpReject {
        status: u16,
    },
    /// HTTP upgrade succeeds, then a control frame carries handshake rejection.
    HandshakeReject {
        status: u16,
        auth_err_code: i32,
    },
}

/// Official ClientConfig pushed by discovery and pong payloads.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClientConfig {
    #[serde(rename = "PingInterval")]
    pub ping_interval: u32,
    #[serde(rename = "ReconnectCount")]
    pub reconnect_count: u32,
    #[serde(rename = "ReconnectInterval")]
    pub reconnect_interval: u32,
    #[serde(rename = "ReconnectNonce")]
    pub reconnect_nonce: u32,
}

impl Default for ClientConfig {
    fn default() -> Self {
        Self {
            ping_interval: 30,
            reconnect_count: 30,
            reconnect_interval: 2,
            reconnect_nonce: 1,
        }
    }
}

/// How a scripted send request is answered. The peer does not decide product
/// Succeeded/Rejected/Partial/Unknown.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SendDisposition {
    Succeed,
    Reject {
        code: i32,
        msg: String,
    },
    /// Request is accepted and assigned a platform message id, then the HTTP
    /// response is never written (client sees timeout / lost response).
    AcceptThenDrop,
    Hang,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ChatType {
    P2p,
    Group,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SenderKind {
    User,
    App,
    Bot,
    Unknown,
}

/// Official mention `id` object (`open_id` / `union_id` / `user_id`).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MentionId {
    pub open_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub union_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub user_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Mention {
    pub key: String,
    pub id: MentionId,
    pub name: String,
    pub mentioned_type: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum EventBody {
    Text(String),
    /// Received post content has no locale wrapper, unlike a send request.
    Post(ReceivedPost),
    Image {
        image_key: String,
    },
    File {
        file_key: String,
        file_name: String,
    },
    Audio {
        file_key: String,
        duration: u64,
    },
    Media {
        file_key: String,
        image_key: String,
        file_name: String,
        duration: u64,
    },
    /// Explicit raw official wire stimulus for message kinds not modeled here.
    /// This name makes no claim about product support or admission.
    Raw {
        message_type: String,
        content: String,
    },
}

/// Official send-post locale wrapper. The peer models the zh_cn sample, not
/// Markdown rendering or the full rich-text platform grammar.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PostContent {
    pub zh_cn: PostLocale,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PostLocale {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    pub content: Vec<Vec<PostElement>>,
}

/// Official received-post object, without a send-side language wrapper.
/// Native Markdown is carried in `content_v2`, never a legacy `md` tag.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ReceivedPost {
    pub title: String,
    pub content: Vec<Vec<PostElement>>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content_v2: Option<Vec<Vec<PostElement>>>,
}

/// A small independent official wire sample; md text stays verbatim. Resource
/// elements also construct inbound posts without product classification logic.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "tag", deny_unknown_fields)]
pub enum PostElement {
    #[serde(rename = "md")]
    Markdown { text: String },
    #[serde(rename = "text")]
    Text { text: String },
    #[serde(rename = "img")]
    Image { image_key: String },
    #[serde(rename = "media")]
    Media { file_key: String, image_key: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum MessageContentObservation {
    Text { text: String },
    Post(PostContent),
    File(super::media::ResourceSummary),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum MessageSendOutcome {
    Waiting,
    Rejected,
    Stored,
    StoredResponseDropped,
    Cancelled,
}

/// Only platform facts. A stored message or prepared response does not decide
/// the product's Succeeded/Partial/Unknown result.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MessageSendObservation {
    pub call_index: usize,
    pub request_body_bytes: usize,
    pub receive_id: String,
    pub uuid: Option<String>,
    pub message_id: String,
    pub content: MessageContentObservation,
    pub disposition: SendDisposition,
    pub outcome: MessageSendOutcome,
}

/// Platform event the peer will push. It never writes product SQLite or trust lists.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SyntheticEvent {
    pub message_id: String,
    pub chat_id: String,
    pub chat_type: ChatType,
    pub sender: SenderKind,
    pub sender_open_id: String,
    pub mentions: Vec<Mention>,
    pub body: EventBody,
    pub create_time_ms: String,
}

/// Outbound WS payload chosen by the operator, not inferred from product state.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum OutboundWs {
    Event(SyntheticEvent),
    EventFragments {
        event: SyntheticEvent,
        parts: usize,
    },
    DuplicateEvent(SyntheticEvent),
    ConflictEvent {
        event: SyntheticEvent,
        other_text: String,
    },
    /// Incomplete `sum > 1` fragment. Same seq + same payload is a retry.
    IncompleteFragment {
        event: SyntheticEvent,
        sum: u32,
        seq: u32,
        payload: Vec<u8>,
    },
    IllegalBytes,
    Close {
        code: u16,
        reason: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RecordedCall {
    pub method: String,
    pub path: String,
    pub kind: Option<CallKind>,
    pub accepted: bool,
    pub diagnostic: Option<String>,
    pub unix_millis: u64,
    /// Scripted / expected reject (bad cursor, non-upgrade). Not a fixture failure.
    #[serde(default)]
    pub owned_reject: bool,
    /// Raw JSON body of POST /im/v1/messages after validation. No secrets.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub send_body: Option<serde_json::Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub assigned_message_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub uuid: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PollObservation {
    pub generation: u64,
    pub unix_millis: u64,
    pub script: RegistrationPollScript,
    pub generation_cancelled: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AckObservation {
    pub message_id: Option<String>,
    pub code: Option<i32>,
    pub biz_rt: Option<String>,
    pub unix_millis: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FeishuLiveStatus {
    pub origin: String,
    pub ws_origin: String,
    pub accepted: usize,
    pub rejected: usize,
    pub token_calls: usize,
    pub token_in_flight: usize,
    pub token_max_in_flight: usize,
    pub ws_connections: usize,
    pub ws_active: usize,
    pub pings: usize,
    pub acks: usize,
    pub remaining_required: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FeishuReadyFile {
    /// Canonical HTTP origin, e.g. `http://127.0.0.1:43123`. No path suffix.
    pub origin: String,
    pub ws_origin: String,
    pub address: SocketAddr,
    pub scenario: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FeishuReport {
    pub complete: bool,
    pub origin: String,
    pub calls: Vec<RecordedCall>,
    pub polls: Vec<PollObservation>,
    pub acks: Vec<AckObservation>,
    pub uploads: Vec<super::media::UploadObservation>,
    pub resource_downloads: Vec<super::media::ResourceDownloadObservation>,
    pub message_sends: Vec<MessageSendObservation>,
    pub resources: Vec<super::media::ResourceSummary>,
    pub media_status: super::media::MediaStatus,
    pub violations: Vec<String>,
    pub unconsumed: Vec<String>,
    pub token_calls: usize,
    pub token_max_in_flight: usize,
    pub ws_connections: usize,
    pub pings: usize,
    pub listener_joined: bool,
    pub sockets_joined: bool,
    pub join_error: Option<String>,
}

impl FeishuReport {
    pub fn verify(&self) -> anyhow::Result<()> {
        if self.complete && self.join_error.is_none() {
            return Ok(());
        }
        anyhow::bail!(
            "feishu fixture failed; violations={:?}; unconsumed={:?}; join={}",
            self.violations,
            self.unconsumed,
            self.join_error.as_deref().unwrap_or("ok")
        )
    }

    pub fn diagnostic_lines(&self) -> Vec<String> {
        let status = if self.complete { "complete" } else { "failed" };
        let mut lines = vec![
            format!("feishu_fixture_status={status}"),
            format!(
                "feishu_fixture_accepted={}",
                self.calls.iter().filter(|c| c.accepted).count()
            ),
            format!(
                "feishu_fixture_rejected={}",
                self.calls.iter().filter(|c| !c.accepted).count()
            ),
            format!("feishu_fixture_token_calls={}", self.token_calls),
            format!(
                "feishu_fixture_token_max_in_flight={}",
                self.token_max_in_flight
            ),
            format!("feishu_fixture_ws_connections={}", self.ws_connections),
            format!("feishu_fixture_pings={}", self.pings),
            format!("feishu_fixture_acks={}", self.acks.len()),
            format!("feishu_fixture_listener_joined={}", self.listener_joined),
            format!("feishu_fixture_sockets_joined={}", self.sockets_joined),
        ];
        if let Some(error) = &self.join_error {
            lines.push(format!("feishu_fixture_join_error={}", one_line(error)));
        }
        for violation in &self.violations {
            lines.push(format!("feishu_fixture_violation={}", one_line(violation)));
        }
        for item in &self.unconsumed {
            lines.push(format!("feishu_fixture_unconsumed={}", one_line(item)));
        }
        lines
    }
}

fn one_line(value: &str) -> String {
    value.replace(['\n', '\r'], " ")
}

/// Catalog entry used by GET chats / members / messages.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GroupChat {
    pub chat_id: String,
    pub name: String,
    pub member_open_ids: Vec<String>,
    /// When false, GET history returns a Feishu business code (missing scope).
    pub history_allowed: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct HistoryMessage {
    pub message_id: String,
    pub chat_id: String,
    pub msg_type: String,
    pub content: String,
    pub create_time_ms: String,
    pub sender_id: String,
    pub sender_type: String,
    pub sender_id_type: String,
}

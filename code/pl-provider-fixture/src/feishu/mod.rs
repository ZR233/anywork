//! Isolated loopback Feishu HTTP/WebSocket peer.
//!
//! Canonical namespace for environment control and evidence. Production bot
//! adapters must not import these types, and this module does not import
//! runtime/protocol/tool/server crates.

mod cli;
mod control;
mod http;
pub mod media;
mod messages;
mod observe;
mod peer;
mod state;
mod types;
mod wire;
mod ws;

pub use cli::{FeishuCliOptions, run_feishu_cli};
pub use control::FeishuControl;
pub use observe::{FeishuObserveOptions, run_feishu_observe};
pub use peer::FeishuPeer;
pub use types::{
    APP_ID_PREFIX, AckObservation, BOT_OPEN_ID, CallBound, CallKind, ChatType, ClientConfig,
    DEFAULT_APP_ID, DEFAULT_APP_SECRET, DIRECT_CHAT_ID, EventBody, FeishuLiveStatus,
    FeishuPeerOptions, FeishuReadyFile, FeishuReport, GROUP_CHAT_ID, GroupChat, HistoryMessage,
    Mention, MentionId, MessageContentObservation, MessageSendObservation, MessageSendOutcome,
    OTHER_BOT_OPEN_ID, OutboundWs, PAIRING_DIRECT_CHAT_ID, PollObservation, PostContent,
    PostElement, PostLocale, REGISTERED_APP_ID, REGISTERED_APP_SECRET, ReceivedPost, RecordedCall,
    RegistrationBeginOptions, RegistrationPollScript, RegistrationTenantBrand, SendDisposition,
    SenderKind, SyntheticEvent, TENANT_ACCESS_TOKEN, TRUSTED_USER_OPEN_ID, TokenScript,
    UNKNOWN_USER_OPEN_ID, WsDiscoveryScript, WsUpgradeScript,
};
pub use wire::{
    FRAME_TYPE_CONTROL, FRAME_TYPE_DATA, HEADER_BIZ_RT, HEADER_HANDSHAKE_AUTHERRCODE,
    HEADER_HANDSHAKE_MSG, HEADER_HANDSHAKE_STATUS, HEADER_MESSAGE_ID, HEADER_SEQ, HEADER_SUM,
    HEADER_TRACE_ID, HEADER_TYPE, ILLEGAL_PBBP2, MESSAGE_TYPE_EVENT, MESSAGE_TYPE_PING,
    MESSAGE_TYPE_PONG, Pbbp2Frame, Pbbp2Header, REQUIRED_TENANT_EVENTS, REQUIRED_TENANT_SCOPES,
    all_mention, decode_addons, encode_addons, other_bot_mention, required_addons, text_event,
    trusted_direct, trusted_user_mention, validate_required_addons,
};

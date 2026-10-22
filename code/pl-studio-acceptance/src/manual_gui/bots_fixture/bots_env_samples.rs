//! Fixed synthetic Feishu samples for `--bots-fixture` environment actions.
//!
//! Every chat, message, group, and member id here is a fixed synthetic
//! constant. No real contact, credential, or operator-supplied text enters the
//! samples. Re-invoking an environment action rebuilds the exact same synthetic
//! wire identity, so the product observes a repeat as a duplicate delivery of
//! the same platform message (identity `bot/chat/message` plus unchanged
//! content), never as a new platform input or a same-id content conflict.

use pl_provider_fixture::GUI_PROMPT;
use pl_provider_fixture::feishu::{
    BOT_OPEN_ID, ChatType, EventBody, GROUP_CHAT_ID, GroupChat, HistoryMessage,
    PAIRING_DIRECT_CHAT_ID, SenderKind, SyntheticEvent, TRUSTED_USER_OPEN_ID, UNKNOWN_USER_OPEN_ID,
};

/// Stable platform message id for `bots-env message unknown-direct`.
pub(super) const ENV_UNKNOWN_DIRECT_MESSAGE_ID: &str = "om_anywork_fixture_env_unknown_direct";
/// Stable platform message id for `bots-env message resend-direct`. A different
/// id from the unknown delivery makes the resend a genuinely new platform
/// input once the GUI has approved the user.
pub(super) const ENV_RESEND_DIRECT_MESSAGE_ID: &str = "om_anywork_fixture_env_resend_direct";

/// The product fingerprints inbound text as `sha256(message_id, chat_id,
/// content)`; `create_time` is not part of it. Fixed times keep every
/// re-delivery byte-identical.
const ENV_UNKNOWN_DIRECT_CREATE_TIME_MS: &str = "1710000000000";
const ENV_RESEND_DIRECT_CREATE_TIME_MS: &str = "1710000100000";

/// Bounded synthetic paging sample sizes. Both exceed the real product default
/// page limit (`limit.unwrap_or(20)`) so the GUI has a genuine next page,
/// without inventing a large unrelated matrix.
pub(super) const PAGED_GROUP_COUNT: usize = 25;
pub(super) const PAGED_HISTORY_COUNT: usize = 25;

/// Second paged group denies history, so the GUI can observe the real Feishu
/// permission-failure business code (230002) on a synthetic chat.
const PAGED_HISTORY_DENIED_NAME: &str = "fixture-group-history-denied";
const PAGED_HISTORY_BASE_TIME_MS: i64 = 1_710_000_000_000;
const PAGED_HISTORY_TIME_STEP_MS: i64 = 1_000;

pub(super) fn unknown_direct_event() -> SyntheticEvent {
    direct_event(
        ENV_UNKNOWN_DIRECT_MESSAGE_ID,
        ENV_UNKNOWN_DIRECT_CREATE_TIME_MS,
    )
}

pub(super) fn resend_direct_event() -> SyntheticEvent {
    direct_event(
        ENV_RESEND_DIRECT_MESSAGE_ID,
        ENV_RESEND_DIRECT_CREATE_TIME_MS,
    )
}

fn direct_event(message_id: &str, create_time_ms: &str) -> SyntheticEvent {
    SyntheticEvent {
        message_id: message_id.to_owned(),
        chat_id: PAIRING_DIRECT_CHAT_ID.to_owned(),
        chat_type: ChatType::P2p,
        sender: SenderKind::User,
        sender_open_id: UNKNOWN_USER_OPEN_ID.to_owned(),
        mentions: Vec::new(),
        body: EventBody::Text(GUI_PROMPT.to_owned()),
        create_time_ms: create_time_ms.to_owned(),
    }
}

/// Fixed synthetic group directory: the peer default group keeps its identity
/// and name first, the second entry denies history, and the remaining entries
/// are numbered synthetic groups. All members are synthetic ids.
pub(super) fn paged_groups() -> Vec<GroupChat> {
    (0..PAGED_GROUP_COUNT)
        .map(|index| GroupChat {
            chat_id: if index == 0 {
                GROUP_CHAT_ID.to_owned()
            } else {
                format!("oc_anywork_fixture_env_group_{index:02}")
            },
            name: match index {
                0 => "fixture-group".to_owned(),
                1 => PAGED_HISTORY_DENIED_NAME.to_owned(),
                other => format!("fixture-group-{other:02}"),
            },
            member_open_ids: vec![TRUSTED_USER_OPEN_ID.to_owned(), BOT_OPEN_ID.to_owned()],
            history_allowed: index != 1,
        })
        .collect()
}

/// Fixed synthetic history for the peer default group. The first entry keeps
/// the default history message; the rest are numbered synthetic texts with
/// strictly increasing stable times.
pub(super) fn paged_history() -> Vec<HistoryMessage> {
    (0..PAGED_HISTORY_COUNT)
        .map(|index| {
            let sequence = index + 1;
            let text = if index == 0 {
                "fixture history".to_owned()
            } else {
                format!("fixture history {sequence}")
            };
            HistoryMessage {
                message_id: format!("om_anywork_fixture_history_{sequence}"),
                chat_id: GROUP_CHAT_ID.to_owned(),
                msg_type: "text".to_owned(),
                content: serde_json::json!({ "text": text }).to_string(),
                create_time_ms: (PAGED_HISTORY_BASE_TIME_MS
                    + index as i64 * PAGED_HISTORY_TIME_STEP_MS)
                    .to_string(),
                sender_id: TRUSTED_USER_OPEN_ID.to_owned(),
                sender_type: "user".to_owned(),
                sender_id_type: "open_id".to_owned(),
            }
        })
        .collect()
}

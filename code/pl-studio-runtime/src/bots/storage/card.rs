//! Shared card lifecycle and the frozen pre-publication migration codec.
//! Old streams are decoded only at migration/preflight boundaries; live writes use publication.

use super::inbound_identity;
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use pl_protocol::studio::BotDiagnostic;
use sea_orm::{ConnectionTrait, QueryResult};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots::storage) struct CardBinding {
    pub bot_id: String,
    pub chat_id: String,
    pub message_id: String,
    pub thread_id: String,
    pub original_input: String,
}

impl CardBinding {
    fn identity(&self) -> String {
        inbound_identity(&self.bot_id, &self.chat_id, &self.message_id)
    }

    pub(in crate::bots::storage) fn reply_operation(&self) -> String {
        format!(
            "botreply:{}:{}:{}",
            self.bot_id, self.chat_id, self.message_id
        )
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::bots) enum CardLifecycle {
    Empty,
    Created,
    Streaming,
    Paused,
    Completed,
    Cancelled,
    Failed,
    BudgetLimited,
    InteractionEnded,
    NoFinalReply,
    NeedsAttention,
}

impl CardLifecycle {
    pub(in crate::bots) fn terminal(self) -> bool {
        matches!(
            self,
            Self::Completed
                | Self::Cancelled
                | Self::Failed
                | Self::BudgetLimited
                | Self::InteractionEnded
                | Self::NoFinalReply
        )
    }

    pub(in crate::bots) fn summary(self) -> &'static str {
        match self {
            Self::Empty | Self::Created | Self::Streaming => "Generating",
            Self::Paused => "Waiting for local confirmation",
            Self::Completed => "Completed",
            Self::Cancelled => "Cancelled",
            Self::Failed => "Failed",
            Self::BudgetLimited => "Budget limit reached",
            Self::InteractionEnded => "Local interaction ended",
            Self::NoFinalReply => "未生成最终答复，所示内容仅为未完成预览",
            Self::NeedsAttention => "Needs local attention",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub(in crate::bots::storage) enum CardAction {
    Create {
        text: String,
    },
    // An empty struct variant keeps the same {"kind":"send"} wire shape while
    // making Serde enforce deny_unknown_fields (a tagged unit ignores extras).
    Send {},
    Content {
        text: String,
        final_content: bool,
    },
    Settings {
        streaming: bool,
        lifecycle: CardLifecycle,
        recovery: bool,
    },
}

impl CardAction {
    fn sequenced(&self) -> bool {
        matches!(self, Self::Content { .. } | Self::Settings { .. })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::bots::storage) enum CardOperationStatus {
    /// Committed before HTTP. A crash or loss of lease here is an unknown outcome.
    Intent,
    Confirmed,
    Rejected,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots::storage) struct CardOperation {
    pub action: CardAction,
    pub sequence: i32,
    pub uuid: String,
    pub content_hash: String,
    pub status: CardOperationStatus,
    pub diagnostic: Option<BotDiagnostic>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::bots) enum CardRecoveryPhase {
    Reopen,
    Content,
    Close,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots::storage) struct CardRecovery {
    pub action: CardAction,
    pub phase: CardRecoveryPhase,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots::storage) struct CardStream {
    pub binding: CardBinding,
    pub watch_input: String,
    /// None means the watched canonical input ended without being consumed by a Turn.
    pub turn_id: Option<String>,
    pub version: i64,
    pub lifecycle: CardLifecycle,
    pub card_id: Option<String>,
    pub platform_message_id: Option<String>,
    /// Last allocated sequence, including explicit rejections. Never reused.
    pub sequence: i32,
    pub confirmed_sequence: i32,
    pub confirmed_text: String,
    pub confirmed_content_hash: String,
    pub final_content_hash: Option<String>,
    pub last_operation: Option<CardOperation>,
    /// At most one timeout/closed-mode recovery across the original reply chain.
    pub recovery_used: bool,
    pub recovery: Option<CardRecovery>,
    pub diagnostic: Option<BotDiagnostic>,
}

pub(in crate::bots) fn hash(bytes: &[u8]) -> String {
    hex::encode(Sha256::digest(bytes))
}

/// Strictly validates a stored identity at the version migration/read boundary, without changing
/// its serialized operation material or inferring an input/continuation that is not in the row.
pub(super) fn decode_stored(row: QueryResult) -> Result<CardStream, FeishuError> {
    let text = |column| row.try_get::<String>("", column).map_err(|_| corrupt());
    let binding = CardBinding {
        bot_id: text("bot_id")?,
        chat_id: text("chat_id")?,
        message_id: text("message_id")?,
        thread_id: text("thread_id")?,
        original_input: text("original_input")?,
    };
    decode(row, &binding)
}

fn decode(row: QueryResult, binding: &CardBinding) -> Result<CardStream, FeishuError> {
    let text = |column| row.try_get::<String>("", column).map_err(|_| corrupt());
    let state: CardStream = serde_json::from_str(&text("state_json")?).map_err(|_| corrupt())?;
    if state.binding != *binding
        || text("identity")? != binding.identity()
        || text("bot_id")? != binding.bot_id
        || text("chat_id")? != binding.chat_id
        || text("message_id")? != binding.message_id
        || text("thread_id")? != binding.thread_id
        || text("original_input")? != binding.original_input
        || text("watch_input")? != state.watch_input
        || text("turn_id")? != state.turn_id.as_deref().unwrap_or_default()
        || row.try_get::<i64>("", "version").map_err(|_| corrupt())? != state.version
        || state.version <= 0
        || state.sequence < 0
        || state.confirmed_sequence > state.sequence
        || state.confirmed_sequence < 0
        || state.watch_input.is_empty()
        || state.turn_id.as_ref().is_some_and(String::is_empty)
        || state.turn_id.is_none() && !matches!(state.lifecycle, CardLifecycle::Paused | CardLifecycle::InteractionEnded | CardLifecycle::NeedsAttention)
        || state.platform_message_id.is_some() && state.card_id.is_none()
        || state
            .card_id
            .as_ref()
            .is_some_and(|id| id.trim().is_empty() || id.len() > 256)
        || state
            .platform_message_id
            .as_ref()
            .is_some_and(|id| id.trim().is_empty())
        || state.card_id.is_some() && state.confirmed_text.trim().is_empty()
        || !state.confirmed_text.is_empty()
            && state.confirmed_content_hash != hash(state.confirmed_text.as_bytes())
        || state
            .final_content_hash
            .as_ref()
            .is_some_and(|hash| *hash != state.confirmed_content_hash)
        || matches!(state.lifecycle, CardLifecycle::Created) && state.card_id.is_none()
        || matches!(
            state.lifecycle,
            CardLifecycle::Streaming | CardLifecycle::Paused
        ) && state.platform_message_id.is_none()
        || state.lifecycle.terminal() && state.card_id.is_none()
        || state.recovery.is_some() && !state.recovery_used
        || state.lifecycle == CardLifecycle::Completed && (state.final_content_hash.is_none() || state.platform_message_id.is_none())
        || state.lifecycle == CardLifecycle::NoFinalReply && state.final_content_hash.is_some()
        || state.lifecycle.terminal() && state.last_operation.as_ref().is_none_or(|operation| {
            operation.status != CardOperationStatus::Confirmed || !matches!(operation.action, CardAction::Settings { streaming: false, lifecycle, .. } if lifecycle == state.lifecycle)
        })
        || state.last_operation.as_ref().is_none_or(|operation| {
            operation.sequence < 0
                || operation.sequence > state.sequence
                || operation.uuid.len() != 32
                || operation.content_hash
                    != hash(
                        &serde_json::to_vec(&operation.action)
                            .expect("card operation strings serialize"),
                    )
                || operation.action.sequenced() && (operation.sequence == 0 || state.card_id.is_none())
                || matches!(operation.action, CardAction::Content { .. }) && state.platform_message_id.is_none()
                || matches!(operation.action, CardAction::Send {}) && state.card_id.is_none()
        })
    {
        return Err(corrupt());
    }
    Ok(state)
}

pub(super) async fn migrate<C: ConnectionTrait>(db: &C) -> anyhow::Result<()> {
    db.execute_unprepared(&super::legacy_schema::CARD_TABLE.replacen(
        "CREATE TABLE",
        "CREATE TABLE IF NOT EXISTS",
        1,
    ))
    .await?;
    Ok(())
}

fn corrupt() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "card stream state is unreadable or conflicts with its owner; local recovery required",
        false,
        None,
    )
}

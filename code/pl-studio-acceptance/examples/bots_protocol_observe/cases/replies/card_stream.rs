//! Strict read-only decoding of the production automatic-card stream facts.
//!
//! The reply facts of one automatic card live in `bot_card_streams.state_json`
//! as typed camelCase JSON. This module owns the only decoder the observe cases
//! use, so a renamed field, an unknown lifecycle, or an unknown operation status
//! fails the case instead of silently matching nothing. The old
//! `send_operations` ledger belongs to ordinary text replies and is never read
//! for an automatic card reply.
//!
//! Only facts that acceptance actually asserts are typed; the remaining
//! payloads stay opaque so a schema extension that keeps these facts intact is
//! not turned into a false failure.

use anyhow::{Context, Result};
use serde::Deserialize;
use std::path::Path;

/// Lifecycle of one durable card reply stream.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum Lifecycle {
    Empty,
    Created,
    Streaming,
    Paused,
    Completed,
    Cancelled,
    Failed,
    BudgetLimited,
    InteractionEnded,
    /// A real canonical Final turned out to be empty: the delivered preview stays
    /// on the same card and the stream closes without claiming a final answer.
    NoFinalReply,
    NeedsAttention,
}

/// Kind of the last recorded card operation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum ActionKind {
    Create,
    Send,
    Content,
    Settings,
}

/// Durable outcome of the last recorded card operation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) enum OperationStatus {
    /// Committed before HTTP; a crash or lost lease makes it unknown, not done.
    Intent,
    Confirmed,
    Rejected,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Action {
    pub kind: ActionKind,
    #[serde(default)]
    pub streaming: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct LastOperation {
    pub action: Action,
    pub sequence: i32,
    pub uuid: String,
    pub status: OperationStatus,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Binding {
    pub chat_id: String,
    pub message_id: String,
    pub thread_id: String,
}

/// The asserted subset of one durable card stream.
#[derive(Debug, Clone, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct CardStreamState {
    pub binding: Binding,
    pub watch_input: String,
    /// `None` means the watched canonical input ended without being consumed by
    /// a Turn; a consumed input always names its Turn.
    #[serde(default)]
    pub turn_id: Option<String>,
    pub version: i64,
    pub lifecycle: Lifecycle,
    #[serde(default)]
    pub card_id: Option<String>,
    #[serde(default)]
    pub platform_message_id: Option<String>,
    /// Last allocated sequence, including explicit rejections.
    pub sequence: i32,
    pub confirmed_sequence: i32,
    pub confirmed_text: String,
    pub final_content_hash: Option<String>,
    pub last_operation: Option<LastOperation>,
    pub recovery_used: bool,
}

/// One durable stream row paired with its decoded state.
#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct CardStream {
    pub identity: String,
    pub message_id: String,
    pub thread_id: String,
    pub turn_id: Option<String>,
    pub version: i64,
    pub state: CardStreamState,
}

/// Reads and strictly decodes every durable card stream of one bot.
pub(super) async fn card_streams(home: &Path, bot_id: &str) -> Result<Vec<CardStream>> {
    let rows = crate::sqlite::card_streams(home, bot_id).await?;
    rows.into_iter()
        .map(|row| {
            let state: CardStreamState =
                serde_json::from_str(&row.state_json).with_context(|| {
                    format!(
                        "card stream {} for {} has an unreadable state_json",
                        row.identity, row.message_id
                    )
                })?;
            Ok(CardStream {
                identity: row.identity,
                message_id: row.message_id,
                thread_id: row.thread_id,
                // The SQL mirror stores an unconsumed input as an empty string;
                // the typed fact is "no Turn", never an empty Turn identity.
                turn_id: (!row.turn_id.is_empty()).then_some(row.turn_id),
                version: row.version,
                state,
            })
        })
        .collect()
}

/// Reads the single durable card stream of one inbound message.
///
/// A missing stream is an error here: the caller asserts on reply facts that
/// only exist when the product persisted them.
pub(super) async fn card_stream(home: &Path, bot_id: &str, message_id: &str) -> Result<CardStream> {
    let mut matches: Vec<CardStream> = card_streams(home, bot_id)
        .await?
        .into_iter()
        .filter(|stream| {
            stream.message_id == message_id || stream.state.binding.message_id == message_id
        })
        .collect();
    match matches.len() {
        1 => Ok(matches.remove(0)),
        0 => anyhow::bail!("no durable card stream for inbound {message_id}"),
        count => anyhow::bail!("inbound {message_id} owns {count} durable card streams"),
    }
}

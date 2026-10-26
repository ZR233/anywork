//! Durable single-card progress. Every mutation is fenced by the original inbound
//! lease and a card version, in one transaction; no HTTP runs in that transaction.

use super::{BotStateStore, INBOUND_CLAIM_TTL_SECONDS, inbound_identity, statement, storage};
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::studio::unix_seconds;
use pl_protocol::studio::BotDiagnostic;
use sea_orm::{ConnectionTrait, QueryResult, TransactionTrait, Value};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::bots) struct CardBinding {
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

    pub(in crate::bots) fn reply_operation(&self) -> String {
        format!(
            "botreply:{}:{}:{}",
            self.bot_id, self.chat_id, self.message_id
        )
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
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

#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub(in crate::bots) enum CardAction {
    Create {
        text: String,
    },
    Send,
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
    pub(in crate::bots) fn text(&self) -> Option<&str> {
        match self {
            Self::Create { text } | Self::Content { text, .. } => Some(text),
            Self::Send | Self::Settings { .. } => None,
        }
    }

    fn sequenced(&self) -> bool {
        matches!(self, Self::Content { .. } | Self::Settings { .. })
    }
}

#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::bots) enum CardOperationStatus {
    /// Committed before HTTP. A crash or loss of lease here is an unknown outcome.
    Intent,
    Confirmed,
    Rejected,
    Unknown,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::bots) struct CardOperation {
    pub action: CardAction,
    pub sequence: i32,
    pub uuid: String,
    pub content_hash: String,
    pub status: CardOperationStatus,
    pub diagnostic: Option<BotDiagnostic>,
}

#[derive(Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::bots) enum CardRecoveryPhase {
    Reopen,
    Content,
    Close,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::bots) struct CardRecovery {
    pub action: CardAction,
    pub phase: CardRecoveryPhase,
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::bots) struct CardStream {
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

impl CardStream {
    pub(in crate::bots) fn new(binding: CardBinding, watch_input: &str, turn_id: &str) -> Self {
        Self {
            binding,
            watch_input: watch_input.to_string(),
            turn_id: Some(turn_id.to_string()),
            version: 0,
            lifecycle: CardLifecycle::Empty,
            card_id: None,
            platform_message_id: None,
            sequence: 0,
            confirmed_sequence: 0,
            confirmed_text: String::new(),
            confirmed_content_hash: String::new(),
            final_content_hash: None,
            last_operation: None,
            recovery_used: false,
            recovery: None,
            diagnostic: None,
        }
    }

    pub(in crate::bots) fn uncertain(&self) -> bool {
        self.last_operation.as_ref().is_some_and(|operation| {
            matches!(
                operation.status,
                CardOperationStatus::Intent | CardOperationStatus::Unknown
            )
        })
    }

    /// Bind only a verified canonical consumption target (or an explicitly
    /// unconsumed input). The caller persists both fields in one fenced CAS.
    pub(in crate::bots) fn bind_target(
        &mut self,
        watch_input: &str,
        turn_id: Option<&str>,
    ) -> Result<bool, FeishuError> {
        if self.uncertain() || watch_input.is_empty() || turn_id.is_some_and(str::is_empty) {
            return Err(corrupt());
        }
        if self.watch_input == watch_input {
            if self.turn_id.as_deref() != turn_id {
                return Err(corrupt());
            }
            return Ok(false);
        }
        if self.lifecycle != CardLifecycle::Paused {
            return Err(corrupt());
        }
        self.watch_input = watch_input.to_string();
        self.turn_id = turn_id.map(str::to_string);
        self.final_content_hash = None;
        Ok(true)
    }

    pub(in crate::bots) fn mark_no_final_reply(&mut self) {
        self.final_content_hash = None;
        self.diagnostic = Some(BotDiagnostic {
            code: "noFinalReply".to_string(),
            message: CardLifecycle::NoFinalReply.summary().to_string(),
            retryable: false,
            platform_code: None,
            guidance: None,
        });
    }

    /// The recovery obligation advances in the same confirmation write as the
    /// network operation. A clean stop cannot skip the full-content step after
    /// a confirmed reopen, or repeat a confirmed step after restart.
    pub(in crate::bots) fn confirm_recovery(
        &mut self,
        action: &CardAction,
    ) -> Result<(), FeishuError> {
        let Some(recovery) = self.recovery.as_mut() else {
            return Ok(());
        };
        let finished = match (recovery.phase, action) {
            (
                CardRecoveryPhase::Reopen,
                CardAction::Settings {
                    streaming: true,
                    recovery: true,
                    ..
                },
            ) => {
                recovery.phase = CardRecoveryPhase::Content;
                false
            }
            (CardRecoveryPhase::Content, CardAction::Content { .. }) => {
                if matches!(
                    recovery.action,
                    CardAction::Settings {
                        streaming: false,
                        ..
                    }
                ) {
                    recovery.phase = CardRecoveryPhase::Close;
                    false
                } else {
                    true
                }
            }
            (
                CardRecoveryPhase::Close,
                CardAction::Settings {
                    streaming: false, ..
                },
            ) => true,
            _ => return Err(corrupt()),
        };
        if finished {
            self.recovery = None;
        }
        Ok(())
    }

    pub(in crate::bots) fn reserve(&mut self, action: CardAction) -> Result<(), FeishuError> {
        if self.uncertain()
            || self.lifecycle.terminal()
            || self.lifecycle == CardLifecycle::NeedsAttention
        {
            return Err(corrupt());
        }
        if self.turn_id.is_none()
            && !matches!(
                action,
                CardAction::Settings {
                    streaming: false,
                    lifecycle: CardLifecycle::InteractionEnded,
                    ..
                }
            )
        {
            return Err(corrupt());
        }
        if matches!(
            action,
            CardAction::Settings {
                lifecycle: CardLifecycle::NoFinalReply,
                ..
            }
        ) {
            self.mark_no_final_reply();
        }
        if action.sequenced() {
            self.sequence = self.sequence.checked_add(1).ok_or_else(|| {
                FeishuError::new(
                    FeishuErrorKind::Rejected,
                    "CardKit int32 sequence exhausted",
                    false,
                    None,
                )
            })?;
        }
        if let CardAction::Settings { recovery: true, .. } = action {
            if self.recovery_used {
                return Err(corrupt());
            }
            self.recovery_used = true;
        }
        let encoded = serde_json::to_vec(&action).expect("card operation strings serialize");
        let content_hash = hash(&encoded);
        let next_version = self.version.checked_add(1).ok_or_else(corrupt)?;
        let uuid = hash(
            format!(
                "{}:{}:{}:{content_hash}",
                self.binding.reply_operation(),
                next_version,
                self.sequence
            )
            .as_bytes(),
        );
        self.last_operation = Some(CardOperation {
            action,
            sequence: self.sequence,
            uuid: uuid[..32].to_string(),
            content_hash,
            status: CardOperationStatus::Intent,
            diagnostic: None,
        });
        Ok(())
    }
}

pub(in crate::bots) fn hash(bytes: &[u8]) -> String {
    hex::encode(Sha256::digest(bytes))
}

impl BotStateStore {
    pub(in crate::bots) async fn load_card(
        &self,
        binding: &CardBinding,
    ) -> Result<Option<CardStream>, FeishuError> {
        let db = self.db().await?;
        db.query_one_raw(statement(
            "SELECT identity, bot_id, chat_id, message_id, thread_id, original_input, watch_input, turn_id, version, state_json FROM bot_card_streams WHERE identity=?",
            vec![binding.identity().into()],
        ))
        .await
        .map_err(storage)?
        .map(|row| decode(row, binding))
        .transpose()
    }

    /// Applies a new local state or side-effect intent only while the original inbound
    /// claim AND canonical continuation binding are still owned by this worker.
    pub(in crate::bots) async fn save_card(
        &self,
        state: &mut CardStream,
        worker_id: &str,
    ) -> Result<super::MarkOutcome, FeishuError> {
        let db = self.db().await?;
        let tx = db.begin().await.map_err(storage)?;
        let binding = &state.binding;
        let expected = state.version;
        let next = expected.checked_add(1).ok_or_else(corrupt)?;
        state.version = next;
        let encoded = serde_json::to_string(state).map_err(|_| corrupt())?;
        let now = unix_seconds();
        let (sql, mut values) = if expected == 0 {
            (
                "INSERT OR IGNORE INTO bot_card_streams(identity, bot_id, chat_id, message_id, thread_id, original_input, watch_input, turn_id, version, state_json, updated_at)
                 SELECT ?,?,?,?,?,?,?,?,?,?,? WHERE",
                vec![binding.identity().into(), binding.bot_id.clone().into(), binding.chat_id.clone().into(), binding.message_id.clone().into(),
                     binding.thread_id.clone().into(), binding.original_input.clone().into(), state.watch_input.clone().into(), state.turn_id.clone().unwrap_or_default().into(),
                     next.into(), encoded.into(), now.into()],
            )
        } else {
            (
                "UPDATE bot_card_streams SET watch_input=?, turn_id=?, version=?, state_json=?, updated_at=?
                 WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=? AND thread_id=? AND original_input=? AND version=? AND",
                vec![state.watch_input.clone().into(), state.turn_id.clone().unwrap_or_default().into(), next.into(), encoded.into(), now.into(),
                     binding.identity().into(), binding.bot_id.clone().into(), binding.chat_id.clone().into(), binding.message_id.clone().into(),
                     binding.thread_id.clone().into(), binding.original_input.clone().into(), expected.into()],
            )
        };
        // Lease validity is part of the actual INSERT/UPDATE predicate, not only
        // a preceding read. The claim and expected card version are one fence.
        values.extend(card_claim_values(state, worker_id, now));
        let sql = format!(
            "{sql} EXISTS(SELECT 1 FROM inbound_work WHERE identity=? AND bot_id=? AND chat_id=? AND message_id=? AND status='claimed' AND claimed_by=? AND claimed_at>? AND (watch_input=? OR (watch_input='' AND ?=?)))"
        );
        let result = tx
            .execute_raw(statement(&sql, values))
            .await
            .map_err(storage)?;
        if result.rows_affected() != 1 {
            state.version = expected;
            tx.rollback().await.map_err(storage)?;
            return Ok(super::MarkOutcome::LostClaim);
        }
        tx.commit().await.map_err(storage)?;
        Ok(super::MarkOutcome::Applied)
    }
}

fn card_claim_values(state: &CardStream, worker_id: &str, now: i64) -> Vec<Value> {
    let binding = &state.binding;
    vec![
        binding.identity().into(),
        binding.bot_id.clone().into(),
        binding.chat_id.clone().into(),
        binding.message_id.clone().into(),
        worker_id.to_string().into(),
        now.saturating_sub(INBOUND_CLAIM_TTL_SECONDS).into(),
        state.watch_input.clone().into(),
        state.watch_input.clone().into(),
        binding.original_input.clone().into(),
    ]
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
                || matches!(operation.action, CardAction::Send) && state.card_id.is_none()
        })
    {
        return Err(corrupt());
    }
    Ok(state)
}

fn corrupt() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "card stream state is unreadable or conflicts with its owner; local recovery required",
        false,
        None,
    )
}

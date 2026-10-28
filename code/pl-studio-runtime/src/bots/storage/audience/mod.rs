//! Schema-nine audience facts. Origins are immutable evidence, never another writable chat route.

mod control;
mod counts;
mod input;
mod proof;
mod read;
mod schema;

pub(super) use control::note_delivery_change;
pub(super) use control::{bind_origin, close_chat, close_unavailable_binding, first_pending_start};
pub(super) use counts::prepare_current_indexes;
pub(super) use counts::prepare_indexes as prepare_count_indexes;
pub(in crate::bots) use read::AudienceScope;
pub(super) use read::{head, proven_origin};
pub(super) use read::{load_auth, read_origin};
pub(super) use schema::preflight_file_without_cards;
pub(super) use schema::{ensure_eight_absent, preflight_eight, validate_source_nine};
pub(super) use schema::{legacy_items_declaration, migrate, validate, validate_current};

use super::{BotStateStore, strict_text, strict_watermark};
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::studio::audience_start::{AudienceStartIntent, AudienceStartReceipt};
use pl_protocol::studio::{
    BotAuthorizationPhase, BotItemLedgerSummary, ChangeBotThreadSyncRequest,
};
use pl_protocol::{BotAudienceCloseReason, BotAuthorizationId, BotAuthorizationRef};
use sea_orm::{DatabaseConnection, QueryResult};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone)]
pub(in crate::bots) struct ThreadOrigin {
    pub thread_id: String,
    pub chat_id: String,
    pub project_id: String,
    pub creation_id: String,
    pub binding_revision: u64,
    pub requires_upgrade: bool,
    pub summary_version: u64,
    pub target: super::target::TargetProof,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct Authorization {
    pub intent: AudienceStartIntent,
    pub app_id: String,
    pub project_id: String,
    pub creation_id: String,
    pub revision: u64,
    pub phase: BotAuthorizationPhase,
    pub start: Option<AudienceStartReceipt>,
    pub closed: Option<(BotAudienceCloseReason, i64)>,
    pub delivery_version: u64,
}

impl Authorization {
    pub(in crate::bots) fn reference(&self) -> BotAuthorizationRef {
        BotAuthorizationRef {
            id: self.intent.authorization.clone(),
            revision: self.revision,
        }
    }

    pub(super) fn validate(&self) -> Result<(), FeishuError> {
        self.intent.validate().map_err(|_| unreadable())?;
        if self.revision == 0
            || self.delivery_version == 0
            || self.app_id.is_empty()
            || self.project_id.is_empty()
            || self.creation_id.is_empty()
            || (self.phase == BotAuthorizationPhase::Closed) != self.closed.is_some()
            || matches!(
                self.phase,
                BotAuthorizationPhase::Active | BotAuthorizationPhase::Paused
            ) && self.start.is_none()
            || self.phase == BotAuthorizationPhase::PendingStart && self.start.is_some()
        {
            return Err(unreadable());
        }
        if let Some(start) = &self.start
            && (start.version != 1
                || start.sequence == 0
                || start.extension_revision == 0
                || start
                    .excluded_turn_id
                    .as_ref()
                    .is_some_and(String::is_empty)
                || start.intent != self.intent)
        {
            return Err(unreadable());
        }
        Ok(())
    }
}

#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct SyncOperation {
    pub request: ChangeBotThreadSyncRequest,
    pub authorization: BotAuthorizationId,
}

/// Only bounded, body-free delivery observations are exposed to the query path. Network operation
/// materials belong to the delivery owner, not to Thread snapshots or GUI mirrors.
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(in crate::bots) struct DeliveryObservation {
    pub item_id: String,
    pub thread_id: String,
    pub authorization: BotAuthorizationId,
    pub ledger: BotItemLedgerSummary,
    pub removed: bool,
    pub pending: bool,
    pub incomplete: bool,
}

impl BotStateStore {
    /// Queries may use only an already prepared database. This cannot initialize, migrate or create
    /// a missing file as a side effect of displaying a cold Thread.
    pub(super) fn audience_db(&self) -> Result<&DatabaseConnection, FeishuError> {
        self.writer.get().ok_or_else(|| {
            FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot audience database is not prepared",
                true,
                None,
            )
        })
    }
}

/// 授权行严格解码：迁移与作用域核对共用同一入口，不另写第二套判据。
pub(super) fn authorization_row(row: &QueryResult) -> Result<Authorization, FeishuError> {
    authorization(row)
}

fn origin(row: &QueryResult) -> Result<ThreadOrigin, FeishuError> {
    let flag: i64 = row
        .try_get("", "requires_upgrade")
        .map_err(|_| unreadable())?;
    let origin = ThreadOrigin {
        thread_id: strict_text(row, "thread_id")?,
        chat_id: strict_text(row, "chat_id")?,
        project_id: strict_text(row, "project_id")?,
        creation_id: strict_text(row, "creation_id")?,
        binding_revision: strict_watermark(row, "binding_revision")?,
        requires_upgrade: flag == 1,
        summary_version: strict_watermark(row, "summary_version")?,
        target: super::target::TargetProof::decode(row)?,
    };
    if !matches!(flag, 0 | 1)
        || origin.thread_id.is_empty()
        || origin.chat_id.is_empty()
        || origin.summary_version == 0
    {
        return Err(unreadable());
    }
    Ok(origin)
}

fn authorization(row: &QueryResult) -> Result<Authorization, FeishuError> {
    let value: Authorization =
        serde_json::from_str(&strict_text(row, "state_json")?).map_err(|_| unreadable())?;
    value.validate()?;
    if value.intent.thread_id != strict_text(row, "thread_id")?
        || value.intent.authorization.chat_id != strict_text(row, "chat_id")?
        || value.intent.authorization.generation != strict_watermark(row, "generation")?
        || value.revision != strict_watermark(row, "control_revision")?
        || phase_name(value.phase) != strict_text(row, "phase")?
    {
        return Err(unreadable());
    }
    Ok(value)
}

fn phase_name(phase: BotAuthorizationPhase) -> &'static str {
    match phase {
        BotAuthorizationPhase::PendingStart => "pending",
        BotAuthorizationPhase::Active => "active",
        BotAuthorizationPhase::Paused => "paused",
        BotAuthorizationPhase::Closed => "closed",
    }
}

pub(in crate::bots) fn unreadable() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "bot audience facts are inconsistent; local recovery required",
        false,
        None,
    )
}

pub(in crate::bots) fn conflict() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "bot audience CAS or operation conflicts",
        false,
        None,
    )
}

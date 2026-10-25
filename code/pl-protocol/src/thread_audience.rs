//! Thread-local audience observations. These values describe authority; they never grant it.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use crate::studio::{BotConversationKind, BotDiagnostic};

/// A generation is unique only within its bot/chat scope.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotAuthorizationId {
    pub bot_id: String,
    pub chat_id: String,
    pub generation: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotAuthorizationRef {
    pub id: BotAuthorizationId,
    /// Control revision, independent of delivery and content revisions.
    pub revision: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum BotAuthorizationHead {
    /// Proven absence, not an unloaded authorization.
    None {},
    Present {
        authorization: BotAuthorizationRef,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotSyncCas {
    pub binding_revision: u64,
    pub authorization_head: BotAuthorizationHead,
}

/// Exactly one locally verified target; absent chat names do not trigger a network lookup.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotAudienceTarget {
    pub bot_id: String,
    pub bot_name: String,
    pub chat_id: String,
    pub chat_name: Option<String>,
    pub kind: BotConversationKind,
}

/// Read-only summary of a saved cut, never accepted as a caller-provided authority proof.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotAudienceStart {
    pub commit_sequence: u64,
    pub excluded_turn_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotStartedAuthorization {
    pub authorization: BotAuthorizationRef,
    pub binding_revision: u64,
    pub start: BotAudienceStart,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotPendingAuthorization {
    pub authorization: BotAuthorizationRef,
    pub operation_id: String,
    pub diagnostic: Option<BotDiagnostic>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum BotClosedStart {
    NeverActivated {},
    Saved { start: BotAudienceStart },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum BotAudienceCloseReason {
    LocalClose,
    BotDisabled,
    TrustRevoked,
    BindingReplaced,
    BindingUnavailable,
    StartCancelled,
    StartFailed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotClosedAuthorization {
    pub authorization: BotAuthorizationRef,
    pub binding_revision: u64,
    pub start: BotClosedStart,
    pub reason: BotAudienceCloseReason,
    /// Display time only; it cannot replace the canonical cut.
    pub closed_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum BotCurrentSync {
    /// Binding-management transition before its Thread and authorization preparation exist.
    PreparingThread {},
    RequiresUpgrade {},
    PendingStart {
        pending: BotPendingAuthorization,
    },
    Active {
        authorization: BotStartedAuthorization,
    },
    Paused {
        authorization: BotStartedAuthorization,
    },
    Closed {},
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum BotThreadBindingPosition {
    Current {
        cas: BotSyncCas,
        sync: Box<BotCurrentSync>,
    },
    Replaced {
        last_binding_revision: u64,
        current_binding_revision: u64,
    },
}

/// Counts saturate at this display limit; retained obligations are never truncated to it.
pub const BOT_DELIVERY_SUMMARY_COUNT_LIMIT: u32 = 16_384;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotDeliverySummary {
    pub version: u64,
    pub pending_items: u32,
    pub unknown_operations: u32,
    pub incomplete_items: u32,
    pub counts_capped: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotLegacyFinalSummary {
    pub unfinished_chains: u32,
    pub unknown_operations: u32,
    pub needs_attention: bool,
    pub counts_capped: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotThreadAudience {
    pub target: BotAudienceTarget,
    pub binding: BotThreadBindingPosition,
    pub latest_closed: Option<BotClosedAuthorization>,
    pub has_older_closed: bool,
    pub delivery: BotDeliverySummary,
    pub legacy_final: BotLegacyFinalSummary,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum ThreadAudienceUnavailableReason {
    OwnershipUnproven,
    InvalidOwnership,
    BotUnavailable,
    StateUnreadable,
    InconsistentScope,
    BindingUnavailable,
    RuntimeClosed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum ThreadAudience {
    Unbound {},
    Unavailable {
        reason: ThreadAudienceUnavailableReason,
    },
    Known {
        audience: Box<BotThreadAudience>,
    },
}

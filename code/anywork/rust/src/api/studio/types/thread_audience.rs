//! Typed local audience observations; these DTOs do not grant sending authority.
//! FRB 2.13 requires unit variants for empty cases. Strict JSON decoding remains in pl-protocol.

use super::{BridgeBotConversationKind, BridgeBotDiagnostic};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotAuthorizationId {
    pub bot_id: String,
    pub chat_id: String,
    pub generation: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotAuthorizationRef {
    pub id: BridgeBotAuthorizationId,
    pub revision: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBotAuthorizationHead {
    None,
    Present {
        authorization: BridgeBotAuthorizationRef,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotSyncCas {
    pub binding_revision: u64,
    pub authorization_head: BridgeBotAuthorizationHead,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotAudienceTarget {
    pub bot_id: String,
    pub bot_name: String,
    pub chat_id: String,
    pub chat_name: Option<String>,
    pub kind: BridgeBotConversationKind,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotAudienceStart {
    pub commit_sequence: u64,
    pub excluded_turn_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotStartedAuthorization {
    pub authorization: BridgeBotAuthorizationRef,
    pub binding_revision: u64,
    pub start: BridgeBotAudienceStart,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotPendingAuthorization {
    pub authorization: BridgeBotAuthorizationRef,
    pub operation_id: String,
    pub diagnostic: Option<BridgeBotDiagnostic>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBotClosedStart {
    NeverActivated,
    Saved { start: BridgeBotAudienceStart },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeBotAudienceCloseReason {
    LocalClose,
    BotDisabled,
    TrustRevoked,
    BindingReplaced,
    BindingUnavailable,
    StartCancelled,
    StartFailed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotClosedAuthorization {
    pub authorization: BridgeBotAuthorizationRef,
    pub binding_revision: u64,
    pub start: BridgeBotClosedStart,
    pub reason: BridgeBotAudienceCloseReason,
    pub closed_at: i64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBotCurrentSync {
    PreparingThread,
    RequiresUpgrade,
    PendingStart {
        pending: BridgeBotPendingAuthorization,
    },
    Active {
        authorization: BridgeBotStartedAuthorization,
    },
    Paused {
        authorization: BridgeBotStartedAuthorization,
    },
    Closed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBotThreadBindingPosition {
    Current {
        cas: BridgeBotSyncCas,
        sync: Box<BridgeBotCurrentSync>,
    },
    Replaced {
        last_binding_revision: u64,
        current_binding_revision: u64,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotDeliverySummary {
    pub version: u64,
    pub pending_items: u32,
    pub unknown_operations: u32,
    pub incomplete_items: u32,
    pub counts_capped: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotLegacyFinalSummary {
    pub unfinished_chains: u32,
    pub unknown_operations: u32,
    pub needs_attention: bool,
    pub counts_capped: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotThreadAudience {
    pub target: BridgeBotAudienceTarget,
    pub binding: BridgeBotThreadBindingPosition,
    pub latest_closed: Option<BridgeBotClosedAuthorization>,
    pub has_older_closed: bool,
    pub delivery: BridgeBotDeliverySummary,
    pub legacy_final: BridgeBotLegacyFinalSummary,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadAudienceUnavailableReason {
    OwnershipUnproven,
    InvalidOwnership,
    BotUnavailable,
    StateUnreadable,
    InconsistentScope,
    BindingUnavailable,
    RuntimeClosed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeThreadAudience {
    Unbound,
    Unavailable {
        reason: BridgeThreadAudienceUnavailableReason,
    },
    Known {
        audience: Box<BridgeBotThreadAudience>,
    },
}

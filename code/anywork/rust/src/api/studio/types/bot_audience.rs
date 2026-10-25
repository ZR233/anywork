//! Local audience queries and synchronization commands.

use super::{
    BridgeBotAudienceTarget, BridgeBotAuthorizationId, BridgeBotAuthorizationRef,
    BridgeBotClosedAuthorization, BridgeBotDiagnostic, BridgeBotSendStopReason, BridgeBotSyncCas,
    BridgeStudioCommandReceipt, BridgeThreadAudience, BridgeThreadAudienceUnavailableReason,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeReadThreadClosedAuthorizationsRequest {
    pub thread_id: String,
    pub cursor: Option<String>,
    pub limit: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadClosedAuthorizationPage {
    pub target: BridgeBotAudienceTarget,
    pub authorizations: Vec<BridgeBotClosedAuthorization>,
    pub next_cursor: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeThreadClosedAuthorizationsRead {
    Unbound,
    Unavailable {
        reason: BridgeThreadAudienceUnavailableReason,
    },
    Page {
        page: BridgeThreadClosedAuthorizationPage,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeReadThreadClosedAuthorizationsReply {
    pub thread_id: String,
    pub result: BridgeThreadClosedAuthorizationsRead,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeReadThreadAudienceItemsRequest {
    pub thread_id: String,
    pub authorization: BridgeBotAuthorizationId,
    pub item_ids: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeBotAuthorizationPhase {
    PendingStart,
    Active,
    Paused,
    Closed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeBotPublicTextChannel {
    Commentary,
    Final,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeBotItemExclusion {
    NonPublicContent,
    OutsideAuthorization,
    ExcludedStartedTurn,
    LegacyOnly,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBotItemEligibility {
    Text { channel: BridgeBotPublicTextChannel },
    PublicArtifact,
    NotAuthorized { reason: BridgeBotItemExclusion },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeBotCanonicalUnavailableReason {
    Missing,
    ReadInvalidated,
    StorageUnavailable,
    InvalidMetadata,
    StartProofUnavailable,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBotAudienceCanonicalItem {
    Present {
        revision: u64,
        saved: bool,
        eligibility: BridgeBotItemEligibility,
    },
    Removed,
    Unavailable {
        reason: BridgeBotCanonicalUnavailableReason,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeBotTextIntegrity {
    Full,
    Truncated,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBotItemPresentation {
    None,
    Text {
        revision: u64,
        integrity: BridgeBotTextIntegrity,
        saved: bool,
    },
    File {
        revision: u64,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBotPlatformResult {
    NotStarted,
    InFlight,
    Accepted,
    Rejected { diagnostic: BridgeBotDiagnostic },
    Unknown { diagnostic: BridgeBotDiagnostic },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeBotCardOperationKind {
    Create,
    Send,
    Content,
    Settings,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotCardOperationSummary {
    pub operation_id: String,
    pub content_revision: u64,
    pub action: BridgeBotCardOperationKind,
    pub result: BridgeBotPlatformResult,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeBotFileOutcome {
    Pending,
    Delivered,
    Partial,
    Rejected,
    Unknown,
    Stopped,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeBotFileBlockReason {
    EmptyFile,
    PlatformSizeLimit,
    SourceUnavailable,
    BudgetUnavailable,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBotItemPlatform {
    None,
    Blocked {
        reason: BridgeBotFileBlockReason,
    },
    Card {
        latest_operation: BridgeBotCardOperationSummary,
    },
    File {
        operation_id: String,
        content_revision: u64,
        upload: BridgeBotPlatformResult,
        message: BridgeBotPlatformResult,
        outcome: BridgeBotFileOutcome,
        local_stop: Option<BridgeBotSendStopReason>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotItemLedgerSummary {
    pub observed_revision: u64,
    pub projected: BridgeBotItemPresentation,
    pub accepted: BridgeBotItemPresentation,
    pub platform: BridgeBotItemPlatform,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBotItemDelivery {
    NotProjected,
    Known {
        ledger: Box<BridgeBotItemLedgerSummary>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeBotAudienceItemStatus {
    pub item_id: String,
    pub canonical: BridgeBotAudienceCanonicalItem,
    pub delivery: BridgeBotItemDelivery,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeBotAudienceItemsUnavailableReason {
    OwnerUnavailable,
    LedgerUnreadable,
    CanonicalReadInvalidated,
    ScopeChanged,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBotAudienceItemsRead {
    Unavailable {
        reason: BridgeBotAudienceItemsUnavailableReason,
    },
    Items {
        authorization: BridgeBotAuthorizationRef,
        phase: BridgeBotAuthorizationPhase,
        summary_version: u64,
        delivery_version: u64,
        items: Vec<BridgeBotAudienceItemStatus>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeReadThreadAudienceItemsReply {
    pub thread_id: String,
    pub authorization: BridgeBotAuthorizationId,
    pub result: BridgeBotAudienceItemsRead,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeBotThreadSyncAction {
    Pause,
    Resume,
    Close,
    Enable,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeChangeBotThreadSyncRequest {
    pub operation_id: String,
    pub thread_id: String,
    pub expected: BridgeBotSyncCas,
    pub action: BridgeBotThreadSyncAction,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeBotThreadSyncCommandState {
    Settled,
    PendingStart {
        authorization: BridgeBotAuthorizationId,
    },
    Superseded {
        authorization: BridgeBotAuthorizationId,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeChangeBotThreadSyncReply {
    pub thread_id: String,
    pub audience: BridgeThreadAudience,
    pub state: BridgeBotThreadSyncCommandState,
    pub receipt: BridgeStudioCommandReceipt,
}

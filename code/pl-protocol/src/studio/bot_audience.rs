//! Local audience queries and explicit synchronization commands, never model broadcast tools.

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

use super::{BotDiagnostic, BotSendStopReason, StudioCommandReceipt};
use crate::{
    BotAudienceTarget, BotAuthorizationId, BotAuthorizationRef, BotClosedAuthorization, BotSyncCas,
    ThreadAudience, ThreadAudienceUnavailableReason,
};

pub const DEFAULT_CLOSED_AUTHORIZATION_PAGE_SIZE: u32 = 16;
pub const MAX_CLOSED_AUTHORIZATION_PAGE_SIZE: u32 = 32;
pub const MAX_THREAD_AUDIENCE_ITEM_IDS: usize = 100;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReadThreadClosedAuthorizationsRequest {
    pub thread_id: String,
    pub cursor: Option<String>,
    pub limit: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadClosedAuthorizationPage {
    pub target: BotAudienceTarget,
    pub authorizations: Vec<BotClosedAuthorization>,
    pub next_cursor: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum ThreadClosedAuthorizationsRead {
    Unbound {},
    Unavailable {
        reason: ThreadAudienceUnavailableReason,
    },
    Page {
        page: ThreadClosedAuthorizationPage,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReadThreadClosedAuthorizationsReply {
    pub thread_id: String,
    pub result: ThreadClosedAuthorizationsRead,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReadThreadAudienceItemsRequest {
    pub thread_id: String,
    pub authorization: BotAuthorizationId,
    pub item_ids: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum BotAuthorizationPhase {
    PendingStart,
    Active,
    Paused,
    Closed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum BotPublicTextChannel {
    Commentary,
    Final,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum BotItemExclusion {
    NonPublicContent,
    OutsideAuthorization,
    ExcludedStartedTurn,
    LegacyOnly,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum BotItemEligibility {
    Text { channel: BotPublicTextChannel },
    PublicArtifact {},
    NotAuthorized { reason: BotItemExclusion },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum BotCanonicalUnavailableReason {
    Missing,
    ReadInvalidated,
    StorageUnavailable,
    InvalidMetadata,
    StartProofUnavailable,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum BotAudienceCanonicalItem {
    Present {
        revision: u64,
        saved: bool,
        eligibility: BotItemEligibility,
    },
    /// Requires real canonical removal evidence; a missing lookup is not a deletion.
    Removed {},
    Unavailable {
        reason: BotCanonicalUnavailableReason,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum BotTextIntegrity {
    Full,
    Truncated,
}

/// The revision of a projection or accepted content, independent of the latest canonical revision.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum BotItemPresentation {
    None {},
    Text {
        revision: u64,
        integrity: BotTextIntegrity,
        saved: bool,
    },
    /// An exact, saved publication. A file never has a truncated presentation.
    File {
        revision: u64,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum BotPlatformResult {
    NotStarted {},
    /// Only while a current managed owner still owns the unfinished request.
    InFlight {},
    Accepted {},
    Rejected {
        diagnostic: BotDiagnostic,
    },
    Unknown {
        diagnostic: BotDiagnostic,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum BotCardOperationKind {
    Create,
    Send,
    Content,
    Settings,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotCardOperationSummary {
    pub operation_id: String,
    pub content_revision: u64,
    pub action: BotCardOperationKind,
    pub result: BotPlatformResult,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum BotFileOutcome {
    Pending,
    Delivered,
    Partial,
    Rejected,
    Unknown,
    Stopped,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum BotFileBlockReason {
    EmptyFile,
    PlatformSizeLimit,
    SourceUnavailable,
    BudgetUnavailable,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum BotItemPlatform {
    None {},
    /// A local admission failure, not a rejection returned by the platform.
    Blocked {
        reason: BotFileBlockReason,
    },
    Card {
        latest_operation: BotCardOperationSummary,
    },
    File {
        operation_id: String,
        content_revision: u64,
        upload: BotPlatformResult,
        message: BotPlatformResult,
        outcome: BotFileOutcome,
        local_stop: Option<BotSendStopReason>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotItemLedgerSummary {
    pub observed_revision: u64,
    pub projected: BotItemPresentation,
    pub accepted: BotItemPresentation,
    pub platform: BotItemPlatform,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum BotItemDelivery {
    NotProjected {},
    Known { ledger: Box<BotItemLedgerSummary> },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotAudienceItemStatus {
    pub item_id: String,
    pub canonical: BotAudienceCanonicalItem,
    pub delivery: BotItemDelivery,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum BotAudienceItemsUnavailableReason {
    OwnerUnavailable,
    LedgerUnreadable,
    CanonicalReadInvalidated,
    ScopeChanged,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum BotAudienceItemsRead {
    Unavailable {
        reason: BotAudienceItemsUnavailableReason,
    },
    Items {
        authorization: BotAuthorizationRef,
        phase: BotAuthorizationPhase,
        summary_version: u64,
        delivery_version: u64,
        items: Vec<BotAudienceItemStatus>,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReadThreadAudienceItemsReply {
    pub thread_id: String,
    pub authorization: BotAuthorizationId,
    pub result: BotAudienceItemsRead,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum BotThreadSyncAction {
    Pause,
    Resume,
    Close,
    Enable,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChangeBotThreadSyncRequest {
    pub operation_id: String,
    pub thread_id: String,
    pub expected: BotSyncCas,
    pub action: BotThreadSyncAction,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum BotThreadSyncCommandState {
    Settled {},
    PendingStart { authorization: BotAuthorizationId },
    Superseded { authorization: BotAuthorizationId },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChangeBotThreadSyncReply {
    pub thread_id: String,
    pub audience: ThreadAudience,
    pub state: BotThreadSyncCommandState,
    pub receipt: StudioCommandReceipt,
}

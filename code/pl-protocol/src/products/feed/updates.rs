use serde::{Deserialize, Serialize};
use crate::studio::StudioError;
use crate::products::identity::*;
use crate::products::references::{UpdatesReadRef, UpdateSummaryReadRef, UpdateOperationReadRef, UpdateErrorReadRef, UpdateDetailsReadRef};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum UpdatesBrief {
    Disabled { revision: u64, updated_at: i64 },
    Idle { revision: u64, updated_at: i64 },
    Checking { revision: u64, started_at: i64 },
    UpToDate { revision: u64, checked_at: i64 },
    Available { revision: u64, checked_at: i64 },
    Downloading { revision: u64, updated_at: i64, downloaded: u64, total: u64 },
    Verifying { revision: u64, updated_at: i64, downloaded: u64, total: u64 },
    Ready { revision: u64, ready_at: i64 },
    InstallerLaunched { revision: u64, launched_at: i64 },
    CheckFailed { revision: u64, failed_at: i64, retryable: bool },
    InstallFailed { revision: u64, failed_at: i64, retryable: bool },
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UpdatesHeader {
    pub reference: UpdatesReadRef,
    pub brief: UpdatesBrief,
    pub summary: Option<UpdateSummaryReadRef>,
    pub operation: Option<UpdateOperationReadRef>,
    pub error: Option<UpdateErrorReadRef>,
    pub details: Option<UpdateDetailsReadRef>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum UpdatesEvent {
    Baseline { identity: ProductFeedIdentity, stamp: ProductProjectionStamp, value: UpdatesHeader },
    Replace { stamp: ProductProjectionStamp, base_revision: u64, value: UpdatesHeader },
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum UpdatesFrame {
    Data { delivery_sequence: u64, event: UpdatesEvent },
    ResyncRequired { identity: ProductFeedIdentity, reason: ProductResyncReason },
    Failure { identity: ProductFeedIdentity, error: StudioError },
    Closed { identity: ProductFeedIdentity, reason: ProductFeedCloseReason },
}

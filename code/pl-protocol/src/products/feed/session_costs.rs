use serde::{Deserialize, Serialize};
use crate::studio::StudioError;
use crate::products::identity::*;
use crate::products::references::SessionCostsReadRef;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SessionCostsHeader {
    pub revision: u64,
    pub updated_at: i64,
    pub statistics_pending: bool,
    pub statistics_gap: bool,
    pub read_failed: bool,
    pub has_cost: bool,
    pub has_unpriced_usage: Option<bool>,
    pub reference: SessionCostsReadRef,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum SessionCostsEvent {
    Baseline { identity: ProductFeedIdentity, stamp: ProductProjectionStamp, value: SessionCostsHeader },
    Replace { stamp: ProductProjectionStamp, base_revision: u64, value: SessionCostsHeader },
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum SessionCostsFrame {
    Data { delivery_sequence: u64, event: SessionCostsEvent },
    ResyncRequired { identity: ProductFeedIdentity, reason: ProductResyncReason },
    Failure { identity: ProductFeedIdentity, error: StudioError },
    Closed { identity: ProductFeedIdentity, reason: ProductFeedCloseReason },
}

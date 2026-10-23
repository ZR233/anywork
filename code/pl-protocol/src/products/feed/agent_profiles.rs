use serde::{Deserialize, Serialize};
use crate::studio::StudioError;
use crate::products::identity::*;
use crate::products::references::AgentProfilesReadRef;
use crate::products::source::ObservedHeader;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentProfilesHeader {
    pub source: ObservedHeader,
    pub profiles_revision: Option<u64>,
    pub reference: Option<AgentProfilesReadRef>,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentProfilesBaseline { pub header: AgentProfilesHeader, pub collection: Option<ProductCollectionRef> }
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentProfilesChange {
    pub header: AgentProfilesHeader,
    pub base_collection_revision: Option<u64>,
    pub collection: Option<ProductCollectionRef>,
    pub upserted: Vec<ProductEntityRef>,
    pub removed_entries: Vec<u64>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum AgentProfilesEvent {
    Baseline { identity: ProductFeedIdentity, stamp: ProductProjectionStamp, value: AgentProfilesBaseline },
    Change { stamp: ProductProjectionStamp, base_revision: u64, value: AgentProfilesChange },
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase", rename_all_fields = "camelCase", deny_unknown_fields)]
pub enum AgentProfilesFrame {
    Data { delivery_sequence: u64, event: AgentProfilesEvent },
    ResyncRequired { identity: ProductFeedIdentity, reason: ProductResyncReason },
    Failure { identity: ProductFeedIdentity, error: StudioError },
    Closed { identity: ProductFeedIdentity, reason: ProductFeedCloseReason },
}

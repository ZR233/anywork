use super::identity::{
    ConfigurationReadRef, FeedClosedReason, ResyncReason, ThreadCapabilitySupport,
    ThreadFacetStamp, ThreadFeedIdentity,
};
use crate::studio::{ConfigProjectionStamp, StudioError};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ConfigurationValue {
    pub details: ConfigurationReadRef,
    pub sources: ConfigProjectionStamp,
    pub mode_revision: u64,
    pub mode_binding_revision: Option<u64>,
    pub model_route: Option<ModelRouteBrief>,
    pub active_skill_count: u64,
    pub active_mcp: ThreadCapabilitySupport,
    pub active_lsp: ThreadCapabilitySupport,
    pub mcp_health: ThreadCapabilitySupport,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelRouteBrief {
    pub revision: u64,
    pub available: bool,
    pub has_unavailable_reason: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum ConfigurationEvent {
    Baseline {
        identity: ThreadFeedIdentity,
        stamp: ThreadFacetStamp,
        value: ConfigurationValue,
    },
    Replace {
        stamp: ThreadFacetStamp,
        value: ConfigurationValue,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum ConfigurationFrame {
    Data {
        delivery_sequence: u64,
        event: ConfigurationEvent,
    },
    ResyncRequired {
        identity: ThreadFeedIdentity,
        reason: ResyncReason,
    },
    Failure {
        identity: ThreadFeedIdentity,
        error: StudioError,
    },
    Closed {
        identity: ThreadFeedIdentity,
        reason: FeedClosedReason,
    },
}

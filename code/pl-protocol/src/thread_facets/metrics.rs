use super::identity::{
    FeedClosedReason, MetricsIdentityRef, ResyncReason, ThreadFacetStamp, ThreadFeedIdentity,
};
use crate::ThreadRuntimeUsageState;
use crate::studio::StudioError;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct MetricsValue {
    pub live: Option<LiveTurnMetrics>,
    pub authoritative: Option<AuthoritativeTurnMetrics>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LiveTurnMetrics {
    pub identity: MetricsIdentityRef,
    pub completion_tokens: Option<u64>,
    pub response_millis: Option<u64>,
    pub state: ThreadRuntimeUsageState,
    pub observation_sequence: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AuthoritativeTurnMetrics {
    pub identity: MetricsIdentityRef,
    pub completion_tokens: u64,
    pub response_millis: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum MetricsEvent {
    Baseline {
        identity: ThreadFeedIdentity,
        stamp: ThreadFacetStamp,
        value: MetricsValue,
    },
    Replace {
        stamp: ThreadFacetStamp,
        value: MetricsValue,
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
pub enum MetricsFrame {
    Data {
        delivery_sequence: u64,
        event: MetricsEvent,
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

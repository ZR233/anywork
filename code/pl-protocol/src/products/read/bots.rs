//! Bots publications and concrete bot-bound query values. Cursors remain native and opaque.
use serde::{Deserialize, Serialize};

use crate::products::identity::{
    ProductFeedCloseReason, ProductFeedIdentity, ProductProjectionStamp, ProductResyncReason,
};
use crate::products::source::ObservedHeader;
use crate::studio::StudioError;
pub use crate::studio::{BotConversationPage, BotsStateSnapshot, ListBotConversationsRequest};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct BotsHeader {
    pub source: ObservedHeader,
    pub bots_revision: Option<u64>,
    pub updated_at: Option<i64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum BotsEvent {
    Baseline {
        identity: ProductFeedIdentity,
        stamp: ProductProjectionStamp,
        header: BotsHeader,
        state: Option<BotsStateSnapshot>,
    },
    StateChanged {
        stamp: ProductProjectionStamp,
        base_revision: u64,
        header: BotsHeader,
        state: Option<BotsStateSnapshot>,
    },
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, utoipa::ToSchema)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum BotsFrame {
    Data {
        delivery_sequence: u64,
        event: Box<BotsEvent>,
    },
    ResyncRequired {
        identity: ProductFeedIdentity,
        reason: ProductResyncReason,
    },
    Failure {
        identity: ProductFeedIdentity,
        error: StudioError,
    },
    Closed {
        identity: ProductFeedIdentity,
        reason: ProductFeedCloseReason,
    },
}

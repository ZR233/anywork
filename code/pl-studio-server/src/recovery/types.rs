use pl_protocol::products::identity::{
    ProductEntityRef, ProductReadScopeIdentity, ProductSourceStatusRef,
};
use pl_protocol::products::references::RecoveryReadRef;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct RecoveryAckRequest {
    pub delivery_sequence: u64,
}

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct RecoveryOpenReadRequest {
    pub feed_id: String,
    pub reference: RecoveryReadRef,
}

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct RecoveryOpenStatusRequest {
    pub feed_id: String,
    pub reference: ProductSourceStatusRef,
}

#[derive(Serialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct RecoveryOpenReadReply {
    pub scope_id: String,
    pub identity: ProductReadScopeIdentity,
}

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct RecoveryTextRequest {
    pub field_id: u64,
    pub offset: u64,
    #[schema(default = 65536, minimum = 4, maximum = 262144)]
    pub max_bytes: Option<u32>,
}

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct RecoveryListRequest {
    pub list_id: u64,
    pub offset: u64,
    #[schema(default = 32, minimum = 1, maximum = 100)]
    pub limit: Option<u32>,
}

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct RecoveryEntriesRequest {
    pub offset: u64,
    #[schema(default = 32, minimum = 1, maximum = 100)]
    pub limit: Option<u32>,
}

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct RecoveryEntityRequest {
    pub reference: ProductEntityRef,
}

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct RecoveryLookupIssueRequest {
    pub issue_id: String,
}

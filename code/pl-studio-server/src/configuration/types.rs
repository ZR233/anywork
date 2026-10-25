use pl_protocol::products::configuration::ConfigurationRoleReadTarget;
use pl_protocol::products::identity::{
    ProductEntityRef, ProductReadScopeIdentity, ProductSourceStatusRef,
};
use pl_protocol::products::references::ConfigurationReadRef;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct EmptyRequest {}
#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct AckRequest {
    pub delivery_sequence: u64,
}
#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct OpenReadRequest {
    pub feed_id: String,
    pub reference: ConfigurationReadRef,
}
#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct OpenPairRequest {
    pub feed_id: String,
    pub sources: ConfigurationRoleReadTarget,
}
#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct OpenStatusRequest {
    pub feed_id: String,
    pub reference: ProductSourceStatusRef,
}
#[derive(Serialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct OpenReadReply {
    pub scope_id: String,
    pub identity: ProductReadScopeIdentity,
}
#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct TextRequest {
    pub field_id: u64,
    pub offset: u64,
    pub max_bytes: Option<u32>,
}
#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct ListRequest {
    pub list_id: u64,
    pub offset: u64,
    pub limit: Option<u32>,
}
#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct EntriesRequest {
    pub offset: u64,
    pub limit: Option<u32>,
}
#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct EntityRequest {
    pub reference: ProductEntityRef,
}
#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct LookupRequest {
    pub account_id: String,
}
#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct RoleRequest {
    pub role_id: String,
}

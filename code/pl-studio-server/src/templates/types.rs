use pl_protocol::products::identity::ProductReadScopeIdentity;
use pl_protocol::products::references::AccountTemplatesReadRef;
use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct EmptyRequest {}

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct AckRequest {
    pub delivery_sequence: u64,
}

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct OpenReadRequest {
    pub feed_id: String,
    pub reference: AccountTemplatesReadRef,
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
    #[schema(default = 65536, minimum = 4, maximum = 262144)]
    pub max_bytes: Option<u32>,
}

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct ListRequest {
    pub list_id: u64,
    pub offset: u64,
    #[schema(default = 32, minimum = 1, maximum = 100)]
    pub limit: Option<u32>,
}

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct EntriesRequest {
    pub offset: u64,
    #[schema(default = 32, minimum = 1, maximum = 100)]
    pub limit: Option<u32>,
}

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct EntityRequest {
    pub reference: pl_protocol::products::identity::ProductEntityRef,
}

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct LookupRequest {
    pub template_id: String,
}

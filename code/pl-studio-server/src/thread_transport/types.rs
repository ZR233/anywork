use pl_protocol::thread_facets::identity::*;

#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct ExecutionRequest {
    pub mode: ThreadObservationMode,
}

#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct AuthoringRequest {
    pub mode: ThreadObservationMode,
}
#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct TodoOpen {
    pub reference: TodoReadRef,
    pub origin: ThreadFacetStamp,
}
#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct WorkflowOpen {
    pub reference: WorkflowReadRef,
    pub origin: ThreadFacetStamp,
}
#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct PlanDocumentOpen {
    pub reference: pl_protocol::thread_facets::authoring::PlanDocumentRef,
    pub origin: ThreadFacetStamp,
}

#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct TurnOpen {
    pub reference: TurnReadRef,
    pub origin: ThreadFacetStamp,
}
#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct IndexOpen {
    pub reference: InteractionIndexRef,
    pub origin: ThreadFacetStamp,
}
#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct InteractionOpen {
    pub reference: InteractionReadRef,
    pub origin: ThreadFacetStamp,
}
#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct ActivityOpen {
    pub reference: ActivityReadRef,
    pub origin: ThreadFacetStamp,
}
#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct StorageOpen {
    pub reference: StorageReadRef,
    pub origin: ThreadFacetStamp,
}
#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct ResolveInteraction {
    pub interaction_id: String,
    pub revision: u64,
    pub origin: ThreadFacetStamp,
}
#[derive(serde::Serialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub(super) struct ReadReply {
    pub identity: ReadScopeIdentity,
}
#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct Ack {
    pub delivery_sequence: u64,
}

#[derive(serde::Deserialize, utoipa::IntoParams)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[into_params(parameter_in = Query, rename_all = "camelCase")]
pub(super) struct PageQuery {
    pub offset: Option<u64>,
    pub limit: Option<u32>,
}
impl PageQuery {
    pub fn offset(&self) -> u64 {
        self.offset.unwrap_or(0)
    }
    pub fn limit(&self) -> u32 {
        self.limit.unwrap_or(32)
    }
}
#[derive(serde::Deserialize, utoipa::IntoParams)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[into_params(parameter_in = Query, rename_all = "camelCase")]
pub(super) struct TextQuery {
    pub field_id: u64,
    pub offset: Option<u64>,
    pub max_bytes: Option<u32>,
}

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[derive(utoipa::ToSchema)]
pub enum ProductResource {
    ProjectDirectory,
    ThreadDirectory,
    AgentDirectory,
    Configuration,
    ModelCatalog,
    AccountTemplates,
    AgentProfiles,
    ModeCatalog,
    AccountUsage,
    PerformanceSummaries,
    PerformanceHistory,
    SessionCosts,
    Recovery,
    Mcp,
    Lsp,
    Skills,
    Persistence,
    PersistenceQueue,
    Updates,
    Bots,
    AcpAuth,
    AcpInstall,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ProductFeedIdentity {
    pub feed_id: String,
    pub owner_epoch: String,
    pub incarnation: u64,
    pub resource: ProductResource,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ProductProjectionStamp {
    pub owner_epoch: String,
    pub incarnation: u64,
    pub revision: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ProductReadOrigin {
    pub owner_epoch: String,
    pub incarnation: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
#[derive(utoipa::ToSchema)]
pub enum ProductReadVersion {
    Value { entry: u64, revision: u64 },
    SourceStatus { entry: u64, revision: u64 },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ProductReadScopeIdentity {
    pub scope_id: String,
    pub owner_epoch: String,
    pub incarnation: u64,
    pub version: ProductReadVersion,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ProductSourceStatusRef {
    pub entry: u64,
    pub revision: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ProductEntityRef {
    pub entry: u64,
    pub revision: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[derive(utoipa::ToSchema)]
pub struct ProductCollectionRef {
    pub entry: u64,
    pub revision: u64,
    pub total: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[derive(utoipa::ToSchema)]
pub enum ProductResyncReason {
    SourceLagged,
    ReliableQueueFull,
    RevisionGap,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
#[derive(utoipa::ToSchema)]
pub enum ProductFeedCloseReason {
    Requested,
    OwnerReplaced,
    RuntimeStopped,
}

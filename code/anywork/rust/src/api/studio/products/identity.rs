#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeProductResource {
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
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeProductFeedIdentity {
    pub feed_id: String,
    pub owner_epoch: String,
    pub incarnation: u64,
    pub resource: BridgeProductResource,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeProductProjectionStamp {
    pub owner_epoch: String,
    pub incarnation: u64,
    pub revision: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeProductReadOrigin {
    pub owner_epoch: String,
    pub incarnation: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeProductReadVersion {
    Value { entry: u64, revision: u64 },
    SourceStatus { entry: u64, revision: u64 },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeProductReadScopeIdentity {
    pub scope_id: String,
    pub owner_epoch: String,
    pub incarnation: u64,
    pub version: BridgeProductReadVersion,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeProductSourceStatusRef {
    pub entry: u64,
    pub revision: u64,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeProductEntityRef {
    pub entry: u64,
    pub revision: u64,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeProductCollectionRef {
    pub entry: u64,
    pub revision: u64,
    pub total: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeProductResyncReason {
    SourceLagged,
    ReliableQueueFull,
    RevisionGap,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeProductFeedCloseReason {
    Requested,
    OwnerReplaced,
    RuntimeStopped,
}

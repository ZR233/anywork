//! Thread identity is bound to the original open, never reconstructed from the current selection.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadFacet {
    Execution,
    Metrics,
    Context,
    Configuration,
    Authoring,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadObservationMode {
    Live,
    Cold,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadFeedIdentity {
    pub feed_id: String,
    pub runtime_epoch: String,
    pub incarnation: u64,
    pub facet: BridgeThreadFacet,
    pub mode: BridgeThreadObservationMode,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadFacetStamp {
    pub runtime_epoch: String,
    pub incarnation: u64,
    pub facet: BridgeThreadFacet,
    pub revision: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeReadScopeIdentity {
    pub scope_id: String,
    pub runtime_epoch: String,
    pub incarnation: u64,
    pub source_revision: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeResyncReason {
    SourceLagged,
    ReliableQueueFull,
    RevisionGap,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeFeedClosedReason {
    Requested,
    OwnerReplaced,
    RuntimeStopped,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadCapabilitySupport {
    Unsupported,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeTurnReadRef {
    pub entry: u64,
    pub revision: u64,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeInteractionReadRef {
    pub entry: u64,
    pub revision: u64,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeInteractionIndexRef {
    pub entry: u64,
    pub revision: u64,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeActivityReadRef {
    pub entry: u64,
    pub revision: u64,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeStorageReadRef {
    pub entry: u64,
    pub revision: u64,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeContextReadRef {
    pub entry: u64,
    pub revision: u64,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeThreadConfigurationReadRef {
    pub entry: u64,
    pub revision: u64,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeTodoReadRef {
    pub entry: u64,
    pub revision: u64,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeWorkflowReadRef {
    pub entry: u64,
    pub revision: u64,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeMetricsIdentityRef {
    pub entry: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeConfigProjectionStamp {
    pub settings_revision: u64,
    pub model_catalog_revision: u64,
    pub closing: bool,
}

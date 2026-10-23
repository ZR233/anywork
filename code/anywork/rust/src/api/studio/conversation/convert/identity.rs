use pl_protocol::thread_facets::identity as protocol;
use super::super::identity as bridge;

impl From<protocol::ThreadFacet> for bridge::BridgeThreadFacet {
    fn from(value: protocol::ThreadFacet) -> Self {
        match value {
            protocol::ThreadFacet::Execution => Self::Execution,
            protocol::ThreadFacet::Metrics => Self::Metrics,
            protocol::ThreadFacet::Context => Self::Context,
            protocol::ThreadFacet::Configuration => Self::Configuration,
            protocol::ThreadFacet::Authoring => Self::Authoring,
        }
    }
}

impl From<protocol::ThreadObservationMode> for bridge::BridgeThreadObservationMode {
    fn from(value: protocol::ThreadObservationMode) -> Self {
        match value { protocol::ThreadObservationMode::Live => Self::Live, protocol::ThreadObservationMode::Cold => Self::Cold }
    }
}

impl From<protocol::ThreadFeedIdentity> for bridge::BridgeThreadFeedIdentity {
    fn from(value: protocol::ThreadFeedIdentity) -> Self {
        Self { feed_id: value.feed_id, runtime_epoch: value.runtime_epoch, incarnation: value.incarnation,
            facet: value.facet.into(), mode: value.mode.into() }
    }
}

impl From<protocol::ThreadFacetStamp> for bridge::BridgeThreadFacetStamp {
    fn from(value: protocol::ThreadFacetStamp) -> Self {
        Self { runtime_epoch: value.runtime_epoch, incarnation: value.incarnation,
            facet: value.facet.into(), revision: value.revision }
    }
}

impl From<bridge::BridgeThreadFacetStamp> for protocol::ThreadFacetStamp {
    fn from(value: bridge::BridgeThreadFacetStamp) -> Self {
        let facet = match value.facet {
            bridge::BridgeThreadFacet::Execution => protocol::ThreadFacet::Execution,
            bridge::BridgeThreadFacet::Metrics => protocol::ThreadFacet::Metrics,
            bridge::BridgeThreadFacet::Context => protocol::ThreadFacet::Context,
            bridge::BridgeThreadFacet::Configuration => protocol::ThreadFacet::Configuration,
            bridge::BridgeThreadFacet::Authoring => protocol::ThreadFacet::Authoring,
        };
        Self { runtime_epoch: value.runtime_epoch, incarnation: value.incarnation, facet, revision: value.revision }
    }
}

impl From<protocol::ReadScopeIdentity> for bridge::BridgeReadScopeIdentity {
    fn from(value: protocol::ReadScopeIdentity) -> Self {
        Self { scope_id: value.scope_id, runtime_epoch: value.runtime_epoch,
            incarnation: value.incarnation, source_revision: value.source_revision }
    }
}

impl From<protocol::ResyncReason> for bridge::BridgeResyncReason {
    fn from(value: protocol::ResyncReason) -> Self {
        match value {
            protocol::ResyncReason::SourceLagged => Self::SourceLagged,
            protocol::ResyncReason::ReliableQueueFull => Self::ReliableQueueFull,
            protocol::ResyncReason::RevisionGap => Self::RevisionGap,
        }
    }
}

impl From<protocol::FeedClosedReason> for bridge::BridgeFeedClosedReason {
    fn from(value: protocol::FeedClosedReason) -> Self {
        match value {
            protocol::FeedClosedReason::Requested => Self::Requested,
            protocol::FeedClosedReason::OwnerReplaced => Self::OwnerReplaced,
            protocol::FeedClosedReason::RuntimeStopped => Self::RuntimeStopped,
        }
    }
}

impl From<protocol::ThreadCapabilitySupport> for bridge::BridgeThreadCapabilitySupport {
    fn from(value: protocol::ThreadCapabilitySupport) -> Self {
        match value { protocol::ThreadCapabilitySupport::Unsupported => Self::Unsupported }
    }
}

impl From<pl_protocol::studio::ConfigProjectionStamp> for bridge::BridgeConfigProjectionStamp {
    fn from(value: pl_protocol::studio::ConfigProjectionStamp) -> Self {
        Self { settings_revision: value.settings_revision, model_catalog_revision: value.model_catalog_revision, closing: value.closing }
    }
}

impl From<protocol::TurnReadRef> for bridge::BridgeTurnReadRef {
    fn from(value: protocol::TurnReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<protocol::InteractionReadRef> for bridge::BridgeInteractionReadRef {
    fn from(value: protocol::InteractionReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<protocol::InteractionIndexRef> for bridge::BridgeInteractionIndexRef {
    fn from(value: protocol::InteractionIndexRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<protocol::ActivityReadRef> for bridge::BridgeActivityReadRef {
    fn from(value: protocol::ActivityReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<protocol::StorageReadRef> for bridge::BridgeStorageReadRef {
    fn from(value: protocol::StorageReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<protocol::ContextReadRef> for bridge::BridgeContextReadRef {
    fn from(value: protocol::ContextReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<protocol::ConfigurationReadRef> for bridge::BridgeConfigurationReadRef {
    fn from(value: protocol::ConfigurationReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<protocol::TodoReadRef> for bridge::BridgeTodoReadRef {
    fn from(value: protocol::TodoReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<protocol::WorkflowReadRef> for bridge::BridgeWorkflowReadRef {
    fn from(value: protocol::WorkflowReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<protocol::MetricsIdentityRef> for bridge::BridgeMetricsIdentityRef {
    fn from(value: protocol::MetricsIdentityRef) -> Self { Self { entry: value.entry } }
}

impl From<bridge::BridgeMetricsIdentityRef> for protocol::MetricsIdentityRef {
    fn from(value: bridge::BridgeMetricsIdentityRef) -> Self { Self { entry: value.entry } }
}

use super::super::identity as bridge;
use pl_protocol::products::identity as protocol;

impl From<protocol::ProductResource> for bridge::BridgeProductResource {
    fn from(value: protocol::ProductResource) -> Self {
        match value {
            protocol::ProductResource::ProjectDirectory => Self::ProjectDirectory,
            protocol::ProductResource::ThreadDirectory => Self::ThreadDirectory,
            protocol::ProductResource::AgentDirectory => Self::AgentDirectory,
            protocol::ProductResource::Configuration => Self::Configuration,
            protocol::ProductResource::ModelCatalog => Self::ModelCatalog,
            protocol::ProductResource::AccountTemplates => Self::AccountTemplates,
            protocol::ProductResource::AgentProfiles => Self::AgentProfiles,
            protocol::ProductResource::ModeCatalog => Self::ModeCatalog,
            protocol::ProductResource::AccountUsage => Self::AccountUsage,
            protocol::ProductResource::PerformanceSummaries => Self::PerformanceSummaries,
            protocol::ProductResource::PerformanceHistory => Self::PerformanceHistory,
            protocol::ProductResource::SessionCosts => Self::SessionCosts,
            protocol::ProductResource::Recovery => Self::Recovery,
            protocol::ProductResource::Mcp => Self::Mcp,
            protocol::ProductResource::Lsp => Self::Lsp,
            protocol::ProductResource::Skills => Self::Skills,
            protocol::ProductResource::Persistence => Self::Persistence,
            protocol::ProductResource::PersistenceQueue => Self::PersistenceQueue,
            protocol::ProductResource::Updates => Self::Updates,
            protocol::ProductResource::Bots => Self::Bots,
        }
    }
}

impl From<protocol::ProductFeedIdentity> for bridge::BridgeProductFeedIdentity {
    fn from(value: protocol::ProductFeedIdentity) -> Self {
        Self {
            feed_id: value.feed_id,
            owner_epoch: value.owner_epoch,
            incarnation: value.incarnation,
            resource: value.resource.into(),
        }
    }
}

impl From<protocol::ProductProjectionStamp> for bridge::BridgeProductProjectionStamp {
    fn from(value: protocol::ProductProjectionStamp) -> Self {
        Self {
            owner_epoch: value.owner_epoch,
            incarnation: value.incarnation,
            revision: value.revision,
        }
    }
}

impl From<protocol::ProductReadOrigin> for bridge::BridgeProductReadOrigin {
    fn from(value: protocol::ProductReadOrigin) -> Self {
        Self {
            owner_epoch: value.owner_epoch,
            incarnation: value.incarnation,
        }
    }
}

impl From<bridge::BridgeProductReadOrigin> for protocol::ProductReadOrigin {
    fn from(value: bridge::BridgeProductReadOrigin) -> Self {
        Self {
            owner_epoch: value.owner_epoch,
            incarnation: value.incarnation,
        }
    }
}

impl From<protocol::ProductReadVersion> for bridge::BridgeProductReadVersion {
    fn from(value: protocol::ProductReadVersion) -> Self {
        match value {
            protocol::ProductReadVersion::Value { entry, revision } => {
                Self::Value { entry, revision }
            }
            protocol::ProductReadVersion::SourceStatus { entry, revision } => {
                Self::SourceStatus { entry, revision }
            }
        }
    }
}

impl From<protocol::ProductReadScopeIdentity> for bridge::BridgeProductReadScopeIdentity {
    fn from(value: protocol::ProductReadScopeIdentity) -> Self {
        Self {
            scope_id: value.scope_id,
            owner_epoch: value.owner_epoch,
            incarnation: value.incarnation,
            version: value.version.into(),
        }
    }
}

impl From<protocol::ProductSourceStatusRef> for bridge::BridgeProductSourceStatusRef {
    fn from(value: protocol::ProductSourceStatusRef) -> Self {
        Self {
            entry: value.entry,
            revision: value.revision,
        }
    }
}

impl From<bridge::BridgeProductSourceStatusRef> for protocol::ProductSourceStatusRef {
    fn from(value: bridge::BridgeProductSourceStatusRef) -> Self {
        Self {
            entry: value.entry,
            revision: value.revision,
        }
    }
}

impl From<protocol::ProductEntityRef> for bridge::BridgeProductEntityRef {
    fn from(value: protocol::ProductEntityRef) -> Self {
        Self {
            entry: value.entry,
            revision: value.revision,
        }
    }
}

impl From<bridge::BridgeProductEntityRef> for protocol::ProductEntityRef {
    fn from(value: bridge::BridgeProductEntityRef) -> Self {
        Self {
            entry: value.entry,
            revision: value.revision,
        }
    }
}

impl From<protocol::ProductCollectionRef> for bridge::BridgeProductCollectionRef {
    fn from(value: protocol::ProductCollectionRef) -> Self {
        Self {
            entry: value.entry,
            revision: value.revision,
            total: value.total,
        }
    }
}

impl From<bridge::BridgeProductCollectionRef> for protocol::ProductCollectionRef {
    fn from(value: bridge::BridgeProductCollectionRef) -> Self {
        Self {
            entry: value.entry,
            revision: value.revision,
            total: value.total,
        }
    }
}

impl From<protocol::ProductResyncReason> for bridge::BridgeProductResyncReason {
    fn from(value: protocol::ProductResyncReason) -> Self {
        match value {
            protocol::ProductResyncReason::SourceLagged => Self::SourceLagged,
            protocol::ProductResyncReason::ReliableQueueFull => Self::ReliableQueueFull,
            protocol::ProductResyncReason::RevisionGap => Self::RevisionGap,
        }
    }
}

impl From<protocol::ProductFeedCloseReason> for bridge::BridgeProductFeedCloseReason {
    fn from(value: protocol::ProductFeedCloseReason) -> Self {
        match value {
            protocol::ProductFeedCloseReason::Requested => Self::Requested,
            protocol::ProductFeedCloseReason::OwnerReplaced => Self::OwnerReplaced,
            protocol::ProductFeedCloseReason::RuntimeStopped => Self::RuntimeStopped,
        }
    }
}

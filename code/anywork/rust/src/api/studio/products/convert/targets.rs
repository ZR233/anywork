use super::super::references as bridge;
use pl_protocol::products::references as protocol;

// A command target always carries its original origin. Conversion never consults a current feed
// to fill it, and collection/source metadata revisions are not substituted for this reference.
impl From<protocol::ProjectDirectoryReadTarget> for bridge::BridgeProjectDirectoryReadTarget {
    fn from(value: protocol::ProjectDirectoryReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}
impl From<protocol::ThreadDirectoryReadTarget> for bridge::BridgeThreadDirectoryReadTarget {
    fn from(value: protocol::ThreadDirectoryReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}
impl From<protocol::AgentDirectoryReadTarget> for bridge::BridgeAgentDirectoryReadTarget {
    fn from(value: protocol::AgentDirectoryReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}
impl From<protocol::ConfigurationReadTarget> for bridge::BridgeConfigurationReadTarget {
    fn from(value: protocol::ConfigurationReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}
impl From<protocol::ModelCatalogReadTarget> for bridge::BridgeModelCatalogReadTarget {
    fn from(value: protocol::ModelCatalogReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}
impl From<protocol::AccountTemplatesReadTarget> for bridge::BridgeAccountTemplatesReadTarget {
    fn from(value: protocol::AccountTemplatesReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}
impl From<protocol::AgentProfilesReadTarget> for bridge::BridgeAgentProfilesReadTarget {
    fn from(value: protocol::AgentProfilesReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}
impl From<protocol::ModeCatalogReadTarget> for bridge::BridgeModeCatalogReadTarget {
    fn from(value: protocol::ModeCatalogReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}
impl From<protocol::AccountUsageReadTarget> for bridge::BridgeAccountUsageReadTarget {
    fn from(value: protocol::AccountUsageReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}
impl From<protocol::PerformanceSummariesReadTarget>
    for bridge::BridgePerformanceSummariesReadTarget
{
    fn from(value: protocol::PerformanceSummariesReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}
impl From<protocol::PerformanceHistoryReadTarget> for bridge::BridgePerformanceHistoryReadTarget {
    fn from(value: protocol::PerformanceHistoryReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}
impl From<protocol::SessionCostsReadTarget> for bridge::BridgeSessionCostsReadTarget {
    fn from(value: protocol::SessionCostsReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}
impl From<protocol::RecoveryReadTarget> for bridge::BridgeRecoveryReadTarget {
    fn from(value: protocol::RecoveryReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}
impl From<protocol::McpReadTarget> for bridge::BridgeMcpReadTarget {
    fn from(value: protocol::McpReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}
impl From<protocol::LspReadTarget> for bridge::BridgeLspReadTarget {
    fn from(value: protocol::LspReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}
impl From<protocol::SkillsReadTarget> for bridge::BridgeSkillsReadTarget {
    fn from(value: protocol::SkillsReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}
impl From<protocol::PersistenceReadTarget> for bridge::BridgePersistenceReadTarget {
    fn from(value: protocol::PersistenceReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}
impl From<protocol::PersistenceQueueReadTarget> for bridge::BridgePersistenceQueueReadTarget {
    fn from(value: protocol::PersistenceQueueReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}
impl From<protocol::UpdatesReadTarget> for bridge::BridgeUpdatesReadTarget {
    fn from(value: protocol::UpdatesReadTarget) -> Self {
        Self {
            origin: value.origin.into(),
            reference: value.reference.into(),
        }
    }
}

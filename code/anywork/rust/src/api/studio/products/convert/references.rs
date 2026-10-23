use pl_protocol::products::references as protocol;
use super::super::references as bridge;

impl From<protocol::ProjectDirectoryReadRef> for bridge::BridgeProjectDirectoryReadRef {
    fn from(value: protocol::ProjectDirectoryReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeProjectDirectoryReadRef> for protocol::ProjectDirectoryReadRef {
    fn from(value: bridge::BridgeProjectDirectoryReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::ThreadDirectoryReadRef> for bridge::BridgeThreadDirectoryReadRef {
    fn from(value: protocol::ThreadDirectoryReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeThreadDirectoryReadRef> for protocol::ThreadDirectoryReadRef {
    fn from(value: bridge::BridgeThreadDirectoryReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::AgentDirectoryReadRef> for bridge::BridgeAgentDirectoryReadRef {
    fn from(value: protocol::AgentDirectoryReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeAgentDirectoryReadRef> for protocol::AgentDirectoryReadRef {
    fn from(value: bridge::BridgeAgentDirectoryReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::ConfigurationReadRef> for bridge::BridgeConfigurationReadRef {
    fn from(value: protocol::ConfigurationReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeConfigurationReadRef> for protocol::ConfigurationReadRef {
    fn from(value: bridge::BridgeConfigurationReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::ModelCatalogReadRef> for bridge::BridgeModelCatalogReadRef {
    fn from(value: protocol::ModelCatalogReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeModelCatalogReadRef> for protocol::ModelCatalogReadRef {
    fn from(value: bridge::BridgeModelCatalogReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::AccountTemplatesReadRef> for bridge::BridgeAccountTemplatesReadRef {
    fn from(value: protocol::AccountTemplatesReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeAccountTemplatesReadRef> for protocol::AccountTemplatesReadRef {
    fn from(value: bridge::BridgeAccountTemplatesReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::AgentProfilesReadRef> for bridge::BridgeAgentProfilesReadRef {
    fn from(value: protocol::AgentProfilesReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeAgentProfilesReadRef> for protocol::AgentProfilesReadRef {
    fn from(value: bridge::BridgeAgentProfilesReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::ModeCatalogReadRef> for bridge::BridgeModeCatalogReadRef {
    fn from(value: protocol::ModeCatalogReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeModeCatalogReadRef> for protocol::ModeCatalogReadRef {
    fn from(value: bridge::BridgeModeCatalogReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::AccountUsageReadRef> for bridge::BridgeAccountUsageReadRef {
    fn from(value: protocol::AccountUsageReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeAccountUsageReadRef> for protocol::AccountUsageReadRef {
    fn from(value: bridge::BridgeAccountUsageReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::PerformanceSummariesReadRef> for bridge::BridgePerformanceSummariesReadRef {
    fn from(value: protocol::PerformanceSummariesReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgePerformanceSummariesReadRef> for protocol::PerformanceSummariesReadRef {
    fn from(value: bridge::BridgePerformanceSummariesReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::PerformanceHistoryReadRef> for bridge::BridgePerformanceHistoryReadRef {
    fn from(value: protocol::PerformanceHistoryReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgePerformanceHistoryReadRef> for protocol::PerformanceHistoryReadRef {
    fn from(value: bridge::BridgePerformanceHistoryReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::SessionCostsReadRef> for bridge::BridgeSessionCostsReadRef {
    fn from(value: protocol::SessionCostsReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeSessionCostsReadRef> for protocol::SessionCostsReadRef {
    fn from(value: bridge::BridgeSessionCostsReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::RecoveryReadRef> for bridge::BridgeRecoveryReadRef {
    fn from(value: protocol::RecoveryReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeRecoveryReadRef> for protocol::RecoveryReadRef {
    fn from(value: bridge::BridgeRecoveryReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::McpReadRef> for bridge::BridgeMcpReadRef {
    fn from(value: protocol::McpReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeMcpReadRef> for protocol::McpReadRef {
    fn from(value: bridge::BridgeMcpReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::LspReadRef> for bridge::BridgeLspReadRef {
    fn from(value: protocol::LspReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeLspReadRef> for protocol::LspReadRef {
    fn from(value: bridge::BridgeLspReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::SkillsReadRef> for bridge::BridgeSkillsReadRef {
    fn from(value: protocol::SkillsReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeSkillsReadRef> for protocol::SkillsReadRef {
    fn from(value: bridge::BridgeSkillsReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::PersistenceReadRef> for bridge::BridgePersistenceReadRef {
    fn from(value: protocol::PersistenceReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgePersistenceReadRef> for protocol::PersistenceReadRef {
    fn from(value: bridge::BridgePersistenceReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::PersistenceQueueReadRef> for bridge::BridgePersistenceQueueReadRef {
    fn from(value: protocol::PersistenceQueueReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgePersistenceQueueReadRef> for protocol::PersistenceQueueReadRef {
    fn from(value: bridge::BridgePersistenceQueueReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::UpdatesReadRef> for bridge::BridgeUpdatesReadRef {
    fn from(value: protocol::UpdatesReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeUpdatesReadRef> for protocol::UpdatesReadRef {
    fn from(value: bridge::BridgeUpdatesReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::PerformanceSummaryIdentityRef> for bridge::BridgePerformanceSummaryIdentityRef {
    fn from(value: protocol::PerformanceSummaryIdentityRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgePerformanceSummaryIdentityRef> for protocol::PerformanceSummaryIdentityRef {
    fn from(value: bridge::BridgePerformanceSummaryIdentityRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::PerformanceEffortIdentityRef> for bridge::BridgePerformanceEffortIdentityRef {
    fn from(value: protocol::PerformanceEffortIdentityRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgePerformanceEffortIdentityRef> for protocol::PerformanceEffortIdentityRef {
    fn from(value: bridge::BridgePerformanceEffortIdentityRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::PerformanceSampleIdentityRef> for bridge::BridgePerformanceSampleIdentityRef {
    fn from(value: protocol::PerformanceSampleIdentityRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgePerformanceSampleIdentityRef> for protocol::PerformanceSampleIdentityRef {
    fn from(value: bridge::BridgePerformanceSampleIdentityRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::UpdateSummaryReadRef> for bridge::BridgeUpdateSummaryReadRef {
    fn from(value: protocol::UpdateSummaryReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeUpdateSummaryReadRef> for protocol::UpdateSummaryReadRef {
    fn from(value: bridge::BridgeUpdateSummaryReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::UpdateOperationReadRef> for bridge::BridgeUpdateOperationReadRef {
    fn from(value: protocol::UpdateOperationReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeUpdateOperationReadRef> for protocol::UpdateOperationReadRef {
    fn from(value: bridge::BridgeUpdateOperationReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::UpdateErrorReadRef> for bridge::BridgeUpdateErrorReadRef {
    fn from(value: protocol::UpdateErrorReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeUpdateErrorReadRef> for protocol::UpdateErrorReadRef {
    fn from(value: bridge::BridgeUpdateErrorReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

impl From<protocol::UpdateDetailsReadRef> for bridge::BridgeUpdateDetailsReadRef {
    fn from(value: protocol::UpdateDetailsReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}
impl From<bridge::BridgeUpdateDetailsReadRef> for protocol::UpdateDetailsReadRef {
    fn from(value: bridge::BridgeUpdateDetailsReadRef) -> Self { Self { entry: value.entry, revision: value.revision } }
}

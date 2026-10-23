use super::identity::BridgeProductReadOrigin;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeProjectDirectoryReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeThreadDirectoryReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeAgentDirectoryReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeConfigurationReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeModelCatalogReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeAccountTemplatesReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeAgentProfilesReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeModeCatalogReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeAccountUsageReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgePerformanceSummariesReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgePerformanceHistoryReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeSessionCostsReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeRecoveryReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeMcpReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeLspReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeSkillsReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgePersistenceReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgePersistenceQueueReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeUpdatesReadRef { pub entry: u64, pub revision: u64 }

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeProjectDirectoryReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgeProjectDirectoryReadRef }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeThreadDirectoryReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgeThreadDirectoryReadRef }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentDirectoryReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgeAgentDirectoryReadRef }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeConfigurationReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgeConfigurationReadRef }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModelCatalogReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgeModelCatalogReadRef }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountTemplatesReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgeAccountTemplatesReadRef }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAgentProfilesReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgeAgentProfilesReadRef }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeModeCatalogReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgeModeCatalogReadRef }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeAccountUsageReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgeAccountUsageReadRef }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePerformanceSummariesReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgePerformanceSummariesReadRef }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePerformanceHistoryReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgePerformanceHistoryReadRef }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSessionCostsReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgeSessionCostsReadRef }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeRecoveryReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgeRecoveryReadRef }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeMcpReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgeMcpReadRef }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeLspReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgeLspReadRef }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeSkillsReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgeSkillsReadRef }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePersistenceReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgePersistenceReadRef }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgePersistenceQueueReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgePersistenceQueueReadRef }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeUpdatesReadTarget { pub origin: BridgeProductReadOrigin, pub reference: BridgeUpdatesReadRef }

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgePerformanceSummaryIdentityRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgePerformanceEffortIdentityRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgePerformanceSampleIdentityRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeUpdateSummaryReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeUpdateOperationReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeUpdateErrorReadRef { pub entry: u64, pub revision: u64 }
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeUpdateDetailsReadRef { pub entry: u64, pub revision: u64 }

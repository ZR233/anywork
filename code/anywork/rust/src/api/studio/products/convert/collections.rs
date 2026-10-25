use super::super::feed as bridge;
use pl_protocol::products::feed as protocol;

// Only these nominal From impls repeat the exact same fixed collection schema. A generic
// function cannot implement From for distinct concrete wire types; no payload or owner is erased.
macro_rules! collection_values {
    ($module:ident, $baseline:ident, $bridge_baseline:ident, $change:ident, $bridge_change:ident) => {
        impl From<protocol::$module::$baseline> for bridge::$module::$bridge_baseline {
            fn from(value: protocol::$module::$baseline) -> Self {
                let protocol::$module::$baseline { header, collection } = value;
                Self {
                    header: header.into(),
                    collection: collection.map(Into::into),
                }
            }
        }
        impl From<protocol::$module::$change> for bridge::$module::$bridge_change {
            fn from(value: protocol::$module::$change) -> Self {
                let protocol::$module::$change {
                    header,
                    base_collection_revision,
                    collection,
                    upserted,
                    removed_entries,
                } = value;
                Self {
                    header: header.into(),
                    base_collection_revision,
                    collection: collection.map(Into::into),
                    upserted: upserted.into_iter().map(Into::into).collect(),
                    removed_entries,
                }
            }
        }
    };
}

collection_values!(
    project_directory,
    ProjectDirectoryBaseline,
    BridgeProjectDirectoryBaseline,
    ProjectDirectoryChange,
    BridgeProjectDirectoryChange
);
collection_values!(
    thread_directory,
    ThreadDirectoryBaseline,
    BridgeThreadDirectoryBaseline,
    ThreadDirectoryChange,
    BridgeThreadDirectoryChange
);
collection_values!(
    agent_directory,
    AgentDirectoryBaseline,
    BridgeAgentDirectoryBaseline,
    AgentDirectoryChange,
    BridgeAgentDirectoryChange
);
collection_values!(
    configuration,
    ConfigurationBaseline,
    BridgeConfigurationBaseline,
    ConfigurationChange,
    BridgeConfigurationChange
);
collection_values!(
    model_catalog,
    ModelCatalogBaseline,
    BridgeModelCatalogBaseline,
    ModelCatalogChange,
    BridgeModelCatalogChange
);
collection_values!(
    account_templates,
    AccountTemplatesBaseline,
    BridgeAccountTemplatesBaseline,
    AccountTemplatesChange,
    BridgeAccountTemplatesChange
);
collection_values!(
    agent_profiles,
    AgentProfilesBaseline,
    BridgeAgentProfilesBaseline,
    AgentProfilesChange,
    BridgeAgentProfilesChange
);
collection_values!(
    mode_catalog,
    ModeCatalogBaseline,
    BridgeModeCatalogBaseline,
    ModeCatalogChange,
    BridgeModeCatalogChange
);
collection_values!(
    account_usage,
    AccountUsageBaseline,
    BridgeAccountUsageBaseline,
    AccountUsageChange,
    BridgeAccountUsageChange
);
collection_values!(
    performance_summaries,
    PerformanceSummariesBaseline,
    BridgePerformanceSummariesBaseline,
    PerformanceSummariesChange,
    BridgePerformanceSummariesChange
);
collection_values!(
    performance_history,
    PerformanceHistoryBaseline,
    BridgePerformanceHistoryBaseline,
    PerformanceHistoryChange,
    BridgePerformanceHistoryChange
);
collection_values!(
    recovery,
    RecoveryBaseline,
    BridgeRecoveryBaseline,
    RecoveryChange,
    BridgeRecoveryChange
);
collection_values!(
    mcp,
    McpBaseline,
    BridgeMcpBaseline,
    McpChange,
    BridgeMcpChange
);
collection_values!(
    lsp,
    LspBaseline,
    BridgeLspBaseline,
    LspChange,
    BridgeLspChange
);
collection_values!(
    skills,
    SkillsBaseline,
    BridgeSkillsBaseline,
    SkillsChange,
    BridgeSkillsChange
);
collection_values!(
    persistence_queue,
    PersistenceQueueBaseline,
    BridgePersistenceQueueBaseline,
    PersistenceQueueChange,
    BridgePersistenceQueueChange
);

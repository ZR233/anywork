use super::super::feed as bridge;
use pl_protocol::products::feed as protocol;

// This macro only removes nominal enum-match boilerplate that generics cannot express. Header
// fields are mapped explicitly in headers.rs; every event/frame variant remains exhaustive.
macro_rules! feed_frames {
    ($module:ident, $event:ident, $bridge_event:ident, $frame:ident, $bridge_frame:ident, $change:ident, boxed) => {
        feed_frames!(@frames $module, $event, $bridge_event, $frame, $bridge_frame, $change, |event: Box<protocol::$module::$event>| *event);
    };
    ($module:ident, $event:ident, $bridge_event:ident, $frame:ident, $bridge_frame:ident, $change:ident) => {
        feed_frames!(@frames $module, $event, $bridge_event, $frame, $bridge_frame, $change, |event: protocol::$module::$event| event);
    };
    (@frames $module:ident, $event:ident, $bridge_event:ident, $frame:ident, $bridge_frame:ident, $change:ident, $take:expr) => {
        impl From<protocol::$module::$event> for bridge::$module::$bridge_event {
            fn from(value: protocol::$module::$event) -> Self {
                match value {
                    protocol::$module::$event::Baseline {
                        identity,
                        stamp,
                        value,
                    } => Self::Baseline {
                        identity: identity.into(),
                        stamp: stamp.into(),
                        value: value.into(),
                    },
                    protocol::$module::$event::$change {
                        stamp,
                        base_revision,
                        value,
                    } => Self::$change {
                        stamp: stamp.into(),
                        base_revision,
                        value: value.into(),
                    },
                }
            }
        }
        impl From<protocol::$module::$frame> for bridge::$module::$bridge_frame {
            fn from(value: protocol::$module::$frame) -> Self {
                match value {
                    protocol::$module::$frame::Data {
                        delivery_sequence,
                        event,
                    } => Self::Data {
                        delivery_sequence,
                        event: ($take)(event).into(),
                    },
                    protocol::$module::$frame::ResyncRequired { identity, reason } => {
                        Self::ResyncRequired {
                            identity: identity.into(),
                            reason: reason.into(),
                        }
                    }
                    protocol::$module::$frame::Failure { identity, error } => Self::Failure {
                        identity: identity.into(),
                        error: error.into(),
                    },
                    protocol::$module::$frame::Closed { identity, reason } => Self::Closed {
                        identity: identity.into(),
                        reason: reason.into(),
                    },
                }
            }
        }
    };
}

feed_frames!(
    project_directory,
    ProjectDirectoryEvent,
    BridgeProjectDirectoryEvent,
    ProjectDirectoryFrame,
    BridgeProjectDirectoryFrame,
    Change
);
feed_frames!(
    thread_directory,
    ThreadDirectoryEvent,
    BridgeThreadDirectoryEvent,
    ThreadDirectoryFrame,
    BridgeThreadDirectoryFrame,
    Change
);
feed_frames!(
    agent_directory,
    AgentDirectoryEvent,
    BridgeAgentDirectoryEvent,
    AgentDirectoryFrame,
    BridgeAgentDirectoryFrame,
    Change
);
feed_frames!(
    configuration,
    ConfigurationEvent,
    BridgeConfigurationEvent,
    ConfigurationFrame,
    BridgeConfigurationFrame,
    Change,
    boxed
);
feed_frames!(
    model_catalog,
    ModelCatalogEvent,
    BridgeModelCatalogEvent,
    ModelCatalogFrame,
    BridgeModelCatalogFrame,
    Change
);
feed_frames!(
    account_templates,
    AccountTemplatesEvent,
    BridgeAccountTemplatesEvent,
    AccountTemplatesFrame,
    BridgeAccountTemplatesFrame,
    Change
);
feed_frames!(
    agent_profiles,
    AgentProfilesEvent,
    BridgeAgentProfilesEvent,
    AgentProfilesFrame,
    BridgeAgentProfilesFrame,
    Change
);
feed_frames!(
    mode_catalog,
    ModeCatalogEvent,
    BridgeModeCatalogEvent,
    ModeCatalogFrame,
    BridgeModeCatalogFrame,
    Change
);
feed_frames!(
    account_usage,
    AccountUsageEvent,
    BridgeAccountUsageEvent,
    AccountUsageFrame,
    BridgeAccountUsageFrame,
    Change
);
feed_frames!(
    performance_summaries,
    PerformanceSummariesEvent,
    BridgePerformanceSummariesEvent,
    PerformanceSummariesFrame,
    BridgePerformanceSummariesFrame,
    Change
);
feed_frames!(
    performance_history,
    PerformanceHistoryEvent,
    BridgePerformanceHistoryEvent,
    PerformanceHistoryFrame,
    BridgePerformanceHistoryFrame,
    Change
);
feed_frames!(
    session_costs,
    SessionCostsEvent,
    BridgeSessionCostsEvent,
    SessionCostsFrame,
    BridgeSessionCostsFrame,
    Replace
);
feed_frames!(
    recovery,
    RecoveryEvent,
    BridgeRecoveryEvent,
    RecoveryFrame,
    BridgeRecoveryFrame,
    Change
);
feed_frames!(
    mcp,
    McpEvent,
    BridgeMcpEvent,
    McpFrame,
    BridgeMcpFrame,
    Change
);
feed_frames!(
    lsp,
    LspEvent,
    BridgeLspEvent,
    LspFrame,
    BridgeLspFrame,
    Change
);
feed_frames!(
    skills,
    SkillsEvent,
    BridgeSkillsEvent,
    SkillsFrame,
    BridgeSkillsFrame,
    Change
);
feed_frames!(
    persistence,
    PersistenceEvent,
    BridgePersistenceEvent,
    PersistenceFrame,
    BridgePersistenceFrame,
    Replace
);
feed_frames!(
    persistence_queue,
    PersistenceQueueEvent,
    BridgePersistenceQueueEvent,
    PersistenceQueueFrame,
    BridgePersistenceQueueFrame,
    Change
);
feed_frames!(
    updates,
    UpdatesEvent,
    BridgeUpdatesEvent,
    UpdatesFrame,
    BridgeUpdatesFrame,
    Replace
);

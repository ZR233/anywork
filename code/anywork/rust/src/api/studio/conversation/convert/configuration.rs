use pl_protocol::thread_facets::configuration as protocol;
use super::super::configuration as bridge;

impl From<protocol::ModelRouteBrief> for bridge::BridgeModelRouteBrief {
    fn from(value: protocol::ModelRouteBrief) -> Self {
        Self { revision: value.revision, available: value.available, has_unavailable_reason: value.has_unavailable_reason }
    }
}

impl From<protocol::ConfigurationValue> for bridge::BridgeConfigurationValue {
    fn from(value: protocol::ConfigurationValue) -> Self {
        Self { details: value.details.into(), sources: value.sources.into(), mode_revision: value.mode_revision,
            mode_binding_revision: value.mode_binding_revision, model_route: value.model_route.map(Into::into),
            active_skill_count: value.active_skill_count, active_mcp: value.active_mcp.into(),
            active_lsp: value.active_lsp.into(), mcp_health: value.mcp_health.into() }
    }
}

impl From<protocol::ConfigurationEvent> for bridge::BridgeConfigurationEvent {
    fn from(value: protocol::ConfigurationEvent) -> Self {
        match value {
            protocol::ConfigurationEvent::Baseline { identity, stamp, value } => Self::Baseline {
                identity: identity.into(), stamp: stamp.into(), value: value.into(),
            },
            protocol::ConfigurationEvent::Replace { stamp, value } => Self::Replace { stamp: stamp.into(), value: value.into() },
        }
    }
}

impl From<protocol::ConfigurationFrame> for bridge::BridgeConfigurationFrame {
    fn from(value: protocol::ConfigurationFrame) -> Self {
        match value {
            protocol::ConfigurationFrame::Data { delivery_sequence, event } => Self::Data { delivery_sequence, event: event.into() },
            protocol::ConfigurationFrame::ResyncRequired { identity, reason } => Self::ResyncRequired { identity: identity.into(), reason: reason.into() },
            protocol::ConfigurationFrame::Failure { identity, error } => Self::Failure { identity: identity.into(), error: error.into() },
            protocol::ConfigurationFrame::Closed { identity, reason } => Self::Closed { identity: identity.into(), reason: reason.into() },
        }
    }
}

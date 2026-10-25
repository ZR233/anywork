use super::super::metrics as bridge;
use pl_protocol::thread_facets::metrics as protocol;

impl From<protocol::LiveTurnMetrics> for bridge::BridgeLiveTurnMetrics {
    fn from(value: protocol::LiveTurnMetrics) -> Self {
        Self {
            identity: value.identity.into(),
            completion_tokens: value.completion_tokens,
            response_millis: value.response_millis,
            state: value.state.into(),
            observation_sequence: value.observation_sequence,
        }
    }
}

impl From<protocol::AuthoritativeTurnMetrics> for bridge::BridgeAuthoritativeTurnMetrics {
    fn from(value: protocol::AuthoritativeTurnMetrics) -> Self {
        Self {
            identity: value.identity.into(),
            completion_tokens: value.completion_tokens,
            response_millis: value.response_millis,
        }
    }
}

impl From<protocol::MetricsValue> for bridge::BridgeMetricsValue {
    fn from(value: protocol::MetricsValue) -> Self {
        Self {
            live: value.live.map(Into::into),
            authoritative: value.authoritative.map(Into::into),
        }
    }
}

impl From<protocol::MetricsEvent> for bridge::BridgeMetricsEvent {
    fn from(value: protocol::MetricsEvent) -> Self {
        match value {
            protocol::MetricsEvent::Baseline {
                identity,
                stamp,
                value,
            } => Self::Baseline {
                identity: identity.into(),
                stamp: stamp.into(),
                value: value.into(),
            },
            protocol::MetricsEvent::Replace { stamp, value } => Self::Replace {
                stamp: stamp.into(),
                value: value.into(),
            },
        }
    }
}

impl From<protocol::MetricsFrame> for bridge::BridgeMetricsFrame {
    fn from(value: protocol::MetricsFrame) -> Self {
        match value {
            protocol::MetricsFrame::Data {
                delivery_sequence,
                event,
            } => Self::Data {
                delivery_sequence,
                event: event.into(),
            },
            protocol::MetricsFrame::ResyncRequired { identity, reason } => Self::ResyncRequired {
                identity: identity.into(),
                reason: reason.into(),
            },
            protocol::MetricsFrame::Failure { identity, error } => Self::Failure {
                identity: identity.into(),
                error: error.into(),
            },
            protocol::MetricsFrame::Closed { identity, reason } => Self::Closed {
                identity: identity.into(),
                reason: reason.into(),
            },
        }
    }
}

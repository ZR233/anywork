use pl_protocol::thread_facets::context as protocol;
use super::super::context as bridge;

impl From<protocol::ContextUsage> for bridge::BridgeContextUsage {
    fn from(value: protocol::ContextUsage) -> Self {
        Self {
            has_incomplete_usage: value.has_incomplete_usage, context_window: value.context_window,
            max_context_window: value.max_context_window, auto_compact_limit: value.auto_compact_limit,
            latest_context_tokens: value.latest_context_tokens, prompt_tokens: value.prompt_tokens,
            completion_tokens: value.completion_tokens, cached_prompt_tokens: value.cached_prompt_tokens,
            cache_write_tokens: value.cache_write_tokens, reasoning_tokens: value.reasoning_tokens,
            inference_count: value.inference_count, total_tokens: value.total_tokens, cache_usage: value.cache_usage.into(),
            estimated_cost_count: value.estimated_cost_count, estimated_cache_saving_count: value.estimated_cache_saving_count,
            has_unpriced_usage: value.has_unpriced_usage, prompt_generation: value.prompt_generation,
            prefix_changed_reason: value.prefix_changed_reason.map(Into::into), updated_at: value.updated_at,
        }
    }
}

impl From<protocol::LiveContext> for bridge::BridgeLiveContext {
    fn from(value: protocol::LiveContext) -> Self {
        Self { identity: value.identity.into(), latest_context_tokens: value.latest_context_tokens, state: value.state.into() }
    }
}

impl From<protocol::CurrentContextPolicy> for bridge::BridgeCurrentContextPolicy {
    fn from(value: protocol::CurrentContextPolicy) -> Self {
        Self { sources: value.sources.into(), mode_revision: value.mode_revision, route_revision: value.route_revision,
            context_window: value.context_window, max_context_window: value.max_context_window,
            input_token_limit: value.input_token_limit, auto_compact_limit: value.auto_compact_limit,
            unavailable: value.unavailable.map(Into::into), adjustment: value.adjustment.map(Into::into) }
    }
}

impl From<protocol::ContextValue> for bridge::BridgeContextValue {
    fn from(value: protocol::ContextValue) -> Self {
        Self { usage: value.usage.map(Into::into), live_context: value.live_context.map(Into::into),
            current_policy: value.current_policy.map(Into::into), details: value.details.into() }
    }
}

impl From<protocol::ContextEvent> for bridge::BridgeContextEvent {
    fn from(value: protocol::ContextEvent) -> Self {
        match value {
            protocol::ContextEvent::Baseline { identity, stamp, value } => Self::Baseline {
                identity: identity.into(), stamp: stamp.into(), value: value.into(),
            },
            protocol::ContextEvent::Replace { stamp, value } => Self::Replace { stamp: stamp.into(), value: value.into() },
        }
    }
}

impl From<protocol::ContextFrame> for bridge::BridgeContextFrame {
    fn from(value: protocol::ContextFrame) -> Self {
        match value {
            protocol::ContextFrame::Data { delivery_sequence, event } => Self::Data { delivery_sequence, event: event.into() },
            protocol::ContextFrame::ResyncRequired { identity, reason } => Self::ResyncRequired { identity: identity.into(), reason: reason.into() },
            protocol::ContextFrame::Failure { identity, error } => Self::Failure { identity: identity.into(), error: error.into() },
            protocol::ContextFrame::Closed { identity, reason } => Self::Closed { identity: identity.into(), reason: reason.into() },
        }
    }
}

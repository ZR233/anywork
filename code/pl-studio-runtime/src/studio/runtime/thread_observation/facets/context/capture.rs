use super::super::metrics::MetricsSnapshot;
use super::*;
use pl_protocol::ThreadRuntimeSnapshot;
use pl_protocol::thread_facets::context::{ContextUsage, CurrentContextPolicy, LiveContext};

impl ContextProjection {
    /// The same owner supplies frozen usage, current policy and its original metrics identity.
    /// Speed samples/observationSequence are deliberately absent from this facet's comparison.
    pub(in crate::studio::runtime) fn observe(
        &self,
        runtime: &ThreadRuntimeSnapshot,
        policy: Option<CurrentContextPolicy>,
        metrics: Option<Arc<MetricsSnapshot>>,
    ) -> Result<(), StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        ensure_open(&state)?;
        let previous = state.current.clone();
        let usage = &runtime.usage;
        if usage
            .estimated_costs
            .iter()
            .chain(&usage.estimated_cache_savings)
            .any(|cost| !cost.amount.is_finite())
        {
            return Err(crate::studio::runtime::read_budget::protocol(
                "Context cost is not a finite JSON number",
            ));
        }
        let source_revision = previous.as_ref().map_or(0, |old| old.source.revision);
        let mut source = ContextSource {
            revision: source_revision,
            frozen_model_id: (!usage.model_id.is_empty()).then(|| usage.model_id.clone()),
            prompt_cache_policy: usage.prompt_cache_policy.clone(),
            estimated_costs: usage.estimated_costs.clone(),
            estimated_cache_savings: usage.estimated_cache_savings.clone(),
        };
        let same_source = previous.as_ref().is_some_and(|old| *old.source == source);
        let details = if same_source {
            previous.as_ref().ok_or_else(exhausted)?.value.details
        } else {
            if previous.is_some() {
                source.revision = source_revision.checked_add(1).ok_or_else(exhausted)?;
            }
            ContextReadRef {
                entry: state.next_entry,
                revision: source.revision,
            }
        };
        let live_context = runtime.live_usage.as_ref().and_then(|live| {
            let sample = metrics.as_ref()?;
            let identity = sample.value.live.as_ref()?;
            Some(LiveContext {
                identity: identity.identity,
                latest_context_tokens: live.latest_context_tokens,
                state: live.state,
            })
        });
        let mut context_usage = ContextUsage {
            has_incomplete_usage: usage.has_incomplete_usage,
            context_window: usage.context_window,
            max_context_window: usage.max_context_window,
            auto_compact_limit: usage.auto_compact_limit,
            latest_context_tokens: usage.latest_context_tokens,
            prompt_tokens: usage.prompt_tokens,
            completion_tokens: usage.completion_tokens,
            cached_prompt_tokens: usage.cached_prompt_tokens,
            cache_write_tokens: usage.cache_write_tokens,
            reasoning_tokens: usage.reasoning_tokens,
            inference_count: usage.inference_count,
            total_tokens: usage.total_tokens,
            cache_usage: usage.cache_usage.clone(),
            estimated_cost_count: u64::try_from(usage.estimated_costs.len())
                .map_err(|_| exhausted())?,
            estimated_cache_saving_count: u64::try_from(usage.estimated_cache_savings.len())
                .map_err(|_| exhausted())?,
            has_unpriced_usage: usage.has_unpriced_usage,
            prompt_generation: usage.prompt_generation,
            prefix_changed_reason: usage.prefix_changed_reason,
            updated_at: previous
                .as_ref()
                .and_then(|old| old.value.usage.as_ref())
                .map_or(usage.updated_at, |old| old.updated_at),
        };
        let mut value = ContextValue {
            usage: Some(context_usage.clone()),
            live_context,
            current_policy: policy,
            details,
        };
        if previous.as_ref().is_some_and(|old| old.value == value) {
            state.capture_error = None;
            drop(state);
            self.changed.notify_waiters();
            return Ok(());
        }
        if !previous
            .as_ref()
            .is_some_and(|old| old.value.usage.as_ref() == Some(&context_usage))
        {
            context_usage.updated_at = usage.updated_at;
            value.usage = Some(context_usage);
        }
        let revision = previous
            .as_ref()
            .map(|old| old.stamp.revision.checked_add(1).ok_or_else(exhausted))
            .transpose()?
            .unwrap_or(0);
        let source = if same_source {
            previous.as_ref().ok_or_else(exhausted)?.source.clone()
        } else {
            Arc::new(source)
        };
        let source_bytes = crate::studio::runtime::read_budget::json_bytes(&(
            &source.frozen_model_id,
            &source.prompt_cache_policy,
            &source.estimated_costs,
            &source.estimated_cache_savings,
        ))?;
        let next = Arc::new(ContextSnapshot {
            stamp: ThreadFacetStamp {
                runtime_epoch: self.epoch.clone(),
                incarnation: self.incarnation,
                facet: ThreadFacet::Context,
                revision,
            },
            value,
            source,
            source_bytes,
            _metrics: metrics,
        });
        state
            .locators
            .retain(|_, locator| locator.source.strong_count() != 0);
        if !same_source {
            let next_entry = state.next_entry.checked_add(1).ok_or_else(exhausted)?;
            if let Some(previous) = &previous
                && let Some(locator) = state.locators.get_mut(&(
                    previous.value.details.entry,
                    previous.value.details.revision,
                ))
            {
                locator.retired_at = Some(revision);
            }
            state.next_entry = next_entry;
            state.locators.insert(
                (next.value.details.entry, next.value.details.revision),
                Locator {
                    source: Arc::downgrade(&next.source),
                    born: revision,
                    exposed_from: None,
                    retired_at: None,
                },
            );
        }
        state.capture_error = None;
        state
            .listeners
            .retain(|listener| listener.strong_count() != 0);
        for listener in state.listeners.iter().filter_map(Weak::upgrade) {
            listener.publish(next.clone());
        }
        state.current = Some(next);
        drop(state);
        self.changed.notify_waiters();
        Ok(())
    }
}

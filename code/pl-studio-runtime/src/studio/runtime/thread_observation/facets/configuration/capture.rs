use super::*;
use pl_protocol::ThreadRuntimeSnapshot;
use pl_protocol::studio::ConfigProjectionStamp;
use pl_protocol::thread_facets::configuration::ModelRouteBrief;
use pl_protocol::thread_facets::identity::ThreadCapabilitySupport;

impl ConfigurationProjection {
    /// Only the original projection owner calls this, with its already qualified runtime facts.
    /// Source clocks are metadata, never substitutes for the independent facet revision.
    pub(in crate::studio::runtime) fn observe(
        &self,
        runtime: &ThreadRuntimeSnapshot,
        sources: ConfigProjectionStamp,
        mode_revision: u64,
        mode_binding_revision: Option<u64>,
    ) -> Result<(), StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        ensure_open(&state)?;
        let previous = state.current.clone();
        if previous.as_ref().is_some_and(|old| {
            old.source.route == runtime.model_route
                && old.source.active_skills == runtime.active_skills
                && old.value.sources == sources
                && old.value.mode_revision == mode_revision
                && old.value.mode_binding_revision == mode_binding_revision
        }) {
            state.capture_error = None;
            drop(state);
            self.changed.notify_waiters();
            return Ok(());
        }
        let revision = previous
            .as_ref()
            .map(|old| old.stamp.revision.checked_add(1).ok_or_else(exhausted))
            .transpose()?
            .unwrap_or(0);
        let entry = state.next_entry;
        let next_entry = entry.checked_add(1).ok_or_else(exhausted)?;
        // Pending deliveries charge their pinned original details, not only the small wire ref.
        let source_bytes = crate::studio::runtime::read_budget::json_bytes(&(
            &runtime.model_route,
            &runtime.active_skills,
        ))?;
        let source = Arc::new(ConfigurationSource {
            revision,
            route: runtime.model_route.clone(),
            active_skills: runtime.active_skills.clone(),
        });
        let value = ConfigurationValue {
            details: ConfigurationReadRef { entry, revision },
            sources,
            mode_revision,
            mode_binding_revision,
            model_route: runtime.model_route.as_ref().map(|route| ModelRouteBrief {
                revision: route.revision,
                available: route.available,
                has_unavailable_reason: route.unavailable_reason.is_some(),
            }),
            active_skill_count: u64::try_from(source.active_skills.len())
                .map_err(|_| exhausted())?,
            active_mcp: ThreadCapabilitySupport::Unsupported,
            active_lsp: ThreadCapabilitySupport::Unsupported,
            mcp_health: ThreadCapabilitySupport::Unsupported,
        };
        let next = Arc::new(ConfigurationSnapshot {
            stamp: ThreadFacetStamp {
                runtime_epoch: self.epoch.clone(),
                incarnation: self.incarnation,
                facet: ThreadFacet::Configuration,
                revision,
            },
            value,
            source,
            source_bytes,
        });
        state
            .locators
            .retain(|_, locator| locator.source.strong_count() != 0);
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
            (entry, revision),
            Locator {
                source: Arc::downgrade(&next.source),
                born: revision,
                exposed_from: None,
                retired_at: None,
            },
        );
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

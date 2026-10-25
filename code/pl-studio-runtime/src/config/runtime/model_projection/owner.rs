//! The named Models capability of the original canonical Configuration owner, not a callback bus.
use std::sync::Arc;

use pl_protocol::products::identity::ProductReadOrigin;
use pl_protocol::studio::{StudioError, StudioErrorCode};

use super::super::{ConfigRuntime, RuntimeState, config_runtime_poisoned, projection_stamp};
use super::{CapturedModels, ModelCaptureFailure, ModelCatalogSource};

impl ConfigRuntime {
    /// The builder supplies its original epoch and one allocation from the shared incarnation
    /// allocator. Initial identity registration and compatible capture use the canonical guard.
    pub(crate) fn attach_models_source(
        &self,
        origin: ProductReadOrigin,
    ) -> anyhow::Result<Arc<ModelCatalogSource>> {
        let mut state = self.state.write().map_err(|_| config_runtime_poisoned())?;
        if state.closing {
            return Err(StudioError::new(
                StudioErrorCode::Cancelled,
                "The canonical Models owner is closing",
                false,
            )
            .into());
        }
        state
            .models_sources
            .retain(|_, source| source.strong_count() != 0);
        if let Some(source) = state
            .models_sources
            .get(&origin.owner_epoch)
            .and_then(std::sync::Weak::upgrade)
        {
            if source.origin() == &origin {
                source.ensure_open()?;
                return Ok(source);
            }
            return Err(StudioError::new(
                StudioErrorCode::Conflict,
                "A different Models projection already belongs to this runtime",
                false,
            )
            .into());
        }
        let captured = CapturedModels::capture(&state.snapshot, &state.catalog)
            .map(Arc::new)
            .map_err(ModelCaptureFailure::capture);
        let source = ModelCatalogSource::new(
            origin,
            projection_stamp(&state),
            state.catalog.updated_at,
            state.models_status.clone(),
            captured,
        );
        state
            .models_sources
            .insert(source.origin().owner_epoch.clone(), Arc::downgrade(&source));
        Ok(source)
    }

    /// Caller holds the original write guard and has installed both canonical source snapshots.
    /// Advance every registered projection before the original retained watch can merge a change.
    pub(in crate::config::runtime) fn publish_models_locked(
        &self,
        state: &mut RuntimeState,
    ) -> Vec<Arc<ModelCatalogSource>> {
        state
            .models_sources
            .retain(|_, source| source.strong_count() != 0);
        let sources: Vec<_> = state
            .models_sources
            .values()
            .filter_map(std::sync::Weak::upgrade)
            .collect();
        if sources.is_empty() {
            return sources;
        }
        let stamp = projection_stamp(state);
        let captured = CapturedModels::capture(&state.snapshot, &state.catalog)
            .map(Arc::new)
            .map_err(ModelCaptureFailure::capture);
        for source in &sources {
            source.publish(
                stamp,
                state.catalog.updated_at,
                state.models_status.clone(),
                captured.clone(),
            );
        }
        // Notifications run after the original state/command guards have been released. The
        // identities above have already advanced even if watch coalesces every intermediate wake.
        sources
    }
}

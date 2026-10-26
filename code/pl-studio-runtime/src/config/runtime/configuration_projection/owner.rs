use pl_protocol::products::identity::ProductReadOrigin;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::sync::{Arc, Weak};

use super::super::{
    ConfigRuntime, ModelCatalogSource, RuntimeState, acp_directory, config_runtime_poisoned,
    projection_stamp,
};
use super::{ConfigurationCaptureFailure, ConfigurationSource, capture, status};

impl ConfigRuntime {
    /// Attach once to the builder's original epoch/incarnation and the very same Models source.
    pub(crate) fn attach_configuration_source(
        &self,
        origin: ProductReadOrigin,
        models: Arc<ModelCatalogSource>,
    ) -> anyhow::Result<Arc<ConfigurationSource>> {
        let mut state = self.state.write().map_err(|_| config_runtime_poisoned())?;
        if state.closing {
            return Err(StudioError::new(
                StudioErrorCode::Cancelled,
                "Configuration owner is closing",
                false,
            )
            .into());
        }
        let registered = state
            .models_sources
            .get(&origin.owner_epoch)
            .and_then(Weak::upgrade);
        if models.origin().owner_epoch != origin.owner_epoch
            || !registered
                .as_ref()
                .is_some_and(|source| Arc::ptr_eq(source, &models))
        {
            return Err(StudioError::new(
                StudioErrorCode::Protocol,
                "Configuration requires this owner's registered Models source",
                false,
            )
            .into());
        }
        state
            .configuration_sources
            .retain(|_, source| source.strong_count() != 0);
        if let Some(source) = state
            .configuration_sources
            .get(&origin.owner_epoch)
            .and_then(Weak::upgrade)
        {
            if source.origin() != &origin {
                return Err(StudioError::new(
                    StudioErrorCode::Conflict,
                    "A different Configuration source is already registered for this runtime",
                    false,
                )
                .into());
            }
            source.ensure_open()?;
            return Ok(source);
        }
        let source = ConfigurationSource::new(origin, models);
        source.publish(
            projection_stamp(&state),
            state.snapshot.updated_at,
            state.configuration_status.clone(),
            capture::capture(
                &state.snapshot,
                acp_directory(state.snapshot.revision, state.acp_directory.as_ref()),
            )
            .map(Arc::new)
            .map_err(ConfigurationCaptureFailure::new),
        );
        state
            .configuration_sources
            .insert(source.origin().owner_epoch.clone(), Arc::downgrade(&source));
        Ok(source)
    }

    pub(in crate::config::runtime) fn publish_configuration_locked(
        &self,
        state: &mut RuntimeState,
    ) -> Vec<Arc<ConfigurationSource>> {
        status::advance(
            &mut state.configuration_status,
            state.closing,
            crate::studio::unix_seconds(),
        );
        state
            .configuration_sources
            .retain(|_, source| source.strong_count() != 0);
        let sources: Vec<_> = state
            .configuration_sources
            .values()
            .filter_map(Weak::upgrade)
            .collect();
        if sources.is_empty() {
            return sources;
        }
        let captured = capture::capture(
            &state.snapshot,
            acp_directory(state.snapshot.revision, state.acp_directory.as_ref()),
        )
        .map(Arc::new)
        .map_err(ConfigurationCaptureFailure::new);
        for source in &sources {
            source.publish(
                projection_stamp(state),
                state.snapshot.updated_at,
                state.configuration_status.clone(),
                captured.clone(),
            );
        }
        sources
    }
}

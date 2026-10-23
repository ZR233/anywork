//! Last-mile admission shared by direct assembler inputs and interaction continuations.
use super::{StudioThreadAssembler, ThreadAssemblyError, agent_services::AgentServices};
use anyhow::{Context, Result};
use pl_core::thread::{DeferredModelUpdatePrecondition, ThreadHandle};

impl AgentServices {
    pub(super) async fn prepare_model_admission(&self, thread: &ThreadHandle) -> Result<()> {
        let snapshot = thread.snapshot();
        anyhow::ensure!(
            !crate::studio::agent_close::is_explicitly_closed(&snapshot)?,
            "child is explicitly closed"
        );
        let config = self.config.read()?.config;
        let child = crate::studio::model_route::saved_profile(&snapshot)?;
        let (extension, route) = if let Some((profile, _)) = child {
            (
                crate::studio::model_route::AGENT_PROFILE_EXTENSION,
                crate::studio::delegation::resolve_child_route(&config, &profile)?,
            )
        } else {
            let selector = crate::studio::model_route::saved(&snapshot)?
                .context("Thread has no frozen model route")?
                .route;
            let route = config
                .models
                .resolve_route(crate::StudioRole::Planner.id(), &selector)?;
            crate::studio::delegation::validate_credential(&route)?;
            (crate::studio::model_route::MODEL_ROUTE_EXTENSION, route)
        };
        let content = snapshot
            .context
            .records
            .iter()
            .flat_map(|record| &record.content)
            .chain(
                snapshot
                    .inputs
                    .iter()
                    .filter(|record| record.state == pl_core::thread::input::InputState::Pending)
                    .flat_map(|record| &record.input.context),
            );
        pl_model::runtime::validate_attachment_content(content, &route.model)?;
        pl_model::runtime::ThreadModel::new(
            pl_model::runtime::ModelRuntime::from_route(&route)?,
            route.reasoning_config(),
        )
        .validate_context_origin(&snapshot.context)?;
        thread
            .queue_deferred_model_update_if_current(
                crate::studio::model_binding::deferred_update(
                    &route,
                    &config,
                    self.config.thread_mode_manager(),
                )?,
                DeferredModelUpdatePrecondition::extension(
                    extension,
                    snapshot
                        .extensions
                        .get(extension)
                        .map(|record| record.revision),
                ),
                Vec::new(),
            )
            .await?;
        Ok(())
    }
}

impl StudioThreadAssembler {
    /// The caller holds the same identity's operation permit through actual core admission.
    pub(super) async fn prepare_input_admission(
        &self,
        id: &str,
        thread: &ThreadHandle,
    ) -> Result<(), ThreadAssemblyError> {
        self.ensure_agent_admission_open(id)?;
        let services = self.0.state().agent_services.clone();
        // Standalone assemblers have no product configuration owner. Studio always installs one
        // before assembly, so every production path resolves its frozen selector against it.
        if let Some(services) = services {
            services
                .prepare_model_admission(thread)
                .await
                .map_err(|source| ThreadAssemblyError::Resource {
                    operation: "admit Thread model",
                    source: source.into(),
                })?;
        }
        Ok(())
    }
}

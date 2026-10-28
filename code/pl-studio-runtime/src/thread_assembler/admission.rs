//! Last-mile admission shared by direct assembler inputs and interaction continuations.
use super::{StudioThreadAssembler, ThreadAssemblyError, agent_services::AgentServices};
use anyhow::{Context, Result};
use pl_core::thread::{DeferredModelUpdatePrecondition, ThreadHandle};

#[derive(Clone, Copy)]
pub(super) enum WorkspaceAdmission<'a> {
    Explicit,
    VerifiedReview(&'a crate::studio::thread_factory::ReviewWorkspaceCheck),
}

impl AgentServices {
    pub(super) async fn prepare_model_admission(
        &self,
        id: &str,
        thread: &ThreadHandle,
        workspace: WorkspaceAdmission<'_>,
    ) -> Result<()> {
        self.store.ensure_agent_execution_allowed(id).await?;
        let snapshot = thread.snapshot();
        let record = self.record(id).await?;
        self.recovery.ensure_thread_read_access(&record)?;
        let resources = match workspace {
            WorkspaceAdmission::Explicit => {
                self.factory
                    .verify_execution_workspace(
                        &record,
                        Some(&snapshot),
                        crate::studio::thread_factory::ExecutionWorkspaceCheck::Execute,
                    )
                    .await
            }
            WorkspaceAdmission::VerifiedReview(proof) => {
                anyhow::ensure!(
                    proof.target() == id,
                    "workspace proof belongs to another target"
                );
                proof.confirm().await.map_err(anyhow::Error::from)
            }
        };
        self.events.emit_recovery_state(
            self.recovery
                .apply_execution_workspace_check(&record, resources.as_ref().err()),
        );
        resources?;
        self.recovery.ensure_thread_execution_access(&record)?;
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
                .resolve_route(crate::config::root_agent_route_id(), &selector)?;
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
        if let WorkspaceAdmission::VerifiedReview(proof) = workspace {
            proof.confirm().await?;
        }
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
                .prepare_model_admission(id, thread, WorkspaceAdmission::Explicit)
                .await
                .map_err(|source| ThreadAssemblyError::Resource {
                    operation: "admit Thread model",
                    source: source.into(),
                })?;
        }
        Ok(())
    }

    pub(super) async fn prepare_verified_review_admission(
        &self,
        id: &str,
        thread: &ThreadHandle,
        proof: &crate::studio::thread_factory::ReviewWorkspaceCheck,
    ) -> Result<(), ThreadAssemblyError> {
        self.ensure_agent_admission_open(id)?;
        let services = self
            .0
            .state()
            .agent_services
            .clone()
            .ok_or(ThreadAssemblyError::Closed)?;
        services
            .prepare_model_admission(id, thread, WorkspaceAdmission::VerifiedReview(proof))
            .await
            .map_err(|source| ThreadAssemblyError::Resource {
                operation: "admit frozen review input",
                source: source.into(),
            })
    }
}

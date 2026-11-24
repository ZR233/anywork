//! Last-mile admission shared by direct assembler inputs and interaction continuations.
use super::{SessionRuntime, ThreadAssemblyError, agent_services::AgentServices};
use crate::studio::model_binding::{NativeBundleOwner, NativeModelConfiguration};
use anyhow::Result;
use pl_core::thread::{ThreadError, ThreadHandle};

#[derive(Clone, Copy)]
pub(super) enum WorkspaceAdmission<'a> {
    Explicit,
    VerifiedReview(&'a crate::studio::thread_factory::ReviewWorkspaceCheck),
}

impl AgentServices {
    pub(super) async fn prepare_model_admission(
        &self,
        session: &SessionRuntime,
        id: &str,
        thread: &ThreadHandle,
        workspace: WorkspaceAdmission<'_>,
    ) -> Result<()> {
        let snapshot = thread.snapshot();
        let record = self.record(id).await?;
        self.recovery.ensure_thread_read_access(&record)?;
        if let WorkspaceAdmission::VerifiedReview(proof) = workspace {
            anyhow::ensure!(
                proof.target() == id,
                "workspace proof belongs to another target"
            );
            proof.recheck()?;
        }
        self.recovery.ensure_thread_execution_access(&record)?;
        anyhow::ensure!(
            !crate::studio::agent_close::is_explicitly_closed(&snapshot)?,
            "child is explicitly closed"
        );
        session.prepare_native_input(id, thread).await?;
        if let WorkspaceAdmission::VerifiedReview(proof) = workspace {
            proof.recheck()?;
        }
        Ok(())
    }
}

impl SessionRuntime {
    /// Resolves and validates the exact saved Native route. A newly selected model uses the
    /// same package preparation as a catalog refresh, and old command controls remain reachable
    /// while an incompatible ordinary candidate waits for its outstanding leases.
    pub(crate) async fn prepare_native_input(
        &self,
        id: &str,
        thread: &ThreadHandle,
    ) -> Result<pl_model::config::ResolvedModelRoute> {
        let services = self
            .0
            .state()
            .agent_services
            .clone()
            .ok_or(ThreadAssemblyError::Closed)?;
        let mut snapshot = thread.snapshot();
        let mut config = NativeModelConfiguration::resolve(&services.config, &snapshot)?;
        let model_ready = |state: &pl_core::thread::ThreadSnapshot,
                           config: &NativeModelConfiguration| {
            state.model_available
                && state.runtime_bundle.model_identity.as_deref() == Some(config.model.identity())
        };
        if model_ready(&snapshot, &config) {
            return Ok(config.route);
        }

        let scope = self.native_resources(thread)?;
        let (gate, cancellation) = services.factory.tool_operation(id)?;
        let installation = tokio::select! {
            biased;
            () = cancellation.cancelled() => return Err(ThreadError::Closed.into()),
            guard = gate.lock_owned() => guard,
        };
        snapshot = thread.snapshot();
        config = NativeModelConfiguration::resolve(&services.config, &snapshot)?;
        let route = config.route.clone();
        if model_ready(&snapshot, &config) {
            return Ok(route);
        }
        let desired = config.desired().into();
        let candidate = config
            .prepare_bundle(
                NativeBundleOwner {
                    id,
                    session: self,
                    factory: &services.factory,
                    config: &services.config,
                    thread,
                    snapshot: &snapshot,
                },
                cancellation,
                desired,
                || true,
            )
            .await?;
        let mut receipt = scope
            .candidates
            .stage_runtime_bundle(thread.clone(), candidate)
            .await?;
        drop(installation);
        receipt.prepared().await?;
        Ok(route)
    }

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
            // Model/workspace preparation carries its own snapshot and IO state. Keep it
            // out of interaction continuations while the same caller retains admission,
            // cancellation and the service snapshot; no independent task is introduced.
            Box::pin(services.prepare_model_admission(
                self,
                id,
                thread,
                WorkspaceAdmission::Explicit,
            ))
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
            .prepare_model_admission(self, id, thread, WorkspaceAdmission::VerifiedReview(proof))
            .await
            .map_err(|source| ThreadAssemblyError::Resource {
                operation: "admit frozen review input",
                source: source.into(),
            })
    }
}

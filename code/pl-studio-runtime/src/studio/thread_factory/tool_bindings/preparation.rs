//! Preparation handoff and asynchronous cleanup using the same binding table as active Threads.
use super::{ThreadToolLifetime, close_archive, close_file_operations};
use crate::{
    studio::StudioThreadFactory,
    thread_assembler::{StudioThreadSpec, ThreadAssemblyError, ThreadPreparationGuard},
};
use std::{future::Future, sync::Arc};

impl StudioThreadFactory {
    pub(in crate::studio::thread_factory) async fn with_prepared_lifetime<F, Fut>(
        &self,
        id: &str,
        cancellation: &tokio_util::sync::CancellationToken,
        prepare: F,
    ) -> Result<StudioThreadSpec, ThreadAssemblyError>
    where
        F: FnOnce(Arc<ThreadToolLifetime>) -> Fut,
        Fut: Future<Output = Result<StudioThreadSpec, ThreadAssemblyError>>,
    {
        let previous = {
            let bindings = self
                .bindings
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if bindings.get(id).is_some() {
                return Err(ThreadAssemblyError::Identity(id.into()));
            }
            bindings.lifetime(id)
        };
        if let Some(previous) = previous {
            self.forget_lifetime(id, &previous).await?;
        }
        let lifetime = Arc::new(ThreadToolLifetime {
            cancellation: cancellation.child_token(),
            ..Default::default()
        });
        self.bindings
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .reserve(id, lifetime.clone())?;
        let factory = self.clone();
        let guard_id = id.to_owned();
        let identity = lifetime.clone();
        let guard = ThreadPreparationGuard::new(move || {
            factory.abandon_tool_binding_if_current(&guard_id, &identity);
        });
        match prepare(lifetime.clone()).await {
            Ok(mut spec) => {
                spec.preparation_guard = Some(guard);
                Ok(spec)
            }
            Err(error) => {
                drop(guard);
                match self.forget_lifetime(id, &lifetime).await {
                    Ok(()) => Err(error),
                    Err(cleanup) => Err(super::resource_error(
                        "cleanup failed Thread preparation",
                        PreparationCleanupError { error, cleanup },
                    )),
                }
            }
        }
    }

    pub(crate) fn preparation_owner(
        &self,
        id: &str,
    ) -> Result<pl_model::runtime::ModelPreparationOwner, ThreadAssemblyError> {
        self.bindings
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(id)
            .map(|binding| binding.lifetime.preparation.clone())
            .ok_or(ThreadAssemblyError::Closed)
    }

    pub(in crate::studio) async fn drain_pending_file_operations(
        &self,
    ) -> Vec<(String, ThreadAssemblyError)> {
        let pending = self
            .bindings
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .pending();
        let mut failures = Vec::new();
        for (id, lifetime) in pending {
            if let Err(error) = self.forget_lifetime(&id, &lifetime).await {
                failures.push((id, error));
            }
        }
        failures
    }

    pub(super) async fn forget_lifetime(
        &self,
        id: &str,
        lifetime: &Arc<ThreadToolLifetime>,
    ) -> Result<(), ThreadAssemblyError> {
        close_file_operations(lifetime).await?;
        // This lifetime never transferred a core owner, so no later result can acquire its pins.
        close_archive(lifetime).await?;
        self.bindings
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .remove_drained(id, lifetime)
    }
}

#[derive(Debug, thiserror::Error)]
#[error("Thread preparation failed: {error}; cleanup also failed: {cleanup}")]
struct PreparationCleanupError {
    #[source]
    error: ThreadAssemblyError,
    cleanup: ThreadAssemblyError,
}

//! Thread/Project 生命周期命令目录页：对外命令入口与 projects/threads 子模块组织。

mod projects;
mod threads;

use anyhow::{Context, Result};

use super::{StudioRuntime, StudioStartNewThreadRequest, StudioStartNewThreadResponse};

impl StudioRuntime {
    pub(in crate::studio::runtime) async fn thread_lifecycle_admission(
        &self,
    ) -> Result<tokio::sync::OwnedMutexGuard<()>> {
        // A bot operation can be awaited by shutdown while it is still queued for this lock.
        // The existing one-way latch wakes that unadmitted operation instead of creating a
        // lifecycle -> bot join -> lifecycle cycle. No accepted worker is cancelled here.
        let guard = tokio::select! {
            biased;
            () = self.shutdown_latch.committed() => anyhow::bail!("Studio runtime is closing"),
            guard = self.lifecycle_lock.clone().lock_owned() => guard,
        };
        anyhow::ensure!(!self.shutdown_committed(), "Studio runtime is closing");
        Ok(guard)
    }

    pub(in crate::studio::runtime) async fn run_thread_lifecycle_operation<T: Send + 'static>(
        &self,
        operation: impl std::future::Future<Output = Result<T>> + Send + 'static,
    ) -> Result<T> {
        let lifecycle = self.thread_lifecycle_admission().await?;
        // Lifecycle admission also serializes slot replacement. Observe the previous completion
        // before replacing it; cancellation while joining leaves that same future retained.
        let joined = super::background_task::finish(&self.thread_lifecycle_task).await;
        self.thread_lifecycle_task.lock().await.take();
        joined.context("previous Thread lifecycle operation failed to join")?;
        let (publication, result) = tokio::sync::oneshot::channel();
        let mut slot = self.thread_lifecycle_task.lock().await;
        *slot = Some(super::background_task::BackgroundTask::new(tokio::spawn(
            async move {
                let _lifecycle = lifecycle;
                let outcome = operation.await;
                let _ = publication.send(outcome);
            },
        )));
        drop(slot);
        result
            .await
            .context("Thread lifecycle worker stopped without a conclusion")?
    }

    /// Creates a root Thread and accepts its first Turn from the shared API request.
    pub async fn create_thread_command(
        &self,
        workspace_id: String,
        request: pl_protocol::studio::CreateThreadRequest,
        preparation_observer: Option<super::ThreadPreparationObserver>,
    ) -> Result<StudioStartNewThreadResponse> {
        let mode = pl_protocol::ThreadModeId::from_label(request.mode.trim()).map_err(|_| {
            anyhow::Error::new(pl_protocol::studio::StudioError::invalid_argument(
                "mode must be an available mode.* id",
            ))
        })?;
        self.start_new_thread(StudioStartNewThreadRequest {
            workspace_id,
            title: request.title,
            input: request.input,
            mode,
            route: request.route,
            delegation_mode: request.delegation_mode,
            delegation_preference: request.delegation_preference,
            workspace_mode: request.workspace_mode,
            options: super::StudioSubmitPromptOptions::default(),
            preparation_observer,
        })
        .await
    }
}

//! Thread/Project 生命周期命令目录页：对外命令入口与 projects/threads 子模块组织。

mod projects;
mod threads;

use anyhow::{Context, Result};

use super::StudioRuntime;

impl StudioRuntime {
    async fn thread_lifecycle_admission(&self) -> Result<tokio::sync::OwnedMutexGuard<()>> {
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

    async fn run_archive<T: Send + 'static>(
        &self,
        operation: impl std::future::Future<Output = Result<T>> + Send + 'static,
    ) -> Result<T> {
        let lifecycle = self.thread_lifecycle_admission().await?;
        // Lifecycle admission also serializes slot replacement. Observe the previous completion
        // before replacing it; cancellation while joining leaves that same future retained.
        let joined = super::background_task::finish(&self.archive_task).await;
        self.archive_task.lock().await.take();
        joined.context("previous archive operation failed to join")?;
        let (publication, result) = tokio::sync::oneshot::channel();
        let mut slot = self.archive_task.lock().await;
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
            .context("archive worker stopped without a conclusion")?
    }
}

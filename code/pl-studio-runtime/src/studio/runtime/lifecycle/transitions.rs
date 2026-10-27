use anyhow::Result;

use crate::studio::StudioRuntimeSnapshot;
use crate::{StudioShutdownIssue, StudioShutdownReport};

use super::super::StudioRuntime;

impl StudioRuntime {
    /// Stops all Studio runtime services (strict contract).
    ///
    /// Every stage must succeed for this to return `Ok`; a failed or timed-out run keeps the
    /// runtime in `Failed` with the owners/handles retained so the caller can retry explicitly.
    pub async fn shutdown_runtime(&self) -> Result<StudioRuntimeSnapshot> {
        // Seal before waiting for an admitted archive/cleanup, without aborting its worker.
        self.shutdown_latch.arm();
        let _lifecycle_guard = self.lifecycle_lock.lock().await;
        self.execute_strict_shutdown().await?;
        self.runtime_snapshot().await
    }

    /// Application-exit shutdown: returns a typed report and accepts `Degraded`.
    ///
    /// The desktop host holds the single 30s deadline and passes its remaining cleanup budget;
    /// this entry never extends that deadline and never fakes `Stopped` or persistence success.
    ///
    /// `external_issues` are the deterministic failures the caller already observed before
    /// entering the runtime orchestration — most importantly, bridge- and Dart-owned subscription
    /// or update cancellations that did not confirm. They are folded into the single shutdown
    /// orchestration as success preconditions rather than merged afterwards, so a `Degraded`
    /// result on either side can never publish `Stopped` or release the instance lock.
    pub async fn shutdown_runtime_for_exit(
        &self,
        remaining_ms: u32,
        external_issues: Vec<StudioShutdownIssue>,
    ) -> StudioShutdownReport {
        self.execute_exit_shutdown(remaining_ms, external_issues)
            .await
    }

    /// Whether this runtime has committed to shutdown (one-way latch).
    pub fn shutdown_committed(&self) -> bool {
        self.shutdown_latch.is_committed()
    }

    /// 订阅关机阶段进度；通道随 runtime 共享，并发 shutdown 共享同一次序列。
    pub async fn subscribe_shutdown_progress(
        &self,
    ) -> tokio::sync::broadcast::Receiver<crate::StudioShutdownProgress> {
        self.shutdown_progress.subscribe()
    }
}

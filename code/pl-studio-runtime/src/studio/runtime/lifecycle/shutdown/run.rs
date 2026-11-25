//! Retained shutdown completion, fixed exit deadline and admission latch.

use futures::FutureExt;

use super::diagnostics::panic_text;
use super::stages::ShutdownBudget;
use crate::studio::{StudioRuntime, StudioRuntimeSnapshot};
use crate::{StudioShutdownIssue, StudioShutdownReport};
use std::panic::AssertUnwindSafe;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, OnceLock};
use std::time::{Duration, Instant};
use tokio::sync::watch;

pub(crate) const EXIT_CLEANUP_BUDGET: Duration = Duration::from_secs(28);

impl StudioRuntime {
    /// Stops all Studio runtime services (strict contract).
    /// Every stage must succeed for this to return `Ok`; a failed or timed-out run keeps the
    /// runtime in `Failed` with the owners/handles retained so the caller can retry explicitly.
    pub async fn shutdown_runtime(&self) -> anyhow::Result<StudioRuntimeSnapshot> {
        // Seal before waiting for an admitted archive/cleanup, without aborting its worker.
        self.shutdown_latch.arm();
        let _lifecycle_guard = self.lifecycle_lock.lock().await;
        self.execute_strict_shutdown().await?;
        self.runtime_snapshot().await
    }

    /// Application-exit shutdown: returns a typed report and accepts `Degraded`.
    /// The desktop host holds the single 30s deadline and passes its remaining cleanup budget;
    /// this entry never extends that deadline and never fakes `Stopped` or persistence success.
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
    pub(crate) fn shutdown_committed(&self) -> bool {
        self.shutdown_latch.is_committed()
    }

    /// 订阅关机阶段进度；通道随 runtime 共享，并发 shutdown 共享同一次序列。
    pub async fn subscribe_shutdown_progress(
        &self,
    ) -> tokio::sync::broadcast::Receiver<crate::StudioShutdownProgress> {
        self.shutdown_progress.subscribe()
    }
}

#[derive(Clone, Default)]
pub(crate) struct ShutdownLatch {
    committed: tokio_util::sync::CancellationToken,
}

impl ShutdownLatch {
    pub(crate) fn arm(&self) {
        self.committed.cancel();
    }

    pub(crate) fn is_committed(&self) -> bool {
        self.committed.is_cancelled()
    }

    pub(crate) async fn committed(&self) {
        self.committed.cancelled().await;
    }
}

/// 同一次退出关闭运行的共享完成句柄。
///
/// `report` 是一个共享的 `watch` 完成状态，不引用 runtime，因此不会与持有它的
/// `StudioRuntime` 形成 `Arc` 环。编排本身运行在 owned spawned task 上：重复退出只 join
/// 同一个任务、不重复执行阶段，也不因新的调用延长已经固定的期限；等待方超时返回后任务
/// 仍被运行时继续 poll 到结束。
#[derive(Clone)]
pub(crate) struct ShutdownRun {
    report: Arc<watch::Sender<Option<StudioShutdownReport>>>,
    started: Arc<AtomicBool>,
    deadline: Arc<OnceLock<Instant>>,
}

impl Default for ShutdownRun {
    fn default() -> Self {
        let (report, _receiver) = watch::channel::<Option<StudioShutdownReport>>(None);
        Self {
            report: Arc::new(report),
            started: Arc::new(AtomicBool::new(false)),
            deadline: Arc::new(OnceLock::new()),
        }
    }
}

impl ShutdownRun {
    /// 首次退出固定绝对期限；重复退出只复用，不延长。
    pub(super) fn fixed_deadline(&self, requested: Duration) -> Instant {
        *self
            .deadline
            .get_or_init(|| Instant::now() + requested.min(EXIT_CLEANUP_BUDGET))
    }

    /// 启动唯一一次 owned 关闭编排任务；已启动则直接返回。
    ///
    /// 首个调用者的 `external_issues` 与预算一起被固定进这次唯一编排；后续重复退出只 join
    /// 同一任务，不重复执行阶段，也不延长已经固定的期限。
    pub(super) fn spawn_once(
        &self,
        runtime: &StudioRuntime,
        budget: ShutdownBudget,
        external_issues: Vec<StudioShutdownIssue>,
    ) {
        if self.started.swap(true, Ordering::SeqCst) {
            return;
        }
        let runtime = runtime.clone();
        let report = Arc::clone(&self.report);
        tokio::spawn(async move {
            // 严格关闭与退出关闭经同一 lifecycle_lock 串行，不并行竞跑第二套编排；该等待也
            // 受同一绝对期限约束，不能在锁上无界阻塞。
            let guard = match budget.deadline() {
                Some(deadline) => {
                    let remaining = deadline.saturating_duration_since(Instant::now());
                    tokio::time::timeout(remaining, runtime.lifecycle_lock.lock())
                        .await
                        .ok()
                }
                None => Some(runtime.lifecycle_lock.lock().await),
            };
            let Some(_lifecycle_guard) = guard else {
                let _ = report.send_replace(Some(StudioShutdownReport::deadline_exceeded(
                    "lifecycleLock",
                    crate::StudioError::internal().correlation_id,
                )));
                return;
            };
            let outcome = AssertUnwindSafe(runtime.execute_shutdown(budget, external_issues))
                .catch_unwind()
                .await;
            let value = match outcome {
                Ok(report) => report,
                Err(payload) => {
                    tracing::error!(
                        pid = std::process::id(),
                        panic = %panic_text(&payload),
                        "Studio shutdown orchestration task panicked; reporting Degraded"
                    );
                    StudioShutdownReport::panicked()
                }
            };
            let _ = report.send_replace(Some(value));
        });
    }

    /// 等到编排写入完成报告，或到达共享期限。
    pub(super) async fn wait(&self, deadline: Option<Instant>) -> Option<StudioShutdownReport> {
        let mut receiver = self.report.subscribe();
        loop {
            let current: Option<StudioShutdownReport> = (*receiver.borrow()).clone();
            if let Some(report) = current {
                return Some(report);
            }
            match deadline {
                None => {
                    if receiver.changed().await.is_err() {
                        return None;
                    }
                }
                Some(deadline) => {
                    let remaining = deadline.saturating_duration_since(Instant::now());
                    if remaining.is_zero() {
                        return None;
                    }
                    match tokio::time::timeout(remaining, receiver.changed()).await {
                        Ok(Ok(())) => {}
                        Ok(Err(_)) | Err(_) => return None,
                    }
                }
            }
        }
    }
}

//! Owned stage waits, shared deadline and retained service completions.

use futures::FutureExt;
use futures::stream::StreamExt;

use crate::StudioPendingPersistence;
use crate::studio::StudioRuntime;
use crate::studio::runtime::observation_lifecycle::{
    ObservationCloseError, RuntimeObservationOwner, RuntimeObserver,
};
use anyhow::Result;
use futures::future::BoxFuture;
use futures::stream::FuturesUnordered;
use std::future::Future;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::task::JoinHandle;

/// 本次关闭可用的时间预算；`deadline` 为绝对上限，多个阶段共享同一剩余时间。
///
/// `None` 表示真正无界（严格路径）：不是用一个巨大的假魔数冒充“无上限”。
#[derive(Debug, Clone, Copy)]
pub(super) struct ShutdownBudget {
    deadline: Option<Instant>,
}

impl ShutdownBudget {
    pub(super) fn at_deadline(deadline: Instant) -> Self {
        Self {
            deadline: Some(deadline),
        }
    }

    /// 严格路径不设墙钟上限：失败保留 owner 并允许显式重试。
    pub(super) fn unbounded() -> Self {
        Self { deadline: None }
    }

    pub(super) fn deadline(&self) -> Option<Instant> {
        self.deadline
    }

    pub(super) fn remaining(&self) -> Option<Duration> {
        self.deadline
            .map(|deadline| deadline.saturating_duration_since(Instant::now()))
    }

    pub(super) fn expired(&self) -> bool {
        self.deadline
            .is_some_and(|deadline| Instant::now() >= deadline)
    }

    /// 单个阶段可等待的上限：无界预算下等价于阶段上限；有界预算下再取与总剩余的最小值。
    /// 预算已耗尽时返回 `None`。
    pub(super) fn observe_wait(&self, limit: Duration) -> Option<Duration> {
        match self.remaining() {
            None => Some(limit),
            Some(remaining) if remaining.is_zero() => None,
            Some(remaining) => Some(limit.min(remaining)),
        }
    }

    /// 阶段的等待策略。
    ///
    /// `limit = None` 表示该阶段在严格（无界）预算下必须真实收束：不人为制造墙钟超时，避免
    /// 把正常的大量历史 drain 误判为失败；退出（有界）预算下仍与同一绝对期限取最小。
    /// `limit = Some(_)` 是外部服务自身收束上界，严格与退出路径都遵守。
    fn stage_policy(&self, limit: Option<Duration>) -> StagePolicy {
        match self.deadline {
            None => match limit {
                Some(limit) => StagePolicy::Bounded(limit),
                None => StagePolicy::Unbounded,
            },
            Some(deadline) => {
                let remaining = deadline.saturating_duration_since(Instant::now());
                if remaining.is_zero() {
                    return StagePolicy::Skipped;
                }
                match limit {
                    Some(limit) => StagePolicy::Bounded(limit.min(remaining)),
                    None => StagePolicy::Bounded(remaining),
                }
            }
        }
    }
}

/// 单个阶段的等待策略。
#[derive(Debug, Clone, Copy)]
enum StagePolicy {
    /// 在给定上限内等待。
    Bounded(Duration),
    /// 真实等待，不设本地墙钟上限（严格路径的存储 / Thread / writer 收束）。
    Unbounded,
    /// 预算已耗尽：取消已广播，跳过等待但保留 owner/handle。
    Skipped,
}

/// 一次外部服务关闭任务真实结果；可多次观测，不因等待超时丢失。
#[derive(Debug, thiserror::Error)]
pub(crate) enum ServiceStopFailure {
    /// 服务自身确认失败（含 worker 明确拒绝）。
    #[error("{0}")]
    Failed(#[source] anyhow::Error),
    /// owned 关闭任务 panic / 被取消。
    #[error(transparent)]
    Panicked(tokio::task::JoinError),
}

/// 外部服务关闭的共享完成句柄。
///
/// 关闭任务在 runtime 中只启动一次并常驻于 `ServiceStopSlot`；重复严格关闭 / 重试只再次观测
/// 同一个共享 completion，不重启 stop，也不因等待超时而丢失 owner 或句柄。底层 owned task 与
/// completion 都由 slot 常驻持有，运行时会持续 poll 到结束。
type ServiceStopCompletion = futures::future::Shared<
    futures::future::BoxFuture<'static, Result<(), Arc<ServiceStopFailure>>>,
>;

#[derive(Clone)]
pub(crate) struct ServiceStopJob {
    completion: ServiceStopCompletion,
}

impl ServiceStopJob {
    pub(crate) fn spawn<Fut>(future: Fut) -> Self
    where
        Fut: std::future::Future<Output = anyhow::Result<()>> + Send + 'static,
    {
        let handle = tokio::spawn(future);
        let completion = async move {
            match handle.await {
                Ok(Ok(())) => Ok(()),
                Ok(Err(error)) => Err(Arc::new(ServiceStopFailure::Failed(error))),
                Err(join) => Err(Arc::new(ServiceStopFailure::Panicked(join))),
            }
        }
        .boxed()
        .shared();
        Self { completion }
    }

    /// 观测关闭结果；多个调用者共享同一 completion，超时只放弃等待。
    pub(crate) async fn join(&self) -> Result<(), Arc<ServiceStopFailure>> {
        self.completion.clone().await
    }
}

/// 单个服务关闭任务的常驻槽位；被 runtime 持有，跨阶段与跨重试保留。
pub(crate) type ServiceStopSlot = Arc<tokio::sync::Mutex<Option<ServiceStopJob>>>;

/// runtime 常驻的执行资源关闭槽位。
#[derive(Clone, Default)]
pub(crate) struct ServiceStopSlots {
    pub(crate) lsp: ServiceStopSlot,
    pub(crate) ssh: ServiceStopSlot,
    pub(crate) executor: ServiceStopSlot,
}

/// 一个并发阶段的真实结果。
///
/// 阶段在各自分支内产生本结构，回到编排线程后按 `order` 统一聚合。它不持有
/// `ShutdownCollector`，因此多个独立阶段可以真正并发发起与并发等待，而不是被一把共享锁串行化。
/// `elapsed` 是该阶段自身的收束耗时，用于日志确认独立阶段确实并发完成。
pub(super) struct StageOutcome {
    pub(super) order: usize,
    pub(super) stage: &'static str,
    pub(super) status: StageStatus,
    pub(super) elapsed: Duration,
}

impl StageOutcome {
    /// 该阶段是否真实确认收束（用于写入链的成功判定）。
    pub(super) fn is_done(&self) -> bool {
        matches!(&self.status, StageStatus::Done)
    }
}

/// 并发阶段的终态；失败原因保留 typed / JoinError 事实，留待统一聚合时脱敏记录。
pub(super) enum StageStatus {
    /// 阶段真实完成并确认收束。
    Done,
    /// 阶段自身返回错误。
    Failed(anyhow::Error),
    /// 阶段的 owned task panic / 被取消。
    Panicked(tokio::task::JoinError),
    /// 外部服务关闭任务确认失败。
    ServiceFailure(Arc<ServiceStopFailure>),
    /// 阶段未在上限内收束；只放弃等待，owner/handle 仍被保留。
    TimedOut,
    /// 共享预算已耗尽，取消已广播但未 join。
    Skipped,
}

/// 一次并发阶段推进的汇总结果；回到 `execute_shutdown` 后再写入单一 collector。
///
/// 阶段本身不直接修改 collector，因此它们可以真正并发；这里的字段与 issue 一并由编排线程按
/// 稳定顺序聚合，保证 writer ack 与持久化判定仍由同一 finalize 前置条件决定。
pub(super) struct StageReport {
    pub(super) outcomes: Vec<StageOutcome>,
    pub(super) writer_reclaimed: bool,
    pub(super) persistence: StudioPendingPersistence,
}

/// 一个独立阶段分支的并发句柄：完成后返回它贡献的阶段结果。
pub(super) type StageBranch = BoxFuture<'static, Vec<StageOutcome>>;

/// 并发 poll 一组阶段分支直至全部收束，收集它们贡献的阶段结果。
///
/// `FuturesUnordered` 首次 poll 时会把全部已入队的分支一起推进，因此同一依赖层内的阶段在同一
/// 时刻发起，并共享同一首次绝对期限的剩余预算。
pub(super) async fn drain_stage_branches(
    branches: &mut FuturesUnordered<StageBranch>,
) -> Vec<StageOutcome> {
    let mut outcomes = Vec::new();
    while let Some(mut produced) = branches.next().await {
        outcomes.append(&mut produced);
    }
    outcomes
}

/// 并发运行的单个 runtime 阶段：先 spawn 为 owned task，再按共享预算有界 join。
///
/// 独立阶段各自调用一次，`FuturesUnordered` 会并发 poll 全部阶段，因此它们的 owned task 在几乎
/// 同一时刻启动，并共享同一首次绝对期限的剩余预算——不会出现先 join 一小部分、用它们的等待
/// 耗尽后续阶段预算的串行缺陷。超时 / 预算耗尽只放弃等待，绝不 abort / drop 在途的存储、writer
/// 或 JoinHandle 所有者。
pub(super) async fn run_stage_owned<Fut>(
    runtime: StudioRuntime,
    budget: ShutdownBudget,
    order: usize,
    stage: &'static str,
    limit: Option<Duration>,
    // factory 被持有在 async fn 状态里跨 await，必须 `Send`，否则整个 owned 阶段 future 不是
    // `Send`，无法放进要求跨线程的 `BoxFuture`（`StageBranch`）与 `tokio::spawn`。
    make: impl FnOnce(StudioRuntime) -> Fut + Send,
) -> StageOutcome
where
    Fut: Future<Output = Result<()>> + Send + 'static,
{
    tracing::info!(
        pid = std::process::id(),
        stage,
        resource = "runtime",
        "Studio shutdown stage started"
    );
    let started = Instant::now();
    let task: JoinHandle<Result<()>> = tokio::spawn(make(runtime));
    let status = wait_stage(budget, limit, async move {
        match task.await {
            Ok(Ok(())) => StageStatus::Done,
            Ok(Err(error)) => StageStatus::Failed(error),
            Err(join) => StageStatus::Panicked(join),
        }
    })
    .await;
    StageOutcome {
        order,
        stage,
        status,
        elapsed: started.elapsed(),
    }
}

/// 直接观测已受 scope 监督的 observer，不再 spawn 第二套清理任务。
/// observer 严格路径真实无界，退出路径直接消费同一首次绝对期限。
pub(super) async fn run_observer_stage(
    observations: Arc<RuntimeObservationOwner>,
    observer: RuntimeObserver,
    budget: ShutdownBudget,
    order: usize,
) -> StageOutcome {
    let started = Instant::now();
    let report = observations
        .close(
            observer,
            budget.deadline().map(tokio::time::Instant::from_std),
        )
        .await;
    let status = if report.is_clean() {
        StageStatus::Done
    } else if !report.failures.is_empty() {
        StageStatus::Failed(ObservationCloseError(report).into())
    } else {
        StageStatus::TimedOut
    };
    StageOutcome {
        order,
        stage: observer.label(),
        status,
        elapsed: started.elapsed(),
    }
}

/// 并发观测 `ensure_service_stops` 启动的常驻关闭 job；消费真实 typed 结果。
///
/// 多个服务的 join 由调用方用 `FuturesUnordered` 并发 poll，因此它们的等待共享同一首次绝对期限
/// 的剩余预算，一个服务的挂起不占用其他服务的收束预算。超时 / 预算耗尽只放弃等待：共享 completion
/// 与 owned task 由 runtime 槽位常驻持有，后续严格重试可再次观测同一结果，不重启 stop。
pub(super) async fn join_service_outcome(
    budget: ShutdownBudget,
    order: usize,
    stage: &'static str,
    job: ServiceStopJob,
    limit: Option<Duration>,
) -> StageOutcome {
    tracing::info!(
        pid = std::process::id(),
        stage,
        resource = "service",
        "Studio shutdown stage started"
    );
    let started = Instant::now();
    let status = wait_stage(budget, limit, async move {
        match job.join().await {
            Ok(()) => StageStatus::Done,
            Err(failure) => StageStatus::ServiceFailure(failure),
        }
    })
    .await;
    StageOutcome {
        order,
        stage,
        status,
        elapsed: started.elapsed(),
    }
}

/// 报告内阶段的稳定排序权重；与完成先后无关，保证并发收束下报告顺序可复现。
pub(super) mod stage_order {
    pub(in crate::studio::runtime::lifecycle::shutdown) const AGENT_FRAMEWORK: usize = 0;
    pub(in crate::studio::runtime::lifecycle::shutdown) const PERSISTENCE: usize = 1;
    pub(in crate::studio::runtime::lifecycle::shutdown) const MODEL_CATALOG: usize = 2;
    pub(in crate::studio::runtime::lifecycle::shutdown) const RECOVERY: usize = 3;
    pub(in crate::studio::runtime::lifecycle::shutdown) const MODEL_REFRESH: usize = 4;
    pub(in crate::studio::runtime::lifecycle::shutdown) const TITLE: usize = 5;
    pub(in crate::studio::runtime::lifecycle::shutdown) const LSP_STATE: usize = 10;
    pub(in crate::studio::runtime::lifecycle::shutdown) const LSP_STOP: usize = 11;
    pub(in crate::studio::runtime::lifecycle::shutdown) const LSP_STOPPED: usize = 12;
    pub(in crate::studio::runtime::lifecycle::shutdown) const TOOL_REFRESH: usize = 13;
    pub(in crate::studio::runtime::lifecycle::shutdown) const PERSISTENCE_OBSERVER: usize = 14;
    pub(in crate::studio::runtime::lifecycle::shutdown) const SSH: usize = 15;
    pub(in crate::studio::runtime::lifecycle::shutdown) const AGENT_PROFILES: usize = 16;
    pub(in crate::studio::runtime::lifecycle::shutdown) const ACP_AUTH: usize = 17;
    pub(in crate::studio::runtime::lifecycle::shutdown) const BOTS: usize = 18;
    pub(in crate::studio::runtime::lifecycle::shutdown) const ACP_INSTALL: usize = 19;
    pub(in crate::studio::runtime::lifecycle::shutdown) const ACCOUNT_USAGE: usize = 20;
    pub(in crate::studio::runtime::lifecycle::shutdown) const ACP_LOCAL_DETECTION: usize = 21;
    pub(in crate::studio::runtime::lifecycle::shutdown) const EXECUTOR: usize = 22;
    pub(in crate::studio::runtime::lifecycle::shutdown) const STORE: usize = 23;
}

/// 在常驻槽位上只启动一次真正的 stop 工作；已存在则返回同一共享句柄。
pub(super) async fn ensure_service_stop(
    slot: &ServiceStopSlot,
    start: impl FnOnce() -> ServiceStopJob,
) -> ServiceStopJob {
    let mut guard = slot.lock().await;
    if let Some(job) = guard.as_ref() {
        return job.clone();
    }
    let job = start();
    *guard = Some(job.clone());
    job
}

async fn wait_stage(
    budget: ShutdownBudget,
    limit: Option<Duration>,
    wait: impl Future<Output = StageStatus>,
) -> StageStatus {
    match budget.stage_policy(limit) {
        StagePolicy::Skipped => StageStatus::Skipped,
        StagePolicy::Bounded(limit) => tokio::time::timeout(limit, wait)
            .await
            .unwrap_or(StageStatus::TimedOut),
        StagePolicy::Unbounded => wait.await,
    }
}

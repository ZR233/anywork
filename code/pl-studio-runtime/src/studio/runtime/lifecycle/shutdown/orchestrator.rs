//! Shutdown sequencing and shared service ownership.

use futures::FutureExt;

use super::diagnostics::{
    PersistenceFacts, ShutdownCollector, shutdown_issue_from_error, shutdown_report_error,
};
use super::stages::{
    ServiceStopJob, ShutdownBudget, StageBranch, StageOutcome, StageReport, StageStatus,
    drain_stage_branches, ensure_service_stop, join_service_outcome, run_observer_stage,
    run_stage_owned, stage_order,
};
use crate::studio::runtime::observation_lifecycle::RuntimeObserver;
use crate::studio::{
    StudioRuntime, StudioRuntimeCommand, StudioRuntimeSnapshot, StudioRuntimeStateKind,
    unix_seconds,
};
use crate::{
    StudioPendingPersistence, StudioShutdownIssue, StudioShutdownOutcome, StudioShutdownReport,
};
use anyhow::Result;
use futures::stream::FuturesUnordered;
use std::future::Future;
use std::time::{Duration, Instant};

/// 单个外部服务阶段的上限；多个完整超时不得简单相加超出总预算。
pub(super) const SERVICE_STAGE_LIMIT: Duration = Duration::from_secs(5);
/// 只读事实观测（runtime 快照、持久化计数）的上限：绝不允许在阶段之外无界等待。
const FACTS_LIMIT: Duration = Duration::from_secs(2);

impl StudioRuntime {
    /// 只读持久化诊断事实：保留中的 writer owner 标识与已 durable 保存水位。
    ///
    /// 只读取现有事实，不改变任何 owner；锁竞争或 owner 缺失时返回 `"未知"`，不阻塞、
    /// 绝不用零掩盖未知。
    pub fn persistence_diagnostics(&self) -> (Option<String>, Option<u64>) {
        match self.agent_facility.persistence.try_lock() {
            Ok(slot) => match slot.as_ref() {
                Some(repository) => (
                    Some("write-behind-writer".to_string()),
                    Some(repository.saved_watermark()),
                ),
                None => (None, None),
            },
            Err(_) => (None, None),
        }
    }

    /// 严格关闭：所有阶段成功才算成功，失败保留 owner 与重试入口。
    pub(in crate::studio::runtime) async fn execute_strict_shutdown(
        &self,
    ) -> Result<StudioShutdownReport> {
        let report = self
            .execute_shutdown(ShutdownBudget::unbounded(), Vec::new())
            .await;
        if report.is_clean() {
            Ok(report)
        } else {
            Err(shutdown_report_error(&report))
        }
    }

    /// 应用退出关闭：返回 typed 报告，接受 `Degraded`。
    ///
    /// 首次调用的剩余预算固定唯一 deadline；重复调用只 join 同一个 owned 编排任务，不延长期限。
    ///
    /// `external_issues` 是调用方（native / Dart 与 bridge 自身）在进入 runtime 编排之前
    /// 已经确定的失败，例如桥端或 Dart 侧订阅、更新取消未确认。它们被就地播种为这次关闭的
    /// 成功前置条件，绝不事后合并：只要存在任何一条，收束阶段就不会判定 `Clean`，也就不会
    /// 发布 `Stopped` 或释放实例锁。
    pub(in crate::studio::runtime) async fn execute_exit_shutdown(
        &self,
        remaining_ms: u32,
        external_issues: Vec<StudioShutdownIssue>,
    ) -> StudioShutdownReport {
        // 同步封闭 runtime 准入闩：先于任何 await 与锁等待，退出期间拒绝迟到安装与新 mutation。
        self.shutdown_latch.arm();
        let requested = Duration::from_millis(u64::from(remaining_ms));
        let deadline = self.shutdown_run.fixed_deadline(requested);
        let budget = ShutdownBudget::at_deadline(deadline);
        self.shutdown_run.spawn_once(self, budget, external_issues);
        match self.shutdown_run.wait(Some(deadline)).await {
            Some(report) => report,
            None => StudioShutdownReport::deadline_exceeded(
                "deadline",
                crate::StudioError::internal().correlation_id,
            ),
        }
    }

    /// 应用退出的早期封闭步骤（native 首次 close 时调用）。
    ///
    /// 与随后的 `shutdown_runtime_for_exit` 共用同一关闭 coordinator：本步只做两件在途安装
    /// 无法越过的封闭动作——
    ///
    /// 1. arm 单向终止闩（先于任何 await），并同步把可关闭状态推进到 `ShuttingDown`，封闭新
    ///    mutation 与迟到安装；
    /// 2. 向所有彼此独立的在途 owner（后台 watcher、title 任务、持久化 observer）广播一次
    ///    取消 / abort。
    ///
    /// 成员 MCP 在原 owner 内尽早启动唯一 stop，与终态保存独立推进；本步绝不 join，
    /// 不关闭数据库 / 释放实例锁，不启动 LSP/SSH 的真正 stop，也不发布
    /// `Stopped`——这些仍由随后的同一编排完成，早期 arm 不会被误认为最终终态。早期观测到的诊断
    /// 被写入常驻槽位，由 `execute_shutdown` 就地播种为成功前置条件，既不吞错也不伪成功。
    ///
    /// 本步有界：独立 owner 的取消广播各自带锁上限，不做任何可能无界阻塞的 join；状态观测与
    /// 推进只持有无 await 的短临界区，绝不在任何锁上无界等待。
    pub async fn fence_exit_admission(&self) -> Vec<StudioShutdownIssue> {
        self.shutdown_latch.arm();
        let mut issues = Vec::new();
        let snapshot = self.runtime_state.snapshot();
        // 只对可关闭状态推进为 `ShuttingDown`；未安装 / 初始化中 / 已进入关闭或终态既不触发
        // 初始化，也不重复推进状态。
        if matches!(
            snapshot.state.kind(),
            StudioRuntimeStateKind::Ready | StudioRuntimeStateKind::Failed
        ) && let Err(error) = self
            .runtime_state
            .apply(StudioRuntimeCommand::BeginShutdown {
                expected_revision: snapshot.revision,
                at: unix_seconds(),
            })
        {
            issues.push(shutdown_issue_from_error(
                "beginShutdown",
                &anyhow::Error::from(error),
            ));
        }
        self.broadcast_cancel().await;
        if !issues.is_empty() {
            for issue in &issues {
                tracing::error!(
                    pid = std::process::id(),
                    stage = %issue.stage,
                    code = %issue.code,
                    resource = "runtimeState",
                    correlation_id = %issue.correlation_id,
                    retryable = issue.retryable,
                    detail = %issue.message,
                    "Studio runtime early exit fence reported a failure"
                );
            }
            let mut slot = match self.early_exit_issues.lock() {
                Ok(slot) => slot,
                Err(poisoned) => poisoned.into_inner(),
            };
            slot.extend(issues.iter().cloned());
        }
        issues
    }

    /// 取走早期退出封闭观测到的诊断，交由同一编排播种（只取一次，重试不重复播种）。
    fn take_early_exit_issues(&self) -> Vec<StudioShutdownIssue> {
        let mut slot = match self.early_exit_issues.lock() {
            Ok(slot) => slot,
            Err(poisoned) => poisoned.into_inner(),
        };
        std::mem::take(&mut *slot)
    }

    /// 统一阶段编排；严格与退出路径都经由它，不维护第二套实现。
    ///
    /// `external_issues` 作为同一编排的最终成功前置条件被就地播种，不是事后合并的第二事实源。
    pub(super) async fn execute_shutdown(
        &self,
        budget: ShutdownBudget,
        external_issues: Vec<StudioShutdownIssue>,
    ) -> StudioShutdownReport {
        let mut collector = ShutdownCollector::new(budget);

        // 只读持久化事实先于快照观测，让后续任何早期失败的诊断都带真实 owner / 水位。
        self.capture_persistence_facts(&mut collector).await;
        let current = self.observe_snapshot(&mut collector).await;

        // 播种调用方（Dart / bridge）在进入编排前已经确定的失败，作为这次关闭的成功前置条件；
        // 放在事实观测之后，使诊断带上真实 owner 与保存水位。
        collector.seed_external_issues(external_issues);
        // native 首次 close 的早期封闭（准入封闭 + 独立取消广播）遗留的诊断同样作为这次关闭的
        // 成功前置条件播种：早期 arm 未被误认为最终终态，早期错误也不被吞掉。
        collector.seed_external_issues(self.take_early_exit_issues());

        // 从未安装 / 已终态：不触发初始化、不做阶段编排。但调用方与 bridge 持有的外部 owner
        // 仍可能未确认，必须按同一成功前置条件收束，绝不能以
        // `Clean`/`NotStarted` 掩盖未收束的 owner。
        let never_installed = current.as_ref().is_some_and(|current| {
            matches!(current.state.kind(), StudioRuntimeStateKind::Uninitialized)
        });
        let already_stopped = current
            .as_ref()
            .is_some_and(|current| current.state.is_stopped());
        if never_installed || already_stopped {
            return if collector.has_issues() {
                collector.report()
            } else if never_installed {
                // 从未安装：不触发初始化、不武装闩；没有待保存事实。
                StudioShutdownReport::not_started()
            } else {
                // 已经处于终态的 runtime 只有在没有任何issue 时才可报 Clean。
                StudioShutdownReport {
                    outcome: StudioShutdownOutcome::Clean,
                    issues: Vec::new(),
                    persistence: StudioPendingPersistence::Drained,
                }
            };
        }

        // 单向终止闩：先于任何阶段武装，拒绝迟到安装；快照不可用时也照样封闭，绝不因只读观测
        // 失败而漏掉独立取消（准入封闭与取消不依赖 runtime 快照）。
        self.shutdown_latch.arm();
        if let Some(exporter) = &self.agent_facility.run_export {
            exporter.arm_shutdown_deadline(budget.deadline().map(tokio::time::Instant::from_std));
        }

        if let Some(current) = current.as_ref()
            && matches!(current.state.kind(), StudioRuntimeStateKind::Initializing)
        {
            // 初始化未完成：不得伪报 NotStarted；记录诊断后仍继续安全清理已创建资源。
            let stage_elapsed_ms = collector.elapsed_ms();
            collector.record_error(
                "installation",
                stage_elapsed_ms,
                &anyhow::anyhow!("runtime initialization is still in progress"),
            );
        }

        // BeginShutdown（best-effort）：只接受 Ready/Failed 的 typed 命令；快照缺失或初始化中仍
        // 封闭准入并继续独立清理，失败本身被记为诊断而不会阻断取消与收尾。
        let begin = match current.as_ref() {
            Some(current)
                if matches!(
                    current.state.kind(),
                    StudioRuntimeStateKind::Ready | StudioRuntimeStateKind::Failed
                ) =>
            {
                self.runtime_state
                    .apply(StudioRuntimeCommand::BeginShutdown {
                        expected_revision: current.revision,
                        at: unix_seconds(),
                    })
                    .map(|_| ())
            }
            Some(_) => Ok(()),
            None => {
                let revision = self.runtime_state.snapshot().revision;
                self.runtime_state
                    .apply(StudioRuntimeCommand::BeginShutdown {
                        expected_revision: revision,
                        at: unix_seconds(),
                    })
                    .map(|_| ())
            }
        };
        if let Err(error) = begin {
            // BeginShutdown 失败不可吞：直接进入 Degraded 但继续安全清理。
            let stage_elapsed_ms = collector.elapsed_ms();
            collector.record_error("beginShutdown", stage_elapsed_ms, &error.into());
        }

        // 提交准入后**先**向所有独立 owner 广播取消，并启动/常驻保留 MCP/LSP/SSH 的 owned 关闭
        // job。真正的阶段 join 与 finalize 仍在后续同一编排内、复用同一批 job。
        self.broadcast_cancel().await;

        let stages = self
            .run_shutdown_stages(budget, collector.pending_hint)
            .await;
        collector.writer_reclaimed = stages.writer_reclaimed;
        collector.persistence = stages.persistence;
        for outcome in stages.outcomes {
            collector.record_stage(outcome);
        }

        self.finalize_shutdown(&mut collector).await;
        collector.report()
    }

    async fn observe_snapshot(
        &self,
        collector: &mut ShutdownCollector,
    ) -> Option<StudioRuntimeSnapshot> {
        let wait = collector
            .budget
            .observe_wait(FACTS_LIMIT)
            .unwrap_or(Duration::ZERO);
        match tokio::time::timeout(wait, self.runtime_snapshot()).await {
            Ok(Ok(snapshot)) => Some(snapshot),
            Ok(Err(error)) => {
                let stage_elapsed_ms = collector.elapsed_ms();
                collector.record_error("snapshot", stage_elapsed_ms, &error);
                None
            }
            Err(_) => {
                let stage_elapsed_ms = collector.elapsed_ms();
                collector.record_timeout("snapshot", stage_elapsed_ms);
                None
            }
        }
    }

    /// 观测真实持久化事实（可未知）；只读，不改变 owner。
    async fn capture_persistence_facts(&self, collector: &mut ShutdownCollector) {
        let wait = collector
            .budget
            .observe_wait(FACTS_LIMIT)
            .unwrap_or(Duration::ZERO);
        match tokio::time::timeout(wait, self.persistence_facts()).await {
            Ok(Ok(facts)) => {
                collector.pending_hint = Some(facts.pending);
                collector.save_watermark = facts.save_watermark;
                collector.owner_id = facts.owner_id;
                collector.unresolved_thread_ids = facts.unresolved_thread_ids;
                collector.history_admitted_min = facts.history_admitted_min;
                collector.history_durable_min = facts.history_durable_min;
                collector.fault_generation = facts.fault_generation;
            }
            Ok(Err(error)) => {
                let stage_elapsed_ms = collector.elapsed_ms();
                collector.record_error("persistenceFacts", stage_elapsed_ms, &error);
            }
            Err(_) => {
                let stage_elapsed_ms = collector.elapsed_ms();
                collector.record_timeout("persistenceFacts", stage_elapsed_ms);
            }
        }
    }

    async fn persistence_facts(&self) -> Result<PersistenceFacts> {
        let repository = self.agent_facility.persistence.lock().await.clone();
        let (writer_pending, save_watermark, owner_id) = match repository {
            Some(repository) => (
                repository.pending_commit_count(),
                Some(repository.saved_watermark()),
                Some("write-behind-writer".to_string()),
            ),
            None => (0, None, None),
        };

        // ThreadHistoryCoordinator 的真实水位：逐 Thread 的 admitted/durable/fault 与未收束标识。
        // 全局确认水位取所有 owner 的**最小值**：只有每个 owner 都推进到该值才能对外声明
        // “已确认到此处”，绝不用某个 owner 的最大值冒充全局确认。
        let snapshot = self.store.thread_persistence().snapshot();
        let mut unresolved_thread_ids = Vec::new();
        let mut history_admitted_min: Option<u64> = None;
        let mut history_durable_min: Option<u64> = None;
        let mut fault_generation: Option<u64> = None;
        for thread in &snapshot.threads {
            if thread.pending_operations > 0
                || thread.in_flight_bytes > 0
                || thread.last_error.is_some()
                || thread.fault.is_some()
            {
                unresolved_thread_ids.push(thread.thread_id.clone());
            }
            if let Some(admitted) = thread.history_admitted_sequence {
                history_admitted_min =
                    Some(history_admitted_min.map_or(admitted, |prev| prev.min(admitted)));
            }
            if let Some(durable) = thread.history_durable_sequence {
                history_durable_min =
                    Some(history_durable_min.map_or(durable, |prev| prev.min(durable)));
            }
            if thread.fault.is_some() {
                fault_generation = Some(fault_generation.map_or(thread.fault_generation, |prev| {
                    prev.max(thread.fault_generation)
                }));
            }
        }

        Ok(PersistenceFacts {
            pending: writer_pending
                + usize::try_from(snapshot.pending_commits).unwrap_or(usize::MAX),
            save_watermark,
            owner_id,
            unresolved_thread_ids,
            history_admitted_min,
            history_durable_min,
            fault_generation,
        })
    }

    /// 在阶段 join 之前，向所有独立 owner 广播取消 / abort。
    ///
    /// 纯观察 scope 协作取消；其余后台任务保留原取消方式。此步不做任何可能无界阻塞的
    /// 服务 join，保证所有独立资源先收到取消。
    pub(in crate::studio::runtime::lifecycle) async fn broadcast_cancel(&self) {
        self.observations.request_close();
        self.thread_observations.close_deliveries();
        self.account_usage.request_close();
        self.model_performance.request_close();
        // A member's terminal save can be blocked by SQLite while Dart is joining its readers.
        // Start the original MCP owner's retained stop now; the Session close still joins the
        // same completion and only then removes its scope. No writer/transport is released here.
        self.thread_factory.request_member_mcp_shutdown();
        use crate::studio::runtime::background_task;
        background_task::signal(&self.settings_refresh).await;
        background_task::signal(&self.recovery_task).await;
        self.title_tasks.signal_cancel().await;
        // ACP 认证操作只接收取消信号：真正的 protocol/进程收束与终态由该 owner 自己的
        // supervisor 完成，随后在独立阶段有界 join，避免提前释放仍存活的进程。
        self.acp_accounts.signal_cancel();
        self.chatgpt_auth.signal_cancel();
        // 官方 server 准备同样只接收取消信号：下载库、校验/解压阻塞任务与发布提交的收束与终态
        // 由该 owner 自己的 supervisor 完成，随后在独立阶段有界 join。
        self.acp_install.signal_cancel();
        self.acp_detection.signal_cancel();
        // 全局关停还必须取消独立后台工具，不能只中断当前 Turn，或等保存/观察者 join 后才发信号。
        // 这里只发信号，不 join、也不 close——真正的收束仍由后续唯一 `agentFramework` 阶段完成，
        // 因此不会重复 close，也绝不提前释放 writer 或实例锁。先前已封闭准入，取消只是加速在途
        // 执行的退出，满足「先封闭准入并广播取消（含 Turn）再 join」。
        for (_, handle) in self.sessions.observed_threads() {
            handle.request_shutdown();
        }
    }

    pub(super) async fn run_shutdown_stages(
        &self,
        budget: ShutdownBudget,
        pending_before: Option<usize>,
    ) -> StageReport {
        let progress = self.shutdown_progress.clone();

        // 取消已在 `execute_shutdown` 中先于任何 join 广播完毕。这里的进度事件只表达"以下独立
        // 阶段都已并发在途"，不是串行契约：全部独立阶段在同一时刻发起、共享同一首次绝对期限的
        // 剩余预算，任何一个阶段的等待都不会消耗其他阶段尚未开始的预算。
        progress.emit(crate::StudioShutdownProgress::StoppingSubscriptions(
            Default::default(),
        ));
        progress.emit(crate::StudioShutdownProgress::CancellingTurns(
            Default::default(),
        ));
        progress.emit(crate::StudioShutdownProgress::StoppingAgents(
            Default::default(),
        ));
        progress.emit(crate::StudioShutdownProgress::StoppingMcp(
            Default::default(),
        ));
        progress.emit(crate::StudioShutdownProgress::StoppingLsp(
            Default::default(),
        ));

        // 写入生产者：它们是可靠保存的前提，其停止必须先于持久化 drain 与 writer 停止——编排在
        // 生产者收束观测结束后才推进持久化（有界退出路径下个别生产者超时也继续，但缺 ACK 会成为
        // issue、不会伪报 Clean）。这些阶段彼此独立，因此并发发起、并发等待（不会用前一个的等待
        // 耗尽后续阶段预算）。
        let (sessions_ready_tx, sessions_ready_rx) = tokio::sync::oneshot::channel::<bool>();
        let (lsp_projection_tx, lsp_projection_rx) = tokio::sync::oneshot::channel::<bool>();
        let (transport_ready_tx, transport_ready_rx) = tokio::sync::oneshot::channel::<bool>();
        let mut producers: FuturesUnordered<StageBranch> = FuturesUnordered::new();
        producers.push(self.stage_branch(
            budget,
            stage_order::ACCOUNT_USAGE,
            "accountUsage",
            Some(SERVICE_STAGE_LIMIT),
            |runtime| async move { runtime.account_usage.close().await },
        ));
        producers.push(self.stage_branch(
            budget,
            stage_order::MODEL_CATALOG,
            "modelCatalog",
            Some(SERVICE_STAGE_LIMIT),
            |runtime| async move { runtime.stop_model_catalog_probes().await },
        ));
        producers.push(self.stage_branch(
            budget,
            stage_order::RECOVERY,
            "recovery",
            Some(SERVICE_STAGE_LIMIT),
            |runtime| async move { runtime.stop_recovery_scan().await },
        ));
        producers.push(self.stage_branch(
            budget,
            stage_order::MODEL_REFRESH,
            "modelRefresh",
            Some(SERVICE_STAGE_LIMIT),
            |runtime| async move { runtime.stop_model_refresh().await },
        ));
        producers.push(self.stage_branch(
            budget,
            stage_order::TITLE,
            "title",
            Some(SERVICE_STAGE_LIMIT),
            |runtime| async move {
                runtime.title_tasks.cancel_and_wait().await;
                Ok::<(), anyhow::Error>(())
            },
        ));
        // Thread/审计收束是可靠的保存前提：严格路径真实等待，退出路径仍受同一期限裁剪。
        producers.push(self.stage_branch(
            budget,
            stage_order::AGENT_FRAMEWORK,
            "agentFramework",
            None,
            |runtime| async move { runtime.shutdown_agent_framework().await },
        ));

        // 远端服务依赖组（独立外部 owner）：与写入收束链（生产者 → 持久化）并发发起、并发等待，
        // 不被持久化 drain 拖后，也不反过来抢占生产者尚未开始的等待预算。这些 owner 直接承载或
        // 观测远端 MCP/LSP/工具通信，SSH transport 必须在它们的停止请求与结果处理**之后**才关闭
        // （见下方 `ssh_branch` 的依赖闸门）；它们彼此独立，因此在同一组内并发发起、并发收束，
        // 而不是串行等待，每个分支都有界（见各自 limit）。
        let mut remote_dependents: FuturesUnordered<StageBranch> = FuturesUnordered::new();
        remote_dependents.push(self.stage_branch(
            budget,
            stage_order::TOOL_REFRESH,
            "toolRefresh",
            Some(SERVICE_STAGE_LIMIT),
            |runtime| async move { runtime.stop_tool_refresh().await },
        ));
        // ACP 认证操作持有官方 server 进程与管道；取消已广播，这里是有界 join。超时保留 owner
        // 与 join 句柄，令 `Clean` 不可达并可重试，绝不伪报已回收。
        remote_dependents.push(self.stage_branch(
            budget,
            stage_order::ACP_AUTH,
            "acpAuth",
            Some(SERVICE_STAGE_LIMIT),
            |runtime| async move {
                runtime.chatgpt_auth.close().await?;
                runtime.acp_accounts.cancel_and_join().await
            },
        ));
        // ACP server 准备持有下载、校验/解压阻塞任务、文件锁与发布提交；取消已广播，这里是有界
        // join。超时保留 owner 与 join 句柄，令 `Clean` 不可达并可重试。
        remote_dependents.push(self.stage_branch(
            budget,
            stage_order::ACP_INSTALL,
            "acpInstall",
            Some(SERVICE_STAGE_LIMIT),
            |runtime| async move { runtime.acp_install.cancel_and_join().await },
        ));
        remote_dependents.push(self.stage_branch(
            budget,
            stage_order::ACP_LOCAL_DETECTION,
            "acpLocalDetection",
            Some(SERVICE_STAGE_LIMIT),
            |runtime| async move { runtime.acp_detection.close().await },
        ));

        // Session 与本次 lspState 都必须真实 ACK，才允许启动 retained stop job。
        let lsp_runtime = self.clone();
        remote_dependents.push(
            async move {
                let dependency_started = Instant::now();
                let (sessions, projection) = futures::join!(sessions_ready_rx, lsp_projection_rx);
                if !matches!(sessions, Ok(true)) || !matches!(projection, Ok(true)) {
                    return vec![StageOutcome { order: stage_order::LSP_STOP, stage: "lspStop", status: StageStatus::Failed(anyhow::anyhow!("Session or LSP projection resources have not closed; shared LSP retained")), elapsed: dependency_started.elapsed() }];
                }
                let lsp_job = lsp_runtime.start_lsp_stop().await;
                let stop = join_service_outcome(
                    budget,
                    stage_order::LSP_STOP,
                    "lspStop",
                    lsp_job,
                    Some(SERVICE_STAGE_LIMIT),
                )
                .await;
                let acked = stop.is_done();
                let mut outcomes = vec![stop];
                if acked {
                    outcomes.push(
                        run_stage_owned(
                            lsp_runtime,
                            budget,
                            stage_order::LSP_STOPPED,
                            "lspStopped",
                            Some(SERVICE_STAGE_LIMIT),
                            |runtime| async move { runtime.external_runtimes.lsp_state.stopped().await },
                        )
                        .await,
                    );
                }
                outcomes
            }
            .boxed(),
        );

        // 三类 observer 并发收束；lspState 只发送本次结果的 ACK，结果仍仅由原阶段收集一次。
        let mut independent: FuturesUnordered<StageBranch> = FuturesUnordered::new();
        let observations = self.observations.clone();
        independent.push(
            async move {
                let outcome = run_observer_stage(
                    observations,
                    RuntimeObserver::Lsp,
                    budget,
                    stage_order::LSP_STATE,
                )
                .await;
                let _ = lsp_projection_tx.send(outcome.is_done());
                vec![outcome]
            }
            .boxed(),
        );
        for (observer, order) in [
            (
                RuntimeObserver::Persistence,
                stage_order::PERSISTENCE_OBSERVER,
            ),
            (RuntimeObserver::Profiles, stage_order::AGENT_PROFILES),
        ] {
            independent.push(
                run_observer_stage(self.observations.clone(), observer, budget, order)
                    .map(|outcome| vec![outcome])
                    .boxed(),
            );
        }

        independent.push(self.stage_branch(
            budget,
            stage_order::BOTS,
            "bots",
            Some(SERVICE_STAGE_LIMIT),
            |runtime| async move {
                runtime
                    .bots
                    .shutdown()
                    .await
                    .map_err(|error| anyhow::Error::from(error.studio_error()))
            },
        ));

        // 写入生产者依赖的共享完成信号：写入链在生产者收束观测结束后继续持久化；SSH 依赖同一份
        // 生产者事实——远端工具由 Turn / Agent 等生产者驱动，它们未收束时不得先切断 SSH 通信——
        // 但 SSH 只等这条依赖边，不等与它无关的持久化 / 数据库提交。信号载荷刻意区分两件事实：
        // 收到信号 = 依赖已结束观测（含失败 / 有界超时 / 预算耗尽），载荷 `bool` = 实际是否全部
        // 成功 ACK。信号不携带 outcome，避免复制不可 Clone 的诊断，也不引入第二份事实源：写入链
        // 仍是生产者 outcome 的唯一持有与记录方。
        let (producers_settled_tx, producers_settled_rx) = tokio::sync::oneshot::channel::<bool>();

        // SSH transport 关闭的依赖闸门：并发等待全部远端依赖（MCP/LSP stop 链、工具刷新、
        // MCP watcher）的停止请求与结果处理，以及写入生产者的收束观测，之后才在常驻槽位请求
        // SSH 回收；仍只 join 已启动的那一次 owned task，真实结果不被 `let _ =` 吞掉。依赖等待与
        // 真正的 SSH stop 分别计时：依赖等待只做闸门，SSH stop 的耗时由 `join_service_outcome` 的
        // `elapsed` 单独给出。Session 或 LSP 尚未真正关闭时保留 transport，使原 owner 可重试。
        let ssh_runtime = self.clone();
        let ssh_branch = async move {
            let dependents_started = Instant::now();
            let (mut outcomes, producers_signal, transport_signal) = futures::join!(
                drain_stage_branches(&mut remote_dependents),
                producers_settled_rx,
                transport_ready_rx,
            );
            let dependents_elapsed_ms = dependents_started.elapsed().as_millis() as u64;
            // 区分「依赖已结束观测」与「实际全部成功 ACK」：前者只要信号送达即成立，后者只由载荷
            // `true` 表达。资源依赖的真实 ACK 决定是否允许关闭共享 transport。
            let producers_observed = producers_signal.is_ok();
            let producers_acked = matches!(&producers_signal, Ok(true));
            tracing::info!(
                pid = std::process::id(),
                stage = "sshTransport",
                resource = "service",
                dependents_settled = outcomes.len(),
                dependents_elapsed_ms,
                producers_observed,
                producers_acked,
                "Studio shutdown SSH dependency gate released; requesting transport recycle"
            );
            if !matches!(transport_signal, Ok(true))
                || !outcomes
                    .iter()
                    .any(|outcome| outcome.stage == "lspStop" && outcome.is_done())
            {
                outcomes.push(StageOutcome {
                    order: stage_order::SSH,
                    stage: "ssh",
                    status: StageStatus::Failed(anyhow::anyhow!(
                        "Session or LSP resources have not closed; shared SSH retained"
                    )),
                    elapsed: Duration::ZERO,
                });
                return outcomes;
            }
            // Session 和 LSP 均已交还其进程后，关闭本地执行器并等待受管任务收束。
            // 常驻槽位保留真实任务；上层等待超时不会丢弃后台回收的所有权。
            let executor_job = ensure_service_stop(&ssh_runtime.service_stops.executor, {
                let executor = ssh_runtime.thread_factory.local_executor();
                move || {
                    ServiceStopJob::spawn(async move {
                        executor.close().await.map_err(anyhow::Error::from)
                    })
                }
            })
            .await;
            outcomes.push(
                join_service_outcome(
                    budget,
                    stage_order::EXECUTOR,
                    "executor",
                    executor_job,
                    Some(SERVICE_STAGE_LIMIT),
                )
                .await,
            );
            let ssh_job = ssh_runtime.start_ssh_stop().await;
            outcomes.push(
                join_service_outcome(
                    budget,
                    stage_order::SSH,
                    "ssh",
                    ssh_job,
                    Some(SERVICE_STAGE_LIMIT),
                )
                .await,
            );
            outcomes
        };

        // 写入收束链：生产者停止观测先于可靠持久化 drain/writer 停止（有向顺序，不可颠倒）；
        // 真正的停止 ACK 由各生产者 outcome 决定并在收尾判定，缺 ACK 不会伪报 Clean。整条链与上面
        // 的独立资源并发进行——独立服务不会被持久化 drain 的等待拖后。
        let write_chain = {
            let progress = progress.clone();
            let runtime = self.clone();
            async move {
                // 先并发收束全部写入生产者；无论成功、失败还是有界超时，都在它们的收束观测结束后才
                // 推进持久化 drain/writer——持久化不早于生产者停止观测，但也不会因个别生产者不可用而
                // 永久阻塞其余安全清理（缺 ACK 会作为 issue 阻止最终 Clean，不在此处伪成功）。
                let mut outcomes = drain_stage_branches(&mut producers).await;
                // 放行 SSH 依赖闸门并如实携带「实际是否全部成功 ACK」：写入链仍是 outcome 唯一记录方，
                // 这里只传事实、不复制诊断。成功与有界失败都照样请求 SSH 回收。
                let producers_acked = outcomes.iter().all(StageOutcome::is_done);
                let _ = producers_settled_tx.send(producers_acked);
                let agent_ok = outcomes
                    .iter()
                    .any(|outcome| outcome.stage == "agentFramework" && outcome.is_done());
                if !agent_ok && let Some(exporter) = &runtime.agent_facility.run_export {
                    exporter.close_admission_on_producer_timeout();
                }
                let _ = sessions_ready_tx.send(agent_ok);
                let _ = transport_ready_tx.send(agent_ok);
                // 只在真实已知时发布 pending count；未知不伪造 0。
                if let Some(pending_before) = pending_before {
                    progress.emit(crate::StudioShutdownProgress::FlushingPersistence(
                        crate::FlushingPersistenceProgress::new(pending_before as u64),
                    ));
                }
                // 可靠保存在严格路径真实等待（大量历史 drain 不是失败）；退出路径共享同一期限。
                let persistence = run_stage_owned(
                    runtime.clone(),
                    budget,
                    stage_order::PERSISTENCE,
                    "persistence",
                    None,
                    |runtime| async move { runtime.flush_persistence().await },
                )
                .await;
                let flush_ok = persistence.is_done();
                outcomes.push(persistence);
                // 观测真实剩余待保存事实；有界只读，未知即 Unknown，绝不用 0 冒充。
                let pending_after = runtime.observe_pending(budget).await;
                if let Some(exporter) = &runtime.agent_facility.run_export {
                    let _report = exporter
                        .finalize_during_shutdown(
                            budget.deadline().map(tokio::time::Instant::from_std),
                            agent_ok,
                            flush_ok,
                            pending_after,
                        )
                        .await;
                }
                (outcomes, agent_ok, flush_ok, pending_after)
            }
        };

        // 写入链、非 SSH 依赖的本地资源、以及依赖闸门后的 SSH 回收三者同时推进：SSH 内只等它的
        // 两条依赖边（`remote_dependents` 的远端服务/工具停止与写入生产者停止 ACK），不等与它
        // 无关的持久化 / 数据库提交——因此保存锁阻塞时 MCP/LSP、远端依赖与 SSH transport 仍能
        // 各自及时收束。
        let independent_branch = async move { drain_stage_branches(&mut independent).await };
        let (
            (write_outcomes, agent_ok, flush_ok, pending_after),
            mut independent_outcomes,
            mut ssh_outcomes,
        ) = futures::join!(write_chain, independent_branch, ssh_branch);

        // 汇总所有阶段的真实结果：按稳定权重排序，报告顺序不随完成先后抖动。
        let mut outcomes = write_outcomes;
        outcomes.append(&mut independent_outcomes);
        outcomes.append(&mut ssh_outcomes);
        outcomes.sort_by_key(|outcome| outcome.order);

        let persistence = match (agent_ok, flush_ok, pending_after) {
            (true, true, Some(0)) => {
                progress.emit(crate::StudioShutdownProgress::FlushingPersistence(
                    crate::FlushingPersistenceProgress::new(0),
                ));
                StudioPendingPersistence::Drained
            }
            (_, _, Some(count)) => StudioPendingPersistence::Pending {
                count: count as u64,
            },
            (_, _, None) => StudioPendingPersistence::Unknown,
        };

        StageReport {
            outcomes,
            writer_reclaimed: flush_ok,
            persistence,
        }
    }

    pub(in crate::studio::runtime::lifecycle) async fn start_lsp_stop(&self) -> ServiceStopJob {
        let lsp = self.external_runtimes.lsp.clone();
        ensure_service_stop(&self.service_stops.lsp, || {
            ServiceStopJob::spawn(async move { lsp.shutdown().await.map_err(anyhow::Error::from) })
        })
        .await
    }

    pub(in crate::studio::runtime::lifecycle) async fn start_ssh_stop(&self) -> ServiceStopJob {
        let ssh = self.ssh_manager.clone();
        ensure_service_stop(&self.service_stops.ssh, || {
            ServiceStopJob::spawn(async move { ssh.shutdown().await.map_err(anyhow::Error::from) })
        })
        .await
    }

    async fn observe_pending(&self, budget: ShutdownBudget) -> Option<usize> {
        let wait = budget.observe_wait(FACTS_LIMIT).unwrap_or(Duration::ZERO);
        tokio::time::timeout(wait, self.pending_persistence_commits())
            .await
            .ok()
    }

    async fn finalize_shutdown(&self, collector: &mut ShutdownCollector) {
        // 仍有运行中的 writer 时不得关闭数据库，也不得释放实例锁。
        let writer_retained = self
            .agent_facility
            .persistence
            .try_lock()
            .map(|slot| slot.is_some())
            .unwrap_or(true);
        if writer_retained {
            let stage_elapsed_ms = collector.elapsed_ms();
            collector.record_error(
                "persistenceOwnerRetained",
                stage_elapsed_ms,
                &anyhow::anyhow!("persistence writer owner is still retained"),
            );
        }
        let drained = matches!(collector.persistence, StudioPendingPersistence::Drained);
        let can_close = !collector.has_issues()
            && drained
            && collector.writer_reclaimed
            && !writer_retained
            && !collector.expired();
        if can_close {
            let result = run_stage_owned(
                self.clone(),
                collector.budget,
                stage_order::STORE,
                "store",
                None,
                |runtime| async move { runtime.store.close().await },
            )
            .await;
            collector.store_closed = result.is_done();
            if !collector.store_closed {
                collector.record_stage(result);
            }
        }

        let clean = !collector.has_issues()
            && matches!(collector.persistence, StudioPendingPersistence::Drained)
            && collector.store_closed;
        if clean {
            if let Err(error) = self
                .runtime_state
                .apply(StudioRuntimeCommand::FinishShutdown {
                    expected_revision: self.runtime_state.snapshot().revision,
                    at: unix_seconds(),
                })
            {
                // FinishShutdown 失败不可吞：退回 Degraded，不发布 Stopped、不释放锁。
                let stage_elapsed_ms = collector.elapsed_ms();
                collector.record_error("finishShutdown", stage_elapsed_ms, &error.into());
            } else {
                self.shutdown_progress
                    .emit(crate::StudioShutdownProgress::Stopped(Default::default()));
                self.instance_lock.release();
                return;
            }
        }

        // Degraded：不发布 Stopped，也不释放实例锁；进程退出由 OS 语义兜底。
        let message = collector
            .issues
            .first()
            .map(|issue| format!("{}: {}", issue.stage, issue.code))
            .unwrap_or_else(|| "shutdown did not reach a clean state".to_string());
        if let Err(error) = self
            .runtime_state
            .apply(StudioRuntimeCommand::FailShutdown {
                expected_revision: self.runtime_state.snapshot().revision,
                at: unix_seconds(),
                error: crate::StateError {
                    code: "studioShutdownDegraded".to_string(),
                    message,
                    retryable: true,
                },
            })
        {
            let stage_elapsed_ms = collector.elapsed_ms();
            collector.record_error("failShutdown", stage_elapsed_ms, &error.into());
        }
    }

    /// 构造一个阶段的并发分支。
    ///
    /// 分支只返回 `StageOutcome`，不触碰 `ShutdownCollector`，因此多个阶段可以真正并发发起与
    /// 并发等待，而不会被共享聚合器串行化；其结果由 `run_shutdown_stages` 统一按稳定权重聚合。
    /// `limit = None` 表示该阶段在严格路径下必须真实收束（不制造本地墙钟超时）。
    fn stage_branch<Fut>(
        &self,
        budget: ShutdownBudget,
        order: usize,
        stage: &'static str,
        limit: Option<Duration>,
        // 同 `run_stage_owned`：factory 跨 await 持有，需 `Send` 才能让返回的 `BoxFuture` 满足其
        // 跨线程 `Send` 不变量；不做 `unsafe`/`allow`/本地 boxed 规避。
        make: impl FnOnce(StudioRuntime) -> Fut + Send + 'static,
    ) -> StageBranch
    where
        Fut: Future<Output = Result<()>> + Send + 'static,
    {
        run_stage_owned(self.clone(), budget, order, stage, limit, make)
            .map(|outcome| vec![outcome])
            .boxed()
    }
}

//! 统一关机阶段编排与退出期限。
//!
//! 严格关闭（进程内 server）与应用退出共用同一套阶段编排，只按
//! `ShutdownBudget` 与调用契约区分：严格路径要求真实 `Clean`，退出路径接受 `Degraded`
//! 并按剩余期限终止。任何阶段失败都不阻断其余彼此独立的安全清理。
//!
//! 本次退出只在首个调用者处固定一个绝对期限；退出编排运行在真正 owned 的 spawned task 上，
//! 即使等待方超时或全部离开也会被运行时继续 poll 到结束。每个阶段先广播取消（或 abort），
//! 再做有界 join；等待超时只放弃等待，从不 drop 在途的存储 / writer / JoinHandle。

use std::future::Future;
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::Result;
use futures::FutureExt;
use futures::future::BoxFuture;
use futures::stream::{FuturesUnordered, StreamExt};

use crate::studio::{
    StudioRuntime, StudioRuntimeCommand, StudioRuntimeSnapshot, StudioRuntimeStateKind,
    unix_seconds,
};
use crate::{
    StudioPendingPersistence, StudioShutdownIssue, StudioShutdownOutcome, StudioShutdownReport,
};

mod recovery;
mod supervision;

pub(crate) use supervision::ShutdownRun;
use supervision::{
    AdmissionDenied, CleanCommit, CleanCommitError, ExitBlock, FailureCause, RetrySnapshot,
    StageFailure, StageId, StageJob,
};

/// 应用退出的清理预算上限；Dart 传入的 native 剩余时间超过它时按它裁剪。
pub(crate) const EXIT_CLEANUP_BUDGET: Duration = Duration::from_secs(28);

/// 单个外部服务阶段的上限；多个完整超时不得简单相加超出总预算。
const SERVICE_STAGE_LIMIT: Duration = Duration::from_secs(5);

/// 只读事实观测（runtime 快照、持久化计数）的上限：绝不允许在阶段之外无界等待。
const FACTS_LIMIT: Duration = Duration::from_secs(2);

/// 单个诊断日志里最多列出的未收束 Thread 标识数量，避免超长 Thread 列表挤占日志。
const UNRESOLVED_THREAD_LOG_LIMIT: usize = 8;

/// 单向关闭终止闩：一旦进入关闭，本进程余下生命周期内拒绝迟到安装。
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

fn panic_text(payload: &(dyn std::any::Any + Send)) -> String {
    if let Some(message) = payload.downcast_ref::<&str>() {
        (*message).to_string()
    } else if let Some(message) = payload.downcast_ref::<String>() {
        message.clone()
    } else {
        "shutdown orchestration task panicked".to_string()
    }
}

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
    fn observe_wait(&self, limit: Duration) -> Option<Duration> {
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

/// 一次关闭观测到的可靠持久化事实；缺失即为未知，绝不用零掩盖。
#[derive(Debug, Clone, Default)]
struct PersistenceFacts {
    pending: usize,
    save_watermark: Option<u64>,
    owner_id: Option<String>,
    /// 仍有待提交、故障或未收束水位的 Thread 标识。
    unresolved_thread_ids: Vec<String>,
    /// 所有 owner 中最保守（最小）的 admitted/durable 历史水位：全局确认要求每个 owner 都
    /// 至少推进到该值，因此用最小值而不是最大值，绝不用单个 owner 的最大值冒充全局确认。
    history_admitted_min: Option<u64>,
    history_durable_min: Option<u64>,
    fault_generation: Option<u64>,
}

/// 阶段诊断聚合器。
struct ShutdownCollector {
    budget: ShutdownBudget,
    started: Instant,
    issues: Vec<StudioShutdownIssue>,
    persistence: StudioPendingPersistence,
    store_closed: bool,
    /// 持久化 writer 是否已在本次编排中实际 ack 并移交（成功 flush 之后）。
    writer_reclaimed: bool,
    owner_id: Option<String>,
    save_watermark: Option<u64>,
    pending_hint: Option<usize>,
    unresolved_thread_ids: Vec<String>,
    history_admitted_min: Option<u64>,
    history_durable_min: Option<u64>,
    fault_generation: Option<u64>,
}

impl ShutdownCollector {
    fn new(budget: ShutdownBudget) -> Self {
        Self {
            budget,
            started: Instant::now(),
            issues: Vec::new(),
            persistence: StudioPendingPersistence::Unknown,
            store_closed: false,
            writer_reclaimed: false,
            owner_id: None,
            save_watermark: None,
            pending_hint: None,
            unresolved_thread_ids: Vec::new(),
            history_admitted_min: None,
            history_durable_min: None,
            fault_generation: None,
        }
    }

    fn expired(&self) -> bool {
        self.budget.expired()
    }

    fn has_issues(&self) -> bool {
        !self.issues.is_empty()
    }

    fn elapsed_ms(&self) -> u128 {
        self.started.elapsed().as_millis()
    }

    fn pending_label(&self) -> String {
        match self.pending_hint {
            Some(count) => format!("pending:{count}"),
            None => "unknown".to_string(),
        }
    }

    fn unresolved_label(&self) -> String {
        if self.unresolved_thread_ids.is_empty() {
            return "-".to_string();
        }
        let shown = self
            .unresolved_thread_ids
            .iter()
            .take(UNRESOLVED_THREAD_LOG_LIMIT)
            .cloned()
            .collect::<Vec<_>>()
            .join(",");
        let hidden = self
            .unresolved_thread_ids
            .len()
            .saturating_sub(UNRESOLVED_THREAD_LOG_LIMIT);
        if hidden == 0 {
            shown
        } else {
            format!("{shown},+{hidden}")
        }
    }

    fn push(&mut self, issue: StudioShutdownIssue) {
        if !self.issues.contains(&issue) {
            self.issues.push(issue);
        }
    }

    /// 播种调用方在进入编排前已经确定的失败（桥端 / Dart 侧订阅、更新取消未确认）。
    ///
    /// 它们与 runtime 自身阶段共享同一 `issues`，因此直接决定 `finalize_shutdown` 的成功
    /// 前置条件：只要存在任何一条，收束阶段就不会判定 `Clean`，也不会发布 `Stopped` 或释放
    /// 实例锁。诊断保留真实 `code` / `correlation_id`，不伪造 runtime 阶段的收束事实。
    fn seed_external_issues(&mut self, issues: Vec<StudioShutdownIssue>) {
        for issue in issues {
            tracing::error!(
                pid = std::process::id(),
                stage = %issue.stage,
                code = %issue.code,
                correlation_id = %issue.correlation_id,
                retryable = issue.retryable,
                elapsed_ms = self.elapsed_ms(),
                detail = %issue.message,
                "Studio shutdown precondition failed before runtime finalization"
            );
            self.push(issue);
        }
    }

    /// 记录一个阶段/子步骤的真实失败。
    ///
    /// `stage_elapsed_ms` 是该阶段自身的耗时（非阶段调用点传总耗时），与总 `elapsed_ms` 一并输出，
    /// 便于从日志确认独立阶段确实并发收束而不是被逐个串行等待。
    fn record_error(&mut self, stage: &str, stage_elapsed_ms: u128, error: &anyhow::Error) {
        // These concrete helpers retain every child error, not just Error::source's first cause.
        if let Some(titles) = error.downcast_ref::<super::super::thread_title::TitleStopFailure>() {
            for (_, error) in &titles.failures {
                self.record_error(stage, stage_elapsed_ms, error);
            }
            return;
        }
        if let Some(catalog) =
            error.downcast_ref::<super::super::model_catalog::CatalogStopFailure>()
        {
            if let Some(error) = &catalog.close {
                self.record_error(stage, stage_elapsed_ms, error);
            }
            for (_, error) in &catalog.probes {
                self.record_error(stage, stage_elapsed_ms, error);
            }
            return;
        }
        if let Some(framework) = error.downcast_ref::<super::framework::FrameworkShutdownFailure>()
        {
            if let Some(error) = &framework.archive {
                self.record_error(stage, stage_elapsed_ms, error);
            }
            for (_, error) in &framework.threads {
                self.record_error(stage, stage_elapsed_ms, error);
            }
            if let Some(error) = &framework.observation {
                self.record_error(stage, stage_elapsed_ms, error);
            }
            return;
        }
        if let Some(persistence) =
            error.downcast_ref::<super::framework::PersistenceShutdownFailure>()
        {
            use super::framework::PersistenceShutdownFailure;
            let (PersistenceShutdownFailure::Drain(error)
            | PersistenceShutdownFailure::Writers(error)
            | PersistenceShutdownFailure::Flush(error)
            | PersistenceShutdownFailure::Shutdown(error)
            | PersistenceShutdownFailure::History(error)) = persistence;
            self.record_error(stage, stage_elapsed_ms, error);
            return;
        }
        if let Some(join) = error.downcast_ref::<tokio::task::JoinError>() {
            self.record_join_error(stage, stage_elapsed_ms, join);
            return;
        }
        let mapped = if let Some(bot) = error.downcast_ref::<crate::bots::FeishuError>() {
            bot.studio_error()
        } else {
            crate::error_mapping::studio_error_from_anyhow_ref(error)
        };
        // Diagnostics keep only redacted, structure-level facts: the shared `StudioError` message,
        // `std::io` kind/OS code and the database failure category/code. The raw source chain can
        // embed prompt bodies or credentials, so its message bodies are never written verbatim;
        // the backtrace is force-captured so the stack is a real fact rather than an `anyhow`
        // backtrace that may be disabled.
        tracing::error!(
            pid = std::process::id(),
            stage,
            code = mapped.code.label(),
            correlation_id = %mapped.correlation_id,
            retryable = mapped.retryable,
            pending = %self.pending_label(),
            stage_elapsed_ms,
            elapsed_ms = self.elapsed_ms(),
            owner_id = self.owner_id.as_deref().unwrap_or("-"),
            save_watermark = self.save_watermark,
            history_admitted_min = self.history_admitted_min,
            history_durable_min = self.history_durable_min,
            fault_generation = self.fault_generation,
            unresolved_threads = %self.unresolved_label(),
            error_bytes = error.to_string().len(),
            error_chain = %redacted_chain(error),
            backtrace = %std::backtrace::Backtrace::force_capture(),
            detail = %mapped.message,
            "Studio shutdown stage failed"
        );
        if let Some(reads) =
            error.downcast_ref::<super::super::read_scopes::ReadScopesCloseFailure>()
        {
            // The shared scope owner retains every typed issue. Include each original diagnostic
            // before finalization instead of replacing multiple unresolved queries with one label.
            for issue in &reads.scope_issues {
                self.push(issue.diagnostic.clone());
            }
            for failure in &reads.call_failures {
                self.push(StudioShutdownIssue {
                    stage: stage.to_string(),
                    code: "joinError".into(),
                    message: format!("Detail read {} did not join successfully", failure.id),
                    retryable: false,
                    correlation_id: pl_protocol::studio::StudioError::internal().correlation_id,
                });
            }
        }
        if let Some(commands) =
            error.downcast_ref::<super::super::draft_commands::DraftCommandsCloseFailure>()
        {
            for issue in &commands.issues {
                self.push(issue.diagnostic.clone());
            }
            if let Some(source) = &commands.source {
                self.record_error(stage, stage_elapsed_ms, source);
            }
        }
        self.push(StudioShutdownIssue {
            stage: stage.to_string(),
            code: mapped.code.label().to_string(),
            message: mapped.message,
            retryable: mapped.retryable,
            correlation_id: mapped.correlation_id,
        });
    }

    fn record_join_error(
        &mut self,
        stage: &str,
        stage_elapsed_ms: u128,
        error: &tokio::task::JoinError,
    ) {
        let message = if error.is_panic() {
            format!("shutdown stage task panicked: {error}")
        } else {
            format!("shutdown stage task failed: {error}")
        };
        self.record_error(stage, stage_elapsed_ms, &anyhow::anyhow!(message));
    }

    /// 记录外部服务关闭任务的真实失败，保留底层原因链（不吞错、不伪成功）。
    fn record_stage_failure(
        &mut self,
        stage: &str,
        stage_elapsed_ms: u128,
        failure: &StageFailure,
    ) {
        let diagnostics = failure.diagnostics.get_or_init(|| {
            // Cache the failure's complete diagnostics independently of issues already present
            // in this collector (e.g. the same scope issue observed through another owner).
            let existing = std::mem::take(&mut self.issues);
            match &failure.cause {
                FailureCause::Failed(error) => self.record_error(stage, stage_elapsed_ms, error),
                FailureCause::Panicked(join) => {
                    self.record_join_error(stage, stage_elapsed_ms, join)
                }
            }
            std::mem::replace(&mut self.issues, existing)
        });
        for diagnostic in diagnostics {
            self.push(diagnostic.clone());
        }
    }

    fn record_exit_block(&mut self, stage: &str, stage_elapsed_ms: u128, block: ExitBlock) {
        self.seed_external_issues(block.issues);
        if block.expired {
            self.record_skipped(stage, stage_elapsed_ms);
        }
    }

    fn record_admission_denied(&mut self, stage: &str, elapsed: u128, denied: AdmissionDenied) {
        match denied {
            AdmissionDenied::Exit(block) => self.record_exit_block(stage, elapsed, block),
            AdmissionDenied::Finalized => self.record_error(
                stage,
                elapsed,
                &pl_protocol::studio::StudioError::new(
                    pl_protocol::studio::StudioErrorCode::Cancelled,
                    "Studio shutdown was already finalized",
                    false,
                )
                .into(),
            ),
        }
    }

    fn record_timeout(&mut self, stage: &str, stage_elapsed_ms: u128) {
        let mapped = pl_protocol::studio::StudioError::new(
            pl_protocol::studio::StudioErrorCode::Busy,
            "shutdown stage exceeded its time budget",
            true,
        );
        tracing::error!(
            pid = std::process::id(),
            stage,
            code = "timeout",
            correlation_id = %mapped.correlation_id,
            pending = %self.pending_label(),
            stage_elapsed_ms,
            elapsed_ms = self.elapsed_ms(),
            owner_id = self.owner_id.as_deref().unwrap_or("-"),
            save_watermark = self.save_watermark,
            history_admitted_min = self.history_admitted_min,
            history_durable_min = self.history_durable_min,
            fault_generation = self.fault_generation,
            unresolved_threads = %self.unresolved_label(),
            "Studio shutdown stage timed out; owner/handle retained"
        );
        self.push(StudioShutdownIssue {
            stage: stage.to_string(),
            code: "timeout".to_string(),
            message: mapped.message,
            retryable: true,
            correlation_id: mapped.correlation_id,
        });
    }

    fn record_skipped(&mut self, stage: &str, stage_elapsed_ms: u128) {
        let mapped = pl_protocol::studio::StudioError::new(
            pl_protocol::studio::StudioErrorCode::Busy,
            "shutdown budget elapsed before this stage could be joined",
            true,
        );
        tracing::warn!(
            pid = std::process::id(),
            stage,
            code = "deadlineExceeded",
            correlation_id = %mapped.correlation_id,
            stage_elapsed_ms,
            elapsed_ms = self.elapsed_ms(),
            "Studio shutdown stage not joined within budget; cancellation already broadcast"
        );
        self.push(StudioShutdownIssue {
            stage: stage.to_string(),
            code: "deadlineExceeded".to_string(),
            message: mapped.message,
            retryable: true,
            correlation_id: mapped.correlation_id,
        });
    }

    /// 记录一个并发阶段的真实结果并统一聚合。
    ///
    /// 阶段在各自分支内只产生 `StageOutcome`，回到编排线程后按固定顺序聚合：这样多个独立阶段
    /// 可以真正并发发起与并发等待，而不会被共享的 `ShutdownCollector` 串行化，报告顺序仍稳定。
    fn record_stage(&mut self, outcome: StageOutcome) {
        let StageOutcome {
            id,
            status,
            elapsed,
        } = outcome;
        let stage = id.label();
        let stage_elapsed_ms = elapsed.as_millis();
        match status {
            StageStatus::Done => {
                tracing::info!(
                    pid = std::process::id(),
                    stage,
                    resource = "runtime",
                    stage_elapsed_ms,
                    elapsed_ms = self.elapsed_ms(),
                    "Studio shutdown stage completed"
                );
            }
            StageStatus::Failed(failure) => {
                self.record_stage_failure(stage, stage_elapsed_ms, &failure);
            }
            StageStatus::TimedOut => self.record_timeout(stage, stage_elapsed_ms),
            StageStatus::Skipped => self.record_skipped(stage, stage_elapsed_ms),
            StageStatus::NotAdmitted(denied) => {
                self.record_admission_denied(stage, stage_elapsed_ms, denied);
            }
        }
    }

    fn report(self) -> StudioShutdownReport {
        let clean = !self.has_issues()
            && matches!(self.persistence, StudioPendingPersistence::Drained)
            && self.store_closed;
        StudioShutdownReport {
            outcome: if clean {
                StudioShutdownOutcome::Clean
            } else {
                StudioShutdownOutcome::Degraded
            },
            issues: self.issues,
            persistence: self.persistence,
        }
    }
}

/// 已脱敏的错误来源链摘要。
///
/// 关机诊断不得写入正文或凭据，但也不能只留一个 generic message 或纯字节数——仅凭字节数无法
/// 定位 SQLite / OS 失败原因。这里保留**结构性的事实**：typed `StudioError` 的稳定诊断码与
/// 已脱敏 message、`std::io::Error` 的 kind 与原始 OS 错误码、`sea_orm::DbErr` 的失败分类与
/// 可公开的 SQL 错误码；未知类型只保留规模。所有分支都不写正文或凭据。
fn redacted_chain(error: &anyhow::Error) -> String {
    let mut parts = Vec::new();
    for cause in error.chain() {
        if let Some(studio) = cause.downcast_ref::<pl_protocol::studio::StudioError>() {
            parts.push(format!("[{}] {}", studio.code.label(), studio.message));
        } else if let Some(io) = cause.downcast_ref::<std::io::Error>() {
            let os_code = io
                .raw_os_error()
                .map_or_else(|| "-".to_string(), |code| code.to_string());
            parts.push(format!("io/{:?}#{}", io.kind(), os_code));
        } else if let Some(db) = cause.downcast_ref::<sea_orm::DbErr>() {
            parts.push(db_error_summary(db));
        } else {
            // 未知 cause：保留规模而不写内容，避免把可能的正文或凭据带入日志。
            parts.push(format!("<unclassified {} bytes>", cause.to_string().len()));
        }
    }
    parts.join(" <- ")
}

/// Safe, structure-only summary of a SeaORM database error (no SQL or row content).
fn db_error_summary(error: &sea_orm::DbErr) -> String {
    use std::ops::Deref;

    use sea_orm::{DbErr, RuntimeErr};

    let kind = match error {
        DbErr::Conn(_) => "connection",
        DbErr::Exec(_) => "exec",
        DbErr::Query(_) => "query",
        _ => "other",
    };
    // The backend error code is a stable, non-sensitive identifier (e.g. SQLite/Postgres code).
    let code = if let DbErr::Query(RuntimeErr::SqlxError(error))
    | DbErr::Exec(RuntimeErr::SqlxError(error)) = error
        && let sea_orm::sqlx::Error::Database(database) = error.deref()
    {
        database.code().map(|code| code.into_owned())
    } else {
        None
    };
    match code {
        Some(code) => format!("db/{kind}#{code}"),
        None => format!("db/{kind}"),
    }
}

/// 本次编排要 join 的服务关闭共享句柄（按需从常驻槽位 ensure）。
///
/// 只含与 SSH transport 无依赖的远端服务：MCP 与 LSP 的 stop 可并发发起。SSH transport 承载
/// 远端 MCP/LSP/工具的通信，必须在这些依赖收束之后才请求回收，因此不在本结构内，而在
/// `run_shutdown_stages` 的依赖闸门之后从同一 ShutdownRun 阶段槽 ensure。
struct ServiceStops {
    mcp: Result<StageJob, AdmissionDenied>,
    lsp: Result<StageJob, AdmissionDenied>,
}

/// 一个并发阶段的真实结果。
///
/// 阶段在各自分支内产生本结构，回到编排线程后按 `order` 统一聚合。它不持有
/// `ShutdownCollector`，因此多个独立阶段可以真正并发发起与并发等待，而不是被一把共享锁串行化。
/// `elapsed` 是该阶段自身的收束耗时，用于日志确认独立阶段确实并发完成。
struct StageOutcome {
    id: StageId,
    status: StageStatus,
    elapsed: Duration,
}

impl StageOutcome {
    /// 该阶段是否真实确认收束（用于写入链的成功判定）。
    fn is_done(&self) -> bool {
        matches!(&self.status, StageStatus::Done)
    }
}

/// 并发阶段的终态；失败原因保留 typed / JoinError 事实，留待统一聚合时脱敏记录。
enum StageStatus {
    /// 阶段真实完成并确认收束。
    Done,
    /// 原业务错误或 JoinError，共享同一次真实完成。
    Failed(Arc<StageFailure>),
    /// 阶段准入被拒绝，factory 尚未执行。
    NotAdmitted(AdmissionDenied),
    /// 阶段未在上限内收束；只放弃等待，owner/handle 仍被保留。
    TimedOut,
    /// 共享预算已耗尽，取消已广播但未 join。
    Skipped,
}

/// 一次并发阶段推进的汇总结果；回到 `execute_shutdown` 后再写入单一 collector。
///
/// 阶段本身不直接修改 collector，因此它们可以真正并发；这里的字段与 issue 一并由编排线程按
/// 稳定顺序聚合，保证 writer ack 与持久化判定仍由同一 finalize 前置条件决定。
struct StageReport {
    outcomes: Vec<StageOutcome>,
    writer_reclaimed: bool,
    persistence: StudioPendingPersistence,
}

/// 一个独立阶段分支的并发句柄：完成后返回它贡献的阶段结果。
type StageBranch = BoxFuture<'static, Vec<StageOutcome>>;

/// 并发 poll 一组阶段分支直至全部收束，收集它们贡献的阶段结果。
///
/// `FuturesUnordered` 首次 poll 时会把全部已入队的分支一起推进，因此同一依赖层内的阶段在同一
/// 时刻发起，并共享同一首次绝对期限的剩余预算。
async fn drain_stage_branches(branches: &mut FuturesUnordered<StageBranch>) -> Vec<StageOutcome> {
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
async fn run_stage_owned<Fut>(
    runtime: StudioRuntime,
    budget: ShutdownBudget,
    id: StageId,
    limit: Option<Duration>,
    retries: RetrySnapshot,
    // factory 被持有在 async fn 状态里跨 await，必须 `Send`，否则整个 owned 阶段 future 不是
    // `Send`，无法放进要求跨线程的 `BoxFuture`（`StageBranch`）与 `tokio::spawn`。
    make: impl FnOnce(StudioRuntime) -> Fut + Send + 'static,
) -> StageOutcome
where
    Fut: Future<Output = Result<()>> + Send + 'static,
{
    let coordinator = runtime.shutdown_run.clone();
    let job = coordinator.ensure_stage(id, &retries, move || make(runtime));
    observe_stage(budget, id, job, limit).await
}

/// 并发观测原协调器持有的阶段 job；消费同一次真实 typed 结果。
///
/// 多个服务的 join 由调用方用 `FuturesUnordered` 并发 poll，因此它们的等待共享同一首次绝对期限
/// 的剩余预算，一个服务的挂起不占用其他服务的收束预算。超时 / 预算耗尽只放弃等待：共享 completion
/// 与 owned task 由原协调器常驻持有，后续严格重试只按入场资格决定是否重试已确认失败。
async fn observe_stage(
    budget: ShutdownBudget,
    id: StageId,
    job: Result<StageJob, AdmissionDenied>,
    limit: Option<Duration>,
) -> StageOutcome {
    tracing::info!(
        pid = std::process::id(),
        stage = id.label(),
        resource = match id {
            StageId::McpStop | StageId::LspStop | StageId::Ssh => "service",
            _ => "runtime",
        },
        "Studio shutdown stage started"
    );
    let started = Instant::now();
    let status = match job {
        Err(denied) => StageStatus::NotAdmitted(denied),
        Ok(job) => {
            if let Some(result) = job.observed_result() {
                match result {
                    Ok(()) => StageStatus::Done,
                    Err(failure) => StageStatus::Failed(failure),
                }
            } else {
                match budget.stage_policy(limit) {
                    StagePolicy::Skipped => StageStatus::Skipped,
                    StagePolicy::Bounded(limit) => {
                        match tokio::time::timeout(limit, job.join()).await {
                            Ok(Ok(())) => StageStatus::Done,
                            Ok(Err(failure)) => StageStatus::Failed(failure),
                            Err(_) => StageStatus::TimedOut,
                        }
                    }
                    StagePolicy::Unbounded => match job.join().await {
                        Ok(()) => StageStatus::Done,
                        Err(failure) => StageStatus::Failed(failure),
                    },
                }
            }
        }
    };
    StageOutcome {
        id,
        status,
        elapsed: started.elapsed(),
    }
}

fn archive_stage_failure(id: StageId, failure: &StageFailure) {
    if failure.diagnostics.get().is_none() {
        let mut collector = ShutdownCollector::new(ShutdownBudget::unbounded());
        collector.record_stage_failure(id.label(), 0, failure);
    }
}

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
        let retries = self.shutdown_run.retry_snapshot();
        let report = self
            .execute_shutdown(ShutdownBudget::unbounded(), retries)
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
        self.models_source.seal();
        self.configuration_source.seal();
        self.mcp_source.seal();
        self.lsp_source.seal();
        self.skills_source.seal();
        self.profiles_source.seal();
        self.templates_source.seal();
        self.modes_source.seal();
        self.usage_source.seal();
        self.statistics_source.seal();
        self.updates_source.seal();
        self.startup_source.seal();
        self.recovery_source.seal();
        self.persistence_source.seal();
        self.persistence_queue_source.seal();
        self.remote_directory_source.seal();
        self.bots_source.seal();
        self.workspace_source.seal();
        self.read_scopes.seal();
        self.read_calls.seal();
        self.draft_commands.seal();
        let requested = Duration::from_millis(u64::from(remaining_ms));
        let deadline = self
            .shutdown_run
            .start_exit(self, requested, external_issues);
        match self.shutdown_run.wait(Some(deadline)).await {
            Some(report) => report,
            None => self.shutdown_run.deadline_report("deadline"),
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
    /// 它绝不启动 MCP/LSP/SSH 的真正 stop、绝不 join、绝不关闭数据库 / 释放实例锁，也不发布
    /// `Stopped`——这些仍由随后的同一编排完成，早期 arm 不会被误认为最终终态。早期观测到的诊断
    /// 被写入常驻槽位，由 `execute_shutdown` 就地播种为成功前置条件，既不吞错也不伪成功。
    ///
    /// 本步有界：独立 owner 的取消广播各自带锁上限，不做任何可能无界阻塞的 join；状态观测与
    /// 推进只持有无 await 的短临界区，绝不在任何锁上无界等待。
    pub async fn fence_exit_admission(&self) -> Vec<StudioShutdownIssue> {
        self.shutdown_latch.arm();
        self.models_source.seal();
        self.configuration_source.seal();
        self.mcp_source.seal();
        self.lsp_source.seal();
        self.skills_source.seal();
        self.profiles_source.seal();
        self.templates_source.seal();
        self.modes_source.seal();
        self.usage_source.seal();
        self.statistics_source.seal();
        self.updates_source.seal();
        self.startup_source.seal();
        self.recovery_source.seal();
        self.persistence_source.seal();
        self.persistence_queue_source.seal();
        self.remote_directory_source.seal();
        self.bots_source.seal();
        self.workspace_source.seal();
        self.read_scopes.seal();
        self.read_calls.seal();
        self.draft_commands.seal();
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
                    backtrace = %std::backtrace::Backtrace::force_capture(),
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
    async fn execute_shutdown(
        &self,
        budget: ShutdownBudget,
        retries: RetrySnapshot,
    ) -> StudioShutdownReport {
        let mut collector = ShutdownCollector::new(budget);

        // 只读持久化事实先于快照观测，让后续任何早期失败的诊断都带真实 owner / 水位。
        self.capture_persistence_facts(&mut collector).await;
        let current = self.observe_snapshot(&mut collector).await;

        // 播种调用方（Dart / bridge）在进入编排前已经确定的失败，作为这次关闭的成功前置条件；
        // 放在事实观测之后，使诊断带上真实 owner 与保存水位。
        collector.seed_external_issues(self.shutdown_run.exit_issues());
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
        self.models_source.seal();
        self.configuration_source.seal();
        self.mcp_source.seal();
        self.lsp_source.seal();
        self.skills_source.seal();
        self.profiles_source.seal();
        self.templates_source.seal();
        self.modes_source.seal();
        self.usage_source.seal();
        self.statistics_source.seal();
        self.updates_source.seal();
        self.startup_source.seal();
        self.recovery_source.seal();
        self.persistence_source.seal();
        self.persistence_queue_source.seal();
        self.remote_directory_source.seal();
        self.bots_source.seal();
        self.workspace_source.seal();
        self.read_scopes.seal();
        self.read_calls.seal();
        self.draft_commands.seal();

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
        let services = self.ensure_service_stops();

        let stages = self
            .run_shutdown_stages(budget, collector.pending_hint, &services, retries)
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
    /// 背景 watcher 用 abort 即刻停摆；title 任务用一次性取消信号。此步不做任何可能无界阻塞的
    /// 服务 join，保证所有独立资源先收到取消。
    async fn broadcast_cancel(&self) {
        use super::super::background_task;
        background_task::signal(&self.settings_refresh).await;
        background_task::signal(&self.recovery_task).await;
        background_task::signal(&self.external_runtimes.mcp_config_watcher).await;
        background_task::signal(&self.external_runtimes.mcp_health_watcher).await;
        background_task::signal(&self.external_runtimes.lsp_state_watcher).await;
        background_task::signal(&self.persistence_observer).await;
        background_task::signal(&self.profiles_forwarder).await;
        // 统计进度 follower 与其它独立 owner 一样，先广播取消（打断 watch 等待），真正的
        // 有界 join 在独立资源组完成。
        background_task::signal(&self.statistics_follower).await;
        self.title_tasks.signal_cancel().await;
        // ACP 认证操作只接收取消信号：真正的 protocol/进程收束与终态由该 owner 自己的
        // supervisor 完成，随后在独立阶段有界 join，避免提前释放仍存活的进程。
        self.acp_auth.signal_cancel();
        // 官方 server 准备同样只接收取消信号：下载库、校验/解压阻塞任务与发布提交的收束与终态
        // 由该 owner 自己的 supervisor 完成，随后在独立阶段有界 join。
        self.acp_install.signal_cancel();
        // 活动 Turn / 模型 / 工具：通过既有的纯取消入口取消每个驻留 Thread 当前执行代次。
        // 这里只发信号，不 join、也不 close——真正的收束仍由后续唯一 `agentFramework` 阶段完成，
        // 因此不会重复 close，也绝不提前释放 writer 或实例锁。先前已封闭准入，取消只是加速在途
        // 执行的退出，满足「先封闭准入并广播取消（含 Turn）再 join」。
        for (_, handle) in self.threads.observed_threads() {
            handle.interrupt();
        }
    }

    /// 确保与 SSH transport 无依赖的远端服务（MCP、LSP）各自唯一一次的真实 stop 工作已在常驻
    /// 槽位启动。SSH transport 依赖它们，改由 `run_shutdown_stages` 的依赖闸门之后单独 ensure。
    ///
    /// 每个服务只调用一次 `shutdown`（MCP worker 的首个 `Shutdown` 即退出）；job 与 completion
    /// 常驻于 runtime 槽位，阶段只 join 同一共享完成句柄。预算耗尽或超时只放弃等待，owner 与
    /// 句柄仍被 runtime 保留；严格重试再次 join 同一 job，不重启 stop。
    fn ensure_service_stops(&self) -> ServiceStops {
        // MCP 与 LSP 是彼此独立的远端服务，stop 并发发起：各自的 owned 关闭 job 在同一时刻
        // spawn，而不是等前一个服务的 stop 启动后才轮到下一个。每个服务仍只启动一次（常驻槽位
        // 保证幂等）。SSH transport 不是与它们独立的资源：它承载远端 MCP/LSP/工具的通信，必须在
        // 这些依赖的停止请求与结果处理之后才回收，因此在依赖闸门之后单独 ensure（见
        // `run_shutdown_stages`）。
        let mcp = self.external_runtimes.mcp.clone();
        let lsp = self.external_runtimes.lsp.clone();
        let mcp = self.shutdown_run.ensure_stage(
            StageId::McpStop,
            &RetrySnapshot::default(),
            move || async move { mcp.shutdown().await.map_err(anyhow::Error::from) },
        );
        let lsp = self.shutdown_run.ensure_stage(
            StageId::LspStop,
            &RetrySnapshot::default(),
            move || async move { lsp.shutdown().await.map_err(anyhow::Error::from) },
        );
        ServiceStops { mcp, lsp }
    }

    async fn run_shutdown_stages(
        &self,
        budget: ShutdownBudget,
        pending_before: Option<usize>,
        services: &ServiceStops,
        retries: RetrySnapshot,
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

        // 写入生产者：它们是可靠保存的前提，只有全部真实停止 ACK 后才可 drain 并停止 writer。
        // 失败或有界超时保留原生产者及 writer，独立资源仍继续安全清理。生产者阶段彼此独立，
        // 因此并发发起、并发等待，不会用前一个的等待耗尽后续阶段预算。
        let mut producers: FuturesUnordered<StageBranch> = FuturesUnordered::new();
        producers.push(self.stage_branch(
            budget,
            StageId::DetailReads,
            None,
            retries.clone(),
            |runtime| async move { runtime.close_detail_reads().await },
        ));
        // Bot 应答 owner 在收束前持 store.history（bots_recovery::bot_input_fact），因此它同样是
        // 历史读取生产者：必须与其它生产者一起真实停止，写入链才允许进入 persistence 并封印历史
        // 关闭。它与远端工具无依赖，故不进入 SSH 闸门的判据（见下方 producers_settled 的计算）。
        producers.push(self.stage_branch(
            budget,
            StageId::Bots,
            Some(SERVICE_STAGE_LIMIT),
            retries.clone(),
            |runtime| async move { runtime.bots.shutdown().await.map_err(anyhow::Error::new) },
        ));
        producers.push(self.stage_branch(
            budget,
            StageId::ModelCatalog,
            Some(SERVICE_STAGE_LIMIT),
            retries.clone(),
            |runtime| async move { runtime.stop_model_catalog_probes().await },
        ));
        producers.push(self.stage_branch(
            budget,
            StageId::Recovery,
            Some(SERVICE_STAGE_LIMIT),
            retries.clone(),
            |runtime| async move { runtime.stop_recovery_scan().await },
        ));
        producers.push(self.stage_branch(
            budget,
            StageId::ModelRefresh,
            Some(SERVICE_STAGE_LIMIT),
            retries.clone(),
            |runtime| async move { runtime.stop_model_refresh().await },
        ));
        producers.push(self.stage_branch(
            budget,
            StageId::Title,
            Some(SERVICE_STAGE_LIMIT),
            retries.clone(),
            |runtime| async move { runtime.title_tasks.cancel_and_wait().await },
        ));
        // Thread/审计收束是可靠的保存前提：严格路径真实等待，退出路径仍受同一期限裁剪。
        producers.push(self.stage_branch(
            budget,
            StageId::AgentFramework,
            None,
            retries.clone(),
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
            StageId::McpStartupReconcile,
            Some(SERVICE_STAGE_LIMIT),
            retries.clone(),
            |runtime| async move { runtime.stop_mcp_config_watcher().await },
        ));
        remote_dependents.push(self.stage_branch(
            budget,
            StageId::McpHealth,
            Some(SERVICE_STAGE_LIMIT),
            retries.clone(),
            |runtime| async move { runtime.stop_mcp_health_watcher().await },
        ));
        remote_dependents.push(self.stage_branch(
            budget,
            StageId::ToolRefresh,
            Some(SERVICE_STAGE_LIMIT),
            retries.clone(),
            |runtime| async move { runtime.stop_tool_refresh().await },
        ));
        // ACP 认证操作持有官方 server 进程与管道；取消已广播，这里是有界 join。超时保留 owner
        // 与 join 句柄，令 `Clean` 不可达并可重试，绝不伪报已回收。
        remote_dependents.push(self.stage_branch(
            budget,
            StageId::AcpAuth,
            Some(SERVICE_STAGE_LIMIT),
            retries.clone(),
            |runtime| async move { runtime.acp_auth.cancel_and_join().await },
        ));
        // ACP server 准备持有下载、校验/解压阻塞任务、文件锁与发布提交；取消已广播，这里是有界
        // join。超时保留 owner 与 join 句柄，令 `Clean` 不可达并可重试。
        remote_dependents.push(self.stage_branch(
            budget,
            StageId::AcpInstall,
            Some(SERVICE_STAGE_LIMIT),
            retries.clone(),
            |runtime| async move { runtime.acp_install.cancel_and_join().await },
        ));

        // MCP/LSP 只 join `ensure_service_stops` 已启动的那一次关闭，消费真实 typed 结果；
        // 只有确认回收才发布 `stopped`，失败绝不伪成功。job 常驻 runtime，超时不丢句柄。
        // stop 与随后的 `stopped` 发布是同一服务内的有向顺序，整体仍与其他独立资源并发。
        let mcp_job = services.mcp.clone();
        let mcp_runtime = self.clone();
        let mcp_retries = retries.clone();
        remote_dependents.push(
            async move {
                let stop =
                    observe_stage(budget, StageId::McpStop, mcp_job, Some(SERVICE_STAGE_LIMIT))
                        .await;
                let acked = stop.is_done();
                let mut outcomes = vec![stop];
                if acked {
                    outcomes.push(
                        run_stage_owned(
                            mcp_runtime,
                            budget,
                            StageId::McpStopped,
                            Some(SERVICE_STAGE_LIMIT),
                            mcp_retries,
                            |runtime| async move { runtime.publish_mcp_stopped().await },
                        )
                        .await,
                    );
                }
                outcomes
            }
            .boxed(),
        );
        let lsp_job = services.lsp.clone();
        let lsp_runtime = self.clone();
        let lsp_retries = retries.clone();
        remote_dependents.push(
            async move {
                let stop = observe_stage(
                    budget,
                    StageId::LspStop,
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
                            StageId::LspStopped,
                            Some(SERVICE_STAGE_LIMIT),
                            lsp_retries,
                            |runtime| async move { runtime.external_runtimes.lsp_state.stopped().await },
                        )
                        .await,
                    );
                }
                outcomes
            }
            .boxed(),
        );

        // 与 SSH transport 无依赖的本地资源：本地 LSP 状态 watcher、持久化 observer 与 Agent
        // Profiles 转发。它们不被 SSH 依赖闸门等待，只与写入链、远端依赖组并发收束（各自有界），
        // 不拖后 SSH 回收。
        let mut independent: FuturesUnordered<StageBranch> = FuturesUnordered::new();
        independent.push(self.stage_branch(
            budget,
            StageId::LspState,
            Some(SERVICE_STAGE_LIMIT),
            retries.clone(),
            |runtime| async move { runtime.stop_lsp_state_watcher().await },
        ));
        independent.push(self.stage_branch(
            budget,
            StageId::PersistenceObserver,
            Some(SERVICE_STAGE_LIMIT),
            retries.clone(),
            |runtime| async move {
                super::super::background_task::stop(&runtime.persistence_observer)
                    .await
                    .map_err(anyhow::Error::new)
            },
        ));
        // Agent Profiles 配置 watch 转发同样由 runtime 拥有：正常退出与失败路径都必须在同一首次
        // 期限内有界地 signal + join，失败 / 超时经 collector 记为该次退出的 issue，令 `Clean`
        // 不可达并保留 owner（常驻槽位超时不丢句柄），不得只靠 `dispose_startup` 或 slot Drop 收束。
        independent.push(self.stage_branch(
            budget,
            StageId::AgentProfiles,
            Some(SERVICE_STAGE_LIMIT),
            retries.clone(),
            |runtime| async move { runtime.stop_agent_profiles_forwarder().await },
        ));

        // 统计进度 follower 同样由 runtime 拥有：正常退出与失败路径都必须在同一首次期限内有界
        // signal + join，失败 / 超时经 collector 记为该次退出的 issue，令 `Clean` 不可达并保留
        // owner（常驻槽位超时不丢句柄）；不得只靠 `dispose_startup` 或 slot Drop 收束。
        independent.push(self.stage_branch(
            budget,
            StageId::StatisticsFollower,
            Some(SERVICE_STAGE_LIMIT),
            retries.clone(),
            |runtime| async move { runtime.stop_statistics_follower().await },
        ));

        independent.push(self.stage_branch(
            budget,
            StageId::Bots,
            Some(SERVICE_STAGE_LIMIT),
            retries.clone(),
            |runtime| async move { runtime.bots.shutdown().await.map_err(anyhow::Error::new) },
        ));
        // 写入生产者依赖的共享完成信号：写入链只有在生产者真实停止 ACK 后继续持久化；SSH 依赖同一份
        // 生产者事实——远端工具由 Turn / Agent 等生产者驱动，它们未收束时不得先切断 SSH 通信——
        // 但 SSH 只等这条依赖边，不等与它无关的持久化 / 数据库提交。信号载荷刻意区分两件事实：
        // 收到信号 = 依赖已结束观测（含失败 / 有界超时 / 预算耗尽），载荷 `bool` = 实际是否全部
        // 成功 ACK。信号不携带 outcome，避免复制不可 Clone 的诊断，也不引入第二份事实源：写入链
        // 仍是生产者 outcome 的唯一持有与记录方。
        let (producers_settled_tx, producers_settled_rx) = tokio::sync::oneshot::channel::<bool>();

        // SSH transport 关闭的依赖闸门：并发等待全部远端依赖（MCP/LSP stop 链、工具刷新、
        // MCP watcher）的停止请求与结果处理，以及写入生产者的收束观测，之后才在常驻槽位请求
        // SSH 回收；仍只 join 已启动的那一次 owned task，真实结果不被 `let _ =` 吞掉。依赖等待与
        // 真正的 SSH stop 分别计时：依赖等待只做闸门，SSH stop 的耗时由 `observe_stage` 的
        // `elapsed` 单独给出。依赖超时 / 失败 / 预算耗尽都不拦下回收请求（有界降级）：
        // 原协调器 ensure 照常调用，只是 `observe_stage` 可能在预算耗尽时返回
        // `Skipped`，owner 仍由常驻槽位保留、可重试。闸门只记录事实，不据此伪报成功。
        let ssh_runtime = self.clone();
        let ssh_branch = async move {
            let dependents_started = Instant::now();
            let (mut outcomes, producers_signal) = futures::join!(
                drain_stage_branches(&mut remote_dependents),
                producers_settled_rx,
            );
            let dependents_elapsed_ms = dependents_started.elapsed().as_millis() as u64;
            // 区分「依赖已结束观测」与「实际全部成功 ACK」：前者只要信号送达即成立，后者只由载荷
            // `true` 表达。任一为假都只作为日志事实，既不放行伪成功，也不阻止照样请求 SSH 回收。
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
            let ssh = ssh_runtime.ssh_manager.clone();
            let remote_runtime = ssh_runtime.clone();
            let ssh_job = ssh_runtime.shutdown_run.ensure_stage(
                StageId::Ssh,
                &RetrySnapshot::default(),
                move || async move {
                    // DetailReads has been observed before this dependency gate. Accepted late
                    // browses registered their original cursors before returning/being discarded.
                    let cursors = remote_runtime
                        .remote_directory_source
                        .finish_close(&remote_runtime)
                        .await;
                    let transport = ssh.shutdown().await.map_err(anyhow::Error::from);
                    match (cursors, transport) {
                        (Ok(()), Ok(())) => Ok(()),
                        (Err(error), Ok(())) | (Ok(()), Err(error)) => Err(error),
                        (Err(cursors), Err(transport)) => {
                            Err(anyhow::anyhow!("{cursors:#}; {transport:#}"))
                        }
                    }
                },
            );
            outcomes.push(
                observe_stage(budget, StageId::Ssh, ssh_job, Some(SERVICE_STAGE_LIMIT)).await,
            );
            outcomes
        };

        // 写入收束链：生产者真实停止 ACK 先于可靠持久化 drain/writer 停止（有向顺序，不可颠倒）。
        // 缺 ACK 不启动 persistence job，原 owner 重试收束后才允许最终停止 writer。整条链与上面
        // 的独立资源并发进行——独立服务不会被持久化 drain 的等待拖后。
        let write_chain = {
            let progress = progress.clone();
            let runtime = self.clone();
            let retries = retries.clone();
            async move {
                // 观测结束不等于生产者已停止。只有原阶段全部真实 Done 才能关闭其 writer 依赖；
                // 失败、超时与预算耗尽的 outcome 仍原样交给 collector，不能用最终 Degraded 补救早关。
                let mut outcomes = drain_stage_branches(&mut producers).await;
                // 放行 SSH 依赖闸门并如实携带「实际是否全部成功 ACK」：写入链仍是 outcome 唯一记录方，
                // 这里只传事实、不复制诊断。成功与有界失败都照样请求 SSH 回收。
                let producers_settled = outcomes.iter().all(StageOutcome::is_done);
                // SSH 闸门只表达“远端工具所依赖的生产者已停止”：Bot 应答 owner 只持历史读取，
                // 不驱动远端工具，因此不延长 SSH 收束；持久化仍要求全部生产者真实停止。
                let _ = producers_settled_tx.send(
                    outcomes
                        .iter()
                        .all(|outcome| outcome.id == StageId::Bots || outcome.is_done()),
                );
                let writer_reclaimed = if producers_settled {
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
                        StageId::Persistence,
                        None,
                        retries,
                        |runtime| async move { runtime.shutdown_persistence().await },
                    )
                    .await;
                    let reclaimed = persistence.is_done();
                    outcomes.push(persistence);
                    reclaimed
                } else {
                    false
                };
                // 观测真实剩余待保存事实；有界只读，未知即 Unknown，绝不用 0 冒充。
                let pending_after = runtime.observe_pending(budget).await;
                (outcomes, producers_settled, writer_reclaimed, pending_after)
            }
        };

        // 写入链、非 SSH 依赖的本地资源、以及依赖闸门后的 SSH 回收三者同时推进：SSH 内只等它的
        // 两条依赖边（`remote_dependents` 的远端服务/工具停止与写入生产者停止 ACK），不等与它
        // 无关的持久化 / 数据库提交——因此保存锁阻塞时 MCP/LSP、远端依赖与 SSH transport 仍能
        // 各自及时收束。
        let independent_branch = async move { drain_stage_branches(&mut independent).await };
        let (
            (write_outcomes, producers_settled, writer_reclaimed, pending_after),
            mut independent_outcomes,
            mut ssh_outcomes,
        ) = futures::join!(write_chain, independent_branch, ssh_branch);

        // 汇总所有阶段的真实结果：按稳定权重排序，报告顺序不随完成先后抖动。
        let mut outcomes = write_outcomes;
        outcomes.append(&mut independent_outcomes);
        outcomes.append(&mut ssh_outcomes);
        outcomes.sort_by_key(|outcome| outcome.id.order());

        let persistence = match (producers_settled, writer_reclaimed, pending_after) {
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
            writer_reclaimed,
            persistence,
        }
    }

    async fn observe_pending(&self, budget: ShutdownBudget) -> Option<usize> {
        let wait = budget.observe_wait(FACTS_LIMIT).unwrap_or(Duration::ZERO);
        tokio::time::timeout(wait, self.pending_persistence_commits())
            .await
            .ok()
    }

    async fn finalize_shutdown(&self, collector: &mut ShutdownCollector) {
        collector.seed_external_issues(self.shutdown_run.exit_issues());
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
        let store_job = if let Some(job) = self.shutdown_run.existing_store() {
            // An earlier caller may have left while Store IO was in flight. Rejoining does not
            // start new IO, and is still required when the new collector already has issues.
            Some(Ok(job))
        } else if can_close {
            // Store admission checks first-exit D0/E under the same slot-installation boundary.
            // Once admitted, IO continues even if a later exit blocks final Clean publication.
            let store = self.store.clone();
            Some(self.shutdown_run.ensure_stage(
                StageId::Store,
                &RetrySnapshot::default(),
                move || async move { store.close().await },
            ))
        } else {
            None
        };
        if let Some(job) = store_job {
            let outcome = observe_stage(collector.budget, StageId::Store, job, None).await;
            collector.store_closed = outcome.is_done();
            collector.record_stage(outcome);
        } else if collector.expired() {
            let elapsed = collector.elapsed_ms();
            collector.record_skipped(StageId::Store.label(), elapsed);
        }

        let clean = !collector.has_issues()
            && matches!(collector.persistence, StudioPendingPersistence::Drained)
            && collector.store_closed;
        if clean {
            match self.shutdown_run.commit_clean(&self.runtime_state) {
                Ok(CleanCommit::First) => {
                    // The coordinator guard is gone: publication and actual resource/file-lock
                    // release cannot call back while holding the finalization admission lock.
                    self.configuration_source.finish_close();
                    self.mcp_source.finish_close();
                    self.lsp_source.finish_close();
                    self.skills_source.finish_close();
                    self.profiles_source.finish_close();
                    self.startup_source.finish_close();
                    self.recovery_source.finish_close();
                    self.persistence_source.finish_close();
                    self.persistence_queue_source.finish_close();
                    self.bots_source.finish_close();
                    self.workspace_source.finish_close();
                    self.shutdown_progress
                        .emit(crate::StudioShutdownProgress::Stopped(Default::default()));
                    self.instance_lock.release();
                    return;
                }
                Ok(CleanCommit::AlreadyCommitted) => return,
                Err(CleanCommitError::Exit(block)) => {
                    let elapsed = collector.elapsed_ms();
                    collector.record_exit_block("finishShutdown", elapsed, block);
                }
                Err(CleanCommitError::Runtime(error)) => {
                    let elapsed = collector.elapsed_ms();
                    collector.record_error("finishShutdown", elapsed, &error.into());
                }
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
                error: pl_protocol::StateError {
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
        id: StageId,
        limit: Option<Duration>,
        retries: RetrySnapshot,
        // 同 `run_stage_owned`：factory 跨 await 持有，需 `Send` 才能让返回的 `BoxFuture` 满足其
        // 跨线程 `Send` 不变量；不做 `unsafe`/`allow`/本地 boxed 规避。
        make: impl FnOnce(StudioRuntime) -> Fut + Send + 'static,
    ) -> StageBranch
    where
        Fut: Future<Output = Result<()>> + Send + 'static,
    {
        run_stage_owned(self.clone(), budget, id, limit, retries, make)
            .map(|outcome| vec![outcome])
            .boxed()
    }
}

/// 把一个编排前的错误（如早期封闭的状态推进失败）投影为脱敏的关闭诊断。
fn shutdown_issue_from_error(stage: &str, error: &anyhow::Error) -> StudioShutdownIssue {
    let mapped = crate::error_mapping::studio_error_from_anyhow_ref(error);
    StudioShutdownIssue {
        stage: stage.to_string(),
        code: mapped.code.label().to_string(),
        message: mapped.message,
        retryable: mapped.retryable,
        correlation_id: mapped.correlation_id,
    }
}

fn shutdown_report_error(report: &StudioShutdownReport) -> anyhow::Error {
    let issue = report.issues.first();
    let message = issue
        .map(|issue| {
            let stage = issue.stage.as_str();
            let code = issue.code.as_str();
            let correlation_id = issue.correlation_id.as_str();
            format!(
                "Studio runtime shutdown did not complete cleanly ({stage}: {code}, correlation {correlation_id})"
            )
        })
        .unwrap_or_else(|| {
            let persistence = report.persistence;
            format!(
                "Studio runtime shutdown did not complete cleanly (persistence: {persistence:?})"
            )
        });
    anyhow::anyhow!(message)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
    use crate::studio::agent_host::ThreadWriteBehindWriter;
    use crate::studio::store::directory::{DirectoryDelta, ProjectDirectoryRecord};
    use pl_core::context::OpaquePayload;
    use pl_core::tool::{
        ToolOutput,
        opaque::{CallContext, Registration, Tool, ToolError},
    };
    use pl_model::config::{AccountConfig, AccountId, ModelRouteConfig};
    use pl_model::model::ModelInfo;
    use pl_model::protocol::ProtocolEndpoint;
    use std::sync::atomic::{AtomicBool, AtomicUsize, Ordering};
    use tokio::sync::Notify;

    #[derive(Debug, Default)]
    struct CloseFault {
        recover: AtomicBool,
        attempts: AtomicUsize,
        retry_written: Notify,
        close_ack: Notify,
    }

    struct CloseFaultTool {
        fault: Arc<CloseFault>,
        writer: ThreadWriteBehindWriter,
        final_write: DirectoryDelta,
    }

    impl std::fmt::Debug for CloseFaultTool {
        fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            formatter
                .debug_struct("CloseFaultTool")
                .finish_non_exhaustive()
        }
    }

    impl Tool for CloseFaultTool {
        async fn execute(
            &self,
            input: OpaquePayload,
            _context: CallContext,
        ) -> Result<ToolOutput, ToolError> {
            Ok(ToolOutput::new(input, Vec::new()))
        }

        async fn close(&self) -> Result<(), ToolError> {
            self.fault.attempts.fetch_add(1, Ordering::SeqCst);
            if !self.fault.recover.load(Ordering::SeqCst) {
                return Err(ToolError::new(std::io::Error::other(
                    "injected original producer close failure",
                )));
            }
            // This is the same producer and writer retained by the failed close, not a new
            // writer or a recovery shim. Its final write must become durable before close ACK.
            self.writer.record_directory(self.final_write.clone());
            self.writer.flush().await.map_err(ToolError::new)?;
            self.fault.retry_written.notify_one();
            self.fault.close_ack.notified().await;
            Ok(())
        }
    }

    #[tokio::test]
    async fn failed_producer_close_retains_writer_until_original_retry_acks() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let workspace = temp.path().join("workspace");
        tokio::fs::create_dir_all(&workspace).await?;
        let endpoint = std::net::TcpListener::bind("127.0.0.1:0")?;
        let account_id = AccountId::new("shutdown-fixture")?;
        let route = ModelRouteConfig {
            account_id: account_id.clone(),
            model_id: "shutdown-model".into(),
            effort: None,
        };
        let mut config = StudioConfig::default_config()?;
        config.models.accounts.clear();
        config.models.accounts.insert(
            account_id,
            AccountConfig::from_explicit_models(
                ProtocolEndpoint::compatible(
                    "Shutdown fixture",
                    format!("http://{}", endpoint.local_addr()?),
                ),
                vec![ModelInfo::compatible(&route.model_id)],
            ),
        );
        for selected in config
            .models
            .routes
            .values_mut()
            .chain(config.mode_model_routes.values_mut())
        {
            *selected = route.clone();
        }
        ConfigStore::new(ConfigPaths::from_config_dir(&home)).save(&config)?;
        let runtime = StudioRuntime::initialize(crate::StudioRuntimeOptions {
            studio_home: Some(home),
            host: crate::StudioHostKind::Test,
            ..crate::StudioRuntimeOptions::desktop()
        })
        .await?;
        let project = runtime.open_project(&workspace).await?;
        let thread = runtime.create_thread(&project.id, "close failure").await?;
        let original = runtime.threads.thread(&thread.id).expect("original Thread");
        let writer = runtime
            .agent_facility
            .persistence
            .lock()
            .await
            .clone()
            .expect("original writer");
        let fault = Arc::new(CloseFault::default());
        original
            .register_tools(vec![Registration::new(
                "close-fault".into(),
                OpaquePayload::text("Close fault fixture"),
                CloseFaultTool {
                    fault: fault.clone(),
                    writer: writer.clone(),
                    final_write: DirectoryDelta::upsert_project(ProjectDirectoryRecord {
                        id: project.id.clone(),
                        name: "written by original producer after close failure".into(),
                        path: project.path.clone(),
                        ssh_alias: None,
                        created_at: 1,
                        updated_at: 2,
                        last_opened_at: None,
                        closed: false,
                    }),
                },
            )?])
            .await?;
        runtime.flush_persistence().await?;

        // Use the actual orchestration and final collector without a wall-clock exit deadline.
        let report = runtime
            .execute_shutdown(ShutdownBudget::unbounded(), RetrySnapshot::default())
            .await;
        assert_eq!(report.outcome, StudioShutdownOutcome::Degraded);
        let original_issue = report
            .issues
            .iter()
            .find(|issue| issue.stage == StageId::AgentFramework.label())
            .expect("original close failure is reported")
            .clone();
        assert!(!matches!(
            report.persistence,
            StudioPendingPersistence::Drained
        ));
        assert!(
            runtime.agent_facility.persistence.lock().await.is_some(),
            "failed producer close must retain the original persistence writer"
        );
        assert!(
            runtime
                .threads
                .observed_thread(&thread.id)
                .is_some_and(|retained| retained.same_instance(&original))
        );
        let calls_effect = pl_core::thread::ThreadEffectBatch {
            thread_id: thread.id.clone(),
            ..Default::default()
        };
        assert!(runtime.store.calls().try_admit_effect(&calls_effect));
        let failed_attempts = fault.attempts.load(Ordering::SeqCst);
        assert!(
            failed_attempts > 0,
            "the original Tool close actually failed"
        );

        // Another observer does not replay a failed owner or erase its original diagnostic.
        let repeated = runtime
            .execute_shutdown(ShutdownBudget::unbounded(), RetrySnapshot::default())
            .await;
        assert_eq!(repeated.outcome, StudioShutdownOutcome::Degraded);
        assert!(repeated.issues.contains(&original_issue));
        assert_eq!(fault.attempts.load(Ordering::SeqCst), failed_attempts);

        fault.recover.store(true, Ordering::SeqCst);
        let retry_runtime = runtime.clone();
        let retry = tokio::spawn(async move { retry_runtime.shutdown_runtime().await });
        tokio::time::timeout(Duration::from_secs(5), fault.retry_written.notified()).await?;
        assert_eq!(
            runtime
                .store
                .read_project(&project.id)
                .await?
                .expect("durable project")
                .name,
            "written by original producer after close failure"
        );
        assert!(runtime.agent_facility.persistence.lock().await.is_some());
        assert!(
            !retry.is_finished(),
            "writer release must wait for the actual close ACK"
        );
        fault.close_ack.notify_one();
        let stopped = tokio::time::timeout(Duration::from_secs(5), retry).await???;
        assert!(stopped.state.is_stopped());
        assert!(runtime.agent_facility.persistence.lock().await.is_none());
        assert!(runtime.threads.observed_thread(&thread.id).is_none());
        assert!(!runtime.store.calls().try_admit_effect(&calls_effect));
        let closed_attempts = fault.attempts.load(Ordering::SeqCst);
        assert!(closed_attempts > failed_attempts);
        assert!(runtime.shutdown_runtime().await?.state.is_stopped());
        assert_eq!(fault.attempts.load(Ordering::SeqCst), closed_attempts);
        endpoint.set_nonblocking(true)?;
        assert!(
            matches!(endpoint.accept(), Err(error) if error.kind() == std::io::ErrorKind::WouldBlock)
        );
        Ok(())
    }
}

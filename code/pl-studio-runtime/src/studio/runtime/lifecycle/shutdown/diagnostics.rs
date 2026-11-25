//! Typed shutdown facts and redacted diagnostic collection.

use super::stages::{ServiceStopFailure, ShutdownBudget, StageOutcome, StageStatus};
use crate::{
    StudioPendingPersistence, StudioShutdownIssue, StudioShutdownOutcome, StudioShutdownReport,
};
use std::time::Instant;

/// 单个诊断日志里最多列出的未收束 Thread 标识数量，避免超长 Thread 列表挤占日志。
const UNRESOLVED_THREAD_LOG_LIMIT: usize = 8;

pub(super) fn panic_text(payload: &(dyn std::any::Any + Send)) -> String {
    if let Some(message) = payload.downcast_ref::<&str>() {
        (*message).to_string()
    } else if let Some(message) = payload.downcast_ref::<String>() {
        message.clone()
    } else {
        "shutdown orchestration task panicked".to_string()
    }
}

/// 一次关闭观测到的可靠持久化事实；缺失即为未知，绝不用零掩盖。
#[derive(Debug, Clone, Default)]
pub(super) struct PersistenceFacts {
    pub(super) pending: usize,
    pub(super) save_watermark: Option<u64>,
    pub(super) owner_id: Option<String>,
    /// 仍有待提交、故障或未收束水位的 Thread 标识。
    pub(super) unresolved_thread_ids: Vec<String>,
    /// 所有 owner 中最保守（最小）的 admitted/durable 历史水位：全局确认要求每个 owner 都
    /// 至少推进到该值，因此用最小值而不是最大值，绝不用单个 owner 的最大值冒充全局确认。
    pub(super) history_admitted_min: Option<u64>,
    pub(super) history_durable_min: Option<u64>,
    pub(super) fault_generation: Option<u64>,
}

/// 阶段诊断聚合器。
pub(super) struct ShutdownCollector {
    pub(super) budget: ShutdownBudget,
    pub(super) started: Instant,
    pub(super) issues: Vec<StudioShutdownIssue>,
    pub(super) persistence: StudioPendingPersistence,
    pub(super) store_closed: bool,
    /// 持久化 writer 是否已在本次编排中实际 ack 并移交（成功 flush 之后）。
    pub(super) writer_reclaimed: bool,
    pub(super) owner_id: Option<String>,
    pub(super) save_watermark: Option<u64>,
    pub(super) pending_hint: Option<usize>,
    pub(super) unresolved_thread_ids: Vec<String>,
    pub(super) history_admitted_min: Option<u64>,
    pub(super) history_durable_min: Option<u64>,
    pub(super) fault_generation: Option<u64>,
}

impl ShutdownCollector {
    pub(super) fn new(budget: ShutdownBudget) -> Self {
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

    pub(super) fn expired(&self) -> bool {
        self.budget.expired()
    }

    pub(super) fn has_issues(&self) -> bool {
        !self.issues.is_empty()
    }

    pub(super) fn elapsed_ms(&self) -> u128 {
        self.started.elapsed().as_millis()
    }

    pub(super) fn pending_label(&self) -> String {
        match self.pending_hint {
            Some(count) => format!("pending:{count}"),
            None => "unknown".to_string(),
        }
    }

    pub(super) fn unresolved_label(&self) -> String {
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
        self.issues.push(issue);
    }

    /// 播种调用方在进入编排前已经确定的失败（桥端 / Dart 侧订阅、更新取消未确认）。
    ///
    /// 它们与 runtime 自身阶段共享同一 `issues`，因此直接决定 `finalize_shutdown` 的成功
    /// 前置条件：只要存在任何一条，收束阶段就不会判定 `Clean`，也不会发布 `Stopped` 或释放
    /// 实例锁。诊断保留真实 `code` / `correlation_id`，不伪造 runtime 阶段的收束事实。
    pub(super) fn seed_external_issues(&mut self, issues: Vec<StudioShutdownIssue>) {
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
    pub(super) fn record_error(
        &mut self,
        stage: &str,
        stage_elapsed_ms: u128,
        error: &anyhow::Error,
    ) {
        let mapped = crate::error_mapping::studio_error_from_anyhow_ref(error);
        // Diagnostics keep only redacted, structure-level facts: the shared `StudioError` message,
        // `std::io` kind/OS code and the database failure category/code. The raw source chain can
        // embed prompt bodies or credentials, so its message bodies are never written verbatim.
        // Do not unwind the embedding host here: the classified issue and its save/owner
        // facts must remain reportable even when the host's native unwinder is unavailable.
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
            detail = %mapped.message,
            "Studio shutdown stage failed"
        );
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
    fn record_service_failure(
        &mut self,
        stage: &str,
        stage_elapsed_ms: u128,
        failure: &ServiceStopFailure,
    ) {
        match failure {
            ServiceStopFailure::Failed(error) => self.record_error(stage, stage_elapsed_ms, error),
            ServiceStopFailure::Panicked(join) => {
                self.record_join_error(stage, stage_elapsed_ms, join)
            }
        }
    }

    pub(super) fn record_timeout(&mut self, stage: &str, stage_elapsed_ms: u128) {
        let mapped = crate::StudioError::new(
            crate::StudioErrorCode::Busy,
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
        let mapped = crate::StudioError::new(
            crate::StudioErrorCode::Busy,
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
    pub(super) fn record_stage(&mut self, outcome: StageOutcome) {
        let StageOutcome {
            stage,
            status,
            elapsed,
            ..
        } = outcome;
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
            StageStatus::Failed(error) => {
                self.record_error(stage, stage_elapsed_ms, &error);
            }
            StageStatus::Panicked(join) => {
                self.record_join_error(stage, stage_elapsed_ms, &join);
            }
            StageStatus::TimedOut => self.record_timeout(stage, stage_elapsed_ms),
            StageStatus::Skipped => self.record_skipped(stage, stage_elapsed_ms),
            StageStatus::ServiceFailure(failure) => {
                self.record_service_failure(stage, stage_elapsed_ms, &failure);
            }
        }
    }

    pub(super) fn report(self) -> StudioShutdownReport {
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
pub(in crate::studio::runtime::lifecycle) fn redacted_chain(error: &anyhow::Error) -> String {
    let mut parts = Vec::new();
    for cause in error.chain() {
        if let Some(studio) = cause.downcast_ref::<crate::StudioError>() {
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

/// 把一个编排前的错误（如早期封闭的状态推进失败）投影为脱敏的关闭诊断。
pub(super) fn shutdown_issue_from_error(stage: &str, error: &anyhow::Error) -> StudioShutdownIssue {
    let mapped = crate::error_mapping::studio_error_from_anyhow_ref(error);
    StudioShutdownIssue {
        stage: stage.to_string(),
        code: mapped.code.label().to_string(),
        message: mapped.message,
        retryable: mapped.retryable,
        correlation_id: mapped.correlation_id,
    }
}

pub(super) fn shutdown_report_error(report: &StudioShutdownReport) -> anyhow::Error {
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

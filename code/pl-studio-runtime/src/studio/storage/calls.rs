//! 全局调用统计投影（`calls.sqlite`）与版本化 JSONL 滚动调用日志。
//!
//! 调用正文写入 `<calls>/logs/` 下的版本化 JSONL 段文件：单段最大 16 MiB、跨 UTC 自然日轮转、
//! 单条记录 1 MiB 上限（超过显式 `truncated`）、整体保留 7 天且总量不超过 256 MiB。启动、每 15
//! 分钟与每次轮转都会清理过期/超量段；清理失败记录为可重试降级并在下一次追加前阻塞增长，因此日志
//! 不会无限膨胀。段尾半条记录（进程在写入中途退出）在打开时回退到最后一个换行。
//!
//! `calls.sqlite` 只保留有界数据：随段回收的日志索引（`call_log_index`）、按 root/thread/purpose
//! 的累计费用摘要（`call_usage_summary`，由可靠 writer 通过
//! [`CallsStore::replace_session_usage`] 以 revision 绝对投影幂等供给，不依赖将被删除的正文），
//! 以及有界的性能样本（`performance_samples`，最多 [`PERFORMANCE_SAMPLE_LIMIT`] 条）。
//!
//! 单库只有一个逻辑 writer：轻量调用事件进入同一条有界队列，后台批量落盘（JSONL 追加 + SQLite
//! 索引/统计）。队列满或写入失败只记录统计缺口，不阻塞 Thread 的权威历史提交。
//!
//! 打开时会校验 `calls_meta.schema_version`：schema <= 4 的旧库先保全累计摘要、再把保留期正文转换
//! 进日志，全部成功后才前移版本并删除旧结构；schema 5 修复遗留样本外键。性能样本只由当前统计口径
//! （`calls_meta.throughput_epoch`）的记录建立，旧口径样本在口径切换时一次性丢弃，且不会从仍保留的
//! 旧日志回填。未来版本显式失败并保留原字节，不触碰用户 home 下的旧数据根。
//! schema 9 将全 effect 水位保全为仅供显式旧 checkpoint 迁移使用的 fence，生产写入只处理实际记录。

use super::sqlite_util::is_retryable_write;
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use crate::{InferenceBillingRecord, RuntimeCostAmount};
use anyhow::{Context, Result, bail, ensure};
use pl_core::model::ModelUsage;
use pl_core::thread::journal::AttemptUpdate;
use pl_core::thread::{AttemptOutcome, ThreadEffectBatch};
use sea_orm::sqlx::sqlite::{SqliteJournalMode, SqliteSynchronous};
use sea_orm::{
    ConnectionTrait, Database, DatabaseBackend, DatabaseConnection, DatabaseTransaction,
    QueryResult, Statement, TransactionTrait, Value,
};
use tokio::sync::{Notify, watch};
use tracing::Instrument;

use crate::studio::thread_projection::merge_runtime_costs as merge_costs;

mod event;
mod log;
#[cfg(feature = "benchmarks")]
pub(crate) mod observation;
mod performance;
pub(crate) use performance::ACP_TEXT_ESTIMATE;
mod schema;
mod summary;

pub(crate) use performance::PERFORMANCE_SAMPLE_LIMIT;
pub(crate) use summary::{PurposeUsageProjection, SessionUsageProjection};

use event::CallLogRecord;
use log::{CallLog, LOG_CLEANUP_INTERVAL};

pub(crate) const CALLS_SCHEMA_VERSION: i64 = 10;
/// `calls` 目录下日志段所在子目录名。
const CALL_LOG_DIR_NAME: &str = "logs";
/// 一天对应的秒数；日志轮转/保留期以 UTC 自然日为准。
pub(super) const SECONDS_PER_DAY: i64 = 86_400;
/// 单批最多应用的 mutation 数。
const MAX_BATCH_MUTATIONS: usize = 64;
/// 单批最多聚合的字节预算。
const MAX_BATCH_BYTES: usize = 4 * 1024 * 1024;
/// 队列条目数上限；达到后拒绝新的统计事实。
const MAX_QUEUE_MUTATIONS: usize = 4_096;
/// 队列保留字节软上限。
const MAX_QUEUE_BYTES: usize = 64 * 1024 * 1024;
/// 进入有界指数退避前允许的快速重试次数。
const FAST_RETRIES: usize = 3;
/// 瞬时失败的重试退避基值。
const RETRY_BACKOFF: Duration = Duration::from_millis(100);
/// 退化后的最大自动重试间隔。
const MAX_RETRY_BACKOFF: Duration = Duration::from_secs(30);

/// 调用结果类别；持久化为稳定字符串。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum CallStatus {
    Running,
    Committed,
    Rejected,
    Cancelled,
    Failed,
    Interrupted,
}

impl CallStatus {
    pub(crate) const fn as_str(self) -> &'static str {
        match self {
            Self::Running => "running",
            Self::Committed => "committed",
            Self::Rejected => "rejected",
            Self::Cancelled => "cancelled",
            Self::Failed => "failed",
            Self::Interrupted => "interrupted",
        }
    }

    pub(crate) const fn is_terminal(self) -> bool {
        !matches!(self, Self::Running)
    }
}

/// 写入 retention：区分主循环调用与内部/辅助推理。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum CallRetention {
    Turn,
    Internal,
}

impl CallRetention {
    pub(crate) const fn as_str(self) -> &'static str {
        match self {
            Self::Turn => "turn",
            Self::Internal => "internal",
        }
    }
}

/// 单个 root 会话的费用聚合投影（由调用库摘要聚合得到）。
#[derive(Debug, Clone, Default)]
pub(crate) struct SessionCostRollup {
    pub(crate) root_thread_id: String,
    pub(crate) estimated_costs: Vec<RuntimeCostAmount>,
    pub(crate) purpose_costs: Vec<PurposeCostRollup>,
    pub(crate) has_unpriced_usage: bool,
}

/// 单个 purpose 的费用聚合投影。
#[derive(Debug, Clone, Default)]
pub(crate) struct PurposeCostRollup {
    pub(crate) purpose: Option<String>,
    pub(crate) estimated_costs: Vec<RuntimeCostAmount>,
    pub(crate) has_unpriced_usage: bool,
}

/// 一条成功调用；未测得的时延不能伪装成零时延。
#[derive(Debug, Clone)]
pub(crate) struct PerformanceSampleRow {
    pub(crate) thread_id: String,
    pub(crate) call_id: String,
    pub(crate) purpose: Option<String>,
    pub(crate) completed_at: i64,
    pub(crate) account_id: String,
    pub(crate) account_display_name: String,
    pub(crate) model_id: Option<String>,
    pub(crate) sent_model: String,
    pub(crate) reported_model: Option<String>,
    pub(crate) effort: Option<String>,
    pub(crate) requested_service_tier: Option<String>,
    pub(crate) completion_tokens: Option<u64>,
    pub(crate) usage_status: pl_core::usage::UsageStatus,
    pub(crate) first_output_source: crate::FirstOutputSource,
    pub(crate) ttft_millis: Option<u64>,
    pub(crate) decode_millis: Option<u64>,
    pub(crate) response_millis: Option<u64>,
    pub(crate) has_throughput_sample: bool,
}

/// 按（账号、冻结的目录配置模型、推理强度、请求档位）的数据库聚合分组。
///
/// 顶层统计身份是 (account_id, model_id)；推理强度与请求档位是组内二级细分。发送/返回模型
/// 只是冻结诊断，不参与归组。
#[derive(Debug, Clone)]
pub(crate) struct PerformanceSummaryRow {
    pub(crate) account_id: String,
    pub(crate) account_display_name: String,
    pub(crate) model_id: String,
    pub(crate) effort: Option<String>,
    pub(crate) requested_service_tier: Option<String>,
    pub(crate) sample_count: u64,
    pub(crate) completion_tokens: u64,
    /// 只有真正测得首字的样本才累加，因此它同时是平均首字的独立分母。
    pub(crate) total_ttft_millis: u64,
    pub(crate) ttft_sample_count: u64,
    /// 含首字等待的总响应耗时；输出吞吐的分母。
    pub(crate) total_response_millis: u64,
}

/// Absolute process-local material versions. A watch receiver may skip intermediate versions;
/// each version identifies a reason to reload the corresponding SQLite material, never a delta.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub(crate) struct CallsMaterialVersions {
    pub(crate) performance: u64,
    pub(crate) costs: u64,
    pub(crate) status: u64,
}

/// Completion of actual writer work, including explicit rejection. Processed tickets are not
/// proofs that every preceding mutation succeeded; gap/error remain separate from progress.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct CallsMaterialProgress {
    pub(crate) versions: CallsMaterialVersions,
    pub(crate) processed_ticket: u64,
    pub(crate) statistics_gap: bool,
    pub(crate) last_error: Option<String>,
}

#[derive(Debug, Clone, Copy)]
pub(crate) struct StatisticsReadRequest {
    pub(crate) costs: bool,
    pub(crate) performance: bool,
}

/// Requested materials come from one short SQLite read transaction, not the JSONL writer lock.
pub(crate) struct CallsStatisticsRead {
    pub(crate) costs: Option<Vec<SessionCostRollup>>,
    pub(crate) history: Option<Vec<PerformanceSampleRow>>,
    pub(crate) summary: Option<Vec<PerformanceSummaryRow>>,
}

pub(crate) struct AcpPerformanceObservation {
    pub(crate) thread_id: String,
    pub(crate) call_id: String,
    pub(crate) account_id: String,
    pub(crate) account_name: String,
    pub(crate) model: Option<String>,
    pub(crate) effort: Option<String>,
    pub(crate) performance: crate::AcpTextPerformance,
}

mod batch;
mod queue;
mod worker;

use self::{batch::*, queue::*, worker::*};

/// 单一逻辑 writer 的共享状态：唯一 SQLite 连接、唯一滚动日志、唯一队列与水位。
struct CallsWriter {
    db: DatabaseConnection,
    #[cfg(feature = "benchmarks")]
    observation: Arc<observation::Observation>,
    log: tokio::sync::Mutex<CallLog>,
    queue: Mutex<MutationQueue>,
    work_notify: Notify,
    retry_notify: Notify,
    admitted_ticket: AtomicU64,
    processed_ticket: watch::Sender<u64>,
    materials: watch::Sender<CallsMaterialProgress>,
    /// Encoded bytes of the batch currently being written; a read-only pressure observation.
    in_flight_bytes: AtomicU64,
    stopping: AtomicBool,
    deleted_threads: Mutex<BTreeSet<String>>,
    last_error: Mutex<Option<String>>,
    statistics_gap: AtomicBool,
}

/// 全局调用库句柄；clone 共享同一条队列、日志与后台 writer。
#[derive(Clone)]
pub(crate) struct CallsStore {
    writer: Arc<CallsWriter>,
    task: Arc<tokio::sync::Mutex<Option<tokio::task::JoinHandle<()>>>>,
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum CallsOpenPolicy {
    Degraded,
    Strict,
}

impl CallsStore {
    pub(crate) fn metrics(&self) -> super::coordinator::CallsQueueMetrics {
        let queue = queue_pressure(&self.writer);
        super::coordinator::CallsQueueMetrics {
            admitted_ticket: self.admitted_ticket(),
            processed_ticket: self.processed_ticket(),
            pending_operations: u64::try_from(queue.mutations).unwrap_or(u64::MAX),
            pending_bytes: u64::try_from(queue.bytes).unwrap_or(u64::MAX),
            in_flight_bytes: u64::try_from(self.in_flight_bytes()).unwrap_or(u64::MAX),
            oldest_pending_age_millis: queue
                .oldest_accepted_at
                .map(|accepted| u64::try_from(accepted.elapsed().as_millis()).unwrap_or(u64::MAX)),
            last_error: self.last_error(),
            pressure_paused: queue.mutations >= MAX_QUEUE_MUTATIONS
                || queue.bytes >= MAX_QUEUE_BYTES,
            statistics_gap: self.statistics_gap(),
        }
    }

    pub(crate) fn statistics_gap(&self) -> bool {
        self.writer.statistics_gap.load(Ordering::Acquire)
    }

    pub(crate) fn mark_statistics_gap(&self) {
        self.writer.statistics_gap.store(true, Ordering::Release);
        publish_status(&self.writer);
    }

    pub(crate) async fn open(path: &Path) -> Result<Self> {
        let store = Self::prepare_with_policy(path, CallsOpenPolicy::Degraded).await?;
        store.start().await;
        Ok(store)
    }

    pub(crate) async fn prepare(path: &Path) -> Result<Self> {
        Self::prepare_with_policy(path, CallsOpenPolicy::Strict).await
    }

    async fn prepare_with_policy(path: &Path, policy: CallsOpenPolicy) -> Result<Self> {
        schema::inspect_existing(path).await?;
        if let Some(parent) = path.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }
        let root_dir = path
            .parent()
            .unwrap_or_else(|| Path::new("."))
            .to_path_buf();
        let mut options = crate::studio::paths::sqlite_file_options(
            path,
            crate::studio::paths::SqliteFileMode::Create,
            |options| {
                options
                    .journal_mode(SqliteJournalMode::Wal)
                    .synchronous(SqliteSynchronous::Full)
                    .busy_timeout(Duration::from_secs(5))
                    .foreign_keys(true)
            },
        )
        .await?;
        options
            .max_connections(2)
            .min_connections(2)
            .connect_timeout(Duration::from_secs(8))
            .acquire_timeout(Duration::from_secs(8))
            .sqlx_logging(false);
        let db = Database::connect(options).await?;
        if let Err(error) = schema::initialize(&db, &root_dir).await {
            let error = crate::studio::startup::input_error(error);
            if let Err(cleanup) = db.close().await {
                return Err(error.context(format!("calls database cleanup failed: {cleanup}")));
            }
            return Err(error);
        }
        let log = match policy {
            CallsOpenPolicy::Degraded => CallLog::open(root_dir.join(CALL_LOG_DIR_NAME)).await,
            CallsOpenPolicy::Strict => CallLog::prepare(root_dir.join(CALL_LOG_DIR_NAME)).await,
        };
        let mut log = match log {
            Ok(log) => log,
            Err(error) => {
                if let Err(cleanup) = db.close().await {
                    return Err(crate::studio::startup::cleanup_error(cleanup).context(error));
                }
                return Err(error);
            }
        };
        let mut startup_error = None;
        if let Err(error) = log.rebuild_index(&db).await {
            if policy == CallsOpenPolicy::Strict {
                let error = crate::studio::startup::input_error(error);
                db.close()
                    .await
                    .context("failed to close calls database after index failure")?;
                return Err(error);
            }
            startup_error = Some(error.to_string());
            tracing::warn!(%error, "调用日志索引重建失败，诊断降级");
        }
        // 启动清理尽力而为：失败记录降级，周期任务会重试。
        if let Err(error) = maintenance(&db, &mut log).await {
            startup_error = Some(error.to_string());
            tracing::warn!(error = %error, "调用库启动清理失败，稍后重试");
        }
        let (processed_ticket, _) = watch::channel(0u64);
        let writer = Arc::new(CallsWriter {
            db,
            #[cfg(feature = "benchmarks")]
            observation: log.observation.clone(),
            log: tokio::sync::Mutex::new(log),
            queue: Mutex::new(MutationQueue::default()),
            work_notify: Notify::new(),
            retry_notify: Notify::new(),
            admitted_ticket: AtomicU64::new(0),
            processed_ticket,
            materials: watch::channel(CallsMaterialProgress {
                statistics_gap: false,
                last_error: startup_error.clone(),
                ..Default::default()
            })
            .0,
            in_flight_bytes: AtomicU64::new(0),
            stopping: AtomicBool::new(false),
            deleted_threads: Mutex::new(BTreeSet::new()),
            statistics_gap: AtomicBool::new(false),
            last_error: Mutex::new(startup_error),
        });
        Ok(Self {
            writer,
            task: Arc::new(tokio::sync::Mutex::new(None)),
        })
    }

    pub(crate) async fn start(&self) {
        let mut task = self.task.lock().await;
        if task.is_none() {
            *task = Some(tokio::spawn(supervise_writer(self.writer.clone())));
        }
    }

    #[cfg(feature = "benchmarks")]
    pub(crate) fn observation(&self) -> &Arc<observation::Observation> {
        &self.writer.observation
    }

    pub(crate) async fn close(&self) -> Result<()> {
        self.stop_best_effort();
        let mut task = self.task.lock().await;
        let completion = match task.as_mut() {
            Some(handle) => handle.await.context("failed to join calls writer"),
            None => Ok(()),
        };
        task.take();
        self.writer.log.lock().await.close();
        let database = self.writer.db.close_by_ref().await;
        completion?;
        database?;
        Ok(())
    }

    /// Permanently removes only these stopped Thread identities from the shared writer.
    pub(crate) async fn delete_threads(&self, thread_ids: &[String]) -> Result<()> {
        {
            let _log = self.writer.log.lock().await;
            self.writer
                .deleted_threads
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .extend(thread_ids.iter().cloned());
        }
        let target = self.admitted_ticket();
        let mut processed = self.writer.processed_ticket.subscribe();
        self.writer.work_notify.notify_one();
        while *processed.borrow_and_update() < target {
            ensure!(
                !self.writer.stopping.load(Ordering::Acquire),
                "calls writer stopped before deletion drain"
            );
            if let Some(error) = self.last_error() {
                anyhow::bail!("calls deletion drain failed: {error}");
            }
            processed
                .changed()
                .await
                .context("calls writer stopped before deletion drain")?;
        }
        let ids = thread_ids.iter().cloned().collect::<BTreeSet<_>>();
        // Once mutation starts it must retain the lock across atomic replacement, even if
        // the caller is cancelled. close() also waits for this same log lock.
        let writer = self.writer.clone();
        let thread_ids = thread_ids.to_vec();
        let span = tracing::info_span!(
            "calls_delete_threads",
            operation = "permanent_delete_calls",
            thread_count = thread_ids.len(),
        );
        tokio::spawn(
            async move {
                let mut log = writer.log.lock().await;
                log.delete_threads(&writer.db, &ids).await?;
                let tx = writer.db.begin().await?;
                for id in &thread_ids {
                    for table in [
                        "call_log_index",
                        "call_usage_summary",
                        "performance_samples",
                        "legacy_call_fences",
                        "legacy_auxiliary_usage",
                    ] {
                        tx.execute_raw(statement(
                            &format!("DELETE FROM {table} WHERE thread_id=?"),
                            vec![id.clone().into()],
                        ))
                        .await?;
                    }
                }
                tx.commit().await?;
                Ok::<_, anyhow::Error>(())
            }
            .instrument(span),
        )
        .await
        .context("failed to join calls deletion")??;
        Ok(())
    }

    /// 用可靠 writer 的 revision 绝对投影替换某个 root/thread 的累计费用摘要。
    ///
    /// 主代理从 Thread 折叠出的权威累计值（含 purpose 拆分）调用本接口；更小的 revision 被忽略，
    /// 因此重复投递同一投影是幂等的，且摘要不依赖将被删除的日志正文。
    pub(crate) fn replace_session_usage(&self, projection: SessionUsageProjection) -> Result<()> {
        ensure!(
            !self.writer.stopping.load(Ordering::Acquire),
            "call writer is stopping"
        );
        let mutation = CallMutation::Summary(PreparedSummary::new(projection)?);
        let bytes = mutation.estimated_bytes();
        {
            let mut queue = self
                .writer
                .queue
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if let CallMutation::Summary(newest) = &mutation {
                for entry in queue.iter() {
                    if let CallMutation::Summary(previous) = &entry.mutation
                        && previous.thread_id == newest.thread_id
                    {
                        ensure!(
                            previous.revision != newest.revision || previous.hash == newest.hash,
                            "conflicting call summary revision"
                        );
                        if previous.revision >= newest.revision {
                            return Ok(());
                        }
                    }
                }
                queue.retain(|entry| !matches!(&entry.mutation, CallMutation::Summary(previous) if previous.thread_id == newest.thread_id && previous.revision <= newest.revision));
            }
            ensure!(
                queue.len() < MAX_QUEUE_MUTATIONS
                    && queue_bytes(&queue).saturating_add(bytes) <= MAX_QUEUE_BYTES,
                "call summary queue is full"
            );
            queue.push_back(QueuedCallMutation {
                ticket: self.next_ticket(),
                accepted_at: tokio::time::Instant::now(),
                bytes,
                mutation,
            });
            #[cfg(feature = "benchmarks")]
            self.writer
                .observation
                .queue(queue.len(), queue_bytes(&queue));
        }
        self.writer.work_notify.notify_one();
        Ok(())
    }

    /// 当前已受理的最高统计 ticket，供持久化进度观测。
    pub(crate) fn admitted_ticket(&self) -> u64 {
        self.writer.admitted_ticket.load(Ordering::Acquire)
    }

    /// 最近一次调用写入错误（瞬时重试与显式拒绝都会记录，直到一次成功写入清除）。
    pub(crate) fn last_error(&self) -> Option<String> {
        self.writer
            .last_error
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .clone()
    }

    /// 正在写入的一批 mutation 的编码字节数；只读观测，不参与写路径。
    pub(crate) fn in_flight_bytes(&self) -> usize {
        usize::try_from(self.writer.in_flight_bytes.load(Ordering::Acquire)).unwrap_or(usize::MAX)
    }

    /// 当前已处理的最高 ticket；提交或显式拒绝均会推进，不证明成功物化。
    pub(crate) fn processed_ticket(&self) -> u64 {
        *self.writer.processed_ticket.borrow()
    }

    #[cfg(any(test, feature = "benchmarks"))]
    pub(crate) fn subscribe_processed_ticket(&self) -> watch::Receiver<u64> {
        self.writer.processed_ticket.subscribe()
    }

    pub(crate) fn subscribe_materials(&self) -> watch::Receiver<CallsMaterialProgress> {
        self.writer.materials.subscribe()
    }

    /// Best-effort call statistics. Full task identities and deliveries belong to history.sqlite.
    /// An unavailable/full statistics queue never blocks the executing Thread.
    ///
    /// 这里只从 effect 提取轻量调用记录，绝不 clone/encode 整个 [`ThreadEffectBatch`]，
    /// 也不把 context / tools 带进队列。
    pub(crate) fn record_effect(&self, effect: &ThreadEffectBatch) {
        let sequence = i64::try_from(effect.sequence).unwrap_or(i64::MAX);
        let mut records: Vec<_> = effect
            .attempt
            .as_ref()
            .map(|attempt| {
                event::attempt_record(&effect.thread_id, sequence, effect.committed_at, attempt)
            })
            .into_iter()
            .collect();
        records.extend(effect.deliveries.iter().map(|delivery| {
            event::tool_record(
                &effect.thread_id,
                effect
                    .tasks
                    .iter()
                    .find(|task| task.call_id == delivery.call_id)
                    .map(|task| task.turn_id.clone()),
                sequence,
                effect.committed_at,
                delivery,
            )
        }));
        if records.is_empty() {
            return;
        }
        if self.writer.stopping.load(Ordering::Acquire) {
            record_statistics_gap(
                &self.writer,
                "call statistics writer is stopping".to_owned(),
            );
            return;
        }
        let records = match records
            .into_iter()
            .map(PreparedRecord::new)
            .collect::<Result<Vec<_>>>()
        {
            Ok(records) => records,
            Err(error) => {
                record_statistics_gap(&self.writer, error.to_string());
                return;
            }
        };
        #[cfg(feature = "benchmarks")]
        for _ in &records {
            self.writer
                .observation
                .increment(observation::Metric::LogRecordEncode);
        }
        self.enqueue_diagnostic(CallMutation::Records(records));
    }

    pub(crate) fn record_acp_performance(&self, sample: AcpPerformanceObservation) {
        let sample = performance::PerformanceSample {
            thread_id: sample.thread_id,
            call_id: sample.call_id,
            purpose: Some(performance::ACP_TEXT_ESTIMATE.into()),
            usage_status: pl_core::usage::UsageStatus::Partial,
            first_output_source: crate::FirstOutputSource::Unobserved,
            throughput_valid: true,
            completed_at: crate::studio::unix_seconds(),
            account_id: Some(sample.account_id),
            account_display_name: Some(sample.account_name),
            model_id: sample.model,
            sent_model: None,
            reported_model: None,
            effort: sample.effort,
            requested_service_tier: Some("notApplicable".into()),
            output_tokens: opt_i64(sample.performance.estimated_output_tokens),
            ttft_millis: None,
            decode_millis: None,
            response_millis: opt_i64(sample.performance.response_millis),
        };
        self.enqueue_diagnostic(CallMutation::AcpPerformance(Box::new(sample)));
    }

    fn enqueue_diagnostic(&self, mutation: CallMutation) {
        let bytes = mutation.estimated_bytes();
        let admitted = {
            let mut queue = self
                .writer
                .queue
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if self.writer.stopping.load(Ordering::Acquire)
                || queue.len() >= MAX_QUEUE_MUTATIONS
                || queue_bytes(&queue).saturating_add(bytes) > MAX_QUEUE_BYTES
            {
                false
            } else {
                let ticket = self.next_ticket();
                queue.push_back(QueuedCallMutation {
                    ticket,
                    accepted_at: tokio::time::Instant::now(),
                    bytes,
                    mutation,
                });
                #[cfg(feature = "benchmarks")]
                self.writer
                    .observation
                    .queue(queue.len(), queue_bytes(&queue));
                true
            }
        };
        if admitted {
            self.writer.work_notify.notify_one();
        } else {
            record_statistics_gap(
                &self.writer,
                "call statistics queue is full; statistics gap".to_owned(),
            );
        }
    }

    /// 同步受理一次计费观察并把其 ticket 交回调用方。
    ///
    /// 受理只入队、不等待 durability。队列满或写入器停机时返回错误，
    /// 调用方记录统计缺口而不阻塞 Thread 执行。
    pub(crate) fn admit_billing(
        &self,
        root_thread_id: &str,
        thread_id: &str,
        billing: &InferenceBillingRecord,
        status: CallStatus,
        retention: CallRetention,
    ) -> Result<u64> {
        if self.writer.stopping.load(Ordering::Acquire) {
            self.writer.statistics_gap.store(true, Ordering::Release);
            publish_status(&self.writer);
            bail!("call writer is stopping");
        }
        let record = event::billing_record(root_thread_id, thread_id, retention, billing, status);
        let record = PreparedRecord::new(record)?;
        #[cfg(feature = "benchmarks")]
        {
            self.writer
                .observation
                .increment(observation::Metric::BillingEncode);
            self.writer
                .observation
                .increment(observation::Metric::LogRecordEncode);
        }
        let mutation = CallMutation::Billing(Box::new(record));
        let bytes = mutation.estimated_bytes();
        let ticket = {
            let mut queue = self
                .writer
                .queue
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if let CallMutation::Billing(record) = &mutation
                && let Some(tickets) = queue.billing.get(&(
                    record.thread_id.clone(),
                    record.call_id.clone(),
                    record.kind.clone(),
                ))
                && let Some((ticket, hash)) = tickets.first_key_value()
            {
                ensure!(
                    *hash == record.hash,
                    "model call {} conflicts with queued call record",
                    record.call_id
                );
                return Ok(*ticket);
            }
            if queue.len() >= MAX_QUEUE_MUTATIONS
                || queue_bytes(&queue).saturating_add(bytes) > MAX_QUEUE_BYTES
            {
                self.writer.statistics_gap.store(true, Ordering::Release);
                publish_status(&self.writer);
                bail!("call writer queue is full");
            }
            let ticket = self.next_ticket();
            queue.push_back(QueuedCallMutation {
                ticket,
                accepted_at: tokio::time::Instant::now(),
                bytes,
                mutation,
            });
            #[cfg(feature = "benchmarks")]
            self.writer
                .observation
                .queue(queue.len(), queue_bytes(&queue));
            ticket
        };
        self.writer.work_notify.notify_one();
        Ok(ticket)
    }

    /// Stop accepting statistics without waiting for the optional projection to drain.
    pub(crate) fn stop_best_effort(&self) {
        self.writer.stopping.store(true, Ordering::Release);
        self.writer.work_notify.notify_one();
        self.writer.retry_notify.notify_one();
    }

    fn next_ticket(&self) -> u64 {
        self.writer
            .admitted_ticket
            .fetch_add(1, Ordering::AcqRel)
            .wrapping_add(1)
    }

    /// 按 root 会话聚合费用；摘要由可靠 writer 供给，不依赖已被清理的日志正文。
    pub(crate) async fn legacy_auxiliary_usage(
        &self,
        thread_id: &str,
    ) -> Result<pl_core::thread::UsageSummary> {
        match self
            .writer
            .db
            .query_one_raw(statement(
                "SELECT payload FROM legacy_auxiliary_usage WHERE thread_id=?",
                vec![thread_id.into()],
            ))
            .await?
        {
            Some(row) => Ok(serde_json::from_str(
                &row.try_get::<String>("", "payload")?,
            )?),
            None => Ok(Default::default()),
        }
    }

    /// Migration-only baseline, retained independently of disposable diagnostic logs.
    pub(crate) async fn legacy_session_costs(
        &self,
        thread_id: &str,
        fence: u64,
    ) -> Result<Vec<PurposeUsageProjection>> {
        if let Some(row) = self
            .writer
            .db
            .query_one_raw(statement(
                "SELECT durable_write_seq FROM legacy_call_fences WHERE thread_id=?",
                vec![thread_id.into()],
            ))
            .await?
        {
            let durable = u64::try_from(row.try_get::<i64>("", "durable_write_seq")?)?;
            ensure!(
                durable <= fence,
                "legacy call watermark is ahead of checkpoint"
            );
        }
        let rows = self.writer.db.query_all_raw(statement("SELECT purpose,cost_currency,amount FROM call_usage_summary WHERE thread_id=? AND revision=0 AND cost_currency<>''", vec![thread_id.into()])).await?;
        let mut purposes =
            std::collections::BTreeMap::<Option<String>, Vec<RuntimeCostAmount>>::new();
        for row in rows {
            let purpose: String = row.try_get("", "purpose")?;
            purposes
                .entry((!purpose.is_empty()).then_some(purpose))
                .or_default()
                .push(RuntimeCostAmount {
                    currency: row.try_get("", "cost_currency")?,
                    amount: row.try_get("", "amount")?,
                });
        }
        Ok(purposes
            .into_iter()
            .map(|(purpose, estimated_costs)| PurposeUsageProjection {
                purpose,
                estimated_costs,
            })
            .collect())
    }

    #[cfg(any(test, feature = "benchmarks"))]
    pub(crate) async fn session_cost_rollups(&self) -> Result<Vec<SessionCostRollup>> {
        summary::read_rollups(
            &self.writer.db,
            #[cfg(feature = "benchmarks")]
            &self.writer.observation,
        )
        .await
    }

    /// 历史与汇总消费同一有界 SQL 材料，不读取或锁定 JSONL。
    #[cfg(any(test, feature = "benchmarks"))]
    pub(crate) async fn recent_performance_samples(
        &self,
        limit: u32,
    ) -> Result<Vec<PerformanceSampleRow>> {
        #[cfg(feature = "benchmarks")]
        {
            self.writer.observation.recent_read_started();
            self.writer
                .observation
                .increment(observation::Metric::RecentIndexSql);
        }
        performance::read_history(&self.writer.db, limit).await
    }

    pub(crate) async fn read_statistics(
        &self,
        request: StatisticsReadRequest,
    ) -> Result<CallsStatisticsRead> {
        let tx = self.writer.db.begin().await?;
        let costs = if request.costs {
            Some(
                summary::read_rollups(
                    &tx,
                    #[cfg(feature = "benchmarks")]
                    &self.writer.observation,
                )
                .await?,
            )
        } else {
            None
        };
        let (history, summary) = if request.performance {
            #[cfg(feature = "benchmarks")]
            {
                self.writer.observation.recent_read_started();
                self.writer
                    .observation
                    .increment(observation::Metric::RecentIndexSql);
                self.writer
                    .observation
                    .increment(observation::Metric::PerformanceSummarySql);
            }
            (
                Some(performance::read_history(&tx, PERFORMANCE_SAMPLE_LIMIT as u32).await?),
                Some(performance::read_summary(&tx).await?),
            )
        } else {
            (None, None)
        };
        tx.commit().await?;
        Ok(CallsStatisticsRead {
            costs,
            history,
            summary,
        })
    }
}
fn performance_summary_row(row: &QueryResult) -> Result<PerformanceSummaryRow> {
    Ok(PerformanceSummaryRow {
        account_id: row.try_get("", "account_id")?,
        account_display_name: row.try_get("", "account_display_name")?,
        model_id: row.try_get("", "model_id")?,
        effort: row.try_get("", "effort")?,
        requested_service_tier: row.try_get("", "requested_service_tier")?,
        sample_count: required_u64(row, "sample_count")?,
        completion_tokens: required_u64(row, "completion_tokens")?,
        total_ttft_millis: required_u64(row, "total_ttft_millis")?,
        ttft_sample_count: required_u64(row, "ttft_sample_count")?,
        total_response_millis: required_u64(row, "total_response_millis")?,
    })
}

fn attempt_status(outcome: &AttemptOutcome) -> CallStatus {
    match outcome {
        AttemptOutcome::Running => CallStatus::Running,
        AttemptOutcome::Interrupted => CallStatus::Interrupted,
        AttemptOutcome::Committed(_) => CallStatus::Committed,
        AttemptOutcome::Cancelled { .. } => CallStatus::Cancelled,
        AttemptOutcome::Failed(_) => CallStatus::Failed,
        AttemptOutcome::Rejected { .. } => CallStatus::Rejected,
    }
}

fn outcome_usage(outcome: &AttemptOutcome) -> Option<&ModelUsage> {
    match outcome {
        AttemptOutcome::Running | AttemptOutcome::Interrupted => None,
        AttemptOutcome::Committed(output) | AttemptOutcome::Rejected { output, .. } => {
            Some(&output.usage)
        }
        AttemptOutcome::Failed(error) => Some(&error.usage),
        AttemptOutcome::Cancelled { result } => Some(match result {
            Ok(output) => &output.usage,
            Err(error) => &error.usage,
        }),
    }
}

fn opt_i64(value: u64) -> Option<i64> {
    i64::try_from(value).ok()
}

fn required_u64(row: &QueryResult, column: &str) -> Result<u64> {
    let value: Option<i64> = row.try_get("", column)?;
    Ok(value
        .and_then(|value| u64::try_from(value).ok())
        .unwrap_or(0))
}

fn statement(sql: &str, values: Vec<Value>) -> Statement {
    Statement::from_sql_and_values(DatabaseBackend::Sqlite, sql, values)
}

fn integer(value: u64) -> Result<i64> {
    value
        .try_into()
        .map_err(|_| anyhow::anyhow!("call write sequence exceeds SQLite range"))
}

#[cfg(test)]
mod storage_fault_tests;

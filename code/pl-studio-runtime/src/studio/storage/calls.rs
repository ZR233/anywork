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

use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::{Context, Result, bail, ensure};
use pl_core::model::ModelUsage;
use pl_core::thread::journal::AttemptUpdate;
use pl_core::thread::{AttemptOutcome, ThreadEffectBatch};
use pl_protocol::{InferenceBillingRecord, RuntimeCostAmount};
use sea_orm::sqlx::sqlite::{SqliteJournalMode, SqliteSynchronous};
use sea_orm::{
    ConnectionTrait, Database, DatabaseBackend, DatabaseConnection, DatabaseTransaction,
    QueryResult, Statement, TransactionTrait, Value,
};
use tokio::sync::{Notify, watch};

use crate::hash::merge_costs;

mod event;
mod log;
#[cfg(feature = "benchmarks")]
pub(crate) mod observation;
mod performance;
mod schema;
mod summary;

pub(crate) use performance::PERFORMANCE_SAMPLE_LIMIT;
pub(crate) use summary::{PurposeUsageProjection, SessionUsageProjection};

use event::CallLogRecord;
use log::{CallLog, LOG_CLEANUP_INTERVAL};

pub(crate) const CALLS_SCHEMA_VERSION: i64 = 8;
/// `calls` 目录下日志段所在子目录名。
const CALL_LOG_DIR_NAME: &str = "logs";
/// 一天对应的秒数；日志轮转/保留期以 UTC 自然日为准。
pub(super) const SECONDS_PER_DAY: i64 = 86_400;
/// 单批最多应用的 mutation 数。
const MAX_BATCH_MUTATIONS: usize = 64;
/// 单批最多聚合的字节预算。
const MAX_BATCH_BYTES: usize = 4 * 1024 * 1024;
/// 队列条目数软上限；达到后受理方等待 writer 腾出空间。
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
    pub(crate) completion_tokens: Option<u64>,
    pub(crate) usage_status: pl_core::usage::UsageStatus,
    pub(crate) first_output_source: pl_protocol::FirstOutputSource,
    pub(crate) ttft_millis: Option<u64>,
    pub(crate) decode_millis: Option<u64>,
    pub(crate) response_millis: Option<u64>,
    pub(crate) has_throughput_sample: bool,
}

/// 按（账号、冻结的目录配置模型、推理强度）的数据库聚合分组。
///
/// 顶层统计身份是 (account_id, model_id)；`effort` 是组内二级细分。发送/返回模型
/// 只是冻结诊断，不参与归组。
#[derive(Debug, Clone)]
pub(crate) struct PerformanceSummaryRow {
    pub(crate) account_id: String,
    pub(crate) account_display_name: String,
    pub(crate) model_id: String,
    pub(crate) effort: Option<String>,
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

/// Directed absolute progress for one Thread. `materialized_sequence` is the latest successful
/// effect, not a claim that a rejected earlier effect was saved; `statistics_gap` retains that fact.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub(crate) struct CallsThreadProgress {
    pub(crate) processed_sequence: u64,
    pub(crate) materialized_sequence: u64,
    pub(crate) statistics_gap: bool,
    pub(crate) retrying: bool,
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

/// 受理一次调用写入的轻量工作单元。
enum CallMutation {
    /// 一次 effect：可能携带一条轻量 attempt 记录；无论是否携带都要推进该 Thread 的 durable 水位。
    Effect {
        thread_id: String,
        sequence: i64,
        records: Vec<PreparedRecord>,
    },
    Billing(Box<PreparedRecord>),
    Summary(PreparedSummary),
}

impl CallMutation {
    /// 估算条目保留字节，用于队列与批次的压力预算；只序列化轻量记录。
    fn estimated_bytes(&self) -> usize {
        match self {
            Self::Effect { records, .. } => {
                128 + records
                    .iter()
                    .map(|record| record.line.len() + 1)
                    .sum::<usize>()
            }
            Self::Billing(record) => record.line.len() + 1,
            Self::Summary(projection) => projection.bytes,
        }
    }
}

struct PreparedSummary {
    projection: SessionUsageProjection,
    hash: String,
    bytes: usize,
}
impl std::ops::Deref for PreparedSummary {
    type Target = SessionUsageProjection;
    fn deref(&self) -> &Self::Target {
        &self.projection
    }
}
impl PreparedSummary {
    fn new(projection: SessionUsageProjection) -> Result<Self> {
        let encoded = serde_json::to_vec(&projection)?;
        Ok(Self {
            projection,
            hash: pl_core::context::content_hash(&encoded),
            bytes: encoded.len(),
        })
    }
}

/// The final (possibly truncated) fact and its bytes are selected before the queue lock.
/// SQL identity checks, JSONL and samples all consume this same fact.
struct PreparedRecord {
    record: CallLogRecord,
    line: String,
    hash: String,
    truncated: bool,
}

impl std::ops::Deref for PreparedRecord {
    type Target = CallLogRecord;
    fn deref(&self) -> &Self::Target {
        &self.record
    }
}

impl PreparedRecord {
    fn new(mut record: CallLogRecord) -> Result<Self> {
        let mut line = serde_json::to_string(&record)?;
        if line.len() >= event::CALL_LOG_RECORD_MAX_BYTES {
            record = record.truncated_fallback();
            line = serde_json::to_string(&record)?;
        }
        ensure!(
            line.len() < event::CALL_LOG_RECORD_MAX_BYTES,
            "call identity exceeds log record budget"
        );
        let hash = pl_core::context::content_hash(line.as_bytes());
        let truncated = record.truncated;
        Ok(Self {
            record,
            line,
            hash,
            truncated,
        })
    }
}

#[derive(Default)]
struct MutationQueue {
    entries: VecDeque<QueuedCallMutation>,
    bytes: usize,
    billing: BTreeMap<(String, String, String), BTreeMap<u64, String>>,
}
impl std::ops::Deref for MutationQueue {
    type Target = VecDeque<QueuedCallMutation>;
    fn deref(&self) -> &Self::Target {
        &self.entries
    }
}
impl MutationQueue {
    fn push_back(&mut self, entry: QueuedCallMutation) {
        self.index_billing(&entry);
        self.bytes += entry.bytes;
        self.entries.push_back(entry);
    }
    fn push_front(&mut self, entry: QueuedCallMutation) {
        self.index_billing(&entry);
        self.bytes += entry.bytes;
        self.entries.push_front(entry);
    }
    fn pop_front(&mut self) -> Option<QueuedCallMutation> {
        let entry = self.entries.pop_front()?;
        self.bytes -= entry.bytes;
        if let CallMutation::Billing(record) = &entry.mutation {
            let key = (
                record.thread_id.clone(),
                record.call_id.clone(),
                record.kind.clone(),
            );
            if let Some(tickets) = self.billing.get_mut(&key) {
                tickets.remove(&entry.ticket);
                if tickets.is_empty() {
                    self.billing.remove(&key);
                }
            }
        }
        Some(entry)
    }
    fn index_billing(&mut self, entry: &QueuedCallMutation) {
        if let CallMutation::Billing(record) = &entry.mutation {
            self.billing
                .entry((
                    record.thread_id.clone(),
                    record.call_id.clone(),
                    record.kind.clone(),
                ))
                .or_default()
                .insert(entry.ticket, record.hash.clone());
        }
    }
    fn retain(&mut self, mut keep: impl FnMut(&QueuedCallMutation) -> bool) {
        let bytes = &mut self.bytes;
        let billing = &mut self.billing;
        self.entries.retain(|entry| {
            if keep(entry) {
                true
            } else {
                *bytes -= entry.bytes;
                if let CallMutation::Billing(record) = &entry.mutation {
                    let key = (
                        record.thread_id.clone(),
                        record.call_id.clone(),
                        record.kind.clone(),
                    );
                    if let Some(tickets) = billing.get_mut(&key) {
                        tickets.remove(&entry.ticket);
                        if tickets.is_empty() {
                            billing.remove(&key);
                        }
                    }
                }
                false
            }
        });
    }
}

struct QueuedCallMutation {
    ticket: u64,
    accepted_at: tokio::time::Instant,
    bytes: usize,
    mutation: CallMutation,
}

/// 不可重试的批量失败；保留消息用于错误上报与诊断。
#[derive(Debug)]
struct BatchFailure {
    message: String,
    retryable: bool,
}

#[derive(Default)]
struct MaterialChanges {
    performance: bool,
    costs: bool,
    status: bool,
}

#[derive(Debug, Clone, Copy, Default)]
struct QueuePressure {
    mutations: usize,
    bytes: usize,
    oldest_accepted_at: Option<tokio::time::Instant>,
}

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
    durable_ticket: watch::Sender<u64>,
    materials: watch::Sender<CallsMaterialProgress>,
    threads: Mutex<BTreeMap<String, Arc<ThreadProgressSubscription>>>,
    /// Encoded bytes of the batch currently being written; a read-only pressure observation.
    in_flight_bytes: AtomicU64,
    stopping: AtomicBool,
    last_error: Mutex<Option<String>>,
    statistics_gap: AtomicBool,
    #[cfg(test)]
    panic_next_mutation: AtomicBool,
    #[cfg(test)]
    subscribe_gate: Mutex<Option<Arc<SubscribeGate>>>,
}

struct ThreadProgressSubscription {
    sender: watch::Sender<CallsThreadProgress>,
    /// Tokio hands a cancelled/failed initialization to another waiter. Presence in
    /// the map alone proves nothing; only a completed SQL merge initializes this cell.
    initialized: tokio::sync::OnceCell<()>,
}

#[cfg(test)]
#[derive(Default)]
struct SubscribeGate {
    registered: Notify,
    loaded: Notify,
    resume: Notify,
    paused_once: AtomicBool,
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
        super::coordinator::CallsQueueMetrics {
            admitted_sequence: self.admitted_ticket(),
            durable_sequence: self.durable_ticket(),
            pending_operations: u64::try_from(self.pending_count()).unwrap_or(u64::MAX),
            pending_bytes: u64::try_from(self.pending_bytes()).unwrap_or(u64::MAX),
            in_flight_bytes: u64::try_from(self.in_flight_bytes()).unwrap_or(u64::MAX),
            oldest_pending_age_millis: self
                .oldest_pending_age()
                .map(|age| u64::try_from(age.as_millis()).unwrap_or(u64::MAX)),
            last_error: self.last_error(),
            pressure_paused: self.pressure_paused(),
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

    #[cfg(test)]
    pub(crate) fn panic_on_next_mutation(&self) {
        self.writer
            .panic_next_mutation
            .store(true, Ordering::Release);
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
        let (durable_ticket, _) = watch::channel(0u64);
        let writer = Arc::new(CallsWriter {
            db,
            #[cfg(feature = "benchmarks")]
            observation: log.observation.clone(),
            log: tokio::sync::Mutex::new(log),
            queue: Mutex::new(MutationQueue::default()),
            work_notify: Notify::new(),
            retry_notify: Notify::new(),
            admitted_ticket: AtomicU64::new(0),
            durable_ticket,
            materials: watch::channel(CallsMaterialProgress {
                statistics_gap: false,
                last_error: startup_error.clone(),
                ..Default::default()
            })
            .0,
            threads: Mutex::new(BTreeMap::new()),
            in_flight_bytes: AtomicU64::new(0),
            stopping: AtomicBool::new(false),
            statistics_gap: AtomicBool::new(false),
            last_error: Mutex::new(startup_error),
            #[cfg(test)]
            panic_next_mutation: AtomicBool::new(false),
            #[cfg(test)]
            subscribe_gate: Mutex::new(None),
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

    /// 当前尚未落库的 mutation 数；关机进度与压力观测使用。
    pub(crate) fn pending_count(&self) -> usize {
        self.writer
            .queue
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .len()
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

    /// 调用库是否因队列压力停止接受新的计费/调用事实。
    ///
    /// 门槛与 `admit_billing` 的拒绝条件一致，因此这是"下一步受理会不会被拒绝"的真实观测，
    /// 不是占位值。
    pub(crate) fn pressure_paused(&self) -> bool {
        let queue = self
            .writer
            .queue
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        queue.len() >= MAX_QUEUE_MUTATIONS || queue_bytes(&queue) >= MAX_QUEUE_BYTES
    }

    /// 当前已落库的最高 ticket，作为调用库 durable sequence 的观测值。
    pub(crate) fn durable_ticket(&self) -> u64 {
        *self.writer.durable_ticket.borrow()
    }

    #[cfg(any(test, feature = "benchmarks"))]
    pub(crate) fn subscribe_durable_ticket(&self) -> watch::Receiver<u64> {
        self.writer.durable_ticket.subscribe()
    }

    pub(crate) fn subscribe_materials(&self) -> watch::Receiver<CallsMaterialProgress> {
        self.writer.materials.subscribe()
    }

    pub(crate) async fn subscribe_thread_progress(
        &self,
        thread_id: &str,
    ) -> Result<watch::Receiver<CallsThreadProgress>> {
        let (subscription, receiver) = {
            let mut threads = self
                .writer
                .threads
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            threads.retain(|_, subscription| subscription.sender.receiver_count() > 0);
            if let Some(subscription) = threads.get(thread_id) {
                (subscription.clone(), subscription.sender.subscribe())
            } else {
                let (sender, receiver) = watch::channel(CallsThreadProgress::default());
                let subscription = Arc::new(ThreadProgressSubscription {
                    sender,
                    initialized: tokio::sync::OnceCell::new(),
                });
                threads.insert(thread_id.to_owned(), subscription.clone());
                (subscription, receiver)
            }
        };
        #[cfg(test)]
        let gate = self.writer.subscribe_gate.lock().unwrap().clone();
        #[cfg(test)]
        if let Some(gate) = &gate {
            gate.registered.notify_one();
        }
        subscription
            .initialized
            .get_or_try_init(|| async {
                // Registered before SQL: a writer can publish while this read is in flight.
                // Merge maxima instead of replacing a possibly newer writer observation.
                let sequence = self.durable_effect_sequence(thread_id).await?;
                #[cfg(test)]
                if let Some(gate) = gate
                    && !gate.paused_once.swap(true, Ordering::AcqRel)
                {
                    gate.loaded.notify_one();
                    gate.resume.notified().await;
                }
                subscription.sender.send_if_modified(|progress| {
                    let previous = progress.clone();
                    progress.processed_sequence = progress.processed_sequence.max(sequence);
                    progress.materialized_sequence = progress.materialized_sequence.max(sequence);
                    *progress != previous
                });
                Ok::<(), anyhow::Error>(())
            })
            .await?;
        Ok(receiver)
    }

    /// Reads the committed effect watermark for one Thread, independently of global queue tickets.
    pub(crate) async fn durable_effect_sequence(&self, thread_id: &str) -> Result<u64> {
        #[cfg(feature = "benchmarks")]
        self.writer
            .observation
            .increment(observation::Metric::WatermarkReadSql);
        let row = self
            .writer
            .db
            .query_one_raw(statement(
                "SELECT durable_write_seq FROM call_watermarks WHERE thread_id=?",
                vec![thread_id.into()],
            ))
            .await?;
        row.map(|row| {
            let value: i64 = row.try_get("", "durable_write_seq")?;
            u64::try_from(value).map_err(Into::into)
        })
        .transpose()
        .map(|value| value.unwrap_or(0))
    }

    /// 排队 mutation 的编码字节数合计，作为调用库 pending bytes 的观测值。
    pub(crate) fn pending_bytes(&self) -> usize {
        let queue = self
            .writer
            .queue
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        queue_bytes(&queue)
    }

    /// 最老排队 mutation 的等待时长；无排队时为 `None`。
    pub(crate) fn oldest_pending_age(&self) -> Option<std::time::Duration> {
        let queue = self
            .writer
            .queue
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        queue.front().map(|entry| entry.accepted_at.elapsed())
    }

    /// Best-effort call statistics. Full task identities and deliveries belong to history.sqlite.
    /// An unavailable/full statistics queue never blocks the executing Thread.
    ///
    /// 这里只从 effect 提取轻量调用记录，绝不 clone/encode 整个 [`ThreadEffectBatch`]，
    /// 也不把 context / tools 带进队列。
    pub(crate) fn try_admit_effect(&self, effect: &ThreadEffectBatch) -> bool {
        if self.writer.stopping.load(Ordering::Acquire) {
            record_statistics_gap(
                &self.writer,
                "call statistics writer is stopping".to_owned(),
            );
            publish_thread(
                &self.writer,
                &effect.thread_id,
                effect.sequence,
                false,
                false,
                Some("call statistics writer is stopping".to_owned()),
            );
            return false;
        }
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
        let records = match records
            .into_iter()
            .map(PreparedRecord::new)
            .collect::<Result<Vec<_>>>()
        {
            Ok(records) => records,
            Err(error) => {
                record_statistics_gap(&self.writer, error.to_string());
                publish_thread(
                    &self.writer,
                    &effect.thread_id,
                    effect.sequence,
                    false,
                    false,
                    Some(error.to_string()),
                );
                return false;
            }
        };
        #[cfg(feature = "benchmarks")]
        for _ in &records {
            self.writer
                .observation
                .increment(observation::Metric::LogRecordEncode);
        }
        let mutation = CallMutation::Effect {
            thread_id: effect.thread_id.clone(),
            sequence,
            records,
        };
        let bytes = mutation.estimated_bytes();
        let admitted = {
            let mut queue = self
                .writer
                .queue
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            if queue.len() >= MAX_QUEUE_MUTATIONS
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
            publish_thread(
                &self.writer,
                &effect.thread_id,
                effect.sequence,
                false,
                false,
                Some("call statistics queue is full".to_owned()),
            );
        }
        admitted
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
        let watermark = self.durable_effect_sequence(thread_id).await?;
        ensure!(
            watermark <= fence,
            "legacy call watermark is ahead of checkpoint"
        );
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

/// writer supervisor：worker panic 后重启；在途事实由等待方重试，不会被静默丢弃。
async fn supervise_writer(shared: Arc<CallsWriter>) {
    loop {
        let worker = tokio::spawn(run_writer(shared.clone()));
        let Err(error) = worker.await else {
            return;
        };
        let message = format!("call writer terminated unexpectedly: {error}");
        if shared.in_flight_bytes.swap(0, Ordering::AcqRel) > 0 {
            record_statistics_gap(&shared, message);
        } else {
            record_last_error(&shared, message);
        }
        if shared.stopping.load(Ordering::Acquire) {
            return;
        }
        tokio::time::sleep(Duration::from_secs(1)).await;
        if shared.stopping.load(Ordering::Acquire) {
            return;
        }
    }
}

/// 唯一的调用库写入循环：取批、应用、重试、推进水位，并周期性清理日志。
async fn run_writer(shared: Arc<CallsWriter>) {
    let mut retries = 0usize;
    // 周期清理以绝对截止时间为准，即使队列一直非空（写入/重试未停）也会到点清理，
    // 避免文档承诺的“每 15 分钟清理”被持续压力饿死。
    let mut next_cleanup = tokio::time::Instant::now() + LOG_CLEANUP_INTERVAL;
    loop {
        if tokio::time::Instant::now() >= next_cleanup {
            next_cleanup = tokio::time::Instant::now() + LOG_CLEANUP_INTERVAL;
            let mut log = shared.log.lock().await;
            if let Err(error) = maintenance(&shared.db, &mut log).await {
                record_last_error(&shared, format!("call log cleanup failed: {error}"));
            }
        }
        let stopping = shared.stopping.load(Ordering::Acquire);
        let pressure = queue_pressure(&shared);
        if pressure.mutations == 0 {
            if stopping {
                return;
            }
            tokio::select! {
                _ = shared.work_notify.notified() => continue,
                // 到点后唤醒执行顶部截止时间检查，而不是在空闲分支里重复清理逻辑。
                _ = tokio::time::sleep_until(next_cleanup) => continue,
            }
        }
        if pressure.bytes >= MAX_QUEUE_BYTES {
            tracing::warn!(
                mutations = pressure.mutations,
                bytes = pressure.bytes,
                oldest_age_ms = pressure
                    .oldest_accepted_at
                    .map_or(0, |oldest| oldest.elapsed().as_millis() as u64),
                "call writer queue is under pressure"
            );
        }
        let mut pending: VecDeque<QueuedCallMutation> = drain_batch(&shared).into();
        if pending.is_empty() {
            continue;
        }
        let batch_bytes = pending.iter().fold(0u64, |total, entry| {
            total.saturating_add(entry.bytes as u64)
        });
        shared.in_flight_bytes.store(batch_bytes, Ordering::Release);
        let deferred = match apply_batch(&shared, &pending).await {
            Ok((completed, failures, deferred)) => {
                if completed > 0 {
                    retries = 0;
                    clear_last_error(&shared);
                    for failure in failures {
                        fail_mutation(&shared, &failure);
                    }
                    let ticket = pending[completed - 1].ticket;
                    pending.drain(..completed);
                    // No receipt may outrun the commit of the outer transaction.
                    advance_durable(&shared, ticket);
                }
                deferred
            }
            Err(error) => Some(classify_failure(error)),
        };
        // 本批已处理完（含退回队首的 deferred 条目），不再有 in-flight 字节。
        shared.in_flight_bytes.store(0, Ordering::Release);
        let Some(failure) = deferred else {
            continue;
        };
        record_last_error(&shared, failure.message.clone());
        if !failure.retryable || shared.stopping.load(Ordering::Acquire) {
            fail_mutation(&shared, &failure.message);
            for entry in &pending {
                if let CallMutation::Effect {
                    thread_id,
                    sequence,
                    ..
                } = &entry.mutation
                {
                    publish_thread(
                        &shared,
                        thread_id,
                        *sequence as u64,
                        false,
                        false,
                        Some(failure.message.clone()),
                    );
                }
            }
            if let Some(last) = pending.back() {
                advance_durable(&shared, last.ticket);
            }
            continue;
        }
        for entry in &pending {
            if let CallMutation::Effect {
                thread_id,
                sequence,
                ..
            } = &entry.mutation
            {
                publish_thread(
                    &shared,
                    thread_id,
                    *sequence as u64,
                    false,
                    true,
                    Some(failure.message.clone()),
                );
            }
        }
        requeue(&shared, pending);
        retries = retries.saturating_add(1);
        if shared.stopping.load(Ordering::Acquire) {
            tokio::task::yield_now().await;
            continue;
        }
        let backoff = if retries <= FAST_RETRIES {
            RETRY_BACKOFF * u32::try_from(retries).unwrap_or(u32::MAX)
        } else {
            let exponent = u32::try_from(retries.saturating_sub(FAST_RETRIES + 1))
                .unwrap_or(u32::MAX)
                .min(5);
            Duration::from_secs(1u64 << exponent).min(MAX_RETRY_BACKOFF)
        };
        tracing::warn!(
            attempt = retries,
            error = failure.message,
            "call writer retrying after a transient failure"
        );
        wait_for_retry(&shared, backoff).await;
    }
}

/// 清理日志并回收索引；周期任务与启动路径共用。
async fn maintenance(db: &DatabaseConnection, log: &mut CallLog) -> Result<()> {
    let outcome = log.cleanup(crate::studio::unix_seconds()).await;
    if !outcome.removed.is_empty() {
        let tx = db.begin().await?;
        prune_index(&tx, &outcome.removed).await?;
        tx.commit().await?;
    }
    if let Some(failure) = outcome.failure {
        return Err(failure).context("call log cleanup incomplete");
    }
    let root_dir = log.root_dir();
    schema::retry_pending_cleanup(db, &root_dir).await?;
    Ok(())
}

/// Merge only contiguous empty effects for one Thread. Every other mutation
/// terminates the run because its savepoint can split the committed prefix.
fn empty_effect_runs(pending: &VecDeque<QueuedCallMutation>) -> Vec<Option<(usize, i64)>> {
    let mut runs = vec![None; pending.len()];
    let mut index = 0;
    while index < pending.len() {
        let CallMutation::Effect {
            thread_id,
            sequence,
            records,
        } = &pending[index].mutation
        else {
            index += 1;
            continue;
        };
        if !records.is_empty() {
            index += 1;
            continue;
        }
        let first = index;
        let mut highest = *sequence;
        index += 1;
        while let Some(entry) = pending.get(index) {
            match &entry.mutation {
                CallMutation::Effect {
                    thread_id: next_thread,
                    sequence,
                    records,
                } if next_thread == thread_id && records.is_empty() => {
                    highest = highest.max(*sequence);
                    index += 1;
                }
                _ => break,
            }
        }
        // No fallible mutation exists inside this run after its first savepoint.
        // Never carry a later empty effect across another run or mutation boundary.
        runs[first..index].fill(Some((first, highest)));
    }
    runs
}

/// One disk commit per bounded batch. Each mutation uses a savepoint, so a bad statistics fact
/// cannot poison the remaining valid facts; a transient failure leaves that suffix queued.
async fn apply_batch(
    shared: &CallsWriter,
    pending: &VecDeque<QueuedCallMutation>,
) -> Result<(usize, Vec<String>, Option<BatchFailure>)> {
    #[cfg(feature = "benchmarks")]
    let lock_started = std::time::Instant::now();
    let mut log = shared.log.lock().await;
    #[cfg(feature = "benchmarks")]
    shared
        .observation
        .lock_acquired(false, lock_started.elapsed());
    let tx = shared.db.begin().await?;
    let mut completed = 0;
    let mut failures = Vec::new();
    let mut deferred = None;
    let mut changes = MaterialChanges::default();
    let mut outcomes = Vec::new();
    let mut summaries = BTreeMap::<&str, (usize, usize)>::new();
    let mut summary_identities = BTreeMap::<(&str, u64), &str>::new();
    let mut summary_conflicts = BTreeSet::new();
    let empty_effects = empty_effect_runs(pending);
    for (index, entry) in pending.iter().enumerate() {
        if let CallMutation::Summary(summary) = &entry.mutation {
            if let Some(hash) =
                summary_identities.get(&(summary.thread_id.as_str(), summary.revision))
                && *hash != summary.hash
            {
                summary_conflicts.insert(index);
                continue;
            }
            summary_identities.insert((&summary.thread_id, summary.revision), &summary.hash);
            let previous = summaries.get(summary.thread_id.as_str()).copied();
            if previous.is_none_or(|(_, previous)| {
                let CallMutation::Summary(old) = &pending[previous].mutation else {
                    unreachable!()
                };
                summary.revision > old.revision
            }) {
                summaries.insert(
                    &summary.thread_id,
                    (previous.map_or(index, |(first, _)| first), index),
                );
            }
        }
    }
    for (index, entry) in pending.iter().enumerate() {
        #[cfg(test)]
        if shared.panic_next_mutation.swap(false, Ordering::AcqRel) {
            panic!("injected call statistics consumer exit");
        }
        let result = match &entry.mutation {
            CallMutation::Summary(summary) => {
                if summary_conflicts.contains(&index) {
                    Err(classify_failure(anyhow::anyhow!(
                        "conflicting call summary revision"
                    )))
                } else {
                    let (first, newest) = summaries[summary.thread_id.as_str()];
                    if first == index {
                        apply_mutation(&mut log, &tx, &pending[newest].mutation).await
                    } else {
                        Ok(MaterialChanges::default())
                    }
                }
            }
            CallMutation::Effect {
                thread_id, records, ..
            } if records.is_empty() => {
                let (first, sequence) =
                    empty_effects[index].expect("empty effect belongs to a run");
                if first != index {
                    Ok(MaterialChanges::default())
                } else {
                    apply_mutation(
                        &mut log,
                        &tx,
                        &CallMutation::Effect {
                            thread_id: thread_id.clone(),
                            sequence,
                            records: Vec::new(),
                        },
                    )
                    .await
                }
            }
            _ => apply_mutation(&mut log, &tx, &entry.mutation).await,
        };
        match result {
            Ok(change) => {
                changes.performance |= change.performance;
                changes.costs |= change.costs;
                changes.status |= change.status;
                outcomes.push(None);
            }
            Err(failure) if failure.retryable => {
                deferred = Some(failure);
                break;
            }
            Err(failure) => {
                outcomes.push(Some(failure.message.clone()));
                failures.push(failure.message);
            }
        }
        completed += 1;
    }
    if changes.performance {
        #[cfg(feature = "benchmarks")]
        shared
            .observation
            .increment(observation::Metric::PerformanceTrimSql);
        performance::trim(&tx).await?;
    }
    // Includes complete orphan lines left by failed savepoints. No SQL success or receipt
    // can escape before every segment touched by this batch crosses its file barrier.
    log.sync_pending().await?;
    tx.commit().await?;
    #[cfg(feature = "benchmarks")]
    shared
        .observation
        .increment(observation::Metric::BatchCommit);
    for (index, entry) in pending.iter().take(completed).enumerate() {
        if let CallMutation::Effect {
            thread_id,
            sequence,
            ..
        } = &entry.mutation
        {
            let error = if let Some((first, _)) = empty_effects[index] {
                outcomes[first].clone()
            } else {
                outcomes[index].clone()
            };
            let material_sequence = if let Some((_, highest)) = empty_effects[index] {
                highest
            } else {
                *sequence
            };
            publish_thread(
                shared,
                thread_id,
                material_sequence as u64,
                error.is_none(),
                false,
                error,
            );
        }
    }
    shared.materials.send_if_modified(|progress| {
        if changes.performance {
            progress.versions.performance += 1;
        }
        if changes.costs {
            progress.versions.costs += 1;
        }
        if changes.status {
            progress.versions.status += 1;
        }
        changes.performance || changes.costs || changes.status
    });
    Ok((completed, failures, deferred))
}

async fn wait_for_retry(shared: &CallsWriter, backoff: Duration) {
    tokio::select! {
        _ = shared.retry_notify.notified() => {}
        _ = tokio::time::sleep(backoff) => {}
    }
}

/// 从队首按条目/字节预算取一批 entry；保持 FIFO 顺序。
fn drain_batch(shared: &CallsWriter) -> Vec<QueuedCallMutation> {
    let mut queue = shared
        .queue
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    let mut entries = Vec::with_capacity(MAX_BATCH_MUTATIONS.min(queue.len().max(1)));
    let mut bytes = 0usize;
    while entries.len() < MAX_BATCH_MUTATIONS {
        let Some(front) = queue.front() else {
            break;
        };
        let next_bytes = bytes.saturating_add(front.bytes);
        if !entries.is_empty() && next_bytes > MAX_BATCH_BYTES {
            break;
        }
        bytes = next_bytes;
        #[cfg(feature = "benchmarks")]
        shared.observation.dequeued(front.accepted_at.elapsed());
        entries.push(queue.pop_front().expect("front entry checked"));
    }
    entries
}

/// 瞬时失败后把未完成条目按原顺序放回队首等待重试。
fn requeue(shared: &CallsWriter, entries: VecDeque<QueuedCallMutation>) {
    let mut queue = shared
        .queue
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    for entry in entries.into_iter().rev() {
        queue.push_front(entry);
    }
}

/// 一次受理得到结论（提交或显式拒绝）后推进耐久 ticket 水位。
fn advance_durable(shared: &CallsWriter, ticket: u64) {
    let current = *shared.durable_ticket.borrow();
    if ticket > current {
        shared.durable_ticket.send_replace(ticket);
    }
    shared.materials.send_if_modified(|progress| {
        if ticket <= progress.processed_ticket {
            return false;
        }
        progress.processed_ticket = ticket;
        true
    });
}

fn publish_thread(
    shared: &CallsWriter,
    thread_id: &str,
    sequence: u64,
    succeeded: bool,
    retrying: bool,
    error: Option<String>,
) {
    let sender = {
        let mut threads = shared
            .threads
            .lock()
            .unwrap_or_else(|error| error.into_inner());
        if threads
            .get(thread_id)
            .is_some_and(|subscription| subscription.sender.receiver_count() == 0)
        {
            threads.remove(thread_id);
            return;
        }
        threads
            .get(thread_id)
            .map(|subscription| subscription.sender.clone())
    };
    if let Some(sender) = sender {
        sender.send_if_modified(|progress| {
            let previous = progress.clone();
            if !retrying {
                progress.processed_sequence = progress.processed_sequence.max(sequence);
            }
            if succeeded {
                progress.materialized_sequence = progress.materialized_sequence.max(sequence);
            }
            if error.is_some() && !retrying {
                progress.statistics_gap = true;
            }
            progress.retrying = retrying;
            progress.last_error = error;
            *progress != previous
        });
    }
}

fn publish_status(shared: &CallsWriter) {
    let error = shared
        .last_error
        .lock()
        .unwrap_or_else(|error| error.into_inner())
        .clone();
    let gap = shared.statistics_gap.load(Ordering::Acquire);
    shared.materials.send_if_modified(|progress| {
        if progress.last_error == error && progress.statistics_gap == gap {
            return false;
        }
        progress.last_error = error;
        progress.statistics_gap = gap;
        progress.versions.status += 1;
        true
    });
}

fn fail_mutation(shared: &CallsWriter, message: &str) {
    tracing::error!(error = message, "call writer rejected a call fact");
    record_statistics_gap(shared, message.to_owned());
}

fn record_statistics_gap(shared: &CallsWriter, message: String) {
    shared.statistics_gap.store(true, Ordering::Release);
    record_last_error(shared, message);
}

/// An operation error is not evidence that an accounting fact was discarded.
/// Retained retry work and retryable maintenance errors must not latch a gap.
fn record_last_error(shared: &CallsWriter, message: String) {
    tracing::error!(error = message, "call writer is degraded");
    *shared
        .last_error
        .lock()
        .unwrap_or_else(|error| error.into_inner()) = Some(message);
    publish_status(shared);
}

/// A durable write succeeded, so the previously recorded degradation no longer describes the
/// writer. The error is retained until this point instead of clearing on admission or retry.
fn clear_last_error(shared: &CallsWriter) {
    *shared
        .last_error
        .lock()
        .unwrap_or_else(|error| error.into_inner()) = None;
    publish_status(shared);
}

fn queue_bytes(queue: &MutationQueue) -> usize {
    queue.bytes
}

fn queue_pressure(shared: &CallsWriter) -> QueuePressure {
    let queue = shared
        .queue
        .lock()
        .unwrap_or_else(|error| error.into_inner());
    QueuePressure {
        mutations: queue.len(),
        bytes: queue.bytes,
        oldest_accepted_at: queue.front().map(|entry| entry.accepted_at),
    }
}

async fn apply_mutation(
    log: &mut CallLog,
    db: &DatabaseTransaction,
    mutation: &CallMutation,
) -> Result<MaterialChanges, BatchFailure> {
    let tx = db
        .begin()
        .await
        .map_err(|error| classify_failure(error.into()))?;
    let result = match mutation {
        CallMutation::Effect {
            thread_id,
            sequence,
            records,
        } => apply_effect(log, &tx, thread_id, *sequence, records)
            .await
            .map(|()| MaterialChanges {
                status: true,
                ..Default::default()
            }),
        CallMutation::Billing(record) => {
            apply_billing(log, &tx, record)
                .await
                .map(|performance| MaterialChanges {
                    performance,
                    ..Default::default()
                })
        }
        CallMutation::Summary(projection) => summary::replace(
            &tx,
            projection,
            &projection.hash,
            #[cfg(feature = "benchmarks")]
            Some(&log.observation),
        )
        .await
        .map(|costs| MaterialChanges {
            costs,
            ..Default::default()
        }),
    };
    match result {
        Ok(changes) => {
            tx.commit()
                .await
                .map_err(|error| classify_failure(error.into()))?;
            Ok(changes)
        }
        Err(error) => {
            tx.rollback().await.map_err(|rollback| {
                classify_failure(anyhow::anyhow!(
                    "{error}; savepoint rollback failed: {rollback}"
                ))
            })?;
            Err(classify_failure(error))
        }
    }
}

fn classify_failure(error: anyhow::Error) -> BatchFailure {
    let message = error.to_string();
    BatchFailure {
        retryable: is_retryable_write(&message),
        message,
    }
}

/// 把一次 effect 的调用事实写入调用库；调用开始与终态更新共享同一调用身份。
async fn apply_effect(
    log: &mut CallLog,
    db: &DatabaseTransaction,
    thread_id: &str,
    sequence: i64,
    records: &[PreparedRecord],
) -> Result<()> {
    let tx = db;
    #[cfg(feature = "benchmarks")]
    log.observation
        .increment(observation::Metric::WatermarkReadSql);
    let current = tx
        .query_one_raw(statement(
            "SELECT durable_write_seq FROM call_watermarks WHERE thread_id=?",
            vec![thread_id.into()],
        ))
        .await?
        .map(|row| row.try_get::<i64>("", "durable_write_seq"))
        .transpose()?
        .unwrap_or(0);
    for record in records {
        apply_attempt(tx, log, record).await?;
    }
    if sequence <= current {
        return Ok(());
    }
    #[cfg(feature = "benchmarks")]
    log.observation
        .increment(observation::Metric::WatermarkWriteSql);
    tx.execute_raw(statement(
        "INSERT INTO call_watermarks(thread_id,admitted_write_seq,durable_write_seq)
         VALUES(?,?,?)
         ON CONFLICT(thread_id) DO UPDATE SET
            admitted_write_seq=MAX(excluded.admitted_write_seq,call_watermarks.admitted_write_seq),
            durable_write_seq=MAX(excluded.durable_write_seq,call_watermarks.durable_write_seq)",
        vec![thread_id.into(), sequence.into(), sequence.into()],
    ))
    .await?;
    Ok(())
}

/// attempt 记录按 revision 单调：更旧的修订不覆盖已索引的更新。
async fn apply_attempt(
    db: &DatabaseTransaction,
    log: &mut CallLog,
    record: &PreparedRecord,
) -> Result<()> {
    let existing = db
        .query_one_raw(statement(
            "SELECT revision FROM call_log_index WHERE thread_id=? AND call_id=? AND kind=?",
            vec![
                record.thread_id.clone().into(),
                record.call_id.clone().into(),
                record.kind.clone().into(),
            ],
        ))
        .await?;
    if let Some(row) = existing {
        let stored: i64 = row.try_get("", "revision")?;
        if record.revision <= stored {
            return Ok(());
        }
    }
    let now = crate::studio::unix_seconds();
    append_record(db, log, record, now).await
}

/// 幂等写入一次计费/性能事实；同一身份不同正文明确失败。
async fn apply_billing(
    log: &mut CallLog,
    db: &DatabaseTransaction,
    record: &PreparedRecord,
) -> Result<bool> {
    #[cfg(feature = "benchmarks")]
    log.observation
        .increment(observation::Metric::BillingIdentitySql);
    let existing = db
        .query_one_raw(statement(
            "SELECT content_hash FROM call_log_index WHERE thread_id=? AND call_id=? AND kind=?",
            vec![
                record.thread_id.clone().into(),
                record.call_id.clone().into(),
                record.kind.clone().into(),
            ],
        ))
        .await?;
    if let Some(row) = existing {
        let stored: Option<String> = row.try_get("", "content_hash")?;
        match stored {
            Some(stored) if stored == record.hash => return Ok(false),
            Some(_) => {
                bail!(
                    "model call {} conflicts with the durable call record",
                    record.call_id
                );
            }
            None => {}
        }
    }
    let now = crate::studio::unix_seconds();
    append_record(db, log, record, now).await?;
    if record.status == CallStatus::Committed.as_str()
        && let Some(sample) = performance::sample_from_record(record)
    {
        #[cfg(feature = "benchmarks")]
        log.observation
            .increment(observation::Metric::PerformanceWriteSql);
        performance::record(db, &sample).await?;
        return Ok(true);
    }
    Ok(false)
}

/// 追加一条记录到 JSONL 日志并在 SQLite 索引中登记位置；顺带回收被清理段的索引行。
async fn append_record(
    db: &impl ConnectionTrait,
    log: &mut CallLog,
    record: &PreparedRecord,
    now: i64,
) -> Result<()> {
    if now.saturating_sub(record.recorded_at) >= log::LOG_RETENTION_SECONDS {
        return Ok(());
    }
    let outcome = log
        .append(event::record_day(record.recorded_at), now, &record.line)
        .await?;
    prune_index(db, &outcome.removed).await?;
    #[cfg(feature = "benchmarks")]
    log.observation
        .increment(observation::Metric::LogIndexWriteSql);
    index_record(db, record, &record.hash, &outcome.record, record.truncated).await
}

async fn index_record(
    db: &impl ConnectionTrait,
    record: &CallLogRecord,
    content_hash: &str,
    location: &log::AppendedRecord,
    truncated: bool,
) -> Result<()> {
    db.execute_raw(statement(
        "INSERT INTO call_log_index(
            thread_id,call_id,kind,revision,content_hash,segment,offset,length,truncated,recorded_at)
         VALUES(?,?,?,?,?,?,?,?,?,?)
         ON CONFLICT(thread_id,call_id,kind) DO UPDATE SET
            revision=MAX(excluded.revision,call_log_index.revision),
            content_hash=excluded.content_hash,
            segment=excluded.segment,
            offset=excluded.offset,
            length=excluded.length,
            truncated=excluded.truncated,
            recorded_at=excluded.recorded_at WHERE excluded.revision >= call_log_index.revision",
        vec![
            record.thread_id.clone().into(),
            record.call_id.clone().into(),
            record.kind.clone().into(),
            record.revision.into(),
            content_hash.into(),
            location.segment.clone().into(),
            integer(location.offset)?.into(),
            integer(location.length)?.into(),
            (truncated as i32).into(),
            record.recorded_at.into(),
        ],
    ))
    .await?;
    Ok(())
}

/// 删除被清理段的索引行。
async fn prune_index(db: &impl ConnectionTrait, segments: &[String]) -> Result<()> {
    for segment in segments {
        db.execute_raw(statement(
            "DELETE FROM call_log_index WHERE segment=?",
            vec![segment.clone().into()],
        ))
        .await?;
    }
    Ok(())
}

fn performance_summary_row(row: &QueryResult) -> Result<PerformanceSummaryRow> {
    Ok(PerformanceSummaryRow {
        account_id: row.try_get("", "account_id")?,
        account_display_name: row.try_get("", "account_display_name")?,
        model_id: row.try_get("", "model_id")?,
        effort: row.try_get("", "effort")?,
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

/// 只有数据库忙/锁/IO 类错误允许自动重试；结构或约束错误必须显式回给调用方。
fn is_retryable_write(message: &str) -> bool {
    let message = message.to_ascii_lowercase();
    message.contains("database is locked")
        || message.contains("database table is locked")
        || message.contains("database is busy")
        || message.contains("disk i/o error")
        || message.contains("sqlite_busy")
        || message.contains("sqlite_locked")
        || message.contains("sqlite_ioerr")
}

#[cfg(test)]
mod storage_fault_tests {
    use super::*;

    fn billing(thread: &str) -> Result<CallMutation> {
        Ok(CallMutation::Billing(Box::new(PreparedRecord::new(
            CallLogRecord {
                version: event::CALL_LOG_RECORD_VERSION,
                kind: "billing".into(),
                thread_id: thread.into(),
                call_id: "call".into(),
                status: "committed".into(),
                recorded_at: crate::studio::unix_seconds(),
                account_id: Some("account".into()),
                model_id: Some("model".into()),
                usage: Some(event::CallUsageRecord {
                    output_tokens: Some(10),
                    ..Default::default()
                }),
                usage_status: Some(pl_core::usage::UsageStatus::Partial),
                timing: Some(event::CallTimingRecord {
                    first_output_source: pl_protocol::FirstOutputSource::Unobserved,
                    response_millis: Some(100),
                    ..Default::default()
                }),
                throughput_epoch: event::THROUGHPUT_EPOCH,
                ..Default::default()
            },
        )?)))
    }

    fn batch(mutations: Vec<CallMutation>) -> VecDeque<QueuedCallMutation> {
        mutations
            .into_iter()
            .enumerate()
            .map(|(index, mutation)| QueuedCallMutation {
                ticket: index as u64 + 1,
                accepted_at: tokio::time::Instant::now(),
                bytes: mutation.estimated_bytes(),
                mutation,
            })
            .collect()
    }

    #[tokio::test]
    async fn queued_and_durable_billing_use_the_same_complete_identity_hash() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
        let record: InferenceBillingRecord = serde_json::from_value(serde_json::json!({
            "inferenceId": "call", "accounting": pl_protocol::InferenceAccounting::default(),
            "recordedAt": crate::studio::unix_seconds(),
        }))?;
        let ticket = store.admit_billing(
            "root",
            "thread",
            &record,
            CallStatus::Committed,
            CallRetention::Turn,
        )?;
        assert_eq!(
            store.admit_billing(
                "root",
                "thread",
                &record,
                CallStatus::Committed,
                CallRetention::Turn
            )?,
            ticket
        );
        let bytes = store.pending_bytes();
        assert_eq!(store.pending_count(), 1);
        let variants = [
            ("other-root", CallStatus::Committed, CallRetention::Turn),
            ("root", CallStatus::Rejected, CallRetention::Turn),
            ("root", CallStatus::Committed, CallRetention::Internal),
        ];
        for (root, status, retention) in variants {
            assert!(
                store
                    .admit_billing(root, "thread", &record, status, retention)
                    .is_err()
            );
        }
        let drained = drain_batch(&store.writer);
        assert_eq!(store.pending_bytes(), 0);
        requeue(&store.writer, drained.into());
        assert_eq!(store.pending_bytes(), bytes);
        let pending = drain_batch(&store.writer).into();
        let (_, failures, _) = apply_batch(&store.writer, &pending).await?;
        assert!(failures.is_empty());
        for (root, status, retention) in variants {
            let changed = event::billing_record(root, "thread", retention, &record, status);
            let pending = batch(vec![CallMutation::Billing(Box::new(PreparedRecord::new(
                changed,
            )?))]);
            let (_, failures, _) = apply_batch(&store.writer, &pending).await?;
            assert_eq!(
                failures.len(),
                1,
                "durable checks reject the same conflicts as admission"
            );
        }
        store.admit_billing(
            "root",
            "another-thread",
            &record,
            CallStatus::Committed,
            CallRetention::Turn,
        )?;
        let (_, failures, _) =
            apply_batch(&store.writer, &drain_batch(&store.writer).into()).await?;
        assert!(
            failures.is_empty(),
            "thread identity is not a global call-id deduplication key"
        );
        store.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn billing_sample_failure_rolls_back_locator_and_preserves_other_items() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
        store
            .writer
            .db
            .execute_unprepared(
                "CREATE TABLE sample_probe(thread_id TEXT);
             CREATE TRIGGER reject_sample BEFORE INSERT ON performance_samples
             WHEN NEW.thread_id='bad' BEGIN
               INSERT INTO sample_probe VALUES(NEW.thread_id);
               SELECT RAISE(FAIL,'injected sample failure');
             END;",
            )
            .await?;
        let pending = batch(vec![billing("first")?, billing("bad")?, billing("last")?]);
        let (completed, failures, deferred) = apply_batch(&store.writer, &pending).await?;
        assert_eq!(completed, 3);
        assert_eq!(failures.len(), 1);
        assert!(deferred.is_none());
        let rows = store
            .writer
            .db
            .query_all_raw(statement(
                "SELECT thread_id FROM call_log_index ORDER BY thread_id",
                vec![],
            ))
            .await?;
        let ids = rows
            .iter()
            .map(|row| row.try_get::<String>("", "thread_id"))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        assert_eq!(ids, ["first", "last"]);
        assert_eq!(store.recent_performance_samples(100).await?.len(), 2);
        assert!(
            store
                .writer
                .db
                .query_all_raw(statement("SELECT * FROM sample_probe", vec![]))
                .await?
                .is_empty()
        );
        assert_eq!(store.subscribe_materials().borrow().versions.performance, 1);
        assert_eq!(
            store.durable_ticket(),
            0,
            "the batch never confirms receipts itself"
        );
        // The failed savepoint can leave a complete isolated line, but not partial SQL.
        let mut segments = tokio::fs::read_dir(temp.path().join("logs")).await?;
        let file = segments.next_entry().await?.unwrap();
        let text = tokio::fs::read_to_string(file.path()).await?;
        assert_eq!(text.lines().count(), 3);
        for line in text.lines() {
            event::decode_record(line)?;
        }
        store.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn file_barrier_failure_cannot_publish_sql_or_material_success() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
        let materials = store.subscribe_materials();
        store.writer.log.lock().await.fail_next_sync = true;
        let pending = batch(vec![billing("thread")?]);
        assert!(apply_batch(&store.writer, &pending).await.is_err());
        assert!(store.recent_performance_samples(100).await?.is_empty());
        assert!(!materials.has_changed()?);
        assert_eq!(store.durable_ticket(), 0);
        let (completed, failures, deferred) = apply_batch(&store.writer, &pending).await?;
        assert_eq!(completed, 1);
        assert!(failures.is_empty());
        assert!(deferred.is_none());
        assert_eq!(materials.borrow().versions.performance, 1);
        assert_eq!(store.recent_performance_samples(100).await?.len(), 1);
        store.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn outer_commit_failure_cannot_publish_material_success() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
        let materials = store.subscribe_materials();
        store
            .writer
            .db
            .execute_unprepared(
                "CREATE TABLE commit_parent(id INTEGER PRIMARY KEY);
             CREATE TABLE commit_probe(parent INTEGER REFERENCES commit_parent(id)
                 DEFERRABLE INITIALLY DEFERRED);
             CREATE TRIGGER reject_commit AFTER INSERT ON performance_samples BEGIN
                 INSERT INTO commit_probe VALUES(1);
             END;",
            )
            .await?;
        let pending = batch(vec![billing("thread")?]);
        assert!(
            apply_batch(&store.writer, &pending).await.is_err(),
            "the deferred constraint fails at the outer commit, not its savepoint"
        );
        assert!(store.recent_performance_samples(100).await?.is_empty());
        assert!(!materials.has_changed()?);
        assert_eq!(store.durable_ticket(), 0);
        store
            .writer
            .db
            .execute_unprepared("DROP TRIGGER reject_commit")
            .await?;
        let (completed, failures, deferred) = apply_batch(&store.writer, &pending).await?;
        assert_eq!(completed, 1);
        assert!(failures.is_empty());
        assert!(deferred.is_none());
        assert_eq!(materials.borrow().versions.performance, 1);
        store.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn statistics_reads_do_not_wait_for_the_jsonl_lease() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
        let lease = store.writer.log.lock().await;
        let read = tokio::time::timeout(
            Duration::from_secs(2),
            store.read_statistics(StatisticsReadRequest {
                costs: true,
                performance: true,
            }),
        )
        .await??;
        assert!(read.costs.unwrap().is_empty());
        assert!(read.history.unwrap().is_empty());
        assert!(read.summary.unwrap().is_empty());
        let read = store
            .read_statistics(StatisticsReadRequest {
                costs: true,
                performance: false,
            })
            .await?;
        assert!(read.history.is_none());
        assert!(read.summary.is_none());
        drop(lease);
        store.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn directed_progress_coalesces_empty_effects_without_discarding_records() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
        store
            .writer
            .db
            .execute_unprepared(
                "CREATE TABLE watermark_probe(sequence INTEGER NOT NULL);
             CREATE TRIGGER probe_insert AFTER INSERT ON call_watermarks BEGIN
                 INSERT INTO watermark_probe VALUES(NEW.durable_write_seq);
             END;
             CREATE TRIGGER probe_update AFTER UPDATE ON call_watermarks BEGIN
                 INSERT INTO watermark_probe VALUES(NEW.durable_write_seq);
             END;",
            )
            .await?;
        let alpha = store.subscribe_thread_progress("alpha").await?;
        let beta = store.subscribe_thread_progress("beta").await?;
        let record = PreparedRecord::new(CallLogRecord {
            version: event::CALL_LOG_RECORD_VERSION,
            thread_id: "alpha".into(),
            call_id: "real-record".into(),
            kind: "attempt".into(),
            revision: 3,
            recorded_at: crate::studio::unix_seconds(),
            ..Default::default()
        })?;
        let pending = batch(vec![
            CallMutation::Effect {
                thread_id: "alpha".into(),
                sequence: 1,
                records: vec![],
            },
            CallMutation::Effect {
                thread_id: "alpha".into(),
                sequence: 2,
                records: vec![],
            },
            CallMutation::Effect {
                thread_id: "alpha".into(),
                sequence: 3,
                records: vec![record],
            },
            CallMutation::Effect {
                thread_id: "alpha".into(),
                sequence: 4,
                records: vec![],
            },
            CallMutation::Effect {
                thread_id: "alpha".into(),
                sequence: 5,
                records: vec![],
            },
        ]);
        apply_batch(&store.writer, &pending).await?;
        assert_eq!(alpha.borrow().materialized_sequence, 5);
        assert_eq!(alpha.borrow().processed_sequence, 5);
        assert!(
            !beta.has_changed()?,
            "unrelated Threads are not woken by a global ticket"
        );
        assert_eq!(store.durable_effect_sequence("alpha").await?, 5);
        let writes = store
            .writer
            .db
            .query_all_raw(statement(
                "SELECT sequence FROM watermark_probe ORDER BY rowid",
                vec![],
            ))
            .await?
            .iter()
            .map(|row| row.try_get::<i64>("", "sequence"))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        assert_eq!(
            writes,
            [2, 3, 5],
            "each contiguous empty run still uses one watermark write"
        );
        assert_eq!(
            store
                .writer
                .db
                .query_all_raw(statement("SELECT * FROM call_log_index", vec![]))
                .await?
                .len(),
            1
        );
        drop(alpha);
        drop(beta);
        let fresh = store.subscribe_thread_progress("fresh").await?;
        assert_eq!(
            store.writer.threads.lock().unwrap().len(),
            1,
            "inactive subscriptions are reclaimed"
        );
        drop(fresh);
        store.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn empty_effect_runs_do_not_confirm_past_retrying_record_savepoint() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("calls.sqlite");
        let store = CallsStore::prepare(&path).await?;
        // Keep the real records mutation retrying inside its savepoint until the
        // test has inspected the committed prefix. This is the same SQL gate used
        // by the busy-recovery regressions, not an alternate writer or saver.
        store
            .writer
            .db
            .execute_unprepared(
                "CREATE TABLE busy_gate(enabled INTEGER NOT NULL);
             INSERT INTO busy_gate VALUES(1);
             CREATE TRIGGER busy_record BEFORE INSERT ON call_log_index
             WHEN NEW.thread_id='alpha' AND NEW.call_id='real-record'
                 AND (SELECT enabled FROM busy_gate)=1 BEGIN
                 SELECT RAISE(FAIL,'database is busy');
             END;",
            )
            .await?;
        let mut materials = store.subscribe_materials();
        let mut alpha = store.subscribe_thread_progress("alpha").await?;
        for sequence in 1..=3 {
            assert!(store.try_admit_effect(&ThreadEffectBatch {
                thread_id: "alpha".into(),
                sequence,
                committed_at: crate::studio::unix_seconds(),
                attempt: (sequence == 2).then(|| AttemptUpdate {
                    request_metadata: None,
                    usage_binding: None,
                    tool_projection: None,
                    turn_id: "turn".into(),
                    attempt_id: "real-record".into(),
                    retry_of: None,
                    input_revision: 2,
                    tools: Default::default(),
                    outcome: AttemptOutcome::Running,
                    input_estimate: None,
                }),
                ..Default::default()
            }));
        }
        assert_eq!(
            store.pending_count(),
            3,
            "all three effects enter the same drained batch"
        );
        store.start().await;
        tokio::time::timeout(Duration::from_secs(2), async {
            loop {
                if alpha.borrow_and_update().retrying {
                    return Ok::<_, anyhow::Error>(());
                }
                alpha.changed().await?;
            }
        })
        .await??;
        assert_eq!(
            store.durable_effect_sequence("alpha").await?,
            1,
            "the SQL prefix must not contain the later empty effect's sequence 3"
        );
        assert_eq!(alpha.borrow().materialized_sequence, 1);
        assert_eq!(
            alpha.borrow().processed_sequence,
            1,
            "the retrying suffix has not been processed or rejected"
        );
        assert_eq!(materials.borrow().processed_ticket, 1);
        assert!(!alpha.borrow().statistics_gap);
        assert!(!materials.borrow().statistics_gap);
        assert!(
            alpha
                .borrow()
                .last_error
                .as_deref()
                .unwrap()
                .contains("database is busy")
        );
        assert!(
            store
                .writer
                .db
                .query_all_raw(statement(
                    "SELECT * FROM call_log_index WHERE thread_id='alpha'",
                    vec![],
                ))
                .await?
                .is_empty(),
            "the failed records savepoint has no partial locator"
        );

        store
            .writer
            .db
            .execute_unprepared("UPDATE busy_gate SET enabled=0")
            .await?;
        store.writer.retry_notify.notify_one();
        wait_material_ticket(&mut materials, 3).await?;
        assert_eq!(store.durable_effect_sequence("alpha").await?, 3);
        assert_eq!(alpha.borrow().materialized_sequence, 3);
        assert_eq!(alpha.borrow().processed_sequence, 3);
        assert!(!alpha.borrow().retrying);
        assert!(!alpha.borrow().statistics_gap);
        assert!(!materials.borrow().statistics_gap);
        assert!(alpha.borrow().last_error.is_none());
        let records = store
            .writer
            .db
            .query_all_raw(statement(
                "SELECT call_id,revision FROM call_log_index WHERE thread_id='alpha'",
                vec![],
            ))
            .await?;
        assert_eq!(
            records.len(),
            1,
            "the successful retry materializes the real call once"
        );
        assert_eq!(records[0].try_get::<String>("", "call_id")?, "real-record");
        assert_eq!(records[0].try_get::<i64>("", "revision")?, 2);
        store.close().await?;

        let reopened = CallsStore::open(&path).await?;
        let restored = reopened.subscribe_thread_progress("alpha").await?;
        assert_eq!(reopened.durable_effect_sequence("alpha").await?, 3);
        assert_eq!(restored.borrow().materialized_sequence, 3);
        assert_eq!(restored.borrow().processed_sequence, 3);
        assert_eq!(
            reopened
                .writer
                .db
                .query_all_raw(statement(
                    "SELECT call_id FROM call_log_index WHERE thread_id='alpha'",
                    vec![],
                ))
                .await?
                .len(),
            1,
            "complete orphan lines never duplicate the logical call on reopen"
        );
        reopened.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn initial_thread_sql_cannot_overwrite_concurrent_committed_progress() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
        let gate = Arc::new(SubscribeGate::default());
        *store.writer.subscribe_gate.lock().unwrap() = Some(gate.clone());
        let subscriber = store.clone();
        let subscription =
            tokio::spawn(async move { subscriber.subscribe_thread_progress("thread").await });
        tokio::time::timeout(Duration::from_secs(2), gate.loaded.notified()).await?;
        let pending = batch(vec![CallMutation::Effect {
            thread_id: "thread".into(),
            sequence: 7,
            records: vec![],
        }]);
        apply_batch(&store.writer, &pending).await?;
        gate.resume.notify_one();
        let progress = tokio::time::timeout(Duration::from_secs(2), subscription).await???;
        assert_eq!(progress.borrow().materialized_sequence, 7);
        assert_eq!(progress.borrow().processed_sequence, 7);
        store.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn cancelled_initial_subscriber_hands_sql_initialization_to_waiting_subscriber()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
        store
            .writer
            .db
            .execute_unprepared(
                "INSERT INTO call_watermarks(thread_id,admitted_write_seq,durable_write_seq)
             VALUES('thread',7,7)",
            )
            .await?;
        let gate = Arc::new(SubscribeGate::default());
        *store.writer.subscribe_gate.lock().unwrap() = Some(gate.clone());
        let first_store = store.clone();
        let first =
            tokio::spawn(async move { first_store.subscribe_thread_progress("thread").await });
        tokio::time::timeout(Duration::from_secs(2), gate.loaded.notified()).await?;
        // Consume A's registration signal before B is allowed to register.
        tokio::time::timeout(Duration::from_secs(2), gate.registered.notified()).await?;
        let second_store = store.clone();
        let second =
            tokio::spawn(async move { second_store.subscribe_thread_progress("thread").await });
        tokio::time::timeout(Duration::from_secs(2), gate.registered.notified()).await?;
        let initialized = {
            let threads = store.writer.threads.lock().unwrap();
            threads.get("thread").unwrap().initialized.initialized()
        };
        assert!(
            !initialized,
            "A still owns incomplete initialization; B must not return zero"
        );
        first.abort();
        assert!(first.await.unwrap_err().is_cancelled());
        let progress = tokio::time::timeout(Duration::from_secs(2), second).await???;
        assert_eq!(progress.borrow().materialized_sequence, 7);
        assert_eq!(progress.borrow().processed_sequence, 7);
        let subsequent = store.subscribe_thread_progress("thread").await?;
        assert_eq!(subsequent.borrow().materialized_sequence, 7);
        assert_eq!(
            store.admitted_ticket(),
            0,
            "no writer work rescues the subscribers"
        );
        store.close().await?;
        Ok(())
    }

    async fn wait_material_ticket(
        progress: &mut watch::Receiver<CallsMaterialProgress>,
        ticket: u64,
    ) -> Result<()> {
        tokio::time::timeout(Duration::from_secs(2), async {
            loop {
                if progress.borrow_and_update().processed_ticket >= ticket {
                    return Ok::<_, anyhow::Error>(());
                }
                progress.changed().await?;
            }
        })
        .await?
    }

    async fn assert_busy_recovery_preserves_gap(prior_rejection: bool) -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
        store
            .writer
            .db
            .execute_unprepared(
                "CREATE TABLE busy_gate(enabled INTEGER NOT NULL);
             INSERT INTO busy_gate VALUES(1);
             CREATE TRIGGER busy_effect BEFORE INSERT ON call_watermarks
             WHEN NEW.durable_write_seq=2 AND (SELECT enabled FROM busy_gate)=1 BEGIN
                SELECT RAISE(FAIL,'database is busy');
             END;
             CREATE TRIGGER rejected_effect BEFORE INSERT ON call_watermarks
             WHEN NEW.durable_write_seq=1 BEGIN
                SELECT RAISE(FAIL,'injected rejected fact');
             END;",
            )
            .await?;
        let mut materials = store.subscribe_materials();
        let mut thread = store.subscribe_thread_progress("thread").await?;
        store.start().await;
        if prior_rejection {
            assert!(store.try_admit_effect(&ThreadEffectBatch {
                thread_id: "thread".into(),
                sequence: 1,
                ..Default::default()
            }));
            wait_material_ticket(&mut materials, store.admitted_ticket()).await?;
            assert!(materials.borrow().statistics_gap);
            assert!(thread.borrow().statistics_gap);
            assert_eq!(thread.borrow().materialized_sequence, 0);
        }
        assert!(store.try_admit_effect(&ThreadEffectBatch {
            thread_id: "thread".into(),
            sequence: 2,
            ..Default::default()
        }));
        let ticket = store.admitted_ticket();
        tokio::time::timeout(Duration::from_secs(2), async {
            loop {
                if thread.borrow_and_update().retrying {
                    return Ok::<_, anyhow::Error>(());
                }
                thread.changed().await?;
            }
        })
        .await??;
        assert_eq!(thread.borrow().statistics_gap, prior_rejection);
        assert_eq!(materials.borrow().statistics_gap, prior_rejection);
        assert!(
            thread
                .borrow()
                .last_error
                .as_deref()
                .unwrap()
                .contains("database is busy")
        );
        assert!(
            materials
                .borrow()
                .last_error
                .as_deref()
                .unwrap()
                .contains("database is busy")
        );
        store
            .writer
            .db
            .execute_unprepared("UPDATE busy_gate SET enabled=0")
            .await?;
        store.writer.retry_notify.notify_one();
        wait_material_ticket(&mut materials, ticket).await?;
        assert_eq!(store.durable_effect_sequence("thread").await?, 2);
        assert_eq!(thread.borrow().materialized_sequence, 2);
        assert!(!thread.borrow().retrying);
        assert!(thread.borrow().last_error.is_none());
        assert!(materials.borrow().last_error.is_none());
        assert_eq!(thread.borrow().statistics_gap, prior_rejection);
        assert_eq!(materials.borrow().statistics_gap, prior_rejection);
        assert_eq!(store.statistics_gap(), prior_rejection);
        store.close().await?;
        assert_eq!(store.statistics_gap(), prior_rejection);
        Ok(())
    }

    #[tokio::test]
    async fn transient_busy_retry_succeeds_without_creating_statistics_gaps() -> Result<()> {
        assert_busy_recovery_preserves_gap(false).await
    }

    #[tokio::test]
    async fn successful_busy_retry_preserves_prior_rejection_gaps() -> Result<()> {
        assert_busy_recovery_preserves_gap(true).await
    }

    #[tokio::test]
    async fn summary_alone_notifies_costs_and_rejects_same_revision_conflicts() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = CallsStore::prepare(&temp.path().join("calls.sqlite")).await?;
        let mut materials = store.subscribe_materials();
        let projection = SessionUsageProjection {
            root_thread_id: "root".into(),
            thread_id: "thread".into(),
            revision: 1,
            has_unpriced_usage: false,
            purpose_costs: vec![],
        };
        store.replace_session_usage(projection.clone())?;
        let mut conflict = projection.clone();
        conflict.has_unpriced_usage = true;
        assert!(store.replace_session_usage(conflict.clone()).is_err());
        store.start().await;
        tokio::time::timeout(Duration::from_secs(2), async {
            loop {
                let progress = materials.borrow_and_update().clone();
                if progress.versions.costs == 1 && progress.processed_ticket == 1 {
                    break;
                }
                materials.changed().await?;
            }
            Ok::<_, anyhow::Error>(())
        })
        .await??;
        assert_eq!(materials.borrow().versions.performance, 0);
        let pending = batch(vec![CallMutation::Summary(PreparedSummary::new(conflict)?)]);
        let (_, failures, _) = apply_batch(&store.writer, &pending).await?;
        assert_eq!(failures.len(), 1);
        assert_eq!(materials.borrow().versions.costs, 1);
        store.close().await?;
        Ok(())
    }

    #[tokio::test]
    async fn unwritable_diagnostics_do_not_starve_absolute_accounting() -> Result<()> {
        let temp = tempfile::tempdir()?;
        tokio::fs::write(temp.path().join("logs"), b"blocked directory").await?;
        let store = CallsStore::open(&temp.path().join("calls.sqlite")).await?;
        let record = CallLogRecord {
            version: event::CALL_LOG_RECORD_VERSION,
            kind: "billing".into(),
            thread_id: "thread".into(),
            call_id: "call".into(),
            status: "committed".into(),
            recorded_at: crate::studio::unix_seconds(),
            ..Default::default()
        };
        let mutations = [
            CallMutation::Billing(Box::new(PreparedRecord::new(record)?)),
            CallMutation::Summary(PreparedSummary::new(SessionUsageProjection {
                root_thread_id: "thread".into(),
                thread_id: "thread".into(),
                revision: 7,
                has_unpriced_usage: false,
                purpose_costs: vec![PurposeUsageProjection {
                    purpose: None,
                    estimated_costs: vec![RuntimeCostAmount {
                        currency: "USD".into(),
                        amount: 3.0,
                    }],
                }],
            })?),
        ];
        let pending = mutations
            .into_iter()
            .enumerate()
            .map(|(index, mutation)| QueuedCallMutation {
                ticket: index as u64 + 1,
                accepted_at: tokio::time::Instant::now(),
                bytes: mutation.estimated_bytes(),
                mutation,
            })
            .collect();
        let (completed, failures, deferred) = apply_batch(&store.writer, &pending).await?;
        assert_eq!(completed, 2);
        assert_eq!(failures.len(), 1);
        assert!(deferred.is_none());
        assert!(
            !store.statistics_gap(),
            "unavailable diagnostics alone did not discard an accounting fact"
        );
        for failure in &failures {
            fail_mutation(&store.writer, failure);
        }
        assert!(store.statistics_gap());
        assert_eq!(
            store.session_cost_rollups().await?[0].estimated_costs[0].amount,
            3.0
        );
        store.stop_best_effort();
        Ok(())
    }

    #[tokio::test]
    async fn batch_savepoint_failure_preserves_other_calls_and_commits_before_receipts()
    -> Result<()> {
        let temp = tempfile::tempdir()?;
        let store = CallsStore::open(&temp.path().join("calls.sqlite")).await?;
        store
            .writer
            .db
            .execute_unprepared(
                "CREATE TABLE failure_probe(thread_id TEXT NOT NULL);
                 CREATE TRIGGER reject_one BEFORE INSERT ON call_watermarks
                 WHEN NEW.thread_id='rejected' BEGIN
                   INSERT INTO failure_probe VALUES(NEW.thread_id);
                   SELECT RAISE(FAIL,'injected invalid call');
                 END;",
            )
            .await?;
        let pending: VecDeque<QueuedCallMutation> = ["first", "rejected", "last"]
            .into_iter()
            .enumerate()
            .map(|(index, thread)| {
                let mutation = CallMutation::Effect {
                    thread_id: thread.to_owned(),
                    sequence: 1,
                    records: Vec::new(),
                };
                QueuedCallMutation {
                    ticket: index as u64 + 1,
                    accepted_at: tokio::time::Instant::now(),
                    bytes: mutation.estimated_bytes(),
                    mutation,
                }
            })
            .collect();
        let (completed, failures, deferred) = apply_batch(&store.writer, &pending).await?;
        assert_eq!(completed, 3);
        assert_eq!(failures.len(), 1);
        assert!(failures[0].contains("injected invalid call"));
        assert!(deferred.is_none());
        // An independent connection observes both committed facts before a receipt is advanced.
        let reopened = CallsStore::open(&temp.path().join("calls.sqlite")).await?;
        let rows = reopened
            .writer
            .db
            .query_all_raw(statement(
                "SELECT thread_id FROM call_watermarks ORDER BY thread_id",
                vec![],
            ))
            .await?;
        let ids = rows
            .iter()
            .map(|row| row.try_get::<String>("", "thread_id"))
            .collect::<std::result::Result<Vec<_>, _>>()?;
        assert_eq!(ids, ["first", "last"]);
        // RAISE(FAIL) preserves earlier trigger writes unless the mutation's savepoint rolls back.
        let failed_writes = reopened
            .writer
            .db
            .query_all_raw(statement("SELECT thread_id FROM failure_probe", vec![]))
            .await?;
        assert!(failed_writes.is_empty());
        assert_eq!(*store.writer.durable_ticket.borrow(), 0);
        store.stop_best_effort();
        reopened.stop_best_effort();
        Ok(())
    }
}

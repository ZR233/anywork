//! 模型性能/费用的产品投影。
//!
//! 会话 history.sqlite 的原子提交拥有累计用量与费用；calls.sqlite 只保存带 revision 的
//! 绝对统计投影和最多 3000 条性能摘要。调用正文位于有保留期限的 JSONL，日志淘汰不改变
//! 会话统计。内存仅保留固定上限的最近身份窗口，执行恢复不依赖调用日志。
//!
//! 投影经 typed product topic 对外发布，进程内只保留固定上限的缓存：单调 revision、更新时间
//! 与最近 inference 身份窗口（256 条，且不持久化）。执行恢复（`load_cache`）只读取产品对象
//! 缓存，完全不读取调用库。
//!
//! 展示投影只由明确的前进点建立：startup 初始化（`initialize_projection`）、统计进度前进
//! （`follow_statistics_progress`：Billing 与可靠历史派生 Summary 的受理 / 落库 / 拒绝都会
//! 唤醒同一 owner）与归档/恢复命令。发布状态（业务 revision、
//! 更新时间与 flags）与读取材料分属不同版本域：只有统计事实的落库水位前进才重新读取汇总、
//! 历史与费用材料；纯待写、统计缺口与读取失败状态只推进轻量状态并保留上一次读取的不可变
//! 材料，既有读取作用域继续有效。全局性能与逐 root 会话费用由同一计费 owner 分别发布
//! （作用域 revision 按 root 独立单调，含清除与淘汰）；查询
//! （snapshot/published_session_costs/session_costs_snapshot）只读已发布值：不写库、
//! 不推进 revision、不扫描补建作用域、不发事件。

use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use pl_protocol::{InferenceBillingRecord, InferenceModelObservation, ModelMatchState};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::statistics::{
    StudioModelPerformanceEffortSummary, StudioModelPerformanceSample,
    StudioModelPerformanceSnapshot, StudioModelPerformanceSummary,
};
use crate::studio::storage::calls::{
    CallRetention, CallStatus, PerformanceSampleRow, PerformanceSummaryRow, PurposeCostRollup,
    SessionCostRollup,
};
use crate::studio::store::object::{PersistedStudioObject, load_object, put_object};
use crate::studio::{ProductEventBus, StudioStore, unix_seconds};
use crate::{PureError, StudioSessionCostSnapshot, StudioSessionCostsState};

pub(in crate::studio) const MODEL_PERFORMANCE_OWNER_ID: &str = "global";
const CACHE_VERSION: u32 = 4;
const LEGACY_CACHE_VERSION: u32 = 2;
/// 产品快照返回的性能历史窗口上限；历史事实源是调用库。
const HISTORY_LIMIT: usize = crate::studio::storage::calls::PERFORMANCE_SAMPLE_LIMIT;
/// 内存中保留的最近 inference 身份窗口上限。
///
/// 持久 idempotency 已由 `calls.sqlite` 的调用身份唯一约束承担；这里只用于抑制同一
/// 进程内重复投递，因此必须有界，且不参与持久化。
const RECENT_IDENTITY_LIMIT: usize = 256;
/// 已清除条目缓存（`cost == None`）的软上限。
///
/// 这不是费用总量的截断：有真实费用材料的条目永不因此被淘汰，仍被观察（source lease 存活）
/// 的活跃根也不会被淘汰；它只限制"已清除且无观察"的空条目缓存，避免无界增长。
const SCOPED_COST_LIMIT: usize = 256;

#[derive(Clone)]
pub(crate) struct ModelPerformanceOwner {
    state: Arc<Mutex<ModelPerformanceState>>,
    store: StudioStore,
    product_events: ProductEventBus,
    source: Arc<super::statistics::StatisticsSource>,
    /// 已持久化的产品对象 revision，避免同一 revision 重复写盘。
    persisted_revision: Arc<AtomicU64>,
    /// 串行化产品对象写入，避免刷新任务与显式快照并发写同一 revision。
    persist_lock: Arc<tokio::sync::Mutex<()>>,
    /// 串行化投影建立：调用库读取、提交与发布在同 owner 内按序完成。
    project_lock: Arc<tokio::sync::Mutex<()>>,
    /// 已发布的展示投影：全局性能与逐 root 费用同一次发布原子可见。
    published: Arc<tokio::sync::Mutex<PublishedProjection>>,
    /// 上一次真实材料读取覆盖的统计落库水位（Billing / 可靠历史派生 Summary）。
    ///
    /// 只作为刷新驱动的读取判据，不参与发布版本、材料版本或读取引用。
    read_through: Arc<AtomicU64>,
    /// 最近一次**尝试**整库读取所依据的统计水位，无论那次读取成功与否。
    ///
    /// 只用于 retry 资格判定：失败过的统计状态不会被无关的 Effect 进度反复重读，而新的统计
    /// 进度前进（或 `initialize_projection` / `refresh_directory_visibility` 这类明确恢复动作）
    /// 仍然会重新读取。它绝不冒充成功水位（成功水位只有 `read_through`），也不参与发布版本
    /// 或读取材料。
    attempted_through: Arc<AtomicU64>,
}

/// 当前已发布的展示投影；查询路径只 clone，不推进。
struct PublishedProjection {
    global: StudioModelPerformanceSnapshot,
    history_sources: Arc<[PerformanceSampleSource]>,
    /// 费用发布水位独立于全局统计；跨缓存淘汰仍给每个 root 单调的展示版本。
    scoped_revision: u64,
    scoped_updated_at: i64,
    /// 每个 root 会话的作用域费用发布状态；revision 按 root 独立单调，互不覆盖。
    scoped: BTreeMap<String, ScopedCostEntry>,
}

/// 一次调用库投影读取得到的完整事实：全局性能与各 root 会话费用。
struct PerformanceProjection {
    global: StudioModelPerformanceSnapshot,
    history_sources: Arc<[PerformanceSampleSource]>,
    session_costs: Vec<StudioSessionCostSnapshot>,
    /// 本次读取开始前已落库的计费水位；刷新驱动据此判断材料是否可能变化。
    watermark: u64,
}

/// Canonical log identity, deliberately separate from the public presentation fields.
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub(super) struct PerformanceSampleSource {
    pub(super) thread_id: String,
    pub(super) call_id: String,
}

/// 单个 root 的作用域费用发布状态。
#[derive(Debug, Clone)]
struct ScopedCostEntry {
    revision: u64,
    updated_at: i64,
    statistics_pending: bool,
    statistics_gap: bool,
    read_failed: bool,
    cost: Option<StudioSessionCostSnapshot>,
}

impl ScopedCostEntry {
    fn differs(
        &self,
        pending: bool,
        gap: bool,
        read_failed: bool,
        cost: &Option<StudioSessionCostSnapshot>,
    ) -> bool {
        self.statistics_pending != pending
            || self.statistics_gap != gap
            || self.read_failed != read_failed
            || &self.cost != cost
    }

    fn state(&self, root_thread_id: &str) -> StudioSessionCostsState {
        StudioSessionCostsState {
            root_thread_id: root_thread_id.to_owned(),
            revision: self.revision,
            updated_at: self.updated_at,
            statistics_pending: self.statistics_pending,
            statistics_gap: self.statistics_gap,
            read_failed: self.read_failed,
            cost: self.cost.clone(),
        }
    }
}

/// 最近 inference 身份窗口（固定上限、不持久化）。
///
/// inference ID 只在执行它的 Thread 内唯一；根 Thread 只用于清理整棵会话树的缓存。
#[derive(Debug, Clone, Default)]
struct RecentIdentities {
    entries: BTreeMap<(String, String), RecentInference>,
    order: VecDeque<(String, String)>,
}

#[derive(Debug, Clone)]
struct RecentInference {
    root_thread_id: String,
    fingerprint: String,
}

impl RecentIdentities {
    fn get(&self, thread_id: &str, identity: &str) -> Option<&String> {
        self.entries
            .get(&(thread_id.to_owned(), identity.to_owned()))
            .map(|entry| &entry.fingerprint)
    }

    fn insert(
        &mut self,
        root_thread_id: &str,
        thread_id: &str,
        identity: &str,
        fingerprint: String,
    ) {
        let key = (thread_id.to_owned(), identity.to_owned());
        let entry = RecentInference {
            root_thread_id: root_thread_id.to_owned(),
            fingerprint,
        };
        if self.entries.insert(key.clone(), entry).is_none() {
            self.order.push_back(key);
        }
        while self.order.len() > RECENT_IDENTITY_LIMIT {
            if let Some(oldest) = self.order.pop_front() {
                self.entries.remove(&oldest);
            }
        }
    }

    fn remove_root(&mut self, root_thread_id: &str) {
        self.entries
            .retain(|_, entry| entry.root_thread_id != root_thread_id);
        self.order.retain(|key| self.entries.contains_key(key));
    }
}

/// 模型性能领域的固定上限缓存。
///
/// 只保留版本、单调 revision、更新时间与最近身份窗口：历史、汇总、fingerprint 集合与内部
/// 回执都不在这里持久化，也不从这里恢复（历史/汇总从 `calls.sqlite` 读取，持久幂等由调用身份
/// 唯一约束承担）。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::studio) struct ModelPerformanceState {
    version: u32,
    revision: u64,
    updated_at: i64,
    #[serde(skip)]
    recent: RecentIdentities,
}

/// 仅在 persistence worker 内存在的 object 编码 DTO。
#[derive(Serialize, Deserialize)]
#[serde(transparent)]
pub(in crate::studio) struct ModelPerformanceDto(ModelPerformanceState);

impl Default for ModelPerformanceState {
    fn default() -> Self {
        Self {
            version: CACHE_VERSION,
            revision: 0,
            updated_at: 0,
            recent: RecentIdentities::default(),
        }
    }
}

impl PersistedStudioObject for ModelPerformanceState {
    type PersistenceDto = ModelPerformanceDto;

    const OWNER_KIND: &'static str = "studio";
    const OBJECT_KIND: &'static str = "modelPerformance";
    const SCHEMA_VERSION: i64 = 1;

    fn revision(&self) -> u64 {
        self.revision
    }

    fn to_persistence_dto(&self) -> Self::PersistenceDto {
        ModelPerformanceDto(self.clone())
    }

    fn from_persistence_dto(dto: Self::PersistenceDto) -> anyhow::Result<Self> {
        Ok(dto.0)
    }
}

#[derive(Clone, Copy)]
enum BillingRetention {
    Turn,
    Internal,
}

impl ModelPerformanceOwner {
    pub(in crate::studio::runtime) fn new(
        store: StudioStore,
        product_events: ProductEventBus,
        source: Arc<super::statistics::StatisticsSource>,
    ) -> Self {
        Self {
            state: Arc::new(Mutex::new(ModelPerformanceState::default())),
            store,
            product_events,
            source,
            persisted_revision: Arc::new(AtomicU64::new(0)),
            persist_lock: Arc::new(tokio::sync::Mutex::new(())),
            project_lock: Arc::new(tokio::sync::Mutex::new(())),
            published: Arc::new(tokio::sync::Mutex::new(PublishedProjection {
                global: StudioModelPerformanceSnapshot::default(),
                history_sources: Arc::from([]),
                scoped_revision: 0,
                scoped_updated_at: 0,
                scoped: BTreeMap::new(),
            })),
            read_through: Arc::new(AtomicU64::new(0)),
            attempted_through: Arc::new(AtomicU64::new(0)),
        }
    }

    /// 恢复固定上限缓存；不读取调用库，执行恢复不依赖 calls。
    pub(crate) async fn load_cache(&self) -> anyhow::Result<()> {
        let calls = self.store.calls();
        let (costs, samples, summaries) = tokio::join!(
            calls.session_cost_rollups(),
            calls.recent_performance_samples(history_limit()),
            calls.performance_summary_rows()
        );
        costs?;
        samples?;
        summaries?;
        let Some(restored) =
            load_object::<ModelPerformanceState>(self.store.database(), MODEL_PERFORMANCE_OWNER_ID)
                .await?
        else {
            return Ok(());
        };
        if restored.version < LEGACY_CACHE_VERSION || restored.version > CACHE_VERSION {
            return Err(crate::studio::startup::data_error(anyhow::anyhow!(
                "unsupported model performance cache version {}",
                restored.version
            )));
        }
        {
            let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
            *state = ModelPerformanceState {
                version: CACHE_VERSION,
                revision: restored.revision,
                updated_at: restored.updated_at,
                recent: RecentIdentities::default(),
            };
        }
        self.persisted_revision
            .store(restored.revision, Ordering::Release);
        self.published.lock().await.global.revision = restored.revision;
        Ok(())
    }

    /// Returns only the owner-published scoped costs required by the GUI bootstrap.
    ///
    /// This narrow read does not clone the global summaries or retained history and does not
    /// mutate revisions, scan calls storage, or publish events.
    pub(crate) async fn published_session_costs(&self) -> Vec<StudioSessionCostsState> {
        let published = self.published.lock().await;
        published
            .scoped
            .iter()
            .map(|(root, entry)| entry.state(root))
            .collect()
    }

    /// 全局模型性能快照（已发布值；不含按 root 会话费用）。
    pub(crate) async fn snapshot(&self) -> StudioModelPerformanceSnapshot {
        self.published.lock().await.global.clone()
    }

    /// Small read projection for model selection; never clones the retained sample history.
    pub(crate) async fn model_summary(
        &self,
        account: &str,
        model: &str,
    ) -> Option<(i64, StudioModelPerformanceSummary)> {
        let published = self.published.lock().await;
        published
            .global
            .summaries
            .iter()
            .find(|summary| summary.account_id == account && summary.model_id == model)
            .cloned()
            .map(|summary| (published.global.updated_at, summary))
    }

    /// Captures log keys and their values at the same publication boundary. A timestamp/model
    /// combination is never used as a sample identity; equal-valued calls remain distinct.
    pub(super) async fn history_source_snapshot(
        &self,
    ) -> (
        StudioModelPerformanceSnapshot,
        Arc<[PerformanceSampleSource]>,
    ) {
        let published = self.published.lock().await;
        (published.global.clone(), published.history_sources.clone())
    }

    /// 单个 root 会话的作用域费用基线；纯读已发布缓存。
    ///
    /// 未缓存 root 返回当前费用水位的空基线，不落缓存、不扫描调用库；即使清除条目
    /// 已被淘汰，也可覆盖客户端更旧的费用。flags 来自同一次已发布投影。这是纯查询，
    /// 不登记观察；需要后续状态可达的 scope 走 [`Self::observe_session_costs`]。
    pub(crate) async fn session_costs_snapshot(
        &self,
        root_thread_id: &str,
    ) -> StudioSessionCostsState {
        let published = self.published.lock().await;
        if let Some(entry) = published.scoped.get(root_thread_id) {
            return entry.state(root_thread_id);
        }
        ScopedCostEntry {
            revision: published.scoped_revision,
            updated_at: published.scoped_updated_at,
            statistics_pending: published.global.statistics_pending,
            statistics_gap: published.global.statistics_gap,
            read_failed: published.global.read_failed,
            cost: None,
        }
        .state(root_thread_id)
    }

    /// 为一个已取得 scope lease 的 root 登记费用观察，返回同一份基线状态。
    ///
    /// 尚无 rollup 的 root 也进入同一份作用域费用账本（`cost == None` 即"没有费用事实"），
    /// 因此后续 pending/gap/read_failed 变化与首次真实 rollup 都沿同一条公开发布路径到达
    /// 该 root 的 feed。这里不读取调用库、不捏造费用、不改动 root 版本语义：空基线与首次
    /// rollup 的 revision 仍全部由 `scoped_revision` 权威给出（`session_costs_snapshot`
    /// 不登记观察，保持纯查询）。
    ///
    /// 观察生命周期由 source lease 决定：登记时回收已无 lease 且无费用的空条目，有费用的
    /// 条目仍由既有容量上限管理，因此不会为没有观察的 root 建立永久增长的表。
    pub(in crate::studio::runtime) async fn observe_session_costs(
        &self,
        root_thread_id: &str,
    ) -> StudioSessionCostsState {
        let mut published = self.published.lock().await;
        let observed = self.source.observed_costs();
        published
            .scoped
            .retain(|root, entry| entry.cost.is_some() || observed.contains(root));
        let (revision, updated_at, statistics_pending, statistics_gap, read_failed) = (
            published.scoped_revision,
            published.scoped_updated_at,
            published.global.statistics_pending,
            published.global.statistics_gap,
            published.global.read_failed,
        );
        published
            .scoped
            .entry(root_thread_id.to_owned())
            .or_insert(ScopedCostEntry {
                revision,
                updated_at,
                statistics_pending,
                statistics_gap,
                read_failed,
                cost: None,
            })
            .state(root_thread_id)
    }

    /// 在同一次 `published` 锁内原子采用一次投影的全局与作用域费用。
    ///
    /// 作用域真值未变化的 root 不提升 revision、不发事件；已发布过费用但不在最新投影
    /// 中的 root 被显式清除（`cost == None`），归档/删除对该作用域消费者可见。返回
    /// 已采用的全局快照与需要发布的作用域事实；typed topic 发布由调用方在锁外完成。
    async fn commit_projection(
        &self,
        mut snapshot: StudioModelPerformanceSnapshot,
        history_sources: Arc<[PerformanceSampleSource]>,
        fresh: Vec<StudioSessionCostSnapshot>,
        flags: (bool, bool),
        watermark: u64,
    ) -> (StudioModelPerformanceSnapshot, Vec<StudioSessionCostsState>) {
        let mut events = Vec::new();
        let global = {
            let mut published = self.published.lock().await;
            let flags_changed = (
                published.global.statistics_pending,
                published.global.statistics_gap,
                published.global.read_failed,
            ) != (flags.0, flags.1, false);
            let scoped_revision = published.scoped_revision.saturating_add(1);
            snapshot.revision = published.global.revision.saturating_add(1);
            // 先提交候选：来源拒绝（关闭、失败、配对长度错误或版本空间溢出）时保留 last-good，
            // 汇总/历史与作用域费用一起停留在上一次权威发布。
            if let Err(error) = self
                .source
                .publish_global(snapshot.clone(), history_sources.clone())
            {
                tracing::warn!(%error, "performance product capture failed");
                return (published.global.clone(), events);
            }
            published.global = snapshot.clone();
            published.history_sources = history_sources;
            // 成功读取水位只前进不回退：它记录"已经真实读到的统计状态"，与尝试水位分开。
            if watermark > self.read_through.load(Ordering::Acquire) {
                self.read_through.store(watermark, Ordering::Release);
            }
            // 活跃费用观察集合来自 source lease（同根共享、不跨 await）：淘汰必须排除它们，
            // 否则活跃空条目连同其 pending/gap/readFailed 会被清掉。锁序仍是 published → source。
            let observed_roots = self.source.observed_costs();
            let scoped = &mut published.scoped;
            let mut seen = std::collections::BTreeSet::new();
            for cost in fresh {
                seen.insert(cost.root_thread_id.clone());
                let root = cost.root_thread_id.clone();
                let entry = scoped
                    .entry(root.clone())
                    .or_insert_with(|| ScopedCostEntry {
                        revision: 0,
                        updated_at: unix_seconds(),
                        statistics_pending: flags.0,
                        statistics_gap: flags.1,
                        read_failed: false,
                        cost: None,
                    });
                if entry.differs(flags.0, flags.1, false, &Some(cost.clone())) {
                    entry.revision = scoped_revision;
                    entry.updated_at = unix_seconds();
                    entry.statistics_pending = flags.0;
                    entry.statistics_gap = flags.1;
                    entry.read_failed = false;
                    entry.cost = Some(cost);
                    events.push(entry.state(&root));
                }
            }
            for (root, entry) in scoped.iter_mut() {
                if !seen.contains(root) && entry.differs(flags.0, flags.1, false, &None) {
                    entry.cost = None;
                    entry.revision = scoped_revision;
                    entry.updated_at = unix_seconds();
                    entry.statistics_pending = flags.0;
                    entry.statistics_gap = flags.1;
                    entry.read_failed = false;
                    events.push(entry.state(root));
                }
            }
            evict_cleared(scoped, &observed_roots);
            if flags_changed || !events.is_empty() {
                published.scoped_revision = scoped_revision;
                published.scoped_updated_at = unix_seconds();
            }
            snapshot
        };
        for event in &events {
            if let Err(error) = self.source.publish_observed_costs(event.clone()) {
                tracing::warn!(%error, "session costs product capture failed");
            }
        }
        (global, events)
    }

    /// 读失败时在同一次 `published` 锁内原子标记全局与各 root：保留最后可用数据，
    /// 只显式标记失败与 flags；返回需要发布的作用域事实供锁外发布。
    ///
    /// 失败不伪造 `updated_at` 或成功值，也不重建读取材料：汇总、历史与费用沿用上一次
    /// 成功读取的不可变结果，已打开的读取作用域继续有效。
    async fn commit_read_failure(
        &self,
        pending: bool,
        gap: bool,
    ) -> (StudioModelPerformanceSnapshot, Vec<StudioSessionCostsState>) {
        let mut events = Vec::new();
        let global = {
            let mut published = self.published.lock().await;
            let flags_changed = (
                published.global.statistics_pending,
                published.global.statistics_gap,
                published.global.read_failed,
            ) != (pending, gap, true);
            let scoped_revision = published.scoped_revision.saturating_add(1);
            let mut candidate = published.global.clone();
            candidate.revision = candidate.revision.saturating_add(1);
            candidate.statistics_pending = pending;
            candidate.statistics_gap = gap;
            candidate.read_failed = true;
            // 只推进轻量状态：来源拒绝时保留 last-good，不用失效状态覆盖已发布事实。
            match self
                .source
                .publish_global(candidate.clone(), published.history_sources.clone())
            {
                Ok(()) => {
                    published.global = candidate.clone();
                    for (root, entry) in published.scoped.iter_mut() {
                        if entry.differs(pending, gap, true, &entry.cost.clone()) {
                            entry.revision = scoped_revision;
                            entry.updated_at = unix_seconds();
                            entry.statistics_pending = pending;
                            entry.statistics_gap = gap;
                            entry.read_failed = true;
                            events.push(entry.state(root));
                        }
                    }
                    if flags_changed || !events.is_empty() {
                        published.scoped_revision = scoped_revision;
                        published.scoped_updated_at = unix_seconds();
                    }
                    candidate
                }
                Err(error) => {
                    tracing::warn!(%error, "performance failure projection capture failed");
                    published.global.clone()
                }
            }
        };
        for event in &events {
            if let Err(error) = self.source.publish_observed_costs(event.clone()) {
                tracing::warn!(%error, "session costs product capture failed");
            }
        }
        (global, events)
    }

    /// 纯状态推进：只更新轻量业务状态与 flags，不重新读取调用库，也不重建读取材料。
    ///
    /// 待写与统计缺口的变化走这里：材料、实体与集合版本沿用上一次成功读取的结果。返回
    /// `None` 表示没有需要对外发布的变化。
    async fn commit_status(
        &self,
        pending: bool,
    ) -> Option<(StudioModelPerformanceSnapshot, Vec<StudioSessionCostsState>)> {
        let mut events = Vec::new();
        let global = {
            let mut published = self.published.lock().await;
            let gap = self.store.calls().statistics_gap();
            if (
                published.global.statistics_pending,
                published.global.statistics_gap,
            ) != (pending, gap)
            {
                let mut candidate = published.global.clone();
                candidate.revision = candidate.revision.saturating_add(1);
                candidate.statistics_pending = pending;
                candidate.statistics_gap = gap;
                match self
                    .source
                    .publish_global(candidate.clone(), published.history_sources.clone())
                {
                    Ok(()) => {
                        let read_failed = candidate.read_failed;
                        published.global = candidate.clone();
                        adopt_scoped_status(&mut published, pending, gap, read_failed, &mut events);
                        Some(candidate)
                    }
                    Err(error) => {
                        tracing::warn!(%error, "performance status capture failed");
                        None
                    }
                }
            } else {
                let read_failed = published.global.read_failed;
                adopt_scoped_status(&mut published, pending, gap, read_failed, &mut events);
                (!events.is_empty()).then(|| published.global.clone())
            }
        };
        for event in &events {
            if let Err(error) = self.source.publish_observed_costs(event.clone()) {
                tracing::warn!(%error, "session costs product capture failed");
            }
        }
        global.map(|global| (global, events))
    }

    fn statistics_flags(&self) -> (bool, bool) {
        let calls = self.store.calls();
        // 待写只比较统计事实（Billing / 可靠历史派生 Summary）的受理与落库水位：会话历史写入
        // （Effect）既不算待写统计，也不会在这里触发统计投影的整库重读。
        (
            calls.statistics_admitted() > calls.statistics_durable(),
            calls.statistics_gap(),
        )
    }

    pub(crate) fn record_inference(
        &self,
        root_thread_id: &str,
        thread_id: &str,
        billing: &InferenceBillingRecord,
        status: CallStatus,
    ) -> Result<(), PureError> {
        self.record(
            root_thread_id,
            thread_id,
            billing,
            status,
            BillingRetention::Turn,
        )
    }

    pub(crate) fn record_auxiliary_inference(
        &self,
        root_thread_id: &str,
        thread_id: &str,
        billing: &InferenceBillingRecord,
        status: CallStatus,
    ) -> Result<(), PureError> {
        self.record(
            root_thread_id,
            thread_id,
            billing,
            status,
            BillingRetention::Internal,
        )
    }

    fn record(
        &self,
        root_thread_id: &str,
        thread_id: &str,
        billing: &InferenceBillingRecord,
        status: CallStatus,
        retention: BillingRetention,
    ) -> Result<(), PureError> {
        if root_thread_id.trim().is_empty() || thread_id.trim().is_empty() {
            return Err(PureError::MemoryError(
                "model performance inference is missing Thread identity".to_string(),
            ));
        }
        let fingerprint = billing_fingerprint(billing)?;
        let conflict = {
            let state = self.state.lock().unwrap_or_else(|error| error.into_inner());
            match state.recent.get(thread_id, &billing.inference_id) {
                Some(existing) if existing == &fingerprint => return Ok(()),
                Some(_) => true,
                None => false,
            }
        };
        if conflict {
            // 同一推理身份携带不同内容，是调用方重复投递被拒，而不是已受理事实的持久化失败：
            // 这次请求从未进入调用库队列，所以只明确拒绝本次请求，绝不把它升级为写者终态。
            // 终端 `Blocked` 只留给调用库真实不可恢复的持久化冲突，避免一次应用级拒绝让整个
            // Studio 的写者健康永久失效。已受理事实与写者健康都不因这次拒绝改变。
            return Err(PureError::MemoryError(format!(
                "Thread {thread_id} inference {} conflicts with the model performance owner",
                billing.inference_id
            )));
        }
        // 调用库是唯一 writer：计费观察同步受理进调用库有界队列，durability 由这里固定的
        // ticket 在刷新快照 / Thread 关闭 / Studio shutdown 时等待，绝不在受理时提前确认。
        let ticket = self
            .store
            .calls()
            .admit_billing(
                root_thread_id,
                thread_id,
                billing,
                status,
                call_retention(retention),
            )
            .map_err(|error| {
                tracing::warn!(%error, inference_id = billing.inference_id, "billing statistics dropped");
                error
            })
            .ok();
        {
            let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
            if ticket.is_some() {
                state.recent.insert(
                    root_thread_id,
                    thread_id,
                    &billing.inference_id,
                    fingerprint,
                );
            }
            state.revision = state.revision.saturating_add(1);
            state.updated_at = unix_seconds();
        }
        // 受理与落库的唤醒由调用库自身的统计进度通知发出（`admit_billing` /
        // `replace_session_usage` / 真实提交 / 拒绝与缺口），owner 不再另存一份 ticket 目标，
        // 也不为每次推理起一个一次性刷新任务。
        Ok(())
    }

    /// 归档/删除会话后丢弃该 root 的进程内身份窗口并发布一次领域更新。
    pub(crate) async fn remove_session(&self, root_thread_id: &str) -> Result<(), PureError> {
        {
            let mut state = self.state.lock().unwrap_or_else(|error| error.into_inner());
            state.recent.remove_root(root_thread_id);
            state.revision = state.revision.saturating_add(1);
            state.updated_at = unix_seconds();
        }
        // 归档/删除的可见性由调用库 + 目录过滤保证；缓存写盘失败不回滚归档动作。
        if let Err(error) = self.persist_state().await {
            tracing::warn!(error = %error, "model performance cache persist failed");
        }
        // 目录可见性是真实材料变化（该 root 的费用不再对产品暴露）：必须重新读取一次。
        self.publish_projection().await;
        Ok(())
    }

    async fn read_projection(&self) -> Result<PerformanceProjection, PureError> {
        let calls = self.store.calls();
        // 统计专属水位：只由 Billing / 可靠历史派生 Summary 的真实提交推进，不被 Effect
        // （会话历史写入）的提交抬高，因此历史写入不会触发无关的整库重读。
        let settled_before_read = calls.statistics_durable();
        let admitted = calls.statistics_admitted();
        // 记录"这个统计状态已经被尝试读取过"：读取失败时它让同一状态的 Effect 进度不会反复
        // 触发整库重读；成功水位仍只由 `read_through` 表达。
        self.attempted_through
            .store(settled_before_read, Ordering::Release);
        // Statistics are an eventual, lossy projection: reads never wait for its writer.
        let costs = calls.session_cost_rollups().await.map_err(memory_error)?;
        let samples = calls
            .recent_performance_samples(history_limit())
            .await
            .map_err(memory_error)?;
        let summaries = calls
            .performance_summary_rows()
            .await
            .map_err(memory_error)?;
        let (revision, updated_at) = {
            let state = self.state.lock().unwrap_or_else(|error| error.into_inner());
            (state.revision, state.updated_at)
        };
        // 归档/删除会话后不再对产品暴露其会话级统计；模型级汇总仍是全局用量事实。
        let archived = self.archived_roots();
        Ok(PerformanceProjection {
            watermark: settled_before_read,
            history_sources: samples
                .iter()
                .map(|sample| PerformanceSampleSource {
                    thread_id: sample.thread_id.clone(),
                    call_id: sample.call_id.clone(),
                })
                .collect(),
            global: StudioModelPerformanceSnapshot {
                revision,
                updated_at,
                statistics_pending: admitted > settled_before_read,
                statistics_gap: calls.statistics_gap(),
                read_failed: false,
                summaries: summary_snapshots(&summaries),
                history: samples.iter().map(history_sample).collect(),
            },
            session_costs: costs
                .iter()
                .filter(|rollup| !archived.contains(&rollup.root_thread_id))
                .map(session_cost_snapshot)
                .collect(),
        })
    }

    /// 把进程内有界缓存（revision/更新时间）前移写盘；同 revision 幂等，旧 revision 不回写。
    async fn persist_state(&self) -> Result<(), PureError> {
        let _guard = self.persist_lock.lock().await;
        let (revision, updated_at, snapshot) = {
            let state = self.state.lock().unwrap_or_else(|error| error.into_inner());
            (state.revision, state.updated_at, state.clone())
        };
        if revision == 0 || revision <= self.persisted_revision.load(Ordering::Acquire) {
            return Ok(());
        }
        put_object(
            self.store.database(),
            MODEL_PERFORMANCE_OWNER_ID,
            &snapshot,
            updated_at,
        )
        .await
        .map_err(|error| PureError::MemoryError(error.to_string()))?;
        self.persisted_revision.store(revision, Ordering::Release);
        Ok(())
    }

    /// 目录中已归档（产品不可见）的会话 root 集合；未登记 root 不在此集合，保持兼容。
    fn archived_roots(&self) -> std::collections::HashSet<String> {
        self.store
            .catalog()
            .entries()
            .into_iter()
            .filter(|entry| entry.archived)
            .map(|entry| entry.id)
            .collect()
    }

    /// 跟随调用库的统计进度，直到 runtime 关闭或调用库释放。
    ///
    /// 唤醒只来自调用库既有的进度 watch：Billing 与可靠历史派生 Summary 的**受理**、**真实
    /// 提交**、**拒绝与缺口**都会发出一次"请重读事实"的通知，因此这些事实都到达同一 owner，
    /// 不存在"最后一次费用必须等下一次调用、重启或查询副作用"的空档，也没有第二个事件通道。
    ///
    /// 订阅后先按当前水位收敛一次，所以启动窗口内已发生的受理不会被漏掉；任务不轮询、不持
    /// 整个 runtime，取消与有界 join 由 runtime 的 `BackgroundTaskSlot` 负责。
    pub(in crate::studio::runtime) async fn follow_statistics_progress(&self) {
        let mut progress = self.store.calls().subscribe_durable_ticket();
        loop {
            self.converge_statistics_progress().await;
            // `changed()` 只是"请重读事实"（值可能未变）：真实水位在收敛内部读取；调用库关闭
            // 后 sender 释放即返回错误，任务由此结束，不依赖 Drop 语义。
            if progress.changed().await.is_err() {
                break;
            }
        }
    }

    /// 一次统计进度收敛：未落库只推进轻量状态，统计落库水位真前进才重建读取材料。
    ///
    /// 每轮按真实水位是否变化决定继续，同一唤醒批次里的多次受理/提交不会被合并丢失；水位
    /// 不变就立即返回，发布失败也不会空转。
    async fn converge_statistics_progress(&self) {
        loop {
            let calls = self.store.calls();
            let admitted = calls.statistics_admitted();
            let settled = calls.statistics_durable();
            // 只有"这个统计状态还没被尝试读过"才重建材料：失败过的状态不会因为无关的 Effect
            // 进度而反复整库重读；新的统计进度（或 initialize/archive 这类显式恢复动作，
            // 它们直接走 `publish_projection`）仍然会真实读取。
            let attempted = self.attempted_through.load(Ordering::Acquire);
            if settled > attempted {
                self.publish_projection().await;
            } else {
                self.publish_status(admitted > settled).await;
            }
            if calls.statistics_admitted() == admitted && calls.statistics_durable() == settled {
                return;
            }
        }
    }

    /// startup 在 `load_cache` 之后显式建立一次投影：已有调用事实立即成为最新首帧。
    ///
    /// 这是查询之外的前进点之一（startup 初始化 / 统计进度前进与 flags 变化 / 归档命令）；
    /// 读取失败只影响展示 flags，不影响 runtime 启动。
    pub(crate) async fn initialize_projection(&self) {
        let _guard = self.project_lock.lock().await;
        self.publish_locked_projection().await;
    }

    /// 显式恢复目录后重投影费用可见性；不激活 Thread、不执行历史或修改计费事实。
    pub(crate) async fn refresh_directory_visibility(&self) {
        self.publish_projection().await;
    }

    /// 把一次投影读取发布到两个领域：全局性能事件 + 逐 root 作用域费用事件。
    ///
    /// 调用库读取、提交与发布在同 owner 内经 `project_lock` 串行：较旧的异步读取
    /// 不可能晚于较新的读取提交而覆盖新事实。
    async fn publish_projection(&self) {
        let _guard = self.project_lock.lock().await;
        self.publish_locked_projection().await;
    }

    /// 读取、在同一次 `published` 锁内原子采用、再在锁外按 typed topics 发布变化事实。
    ///
    /// 全局与作用域在同一次锁内采用；锁内不 send/await，发布事实全部在锁外发出。
    async fn publish_locked_projection(&self) {
        match self.read_projection().await {
            Ok(projection) => {
                let flags = (
                    projection.global.statistics_pending,
                    projection.global.statistics_gap,
                );
                let (global, scoped_events) = self
                    .commit_projection(
                        projection.global,
                        projection.history_sources,
                        projection.session_costs,
                        flags,
                        projection.watermark,
                    )
                    .await;
                let _ = self.product_events.emit_model_performance_state(global);
                for state in scoped_events {
                    self.product_events.emit_session_costs(state);
                }
            }
            Err(error) => {
                tracing::warn!(error = %error, "model performance projection read failed");
                let (pending, gap) = self.statistics_flags();
                let (global, scoped_events) = self.commit_read_failure(pending, gap).await;
                let _ = self.product_events.emit_model_performance_state(global);
                for state in scoped_events {
                    self.product_events.emit_session_costs(state);
                }
            }
        }
        // 有界产品对象（revision/更新时间）只在投影前进点写盘；查询不写盘。
        if let Err(error) = self.persist_state().await {
            tracing::warn!(error = %error, "model performance cache persist failed");
        }
    }

    /// 只推进轻量发布状态：沿用原 `project_lock` 边界，不读取调用库、不重建材料。
    async fn publish_status(&self, pending: bool) {
        let _guard = self.project_lock.lock().await;
        let Some((global, scoped_events)) = self.commit_status(pending).await else {
            return;
        };
        let _ = self.product_events.emit_model_performance_state(global);
        for state in scoped_events {
            self.product_events.emit_session_costs(state);
        }
    }
}

/// 按新 flags 更新各 root 作用域的轻量状态，不改动已发布费用材料。
fn adopt_scoped_status(
    published: &mut PublishedProjection,
    pending: bool,
    gap: bool,
    read_failed: bool,
    events: &mut Vec<StudioSessionCostsState>,
) {
    let scoped_revision = published.scoped_revision.saturating_add(1);
    for (root, entry) in published.scoped.iter_mut() {
        if entry.differs(pending, gap, read_failed, &entry.cost.clone()) {
            entry.revision = scoped_revision;
            entry.updated_at = unix_seconds();
            entry.statistics_pending = pending;
            entry.statistics_gap = gap;
            entry.read_failed = read_failed;
            events.push(entry.state(root));
        }
    }
    if !events.is_empty() {
        published.scoped_revision = scoped_revision;
        published.scoped_updated_at = unix_seconds();
    }
}

/// 超出软上限时淘汰最旧的已清除条目。
///
/// 有真实费用材料的条目、以及仍被观察（`observed` 中的活跃 root）的条目都不淘汰：活跃空条目
/// 携带待写入/缺口/读取失败状态，被淘汰会让其订阅静默失联。因此条目总数可能超过软上限，超出
/// 的只是"已清除且最后一份观察需求已消失"的缓存。
fn evict_cleared(scoped: &mut BTreeMap<String, ScopedCostEntry>, observed: &BTreeSet<String>) {
    if scoped.len() <= SCOPED_COST_LIMIT {
        return;
    }
    let mut cleared: Vec<(i64, String)> = scoped
        .iter()
        .filter(|(root, entry)| entry.cost.is_none() && !observed.contains(*root))
        .map(|(root, entry)| (entry.updated_at, root.clone()))
        .collect();
    cleared.sort_unstable();
    let excess = scoped.len().saturating_sub(SCOPED_COST_LIMIT);
    for (_, root) in cleared.into_iter().take(excess) {
        scoped.remove(&root);
    }
}

fn memory_error(error: anyhow::Error) -> PureError {
    PureError::MemoryError(error.to_string())
}

fn history_limit() -> u32 {
    u32::try_from(HISTORY_LIMIT).unwrap_or(u32::MAX)
}

fn session_cost_snapshot(rollup: &SessionCostRollup) -> StudioSessionCostSnapshot {
    StudioSessionCostSnapshot {
        root_thread_id: rollup.root_thread_id.clone(),
        purpose_costs: rollup
            .purpose_costs
            .iter()
            .map(purpose_cost_snapshot)
            .collect(),
        estimated_costs: rollup.estimated_costs.clone(),
        has_unpriced_usage: rollup.has_unpriced_usage,
    }
}

fn purpose_cost_snapshot(rollup: &PurposeCostRollup) -> crate::StudioPurposeCostSnapshot {
    crate::StudioPurposeCostSnapshot {
        purpose: rollup.purpose.clone(),
        estimated_costs: rollup.estimated_costs.clone(),
        has_unpriced_usage: rollup.has_unpriced_usage,
    }
}

/// 把 (account_id, model_id, effort) 的数据库分组折叠为唯一顶层 (account, model) 汇总。
///
/// 同一账号模型在不同推理强度下的样本先在该组内累加得到顶层指标，再以
/// `effort_breakdowns` 提供二级细分；显示名取组内最新的非空展示值，不参与身份。
fn summary_snapshots(rows: &[PerformanceSummaryRow]) -> Vec<StudioModelPerformanceSummary> {
    let mut groups: Vec<(String, String, StudioModelPerformanceSummary)> = Vec::new();
    for row in rows {
        let existing = groups
            .iter()
            .position(|(account, model, _)| account == &row.account_id && model == &row.model_id);
        let index = match existing {
            Some(index) => index,
            None => {
                groups.push((
                    row.account_id.clone(),
                    row.model_id.clone(),
                    StudioModelPerformanceSummary {
                        account_id: row.account_id.clone(),
                        account_display_name: row.account_display_name.clone(),
                        model_id: row.model_id.clone(),
                        sample_count: 0,
                        completion_tokens: 0,
                        total_ttft_millis: 0,
                        ttft_sample_count: 0,
                        total_response_millis: 0,
                        tokens_per_second: 0.0,
                        average_ttft_millis: None,
                        average_response_millis: 0.0,
                        effort_breakdowns: Vec::new(),
                    },
                ));
                groups.len() - 1
            }
        };
        let summary = &mut groups[index].2;
        if summary.account_display_name.is_empty() && !row.account_display_name.is_empty() {
            summary.account_display_name = row.account_display_name.clone();
        }
        summary.sample_count = summary.sample_count.saturating_add(row.sample_count);
        summary.completion_tokens = summary
            .completion_tokens
            .saturating_add(row.completion_tokens);
        summary.total_ttft_millis = summary
            .total_ttft_millis
            .saturating_add(row.total_ttft_millis);
        summary.ttft_sample_count = summary
            .ttft_sample_count
            .saturating_add(row.ttft_sample_count);
        summary.total_response_millis = summary
            .total_response_millis
            .saturating_add(row.total_response_millis);
        summary
            .effort_breakdowns
            .push(StudioModelPerformanceEffortSummary {
                effort: row.effort.clone(),
                sample_count: row.sample_count,
                completion_tokens: row.completion_tokens,
                total_ttft_millis: row.total_ttft_millis,
                ttft_sample_count: row.ttft_sample_count,
                total_response_millis: row.total_response_millis,
                tokens_per_second: throughput(row.completion_tokens, row.total_response_millis),
                average_ttft_millis: average_ttft(row.total_ttft_millis, row.ttft_sample_count),
                average_response_millis: row.total_response_millis as f64 / row.sample_count as f64,
            });
    }
    groups
        .into_iter()
        .map(|(_, _, mut summary)| {
            let samples = summary.sample_count as f64;
            summary.tokens_per_second =
                throughput(summary.completion_tokens, summary.total_response_millis);
            summary.average_ttft_millis =
                average_ttft(summary.total_ttft_millis, summary.ttft_sample_count);
            summary.average_response_millis = summary.total_response_millis as f64 / samples;
            summary
        })
        .collect()
}

fn history_sample(row: &PerformanceSampleRow) -> StudioModelPerformanceSample {
    let observation = row
        .model_id
        .as_ref()
        .map(|model_id| InferenceModelObservation {
            configured_model: model_id.clone(),
            sent_model: row.sent_model.clone(),
            reported_model: row.reported_model.clone(),
        });
    StudioModelPerformanceSample {
        completed_at: row.completed_at,
        account_id: row.account_id.clone(),
        account_display_name: row.account_display_name.clone(),
        model_id: row.model_id.clone(),
        sent_model: observation.as_ref().map(|value| value.sent_model.clone()),
        reported_model: observation
            .as_ref()
            .and_then(|value| value.reported_model.clone()),
        model_match_state: observation
            .as_ref()
            .map_or(ModelMatchState::LegacyUnknown, |value| value.match_state()),
        effort: row.effort.clone(),
        completion_tokens: row.completion_tokens,
        ttft_millis: row.ttft_millis,
        decode_millis: row.decode_millis,
        total_response_millis: row.response_millis,
        tokens_per_second: row
            .response_millis
            .filter(|_| row.has_throughput_sample)
            .map(|value| throughput(row.completion_tokens, value)),
    }
}

/// 平均首字延迟只用真正测得首字的样本；没有此类样本时保持未知。
fn average_ttft(total_ttft_millis: u64, ttft_sample_count: u64) -> Option<f64> {
    (ttft_sample_count > 0).then(|| total_ttft_millis as f64 / ttft_sample_count as f64)
}

/// 含首字等待的输出吞吐：成对加权 output / 总响应耗时，不平均各次速率。
fn throughput(completion_tokens: u64, response_millis: u64) -> f64 {
    completion_tokens as f64 * 1_000.0 / response_millis as f64
}

fn billing_fingerprint(billing: &InferenceBillingRecord) -> Result<String, PureError> {
    let bytes = serde_json::to_vec(billing)?;
    Ok(hex::encode(Sha256::digest(bytes)))
}

fn call_retention(retention: BillingRetention) -> CallRetention {
    match retention {
        BillingRetention::Turn => CallRetention::Turn,
        BillingRetention::Internal => CallRetention::Internal,
    }
}

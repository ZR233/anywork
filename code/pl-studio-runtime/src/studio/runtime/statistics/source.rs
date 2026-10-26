use super::super::model_performance::PerformanceSampleSource;
use crate::statistics::{
    StudioModelPerformanceSample, StudioModelPerformanceSnapshot, StudioModelPerformanceSummary,
};
use crate::{StudioSessionCostSnapshot, StudioSessionCostsState};
use pl_protocol::products::identity::{ProductCollectionRef, ProductEntityRef, ProductReadOrigin};
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, Weak};

/// 活跃费用观察上限：**不同** `Key::Costs` root 的需求最多这么多，同一 root 共享同一 lease。
///
/// 只计费用观察本身：模型汇总/历史 lease 不占此额度。达到上限时显式 `Overloaded` 拒绝新的
/// root 观察，而不是先准入再失联。
const MAX_OBSERVED_COST_ROOTS: usize = 256;

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
pub(super) enum Key {
    Summaries,
    History,
    Costs(String),
}
/// 不可变读取材料的数据部分：只含固定的读取事实。
///
/// 发布状态（业务 revision、更新时间与 flags）不在材料里；只变状态时材料、实体、
/// 集合版本与读取引用都保持原样。
#[derive(Clone, PartialEq)]
pub(super) enum Root {
    Summaries(Vec<StudioModelPerformanceSummary>),
    History {
        samples: Vec<StudioModelPerformanceSample>,
        sample_keys: Arc<[PerformanceSampleSource]>,
    },
    Costs(Option<StudioSessionCostSnapshot>),
}
/// 发布状态：轻量业务 header 与 flags，与读取材料分属不同版本域。
#[derive(Clone, PartialEq, Eq)]
pub(in crate::studio::runtime) struct StatisticsStatus {
    pub(super) revision: u64,
    pub(super) updated_at: i64,
    pub(super) statistics_pending: bool,
    pub(super) statistics_gap: bool,
    pub(super) read_failed: bool,
}
impl StatisticsStatus {
    fn global(value: &StudioModelPerformanceSnapshot) -> Self {
        Self {
            revision: value.revision,
            updated_at: value.updated_at,
            statistics_pending: value.statistics_pending,
            statistics_gap: value.statistics_gap,
            read_failed: value.read_failed,
        }
    }
    fn costs(value: &StudioSessionCostsState) -> Self {
        Self {
            revision: value.revision,
            updated_at: value.updated_at,
            statistics_pending: value.statistics_pending,
            statistics_gap: value.statistics_gap,
            read_failed: value.read_failed,
        }
    }
}
#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
enum IdentityKey {
    Summary(String, String),
    Effort(String, String, Option<String>),
    Sample(String, String),
}
#[derive(Clone, PartialEq)]
pub(super) enum IdentityValue {
    Summary {
        account_id: String,
        account_display_name: String,
        model_id: String,
    },
    Effort(Option<String>),
    Sample {
        account_id: String,
        account_display_name: String,
        model_id: Option<String>,
        sent_model: Option<String>,
        reported_model: Option<String>,
        model_match_state: pl_protocol::ModelMatchState,
        effort: Option<String>,
    },
}
pub(super) struct IdentityMaterial {
    pub reference: ProductEntityRef,
    pub value: IdentityValue,
}
pub(in crate::studio::runtime) struct StatisticsMaterial {
    pub(super) entry: u64,
    pub(super) revision: u64,
    pub(super) key: Key,
    pub(super) root: Root,
    pub(super) collection: Option<ProductCollectionRef>,
    pub(super) entities: Vec<ProductEntityRef>,
    pub(super) identities: Vec<Arc<IdentityMaterial>>,
    pub(super) efforts: Vec<Vec<Arc<IdentityMaterial>>>,
}
/// 一次权威发布：轻量状态与固定读取材料在同一发布边界配对。
///
/// `revision` 是本来源的发布投影版本，只用于交付 stamp 与 `base_revision`；读取引用使用
/// 材料自身的版本，两者互不冒充，也不等价于传输交付序号。
pub(in crate::studio::runtime) struct StatisticsPublication {
    pub(super) revision: u64,
    pub(super) status: StatisticsStatus,
    pub(super) material: Arc<StatisticsMaterial>,
}
struct State {
    sealed: bool,
    failure: Option<StudioError>,
    next_entry: u64,
    /// 材料与身份版本域。
    revision: u64,
    /// 发布投影版本域：只有状态或材料实际改变时才推进。
    publication: u64,
    current: BTreeMap<Key, Arc<StatisticsPublication>>,
    roots: BTreeMap<(u64, u64), Weak<StatisticsMaterial>>,
    identities: BTreeMap<IdentityKey, Weak<IdentityMaterial>>,
    exposed_identities: BTreeMap<(u64, u64), Weak<IdentityMaterial>>,
    leases: BTreeMap<Key, Weak<()>>,
}
/// 一次发布的候选材料：先在 `State` 之外构造与校验，成功后再一起采用。
///
/// 任一候选构造失败（身份或版本空间溢出、资源不匹配）都不改变已发布状态，因此不会提交
/// 半个 summary/history pair，也不会覆盖 last-good。
struct Stage {
    revision: u64,
    next_entry: u64,
    identities: Vec<(IdentityKey, Arc<IdentityMaterial>)>,
    pending: Vec<(Key, Arc<StatisticsMaterial>)>,
}
impl Stage {
    fn new(state: &State) -> Self {
        Self {
            revision: state.revision,
            next_entry: state.next_entry,
            identities: Vec::new(),
            pending: Vec::new(),
        }
    }
    /// 为 `key` 形成候选：材料真实变化才重建，只变状态时沿用原不可变材料。
    fn plan(
        &mut self,
        state: &State,
        key: &Key,
        payload: Option<Root>,
        status: &StatisticsStatus,
    ) -> Result<Arc<StatisticsMaterial>, StudioError> {
        let previous = state
            .current
            .get(key)
            .map(|publication| (publication.status.clone(), publication.material.clone()));
        let Some((previous_status, previous_material)) = previous else {
            let Some(root) = payload else {
                return Err(cancelled());
            };
            let material = self.material(state, key.clone(), root, None)?;
            self.pending.push((key.clone(), material.clone()));
            return Ok(material);
        };
        // 较旧的读取结论不得回退已发布的材料与状态。
        if status.revision < previous_status.revision {
            return Ok(previous_material);
        }
        let reuse = payload
            .as_ref()
            .is_some_and(|root| *root == previous_material.root);
        let material = match payload {
            _ if reuse => previous_material.clone(),
            Some(root) => {
                self.material(state, key.clone(), root, Some(previous_material.clone()))?
            }
            None => previous_material.clone(),
        };
        let unchanged = previous_status == *status && Arc::ptr_eq(&previous_material, &material);
        if !unchanged {
            self.pending.push((key.clone(), material.clone()));
        }
        Ok(material)
    }
    fn material(
        &mut self,
        state: &State,
        key: Key,
        root: Root,
        previous: Option<Arc<StatisticsMaterial>>,
    ) -> Result<Arc<StatisticsMaterial>, StudioError> {
        let revision = self.advance()?;
        let entry = match (&previous, &key) {
            (Some(old), _) => old.entry,
            (_, Key::Summaries) => 1,
            (_, Key::History) => 3,
            _ => self.allocate()?,
        };
        let mut identities = Vec::new();
        let mut efforts = Vec::new();
        let mut entities = Vec::new();
        match (&key, &root) {
            (Key::Summaries, Root::Summaries(summaries)) => {
                for summary in summaries {
                    let summary_identity = self.identity(
                        state,
                        IdentityKey::Summary(summary.account_id.clone(), summary.model_id.clone()),
                        IdentityValue::Summary {
                            account_id: summary.account_id.clone(),
                            account_display_name: summary.account_display_name.clone(),
                            model_id: summary.model_id.clone(),
                        },
                    )?;
                    let old = previous.as_ref().and_then(|old| {
                        old.entities
                            .iter()
                            .position(|entity| entity.entry == summary_identity.reference.entry)
                            .map(|position| (old, position))
                    });
                    let entity_revision = match old {
                        Some((old, position)) if summary_at(old, position) == Some(summary) => {
                            old.entities[position].revision
                        }
                        _ => revision,
                    };
                    entities.push(ProductEntityRef {
                        entry: summary_identity.reference.entry,
                        revision: entity_revision,
                    });
                    identities.push(summary_identity);
                    let mut children = Vec::with_capacity(summary.effort_breakdowns.len());
                    for effort in &summary.effort_breakdowns {
                        children.push(self.identity(
                            state,
                            IdentityKey::Effort(
                                summary.account_id.clone(),
                                summary.model_id.clone(),
                                effort.effort.clone(),
                            ),
                            IdentityValue::Effort(effort.effort.clone()),
                        )?);
                    }
                    efforts.push(children);
                }
            }
            (
                Key::History,
                Root::History {
                    samples,
                    sample_keys,
                },
            ) => {
                for (sample, log) in samples.iter().zip(sample_keys.iter()) {
                    let identity = self.identity(
                        state,
                        IdentityKey::Sample(log.thread_id.clone(), log.call_id.clone()),
                        IdentityValue::Sample {
                            account_id: sample.account_id.clone(),
                            account_display_name: sample.account_display_name.clone(),
                            model_id: sample.model_id.clone(),
                            sent_model: sample.sent_model.clone(),
                            reported_model: sample.reported_model.clone(),
                            model_match_state: sample.model_match_state,
                            effort: sample.effort.clone(),
                        },
                    )?;
                    let old = previous.as_ref().and_then(|old| {
                        old.entities
                            .iter()
                            .position(|entity| entity.entry == identity.reference.entry)
                            .map(|position| (old, position))
                    });
                    let entity_revision = match old {
                        Some((old, position)) if sample_at(old, position) == Some(sample) => {
                            old.entities[position].revision
                        }
                        _ => revision,
                    };
                    entities.push(ProductEntityRef {
                        entry: identity.reference.entry,
                        revision: entity_revision,
                    });
                    identities.push(identity);
                }
            }
            (Key::Costs(_), Root::Costs(_)) => {}
            _ => {
                return Err(StudioError::invalid_argument(
                    "Statistics root/resource mismatch",
                ));
            }
        }
        let collection = if matches!(key, Key::Costs(_)) {
            None
        } else {
            let collection_revision = match &previous {
                Some(old) if old.entities == entities => {
                    old.collection.ok_or_else(expired)?.revision
                }
                Some(old) => checked_next(old.collection.ok_or_else(expired)?.revision)?,
                None => 1,
            };
            Some(ProductCollectionRef {
                entry: if key == Key::Summaries { 2 } else { 4 },
                revision: collection_revision,
                total: super::super::read_budget::count(entities.len())?,
            })
        };
        Ok(Arc::new(StatisticsMaterial {
            entry,
            revision,
            key,
            root,
            collection,
            entities,
            identities,
            efforts,
        }))
    }
    fn identity(
        &mut self,
        state: &State,
        key: IdentityKey,
        value: IdentityValue,
    ) -> Result<Arc<IdentityMaterial>, StudioError> {
        let old = state
            .identities
            .get(&key)
            .and_then(Weak::upgrade)
            .or_else(|| {
                self.identities
                    .iter()
                    .find(|(staged, _)| staged == &key)
                    .map(|(_, material)| material.clone())
            });
        if let Some(old) = &old
            && old.value == value
        {
            return Ok(old.clone());
        }
        let reference = match old {
            Some(old) => ProductEntityRef {
                entry: old.reference.entry,
                revision: checked_next(old.reference.revision)?,
            },
            None => ProductEntityRef {
                entry: self.allocate()?,
                revision: 1,
            },
        };
        let material = Arc::new(IdentityMaterial { reference, value });
        self.identities.push((key, material.clone()));
        Ok(material)
    }
    fn advance(&mut self) -> Result<u64, StudioError> {
        self.revision = checked_next(self.revision)?;
        Ok(self.revision)
    }
    fn allocate(&mut self) -> Result<u64, StudioError> {
        let entry = self.next_entry;
        self.next_entry = checked_next(entry)?;
        Ok(entry)
    }
    fn commit(self, state: &mut State, status: StatisticsStatus) -> Result<bool, StudioError> {
        if self.pending.is_empty() {
            return Ok(false);
        }
        let publication = checked_next(state.publication)?;
        state.publication = publication;
        state.revision = self.revision;
        state.next_entry = self.next_entry;
        for (key, identity) in self.identities {
            state.identities.insert(key, Arc::downgrade(&identity));
        }
        for (key, material) in self.pending {
            state.current.insert(
                key,
                Arc::new(StatisticsPublication {
                    revision: publication,
                    status: status.clone(),
                    material,
                }),
            );
        }
        Ok(true)
    }
}
pub(in crate::studio::runtime) struct StatisticsSource {
    origin: ProductReadOrigin,
    state: Mutex<State>,
    updates: tokio::sync::watch::Sender<()>,
}
impl StatisticsSource {
    pub(in crate::studio::runtime) fn new(origin: ProductReadOrigin) -> Arc<Self> {
        let (updates, _) = tokio::sync::watch::channel(());
        Arc::new(Self {
            origin,
            updates,
            state: Mutex::new(State {
                sealed: false,
                failure: None,
                next_entry: 10,
                revision: 0,
                publication: 0,
                current: BTreeMap::new(),
                roots: BTreeMap::new(),
                identities: BTreeMap::new(),
                exposed_identities: BTreeMap::new(),
                leases: BTreeMap::new(),
            }),
        })
    }
    pub(super) fn origin(&self) -> &ProductReadOrigin {
        &self.origin
    }
    pub(super) fn lease(&self, key: &Key) -> Result<Arc<()>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed {
            return Err(cancelled());
        }
        if let Some(lease) = state.leases.get(key).and_then(Weak::upgrade) {
            return Ok(lease);
        }
        state.leases.retain(|_, lease| lease.strong_count() != 0);
        // 费用观察额度只按不同 root 计；汇总/历史 lease 与魔数偏移都不参与，避免把无关资源
        // 算进额度或借"全部 len"猜边界。
        if matches!(key, Key::Costs(_)) && observed_cost_roots(&state) >= MAX_OBSERVED_COST_ROOTS {
            return Err(StudioError::new(
                StudioErrorCode::Overloaded,
                "Statistics observed-root capacity is exhausted",
                true,
            ));
        }
        let lease = Arc::new(());
        state.leases.insert(key.clone(), Arc::downgrade(&lease));
        Ok(lease)
    }
    pub(super) fn ensure_open(&self) -> Result<(), StudioError> {
        open(
            &self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner),
        )
    }
    /// Called with the original paired global/log-key publication, never fabricated timestamp keys.
    ///
    /// 状态与材料在同一发布边界配对；汇总与历史分别与各自的真实材料比较，一方变化不使另一方的
    /// 材料版本失效。配对长度错误、来源关闭或已失败时不在任一侧提交。
    pub(in crate::studio::runtime) fn publish_global(
        &self,
        value: StudioModelPerformanceSnapshot,
        sample_keys: Arc<[PerformanceSampleSource]>,
    ) -> Result<(), StudioError> {
        let result = self.publish_global_inner(value, sample_keys);
        self.capture_failure(&result);
        result
    }
    fn publish_global_inner(
        &self,
        value: StudioModelPerformanceSnapshot,
        sample_keys: Arc<[PerformanceSampleSource]>,
    ) -> Result<(), StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        open(&state)?;
        if value.history.len() != sample_keys.len() {
            return Err(StudioError::new(
                StudioErrorCode::Protocol,
                "Performance history/log identity lengths differ",
                false,
            ));
        }
        let status = StatisticsStatus::global(&value);
        let mut stage = Stage::new(&state);
        stage.plan(
            &state,
            &Key::Summaries,
            Some(Root::Summaries(value.summaries)),
            &status,
        )?;
        stage.plan(
            &state,
            &Key::History,
            Some(Root::History {
                samples: value.history,
                sample_keys,
            }),
            &status,
        )?;
        let published = stage.commit(&mut state, status)?;
        prune(&mut state);
        if published {
            self.updates.send_replace(());
        }
        Ok(())
    }
    pub(in crate::studio::runtime) fn publish_costs(
        &self,
        value: StudioSessionCostsState,
    ) -> Result<Arc<StatisticsMaterial>, StudioError> {
        let result = self.publish_costs_inner(value);
        self.capture_failure(&result);
        result
    }
    fn publish_costs_inner(
        &self,
        value: StudioSessionCostsState,
    ) -> Result<Arc<StatisticsMaterial>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        open(&state)?;
        let key = Key::Costs(value.root_thread_id.clone());
        // Empty, no-longer-borrowed root projections do not create a second unbounded root table.
        let observed = state
            .leases
            .iter()
            .filter(|(_, lease)| lease.strong_count() != 0)
            .map(|(key, _)| key.clone())
            .collect::<Vec<_>>();
        state
            .current
            .retain(|key, _| !matches!(key, Key::Costs(_)) || observed.contains(key));
        // 费用投影额度同样只计不同 root 的 `Key::Costs`，与观察准入使用同一上限。
        let cost_projections = state
            .current
            .keys()
            .filter(|key| matches!(key, Key::Costs(_)))
            .count();
        if !state.current.contains_key(&key) && cost_projections >= MAX_OBSERVED_COST_ROOTS {
            return Err(StudioError::new(
                StudioErrorCode::Overloaded,
                "Statistics root projection capacity is exhausted",
                true,
            ));
        }
        let status = StatisticsStatus::costs(&value);
        let mut stage = Stage::new(&state);
        let material = stage.plan(&state, &key, Some(Root::Costs(value.cost)), &status)?;
        let published = stage.commit(&mut state, status)?;
        prune(&mut state);
        if published {
            self.updates.send_replace(());
        }
        Ok(material)
    }
    pub(in crate::studio::runtime) fn publish_observed_costs(
        &self,
        value: StudioSessionCostsState,
    ) -> Result<(), StudioError> {
        let observed = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .leases
            .get(&Key::Costs(value.root_thread_id.clone()))
            .is_some_and(|lease| lease.strong_count() != 0);
        if observed {
            self.publish_costs(value)?;
        }
        Ok(())
    }
    /// 仍被 scope lease 观察的 root 集合。
    ///
    /// 只用于按观察生命周期回收空的费用状态，不参与发布版本、材料或费用事实。
    pub(in crate::studio::runtime) fn observed_costs(&self) -> std::collections::BTreeSet<String> {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .leases
            .iter()
            .filter(|(_, lease)| lease.strong_count() != 0)
            .filter_map(|(key, _)| match key {
                Key::Costs(root) => Some(root.clone()),
                Key::Summaries | Key::History => None,
            })
            .collect()
    }
    pub(super) fn observe(
        &self,
        key: &Key,
    ) -> Result<(Arc<StatisticsPublication>, tokio::sync::watch::Receiver<()>), StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        open(&state)?;
        Ok((
            state.current.get(key).cloned().ok_or_else(cancelled)?,
            self.updates.subscribe(),
        ))
    }
    pub(super) fn current(&self, key: &Key) -> Result<Arc<StatisticsPublication>, StudioError> {
        self.observe(key).map(|(value, _)| value)
    }
    pub(super) fn pin(
        &self,
        origin: &ProductReadOrigin,
        entry: u64,
        revision: u64,
        expected: fn(&Key) -> bool,
    ) -> Result<Arc<StatisticsMaterial>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed || origin != &self.origin {
            return Err(cancelled());
        }
        prune(&mut state);
        let material = state
            .roots
            .get(&(entry, revision))
            .and_then(Weak::upgrade)
            .ok_or_else(expired)?;
        if !expected(&material.key) {
            return Err(StudioError::invalid_argument(
                "Statistics reference belongs to another resource",
            ));
        }
        Ok(material)
    }
    pub(super) fn pin_identity(
        &self,
        origin: &ProductReadOrigin,
        reference: ProductEntityRef,
    ) -> Result<Arc<IdentityMaterial>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed || origin != &self.origin {
            return Err(cancelled());
        }
        prune(&mut state);
        state
            .exposed_identities
            .get(&(reference.entry, reference.revision))
            .and_then(Weak::upgrade)
            .ok_or_else(expired)
    }
    /// A material becomes pin-able only after its frame was actually sent.
    pub(super) fn send_exposing(
        &self,
        material: &Arc<StatisticsMaterial>,
        send: impl FnOnce() -> Result<bool, StudioError>,
    ) -> Result<bool, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed {
            return Err(cancelled());
        }
        let sent = send()?;
        if sent {
            state.roots.insert(
                (material.entry, material.revision),
                Arc::downgrade(material),
            );
            for identity in material
                .identities
                .iter()
                .chain(material.efforts.iter().flatten())
            {
                state.exposed_identities.insert(
                    (identity.reference.entry, identity.reference.revision),
                    Arc::downgrade(identity),
                );
            }
        }
        Ok(sent)
    }
    pub(in crate::studio::runtime) fn seal(&self) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sealed = true;
        self.updates.send_replace(());
    }
    fn capture_failure<T>(&self, result: &Result<T, StudioError>) {
        if let Err(error) = result
            && error.code != StudioErrorCode::Cancelled
            && !(error.code == StudioErrorCode::Overloaded && error.retryable)
        {
            self.state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .failure = Some(error.clone());
            self.updates.send_replace(());
        }
    }
    pub(in crate::studio::runtime) fn finish_close(&self) {
        self.seal();
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.current.clear();
        state.roots.clear();
        state.identities.clear();
        state.exposed_identities.clear();
        state.leases.clear();
    }
}
fn open(state: &State) -> Result<(), StudioError> {
    if state.sealed {
        return Err(cancelled());
    }
    if let Some(error) = &state.failure {
        return Err(error.clone());
    }
    Ok(())
}
fn summary_at(
    material: &StatisticsMaterial,
    index: usize,
) -> Option<&StudioModelPerformanceSummary> {
    match &material.root {
        Root::Summaries(summaries) => summaries.get(index),
        Root::History { .. } | Root::Costs(_) => None,
    }
}
fn sample_at(material: &StatisticsMaterial, index: usize) -> Option<&StudioModelPerformanceSample> {
    match &material.root {
        Root::History { samples, .. } => samples.get(index),
        Root::Summaries(_) | Root::Costs(_) => None,
    }
}
/// 当前仍被观察的**不同**费用 root 数量；`Key::Summaries`/`Key::History` 不占该额度。
fn observed_cost_roots(state: &State) -> usize {
    state
        .leases
        .iter()
        .filter(|(key, lease)| matches!(key, Key::Costs(_)) && lease.strong_count() != 0)
        .count()
}
fn prune(state: &mut State) {
    state.roots.retain(|_, value| value.strong_count() != 0);
    state
        .identities
        .retain(|_, value| value.strong_count() != 0);
    state
        .exposed_identities
        .retain(|_, value| value.strong_count() != 0);
}
fn checked_next(value: u64) -> Result<u64, StudioError> {
    value.checked_add(1).ok_or_else(|| {
        StudioError::new(
            StudioErrorCode::Overloaded,
            "Statistics identity space exhausted",
            false,
        )
    })
}
fn expired() -> StudioError {
    StudioError::new(
        StudioErrorCode::Superseded,
        "Statistics material is not exposed or retained by its original source",
        true,
    )
}
pub(super) fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Statistics source is closing",
        false,
    )
}

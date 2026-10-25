use super::super::model_performance::PerformanceSampleSource;
use crate::{
    StudioModelPerformanceSample, StudioModelPerformanceSnapshot, StudioModelPerformanceSummary,
    StudioSessionCostsState,
};
use pl_protocol::products::identity::{ProductCollectionRef, ProductEntityRef, ProductReadOrigin};
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, Weak};

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
pub(super) enum Key {
    Summaries,
    History,
    Costs(String),
}
#[derive(Clone, PartialEq)]
pub(super) enum Root {
    Global {
        value: Arc<StudioModelPerformanceSnapshot>,
        sample_keys: Arc<[PerformanceSampleSource]>,
    },
    Costs(StudioSessionCostsState),
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
struct State {
    sealed: bool,
    failure: Option<StudioError>,
    next_entry: u64,
    revision: u64,
    current: BTreeMap<Key, Arc<StatisticsMaterial>>,
    roots: BTreeMap<(u64, u64), Weak<StatisticsMaterial>>,
    identities: BTreeMap<IdentityKey, Weak<IdentityMaterial>>,
    exposed_identities: BTreeMap<(u64, u64), Weak<IdentityMaterial>>,
    leases: BTreeMap<Key, Weak<()>>,
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
        if matches!(key, Key::Costs(_)) && state.leases.len() >= 258 {
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
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed {
            Err(cancelled())
        } else if let Some(error) = &state.failure {
            Err(error.clone())
        } else {
            Ok(())
        }
    }
    /// Called with the original paired global/log-key publication, never fabricated timestamp keys.
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
        if state.sealed {
            return Err(cancelled());
        }
        if value.history.len() != sample_keys.len() {
            return Err(StudioError::new(
                StudioErrorCode::Protocol,
                "Performance history/log identity lengths differ",
                false,
            ));
        }
        if let Some(error) = &state.failure {
            return Err(error.clone());
        }
        let root = Root::Global {
            value: Arc::new(value),
            sample_keys,
        };
        publish(&mut state, Key::Summaries, root.clone())?;
        publish(&mut state, Key::History, root)?;
        prune(&mut state);
        self.updates.send_replace(());
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
        if state.sealed {
            return Err(cancelled());
        }
        if let Some(error) = &state.failure {
            return Err(error.clone());
        }
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
        if !state.current.contains_key(&key) && state.current.len() >= 258 {
            return Err(StudioError::new(
                StudioErrorCode::Overloaded,
                "Statistics root projection capacity is exhausted",
                true,
            ));
        }
        let material = publish(&mut state, key, Root::Costs(value))?;
        prune(&mut state);
        self.updates.send_replace(());
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
    pub(super) fn observe(
        &self,
        key: &Key,
    ) -> Result<(Arc<StatisticsMaterial>, tokio::sync::watch::Receiver<()>), StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed {
            return Err(cancelled());
        }
        if let Some(error) = &state.failure {
            return Err(error.clone());
        }
        Ok((
            state.current.get(key).cloned().ok_or_else(cancelled)?,
            self.updates.subscribe(),
        ))
    }
    pub(super) fn current(&self, key: &Key) -> Result<Arc<StatisticsMaterial>, StudioError> {
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
fn publish(
    state: &mut State,
    key: Key,
    root: Root,
) -> Result<Arc<StatisticsMaterial>, StudioError> {
    let previous = state.current.get(&key).cloned();
    if let Some(previous) = &previous {
        if previous.root == root {
            return Ok(previous.clone());
        }
        let revision = |root: &Root| match root {
            Root::Global { value, .. } => value.revision,
            Root::Costs(value) => value.revision,
        };
        if revision(&previous.root) > revision(&root) {
            return Ok(previous.clone());
        }
    }
    let revision = next(state.revision)?;
    let entry = match (&previous, &key) {
        (Some(old), _) => old.entry,
        (_, Key::Summaries) => 1,
        (_, Key::History) => 3,
        _ => allocate(state)?,
    };
    let mut identities = Vec::new();
    let mut efforts = Vec::new();
    let mut entities = Vec::new();
    match (&key, &root) {
        (Key::Summaries, Root::Global { value, .. }) => {
            for (index, summary) in value.summaries.iter().enumerate() {
                let summary_identity = identity(
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
                        .map(|index| (old, index))
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
                let mut children =
                    Vec::with_capacity(value.summaries[index].effort_breakdowns.len());
                for effort in &summary.effort_breakdowns {
                    children.push(identity(
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
        (Key::History, Root::Global { value, sample_keys }) => {
            for (sample, log) in value.history.iter().zip(sample_keys.iter()) {
                let identity = identity(
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
                        .map(|index| (old, index))
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
            Some(old) if old.entities == entities => old.collection.ok_or_else(expired)?.revision,
            Some(old) => next(old.collection.ok_or_else(expired)?.revision)?,
            None => 1,
        };
        Some(ProductCollectionRef {
            entry: if key == Key::Summaries { 2 } else { 4 },
            revision: collection_revision,
            total: super::super::read_budget::count(entities.len())?,
        })
    };
    let material = Arc::new(StatisticsMaterial {
        entry,
        revision,
        key: key.clone(),
        root,
        collection,
        entities,
        identities,
        efforts,
    });
    state.revision = revision;
    state.current.insert(key, material.clone());
    Ok(material)
}
fn summary_at(
    material: &StatisticsMaterial,
    index: usize,
) -> Option<&StudioModelPerformanceSummary> {
    match &material.root {
        Root::Global { value, .. } => value.summaries.get(index),
        _ => None,
    }
}
fn sample_at(material: &StatisticsMaterial, index: usize) -> Option<&StudioModelPerformanceSample> {
    match &material.root {
        Root::Global { value, .. } => value.history.get(index),
        _ => None,
    }
}
fn identity(
    state: &mut State,
    key: IdentityKey,
    value: IdentityValue,
) -> Result<Arc<IdentityMaterial>, StudioError> {
    let old = state.identities.get(&key).and_then(Weak::upgrade);
    if let Some(old) = &old
        && old.value == value
    {
        return Ok(old.clone());
    }
    let reference = match old {
        Some(old) => ProductEntityRef {
            entry: old.reference.entry,
            revision: next(old.reference.revision)?,
        },
        None => ProductEntityRef {
            entry: allocate(state)?,
            revision: 1,
        },
    };
    let material = Arc::new(IdentityMaterial { reference, value });
    state.identities.insert(key, Arc::downgrade(&material));
    Ok(material)
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
fn allocate(state: &mut State) -> Result<u64, StudioError> {
    let entry = state.next_entry;
    state.next_entry = next(entry)?;
    Ok(entry)
}
fn next(value: u64) -> Result<u64, StudioError> {
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

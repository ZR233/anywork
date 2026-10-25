use crate::{PersistenceStateSnapshot, StudioPersistenceQueueStateSnapshot};
use pl_protocol::products::{
    identity::*,
    references::{PersistenceQueueReadRef, PersistenceReadRef},
};
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::collections::{BTreeMap, VecDeque};
use std::sync::{Arc, Mutex, Weak};

pub(super) struct PersistenceSnapshot {
    pub revision: u64,
    pub reference: PersistenceReadRef,
    pub value: Arc<PersistenceStateSnapshot>,
}
struct PersistenceState {
    sealed: bool,
    revision: u64,
    current: Option<Arc<PersistenceSnapshot>>,
    exposed: BTreeMap<u64, Weak<PersistenceSnapshot>>,
    committed: VecDeque<Arc<PersistenceSnapshot>>,
    failure: Option<StudioError>,
}
pub(in crate::studio) struct PersistenceSource {
    origin: ProductReadOrigin,
    state: Mutex<PersistenceState>,
    updates: tokio::sync::watch::Sender<()>,
}
impl PersistenceSource {
    pub(in crate::studio) fn new(origin: ProductReadOrigin) -> Arc<Self> {
        let (updates, _) = tokio::sync::watch::channel(());
        Arc::new(Self {
            origin,
            state: Mutex::new(PersistenceState {
                sealed: false,
                revision: 0,
                current: None,
                exposed: BTreeMap::new(),
                committed: VecDeque::new(),
                failure: None,
            }),
            updates,
        })
    }
    pub(super) fn origin(&self) -> &ProductReadOrigin {
        &self.origin
    }
    pub(in crate::studio) fn publish(&self, value: PersistenceStateSnapshot) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed {
            return;
        }
        if let Err(error) = capture_persistence(&mut state, value) {
            state.failure = Some(error);
        }
        drop(state);
        self.updates.send_replace(());
    }
    pub(super) fn capture_committed(
        &self,
        value: PersistenceStateSnapshot,
    ) -> Result<Arc<PersistenceSnapshot>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        check(state.sealed, &state.failure)?;
        let snapshot = if let Some(current) = &state.current
            && *current.value == value
        {
            current.clone()
        } else {
            let revision = next(state.revision)?;
            state.revision = revision;
            Arc::new(PersistenceSnapshot {
                revision,
                reference: PersistenceReadRef { entry: 1, revision },
                value: Arc::new(value),
            })
        };
        state
            .exposed
            .insert(snapshot.revision, Arc::downgrade(&snapshot));
        state.committed.push_back(snapshot.clone());
        if state.committed.len() > 8 {
            state.committed.pop_front();
        }
        state.exposed.retain(|_, value| value.strong_count() > 0);
        Ok(snapshot)
    }
    pub(super) fn current(&self) -> Result<Arc<PersistenceSnapshot>, StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        check(state.sealed, &state.failure)?;
        state.current.clone().ok_or_else(cancelled)
    }
    pub(super) fn observe(
        &self,
    ) -> Result<(Arc<PersistenceSnapshot>, tokio::sync::watch::Receiver<()>), StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        check(state.sealed, &state.failure)?;
        Ok((
            state.current.clone().ok_or_else(cancelled)?,
            self.updates.subscribe(),
        ))
    }
    pub(super) fn is_sealed(&self) -> bool {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sealed
    }
    pub(super) fn ensure_open(&self) -> Result<(), StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        check(state.sealed, &state.failure)
    }
    pub(super) fn send_exposing(
        &self,
        snapshot: &Arc<PersistenceSnapshot>,
        send: impl FnOnce() -> Result<bool, StudioError>,
    ) -> Result<bool, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        check(state.sealed, &state.failure)?;
        let sent = send()?;
        if sent {
            state.exposed.retain(|_, value| value.strong_count() > 0);
            state
                .exposed
                .insert(snapshot.revision, Arc::downgrade(snapshot));
        }
        Ok(sent)
    }
    pub(super) fn pin(
        &self,
        origin: &ProductReadOrigin,
        reference: PersistenceReadRef,
    ) -> Result<Arc<PersistenceSnapshot>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        check(state.sealed, &state.failure)?;
        if origin != &self.origin
            || reference.entry != 1
            || reference.revision == 0
            || reference.revision > state.revision
        {
            return Err(unpublished());
        }
        state.exposed.retain(|_, value| value.strong_count() > 0);
        state
            .exposed
            .get(&reference.revision)
            .and_then(Weak::upgrade)
            .ok_or_else(expired)
    }
    pub(in crate::studio) fn seal(&self) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sealed = true;
        self.updates.send_replace(());
    }
    pub(in crate::studio) fn finish_close(&self) {
        self.seal();
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.current.take();
        state.exposed.clear();
        state.committed.clear();
    }
}
fn capture_persistence(
    state: &mut PersistenceState,
    value: PersistenceStateSnapshot,
) -> Result<(), StudioError> {
    if state
        .current
        .as_ref()
        .is_some_and(|current| *current.value == value)
    {
        return Ok(());
    }
    let revision = next(state.revision)?;
    state.revision = revision;
    state.current = Some(Arc::new(PersistenceSnapshot {
        revision,
        reference: PersistenceReadRef { entry: 1, revision },
        value: Arc::new(value),
    }));
    state.exposed.retain(|_, value| value.strong_count() > 0);
    Ok(())
}

pub(super) struct PersistenceQueueSnapshot {
    pub revision: u64,
    pub reference: PersistenceQueueReadRef,
    pub collection: ProductCollectionRef,
    pub entities: Vec<ProductEntityRef>,
    pub value: Arc<StudioPersistenceQueueStateSnapshot>,
}
struct QueueState {
    sealed: bool,
    revision: u64,
    next_entity: u64,
    current: Option<Arc<PersistenceQueueSnapshot>>,
    exposed: BTreeMap<u64, Weak<PersistenceQueueSnapshot>>,
    failure: Option<StudioError>,
}
pub(in crate::studio) struct PersistenceQueueSource {
    origin: ProductReadOrigin,
    state: Mutex<QueueState>,
    updates: tokio::sync::watch::Sender<()>,
}
impl PersistenceQueueSource {
    pub(in crate::studio) fn new(origin: ProductReadOrigin) -> Arc<Self> {
        let (updates, _) = tokio::sync::watch::channel(());
        Arc::new(Self {
            origin,
            state: Mutex::new(QueueState {
                sealed: false,
                revision: 0,
                next_entity: 3,
                current: None,
                exposed: BTreeMap::new(),
                failure: None,
            }),
            updates,
        })
    }
    pub(super) fn origin(&self) -> &ProductReadOrigin {
        &self.origin
    }
    pub(in crate::studio) fn publish(&self, value: StudioPersistenceQueueStateSnapshot) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed {
            return;
        }
        if let Err(error) = capture_queue(&mut state, value) {
            state.failure = Some(error);
        }
        drop(state);
        self.updates.send_replace(());
    }
    pub(super) fn current(&self) -> Result<Arc<PersistenceQueueSnapshot>, StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        check(state.sealed, &state.failure)?;
        state.current.clone().ok_or_else(cancelled)
    }
    pub(super) fn observe(
        &self,
    ) -> Result<
        (
            Arc<PersistenceQueueSnapshot>,
            tokio::sync::watch::Receiver<()>,
        ),
        StudioError,
    > {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        check(state.sealed, &state.failure)?;
        Ok((
            state.current.clone().ok_or_else(cancelled)?,
            self.updates.subscribe(),
        ))
    }
    pub(super) fn is_sealed(&self) -> bool {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sealed
    }
    pub(super) fn ensure_open(&self) -> Result<(), StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        check(state.sealed, &state.failure)
    }
    pub(super) fn send_exposing(
        &self,
        snapshot: &Arc<PersistenceQueueSnapshot>,
        send: impl FnOnce() -> Result<bool, StudioError>,
    ) -> Result<bool, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        check(state.sealed, &state.failure)?;
        let sent = send()?;
        if sent {
            state.exposed.retain(|_, value| value.strong_count() > 0);
            state
                .exposed
                .insert(snapshot.revision, Arc::downgrade(snapshot));
        }
        Ok(sent)
    }
    pub(super) fn pin(
        &self,
        origin: &ProductReadOrigin,
        reference: PersistenceQueueReadRef,
    ) -> Result<Arc<PersistenceQueueSnapshot>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        check(state.sealed, &state.failure)?;
        if origin != &self.origin
            || reference.entry != 1
            || reference.revision == 0
            || reference.revision > state.revision
        {
            return Err(unpublished());
        }
        state.exposed.retain(|_, value| value.strong_count() > 0);
        state
            .exposed
            .get(&reference.revision)
            .and_then(Weak::upgrade)
            .ok_or_else(expired)
    }
    pub(in crate::studio) fn seal(&self) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sealed = true;
        self.updates.send_replace(());
    }
    pub(in crate::studio) fn finish_close(&self) {
        self.seal();
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.current.take();
        state.exposed.clear();
    }
}
fn capture_queue(
    state: &mut QueueState,
    value: StudioPersistenceQueueStateSnapshot,
) -> Result<(), StudioError> {
    if state
        .current
        .as_ref()
        .is_some_and(|current| *current.value == value)
    {
        return Ok(());
    }
    let revision = next(state.revision)?;
    let mut entities = Vec::new();
    let mut ids = std::collections::BTreeSet::new();
    for thread in &value.queue.threads {
        if !ids.insert(&thread.thread_id) {
            return Err(StudioError::new(
                StudioErrorCode::Protocol,
                "Duplicate persistence Thread identity",
                false,
            ));
        }
        let previous = state.current.as_ref().and_then(|previous| {
            previous
                .value
                .queue
                .threads
                .iter()
                .position(|old| old.thread_id == thread.thread_id)
                .map(|index| {
                    (
                        &previous.value.queue.threads[index],
                        previous.entities[index],
                    )
                })
        });
        entities.push(match previous {
            Some((old, reference)) if old == thread => reference,
            Some((_, reference)) => ProductEntityRef {
                entry: reference.entry,
                revision: next(reference.revision)?,
            },
            None => {
                let entry = state.next_entity;
                state.next_entity = next(entry)?;
                ProductEntityRef { entry, revision: 1 }
            }
        });
    }
    state.revision = revision;
    state.current = Some(Arc::new(PersistenceQueueSnapshot {
        revision,
        reference: PersistenceQueueReadRef { entry: 1, revision },
        collection: ProductCollectionRef {
            entry: 2,
            revision,
            total: value.queue.threads.len() as u64,
        },
        entities,
        value: Arc::new(value),
    }));
    state.exposed.retain(|_, value| value.strong_count() > 0);
    Ok(())
}
fn next(value: u64) -> Result<u64, StudioError> {
    value.checked_add(1).ok_or_else(|| {
        StudioError::new(
            StudioErrorCode::Overloaded,
            "Persistence identity exhausted",
            false,
        )
    })
}
fn check(sealed: bool, failure: &Option<StudioError>) -> Result<(), StudioError> {
    if sealed {
        Err(cancelled())
    } else {
        failure.clone().map_or(Ok(()), Err)
    }
}
fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Persistence source is closing or unavailable",
        false,
    )
}
fn unpublished() -> StudioError {
    StudioError::invalid_argument("Persistence reference/origin was not issued by this source")
}
fn expired() -> StudioError {
    StudioError::new(
        StudioErrorCode::Superseded,
        "The original Persistence publication expired or was not exposed",
        true,
    )
}

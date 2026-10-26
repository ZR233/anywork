use super::AccountUsageStateSnapshot;
use pl_protocol::products::identity::{
    ProductCollectionRef, ProductEntityRef, ProductReadOrigin, ProductSourceStatusRef,
};
use pl_protocol::products::references::{AccountUsageReadRef, AccountUsageReadTarget};
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::collections::{BTreeMap, VecDeque};
use std::sync::{Arc, Mutex, Weak};

pub(in crate::studio::runtime) struct UsageMaterial {
    pub reference: AccountUsageReadRef,
    pub status: ProductSourceStatusRef,
    pub collection: Option<ProductCollectionRef>,
    pub entities: Vec<ProductEntityRef>,
    pub value: AccountUsageStateSnapshot,
}
struct State {
    sealed: bool,
    failure: Option<StudioError>,
    next_entity: u64,
    revision: u64,
    current: Option<Arc<UsageMaterial>>,
    exposed: BTreeMap<u64, Weak<UsageMaterial>>,
    commands: VecDeque<Arc<UsageMaterial>>,
}
pub(in crate::studio::runtime) struct UsageSource {
    origin: ProductReadOrigin,
    state: Mutex<State>,
    updates: tokio::sync::watch::Sender<()>,
}
impl UsageSource {
    pub(in crate::studio::runtime) fn new(origin: ProductReadOrigin) -> Arc<Self> {
        let (updates, _) = tokio::sync::watch::channel(());
        Arc::new(Self {
            origin,
            updates,
            state: Mutex::new(State {
                sealed: false,
                failure: None,
                next_entity: 4,
                revision: 0,
                current: None,
                exposed: BTreeMap::new(),
                commands: VecDeque::new(),
            }),
        })
    }
    pub(super) fn origin(&self) -> &ProductReadOrigin {
        &self.origin
    }
    pub(in crate::studio::runtime) fn publish(
        &self,
        value: AccountUsageStateSnapshot,
    ) -> Result<Arc<UsageMaterial>, StudioError> {
        let result = self.publish_inner(value);
        if let Err(error) = &result
            && error.code != StudioErrorCode::Cancelled
        {
            self.state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .failure = Some(error.clone());
            self.updates.send_replace(());
        }
        result
    }
    fn publish_inner(
        &self,
        value: AccountUsageStateSnapshot,
    ) -> Result<Arc<UsageMaterial>, StudioError> {
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
        if let Some(old) = &state.current
            && old.value == value
        {
            return Ok(old.clone());
        }
        let revision = next(state.revision)?;
        let mut next_entity = state.next_entity;
        let mut entities = Vec::new();
        if let Some(data) = value.state.value() {
            for usage in &data.usages {
                let old = state.current.as_ref().and_then(|old| {
                    old.value.state.value().and_then(|data| {
                        data.usages
                            .iter()
                            .zip(&old.entities)
                            .find(|(old, _)| old.account_id() == usage.account_id())
                    })
                });
                let reference = if let Some((old, reference)) = old {
                    ProductEntityRef {
                        entry: reference.entry,
                        revision: if old == usage {
                            reference.revision
                        } else {
                            revision
                        },
                    }
                } else {
                    let entry = next_entity;
                    next_entity = next(next_entity)?;
                    ProductEntityRef { entry, revision: 1 }
                };
                entities.push(reference);
            }
        }
        let collection = value
            .state
            .value()
            .map(|_| -> Result<_, StudioError> {
                let old = state.current.as_ref();
                let collection_revision = match old.and_then(|old| old.collection) {
                    Some(collection) if old.is_some_and(|old| old.entities == entities) => {
                        collection.revision
                    }
                    _ => revision,
                };
                Ok(ProductCollectionRef {
                    entry: 2,
                    revision: collection_revision,
                    total: super::super::read_budget::count(entities.len())?,
                })
            })
            .transpose()?;
        let material = Arc::new(UsageMaterial {
            reference: AccountUsageReadRef { entry: 1, revision },
            status: ProductSourceStatusRef { entry: 3, revision },
            collection,
            entities,
            value,
        });
        let latest = !state
            .current
            .as_ref()
            .is_some_and(|old| old.value.state.revision() > material.value.state.revision());
        if latest {
            state.current = Some(material.clone());
        }
        state.revision = revision;
        state.next_entity = next_entity;
        state.exposed.retain(|_, pin| pin.strong_count() != 0);
        if latest {
            self.updates.send_replace(());
        }
        Ok(material)
    }
    pub(super) fn observe(
        &self,
    ) -> Result<(Arc<UsageMaterial>, tokio::sync::watch::Receiver<()>), StudioError> {
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
            state.current.clone().ok_or_else(cancelled)?,
            self.updates.subscribe(),
        ))
    }
    pub(super) fn current(&self) -> Result<Arc<UsageMaterial>, StudioError> {
        self.observe().map(|(value, _)| value)
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
    fn pin_revision(
        &self,
        origin: &ProductReadOrigin,
        entry: u64,
        expected_entry: u64,
        revision: u64,
    ) -> Result<Arc<UsageMaterial>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed || origin != &self.origin {
            return Err(cancelled());
        }
        state.exposed.retain(|_, pin| pin.strong_count() != 0);
        if entry != expected_entry || revision == 0 || revision > state.revision {
            return Err(StudioError::invalid_argument(
                "Usage reference was not issued by this source",
            ));
        }
        state
            .exposed
            .get(&revision)
            .and_then(Weak::upgrade)
            .ok_or_else(|| {
                StudioError::new(
                    StudioErrorCode::Superseded,
                    "Original Usage material is not exposed or retained",
                    true,
                )
            })
    }
    pub(super) fn pin(
        &self,
        origin: &ProductReadOrigin,
        reference: AccountUsageReadRef,
    ) -> Result<Arc<UsageMaterial>, StudioError> {
        let material = self.pin_revision(origin, reference.entry, 1, reference.revision)?;
        if material.value.state.value().is_none() {
            return Err(StudioError::invalid_argument(
                "Usage source has no readable value",
            ));
        }
        Ok(material)
    }
    pub(super) fn pin_status(
        &self,
        origin: &ProductReadOrigin,
        reference: ProductSourceStatusRef,
    ) -> Result<Arc<UsageMaterial>, StudioError> {
        self.pin_revision(origin, reference.entry, 3, reference.revision)
    }
    pub(super) fn send_exposing(
        &self,
        material: &Arc<UsageMaterial>,
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
            state
                .exposed
                .insert(material.reference.revision, Arc::downgrade(material));
        }
        Ok(sent)
    }
    pub(in crate::studio::runtime) fn expose_committed(
        &self,
        material: Arc<UsageMaterial>,
    ) -> Result<AccountUsageReadTarget, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed {
            return Err(cancelled());
        }
        let target = AccountUsageReadTarget {
            origin: self.origin.clone(),
            reference: material.reference,
        };
        state
            .exposed
            .insert(material.reference.revision, Arc::downgrade(&material));
        state.commands.push_back(material);
        while state.commands.len() > 8 {
            state.commands.pop_front();
        }
        Ok(target)
    }
    pub(in crate::studio::runtime) fn seal(&self) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sealed = true;
        self.updates.send_replace(());
    }
    pub(in crate::studio::runtime) fn finish_close(&self) {
        self.seal();
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.current.take();
        state.commands.clear();
        state.exposed.clear();
    }
}
fn next(value: u64) -> Result<u64, StudioError> {
    value.checked_add(1).ok_or_else(|| {
        StudioError::new(
            StudioErrorCode::Overloaded,
            "Usage identity space exhausted",
            false,
        )
    })
}
pub(super) fn cancelled() -> StudioError {
    StudioError::new(StudioErrorCode::Cancelled, "Usage source is closing", false)
}

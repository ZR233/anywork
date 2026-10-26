//! Native identities are issued before transport coalescing. Only actual sends/commands expose.
use pl_protocol::ThreadModeCatalogSnapshot;
use pl_protocol::products::identity::{ProductCollectionRef, ProductEntityRef, ProductReadOrigin};
use pl_protocol::products::references::{ModeCatalogReadRef, ModeCatalogReadTarget};
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::collections::{BTreeMap, VecDeque};
use std::sync::{Arc, Mutex, Weak};

pub(in crate::studio::runtime) struct ModesMaterial {
    pub reference: ModeCatalogReadRef,
    pub collection: ProductCollectionRef,
    pub entities: Vec<ProductEntityRef>,
    pub value: ThreadModeCatalogSnapshot,
}
struct State {
    sealed: bool,
    failure: Option<StudioError>,
    next_entity: u64,
    revision: u64,
    current: Option<Arc<ModesMaterial>>,
    exposed: BTreeMap<u64, Weak<ModesMaterial>>,
    commands: VecDeque<Arc<ModesMaterial>>,
}
pub(in crate::studio::runtime) struct ModesSource {
    origin: ProductReadOrigin,
    state: Mutex<State>,
    updates: tokio::sync::watch::Sender<()>,
}
impl ModesSource {
    pub(in crate::studio::runtime) fn new(origin: ProductReadOrigin) -> Arc<Self> {
        let (updates, _) = tokio::sync::watch::channel(());
        Arc::new(Self {
            origin,
            updates,
            state: Mutex::new(State {
                sealed: false,
                failure: None,
                next_entity: 3,
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
        value: ThreadModeCatalogSnapshot,
    ) -> Result<Arc<ModesMaterial>, StudioError> {
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
        value: ThreadModeCatalogSnapshot,
    ) -> Result<Arc<ModesMaterial>, StudioError> {
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
        let mut entities = Vec::with_capacity(value.modes.len());
        for item in &value.modes {
            let old = state.current.as_ref().and_then(|old| {
                old.value
                    .modes
                    .iter()
                    .zip(&old.entities)
                    .find(|(mode, _)| mode.id == item.id)
            });
            let reference = if let Some((old, reference)) = old {
                ProductEntityRef {
                    entry: reference.entry,
                    revision: if old == item {
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
        let collection_revision = match &state.current {
            Some(old) if old.entities == entities => old.collection.revision,
            _ => revision,
        };
        let total = super::super::read_budget::count(entities.len())?;
        let material = Arc::new(ModesMaterial {
            reference: ModeCatalogReadRef { entry: 1, revision },
            collection: ProductCollectionRef {
                entry: 2,
                revision: collection_revision,
                total,
            },
            entities,
            value,
        });
        let latest = !state
            .current
            .as_ref()
            .is_some_and(|old| old.value.revision > material.value.revision);
        state.next_entity = next_entity;
        state.revision = revision;
        if latest {
            state.current = Some(material.clone());
        }
        state.exposed.retain(|_, pin| pin.strong_count() != 0);
        if latest {
            self.updates.send_replace(());
        }
        Ok(material)
    }
    pub(super) fn observe(
        &self,
    ) -> Result<(Arc<ModesMaterial>, tokio::sync::watch::Receiver<()>), StudioError> {
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
    pub(super) fn current(&self) -> Result<Arc<ModesMaterial>, StudioError> {
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
    pub(super) fn pin(
        &self,
        origin: &ProductReadOrigin,
        reference: ModeCatalogReadRef,
    ) -> Result<Arc<ModesMaterial>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed || origin != &self.origin {
            return Err(cancelled());
        }
        state.exposed.retain(|_, pin| pin.strong_count() != 0);
        if reference.entry != 1 || reference.revision == 0 || reference.revision > state.revision {
            return Err(StudioError::invalid_argument(
                "Mode reference was not issued by this source",
            ));
        }
        state
            .exposed
            .get(&reference.revision)
            .and_then(Weak::upgrade)
            .ok_or_else(|| {
                StudioError::new(
                    StudioErrorCode::Superseded,
                    "The requested Mode material is not exposed or retained",
                    true,
                )
            })
    }
    /// The bounded synchronous callback must never reenter this source (including inline reads).
    pub(super) fn send_exposing(
        &self,
        material: &Arc<ModesMaterial>,
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
    pub(super) fn expose_committed(
        &self,
        material: Arc<ModesMaterial>,
    ) -> Result<ModeCatalogReadTarget, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed {
            return Err(cancelled());
        }
        state
            .exposed
            .insert(material.reference.revision, Arc::downgrade(&material));
        let target = ModeCatalogReadTarget {
            origin: self.origin.clone(),
            reference: material.reference,
        };
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
            "Mode identities exhausted",
            false,
        )
    })
}
pub(super) fn cancelled() -> StudioError {
    StudioError::new(StudioErrorCode::Cancelled, "Mode source is closing", false)
}

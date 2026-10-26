//! Independent Profiles source. The original resource publishes under its adoption guard;
//! only an actual feed send or an owned command's original capture exposes read references.
use std::collections::BTreeMap;
use std::sync::{
    Arc, Mutex, Weak,
    atomic::{AtomicBool, Ordering},
};

use pl_protocol::products::identity::{
    ProductCollectionRef, ProductEntityRef, ProductReadOrigin, ProductSourceStatusRef,
};
use pl_protocol::products::references::AgentProfilesReadRef;
use pl_protocol::studio::{StudioError, StudioErrorCode};

use super::{AgentProfileCatalog, runtime::ConfigurationStatusMaterial};

#[derive(Debug)]
pub(crate) struct ProfilesCaptureFailure {
    pub(crate) diagnostic: StudioError,
}
impl ProfilesCaptureFailure {
    pub(super) fn new(error: StudioError) -> Arc<Self> {
        Arc::new(Self { diagnostic: error })
    }
}

pub(crate) struct ProfilesMaterial {
    pub(crate) reference: AgentProfilesReadRef,
    pub(crate) collection: ProductCollectionRef,
    pub(crate) entities: Vec<ProductEntityRef>,
    pub(crate) value: AgentProfileCatalog,
}

pub(crate) struct ProfilesSnapshot {
    pub(crate) origin: ProductReadOrigin,
    pub(crate) revision: u64,
    pub(crate) profiles_revision: u64,
    pub(crate) source_status: Result<Arc<ConfigurationStatusMaterial>, Arc<ProfilesCaptureFailure>>,
    pub(crate) material: Result<Arc<ProfilesMaterial>, Arc<ProfilesCaptureFailure>>,
    pub(crate) last_failure: Option<Arc<ProfilesCaptureFailure>>,
}

struct State {
    current: Option<Arc<ProfilesSnapshot>>,
    // Pointer provenance, not a second revision clock. A terminal capture failure can retain
    // the exhausted watermark, but must not replace the last valid, still-owned capture.
    issued: Vec<Weak<ProfilesSnapshot>>,
    values: BTreeMap<u64, Weak<ProfilesMaterial>>,
    statuses: BTreeMap<u64, Weak<ConfigurationStatusMaterial>>,
}

/// Lock order is canonical AgentProfilesResource -> this source. No reverse acquisition.
/// Historical locators are weak; current, unACKed deliveries, read scopes and owned command
/// results are the only pins. A guessed reference cannot pin unpublished current material.
pub(crate) struct ProfilesSource {
    origin: ProductReadOrigin,
    sealed: AtomicBool,
    state: Mutex<State>,
    updates: tokio::sync::watch::Sender<()>,
}
impl ProfilesSource {
    pub(super) fn new(origin: ProductReadOrigin) -> Arc<Self> {
        let (updates, _) = tokio::sync::watch::channel(());
        Arc::new(Self {
            origin,
            sealed: AtomicBool::new(false),
            updates,
            state: Mutex::new(State {
                current: None,
                issued: Vec::new(),
                values: BTreeMap::new(),
                statuses: BTreeMap::new(),
            }),
        })
    }
    pub(crate) fn origin(&self) -> &ProductReadOrigin {
        &self.origin
    }
    pub(crate) fn ensure_open(&self) -> Result<(), StudioError> {
        if self.sealed.load(Ordering::Acquire) {
            Err(cancelled())
        } else {
            Ok(())
        }
    }
    pub(crate) fn observe(
        &self,
    ) -> Result<(Arc<ProfilesSnapshot>, tokio::sync::watch::Receiver<()>), StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let updates = self.updates.subscribe();
        self.ensure_open()?;
        Ok((state.current.clone().ok_or_else(cancelled)?, updates))
    }
    pub(crate) fn current(&self) -> Result<Arc<ProfilesSnapshot>, StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.ensure_open()?;
        state.current.clone().ok_or_else(cancelled)
    }
    pub(crate) fn pin(
        &self,
        origin: &ProductReadOrigin,
        reference: AgentProfilesReadRef,
    ) -> Result<Arc<ProfilesMaterial>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_origin(origin)?;
        state.values.retain(|_, value| value.strong_count() != 0);
        if reference.entry != 1 || reference.revision == 0 {
            return Err(unpublished());
        }
        state
            .values
            .get(&reference.revision)
            .and_then(Weak::upgrade)
            .ok_or_else(expired)
    }
    pub(crate) fn pin_source_status(
        &self,
        origin: &ProductReadOrigin,
        reference: ProductSourceStatusRef,
    ) -> Result<Arc<ConfigurationStatusMaterial>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_origin(origin)?;
        state.statuses.retain(|_, value| value.strong_count() != 0);
        if reference.entry != 3 || reference.revision == 0 {
            return Err(unpublished());
        }
        state
            .statuses
            .get(&reference.revision)
            .and_then(Weak::upgrade)
            .ok_or_else(expired)
    }
    /// The bounded synchronous transport callback must not re-enter the source. Exposure and
    /// successful send commit together, so readers cannot race ahead of publication.
    pub(crate) fn send_exposing(
        &self,
        snapshot: &ProfilesSnapshot,
        send: impl FnOnce() -> Result<bool, StudioError>,
    ) -> Result<bool, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_origin(&snapshot.origin)?;
        let sent = send()?;
        if sent {
            expose(&mut state, snapshot);
        }
        Ok(sent)
    }
    /// An owned command exposes only its original adopted capture, never current or Feed Data.
    /// The caller retains that capture until actual call close; this grants no ACK credit.
    pub(crate) fn expose_committed(
        &self,
        snapshot: &Arc<ProfilesSnapshot>,
        expected_profiles_revision: u64,
    ) -> Result<(), StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_origin(&snapshot.origin)?;
        state.issued.retain(|issued| issued.strong_count() != 0);
        if !state
            .issued
            .iter()
            .filter_map(Weak::upgrade)
            .any(|issued| Arc::ptr_eq(&issued, snapshot))
        {
            return Err(unpublished());
        }
        if snapshot.revision == 0 || snapshot.profiles_revision != expected_profiles_revision {
            return Err(unpublished());
        }
        let material = snapshot
            .material
            .as_ref()
            .map_err(|failure| failure.diagnostic.clone())?;
        let status = snapshot
            .source_status
            .as_ref()
            .map_err(|failure| failure.diagnostic.clone())?;
        if material.reference.entry != 1
            || material.reference.revision == 0
            || material.collection.entry != 2
            || material.collection.revision == 0
            || status.header.status.entry != 3
            || status.header.status.revision == 0
        {
            return Err(unpublished());
        }
        expose(&mut state, snapshot);
        Ok(())
    }
    pub(super) fn publish(&self, snapshot: Arc<ProfilesSnapshot>, closing: bool) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.issued.retain(|issued| issued.strong_count() != 0);
        state.issued.push(Arc::downgrade(&snapshot));
        state.current = Some(snapshot);
        state.values.retain(|_, value| value.strong_count() != 0);
        state.statuses.retain(|_, value| value.strong_count() != 0);
        if closing {
            self.sealed.store(true, Ordering::Release);
        }
    }
    pub(super) fn notify(&self) {
        self.updates.send_replace(());
    }
    pub(crate) fn seal(&self) {
        self.sealed.store(true, Ordering::Release);
        self.notify();
    }
    /// Called by runtime shutdown only after original read and transport owners really joined.
    pub(crate) fn finish_close(&self) {
        self.seal();
        let current = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.issued.clear();
            state.values.clear();
            state.statuses.clear();
            state.current.take()
        };
        drop(current);
    }
    fn check_origin(&self, origin: &ProductReadOrigin) -> Result<(), StudioError> {
        self.ensure_open()?;
        if origin != &self.origin {
            return Err(unpublished());
        }
        Ok(())
    }
}
fn expose(state: &mut State, snapshot: &ProfilesSnapshot) {
    if let Ok(material) = &snapshot.material {
        state
            .values
            .insert(material.reference.revision, Arc::downgrade(material));
    }
    if let Ok(status) = &snapshot.source_status {
        state
            .statuses
            .insert(status.header.status.revision, Arc::downgrade(status));
    }
}

/// Every adopted membership transition is captured even if all watchers coalesce notifications.
/// A failed identity allocation is terminal for this source history, not a reusable last ID.
pub(super) fn capture(
    previous: Option<&ProfilesMaterial>,
    catalog: AgentProfileCatalog,
    next_entity: &mut u64,
) -> Result<Arc<ProfilesMaterial>, Arc<ProfilesCaptureFailure>> {
    let old: BTreeMap<_, _> =
        previous
            .into_iter()
            .flat_map(|material| {
                material.value.profiles.iter().zip(&material.entities).map(
                    |(profile, reference)| (profile.profile_id.as_str(), (profile, *reference)),
                )
            })
            .collect();
    let mut allocation = *next_entity;
    let mut entities = Vec::with_capacity(catalog.profiles.len());
    for profile in &catalog.profiles {
        let reference = match old.get(profile.profile_id.as_str()) {
            Some((value, reference)) => ProductEntityRef {
                entry: reference.entry,
                revision: if *value == profile {
                    reference.revision
                } else {
                    next(reference.revision)?
                },
            },
            None => {
                let entry = allocation;
                allocation = next(allocation)?;
                ProductEntityRef { entry, revision: 1 }
            }
        };
        entities.push(reference);
    }
    let revision = previous.map_or(Ok(1), |value| next(value.reference.revision))?;
    let collection_revision = match previous {
        Some(value) if value.entities == entities => value.collection.revision,
        Some(value) => next(value.collection.revision)?,
        None => 1,
    };
    let total = u64::try_from(entities.len()).map_err(|_| exhausted())?;
    *next_entity = allocation;
    Ok(Arc::new(ProfilesMaterial {
        reference: AgentProfilesReadRef { entry: 1, revision },
        collection: ProductCollectionRef {
            entry: 2,
            revision: collection_revision,
            total,
        },
        entities,
        value: catalog,
    }))
}
pub(super) fn next(value: u64) -> Result<u64, Arc<ProfilesCaptureFailure>> {
    value.checked_add(1).ok_or_else(exhausted)
}
fn exhausted() -> Arc<ProfilesCaptureFailure> {
    ProfilesCaptureFailure::new(StudioError::new(
        StudioErrorCode::Overloaded,
        "Profiles capture identity or revision is exhausted",
        false,
    ))
}
fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Profiles source is closing",
        false,
    )
}
fn unpublished() -> StudioError {
    StudioError::new(
        StudioErrorCode::Protocol,
        "Profiles reference was not issued by this original source",
        false,
    )
}
fn expired() -> StudioError {
    StudioError::new(
        StudioErrorCode::NotFound,
        "The original Profiles reference is unpublished or its material has expired",
        false,
    )
}

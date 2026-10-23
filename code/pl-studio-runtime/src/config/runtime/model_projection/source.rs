//! Current Models material is advanced by ConfigRuntime, before any coalescible notification.
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, Weak, atomic::{AtomicBool, Ordering}};

use pl_protocol::products::identity::{ProductCollectionRef, ProductEntityRef, ProductReadOrigin};
use pl_protocol::products::references::ModelCatalogReadRef;
use pl_protocol::studio::{ConfigProjectionStamp, StudioError, StudioErrorCode};

use super::{CapturedModels, ModelCatalogMaterial};

const VALUE_ENTRY: u64 = 1;
const COLLECTION_ENTRY: u64 = 2;

/// The original failure is retained internally; only the redacted typed diagnostic crosses wire.
#[derive(Debug, thiserror::Error)]
#[error("Models publication could not capture its canonical material")]
pub(crate) struct ModelCaptureFailure {
    pub(crate) diagnostic: StudioError,
    #[source]
    cause: anyhow::Error,
}

impl ModelCaptureFailure {
    pub(in crate::config::runtime) fn capture(cause: anyhow::Error) -> Arc<Self> {
        let diagnostic = cause.downcast_ref::<StudioError>().cloned().unwrap_or_else(|| {
            StudioError::new(StudioErrorCode::Unavailable,
                "The canonical Models material could not be captured", true)
        });
        Arc::new(Self { diagnostic, cause })
    }
}

/// An immutable publication, including the real compatible source watermarks. The last failure
/// token survives recovery: a slow feed can detect a failed capture even if watch merged it away.
/// Only one failure is retained, not an error log or a strong history of business values.
pub(crate) struct ModelsSnapshot {
    pub(crate) revision: u64,
    pub(crate) stamp: ConfigProjectionStamp,
    pub(crate) updated_at: i64,
    pub(crate) material: Result<Arc<ModelCatalogMaterial>, Arc<ModelCaptureFailure>>,
    pub(crate) last_failure: Option<Arc<ModelCaptureFailure>>,
}

struct SourceState {
    current: Option<Arc<ModelsSnapshot>>,
    versions: BTreeMap<u64, Weak<ModelCatalogMaterial>>,
    next_entity: u64,
    value_revision: u64,
    collection_revision: u64,
    projection_revision: u64,
    last_failure: Option<Arc<ModelCaptureFailure>>,
    exhausted: bool,
}

/// One Models projection instance bound once to the runtime's original epoch/incarnation.
/// Lock order is ConfigRuntime state -> this state; no method here acquires ConfigRuntime.
pub(crate) struct ModelCatalogSource {
    origin: ProductReadOrigin,
    sealed: AtomicBool,
    state: Mutex<SourceState>,
    updates: tokio::sync::watch::Sender<()>,
}

impl ModelCatalogSource {
    pub(in crate::config::runtime) fn new(origin: ProductReadOrigin, stamp: ConfigProjectionStamp, updated_at: i64,
        captured: Result<Arc<CapturedModels>, Arc<ModelCaptureFailure>>) -> Arc<Self> {
        let (updates, _) = tokio::sync::watch::channel(());
        let source = Arc::new(Self { origin, sealed: AtomicBool::new(false), updates,
            state: Mutex::new(SourceState { current: None, versions: BTreeMap::new(),
                next_entity: 3, value_revision: 0, collection_revision: 0,
                projection_revision: 0, last_failure: None, exhausted: false }) });
        source.publish(stamp, updated_at, captured);
        source
    }

    pub(crate) fn origin(&self) -> &ProductReadOrigin { &self.origin }

    /// Registration and the already-published current material share the same guard. The watch
    /// has no payload/history; consumers inspect this source, never recapture Configuration.
    pub(crate) fn observe(&self) -> Result<(Arc<ModelsSnapshot>, tokio::sync::watch::Receiver<()>), StudioError> {
        self.ensure_open()?;
        let state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        // Register before the final admission check: an already-seen seal must be rejected;
        // a later seal advances this receiver's version even before its first changed() call.
        let updates = self.updates.subscribe();
        self.ensure_open()?;
        let current = state.current.clone().ok_or_else(cancelled)?;
        Ok((current, updates))
    }

    pub(crate) fn current(&self) -> Result<Arc<ModelsSnapshot>, StudioError> {
        self.ensure_open()?;
        let state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        self.ensure_open()?;
        state.current.clone().ok_or_else(cancelled)
    }

    /// Only current/unACK/pending/scope ownership can keep a version resolvable. Expired weak
    /// locators are pruned, and an old ref is never satisfied with today's canonical value.
    pub(crate) fn pin(&self, origin: &ProductReadOrigin, reference: ModelCatalogReadRef)
        -> Result<Arc<ModelCatalogMaterial>, StudioError> {
        self.ensure_open()?;
        if origin != &self.origin { return Err(cancelled()); }
        let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        self.ensure_open()?;
        state.versions.retain(|_, material| material.strong_count() != 0);
        if reference.entry != VALUE_ENTRY || reference.revision == 0 || reference.revision > state.value_revision {
            return Err(StudioError::new(StudioErrorCode::Unavailable,
                "The requested Models value was not published by this source", false));
        }
        state.versions.get(&reference.revision).and_then(Weak::upgrade).ok_or_else(|| {
            StudioError::new(StudioErrorCode::Superseded,
                "The requested immutable Models value is no longer retained", true)
        })
    }

    /// The original runtime close fence can seal this source without waiting for config commands.
    /// Published data is guarded separately; this atomic carries only the one-way admission fact.
    pub(crate) fn seal(&self) {
        self.sealed.store(true, Ordering::Release);
        self.updates.send_replace(());
    }

    /// Called only after the original read/scope owners have genuinely joined. A failed close
    /// retains the source and its current material for the same unresolved responsibility.
    pub(crate) fn finish_close(&self) {
        self.seal();
        let current = {
            let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
            state.versions.clear();
            state.current.take()
        };
        drop(current);
    }

    fn ensure_open(&self) -> Result<(), StudioError> {
        if self.sealed.load(Ordering::Acquire) { Err(cancelled()) } else { Ok(()) }
    }

    /// This named owner operation is only called under ConfigRuntime's canonical write guard.
    /// No await, IO or external consumer runs between identity advancement and publication.
    pub(in crate::config::runtime) fn publish(&self, stamp: ConfigProjectionStamp, updated_at: i64,
        captured: Result<Arc<CapturedModels>, Arc<ModelCaptureFailure>>) {
        if self.ensure_open().is_err() { return; }
        let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if self.ensure_open().is_err() { return; }
        if state.exhausted {
            drop(state);
            if stamp.closing { self.seal(); }
            return;
        }
        let advanced = captured.and_then(|fields| advance_material(&state, fields));
        let changed = state.current.as_ref().is_none_or(|previous| {
            previous.stamp.model_catalog_revision != stamp.model_catalog_revision
                || previous.updated_at != updated_at || match (&previous.material, &advanced) {
                    (Ok(previous), Ok(next)) => previous.reference != next.material.reference,
                    _ => true,
                }
        });
        let revision = if changed { state.projection_revision.checked_add(1) }
            else { Some(state.projection_revision) };
        let material = match revision {
            Some(revision) => {
                state.projection_revision = revision;
                advanced.map(|next| {
                    state.next_entity = next.next_entity;
                    state.value_revision = next.material.reference.revision;
                    state.collection_revision = next.material.collection.revision;
                    state.versions.insert(next.material.reference.revision, Arc::downgrade(&next.material));
                    next.material
                })
            }
            None => { state.exhausted = true; Err(identity_exhausted()) }
        };
        if let Err(failure) = &material { state.last_failure = Some(failure.clone()); }
        let closing = stamp.closing;
        state.current = Some(Arc::new(ModelsSnapshot { revision: state.projection_revision,
            stamp, updated_at, material, last_failure: state.last_failure.clone() }));
        state.versions.retain(|_, material| material.strong_count() != 0);
        if closing { self.sealed.store(true, Ordering::Release); }
        drop(state);
        self.updates.send_replace(());
    }
}

struct MaterialAdvance {
    material: Arc<ModelCatalogMaterial>,
    next_entity: u64,
}

/// Counters and member identities commit together, only after every checked allocation succeeds.
/// A failed capture discards the previous current identity map; recovery creates fresh members.
fn advance_material(state: &SourceState, fields: Arc<CapturedModels>)
    -> Result<MaterialAdvance, Arc<ModelCaptureFailure>> {
    let previous = state.current.as_ref().and_then(|snapshot| snapshot.material.as_ref().ok());
    if let Some(previous) = previous && previous.fields.same_business(&fields) {
        return Ok(MaterialAdvance { material: previous.clone(), next_entity: state.next_entity });
    }
    let mut next_entity = state.next_entity;
    let previous_members: BTreeMap<_, _> = previous.into_iter().flat_map(|material| {
        material.value().accounts.iter().zip(&material.entities).enumerate()
            .map(|(index, (account, reference))| (account.account_id.as_str(), (index, *reference)))
    }).collect();
    let mut entities = Vec::with_capacity(fields.value.accounts.len());
    for (index, account) in fields.value.accounts.iter().enumerate() {
        let reference = match previous_members.get(account.account_id.as_str()) {
            Some((old_index, old)) => {
                let unchanged = previous.is_some_and(|material| fields.same_account(index, &material.fields, *old_index));
                ProductEntityRef { entry: old.entry, revision: if unchanged { old.revision }
                    else { next_identity(old.revision)? } }
            }
            None => {
                let entry = next_entity;
                next_entity = next_identity(next_entity)?;
                ProductEntityRef { entry, revision: 1 }
            }
        };
        entities.push(reference);
    }
    let value_revision = next_identity(state.value_revision)?;
    let collection_revision = if previous.is_some_and(|material| material.entities == entities) {
        state.collection_revision
    } else { next_identity(state.collection_revision)? };
    let total = u64::try_from(entities.len()).map_err(|_| identity_exhausted())?;
    let material = Arc::new(ModelCatalogMaterial {
        reference: ModelCatalogReadRef { entry: VALUE_ENTRY, revision: value_revision },
        collection: ProductCollectionRef { entry: COLLECTION_ENTRY, revision: collection_revision, total },
        entities, fields,
    });
    Ok(MaterialAdvance { material, next_entity })
}

fn next_identity(previous: u64) -> Result<u64, Arc<ModelCaptureFailure>> {
    previous.checked_add(1).ok_or_else(identity_exhausted)
}

fn identity_exhausted() -> Arc<ModelCaptureFailure> {
    ModelCaptureFailure::capture(StudioError::new(StudioErrorCode::Overloaded,
        "Models publication identity space is exhausted", false).into())
}

fn cancelled() -> StudioError {
    StudioError::new(StudioErrorCode::Cancelled, "The Models source is closing or replaced", false)
}

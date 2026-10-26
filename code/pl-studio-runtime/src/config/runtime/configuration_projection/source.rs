//! Source-local identities advance before watch coalescing; historical locators are only Weak.
use std::collections::BTreeMap;
use std::sync::{
    Arc, Mutex, Weak,
    atomic::{AtomicBool, Ordering},
};

use pl_protocol::products::configuration::{
    ConfigurationRoleReadRef, ConfigurationRoleReadTarget, ConfigurationValue,
};
use pl_protocol::products::identity::{
    ProductCollectionRef, ProductEntityRef, ProductReadOrigin, ProductSourceStatusRef,
};
use pl_protocol::products::references::{
    ConfigurationReadRef, ConfigurationReadTarget, ModelCatalogReadTarget,
};
use pl_protocol::studio::{ConfigProjectionStamp, StudioError, StudioErrorCode};

use super::super::{ModelCatalogMaterial, ModelsSnapshot};
use super::status::{ConfigurationMetadata, ConfigurationStatusMaterial};

#[derive(Debug, thiserror::Error)]
#[error("Configuration publication could not capture its canonical material")]
pub(crate) struct ConfigurationCaptureFailure {
    pub(crate) diagnostic: StudioError,
    #[source]
    cause: anyhow::Error,
}

impl ConfigurationCaptureFailure {
    pub(super) fn new(cause: anyhow::Error) -> Arc<Self> {
        let diagnostic = crate::error_mapping::studio_error_from_anyhow_ref(&cause);
        Arc::new(Self { diagnostic, cause })
    }

    pub(super) fn metadata_transition(cause: anyhow::Error) -> Arc<Self> {
        Arc::new(Self {
            diagnostic: StudioError::new(
                StudioErrorCode::Protocol,
                "The canonical Configuration source metadata transition failed",
                false,
            ),
            cause,
        })
    }
}

pub(crate) struct ConfigurationMaterial {
    pub(crate) reference: ConfigurationReadRef,
    pub(crate) collection: ProductCollectionRef,
    pub(crate) entities: Vec<ProductEntityRef>,
    pub(crate) value: Arc<ConfigurationValue>,
}

/// This is the only compatible pair. Its public credential cannot create or rehydrate one.
pub(crate) struct ConfigurationPair {
    pub(crate) target: ConfigurationRoleReadTarget,
    pub(crate) configuration: Arc<ConfigurationMaterial>,
    pub(crate) models: Arc<ModelCatalogMaterial>,
    // The original metadata snapshot and both watermarks stay alive with the actual pair pin.
    pub(crate) model_publication: Arc<ModelsSnapshot>,
}

pub(crate) struct ConfigurationSnapshot {
    pub(crate) revision: u64,
    pub(crate) stamp: ConfigProjectionStamp,
    pub(crate) updated_at: i64,
    pub(crate) source_status:
        Result<Arc<ConfigurationStatusMaterial>, Arc<ConfigurationCaptureFailure>>,
    pub(crate) material: Result<Arc<ConfigurationMaterial>, Arc<ConfigurationCaptureFailure>>,
    pub(crate) pair: Result<Arc<ConfigurationPair>, Arc<ConfigurationCaptureFailure>>,
    pub(crate) last_failure: Option<Arc<ConfigurationCaptureFailure>>,
}

struct State {
    current: Option<Arc<ConfigurationSnapshot>>,
    values: BTreeMap<u64, Weak<ConfigurationMaterial>>,
    statuses: BTreeMap<u64, Weak<ConfigurationStatusMaterial>>,
    pairs: BTreeMap<u64, Weak<ConfigurationPair>>,
    next_entity: u64,
    value_revision: u64,
    collection_revision: u64,
    status_revision: u64,
    pair_revision: u64,
    projection_revision: u64,
    last_failure: Option<Arc<ConfigurationCaptureFailure>>,
}

/// Lock order: ConfigRuntime state -> Configuration source -> Models source (read only).
/// No method below acquires ConfigRuntime. Canonical capture never calls consumers; the separate
/// actual-send gate accepts only the bounded non-reentrant transport callback documented below.
pub(crate) struct ConfigurationSource {
    origin: ProductReadOrigin,
    models: Arc<super::super::ModelCatalogSource>,
    sealed: AtomicBool,
    state: Mutex<State>,
    updates: tokio::sync::watch::Sender<()>,
}

impl ConfigurationSource {
    pub(super) fn new(
        origin: ProductReadOrigin,
        models: Arc<super::super::ModelCatalogSource>,
    ) -> Arc<Self> {
        let (updates, _) = tokio::sync::watch::channel(());
        Arc::new(Self {
            origin,
            models,
            sealed: AtomicBool::new(false),
            updates,
            state: Mutex::new(State {
                current: None,
                values: BTreeMap::new(),
                statuses: BTreeMap::new(),
                pairs: BTreeMap::new(),
                next_entity: 5,
                value_revision: 0,
                collection_revision: 0,
                status_revision: 0,
                pair_revision: 0,
                projection_revision: 0,
                last_failure: None,
            }),
        })
    }

    pub(crate) fn origin(&self) -> &ProductReadOrigin {
        &self.origin
    }

    pub(crate) fn observe(
        &self,
    ) -> Result<(Arc<ConfigurationSnapshot>, tokio::sync::watch::Receiver<()>), StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let updates = self.updates.subscribe();
        self.ensure_open()?;
        Ok((state.current.clone().ok_or_else(cancelled)?, updates))
    }

    pub(crate) fn current(&self) -> Result<Arc<ConfigurationSnapshot>, StudioError> {
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
        reference: ConfigurationReadRef,
    ) -> Result<Arc<ConfigurationMaterial>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_origin(origin)?;
        state.values.retain(|_, value| value.strong_count() != 0);
        if reference.entry != 1
            || reference.revision == 0
            || reference.revision > state.value_revision
        {
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
        if reference.entry != 3
            || reference.revision == 0
            || reference.revision > state.status_revision
        {
            return Err(unpublished());
        }
        state
            .statuses
            .get(&reference.revision)
            .and_then(Weak::upgrade)
            .ok_or_else(expired)
    }

    pub(crate) fn pin_pair(
        &self,
        target: &ConfigurationRoleReadTarget,
    ) -> Result<Arc<ConfigurationPair>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check_origin(&target.configuration.origin)?;
        state.pairs.retain(|_, value| value.strong_count() != 0);
        if target.reference.entry != 4
            || target.reference.revision == 0
            || target.reference.revision > state.pair_revision
        {
            return Err(unpublished());
        }
        let pair = state
            .pairs
            .get(&target.reference.revision)
            .and_then(Weak::upgrade)
            .ok_or_else(expired)?;
        if &pair.target != target || pair.model_publication.stamp != target.stamp {
            return Err(StudioError::new(
                StudioErrorCode::Protocol,
                "The Configuration/catalog targets or capture watermarks do not match the issued pair",
                false,
            ));
        }
        Ok(pair)
    }

    /// The bounded synchronous transport callback must not re-enter this source. A receiver's
    /// read blocks on this guard until successful send and reference exposure commit together.
    /// Failed sends do not grant access to pending/current material.
    pub(crate) fn send_exposing(
        &self,
        snapshot: &ConfigurationSnapshot,
        send: impl FnOnce() -> Result<bool, StudioError>,
    ) -> Result<bool, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.ensure_open()?;
        let sent = send()?;
        if sent {
            expose(&mut state, snapshot);
        }
        Ok(sent)
    }

    /// A committed command's own result is a separate source of canonical read targets. It uses
    /// its original captured publication; it neither pretends to send Feed Data nor advances an
    /// ACK prefix. The command owner retains the publication through result materialization.
    pub(crate) fn expose_committed(
        &self,
        snapshot: &ConfigurationSnapshot,
    ) -> Result<(), StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.ensure_open()?;
        let pair = snapshot
            .pair
            .as_ref()
            .map_err(|failure| failure.diagnostic.clone())?;
        if pair.target.configuration.origin != self.origin {
            return Err(unpublished());
        }
        expose(&mut state, snapshot);
        Ok(())
    }

    /// Expose only this capture's Configuration material and return its typed read target.
    ///
    /// ACP account commands return a Settings-only receipt plus the Configuration target captured
    /// by that very commit: they neither need nor pretend to have a Models pair. The caller's
    /// retained publication keeps this material alive until explicit call close.
    pub(crate) fn expose_committed_configuration(
        &self,
        snapshot: &ConfigurationSnapshot,
    ) -> Result<pl_protocol::products::references::ConfigurationReadTarget, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.ensure_open()?;
        let material = snapshot
            .material
            .as_ref()
            .map_err(|failure| failure.diagnostic.clone())?;
        state
            .values
            .insert(material.reference.revision, Arc::downgrade(material));
        Ok(pl_protocol::products::references::ConfigurationReadTarget {
            origin: self.origin.clone(),
            reference: material.reference,
        })
    }

    pub(crate) fn ensure_open(&self) -> Result<(), StudioError> {
        if self.sealed.load(Ordering::Acquire) {
            Err(cancelled())
        } else {
            Ok(())
        }
    }

    pub(crate) fn seal(&self) {
        self.sealed.store(true, Ordering::Release);
        self.notify();
    }

    /// Only after the original read/transport owners have actually joined.
    pub(crate) fn finish_close(&self) {
        self.seal();
        let current = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.values.clear();
            state.statuses.clear();
            state.pairs.clear();
            state.current.take()
        };
        drop(current);
    }

    pub(in crate::config::runtime) fn notify(&self) {
        self.updates.send_replace(());
    }

    pub(in crate::config::runtime) fn publish(
        &self,
        stamp: ConfigProjectionStamp,
        updated_at: i64,
        metadata: ConfigurationMetadata,
        captured: Result<Arc<ConfigurationValue>, Arc<ConfigurationCaptureFailure>>,
    ) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        // Sealing rejects admission immediately, but does not suppress the canonical owner's
        // later Stopped metadata publication while accepted commits/closing finish joining.
        if self.ensure_open().is_err() && !stamp.closing {
            return;
        }
        let status = metadata.and_then(|metadata| {
            let previous = state
                .current
                .as_ref()
                .and_then(|value| value.source_status.as_ref().ok());
            if let Some(previous) = previous
                && previous.metadata() == metadata.as_ref()
            {
                return Ok(previous.clone());
            }
            let revision = next(state.status_revision)?;
            Ok(Arc::new(ConfigurationStatusMaterial::new(
                revision, metadata,
            )))
        });
        let material = captured.and_then(|value| advance_material(&mut state, value));
        // ConfigRuntime has already published Models under the same canonical guard.
        let pair = material.as_ref().map_err(Arc::clone).and_then(|configuration| {
            status.as_ref().map_err(Arc::clone)?;
            let models = self.models.current().map_err(|error| ConfigurationCaptureFailure::new(error.into()))?;
            let original = models.material.as_ref().map_err(|failure| ConfigurationCaptureFailure::new(failure.diagnostic.clone().into()))?;
            models.source_status.as_ref().map_err(|failure| ConfigurationCaptureFailure::new(failure.diagnostic().into()))?;
            if models.stamp != stamp { return Err(ConfigurationCaptureFailure::new(StudioError::new(
                StudioErrorCode::Protocol, "Models and Configuration were not captured at the same canonical boundary", false).into())); }
            let previous = state.current.as_ref().and_then(|value| value.pair.as_ref().ok());
            if let Some(previous) = previous && previous.target.stamp == stamp
                && previous.target.configuration.reference == configuration.reference
                && previous.target.catalog.reference == original.reference { return Ok(previous.clone()); }
            let revision = next(state.pair_revision)?;
            Ok(Arc::new(ConfigurationPair { target: ConfigurationRoleReadTarget {
                reference: ConfigurationRoleReadRef { entry: 4, revision },
                configuration: ConfigurationReadTarget { origin: self.origin.clone(), reference: configuration.reference },
                catalog: ModelCatalogReadTarget { origin: self.models.origin().clone(), reference: original.reference }, stamp,
            }, configuration: configuration.clone(), models: original.clone(), model_publication: models }))
        });
        let revision = next(state.projection_revision);
        if let Ok(revision) = revision.as_ref() {
            state.projection_revision = *revision;
        }
        let material = revision.and(material);
        let pair = material.as_ref().map_err(Arc::clone).and(pair);
        state.last_failure = status
            .as_ref()
            .err()
            .cloned()
            .or_else(|| material.as_ref().err().cloned())
            .or_else(|| pair.as_ref().err().cloned())
            .or_else(|| state.last_failure.clone());
        if let Ok(status) = &status {
            state.status_revision = status.header.status.revision;
        }
        if let Ok(pair) = &pair {
            state.pair_revision = pair.target.reference.revision;
        }
        let closing = stamp.closing;
        state.current = Some(Arc::new(ConfigurationSnapshot {
            revision: state.projection_revision,
            stamp,
            updated_at,
            source_status: status,
            material,
            pair,
            last_failure: state.last_failure.clone(),
        }));
        state.values.retain(|_, value| value.strong_count() != 0);
        state.statuses.retain(|_, value| value.strong_count() != 0);
        state.pairs.retain(|_, value| value.strong_count() != 0);
        if closing {
            self.sealed.store(true, Ordering::Release);
        }
    }

    fn check_origin(&self, origin: &ProductReadOrigin) -> Result<(), StudioError> {
        self.ensure_open()?;
        if origin != &self.origin {
            return Err(cancelled());
        }
        Ok(())
    }
}

fn expose(state: &mut State, snapshot: &ConfigurationSnapshot) {
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
    if let Ok(pair) = &snapshot.pair {
        state
            .pairs
            .insert(pair.target.reference.revision, Arc::downgrade(pair));
    }
}

fn advance_material(
    state: &mut State,
    value: Arc<ConfigurationValue>,
) -> Result<Arc<ConfigurationMaterial>, Arc<ConfigurationCaptureFailure>> {
    let previous = state
        .current
        .as_ref()
        .and_then(|snapshot| snapshot.material.as_ref().ok());
    if let Some(previous) = previous
        && previous.value == value
    {
        return Ok(previous.clone());
    }
    let previous_members: BTreeMap<_, _> =
        previous
            .into_iter()
            .flat_map(|material| {
                material.value.accounts.iter().zip(&material.entities).map(
                    |(account, reference)| (account.account_id.as_str(), (account, *reference)),
                )
            })
            .collect();
    let mut next_entity = state.next_entity;
    let mut entities = Vec::with_capacity(value.accounts.len());
    for account in &value.accounts {
        let reference = match previous_members.get(account.account_id.as_str()) {
            Some((old, reference)) => ProductEntityRef {
                entry: reference.entry,
                revision: if *old == account {
                    reference.revision
                } else {
                    next(reference.revision)?
                },
            },
            None => {
                let entry = next_entity;
                next_entity = next(next_entity)?;
                ProductEntityRef { entry, revision: 1 }
            }
        };
        entities.push(reference);
    }
    let revision = next(state.value_revision)?;
    let collection_revision = if previous.is_some_and(|material| material.entities == entities) {
        state.collection_revision
    } else {
        next(state.collection_revision)?
    };
    let total = u64::try_from(entities.len())
        .map_err(|error| ConfigurationCaptureFailure::new(error.into()))?;
    state.next_entity = next_entity;
    state.value_revision = revision;
    state.collection_revision = collection_revision;
    Ok(Arc::new(ConfigurationMaterial {
        reference: ConfigurationReadRef { entry: 1, revision },
        collection: ProductCollectionRef {
            entry: 2,
            revision: collection_revision,
            total,
        },
        entities,
        value,
    }))
}

fn next(revision: u64) -> Result<u64, Arc<ConfigurationCaptureFailure>> {
    revision.checked_add(1).ok_or_else(|| {
        ConfigurationCaptureFailure::new(
            StudioError::new(
                StudioErrorCode::Overloaded,
                "Configuration publication identity space is exhausted",
                false,
            )
            .into(),
        )
    })
}

fn unpublished() -> StudioError {
    StudioError::new(
        StudioErrorCode::Unavailable,
        "This Configuration reference was not published by the original source",
        false,
    )
}
fn expired() -> StudioError {
    StudioError::new(
        StudioErrorCode::Superseded,
        "The original immutable Configuration material is no longer retained",
        true,
    )
}
fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "The original Configuration source is closing or replaced",
        false,
    )
}

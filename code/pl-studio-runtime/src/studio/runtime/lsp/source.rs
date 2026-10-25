//! Original publication owner. Only current, unACKed Data, read scopes and in-flight commands
//! retain strong material pins; historical locators are Weak and grant nothing before exposure.
use pl_protocol::ObservedResource;
use pl_protocol::products::identity::{
    ProductCollectionRef, ProductEntityRef, ProductReadOrigin, ProductSourceStatusRef,
};
use pl_protocol::products::references::{LspReadRef, LspReadTarget};
use pl_protocol::products::source::{ObservedBrief, ObservedHeader};
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, Weak};

pub(crate) struct LspMaterial {
    pub(crate) reference: LspReadRef,
    pub(crate) collection: ProductCollectionRef,
    pub(crate) entities: Vec<ProductEntityRef>,
    pub(crate) value: Arc<crate::StudioLspHealth>,
}
pub(crate) struct LspStatusMaterial {
    pub(crate) header: ObservedHeader,
    metadata: Arc<ObservedResource<()>>,
}
impl LspStatusMaterial {
    pub(crate) fn metadata(&self) -> &ObservedResource<()> {
        &self.metadata
    }
}
/// A command carries this exact capture out of its original publication guard, never a later read.
pub struct LspSnapshot {
    pub(crate) origin: ProductReadOrigin,
    pub(crate) revision: u64,
    pub(crate) native_revision: u64,
    pub(crate) source_status: Arc<LspStatusMaterial>,
    pub(crate) material: Option<Arc<LspMaterial>>,
    pub(crate) last_failure: Option<Arc<StudioError>>,
}
struct State {
    sealed: bool,
    current: Option<Arc<LspSnapshot>>,
    values: BTreeMap<u64, Weak<LspMaterial>>,
    statuses: BTreeMap<u64, Weak<LspStatusMaterial>>,
    next_entity: u64,
    value_revision: u64,
    collection_revision: u64,
    failure: Option<Arc<StudioError>>,
    last_failure: Option<Arc<StudioError>>,
}
pub(crate) struct LspSource {
    origin: ProductReadOrigin,
    state: Mutex<State>,
    updates: tokio::sync::watch::Sender<()>,
}
impl LspSource {
    pub(crate) fn new(origin: ProductReadOrigin) -> Arc<Self> {
        let (updates, _) = tokio::sync::watch::channel(());
        Arc::new(Self {
            origin,
            updates,
            state: Mutex::new(State {
                sealed: false,
                current: None,
                values: BTreeMap::new(),
                statuses: BTreeMap::new(),
                next_entity: 4,
                value_revision: 0,
                collection_revision: 0,
                failure: None,
                last_failure: None,
            }),
        })
    }
    pub(crate) fn origin(&self) -> &ProductReadOrigin {
        &self.origin
    }
    pub(crate) fn ensure_open(&self) -> Result<(), StudioError> {
        if self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sealed
        {
            Err(cancelled())
        } else {
            Ok(())
        }
    }
    pub(crate) fn observe(
        &self,
    ) -> Result<(Arc<LspSnapshot>, tokio::sync::watch::Receiver<()>), StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let updates = self.updates.subscribe();
        Ok((current(&state)?, updates))
    }
    pub(crate) fn current(&self) -> Result<Arc<LspSnapshot>, StudioError> {
        current(
            &self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner),
        )
    }
    /// The canonical producer calls this under its own original publication/command guard.
    /// This owner never calls back into that producer. A failed capture is observable even if a
    /// subsequent successful publication coalesces the watch notification.
    pub(crate) fn publish(
        &self,
        input: &ObservedResource<crate::StudioLspHealth>,
    ) -> Result<Arc<LspSnapshot>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed && !matches!(input, ObservedResource::Stopped(_)) {
            return Err(cancelled());
        }
        let result = capture(&mut state, &self.origin, input);
        match &result {
            Ok(snapshot) => {
                state.current = Some(snapshot.clone());
                state.failure = None;
            }
            Err(error) => {
                let error = Arc::new(error.clone());
                state.failure = Some(error.clone());
                state.last_failure = Some(error);
            }
        }
        prune(&mut state);
        drop(state);
        self.updates.send_replace(());
        result
    }
    pub(crate) fn pin(
        &self,
        origin: &ProductReadOrigin,
        reference: LspReadRef,
    ) -> Result<Arc<LspMaterial>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check(&state, origin)?;
        prune(&mut state);
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
    ) -> Result<Arc<LspStatusMaterial>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check(&state, origin)?;
        prune(&mut state);
        if reference.entry != 3
            || reference.revision == 0
            || reference.revision
                > state
                    .current
                    .as_ref()
                    .map_or(0, |snapshot| snapshot.source_status.header.status.revision)
        {
            return Err(unpublished());
        }
        state
            .statuses
            .get(&reference.revision)
            .and_then(Weak::upgrade)
            .ok_or_else(expired)
    }
    /// Synchronous, bounded, non-reentrant send: exposure and actual delivery commit together.
    pub(crate) fn send_exposing(
        &self,
        snapshot: &LspSnapshot,
        send: impl FnOnce() -> Result<bool, StudioError>,
    ) -> Result<bool, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check(&state, &snapshot.origin)?;
        let sent = send()?;
        if sent {
            expose(&mut state, snapshot);
        }
        Ok(sent)
    }
    /// A command grants only its own captured target. This does not consume feed credit or ACK.
    pub(crate) fn expose_committed(
        &self,
        snapshot: &LspSnapshot,
    ) -> Result<LspReadTarget, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check(&state, &snapshot.origin)?;
        let material = snapshot.material.as_ref().ok_or_else(|| {
            StudioError::new(
                StudioErrorCode::Unavailable,
                "Lsp command has no readable value",
                true,
            )
        })?;
        expose(&mut state, snapshot);
        Ok(LspReadTarget {
            origin: self.origin.clone(),
            reference: material.reference,
        })
    }
    pub(crate) fn seal(&self) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sealed = true;
        self.updates.send_replace(());
    }
    /// Called only after original producers, transport tasks and read calls/scopes truly join.
    pub(crate) fn finish_close(&self) {
        let current = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            state.sealed = true;
            state.values.clear();
            state.statuses.clear();
            state.current.take()
        };
        drop(current);
        self.updates.send_replace(());
    }
    fn check(&self, state: &State, origin: &ProductReadOrigin) -> Result<(), StudioError> {
        if state.sealed || origin != &self.origin {
            Err(cancelled())
        } else {
            Ok(())
        }
    }
}
fn current(state: &State) -> Result<Arc<LspSnapshot>, StudioError> {
    if state.sealed {
        return Err(cancelled());
    }
    if let Some(error) = &state.failure {
        return Err(error.as_ref().clone());
    }
    state.current.clone().ok_or_else(|| {
        StudioError::new(
            StudioErrorCode::Unavailable,
            "Lsp source has not published",
            true,
        )
    })
}
fn capture(
    state: &mut State,
    origin: &ProductReadOrigin,
    input: &ObservedResource<crate::StudioLspHealth>,
) -> Result<Arc<LspSnapshot>, StudioError> {
    let previous = state.current.as_ref();
    let metadata = Arc::new(input.clone().map(|_| ()));
    if let Some(previous) = previous {
        if input.revision() < previous.native_revision {
            return Err(StudioError::new(
                StudioErrorCode::Protocol,
                "Lsp publication moved backwards",
                false,
            ));
        }
        if input.revision() == previous.native_revision
            && previous.source_status.metadata == metadata
            && previous
                .material
                .as_ref()
                .map(|material| material.value.as_ref())
                == input.value()
        {
            return Ok(previous.clone());
        }
        if input.revision() == previous.native_revision {
            return Err(StudioError::new(
                StudioErrorCode::Protocol,
                "Lsp publication changed without advancing its original revision",
                false,
            ));
        }
    }
    let revision = next(previous.map_or(0, |snapshot| snapshot.revision))?;
    let status_revision =
        next(previous.map_or(0, |snapshot| snapshot.source_status.header.status.revision))?;
    let source_status = Arc::new(LspStatusMaterial {
        header: ObservedHeader {
            brief: brief(&metadata),
            status: ProductSourceStatusRef {
                entry: 3,
                revision: status_revision,
            },
        },
        metadata,
    });
    let prior = previous.and_then(|snapshot| snapshot.material.as_ref());
    let mut next_entity = state.next_entity;
    let material = match input.value() {
        None => None,
        Some(value) if prior.is_some_and(|prior| prior.value.as_ref() == value) => prior.cloned(),
        Some(value) => {
            let old: BTreeMap<_, _> = prior
                .into_iter()
                .flat_map(|material| material.value.lsp_servers.iter().zip(&material.entities))
                .map(|(member, reference)| (member.id.clone(), (member, *reference)))
                .collect();
            // The canonical global mirror aggregates workspaces without their identity. Repeated
            // server IDs are legitimate, so do not drop rows or pretend to know which workspace
            // survived a publication. Only unambiguous IDs can retain a cross-publication entry.
            let mut previous_counts = BTreeMap::new();
            for member in prior
                .into_iter()
                .flat_map(|material| &material.value.lsp_servers)
            {
                *previous_counts.entry(member.id.as_str()).or_insert(0_usize) += 1;
            }
            let mut current_counts = BTreeMap::new();
            for member in &value.lsp_servers {
                *current_counts.entry(member.id.as_str()).or_insert(0_usize) += 1;
            }
            let mut entities = Vec::with_capacity(value.lsp_servers.len());
            for member in &value.lsp_servers {
                let unambiguous = previous_counts.get(member.id.as_str()) == Some(&1)
                    && current_counts.get(member.id.as_str()) == Some(&1);
                let reference =
                    if let Some((prior, reference)) = old.get(&member.id).filter(|_| unambiguous) {
                        ProductEntityRef {
                            entry: reference.entry,
                            revision: if *prior == member {
                                reference.revision
                            } else {
                                next(reference.revision)?
                            },
                        }
                    } else {
                        let entry = next_entity;
                        next_entity = next(next_entity)?;
                        ProductEntityRef { entry, revision: 1 }
                    };
                entities.push(reference);
            }
            let collection_revision = if prior.is_some_and(|prior| prior.entities == entities) {
                state.collection_revision
            } else {
                next(state.collection_revision)?
            };
            Some(Arc::new(LspMaterial {
                reference: LspReadRef {
                    entry: 1,
                    revision: next(state.value_revision)?,
                },
                collection: ProductCollectionRef {
                    entry: 2,
                    revision: collection_revision,
                    total: super::super::read_budget::count(entities.len())?,
                },
                entities,
                value: Arc::new(value.clone()),
            }))
        }
    };
    if let Some(material) = &material {
        state.value_revision = material.reference.revision;
        state.collection_revision = material.collection.revision;
    }
    state.next_entity = next_entity;
    Ok(Arc::new(LspSnapshot {
        origin: origin.clone(),
        revision,
        native_revision: input.revision(),
        source_status,
        material,
        last_failure: state.last_failure.clone(),
    }))
}
fn prune(state: &mut State) {
    state.values.retain(|_, pin| pin.strong_count() != 0);
    state.statuses.retain(|_, pin| pin.strong_count() != 0);
}
fn expose(state: &mut State, snapshot: &LspSnapshot) {
    prune(state);
    if let Some(material) = &snapshot.material {
        state
            .values
            .insert(material.reference.revision, Arc::downgrade(material));
    }
    state.statuses.insert(
        snapshot.source_status.header.status.revision,
        Arc::downgrade(&snapshot.source_status),
    );
}
fn next(revision: u64) -> Result<u64, StudioError> {
    revision.checked_add(1).ok_or_else(|| {
        StudioError::new(
            StudioErrorCode::Overloaded,
            "Lsp identity space is exhausted",
            false,
        )
    })
}
fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Original Lsp source is closing or replaced",
        false,
    )
}
fn unpublished() -> StudioError {
    StudioError::new(
        StudioErrorCode::Unavailable,
        "Lsp reference was not published by its original source",
        false,
    )
}
fn expired() -> StudioError {
    StudioError::new(
        StudioErrorCode::Superseded,
        "Original Lsp material is no longer pinned",
        true,
    )
}
fn brief(metadata: &ObservedResource<()>) -> ObservedBrief {
    match metadata {
        ObservedResource::Uninitialized(state) => ObservedBrief::Uninitialized {
            revision: state.revision(),
            updated_at: state.updated_at(),
        },
        ObservedResource::Loading(state) => ObservedBrief::Loading {
            revision: state.revision(),
            started_at: state.started_at(),
        },
        ObservedResource::Ready(state) => ObservedBrief::Ready {
            revision: state.revision(),
            updated_at: state.updated_at(),
            last_checked_at: state.last_checked_at(),
        },
        ObservedResource::Refreshing(state) => ObservedBrief::Refreshing {
            revision: state.revision(),
            started_at: state.started_at(),
            last_checked_at: state.last_checked_at(),
        },
        ObservedResource::Stale(state) => ObservedBrief::Stale {
            revision: state.revision(),
            stale_at: state.stale_at(),
            last_checked_at: state.last_checked_at(),
        },
        ObservedResource::Degraded(state) => ObservedBrief::Degraded {
            revision: state.revision(),
            failed_at: state.failed_at(),
            last_checked_at: state.last_checked_at(),
            retryable: state.error().retryable,
        },
        ObservedResource::Failed(state) => ObservedBrief::Failed {
            revision: state.revision(),
            failed_at: state.failed_at(),
            retryable: state.error().retryable,
        },
        ObservedResource::Stopped(state) => ObservedBrief::Stopped {
            revision: state.revision(),
            stopped_at: state.stopped_at(),
        },
    }
}

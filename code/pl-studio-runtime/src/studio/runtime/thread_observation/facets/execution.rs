//! One execution projection in the original observation owner. Bodies live only in exact read
//! materials; listeners own the sole reliable FIFO and the original unacknowledged material pins.
mod capture;
mod delivery;

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, Weak};

use pl_protocol::studio::{StudioError, StudioErrorCode, ThreadStorageState};
use pl_protocol::thread_facets::execution::ExecutionBaseline;
use pl_protocol::thread_facets::identity::{FeedClosedReason, ThreadFacet, ThreadFacetStamp};
use pl_protocol::{InteractionRequest, ThreadActivity, Turn};
use tokio::sync::Notify;

use crate::studio::runtime::thread_reads::index::InteractionIndexSource;
pub use delivery::DeliveryStep;
pub(in crate::studio::runtime) use delivery::ExecutionDelivery;

#[derive(Clone, PartialEq, Eq, PartialOrd, Ord)]
enum Key {
    Turn(String),
    Interaction(String),
    Activity(String),
    Storage,
    Index,
}

#[derive(Clone)]
pub(in crate::studio::runtime) enum Material {
    Turn(Arc<Turn>),
    Interaction(Arc<InteractionRequest>),
    Index(Arc<InteractionIndexSource>),
    Activity(Arc<ThreadActivity>),
    Storage(Arc<ThreadStorageState>),
}

// Weak locators point to the underlying immutable fact, not to a temporary enum wrapper.
// An index scope therefore keeps all of its member versions readable through its Arc members.
enum WeakMaterial {
    Turn(Weak<Turn>),
    Interaction(Weak<InteractionRequest>),
    Index(Weak<InteractionIndexSource>),
    Activity(Weak<ThreadActivity>),
    Storage(Weak<ThreadStorageState>),
}
impl Material {
    fn downgrade(&self) -> WeakMaterial {
        match self {
            Self::Turn(value) => WeakMaterial::Turn(Arc::downgrade(value)),
            Self::Interaction(value) => WeakMaterial::Interaction(Arc::downgrade(value)),
            Self::Index(value) => WeakMaterial::Index(Arc::downgrade(value)),
            Self::Activity(value) => WeakMaterial::Activity(Arc::downgrade(value)),
            Self::Storage(value) => WeakMaterial::Storage(Arc::downgrade(value)),
        }
    }
}
impl WeakMaterial {
    fn upgrade(&self) -> Option<Arc<Material>> {
        Some(Arc::new(match self {
            Self::Turn(value) => Material::Turn(value.upgrade()?),
            Self::Interaction(value) => Material::Interaction(value.upgrade()?),
            Self::Index(value) => Material::Index(value.upgrade()?),
            Self::Activity(value) => Material::Activity(value.upgrade()?),
            Self::Storage(value) => Material::Storage(value.upgrade()?),
        }))
    }
    fn strong_count(&self) -> usize {
        match self {
            Self::Turn(value) => value.strong_count(),
            Self::Interaction(value) => value.strong_count(),
            Self::Index(value) => value.strong_count(),
            Self::Activity(value) => value.strong_count(),
            Self::Storage(value) => value.strong_count(),
        }
    }
}

#[derive(Clone)]
pub(in crate::studio::runtime) struct Fact {
    pub(in crate::studio::runtime) entry: u64,
    pub(in crate::studio::runtime) revision: u64,
    pub(in crate::studio::runtime) material: Arc<Material>,
}

#[derive(Clone, PartialEq, Eq)]
pub(in crate::studio::runtime) enum InteractionReceiptKind {
    Interaction,
    Permission,
}

impl InteractionReceiptKind {
    pub(in crate::studio::runtime) fn as_str(&self) -> &'static str {
        match self {
            Self::Interaction => "interaction",
            Self::Permission => "permission",
        }
    }
}

#[derive(Clone, PartialEq, Eq)]
pub(in crate::studio::runtime) struct InteractionIdentity {
    pub(in crate::studio::runtime) wire_id: String,
    pub(in crate::studio::runtime) local_id: String,
    pub(in crate::studio::runtime) kind: InteractionReceiptKind,
}

impl InteractionIdentity {
    fn from_fact(value: &InteractionRequest) -> Result<Self, StudioError> {
        let (owner, local) = crate::thread_assembler::decode_interaction_key(&value.interaction_id)
            .map_err(|_| capture::corrupt())?;
        if owner != value.scope.thread_id {
            return Err(capture::corrupt());
        }
        let kind = match value.kind() {
            pl_protocol::InteractionKind::ToolApproval => InteractionReceiptKind::Permission,
            pl_protocol::InteractionKind::UserInput => InteractionReceiptKind::Interaction,
        };
        Ok(Self {
            wire_id: value.interaction_id.clone(),
            local_id: local.to_owned(),
            kind,
        })
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum FactSource {
    Projection,
    Durable,
}

struct Locator {
    material: WeakMaterial,
    source: FactSource,
    /// Only successful Data delivery records this watermark, never a read/resolve request.
    exposed_from: Option<u64>,
    interaction: Option<InteractionIdentity>,
    /// A separately verified exact receipt may grant a history ref without claiming feed exposure.
    durable_from: Option<u64>,
}

impl Locator {
    fn exposed_at(&self, revision: u64) -> bool {
        self.exposed_from.is_some_and(|first| first <= revision)
    }

    fn interaction_readable_at(&self, revision: u64) -> bool {
        self.exposed_at(revision) || self.durable_from.is_some_and(|first| first <= revision)
    }

    fn ensure_resolvable_at(&self, revision: u64) -> Result<(), StudioError> {
        match self.source {
            FactSource::Projection if !self.exposed_at(revision) => Err(superseded()),
            FactSource::Durable if self.durable_from.is_some_and(|first| first > revision) => {
                Err(superseded())
            }
            FactSource::Projection | FactSource::Durable => Ok(()),
        }
    }
}

pub(in crate::studio::runtime) struct ExecutionSnapshot {
    pub(in crate::studio::runtime) stamp: ThreadFacetStamp,
    pub(in crate::studio::runtime) value: ExecutionBaseline,
    facts: Vec<Fact>,
}

struct State {
    current: Option<Arc<ExecutionSnapshot>>,
    capture_error: Option<StudioError>,
    terminal: Option<Terminal>,
    next_entry: u64,
    keys: BTreeMap<Key, u64>,
    locators: BTreeMap<(u64, u64), Locator>,
    listeners: Vec<Weak<ExecutionDelivery>>,
    core_sequence: Option<u64>,
    resolved: std::collections::VecDeque<(u64, u64)>,
}

#[derive(Clone)]
pub(in crate::studio::runtime) enum Terminal {
    Failure(StudioError),
    Closed(FeedClosedReason),
}

pub(in crate::studio::runtime) struct ExecutionProjection {
    epoch: String,
    incarnation: u64,
    state: Mutex<State>,
    changed: Notify,
}

impl ExecutionProjection {
    pub(in crate::studio::runtime) fn interaction_revision(&self) -> Option<u64> {
        self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
            .current.as_ref().map(|current| current.value.interactions.reference.revision)
    }

    pub(in crate::studio::runtime) fn hosted_pending(&self, host: &str) -> Vec<Arc<InteractionRequest>> {
        self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
            .current.as_ref().map_or_else(Vec::new, |current| {
                current.facts.iter().filter_map(|fact| match &*fact.material {
                    Material::Interaction(value) if value.scope.thread_id != host => Some(value.clone()),
                    _ => None,
                }).collect()
            })
    }

    pub(super) fn new(epoch: String, incarnation: u64) -> Self {
        Self {
            epoch,
            incarnation,
            state: Mutex::new(State {
                current: None,
                capture_error: None,
                terminal: None,
                next_entry: 1,
                keys: BTreeMap::new(),
                locators: BTreeMap::new(),
                listeners: Vec::new(),
                core_sequence: None,
                resolved: std::collections::VecDeque::new(),
            }),
            changed: Notify::new(),
        }
    }

    pub(in crate::studio::runtime) fn matches_origin(&self, origin: &ThreadFacetStamp) -> bool {
        origin.facet == ThreadFacet::Execution
            && origin.runtime_epoch == self.epoch
            && origin.incarnation == self.incarnation
    }

    pub(in crate::studio::runtime) fn origin(&self) -> (String, u64) {
        (self.epoch.clone(), self.incarnation)
    }

    pub(in crate::studio::runtime) fn ensure_open(&self) -> Result<(), StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        ensure_open(&state)
    }

    pub(in crate::studio::runtime) fn close(&self, reason: FeedClosedReason) {
        self.finish(Terminal::Closed(reason));
    }
    pub(in crate::studio::runtime) fn fail(&self, error: StudioError) {
        self.finish(Terminal::Failure(error));
    }

    pub(in crate::studio::runtime) fn resync(
        &self,
        reason: pl_protocol::thread_facets::identity::ResyncReason,
    ) {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for listener in state.listeners.iter().filter_map(Weak::upgrade) {
            listener.request_resync(reason);
        }
    }

    pub(in crate::studio::runtime) fn capture_failed(&self, error: StudioError) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.terminal.is_some() {
            return;
        }
        state.capture_error = Some(error);
        for listener in state.listeners.iter().filter_map(Weak::upgrade) {
            listener
                .request_resync(pl_protocol::thread_facets::identity::ResyncReason::SourceLagged);
        }
        drop(state);
        self.changed.notify_waiters();
    }

    fn finish(&self, terminal: Terminal) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.terminal.is_some() {
            return;
        }
        state.terminal = Some(terminal.clone());
        for listener in state.listeners.iter().filter_map(Weak::upgrade) {
            listener.finish(terminal.clone());
        }
        drop(state);
        self.changed.notify_waiters();
    }

    pub(in crate::studio::runtime) async fn ready(&self) -> Result<(), StudioError> {
        loop {
            let changed = self.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            {
                let state = self
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                ensure_open(&state)?;
                if let Some(error) = &state.capture_error {
                    return Err(error.clone());
                }
                if state.current.is_some() {
                    return Ok(());
                }
            }
            changed.await;
        }
    }

    /// Only a ref actually exposed at/before the supplied facet stamp grants a read. Locators are
    /// weak: current, reliable pending/unacked and explicit scopes are the only material owners.
    pub(in crate::studio::runtime) fn material_at(
        &self,
        entry: u64,
        revision: u64,
        origin: &ThreadFacetStamp,
    ) -> Result<Arc<Material>, StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        ensure_open(&state)?;
        if !self.matches_origin(origin)
            || !state
                .current
                .as_ref()
                .is_some_and(|value| origin.revision <= value.stamp.revision)
        {
            return Err(superseded());
        }
        let locator = state
            .locators
            .get(&(entry, revision))
            .ok_or_else(superseded)?;
        if !locator.exposed_at(origin.revision) {
            return Err(superseded());
        }
        locator.material.upgrade().ok_or_else(superseded)
    }

    pub(in crate::studio::runtime) fn interaction_at(
        &self,
        entry: u64,
        revision: u64,
        origin: &ThreadFacetStamp,
    ) -> Result<Result<Arc<Material>, InteractionIdentity>, StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        ensure_open(&state)?;
        if !self.matches_origin(origin)
            || !state
                .current
                .as_ref()
                .is_some_and(|value| origin.revision <= value.stamp.revision)
        {
            return Err(superseded());
        }
        let locator = state
            .locators
            .get(&(entry, revision))
            .ok_or_else(superseded)?;
        if !locator.interaction_readable_at(origin.revision) {
            return Err(superseded());
        }
        if let Some(material) = locator.material.upgrade() {
            return match &*material {
                Material::Interaction(_) => Ok(Ok(material)),
                _ => Err(superseded()),
            };
        }
        if locator.durable_from.is_none() {
            return Err(superseded());
        }
        locator.interaction.clone().map(Err).ok_or_else(superseded)
    }

    pub(in crate::studio::runtime) fn bind_durable_interaction(
        &self,
        entry: u64,
        revision: u64,
        value: Arc<InteractionRequest>,
        origin: &ThreadFacetStamp,
    ) -> Result<Arc<Material>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        ensure_open(&state)?;
        if !self.matches_origin(origin)
            || !state
                .current
                .as_ref()
                .is_some_and(|value| origin.revision <= value.stamp.revision)
        {
            return Err(superseded());
        }
        let locator = state
            .locators
            .get_mut(&(entry, revision))
            .ok_or_else(superseded)?;
        if !locator.interaction_readable_at(origin.revision)
            || value.revision != revision
            || locator.interaction.as_ref() != Some(&InteractionIdentity::from_fact(&value)?)
        {
            return Err(superseded());
        }
        let material = Arc::new(Material::Interaction(value));
        locator.material = material.downgrade();
        Ok(material)
    }
}

fn ensure_open(state: &State) -> Result<(), StudioError> {
    match &state.terminal {
        None => Ok(()),
        Some(Terminal::Failure(error)) => Err(error.clone()),
        Some(Terminal::Closed(FeedClosedReason::OwnerReplaced)) => Err(superseded()),
        Some(Terminal::Closed(FeedClosedReason::Requested | FeedClosedReason::RuntimeStopped)) => {
            Err(cancelled())
        }
    }
}

pub(in crate::studio::runtime) fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "The original execution source is closing",
        false,
    )
}
fn superseded() -> StudioError {
    StudioError::new(
        StudioErrorCode::Superseded,
        "The exact execution source or fact is no longer available",
        false,
    )
}
fn exhausted() -> StudioError {
    StudioError::new(
        StudioErrorCode::Overloaded,
        "Execution identity/revision capacity is exhausted",
        false,
    )
}

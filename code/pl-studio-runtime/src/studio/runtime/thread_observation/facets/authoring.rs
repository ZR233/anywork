//! Authoring facts of one original observation: current, pending/unacked and scopes are the only
//! strong pins. Locators never follow the current Thread or a newer document with the same name.
mod capture;
mod delivery;

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, Weak};

use pl_protocol::studio::{StudioError, StudioErrorCode};
use pl_protocol::thread_facets::authoring::{AuthoringBaseline, PlanDocumentRef};
use pl_protocol::thread_facets::identity::{
    FeedClosedReason, ResyncReason, ThreadFacet, ThreadFacetStamp,
};
use pl_protocol::{AgentSessionPlanDocument, WorkflowRuntimeSnapshot};
use tokio::sync::Notify;

use super::super::super::thread_reads::todo::TodoSource;
pub(in crate::studio::runtime) use delivery::AuthoringDelivery;
pub use delivery::DeliveryStep;

pub(in crate::studio::runtime) enum Material {
    Todo(Arc<TodoSource>),
    Workflow(Arc<WorkflowRuntimeSnapshot>),
    Document(Arc<AgentSessionPlanDocument>),
}

enum WeakMaterial {
    Todo(Weak<TodoSource>),
    Workflow(Weak<WorkflowRuntimeSnapshot>),
    Document(Weak<AgentSessionPlanDocument>),
}
impl Material {
    fn downgrade(&self) -> WeakMaterial {
        match self {
            Self::Todo(value) => WeakMaterial::Todo(Arc::downgrade(value)),
            Self::Workflow(value) => WeakMaterial::Workflow(Arc::downgrade(value)),
            Self::Document(value) => WeakMaterial::Document(Arc::downgrade(value)),
        }
    }
    fn same(&self, other: &Self) -> bool {
        match (self, other) {
            (Self::Todo(a), Self::Todo(b)) => a == b,
            (Self::Workflow(a), Self::Workflow(b)) => a == b,
            (Self::Document(a), Self::Document(b)) => a == b,
            _ => false,
        }
    }
}
impl WeakMaterial {
    fn upgrade(&self) -> Option<Arc<Material>> {
        Some(Arc::new(match self {
            Self::Todo(value) => Material::Todo(value.upgrade()?),
            Self::Workflow(value) => Material::Workflow(value.upgrade()?),
            Self::Document(value) => Material::Document(value.upgrade()?),
        }))
    }
    fn alive(&self) -> bool {
        match self {
            Self::Todo(value) => value.strong_count() != 0,
            Self::Workflow(value) => value.strong_count() != 0,
            Self::Document(value) => value.strong_count() != 0,
        }
    }
}

#[derive(Clone)]
struct Fact {
    entry: u64,
    revision: u64,
    material: Arc<Material>,
}
struct Locator {
    material: WeakMaterial,
    born: u64,
    exposed_from: Option<u64>,
    // Documents have version/hash rather than an opaque entry on wire. Their original interval
    // prevents an expired/deleted generation from falling back to a later identical recreation.
    document: Option<PlanDocumentRef>,
    retired_at: Option<u64>,
}
struct AuthoringSnapshot {
    stamp: ThreadFacetStamp,
    value: AuthoringBaseline,
    facts: Vec<Fact>,
    todo_record: Option<pl_core::thread::extensions::ExtensionRecord>,
    source_bytes: usize,
}
struct CaptureFailure {
    wire: StudioError,
    _cause: Arc<anyhow::Error>,
    recover_on_catch_up: bool,
}
struct State {
    current: Option<Arc<AuthoringSnapshot>>,
    capture_error: Option<CaptureFailure>,
    terminal: Option<Terminal>,
    sequence: Option<u64>,
    next_entry: u64,
    locators: BTreeMap<(u64, u64), Locator>,
    listeners: Vec<Weak<AuthoringDelivery>>,
}
#[derive(Clone)]
enum Terminal {
    Failure(StudioError),
    Closed(FeedClosedReason),
}

pub(in crate::studio::runtime) struct AuthoringProjection {
    thread_id: String,
    epoch: String,
    incarnation: u64,
    state: Mutex<State>,
    changed: Notify,
}
impl AuthoringProjection {
    pub(super) fn new(thread_id: String, epoch: String, incarnation: u64) -> Self {
        Self {
            thread_id,
            epoch,
            incarnation,
            state: Mutex::new(State {
                current: None,
                capture_error: None,
                terminal: None,
                sequence: None,
                next_entry: 1,
                locators: BTreeMap::new(),
                listeners: Vec::new(),
            }),
            changed: Notify::new(),
        }
    }
    pub(in crate::studio::runtime) fn matches_origin(&self, origin: &ThreadFacetStamp) -> bool {
        origin.facet == ThreadFacet::Authoring
            && origin.runtime_epoch == self.epoch
            && origin.incarnation == self.incarnation
    }
    pub(in crate::studio::runtime) fn ensure_open(&self) -> Result<(), StudioError> {
        ensure_open(
            &self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner),
        )
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
                    return Err(error.wire.clone());
                }
                if state.current.is_some() {
                    return Ok(());
                }
            }
            changed.await;
        }
    }
    pub(in crate::studio::runtime) fn close(&self, reason: FeedClosedReason) {
        self.finish(Terminal::Closed(reason));
    }
    pub(in crate::studio::runtime) fn fail(&self, error: StudioError) {
        self.finish(Terminal::Failure(error));
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
    pub(in crate::studio::runtime) fn resync(&self, reason: ResyncReason) {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for listener in state.listeners.iter().filter_map(Weak::upgrade) {
            listener.request_resync(reason);
        }
    }
    pub(in crate::studio::runtime) fn capture_failed(&self, cause: Arc<anyhow::Error>) {
        self.capture_failure(cause, false);
    }
    /// A shared worker retry may succeed without another commit. Clear only that diagnostic
    /// after the worker catches up to an already captured committed watermark. This never
    /// reconstructs material from a coalesced snapshot or restarts a terminated listener.
    pub(in crate::studio::runtime) fn confirm_caught_up(&self, sequence: u64) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.terminal.is_none()
            && state.sequence.is_some_and(|captured| captured >= sequence)
            && state
                .capture_error
                .as_ref()
                .is_some_and(|error| error.recover_on_catch_up)
        {
            state.capture_error = None;
            drop(state);
            self.changed.notify_waiters();
        }
    }
    fn capture_failure(&self, cause: Arc<anyhow::Error>, malformed: bool) {
        let wire = if malformed {
            cause
                .downcast_ref::<StudioError>()
                .cloned()
                .unwrap_or_else(|| {
                    StudioError::new(
                        StudioErrorCode::Protocol,
                        "The original Authoring material could not be captured",
                        false,
                    )
                })
        } else {
            crate::error_mapping::studio_error_from_anyhow_ref(cause.as_ref())
        };
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.terminal.is_some() {
            return;
        }
        for listener in state.listeners.iter().filter_map(Weak::upgrade) {
            if malformed {
                listener.finish(Terminal::Failure(wire.clone()));
            } else {
                listener.request_resync(ResyncReason::SourceLagged);
            }
        }
        state.capture_error = Some(CaptureFailure {
            wire,
            _cause: cause,
            recover_on_catch_up: !malformed,
        });
        drop(state);
        self.changed.notify_waiters();
    }
    fn validate_origin(&self, state: &State, origin: &ThreadFacetStamp) -> Result<(), StudioError> {
        ensure_open(state)?;
        if !self.matches_origin(origin)
            || !state
                .current
                .as_ref()
                .is_some_and(|current| origin.revision <= current.stamp.revision)
        {
            return Err(superseded());
        }
        Ok(())
    }
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
        self.validate_origin(&state, origin)?;
        let locator = state
            .locators
            .get(&(entry, revision))
            .ok_or_else(superseded)?;
        if locator.born > origin.revision
            || locator.retired_at.is_some_and(|end| origin.revision >= end)
            || !locator
                .exposed_from
                .is_some_and(|first| first <= origin.revision)
        {
            return Err(superseded());
        }
        locator.material.upgrade().ok_or_else(superseded)
    }
    pub(in crate::studio::runtime) fn document_at(
        &self,
        reference: &PlanDocumentRef,
        origin: &ThreadFacetStamp,
    ) -> Result<Arc<Material>, StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.validate_origin(&state, origin)?;
        let locator = state
            .locators
            .values()
            .find(|locator| {
                locator.document.as_ref() == Some(reference)
                    && locator.born <= origin.revision
                    && locator.retired_at.is_none_or(|end| origin.revision < end)
            })
            .ok_or_else(superseded)?;
        if !locator
            .exposed_from
            .is_some_and(|first| first <= origin.revision)
        {
            return Err(superseded());
        }
        locator.material.upgrade().ok_or_else(superseded)
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
        "The original Authoring source is closing",
        false,
    )
}
fn superseded() -> StudioError {
    StudioError::new(
        StudioErrorCode::Superseded,
        "The exact original Authoring material is no longer available",
        false,
    )
}
fn exhausted() -> StudioError {
    StudioError::new(
        StudioErrorCode::Overloaded,
        "Authoring reference/revision capacity is exhausted",
        false,
    )
}

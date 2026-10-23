use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, Weak};

use pl_core::thread::{AttemptStatus, ThreadSnapshot, UsageSummary};
use pl_protocol::studio::{StudioError, StudioErrorCode};
use pl_protocol::thread_facets::identity::{FeedClosedReason, MetricsIdentityRef,
    ThreadFacet, ThreadFacetStamp};
use pl_protocol::thread_facets::metrics::{AuthoritativeTurnMetrics, LiveTurnMetrics, MetricsValue};
use pl_protocol::ThreadRuntimeUsageState;
use tokio::sync::watch;
use tokio_util::sync::CancellationToken;

use super::super::super::thread_reads::scalar::MetricsIdentitySource;

#[derive(Clone)]
pub(in crate::studio::runtime) struct IdentityFact {
    pub(in crate::studio::runtime) reference: MetricsIdentityRef,
    _source: Arc<MetricsIdentitySource>,
}

pub(in crate::studio::runtime) struct MetricsSnapshot {
    pub(in crate::studio::runtime) stamp: ThreadFacetStamp,
    pub(in crate::studio::runtime) value: MetricsValue,
    // Published/current, unacknowledged deliveries and opened scopes hold these actual sources.
    // The lookup below contains only weak locators; ACK may release a superseded identity.
    pub(in crate::studio::runtime) identities: Vec<IdentityFact>,
}

#[derive(Clone)]
pub(in crate::studio::runtime) enum MetricsPublication {
    Pending,
    Ready(Arc<MetricsSnapshot>),
    Failure(StudioError),
    Closed(FeedClosedReason),
}

struct State {
    current: MetricsPublication,
    closed: bool,
    close_reason: Option<FeedClosedReason>,
    next_entry: u64,
    published_revision: Option<u64>,
    identities: BTreeMap<u64, IdentityLocator>,
}

struct IdentityLocator {
    source: Weak<MetricsIdentitySource>,
    first_revision: u64,
    exposed_from: Option<u64>,
}

pub(in crate::studio::runtime) struct MetricsProjection {
    epoch: String,
    incarnation: u64,
    state: Mutex<State>,
    published: watch::Sender<MetricsPublication>,
    closed: CancellationToken,
}

impl MetricsProjection {
    pub(super) fn new(epoch: String, incarnation: u64) -> Self {
        let (published, _) = watch::channel(MetricsPublication::Pending);
        Self { epoch, incarnation, state: Mutex::new(State {
            current: MetricsPublication::Pending, closed: false, close_reason: None, next_entry: 1,
            published_revision: None, identities: BTreeMap::new(),
        }), published, closed: CancellationToken::new() }
    }

    pub(in crate::studio::runtime) fn subscribe(&self) -> watch::Receiver<MetricsPublication> {
        // Publication and subscribe/current share the same owner guard. No snapshot/listen gap.
        let _state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        self.published.subscribe()
    }

    pub(in crate::studio::runtime) fn ensure_open(&self) -> Result<(), StudioError> {
        if self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner).closed {
            Err(closed())
        } else { Ok(()) }
    }

    pub(in crate::studio::runtime) fn terminal(&self) -> Option<MetricsPublication> {
        let state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        match &state.current {
            MetricsPublication::Failure(_) | MetricsPublication::Closed(_) => Some(state.current.clone()),
            MetricsPublication::Pending | MetricsPublication::Ready(_) => None,
        }
    }

    pub(in crate::studio::runtime) fn current_close_reason(&self) -> Option<FeedClosedReason> {
        self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner).close_reason
    }

    pub(in crate::studio::runtime) fn close(&self, reason: FeedClosedReason) {
        let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        state.closed = true;
        if state.close_reason.is_none() { state.close_reason = Some(reason); }
        if !matches!(state.current, MetricsPublication::Failure(_) | MetricsPublication::Closed(_)) {
        state.current = MetricsPublication::Closed(reason);
        self.published.send_replace(state.current.clone());
    }
        drop(state);
        self.closed.cancel();
    }

    pub(in crate::studio::runtime) async fn closed_reason(&self) -> Result<FeedClosedReason, StudioError> {
        self.closed.cancelled().await;
        self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner).close_reason
            .ok_or_else(|| StudioError::new(StudioErrorCode::Protocol, "Metrics owner closed without a reason", false))
    }

    pub(in crate::studio::runtime) fn fail(&self, error: StudioError) {
        let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closed || matches!(state.current, MetricsPublication::Failure(_)) { return; }
        state.current = MetricsPublication::Failure(error);
        self.published.send_replace(state.current.clone());
    }

    /// Direct source projection: no runtime aggregate, Plan/Todo/Workflow, catalog or body cloning.
    pub(in crate::studio::runtime) fn observe(&self, snapshot: &ThreadSnapshot, usage: &UsageSummary) {
        let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closed || matches!(state.current, MetricsPublication::Failure(_)) { return; }
        match self.project(&mut state, snapshot, usage) {
            Ok(next) => {
                if matches!(&state.current, MetricsPublication::Ready(old) if old.value == next.value) { return; }
                state.published_revision = Some(next.stamp.revision);
                state.current = MetricsPublication::Ready(Arc::new(next));
            }
            Err(error) => state.current = MetricsPublication::Failure(error),
        }
        self.published.send_replace(state.current.clone());
    }

    fn project(&self, state: &mut State, snapshot: &ThreadSnapshot, usage: &UsageSummary) -> Result<MetricsSnapshot, StudioError> {
        state.identities.retain(|_, locator| locator.source.strong_count() != 0);
        let mut identities = Vec::with_capacity(2);
        let live = snapshot.model_progress.as_ref().and_then(|active| {
            let attempt = snapshot.attempts.last()?;
            let usable = matches!(&attempt.status, AttemptStatus::Running | AttemptStatus::Committed);
            if !usable || active.attempt_id != attempt.attempt_id { return None; }
            let observation = active.progress.usage_observation()?;
            (observation.attempt_id == active.attempt_id && observation.turn_id == attempt.turn_id).then_some(observation)
        });
        let live = live.map(|live| {
            let identity = Self::identity(state, &live.turn_id, Some(&live.attempt_id))?;
            let value = LiveTurnMetrics { identity: identity.reference,
                completion_tokens: live.completion_tokens, response_millis: live.response_millis,
                state: match live.state {
                    pl_core::model::ModelUsageObservationState::Live => ThreadRuntimeUsageState::Live,
                    pl_core::model::ModelUsageObservationState::Authoritative => ThreadRuntimeUsageState::Authoritative,
                }, observation_sequence: live.observation_sequence };
            identities.push(identity);
            Ok::<_, StudioError>(value)
        }).transpose()?;
        let authoritative = if usage.turn_id.is_empty() {
            None
        } else {
            let identity = Self::identity(state, &usage.turn_id, None)?;
            let value = AuthoritativeTurnMetrics { identity: identity.reference,
                completion_tokens: usage.turn_completion_tokens, response_millis: usage.turn_response_millis };
            identities.push(identity);
            Some(value)
        };
        let value = MetricsValue { live, authoritative };
        let revision = match &state.current {
            MetricsPublication::Ready(previous) if previous.value == value => previous.stamp.revision,
            MetricsPublication::Ready(previous) => previous.stamp.revision.checked_add(1).ok_or_else(exhausted)?,
            MetricsPublication::Pending => 0,
            MetricsPublication::Failure(_) | MetricsPublication::Closed(_) => return Err(closed()),
        };
        Ok(MetricsSnapshot { stamp: ThreadFacetStamp { runtime_epoch: self.epoch.clone(),
            incarnation: self.incarnation, facet: ThreadFacet::Metrics, revision }, value, identities })
    }

    fn identity(state: &mut State, turn_id: &str, attempt_id: Option<&str>) -> Result<IdentityFact, StudioError> {
        if let Some((entry, source)) = state.identities.iter().find_map(|(entry, locator)| {
            let source = locator.source.upgrade()?;
            (source.turn_id == turn_id && source.attempt_id.as_deref() == attempt_id).then_some((*entry, source))
        }) {
            return Ok(IdentityFact { reference: MetricsIdentityRef { entry }, _source: source });
        }
        let entry = state.next_entry;
        state.next_entry = entry.checked_add(1).ok_or_else(exhausted)?;
        let source = Arc::new(MetricsIdentitySource { turn_id: turn_id.to_owned(), attempt_id: attempt_id.map(str::to_owned) });
        let first_revision = match state.published_revision {
            Some(revision) => revision.checked_add(1).ok_or_else(exhausted)?,
            None => 0,
        };
        state.identities.insert(entry, IdentityLocator { source: Arc::downgrade(&source),
            first_revision, exposed_from: None });
        Ok(IdentityFact { reference: MetricsIdentityRef { entry }, _source: source })
    }

    pub(in crate::studio::runtime) fn deliver<T>(&self, snapshot: &MetricsSnapshot,
        send: impl FnOnce() -> Result<T, StudioError>) -> Result<T, StudioError> {
        let mut state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closed { return Err(closed()); }
        // The actual bounded, non-reentrant port send and ref exposure share this guard. A scope
        // can neither see an unsent latest sample nor race successful send -> locator publication.
        let value = send()?;
        for identity in &snapshot.identities {
            if let Some(locator) = state.identities.get_mut(&identity.reference.entry) {
                locator.exposed_from = Some(locator.exposed_from
                    .map_or(snapshot.stamp.revision, |old| old.min(snapshot.stamp.revision)));
            }
        }
        Ok(value)
    }

    pub(in crate::studio::runtime) fn identity_at(&self, reference: MetricsIdentityRef, origin: &ThreadFacetStamp)
        -> Result<Arc<MetricsIdentitySource>, StudioError>
    {
        let state = self.state.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closed { return Err(closed()); }
        if !self.matches_origin(origin) {
            return Err(closed());
        }
        let source = state.identities.get(&reference.entry).filter(|locator|
            origin.revision >= locator.first_revision
                && locator.exposed_from.is_some_and(|first| origin.revision >= first)
                && state.published_revision.is_some_and(|latest| origin.revision <= latest))
            .and_then(|locator| locator.source.upgrade());
        source.ok_or_else(|| StudioError::new(StudioErrorCode::Superseded,
            "The metrics identity is not delivered or no longer retained", false))
    }

    pub(in crate::studio::runtime) fn matches_origin(&self, origin: &ThreadFacetStamp) -> bool {
        origin.runtime_epoch == self.epoch && origin.incarnation == self.incarnation && origin.facet == ThreadFacet::Metrics
    }
}

fn exhausted() -> StudioError {
    StudioError::new(StudioErrorCode::Overloaded, "Thread metrics identity or revision space is exhausted", false)
}

fn closed() -> StudioError {
    StudioError::new(StudioErrorCode::Cancelled, "Thread metrics observation is closed or replaced", false)
}

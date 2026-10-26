use super::super::StudioUpdateStateSnapshot;
use super::task::UpdateTasks;
use pl_protocol::products::identity::ProductReadOrigin;
use pl_protocol::products::references::*;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::collections::{BTreeMap, VecDeque};
use std::sync::{Arc, Mutex, Weak};

pub(super) struct SummaryMaterial {
    pub reference: UpdateSummaryReadRef,
    pub details: UpdateDetailsReadRef,
    pub update: crate::StudioUpdate,
}
pub(super) struct OperationMaterial {
    pub reference: UpdateOperationReadRef,
    pub operation_id: String,
}
pub(super) struct ErrorMaterial {
    pub reference: UpdateErrorReadRef,
    pub error: pl_protocol::StateError,
}
pub(in crate::studio::runtime) struct UpdatesMaterial {
    pub(super) reference: UpdatesReadRef,
    pub(super) value: StudioUpdateStateSnapshot,
    pub(super) summary: Option<Arc<SummaryMaterial>>,
    pub(super) operation: Option<Arc<OperationMaterial>>,
    pub(super) error: Option<Arc<ErrorMaterial>>,
}
impl UpdatesMaterial {
    pub(in crate::studio::runtime) fn snapshot(&self) -> &StudioUpdateStateSnapshot {
        &self.value
    }
}
struct State {
    sealed: bool,
    failure: Option<StudioError>,
    revision: u64,
    floor: u64,
    summary_revision: u64,
    operation_revision: u64,
    error_revision: u64,
    current: Option<Arc<UpdatesMaterial>>,
    history: VecDeque<Arc<UpdatesMaterial>>,
    roots: BTreeMap<u64, Weak<UpdatesMaterial>>,
    summaries: BTreeMap<u64, Weak<SummaryMaterial>>,
    operations: BTreeMap<u64, Weak<OperationMaterial>>,
    errors: BTreeMap<u64, Weak<ErrorMaterial>>,
}
pub(in crate::studio::runtime) struct UpdatesSource {
    origin: ProductReadOrigin,
    state: Mutex<State>,
    updates: tokio::sync::watch::Sender<()>,
    pub(super) tasks: UpdateTasks,
}
impl UpdatesSource {
    pub(in crate::studio::runtime) fn new(origin: ProductReadOrigin) -> Arc<Self> {
        let (updates, _) = tokio::sync::watch::channel(());
        Arc::new(Self {
            origin,
            updates,
            tasks: UpdateTasks::default(),
            state: Mutex::new(State {
                sealed: false,
                failure: None,
                revision: 0,
                floor: 0,
                summary_revision: 0,
                operation_revision: 0,
                error_revision: 0,
                current: None,
                history: VecDeque::new(),
                roots: BTreeMap::new(),
                summaries: BTreeMap::new(),
                operations: BTreeMap::new(),
                errors: BTreeMap::new(),
            }),
        })
    }
    pub(super) fn origin(&self) -> &ProductReadOrigin {
        &self.origin
    }
    pub(in crate::studio::runtime) fn publish(
        &self,
        value: StudioUpdateStateSnapshot,
    ) -> Result<Arc<UpdatesMaterial>, StudioError> {
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
        value: StudioUpdateStateSnapshot,
    ) -> Result<Arc<UpdatesMaterial>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if let Some(error) = &state.failure {
            return Err(error.clone());
        }
        // In-flight tasks may capture their actual terminal result after the external seal. The
        // source remains unavailable to readers; only finish_close may release those task pins.
        if let Some(old) = &state.current
            && old.value == value
        {
            return Ok(old.clone());
        }
        let previous = state.current.clone();
        let revision = next(state.revision)?;
        let summary = value
            .update()
            .map(|update| -> Result<_, StudioError> {
                if let Some(old) = previous.as_ref().and_then(|old| old.summary.as_ref())
                    && old.update == *update
                {
                    return Ok(old.clone());
                }
                let revision = next(state.summary_revision)?;
                state.summary_revision = revision;
                Ok(Arc::new(SummaryMaterial {
                    reference: UpdateSummaryReadRef { entry: 2, revision },
                    details: UpdateDetailsReadRef { entry: 5, revision },
                    update: update.clone(),
                }))
            })
            .transpose()?;
        let operation = match &value {
            StudioUpdateStateSnapshot::Checking(value) => {
                if let Some(old) = previous.as_ref().and_then(|old| old.operation.as_ref())
                    && old.operation_id == value.operation_id()
                {
                    Some(old.clone())
                } else {
                    let revision = next(state.operation_revision)?;
                    state.operation_revision = revision;
                    Some(Arc::new(OperationMaterial {
                        reference: UpdateOperationReadRef { entry: 3, revision },
                        operation_id: value.operation_id().to_owned(),
                    }))
                }
            }
            _ => None,
        };
        let error = match &value {
            StudioUpdateStateSnapshot::CheckFailed(value) => Some(value.error()),
            StudioUpdateStateSnapshot::InstallFailed(value) => Some(value.error()),
            _ => None,
        }
        .map(|error| -> Result<_, StudioError> {
            if let Some(old) = previous.as_ref().and_then(|old| old.error.as_ref())
                && old.error == *error
            {
                return Ok(old.clone());
            }
            let revision = next(state.error_revision)?;
            state.error_revision = revision;
            Ok(Arc::new(ErrorMaterial {
                reference: UpdateErrorReadRef { entry: 4, revision },
                error: error.clone(),
            }))
        })
        .transpose()?;
        let material = Arc::new(UpdatesMaterial {
            reference: UpdatesReadRef { entry: 1, revision },
            value,
            summary,
            operation,
            error,
        });
        state.revision = revision;
        let latest = !previous
            .as_ref()
            .is_some_and(|old| old.value.revision() > material.value.revision());
        if latest {
            // Only same-stage download counters may coalesce; stage transitions remain reliable.
            if matches!(material.value, StudioUpdateStateSnapshot::Downloading(_))
                && state.history.back().is_some_and(|old| {
                    matches!(old.value, StudioUpdateStateSnapshot::Downloading(_))
                })
            {
                state.history.pop_back();
            }
            state.current = Some(material.clone());
            state.history.push_back(material.clone());
            while state.history.len() > 64 {
                if let Some(old) = state.history.pop_front() {
                    state.floor = old.reference.revision;
                }
            }
            self.updates.send_replace(());
        }
        prune(&mut state);
        Ok(material)
    }
    pub(super) fn observe(
        &self,
    ) -> Result<(Arc<UpdatesMaterial>, tokio::sync::watch::Receiver<()>), StudioError> {
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
    pub(super) fn next_after(
        &self,
        revision: Option<u64>,
    ) -> Result<Option<Arc<UpdatesMaterial>>, StudioError> {
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
        match revision {
            None => Ok(state.current.clone()),
            Some(revision) if revision < state.floor => Err(StudioError::new(
                StudioErrorCode::Superseded,
                "Reliable update stage queue was exceeded",
                true,
            )),
            Some(revision) => Ok(state
                .history
                .iter()
                .find(|value| value.reference.revision > revision)
                .cloned()),
        }
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
    fn check(&self, state: &State, origin: &ProductReadOrigin) -> Result<(), StudioError> {
        if state.sealed || origin != &self.origin {
            Err(cancelled())
        } else {
            Ok(())
        }
    }
    pub(super) fn pin(
        &self,
        origin: &ProductReadOrigin,
        reference: UpdatesReadRef,
    ) -> Result<Arc<UpdatesMaterial>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check(&state, origin)?;
        prune(&mut state);
        if reference.entry != 1 {
            return Err(wrong());
        }
        state
            .roots
            .get(&reference.revision)
            .and_then(Weak::upgrade)
            .ok_or_else(expired)
    }
    pub(super) fn pin_summary(
        &self,
        origin: &ProductReadOrigin,
        entry: u64,
        revision: u64,
        details: bool,
    ) -> Result<Arc<SummaryMaterial>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check(&state, origin)?;
        prune(&mut state);
        if entry != if details { 5 } else { 2 } {
            return Err(wrong());
        }
        state
            .summaries
            .get(&revision)
            .and_then(Weak::upgrade)
            .ok_or_else(expired)
    }
    pub(super) fn pin_operation(
        &self,
        origin: &ProductReadOrigin,
        reference: UpdateOperationReadRef,
    ) -> Result<Arc<OperationMaterial>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check(&state, origin)?;
        prune(&mut state);
        if reference.entry != 3 {
            return Err(wrong());
        }
        state
            .operations
            .get(&reference.revision)
            .and_then(Weak::upgrade)
            .ok_or_else(expired)
    }
    pub(super) fn pin_error(
        &self,
        origin: &ProductReadOrigin,
        reference: UpdateErrorReadRef,
    ) -> Result<Arc<ErrorMaterial>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        self.check(&state, origin)?;
        prune(&mut state);
        if reference.entry != 4 {
            return Err(wrong());
        }
        state
            .errors
            .get(&reference.revision)
            .and_then(Weak::upgrade)
            .ok_or_else(expired)
    }
    pub(super) fn send_exposing(
        &self,
        material: &Arc<UpdatesMaterial>,
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
            expose(&mut state, material);
        }
        Ok(sent)
    }
    pub(in crate::studio::runtime) fn expose_committed(
        &self,
        material: &Arc<UpdatesMaterial>,
    ) -> UpdatesReadTarget {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        expose(&mut state, material);
        UpdatesReadTarget {
            origin: self.origin.clone(),
            reference: material.reference,
        }
    }
    pub(in crate::studio::runtime) fn seal(&self) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sealed = true;
        self.tasks.seal();
        self.updates.send_replace(());
    }
    pub(in crate::studio::runtime) async fn close_tasks(
        &self,
    ) -> Vec<pl_protocol::studio::FeedCloseIssue> {
        self.tasks.close().await
    }
    pub(in crate::studio::runtime) fn finish_close(&self) {
        self.seal();
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.current.take();
        state.history.clear();
        state.roots.clear();
        state.summaries.clear();
        state.operations.clear();
        state.errors.clear();
    }
}
fn expose(state: &mut State, material: &Arc<UpdatesMaterial>) {
    state
        .roots
        .insert(material.reference.revision, Arc::downgrade(material));
    if let Some(summary) = &material.summary {
        state
            .summaries
            .insert(summary.reference.revision, Arc::downgrade(summary));
    }
    if let Some(operation) = &material.operation {
        state
            .operations
            .insert(operation.reference.revision, Arc::downgrade(operation));
    }
    if let Some(error) = &material.error {
        state
            .errors
            .insert(error.reference.revision, Arc::downgrade(error));
    }
}
fn prune(state: &mut State) {
    state.roots.retain(|_, value| value.strong_count() != 0);
    state.summaries.retain(|_, value| value.strong_count() != 0);
    state
        .operations
        .retain(|_, value| value.strong_count() != 0);
    state.errors.retain(|_, value| value.strong_count() != 0);
}
fn next(value: u64) -> Result<u64, StudioError> {
    value.checked_add(1).ok_or_else(|| {
        StudioError::new(
            StudioErrorCode::Overloaded,
            "Update identity space exhausted",
            false,
        )
    })
}
fn expired() -> StudioError {
    StudioError::new(
        StudioErrorCode::Superseded,
        "Update material is not exposed or retained by its original source",
        true,
    )
}
fn wrong() -> StudioError {
    StudioError::invalid_argument("Update reference belongs to another read kind")
}
pub(super) fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Update source is closing",
        false,
    )
}

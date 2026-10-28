//! Every canonical publication captures identities before notification coalescing.
use crate::StudioRecoveryIssue;
use pl_protocol::ObservedResource;
use pl_protocol::products::identity::*;
use pl_protocol::products::references::RecoveryReadRef;
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::collections::{BTreeMap, VecDeque};
use std::sync::{Arc, Mutex, Weak};

pub(super) struct RecoverySnapshot {
    pub revision: u64,
    pub reference: Option<RecoveryReadRef>,
    pub collection: Option<ProductCollectionRef>,
    pub entities: Vec<ProductEntityRef>,
    pub metadata: ObservedResource<()>,
    pub status: ProductSourceStatusRef,
    pub value: Option<Arc<Vec<StudioRecoveryIssue>>>,
}
struct State {
    sealed: bool,
    revision: u64,
    value_revision: u64,
    status_revision: u64,
    collection_revision: u64,
    next_entity: u64,
    current: Option<Arc<RecoverySnapshot>>,
    values: BTreeMap<u64, Weak<RecoverySnapshot>>,
    statuses: BTreeMap<u64, Weak<RecoverySnapshot>>,
    committed: VecDeque<Arc<RecoverySnapshot>>,
    failure: Option<StudioError>,
}
pub(in crate::studio) struct RecoverySource {
    origin: ProductReadOrigin,
    state: Mutex<State>,
    updates: tokio::sync::watch::Sender<()>,
}
impl std::fmt::Debug for RecoverySource {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("RecoverySource")
            .field("origin", &self.origin)
            .finish_non_exhaustive()
    }
}
impl RecoverySource {
    pub(in crate::studio) fn new(origin: ProductReadOrigin) -> Arc<Self> {
        let (updates, _) = tokio::sync::watch::channel(());
        Arc::new(Self {
            origin,
            state: Mutex::new(State {
                sealed: false,
                revision: 0,
                value_revision: 0,
                status_revision: 0,
                collection_revision: 0,
                next_entity: 4,
                current: None,
                values: BTreeMap::new(),
                statuses: BTreeMap::new(),
                committed: VecDeque::new(),
                failure: None,
            }),
            updates,
        })
    }
    pub(super) fn origin(&self) -> &ProductReadOrigin {
        &self.origin
    }
    pub(in crate::studio) fn publish(&self, value: ObservedResource<Vec<StudioRecoveryIssue>>) {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.sealed {
            return;
        }
        let previous = state.current.clone();
        match capture(&mut state, value, previous.as_ref()) {
            Ok(snapshot) => state.current = Some(snapshot),
            Err(error) => state.failure = Some(error),
        }
        prune(&mut state);
        drop(state);
        self.updates.send_replace(());
    }
    /// Called with the command's exact captured result, not with a feed's latest header/ref.
    /// An older result is a detached immutable command publication and cannot roll current back.
    /// Eight bounded receipt pins keep targets readable after the bridge reply releases its owner.
    pub(super) fn capture_committed(
        &self,
        value: ObservedResource<Vec<StudioRecoveryIssue>>,
    ) -> Result<Arc<RecoverySnapshot>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        check(&state)?;
        let current = state.current.clone();
        let same = current.as_ref().is_some_and(|s| {
            s.metadata == value.clone().map(|_| ())
                && s.value.as_deref().map(Vec::as_slice) == value.value().map(Vec::as_slice)
        });
        let snapshot = if same {
            current.ok_or_else(cancelled)?
        } else {
            capture(&mut state, value, None)?
        };
        expose(&mut state, &snapshot);
        state.committed.push_back(snapshot.clone());
        if state.committed.len() > 8 {
            state.committed.pop_front();
        }
        prune(&mut state);
        Ok(snapshot)
    }
    pub(super) fn current(&self) -> Result<Arc<RecoverySnapshot>, StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        check(&state)?;
        state.current.clone().ok_or_else(cancelled)
    }
    pub(super) fn observe(
        &self,
    ) -> Result<(Arc<RecoverySnapshot>, tokio::sync::watch::Receiver<()>), StudioError> {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        check(&state)?;
        Ok((
            state.current.clone().ok_or_else(cancelled)?,
            self.updates.subscribe(),
        ))
    }
    pub(super) fn is_sealed(&self) -> bool {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sealed
    }
    pub(super) fn ensure_open(&self) -> Result<(), StudioError> {
        check(
            &self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner),
        )
    }
    /// The bounded synchronous callback cannot reenter this source. Failed sends grant no access.
    pub(super) fn send_exposing(
        &self,
        snapshot: &Arc<RecoverySnapshot>,
        send: impl FnOnce() -> Result<bool, StudioError>,
    ) -> Result<bool, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        check(&state)?;
        let sent = send()?;
        if sent {
            expose(&mut state, snapshot);
        }
        Ok(sent)
    }
    pub(super) fn pin(
        &self,
        origin: &ProductReadOrigin,
        entry: u64,
        revision: u64,
        status: bool,
    ) -> Result<Arc<RecoverySnapshot>, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        check(&state)?;
        let issued = if status {
            state.status_revision
        } else {
            state.value_revision
        };
        if origin != &self.origin
            || entry != (if status { 3 } else { 1 })
            || revision == 0
            || revision > issued
        {
            return Err(unpublished());
        }
        prune(&mut state);
        let values = if status {
            &state.statuses
        } else {
            &state.values
        };
        values
            .get(&revision)
            .and_then(Weak::upgrade)
            .ok_or_else(|| {
                StudioError::new(
                    StudioErrorCode::Superseded,
                    "The original Recovery publication expired or was not exposed",
                    true,
                )
            })
    }
    pub(in crate::studio) fn seal(&self) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .sealed = true;
        self.updates.send_replace(());
    }
    pub(in crate::studio) fn finish_close(&self) {
        self.seal();
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.current.take();
        state.values.clear();
        state.statuses.clear();
        state.committed.clear();
    }
}
fn capture(
    state: &mut State,
    value: ObservedResource<Vec<StudioRecoveryIssue>>,
    previous: Option<&Arc<RecoverySnapshot>>,
) -> Result<Arc<RecoverySnapshot>, StudioError> {
    let metadata = value.clone().map(|_| ());
    let items = value.value().cloned().map(Arc::new);
    let values_same =
        previous.is_some_and(|previous| previous.value.as_deref() == items.as_deref());
    let status_same = previous.is_some_and(|previous| previous.metadata == metadata);
    if values_same && status_same {
        return previous.cloned().ok_or_else(cancelled);
    }
    let revision = next(state.revision)?;
    let status = if status_same {
        previous.ok_or_else(cancelled)?.status
    } else {
        state.status_revision = next(state.status_revision)?;
        ProductSourceStatusRef {
            entry: 3,
            revision: state.status_revision,
        }
    };
    let (reference, collection, entities) = if values_same {
        let previous = previous.ok_or_else(cancelled)?;
        (
            previous.reference,
            previous.collection,
            previous.entities.clone(),
        )
    } else {
        state.value_revision = next(state.value_revision)?;
        state.collection_revision = next(state.collection_revision)?;
        let mut entities = Vec::new();
        let mut ids = std::collections::BTreeSet::new();
        if let Some(items) = &items {
            for item in items.iter() {
                if !ids.insert(&item.id) {
                    return Err(StudioError::new(
                        StudioErrorCode::Protocol,
                        "Duplicate Recovery issue identity",
                        false,
                    ));
                }
                let old = previous.and_then(|previous| {
                    previous.value.as_ref().and_then(|values| {
                        values
                            .iter()
                            .position(|old| old.id == item.id)
                            .map(|index| (&values[index], previous.entities[index]))
                    })
                });
                entities.push(match old {
                    Some((old, reference)) if old == item => reference,
                    Some((_, reference)) => ProductEntityRef {
                        entry: reference.entry,
                        revision: next(reference.revision)?,
                    },
                    None => {
                        let entry = state.next_entity;
                        state.next_entity = next(entry)?;
                        ProductEntityRef { entry, revision: 1 }
                    }
                });
            }
        }
        (
            items.as_ref().map(|_| RecoveryReadRef {
                entry: 1,
                revision: state.value_revision,
            }),
            items.as_ref().map(|items| ProductCollectionRef {
                entry: 2,
                revision: state.collection_revision,
                total: items.len() as u64,
            }),
            entities,
        )
    };
    state.revision = revision;
    Ok(Arc::new(RecoverySnapshot {
        revision,
        reference,
        collection,
        entities,
        metadata,
        status,
        value: items,
    }))
}
fn expose(state: &mut State, snapshot: &Arc<RecoverySnapshot>) {
    prune(state);
    if let Some(reference) = snapshot.reference {
        state
            .values
            .entry(reference.revision)
            .or_insert_with(|| Arc::downgrade(snapshot));
    }
    state
        .statuses
        .entry(snapshot.status.revision)
        .or_insert_with(|| Arc::downgrade(snapshot));
}
fn prune(state: &mut State) {
    state.values.retain(|_, value| value.strong_count() > 0);
    state.statuses.retain(|_, value| value.strong_count() > 0);
}
fn check(state: &State) -> Result<(), StudioError> {
    if state.sealed {
        Err(cancelled())
    } else {
        state.failure.clone().map_or(Ok(()), Err)
    }
}
fn next(value: u64) -> Result<u64, StudioError> {
    value.checked_add(1).ok_or_else(|| {
        StudioError::new(
            StudioErrorCode::Overloaded,
            "Recovery identity exhausted",
            false,
        )
    })
}
fn unpublished() -> StudioError {
    StudioError::invalid_argument("Recovery reference/origin was not issued by this source")
}
fn cancelled() -> StudioError {
    StudioError::new(
        StudioErrorCode::Cancelled,
        "Recovery source is closing or unavailable",
        false,
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::{
        StudioRecoveryIssueAction, StudioRecoveryIssueCategory, StudioRecoveryIssueScope,
        StudioRecoveryRegistry,
    };

    #[test]
    fn registry_mutations_publish_typed_source_without_legacy_product_events()
    -> Result<(), StudioError> {
        let source = RecoverySource::new(ProductReadOrigin {
            owner_epoch: "registry-publication-fixture".into(),
            incarnation: 1,
        });
        let registry = StudioRecoveryRegistry::new();
        registry.attach_source(source.clone());
        let (initial, mut updates) = source.observe()?;
        assert!(
            initial
                .value
                .as_ref()
                .expect("initial ready value")
                .is_empty()
        );

        registry.begin();
        assert!(
            updates
                .has_changed()
                .expect("source notification remains live")
        );
        updates.borrow_and_update();
        assert!(matches!(
            &source.current()?.metadata,
            ObservedResource::Refreshing(_)
        ));
        let issue = StudioRecoveryIssue {
            id: "thread-issue".into(),
            scope: StudioRecoveryIssueScope::Thread,
            category: StudioRecoveryIssueCategory::Repository,
            action: StudioRecoveryIssueAction::Retry,
            project_id: Some("project".into()),
            thread_id: Some("child".into()),
            message: "original diagnostic".into(),
            worktree: None,
        };
        registry.replace(vec![issue.clone()]);
        let published = source.current()?;
        assert_eq!(published.value.as_deref(), Some(&vec![issue.clone()]));
        assert_eq!(published.collection.expect("published collection").total, 1);

        let mut changed = issue.clone();
        changed.message = "updated diagnostic".into();
        registry.update_if_current(&issue.id, Some(changed.clone()), || false);
        assert!(
            Arc::ptr_eq(&source.current()?, &published),
            "stale producers cannot publish"
        );
        registry.update_if_current(&issue.id, Some(changed.clone()), || true);
        assert_eq!(source.current()?.value.as_deref(), Some(&vec![changed]));

        registry.fail(
            std::io::Error::new(std::io::ErrorKind::PermissionDenied, "private cause").into(),
        );
        let failed = source.current()?;
        let ObservedResource::Degraded(metadata) = &failed.metadata else {
            panic!("failure is published with the retained issue value");
        };
        assert!(metadata.error().message.contains("PermissionDenied"));
        assert!(!metadata.error().message.contains("private cause"));

        registry.retire_thread("child");
        assert!(
            source
                .current()?
                .value
                .as_ref()
                .expect("retired value")
                .is_empty()
        );
        registry.replace(vec![issue.clone()]);
        assert!(
            source
                .current()?
                .value
                .as_ref()
                .expect("retired owner remains retired")
                .is_empty()
        );

        registry.begin();
        let mut worktree = issue;
        worktree.id = "worktree-lease-child".into();
        registry.replace(vec![worktree.clone()]);
        registry.retire_thread("child");
        assert_eq!(
            source.current()?.value.as_deref(),
            Some(&vec![worktree.clone()]),
            "retiring execution cannot retire its workspace diagnosis"
        );
        registry.remove(&worktree.id);
        assert!(
            source
                .current()?
                .value
                .as_ref()
                .expect("removed value")
                .is_empty()
        );
        registry.replace(vec![worktree]);
        assert!(
            source
                .current()?
                .value
                .as_ref()
                .expect("removed identity remains removed")
                .is_empty()
        );
        registry.stop();
        assert!(matches!(
            &source.current()?.metadata,
            ObservedResource::Stopped(_)
        ));
        Ok(())
    }
}

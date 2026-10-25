use super::*;
use crate::studio::thread_projection::LiveEvent;
use pl_core::thread::ThreadSnapshot;
use pl_protocol::thread_facets::execution::*;
use pl_protocol::thread_facets::identity::*;
use pl_protocol::{InteractionStatus, TurnCancellationCause, TurnRolloverOutcome, TurnState};

impl ExecutionProjection {
    /// Called only by the existing LiveOwner, once per compatible committed/streaming capture.
    /// The immutable read facts are shared by current, reliable delivery and opened scopes.
    #[allow(clippy::too_many_arguments)] // 参数即 facet 捕获所需的不可变事实集合，逐项传递避免复制第二份事实源。
    pub(in crate::studio::runtime) fn observe(
        &self,
        thread_id: &str,
        updated_at: i64,
        snapshot: &ThreadSnapshot,
        recent: Option<Arc<Turn>>,
        activity: Option<Arc<ThreadActivity>>,
        storage: Option<Arc<ThreadStorageState>>,
        effects: &[LiveEvent],
    ) {
        let result = self.capture(
            thread_id, updated_at, snapshot, recent, activity, storage, effects,
        );
        if let Err(error) = result {
            self.fail(error);
        }
    }

    #[allow(clippy::too_many_arguments)] // 同上：与 observe 保持同一事实形状。
    fn capture(
        &self,
        thread_id: &str,
        updated_at: i64,
        snapshot: &ThreadSnapshot,
        recent: Option<Arc<Turn>>,
        activity: Option<Arc<ThreadActivity>>,
        storage: Option<Arc<ThreadStorageState>>,
        effects: &[LiveEvent],
    ) -> Result<(), StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.terminal.is_some() {
            return Ok(());
        }
        // A stream preview captured before a now-admitted effect must never roll the execution
        // source back after that effect has already been published by this same owner.
        if state
            .core_sequence
            .is_some_and(|applied| snapshot.commit_sequence < applied)
        {
            return Ok(());
        }
        prune(&mut state);
        let previous = state.current.clone();
        let mut facts = Vec::new();
        let active =
            crate::studio::thread_projection::project_active_turn(thread_id, snapshot, updated_at)
                .map_err(|_| corrupt())?;
        let active_turn = active
            .map(|turn| turn_fact(&mut state, Arc::new(turn), &mut facts))
            .transpose()?;
        let recent_terminal_turn = recent
            .map(|turn| turn_fact(&mut state, turn, &mut facts))
            .transpose()?;
        let mut entries = Vec::new();
        if state.core_sequence == Some(snapshot.commit_sequence) {
            if let Some(previous) = &previous {
                for fact in &previous.facts {
                    if let Material::Interaction(value) = &*fact.material {
                        facts.push(fact.clone());
                        entries.push(interaction_brief(fact, value));
                    }
                }
            }
        } else {
            for id in snapshot
                .permissions
                .keys()
                .chain(snapshot.interactions.keys())
            {
                let value =
                    crate::thread_assembler::project_thread_interaction(thread_id, id, snapshot)
                        .map_err(|_| corrupt())?
                        .ok_or_else(corrupt)?;
                let value = Arc::new(value);
                let fact = register(
                    &mut state,
                    Key::Interaction(value.interaction_id.clone()),
                    value.revision,
                    Material::Interaction(value.clone()),
                )?;
                entries.push(interaction_brief(&fact, &value));
                facts.push(fact);
            }
        }
        entries.sort_by_key(|entry| entry.reference.entry);
        let previous_index = previous.as_ref().and_then(|previous| {
            previous.facts.iter().find_map(|fact| {
                if let Material::Index(index) = &*fact.material {
                    Some(index.clone())
                } else {
                    None
                }
            })
        });
        let index_revision = match &previous_index {
            Some(old) if old.entries == entries => old.revision,
            Some(old) => old.revision.checked_add(1).ok_or_else(exhausted)?,
            None => 0,
        };
        let members = facts
            .iter()
            .filter_map(|fact| {
                if let Material::Interaction(value) = &*fact.material {
                    Some(value.clone())
                } else {
                    None
                }
            })
            .collect();
        let index = Arc::new(InteractionIndexSource {
            revision: index_revision,
            entries,
            _members: members,
        });
        let index_fact = register(
            &mut state,
            Key::Index,
            index_revision,
            Material::Index(index.clone()),
        )?;
        let interactions = InteractionIndexHeader {
            reference: InteractionIndexRef {
                entry: index_fact.entry,
                revision: index_revision,
            },
            total: u64::try_from(index.entries.len()).map_err(|_| exhausted())?,
            pending: u64::try_from(
                index
                    .entries
                    .iter()
                    .filter(|entry| entry.status == InteractionStatus::Pending)
                    .count(),
            )
            .map_err(|_| exhausted())?,
        };
        facts.push(index_fact);
        let activity = activity
            .map(|value| {
                let continuing = previous
                    .as_ref()
                    .and_then(|previous| {
                        previous.facts.iter().find_map(|fact| {
                            if let Material::Activity(old) = &*fact.material {
                                Some(old)
                            } else {
                                None
                            }
                        })
                    })
                    .is_some_and(|old| {
                        old.identity == value.identity && old.revision <= value.revision
                    });
                if !continuing {
                    state.keys.remove(&Key::Activity(value.identity.clone()));
                }
                let fact = register(
                    &mut state,
                    Key::Activity(value.identity.clone()),
                    value.revision,
                    Material::Activity(value.clone()),
                )?;
                let brief = ActivityBrief {
                    reference: ActivityReadRef {
                        entry: fact.entry,
                        revision: fact.revision,
                    },
                    revision: value.revision,
                    kind: value.kind,
                    tool_count: value.tools.count,
                    background_count: value.tools.background,
                    active_count: u64::try_from(value.tools.active.len())
                        .map_err(|_| exhausted())?,
                    has_latest_started: value.tools.latest_started.is_some(),
                };
                facts.push(fact);
                Ok::<_, StudioError>(brief)
            })
            .transpose()?;
        let storage = storage.map(|value| {
            let old = previous.as_ref().and_then(|previous| previous.facts.iter().find(|fact| matches!(&*fact.material, Material::Storage(_))));
            let revision = match old {
                Some(old) if matches!(&*old.material, Material::Storage(source) if source == &value) => old.revision,
                Some(old) => old.revision.checked_add(1).ok_or_else(exhausted)?, None => 0,
            };
            let fact = register(&mut state, Key::Storage, revision, Material::Storage(value.clone()))?;
            let brief = StorageBrief { reference: StorageReadRef { entry: fact.entry, revision },
                fault: value.fault, fault_generation: value.fault_generation, accepted_sequence: value.accepted_sequence,
                durable_sequence: value.durable_sequence, execution: value.execution, pressure_paused: value.pressure_paused,
                resume_required: value.resume_required, can_resume: value.can_resume, has_last_error: value.last_error.is_some() };
            facts.push(fact); Ok::<_, StudioError>(brief)
        }).transpose()?;
        let mut status = crate::studio::thread_projection::status(snapshot);
        if crate::studio::agent_close::is_explicitly_closed(snapshot).map_err(|_| corrupt())?
            && snapshot.lifecycle == pl_core::thread::ThreadLifecycle::Open
        {
            status = pl_protocol::ThreadStatus::Closing;
        }
        let value = ExecutionBaseline {
            status,
            active_turn,
            recent_terminal_turn,
            interactions,
            activity,
            storage,
        };
        // An effect's terminal can have left the compact current set. Only the actual projected
        // terminal authorizes terminal_facts; disappearance is never converted to a decision.
        let mut terminal_facts = Vec::new();
        let mut terminal_pins = Vec::new();
        for effect in effects {
            if let LiveEvent::Interaction(value) = effect
                && value.status() != InteractionStatus::Pending
            {
                let value = Arc::new((**value).clone());
                let fact = register(
                    &mut state,
                    Key::Interaction(value.interaction_id.clone()),
                    value.revision,
                    Material::Interaction(value.clone()),
                )?;
                if !index
                    .entries
                    .iter()
                    .any(|entry| entry.reference.entry == fact.entry)
                {
                    terminal_facts.push(interaction_brief(&fact, &value));
                    terminal_pins.push(fact);
                }
            }
        }
        state.core_sequence = Some(snapshot.commit_sequence);
        state.capture_error = None;
        if previous.as_ref().is_some_and(|old| old.value == value) && terminal_facts.is_empty() {
            drop(state);
            self.changed.notify_waiters();
            return Ok(());
        }
        let revision = previous
            .as_ref()
            .map(|old| old.stamp.revision.checked_add(1).ok_or_else(exhausted))
            .transpose()?
            .unwrap_or(0);
        let next = Arc::new(ExecutionSnapshot {
            stamp: ThreadFacetStamp {
                runtime_epoch: self.epoch.clone(),
                incarnation: self.incarnation,
                facet: ThreadFacet::Execution,
                revision,
            },
            value,
            facts,
        });
        let change = previous.as_ref().map(|old| {
            delta(
                old,
                &next,
                previous_index.as_deref(),
                &index,
                terminal_facts,
            )
        });
        state
            .listeners
            .retain(|listener| listener.strong_count() != 0);
        for listener in state.listeners.iter().filter_map(Weak::upgrade) {
            listener.publish(next.clone(), change.clone(), terminal_pins.clone());
        }
        state.current = Some(next);
        drop(state);
        self.changed.notify_waiters();
        Ok(())
    }
}

fn register(
    state: &mut State,
    key: Key,
    revision: u64,
    material: Material,
) -> Result<Fact, StudioError> {
    register_source(state, key, revision, material, FactSource::Projection)
}

fn register_source(
    state: &mut State,
    key: Key,
    revision: u64,
    material: Material,
    source: FactSource,
) -> Result<Fact, StudioError> {
    let entry = match state.keys.get(&key) {
        Some(entry) => *entry,
        None => {
            let entry = state.next_entry;
            state.next_entry = entry.checked_add(1).ok_or_else(exhausted)?;
            state.keys.insert(key, entry);
            entry
        }
    };
    if let Some(locator) = state.locators.get_mut(&(entry, revision))
        && let Some(previous) = locator.material.upgrade()
    {
        if !same(&previous, &material) {
            return Err(corrupt());
        }
        if source == FactSource::Projection {
            locator.source = source;
        }
        return Ok(Fact {
            entry,
            revision,
            material: previous,
        });
    }
    let material = Arc::new(material);
    let previous = state.locators.get(&(entry, revision));
    let exposed_from = previous.and_then(|locator| locator.exposed_from);
    let durable_from = previous.and_then(|locator| locator.durable_from);
    let source = if previous.is_some_and(|locator| locator.source == FactSource::Projection) {
        FactSource::Projection
    } else {
        source
    };
    let interaction = match &*material {
        Material::Interaction(value) => Some(InteractionIdentity::from_fact(value)?),
        _ => None,
    };
    if previous.is_some_and(|locator| locator.interaction != interaction) {
        return Err(corrupt());
    }
    state.locators.insert(
        (entry, revision),
        Locator {
            material: material.downgrade(),
            source,
            exposed_from,
            interaction,
            durable_from,
        },
    );
    Ok(Fact {
        entry,
        revision,
        material,
    })
}

fn same(left: &Material, right: &Material) -> bool {
    match (left, right) {
        (Material::Turn(left), Material::Turn(right)) => left == right,
        (Material::Interaction(left), Material::Interaction(right)) => left == right,
        (Material::Index(left), Material::Index(right)) => {
            left.revision == right.revision && left.entries == right.entries
        }
        (Material::Activity(left), Material::Activity(right)) => left == right,
        (Material::Storage(left), Material::Storage(right)) => left == right,
        _ => false,
    }
}

fn turn_fact(
    state: &mut State,
    mut turn: Arc<Turn>,
    facts: &mut Vec<Fact>,
) -> Result<TurnBrief, StudioError> {
    if let Some(entry) = state.keys.get(&Key::Turn(turn.id.clone()))
        && let Some(old) = state
            .locators
            .range((*entry, 0)..=(*entry, u64::MAX))
            .rev()
            .find_map(|(_, locator)| locator.material.upgrade())
        && let Material::Turn(previous) = &*old
    {
        if previous.state == turn.state && previous.input_id == turn.input_id {
            turn = previous.clone();
        } else if turn.revision <= previous.revision {
            let value = Arc::make_mut(&mut turn);
            value.revision = previous.revision.checked_add(1).ok_or_else(exhausted)?;
        }
    }
    let fact = register(
        state,
        Key::Turn(turn.id.clone()),
        turn.revision,
        Material::Turn(turn.clone()),
    )?;
    let value = TurnBrief {
        reference: TurnReadRef {
            entry: fact.entry,
            revision: fact.revision,
        },
        revision: turn.revision,
        updated_at: turn.updated_at,
        state: match &turn.state {
            TurnState::Queued(value) => TurnBriefState::Queued {
                queued_at: value.queued_at(),
            },
            TurnState::Running(value) => TurnBriefState::Running {
                started_at: value.started_at(),
                phase: value.phase(),
            },
            TurnState::Completed(value) => TurnBriefState::Completed {
                started_at: value.started_at(),
                completed_at: value.completed_at(),
                completion: value.completion(),
            },
            TurnState::Cancelled(value) => TurnBriefState::Cancelled {
                started_at: value.started_at(),
                requested_at: value.requested_at(),
                completed_at: value.completed_at(),
                cause: match value.cause() {
                    TurnCancellationCause::Unspecified => TurnCancellationKind::Unspecified,
                    TurnCancellationCause::UserRequested => TurnCancellationKind::UserRequested,
                    TurnCancellationCause::RuntimeShutdown => TurnCancellationKind::RuntimeShutdown,
                    TurnCancellationCause::AgentClosed => TurnCancellationKind::AgentClosed,
                    TurnCancellationCause::Interrupted => TurnCancellationKind::Interrupted,
                    TurnCancellationCause::Recovery => TurnCancellationKind::Recovery,
                    TurnCancellationCause::Coalesced { .. } => TurnCancellationKind::Coalesced,
                },
            },
            TurnState::Failed(value) => TurnBriefState::Failed {
                started_at: value.started_at(),
                completed_at: value.completed_at(),
                category: value.failure().category,
                provider_kind: value.failure().provider_kind,
                http_status: value.failure().http_status,
                retry: value.failure().retry.clone(),
            },
            TurnState::BudgetLimited(value) => TurnBriefState::BudgetLimited {
                started_at: value.started_at(),
                completed_at: value.completed_at(),
                limit: *value.limit(),
                rollover: match value.rollover() {
                    TurnRolloverOutcome::NotAttempted => TurnRolloverKind::NotAttempted,
                    TurnRolloverOutcome::Succeeded => TurnRolloverKind::Succeeded,
                    TurnRolloverOutcome::Failed { .. } => TurnRolloverKind::Failed,
                },
            },
        },
    };
    facts.push(fact);
    Ok(value)
}

fn interaction_brief(fact: &Fact, value: &InteractionRequest) -> InteractionBrief {
    InteractionBrief {
        reference: InteractionReadRef {
            entry: fact.entry,
            revision: fact.revision,
        },
        revision: value.revision,
        kind: value.kind(),
        status: value.status(),
        created_at: value.created_at,
        updated_at: value.updated_at,
    }
}

fn delta(
    old: &ExecutionSnapshot,
    next: &ExecutionSnapshot,
    old_index: Option<&InteractionIndexSource>,
    index: &InteractionIndexSource,
    terminal_facts: Vec<InteractionBrief>,
) -> (u64, ExecutionChange) {
    let previous = old_index
        .map(|value| value.entries.as_slice())
        .unwrap_or_default();
    let interactions = (old.value.interactions != next.value.interactions
        || !terminal_facts.is_empty())
    .then(|| InteractionDelta {
        base_index_revision: old.value.interactions.reference.revision,
        index: next.value.interactions.clone(),
        upserted: index
            .entries
            .iter()
            .filter(|next| !previous.contains(next))
            .cloned()
            .collect(),
        removed_entries: previous
            .iter()
            .filter(|old| {
                !index
                    .entries
                    .iter()
                    .any(|next| next.reference.entry == old.reference.entry)
            })
            .map(|old| old.reference.entry)
            .collect(),
        terminal_facts,
    });
    (
        old.stamp.revision,
        ExecutionChange {
            status: (old.value.status != next.value.status).then_some(next.value.status),
            turns: (old.value.active_turn != next.value.active_turn
                || old.value.recent_terminal_turn != next.value.recent_terminal_turn)
                .then(|| TurnsReplacement {
                    active_turn: next.value.active_turn.clone(),
                    recent_terminal_turn: next.value.recent_terminal_turn.clone(),
                }),
            interactions,
            activity: if old.value.activity == next.value.activity {
                ActivityReplacement::Unchanged
            } else {
                ActivityReplacement::Replace {
                    value: next.value.activity.clone(),
                }
            },
            storage: if old.value.storage == next.value.storage {
                StorageReplacement::Unchanged
            } else {
                StorageReplacement::Replace {
                    value: next.value.storage.clone(),
                }
            },
        },
    )
}

pub(super) fn corrupt() -> StudioError {
    StudioError::new(
        StudioErrorCode::Protocol,
        "Execution facts could not be captured consistently",
        false,
    )
}

impl ExecutionProjection {
    pub(in crate::studio::runtime) fn resolve_resident_interaction(
        &self,
        id: &str,
        revision: u64,
        origin: &ThreadFacetStamp,
    ) -> Result<Option<InteractionReadRef>, StudioError> {
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
        let Some(entry) = state.keys.get(&Key::Interaction(id.to_owned())).copied() else {
            return Ok(None);
        };
        let Some(locator) = state.locators.get(&(entry, revision)) else {
            return Ok(None);
        };
        // A known projection ref must already have been delivered at this origin. In particular,
        // reject an unsent/newer locator here rather than falling through to history registration.
        locator.ensure_resolvable_at(origin.revision)?;
        // A history-only locator is not a resident projection: resolve it through a fresh exact
        // receipt read. Its prior explicit grant remains separate from actual feed exposure.
        if locator.source == FactSource::Durable
            || (locator.material.upgrade().is_none() && locator.durable_from.is_none())
        {
            return Ok(None);
        }
        Ok(Some(InteractionReadRef { entry, revision }))
    }

    pub(in crate::studio::runtime) fn known_interaction(
        &self,
        id: &str,
        origin: &ThreadFacetStamp,
    ) -> Result<Option<InteractionIdentity>, StudioError> {
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
        let Some(entry) = state.keys.get(&Key::Interaction(id.to_owned())).copied() else {
            return Ok(None);
        };
        let mut known_unexposed = false;
        for (_, locator) in state.locators.range((entry, 0)..=(entry, u64::MAX)).rev() {
            if locator.interaction_readable_at(origin.revision) {
                return Ok(locator.interaction.clone());
            }
            known_unexposed |=
                locator.source == FactSource::Projection || locator.durable_from.is_some();
        }
        if known_unexposed {
            return Err(superseded());
        }
        Ok(None)
    }

    /// Exact historical resolution retains only a bounded locator, not a second body cache. Its
    /// open re-reads that exact original durable receipt; an evicted locator is Superseded.
    pub(in crate::studio::runtime) fn register_durable_interaction(
        &self,
        value: Arc<InteractionRequest>,
        origin: &ThreadFacetStamp,
    ) -> Result<InteractionReadRef, StudioError> {
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
        let key = Key::Interaction(value.interaction_id.clone());
        if let Some(entry) = state.keys.get(&key)
            && let Some(locator) = state.locators.get(&(*entry, value.revision))
        {
            // Recheck after the exact receipt IO: capture may have installed this version while
            // that read was in flight. A durable lookup cannot authorize an unsent projection.
            locator.ensure_resolvable_at(origin.revision)?;
        }
        let fact = register_source(
            &mut state,
            key,
            value.revision,
            Material::Interaction(value.clone()),
            FactSource::Durable,
        )?;
        if let Some(locator) = state.locators.get_mut(&(fact.entry, fact.revision)) {
            locator.durable_from.get_or_insert(origin.revision);
        }
        let key = (fact.entry, fact.revision);
        state.resolved.retain(|entry| *entry != key);
        state.resolved.push_back(key);
        while state.resolved.len() > 64 {
            if let Some(key) = state.resolved.pop_front()
                && let Some(locator) = state.locators.get_mut(&key)
            {
                locator.durable_from = None;
            }
        }
        prune(&mut state);
        Ok(InteractionReadRef {
            entry: fact.entry,
            revision: fact.revision,
        })
    }
}

fn prune(state: &mut State) {
    state.locators.retain(|_, locator| {
        locator.material.strong_count() != 0 || locator.durable_from.is_some()
    });
    let retained: std::collections::BTreeSet<_> =
        state.locators.keys().map(|(entry, _)| *entry).collect();
    state.keys.retain(|_, entry| retained.contains(entry));
}

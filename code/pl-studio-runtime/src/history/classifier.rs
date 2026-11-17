use super::types::milliseconds_from_seconds;
use super::*;
use pl_core::thread::current::RuntimeEpoch;
use std::collections::BTreeMap;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HistoryPlacement {
    Hidden,
    Work,
    Single,
}

/// A producer's actual boundary observation, including independently frozen bytes. A missing
/// observation for an unfinished member is an error; the classifier never derives it from a final.
#[derive(Debug, Clone)]
pub struct HistoryBoundaryObservation {
    pub event: HistoryEvent,
    pub entity: HistoryEntityHead,
}

#[derive(Debug, Clone)]
pub struct HistoryEntityChange {
    pub event: HistoryEvent,
    pub entity: HistoryEntityHead,
    pub placement: HistoryPlacement,
    pub boundary_observations: Vec<HistoryBoundaryObservation>,
    pub public_summary: Option<String>,
}

/// Native producer conversion uses the original timestamps and rejects overflow.
pub trait NativeHistoryEntity {
    fn from_atom(atom: &pl_protocol::ChatAtom, run: Option<String>) -> Result<HistoryEntityHead>;
}
impl NativeHistoryEntity for HistoryEntityHead {
    /// Native atomic timestamps use seconds; history heads use UTC milliseconds.
    /// Legacy absence stays unknown, and out-of-range timestamps are rejected.
    fn from_atom(atom: &pl_protocol::ChatAtom, run: Option<String>) -> Result<Self> {
        let state = match atom.lifecycle {
            pl_protocol::ChatAtomLifecycle::Active { status, .. } => {
                HistoryEntityState::KnownActive { status }
            }
            pl_protocol::ChatAtomLifecycle::Terminal { outcome, .. } => {
                HistoryEntityState::KnownTerminal { outcome }
            }
        };
        Ok(Self {
            entity_id: atom.id.clone(),
            run_id: run,
            attempt_id: atom.attempt_id.clone(),
            source: atom.source.clone(),
            kind: atom.kind,
            delivery: atom.delivery,
            state,
            started_at: atom.started_at.map(milliseconds_from_seconds).transpose()?,
            finished_at: atom
                .finished_at
                .map(milliseconds_from_seconds)
                .transpose()?,
            text_channel: atom.text_channel,
            tool: atom.tool.clone(),
            wait: atom
                .wait
                .clone()
                .map(|presentation| HistoryWaitHead::Inline { presentation }),
            content_present: atom.content_present,
            single_visibility: None,
            observation: HistoryObservation::Original,
            presentation_contract: None,
            detail_event_id: None,
            input_manifest_event_id: None,
            body_manifest_event_id: None,
        })
    }
}
impl HistoryEntityChange {
    pub fn from_atom(
        mut event: HistoryEvent,
        atom: &pl_protocol::ChatAtom,
        run: RuntimeEpoch,
    ) -> Result<Self> {
        event.header.turn_id = atom.turn_id.clone();
        let placement = if crate::studio::thread_projection::hidden(atom) {
            HistoryPlacement::Hidden
        } else if crate::studio::thread_projection::work(atom) {
            HistoryPlacement::Work
        } else {
            HistoryPlacement::Single
        };
        Ok(Self {
            event,
            entity: HistoryEntityHead::from_atom(atom, Some(run.to_string()))?,
            placement,
            boundary_observations: Vec::new(),
            public_summary: None,
        })
    }
}

#[derive(Clone)]
struct OpenGroup {
    head: HistoryWorkHead,
    active: BTreeMap<String, HistoryEntityHead>,
}

/// Only the current run's open group and unfinished member headers are retained. Finished member
/// existence is an indexed owner lookup, not an ever-growing in-memory history ledger.
#[derive(Clone)]
pub struct HistoryClassifier {
    run: RuntimeEpoch,
    open: Option<OpenGroup>,
}
impl HistoryClassifier {
    pub fn new(run: RuntimeEpoch) -> Self {
        Self { run, open: None }
    }
    pub fn from_run_id(run: &str) -> Result<Self> {
        Ok(Self::new(run.parse().map_err(|error| {
            HistoryError::Storage(anyhow::Error::new(error))
        })?))
    }
    pub fn run_matches(&self, run: &str) -> bool {
        self.run.to_string() == run
    }
    pub fn open_group(&self) -> Option<&str> {
        self.open.as_ref().map(|group| group.head.group_id.as_str())
    }

    /// The bounded unfinished members whose original observations a visible boundary needs.
    pub(crate) fn boundary_entities(&self) -> impl Iterator<Item = &str> {
        self.open
            .iter()
            .flat_map(|group| group.active.keys().map(String::as_str))
    }

    /// Prepares on a local candidate; a failed acceptance leaves this classifier unchanged.
    /// Call once per semantic fact; retry accepted storage batches with their original event IDs.
    pub async fn record(
        &mut self,
        store: &HistoryStore,
        change: &HistoryEntityChange,
    ) -> Result<Vec<u64>> {
        let mut change = change.clone();
        if change.entity.run_id.as_deref() != Some(&self.run.to_string()) {
            return Err(HistoryError::InvalidEvent(
                "entity belongs to another runtime epoch".into(),
            ));
        }
        let single_exists = change.placement == HistoryPlacement::Single
            && store
                .anchor_exists(&format!("single:{}", change.entity.entity_id))
                .await?;
        let visible_boundary = change.placement == HistoryPlacement::Single
            && !single_exists
            && change.entity.content_present != Some(false);
        if !visible_boundary && !change.boundary_observations.is_empty() {
            return Err(HistoryError::InvalidEvent(
                "boundary observations require a newly visible Single".into(),
            ));
        }
        fit_wait(&mut change.event, &mut change.entity, store.database_id())?;
        for observation in &mut change.boundary_observations {
            fit_wait(
                &mut observation.event,
                &mut observation.entity,
                store.database_id(),
            )?;
        }
        let mut candidate = self.clone();
        let mut events = Vec::new();
        let mut event = change.event;
        set_entity(&mut event, &change.entity);
        match change.placement {
            HistoryPlacement::Hidden => {
                canonical_metadata(&mut event, &change.entity)?;
                events.push(event);
            }
            HistoryPlacement::Single => {
                let row = format!("single:{}", change.entity.entity_id);
                let exists = single_exists;
                if !exists && change.entity.content_present == Some(false) {
                    canonical_metadata(&mut event, &change.entity)?;
                    events.push(event);
                } else {
                    if !exists {
                        candidate.close_boundary(
                            &mut events,
                            change.boundary_observations,
                            event.header.occurred_at,
                            event.header.recorded_at,
                            change.public_summary,
                        )?;
                    }
                    if exists && change.entity.content_present == Some(false) {
                        change.entity.single_visibility =
                            Some(HistorySingleVisibility::FinalEmptyAfterContent);
                    } else if change.entity.single_visibility.is_none() {
                        change.entity.single_visibility = Some(HistorySingleVisibility::Content);
                    }
                    event.header.row_key = Some(row);
                    event.is_anchor = !exists;
                    event.head = Some(HistoryRowHead::Single(change.entity));
                    events.push(event);
                }
            }
            HistoryPlacement::Work => {
                if candidate.open.is_none() {
                    // The first member event is a stable semantic identity. Deriving the group from
                    // it keeps a crash-after-commit retry on the same append-only group instead of
                    // allocating a second group for the same frozen effect.
                    let group_id = format!("{}:{}", self.run, event.header.event_id);
                    let head = HistoryWorkHead {
                        group_id: group_id.clone(),
                        run_id: Some(self.run.to_string()),
                        started_at: event.header.occurred_at,
                        boundary_at: None,
                        closed: false,
                        member_count: 0,
                        unfinished_count: 0,
                        execution_present: false,
                        summary: None,
                    };
                    events.push(group_event(
                        format!("group_opened:{group_id}"),
                        HistoryEventKind::GroupOpened,
                        &head,
                        true,
                        event.header.recorded_at,
                    ));
                    candidate.open = Some(OpenGroup {
                        head,
                        active: BTreeMap::new(),
                    });
                }
                let group = candidate.open.as_mut().expect("open group installed");
                let row = format!("member:{}:{}", group.head.group_id, change.entity.entity_id);
                let exists = store.anchor_exists(&row).await?;
                if !exists {
                    group.head.member_count =
                        group.head.member_count.checked_add(1).ok_or_else(|| {
                            HistoryError::InvalidEvent("member count overflow".into())
                        })?;
                }
                if matches!(change.entity.state, HistoryEntityState::KnownActive { .. }) {
                    group
                        .active
                        .insert(change.entity.entity_id.clone(), change.entity.clone());
                } else {
                    group.active.remove(&change.entity.entity_id);
                }
                group.head.unfinished_count = group.active.len() as u64;
                group.head.execution_present |= matches!(
                    change.entity.kind,
                    HistoryEntityKind::ToolCall
                        | HistoryEntityKind::Reasoning
                        | HistoryEntityKind::Inference
                );
                if let Some(summary) = change.public_summary {
                    group.head.summary = Some(summary);
                }
                event.header.group_id = Some(group.head.group_id.clone());
                event.header.row_key = Some(row);
                event.is_anchor = !exists;
                event.head = Some(HistoryRowHead::Member(change.entity));
                let change_id = event.header.event_id.clone();
                let recorded_at = event.header.recorded_at;
                events.push(event);
                events.push(group_event(
                    format!("group_head_changed:{change_id}"),
                    HistoryEventKind::GroupHeadChanged,
                    &group.head,
                    false,
                    recorded_at,
                ));
            }
        }
        let sequences = store.accept_batch(&events).await?;
        *self = candidate;
        Ok(sequences)
    }
    fn close_boundary(
        &mut self,
        events: &mut Vec<HistoryEvent>,
        observations: Vec<HistoryBoundaryObservation>,
        occurred_at: Option<i64>,
        recorded_at: i64,
        summary: Option<String>,
    ) -> Result<()> {
        let Some(mut group) = self.open.take() else {
            if !observations.is_empty() {
                return Err(HistoryError::InvalidEvent(
                    "boundary observations have no open group".into(),
                ));
            }
            return Ok(());
        };
        let mut observed = BTreeMap::new();
        for observation in observations {
            let id = observation.entity.entity_id.clone();
            if observed.insert(id, observation).is_some() {
                return Err(HistoryError::InvalidEvent(
                    "duplicate boundary member".into(),
                ));
            }
        }
        if observed.len() != group.active.len()
            || observed.keys().any(|id| !group.active.contains_key(id))
        {
            return Err(HistoryError::InvalidEvent(
                "every unfinished member requires its own boundary observation".into(),
            ));
        }
        for (id, mut observation) in observed {
            let old = &group.active[&id];
            if observation.entity.run_id != old.run_id
                || observation.entity.attempt_id != old.attempt_id
                || observation.entity.source != old.source
                || !matches!(
                    observation.entity.state,
                    HistoryEntityState::KnownActive { .. }
                )
            {
                return Err(HistoryError::InvalidEvent(
                    "boundary identity or observed state differs".into(),
                ));
            }
            observation.entity.observation = HistoryObservation::Boundary {
                captured_at: occurred_at,
            };
            let event = &mut observation.event;
            event.header.kind = HistoryEventKind::BoundaryObserved;
            event.header.original = None;
            event.header.group_id = Some(group.head.group_id.clone());
            event.header.row_key = Some(format!("member:{}:{id}", group.head.group_id));
            set_entity(event, &observation.entity);
            event.head = Some(HistoryRowHead::Member(observation.entity));
            event.is_anchor = false;
            events.push(observation.event);
        }
        group.head.closed = true;
        group.head.boundary_at = occurred_at;
        if let Some(summary) = summary {
            group.head.summary = Some(summary);
        }
        events.push(group_event(
            format!("group_closed:{}", group.head.group_id),
            HistoryEventKind::GroupClosed,
            &group.head,
            false,
            recorded_at,
        ));
        Ok(())
    }
}

fn set_entity(event: &mut HistoryEvent, head: &HistoryEntityHead) {
    event.header.run_id = head.run_id.clone();
    event.header.attempt_id = head.attempt_id.clone();
    event.header.entity_id = Some(head.entity_id.clone());
    event.header.source = Some(head.source.clone());
    event.header.call_id = head.tool.as_ref().map(|tool| tool.call_id.clone());
}
fn group_event(
    id: String,
    kind: HistoryEventKind,
    head: &HistoryWorkHead,
    anchor: bool,
    at: i64,
) -> HistoryEvent {
    let mut event = HistoryEvent::new(id, kind, at);
    event.header.run_id = head.run_id.clone();
    event.header.group_id = Some(head.group_id.clone());
    event.header.row_key = Some(format!("work:{}", head.group_id));
    event.header.occurred_at = if head.closed {
        head.boundary_at
    } else {
        head.started_at
    };
    event.head = Some(HistoryRowHead::Work(head.clone()));
    event.is_anchor = anchor;
    event
}
pub(crate) fn prepare_entity_content(
    event: &mut HistoryEvent,
    entity: &mut HistoryEntityHead,
    database_id: &str,
) -> Result<()> {
    fit_wait(event, entity, database_id)?;
    canonical_metadata(event, entity)
}

fn canonical_metadata(event: &mut HistoryEvent, entity: &HistoryEntityHead) -> Result<()> {
    if event.header.original.is_some()
        && !event
            .bodies
            .iter()
            .any(|body| body.role == HistoryBodyRole::CanonicalMetadata)
    {
        event.bodies.push(HistoryBody::new(
            "canonical_metadata",
            HistoryBodyRole::CanonicalMetadata,
            serde_json::to_vec(entity)?,
        ));
    }
    Ok(())
}
fn fit_wait(
    event: &mut HistoryEvent,
    entity: &mut HistoryEntityHead,
    database: &str,
) -> Result<()> {
    if serde_json::to_vec(entity)?.len() + 64 <= HEAD_MAX_BYTES {
        return Ok(());
    }
    let wait = entity.wait.take();
    if let Some(HistoryWaitHead::Inline { presentation }) = wait {
        let intent = match presentation.intent() {
            pl_protocol::ThreadWaitIntent::Events {
                targets,
                timeout_ms,
            } => HistoryWaitIntentHead::Events {
                target_count: targets.len() as u64,
                timeout_ms: *timeout_ms,
            },
            pl_protocol::ThreadWaitIntent::Timer { duration_ms } => HistoryWaitIntentHead::Timer {
                duration_ms: *duration_ms,
            },
        };
        let body = HistoryBody::new(
            "wait_presentation",
            HistoryBodyRole::WaitPresentation,
            serde_json::to_vec(&presentation)?,
        );
        let reference = HistoryEventBodyRef {
            database_id: database.into(),
            owner_event_id: event.header.event_id.clone(),
            body_key: body.body_key.clone(),
            body_id: body.body_id.clone(),
            byte_start: 0,
            byte_length: body.bytes.len() as u64,
        };
        entity.wait = Some(HistoryWaitHead::Deferred {
            intent,
            state: presentation.state(),
            messages_ready: presentation.messages_ready(),
            presentation: reference,
        });
        event.bodies.push(body);
    } else {
        entity.wait = wait;
    }
    Ok(())
}

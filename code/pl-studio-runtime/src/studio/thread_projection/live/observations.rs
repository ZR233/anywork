//! Immutable producer cuts retained before a terminal can retire its live body.
use super::*;
use crate::history::NativeHistoryEntity;
use anyhow::{Context, Result, ensure};
use pl_core::chat::{ChatContent, ChatContentKey, ContentData, ContentDescriptor};
use pl_protocol::{ChatAtom, ChatAtomLifecycle, ContentTarget};

#[derive(Debug, Clone)]
pub(in crate::studio) struct Observation {
    atom: ChatAtom,
    thread_id: String,
    shape: Option<ExecutionShape>,
    bodies: BTreeMap<String, Arc<ContentBlock>>,
}

impl Observation {
    pub(in crate::studio) fn freeze(
        &self,
        boundary: &HistoryEvent,
        database_id: &str,
    ) -> Result<crate::history::HistoryBoundaryObservation> {
        let atom = &self.atom;
        ensure!(
            matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }),
            "boundary input is not active"
        );
        let shape = self
            .shape
            .as_ref()
            .context("boundary member has no retained producer cut")?;
        let mut contents = Vec::with_capacity(atom.contents.len());
        for body in &atom.contents {
            let ContentTarget::Body { owner, key } = &body.reference.target else {
                anyhow::bail!("boundary content is not a producer body");
            };
            let block = self
                .bodies
                .get(key)
                .context("boundary member has no retained producer body")?;
            let content = Arc::new(ChatContent {
                descriptor: ContentDescriptor {
                    key: ChatContentKey {
                        owner: crate::studio::conversation_identity::content_owner_key(owner)?,
                        key: key.clone(),
                    },
                    byte_length: block.len() as u64,
                    generation: 1,
                    media_type: Some("text/plain; charset=utf-8".into()),
                },
                data: ContentData::text(block.clone()),
            });
            contents.push(content);
        }
        let mut event = HistoryEvent::new(
            format!("boundary:{}:{}", boundary.header.event_id, atom.id),
            HistoryEventKind::BoundaryObserved,
            boundary.header.recorded_at,
        );
        event.header.run_id = boundary.header.run_id.clone();
        event.header.entity_id = Some(atom.id.clone());
        event.header.turn_id = atom.turn_id.clone();
        event.header.attempt_id = atom.attempt_id.clone();
        event.header.source = Some(atom.source.clone());
        event.header.call_id = atom.tool.as_ref().map(|tool| tool.call_id.clone());
        event.header.occurred_at = boundary.header.occurred_at;
        let mut entity =
            crate::history::HistoryEntityHead::from_atom(atom, boundary.header.run_id.clone())?;
        entity.observation = crate::history::HistoryObservation::Boundary {
            captured_at: boundary.header.occurred_at,
        };
        crate::studio::runtime::chat_item::freeze_history_observation(
            &mut event,
            &mut entity,
            shape,
            atom,
            &self.thread_id,
            contents,
            database_id,
        )?;
        Ok(crate::history::HistoryBoundaryObservation { event, entity })
    }
    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        self.bodies.iter().fold(
            serde_json::to_vec(&self.atom)
                .map_or(u64::MAX, |bytes| bytes.len() as u64)
                .saturating_add(self.shape.as_ref().map_or(0, state_body_bytes))
                .saturating_add(self.thread_id.len() as u64)
                .saturating_add(RETAINED_ITEM_OVERHEAD),
            |bytes, (key, body)| {
                bytes
                    .saturating_add(key.len() as u64)
                    .saturating_add(RETAINED_ENTRY_OVERHEAD)
                    .saturating_add(body.len() as u64)
            },
        )
    }
}

#[derive(Debug, Default)]
struct ProducerCut {
    shape: Option<ExecutionShape>,
    fields: BTreeMap<BodyKey, Arc<ContentBlock>>,
}

fn producer_cuts(state: &ThreadSnapshot) -> BTreeMap<String, ProducerCut> {
    let mut cuts = BTreeMap::<String, ProducerCut>::new();
    if let Some(active) = state.model_progress.as_ref() {
        let progress = &active.progress;
        for failed in &progress.observation().failed {
            capture_model_parts(
                &mut cuts,
                &active.attempt_id,
                failed.generation,
                &failed.parts,
                false,
            );
        }
        capture_model_parts(
            &mut cuts,
            &active.attempt_id,
            progress.observation().generation,
            progress.parts(),
            true,
        );
    }
    for (task_id, progress) in &state.tool_progress {
        let task = state.tasks.get(task_id).or_else(|| {
            state
                .terminal_tasks
                .iter()
                .find(|task| task.id == task_id.as_str())
        });
        let Some(task) = task else {
            continue;
        };
        if progress.bytes() == 0 {
            continue;
        }
        cuts.entry(super::super::order::tool_id(&task.call_id))
            .or_default()
            .fields
            .insert(BodyKey::host(TOOL_RESULT_FIELD), progress.content());
    }
    cuts
}

fn capture_model_parts(
    cuts: &mut BTreeMap<String, ProducerCut>,
    attempt_id: &str,
    generation: u32,
    parts: &pl_core::model::ModelParts,
    include_shape: bool,
) {
    for part in parts.iter() {
        let Some((id, field, shape)) = super::observation_start(
            attempt_id,
            generation,
            part.identity(),
            &ThreadContentLifecycle::streaming(),
        ) else {
            continue;
        };
        let cut = cuts.entry(id).or_default();
        if include_shape {
            cut.shape.get_or_insert(shape);
        }
        cut.fields.insert(field, part.content().clone());
    }
}

impl LiveProjection {
    fn observation_input(
        &self,
        thread_id: &str,
        cuts: &BTreeMap<String, ProducerCut>,
        atom: &ChatAtom,
    ) -> Result<Observation> {
        let item = self.items.get(&atom.id).filter(|item| !item.is_terminal());
        let cut = cuts.get(&atom.id);
        let shape = item
            .map(|item| static_state(item.state()))
            .or_else(|| cut.and_then(|cut| cut.shape.as_ref()).map(static_state))
            .context("boundary member has no resident shape or exact producer cut")?;
        let mut bodies = item
            .map(|item| {
                crate::studio::runtime::chat_item::content_fields(item.state())
                    .map_err(|error| ProjectionError::History(error.to_string()))
            })
            .transpose()?
            .unwrap_or_default();
        if let Some(cut) = cut {
            bodies.extend(cut.fields.clone());
        }
        for body in &atom.contents {
            let ContentTarget::Body { key, .. } = &body.reference.target else {
                continue;
            };
            if !bodies.keys().any(|field| field.as_key() == key.as_str()) {
                anyhow::bail!("boundary member has no exact producer body for {key}");
            }
        }
        Ok(Observation {
            atom: atom.clone(),
            thread_id: thread_id.into(),
            shape: Some(shape),
            bodies: bodies.into_iter().map(|(key, block)| (key.as_key().to_owned(), block)).collect(),
        })
    }
    pub(super) fn observation_inputs(
        &self,
        thread_id: &str,
        state: &ThreadSnapshot,
    ) -> Result<BTreeMap<String, Observation>> {
        let cuts = producer_cuts(state);
        self.atom_starts
            .values()
            .map(|atom| {
                Ok((
                    atom.id.clone(),
                    self.observation_input(thread_id, &cuts, atom)?,
                ))
            })
            .collect()
    }
    pub(super) fn retain_boundary_inputs(
        &self,
        thread_id: &str,
        state: &ThreadSnapshot,
        mut before: BTreeMap<String, Observation>,
    ) -> Result<Arc<BTreeMap<String, Observation>>> {
        // Existing producers keep the cut captured before the effect changed this projection. Only
        // identities first started by the effect are added now; a terminal canonical result can
        // never replace an older member's boundary bytes.
        for (id, input) in self.observation_inputs(thread_id, state)? {
            before.entry(id).or_insert(input);
        }
        Ok(Arc::new(before))
    }
}

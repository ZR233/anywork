//! Immutable producer cuts retained before a terminal can retire its live body.
use super::*;
use crate::history::NativeHistoryEntity;
use anyhow::{Context, Result, ensure};
use pl_core::chat::{ChatContent, ChatContentKey, ContentData, ContentDescriptor};
use pl_protocol::{ChatAtom, ChatAtomLifecycle, ContentTarget};

#[derive(Debug, Clone)]
enum CapturedBody {
    Current(Arc<super::super::current::CurrentContent>),
    Preview(Arc<ContentBlock>),
}

#[derive(Debug, Clone)]
pub(in crate::studio) struct Observation {
    atom: ChatAtom,
    thread_id: String,
    shape: Option<ExecutionShape>,
    bodies: BTreeMap<String, CapturedBody>,
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
            let content = match self
                .bodies
                .get(key)
                .context("boundary member has no retained body cut")?
            {
                CapturedBody::Current(content) => content.content(),
                CapturedBody::Preview(block) => Arc::new(ChatContent {
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
                }),
            };
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
                    .saturating_add(match body {
                        CapturedBody::Current(value) => value.descriptor.byte_length,
                        CapturedBody::Preview(value) => value.len() as u64,
                    })
            },
        )
    }
}
impl LiveProjection {
    fn observation_input(&self, thread_id: &str, atom: &ChatAtom) -> Result<Observation> {
        let preview = self.previews.get(&atom.id);
        let shape = self
            .items
            .get(&atom.id)
            .filter(|item| !item.is_terminal())
            .map(|item| static_state(item.state()))
            .or_else(|| preview.map(|preview| preview.shape.clone()));
        let current = self.current.snapshot();
        let mut bodies = BTreeMap::new();
        for body in &atom.contents {
            let ContentTarget::Body { owner, key } = &body.reference.target else {
                continue;
            };
            let block = preview.and_then(|preview| {
                preview
                    .fields
                    .iter()
                    .find(|(field, _)| field.as_key() == *key)
                    .map(|(_, block)| block.clone())
            });
            if let Some(block) = block {
                bodies.insert(key.clone(), CapturedBody::Preview(block));
            } else if let Some(current) = &current {
                let owner = crate::studio::conversation_identity::content_owner_key(owner)?;
                if let Some(content) = current.contents().get(&ChatContentKey {
                    owner,
                    key: key.clone(),
                }) {
                    bodies.insert(key.clone(), CapturedBody::Current(content.clone()));
                }
            }
        }
        Ok(Observation {
            atom: atom.clone(),
            thread_id: thread_id.into(),
            shape,
            bodies,
        })
    }
    pub(super) fn observation_inputs(
        &self,
        thread_id: &str,
    ) -> Result<BTreeMap<String, Observation>> {
        self.atom_starts
            .values()
            .map(|atom| Ok((atom.id.clone(), self.observation_input(thread_id, atom)?)))
            .collect()
    }
    pub(super) fn retain_boundary_inputs(
        &self,
        thread_id: &str,
        mut before: BTreeMap<String, Observation>,
    ) -> Result<Arc<BTreeMap<String, Observation>>> {
        // Active post-effect producers own the newer cut. A retired producer retains its exact
        // pre-terminal cut; the later canonical result can never replace an old group's bytes.
        before.extend(self.observation_inputs(thread_id)?);
        Ok(Arc::new(before))
    }
}

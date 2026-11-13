//! Effect-owned immutable inputs, borrowed before a terminal can retire its live owner.
use super::*;
use anyhow::{Context, Result, ensure};
use pl_core::chat::{ChatContent, ChatContentKey, ContentData, ContentDescriptor};
use pl_protocol::{ChatAtom, ChatAtomLifecycle, ContentTarget};

#[derive(Debug, Clone)]
enum CapturedBody {
    Current(Arc<super::super::current::CurrentContent>),
    Preview(Arc<ContentBlock>),
}

#[derive(Debug, Clone)]
pub(super) struct Observation {
    atom: ChatAtom,
    thread_id: String,
    shape: Option<ThreadItemState>,
    bodies: BTreeMap<String, CapturedBody>,
}

type RetainedDisplayObservations = (
    Arc<BTreeMap<String, Observation>>,
    Arc<super::super::presentation::ObservationPlan>,
);

impl Observation {
    pub(super) fn freeze(&self) -> Result<super::super::presentation::ObservationInput> {
        let mut atom = self.atom.clone();
        ensure!(
            matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }),
            "boundary input is not the admitted active observation"
        );
        let shape = self
            .shape
            .as_ref()
            .context("boundary member has no retained public payload cut")?;
        let mut contents = Vec::with_capacity(atom.contents.len());
        for body in &atom.contents {
            let ContentTarget::Body { owner, key } = &body.reference.target else {
                anyhow::bail!("boundary content is not an owned Body");
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
                        // The derived display owner is a new immutable content identity.
                        generation: 1,
                        media_type: Some("text/plain; charset=utf-8".into()),
                    },
                    data: ContentData::text(block.clone()),
                }),
            };
            contents.push(content);
        }
        atom.payload = None;
        Ok(super::super::presentation::ObservationInput {
            atom,
            state: shape.clone(),
            thread_id: self.thread_id.clone(),
            contents,
        })
    }

    pub(super) fn retained_bytes(&self) -> u64 {
        self.bodies.iter().fold(
            serde_json::to_vec(&self.atom)
                .map_or(u64::MAX, |bytes| bytes.len() as u64)
                .saturating_add(self.shape.as_ref().map_or(0, state_body_bytes))
                .saturating_add(self.thread_id.len() as u64)
                .saturating_add(RETAINED_ITEM_OVERHEAD),
            |bytes, (key, content)| {
                bytes
                    .saturating_add(key.len() as u64)
                    .saturating_add(RETAINED_ENTRY_OVERHEAD)
                    .saturating_add(match content {
                        CapturedBody::Current(content) => content.descriptor.byte_length,
                        CapturedBody::Preview(block) => block.len() as u64,
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
            let from_preview = preview.and_then(|preview| {
                preview
                    .fields
                    .iter()
                    .find(|(field, _)| field.as_key() == *key)
                    .map(|(_, block)| block.clone())
            });
            if let Some(block) = from_preview {
                bodies.insert(key.clone(), CapturedBody::Preview(block));
            } else if let Some(content) = current.as_ref().and_then(|current| {
                let owner = crate::studio::conversation_identity::content_owner_key(owner).ok()?;
                current
                    .contents()
                    .get(&ChatContentKey {
                        owner,
                        key: key.clone(),
                    })
                    .cloned()
            }) {
                // This Arc is captured now, not resolved from current state at publication.
                bodies.insert(key.clone(), CapturedBody::Current(content));
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
            .map(|atom| {
                Ok((
                    super::super::presentation::member_key(atom)?,
                    self.observation_input(thread_id, atom)?,
                ))
            })
            .collect()
    }

    pub(super) fn retain_display_observations(
        &self,
        thread_id: &str,
        effect: u64,
        facts: &[ChatAtom],
        visible: &[super::super::presentation::TextVisible],
        mut before: BTreeMap<String, Observation>,
    ) -> Result<RetainedDisplayObservations> {
        let presentation = self
            .presentation
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let facts = facts.iter().filter(|atom| {
            !matches!(atom.lifecycle, ChatAtomLifecycle::Active { started: Some(at), .. } if at.effect_seq != effect)
                || presentation.accepts_update(atom)
        }).cloned().collect::<Vec<_>>();
        let mut retained = BTreeMap::new();
        let plan = presentation.observation_requests(effect, &facts, visible)?;
        for (key, (_, member)) in &plan {
            let observed = if let Some(atom) = self.atom_starts.get(&member.head.record.atom.id) {
                ensure!(
                    atom.source == member.head.record.atom.source,
                    "boundary input source changed"
                );
                self.observation_input(thread_id, atom)?
            } else {
                before
                    .remove(key)
                    .context("boundary has no retained pre-terminal owner cut")?
            };
            retained.insert(key.clone(), observed);
        }
        Ok((Arc::new(retained), Arc::new(plan)))
    }
}

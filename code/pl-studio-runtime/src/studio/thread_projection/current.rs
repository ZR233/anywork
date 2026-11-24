//! Effect-local product current and its read owners. No completed-history mirror lives here.

use crate::studio::{
    content_owner_key,
    runtime::chat_item::{BodyKey, TOOL_ARGUMENTS_FIELD, TOOL_RESULT_FIELD},
};
use crate::*;
use anyhow::{Result, ensure};
use pl_core::{
    chat::{ChatContent, ChatContentKey, ContentData, ContentDescriptor},
    model::ContentBlock,
    thread::ThreadSnapshot,
};
use std::{
    collections::BTreeMap,
    sync::{Arc, OnceLock},
};

const PREVIEW_BYTES: usize = 512;
const PREVIEW_COUNT: usize = 4;
#[derive(Clone, Copy, PartialEq, Eq)]
pub(in crate::studio) struct ModelPartLocation {
    pub generation: u32,
    pub index: usize,
}

pub(super) type ActiveText = (
    String,
    BodyKey,
    Arc<ContentBlock>,
    Option<ThreadTextChannel>,
    Option<ModelPartLocation>,
);

#[derive(Debug, Clone)]
pub(in crate::studio) struct CurrentEntryWrite {
    pub collection: String,
    pub position: i64,
    pub entry_id: String,
    pub payload: Arc<[u8]>,
}

#[derive(Debug)]
pub(in crate::studio) struct CurrentContent {
    pub descriptor: ContentDescriptor,
    pub reference: CurrentContentRef,
    block: Arc<ContentBlock>,
    indexed: OnceLock<Arc<ChatContent>>,
}
impl CurrentContent {
    pub fn content(&self) -> Arc<ChatContent> {
        self.indexed
            .get_or_init(|| {
                Arc::new(ChatContent {
                    descriptor: self.descriptor.clone(),
                    data: ContentData::text(self.block.clone()),
                })
            })
            .clone()
    }
}

pub(in crate::studio) type CurrentPositionIndex =
    BTreeMap<(String, i64, String), Arc<CurrentEntryWrite>>;

#[derive(Debug)]
pub(in crate::studio) struct FrozenCurrentProjection {
    projection: CurrentProjection,
    json_bytes: OnceLock<u64>,
}

impl FrozenCurrentProjection {
    pub fn new(projection: CurrentProjection) -> Arc<Self> {
        Arc::new(Self {
            projection,
            json_bytes: OnceLock::new(),
        })
    }

    pub fn projection(&self) -> &CurrentProjection {
        &self.projection
    }

    /// Exact compact JSON length, without any retained-memory accounting fees.
    /// A failed measurement cannot fit any bounded publication frame.
    pub fn json_bytes(&self) -> u64 {
        *self.json_bytes.get_or_init(|| {
            serde_json::to_vec(&self.projection).map_or(u64::MAX, |bytes| {
                u64::try_from(bytes.len()).unwrap_or(u64::MAX)
            })
        })
    }

    /// Every holder still pays the original complete JSON charge. Sharing only
    /// avoids re-encoding; it does not discount another owner's responsibility.
    pub fn retained_bytes(&self) -> u64 {
        self.json_bytes()
            .saturating_add(std::mem::size_of::<OnceLock<u64>>() as u64)
            // Conservatively reserve a strong handle and both allocation counters.
            .saturating_add(3 * std::mem::size_of::<usize>() as u64)
    }
}

#[derive(Debug)]
pub(in crate::studio) struct CurrentState {
    projection: Arc<FrozenCurrentProjection>,
    revision: u64,
    owner_id: String,
    contents: Arc<BTreeMap<ChatContentKey, Arc<CurrentContent>>>,
    references: Arc<BTreeMap<CurrentContentRef, Arc<CurrentContent>>>,
    entries: Arc<BTreeMap<(String, String), Arc<CurrentEntryWrite>>>,
    by_position: Arc<CurrentPositionIndex>,
    active_turn: Option<Turn>,
    business_bytes: u64,
    metadata_bytes: OnceLock<u64>,
}

#[derive(Default)]
pub(super) struct CurrentOwner {
    owner_id: Option<String>,
    activity: super::activity::ActivityProjection,
    state: Option<Arc<CurrentState>>,
    plan_extension_revision: Option<u64>,
    interaction_revision: Option<u64>,
    next_position: i64,
    sources: Arc<[ChatSourceState]>,
    atoms: Vec<ChatAtom>,
    resource_versions: BTreeMap<&'static str, u64>,
    cold_revision: Option<u64>,
}
impl CurrentOwner {
    pub(super) fn provenance(&mut self, sources: Vec<ChatSourceState>, atoms: Vec<ChatAtom>) {
        self.sources = sources.into();
        self.atoms = atoms;
    }
    pub(super) fn activity(&self) -> Option<ThreadActivity> {
        self.activity.current().cloned()
    }
    pub(super) fn retained_bytes(&self) -> u64 {
        self.activity
            .retained_bytes()
            .saturating_add(std::mem::size_of::<Self>() as u64)
            .saturating_add(
                self.state
                    .as_ref()
                    .map_or(0, |state| state.metadata_bytes()),
            )
    }
    pub(super) fn owner_id(&self) -> Option<&str> {
        self.owner_id.as_deref()
    }
    pub(super) fn bind(&mut self, owner_id: String) -> Result<()> {
        ensure!(!owner_id.is_empty(), "empty conversation database identity");
        ensure!(
            self.owner_id.as_ref().is_none_or(|old| old == &owner_id),
            "conversation database identity changed within owner"
        );
        self.owner_id = Some(owner_id);
        Ok(())
    }
    pub(super) fn snapshot(&self) -> Option<Arc<CurrentState>> {
        self.state.clone()
    }

    pub(super) fn observe(
        &mut self,
        thread: &Thread,
        state: &ThreadSnapshot,
        sequence: u64,
        active: impl IntoIterator<Item = ActiveText>,
    ) -> Result<Arc<CurrentState>> {
        self.project(thread, state, sequence, active)
    }

    fn project(
        &mut self,
        thread: &Thread,
        state: &ThreadSnapshot,
        sequence: u64,
        active: impl IntoIterator<Item = ActiveText>,
    ) -> Result<Arc<CurrentState>> {
        let owner_id = self
            .owner_id
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("current owner has no identity"))?
            .clone();
        let active = active.into_iter().collect::<Vec<_>>();
        let activity = self.activity.observe_admitted(
            &thread.id,
            state,
            &self.atoms,
            &active,
            crate::studio::ids::unix_seconds(),
        );
        let mut projection = CurrentProjection::empty(super::status(state));
        projection.sources = self
            .sources
            .iter()
            .filter(|source| {
                matches!(source.lifecycle, ChatSourceLifecycle::Active)
                    || source.ended.is_none_or(|at| at.effect_seq == sequence)
            })
            .cloned()
            .collect();
        projection.execution_present = true;
        projection.active = activity.as_ref().map(|activity| CurrentActivityHead {
            id: activity.identity.clone(),
            kind: activity.kind,
            summary: activity.summary.clone(),
            thinking_summary: activity.thinking_summary.clone(),
            thinking_seconds: activity.thinking_seconds,
            tool_count: activity.tools.count,
            background_tool_count: activity.tools.background,
            latest_tool: activity
                .tools
                .latest_started
                .as_ref()
                .map(|tool| CurrentToolHead {
                    call_id: tool.call_id.clone(),
                    name: tool.name.clone(),
                    state: tool.state,
                }),
        });
        // Idle compaction has an admitted operation but no Turn or model-execution snapshot.
        // Its original current atom is the activity fact; do not borrow a previous Turn.
        if let Some(atom) = self.atoms.iter().find(|atom| {
            atom.kind == ChatAtomKind::Compaction
                && matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. })
        }) {
            projection.active = Some(CurrentActivityHead {
                id: atom.id.clone(),
                kind: ThreadActivityKind::Compacting,
                summary: String::new(),
                thinking_summary: None,
                thinking_seconds: None,
                tool_count: 0,
                background_tool_count: 0,
                latest_tool: None,
            });
        }
        let active_turn = super::project_active_turn(&thread.id, state, thread.updated_at)?;
        projection.active_turn = active_turn
            .as_ref()
            .and_then(|turn| turn.phase().map(|phase| (turn, phase)))
            .map(|(turn, phase)| -> Result<_> {
                Ok(CurrentTurnHead {
                    id: turn.id.clone(),
                    phase,
                })
            })
            .transpose()?;
        let mut contents = BTreeMap::new();
        let mut entries = BTreeMap::new();
        let mut next_position = self.next_position;
        for (id, position, block, text_channel, _model_part) in active {
            let key = position.as_key();
            let owner = ContentOwner::Item {
                item_id: id.clone(),
            };
            let content_key = ChatContentKey {
                owner: content_owner_key(&owner)?,
                key: key.clone(),
            };
            let content = self.text(content_key, block, true)?;
            let reference = content.reference.clone();
            if projection.previews.len() < PREVIEW_COUNT {
                let role = match position {
                    BodyKey::Part(
                        pl_core::chat::PresentationPart::ReasoningText(_)
                        | pl_core::chat::PresentationPart::SummaryText(_),
                    ) => CurrentContentRole::Reasoning,
                    BodyKey::Host(ref key) if key == TOOL_ARGUMENTS_FIELD => {
                        CurrentContentRole::ToolArguments
                    }
                    BodyKey::Host(ref key)
                        if key == TOOL_RESULT_FIELD
                            || key.starts_with(&format!("{TOOL_RESULT_FIELD}:")) =>
                    {
                        CurrentContentRole::ToolOutput
                    }
                    _ => CurrentContentRole::Response,
                };
                let cached = self.state.as_ref().and_then(|state| {
                    state
                        .contents
                        .get(&content.descriptor.key)
                        .filter(|old| {
                            old.descriptor.generation == content.descriptor.generation
                                && old.block.len() >= PREVIEW_BYTES
                                && content.block.len() >= PREVIEW_BYTES
                        })
                        .and_then(|_| {
                            state
                                .projection()
                                .previews
                                .iter()
                                .find(|preview| preview.reference == reference)
                                .map(|preview| preview.text.clone())
                        })
                });
                let text = match cached {
                    Some(text) => text,
                    None => content
                        .block
                        .range(0, PREVIEW_BYTES)
                        .map(|(text, _)| text)
                        .ok_or_else(|| anyhow::anyhow!("current preview range is invalid"))?,
                };
                projection.previews.push(CurrentContentPreview {
                    id,
                    role,
                    text_channel,
                    text,
                    reference,
                });
            }
            contents.insert(content.descriptor.key.clone(), content);
        }
        let cached_business = self
            .state
            .as_ref()
            .filter(|_| self.interaction_revision == Some(state.interaction_collection_revision));
        if cached_business.is_none() {
            for id in state.permissions.keys().chain(state.interactions.keys()) {
                if let Some(interaction) =
                    crate::thread_assembler::project_thread_interaction(&thread.id, id, state)?
                {
                    let entry = CurrentEntryWrite {
                        collection: "interactions".into(),
                        // The first row is the active decision: pending permissions precede
                        // pending questions; settled records remain independently pageable.
                        position: match (interaction.status(), interaction.kind()) {
                            (
                                crate::InteractionStatus::Pending,
                                crate::InteractionKind::ToolApproval,
                            ) => 0,
                            (
                                crate::InteractionStatus::Pending,
                                crate::InteractionKind::UserInput,
                            ) => 1,
                            _ => 2,
                        },
                        entry_id: interaction.interaction_id.clone(),
                        payload: Arc::from(serde_json::to_vec(&interaction)?),
                    };
                    entries.insert((entry.collection.clone(), entry.entry_id.clone()), entry);
                }
            }
        }
        let plan_record = state.extensions.get(crate::plan_tool::PLAN_EXTENSION);
        if plan_record.map(|record| record.revision) == self.plan_extension_revision
            && let Some(previous) = self.state.as_ref()
        {
            projection.plan = previous.projection().plan.clone();
            if let Some(reference) = projection
                .plan
                .as_ref()
                .and_then(|plan| plan.document.as_ref())
            {
                let content = previous
                    .references
                    .get(reference)
                    .ok_or_else(|| anyhow::anyhow!("current plan lost its content owner"))?;
                contents.insert(content.descriptor.key.clone(), content.clone());
            }
        } else if let Some(record) = plan_record {
            let plan = crate::plan_tool::decode_plan_state(&record.payload)?;
            let document = plan
                .plan
                .document
                .as_ref()
                .map(|document| -> Result<_> {
                    let owner = ContentOwner::Current {
                        domain: "plan".into(),
                        id: "document".into(),
                        revision: plan.plan.revision,
                    };
                    let key = ChatContentKey {
                        owner: content_owner_key(&owner)?,
                        key: "document".into(),
                    };
                    let content =
                        self.text(key, ContentBlock::from_text(&document.content), false)?;
                    let reference = content.reference.clone();
                    contents.insert(content.descriptor.key.clone(), content);
                    Ok(reference)
                })
                .transpose()?;
            projection.plan = Some(CurrentPlanHead {
                revision: plan.plan.revision,
                phase: plan.phase(),
                document,
            });
        }
        projection.interactions = Some(CurrentCollectionRef {
            owner_id: owner_id.clone(),
            collection: "interactions".into(),
            // The original Core owner versions both transfer and resident slices.
            // Reopening or observing progress must never allocate a resource version.
            revision: super::collection_revision(
                state.interaction_collection_revision,
                self.cold_revision.is_some(),
            )?,
        });
        let (mut entries, mut by_position, mut business_bytes) =
            if let Some(previous) = cached_business {
                (
                    previous.entries.clone(),
                    previous.by_position.clone(),
                    previous.business_bytes,
                )
            } else {
                let entries = entries
                    .into_iter()
                    .map(|(key, entry)| {
                        let owned = self
                            .state
                            .as_ref()
                            .and_then(|state| state.entries.get(&key))
                            .filter(|old| {
                                old.position == entry.position && old.payload == entry.payload
                            })
                            .cloned()
                            .unwrap_or_else(|| Arc::new(entry));
                        (key, owned)
                    })
                    .collect::<BTreeMap<_, _>>();
                let by_position = entries
                    .values()
                    .map(|entry| {
                        (
                            (
                                entry.collection.clone(),
                                entry.position,
                                entry.entry_id.clone(),
                            ),
                            entry.clone(),
                        )
                    })
                    .collect();
                let business_bytes = entries.values().fold(0u64, |bytes, entry| {
                    bytes
                        .saturating_add(entry.payload.len() as u64)
                        .saturating_add(entry.entry_id.len() as u64)
                        .saturating_add(128)
                });
                (Arc::new(entries), Arc::new(by_position), business_bytes)
            };
        let references = contents
            .values()
            .map(|content| (content.reference.clone(), content.clone()))
            .collect::<BTreeMap<_, _>>();
        let mut by_entity = BTreeMap::<&str, Vec<&Arc<CurrentContent>>>::new();
        for content in contents
            .values()
            .filter(|content| content.reference.domain == "entity")
        {
            by_entity
                .entry(&content.reference.entity_id)
                .or_default()
                .push(content);
        }
        projection.atoms = self
            .atoms
            .iter()
            .map(|atom| {
                let mut atom_contents: Vec<CurrentAtomContent> = atom
                    .contents
                    .iter()
                    .filter_map(|entry| {
                        let ContentTarget::Body { owner, key } = &entry.reference.target else {
                            return None;
                        };
                        let key = ChatContentKey {
                            owner: content_owner_key(owner).ok()?,
                            key: key.clone(),
                        };
                        let content = contents.get(&key)?;
                        Some(CurrentAtomContent {
                            role: entry.role,
                            reference: content.reference.clone(),
                        })
                    })
                    .collect();
                for content in by_entity.get(atom.id.as_str()).into_iter().flatten() {
                    if !atom_contents
                        .iter()
                        .any(|entry| entry.reference == content.reference)
                    {
                        atom_contents.push(CurrentAtomContent {
                            role: crate::studio::runtime::chat_item::atom_content_role_by_key(
                                &content.reference.content_key,
                            )
                            .unwrap_or(
                                if atom.kind == ChatAtomKind::ToolCall {
                                    ChatContentRole::ToolOutput
                                } else {
                                    ChatContentRole::Body
                                },
                            ),
                            reference: content.reference.clone(),
                        });
                    }
                }
                CurrentAtom {
                    id: atom.id.clone(),
                    source: atom.source.clone(),
                    source_state: atom.source_state.clone(),
                    source_order: atom.source_order,
                    kind: atom.kind,
                    delivery: atom.delivery,
                    lifecycle: atom.lifecycle.clone(),
                    turn_id: atom.turn_id.clone(),
                    attempt_id: atom.attempt_id.clone(),
                    tool: atom.tool.clone(),
                    wait: atom.wait.clone(),
                    text_channel: atom.text_channel,
                    started_at: atom.started_at,
                    finished_at: atom.finished_at,
                    content_present: atom.content_present,
                    contents: atom_contents,
                }
            })
            .collect();
        // Large live collections use the existing current paging/body port, not a truncated head.
        let had_resources = entries
            .keys()
            .any(|(collection, _)| collection == "atoms" || collection == "sources");
        if had_resources {
            Arc::make_mut(&mut entries)
                .retain(|(collection, _), _| collection != "atoms" && collection != "sources");
            Arc::make_mut(&mut by_position)
                .retain(|(collection, _, _), _| collection != "atoms" && collection != "sources");
        }
        const HEAD_BYTES: usize = 32 * 1024;
        if serde_json::to_vec(&projection)?.len() > HEAD_BYTES && !projection.atoms.is_empty() {
            let rows = std::mem::take(&mut projection.atoms)
                .into_iter()
                .map(|atom| Ok((atom.id.clone(), Arc::from(serde_json::to_vec(&atom)?))))
                .collect::<Result<Vec<_>>>()?;
            projection.collections.push(self.resource_collection(
                "atoms",
                rows,
                Arc::make_mut(&mut entries),
                Arc::make_mut(&mut by_position),
                &mut next_position,
            )?);
        }
        if serde_json::to_vec(&projection)?.len() > HEAD_BYTES && !projection.sources.is_empty() {
            let rows = std::mem::take(&mut projection.sources)
                .into_iter()
                .map(|source| {
                    Ok((
                        serde_json::to_string(&source.source)?,
                        Arc::from(serde_json::to_vec(&source)?),
                    ))
                })
                .collect::<Result<Vec<_>>>()?;
            projection.collections.push(self.resource_collection(
                "sources",
                rows,
                Arc::make_mut(&mut entries),
                Arc::make_mut(&mut by_position),
                &mut next_position,
            )?);
        }
        if had_resources
            || projection.collections.iter().any(|reference| {
                reference.collection == "atoms" || reference.collection == "sources"
            })
        {
            business_bytes = entries.values().fold(0u64, |bytes, entry| {
                bytes
                    .saturating_add(entry.payload.len() as u64)
                    .saturating_add(entry.entry_id.len() as u64)
                    .saturating_add(128)
            });
        }
        let snapshot = Arc::new(CurrentState {
            revision: sequence,
            owner_id: owner_id.clone(),
            references: Arc::new(references),
            projection: FrozenCurrentProjection::new(projection),
            contents: Arc::new(contents),
            entries,
            by_position,
            active_turn,
            business_bytes,
            metadata_bytes: OnceLock::new(),
        });
        self.state = Some(snapshot.clone());
        self.plan_extension_revision = plan_record.map(|record| record.revision);
        self.interaction_revision = Some(state.interaction_collection_revision);
        self.next_position = next_position;
        Ok(snapshot)
    }

    fn resource_collection(
        &mut self,
        collection: &'static str,
        rows: Vec<(String, Arc<[u8]>)>,
        entries: &mut BTreeMap<(String, String), Arc<CurrentEntryWrite>>,
        by_position: &mut CurrentPositionIndex,
        next_position: &mut i64,
    ) -> Result<CurrentCollectionRef> {
        let old = self.state.as_ref().map(|state| &state.entries);
        let changed = old.is_none_or(|old| {
            old.keys().filter(|(name, _)| name == collection).count() != rows.len()
                || rows.iter().any(|(id, payload)| {
                    old.get(&(collection.into(), id.clone()))
                        .is_none_or(|entry| &entry.payload != payload)
                })
        });
        let revision = self.resource_versions.entry(collection).or_default();
        if changed || *revision == 0 {
            *revision = revision
                .checked_add(1)
                .ok_or_else(|| anyhow::anyhow!("current collection revision exhausted"))?;
        }
        for (id, payload) in rows {
            let key = (collection.into(), id.clone());
            let previous = old.and_then(|old| old.get(&key));
            let entry = if let Some(previous) = previous.filter(|entry| entry.payload == payload) {
                previous.clone()
            } else {
                let position = match previous {
                    Some(entry) => entry.position,
                    None => {
                        *next_position = next_position
                            .checked_add(1)
                            .ok_or_else(|| anyhow::anyhow!("current position exhausted"))?;
                        *next_position
                    }
                };
                Arc::new(CurrentEntryWrite {
                    collection: collection.into(),
                    position,
                    entry_id: id.clone(),
                    payload,
                })
            };
            by_position.insert((collection.into(), entry.position, id), entry.clone());
            ensure!(
                entries.insert(key, entry).is_none(),
                "duplicate current entity identity"
            );
        }
        Ok(CurrentCollectionRef {
            owner_id: self
                .owner_id
                .clone()
                .ok_or_else(|| anyhow::anyhow!("current owner has no identity"))?,
            collection: collection.into(),
            revision: super::collection_revision(*revision, self.cold_revision.is_some())?,
        })
    }

    fn text(
        &self,
        key: ChatContentKey,
        block: Arc<ContentBlock>,
        appendable: bool,
    ) -> Result<Arc<CurrentContent>> {
        let old = self
            .state
            .as_ref()
            .and_then(|state| state.contents.get(&key));
        let mut generation = 1;
        if let Some(old) = old {
            generation = old.descriptor.generation;
            if Arc::ptr_eq(&old.block, &block)
                || (!appendable && ContentBlock::text_eq(&old.block, &block))
            {
                return Ok(old.clone());
            }
            ensure!(
                appendable,
                pl_core::chat::ChatError::Conflict(
                    "immutable current revision changed its bytes".into()
                )
            );
            if ContentBlock::appended_since(&block, &old.block).is_none() {
                generation = generation
                    .checked_add(1)
                    .ok_or_else(|| anyhow::anyhow!("content generation exhausted"))?;
            }
        }
        let (domain, entity_id, scope_revision) = decode_current_key(&key)?;
        let reference = CurrentContentRef {
            owner_id: self
                .owner_id
                .clone()
                .ok_or_else(|| anyhow::anyhow!("current owner has no identity"))?,
            domain,
            entity_id,
            content_key: key.key.clone(),
            generation: match self.cold_revision {
                Some(revision) => format!("cold:{revision}:{scope_revision}:{generation}"),
                None => format!("{scope_revision}:{generation}"),
            },
        };
        Ok(Arc::new(CurrentContent {
            reference,
            descriptor: ContentDescriptor {
                key,
                byte_length: block.len() as u64,
                generation,
                media_type: Some("text/plain; charset=utf-8".into()),
            },
            block,
            indexed: OnceLock::new(),
        }))
    }
}

fn paused_tool_atom(
    id: String,
    turn_id: &str,
    attempt_id: Option<String>,
    call_id: String,
    name: String,
) -> ChatAtom {
    ChatAtom {
        id,
        completion_item_id: None,
        completion_seq: None,
        source: ChatSourceId::ForegroundTurn {
            turn_id: turn_id.into(),
        },
        source_state: None,
        source_order: None,
        kind: ChatAtomKind::ToolCall,
        delivery: ChatDeliveryKind::Foreground,
        lifecycle: ChatAtomLifecycle::Active {
            started: None,
            status: ChatActiveStatus::Waiting,
        },
        turn_id: Some(turn_id.into()),
        attempt_id,
        tool: Some(ChatToolIdentity { call_id, name }),
        wait: None,
        text_channel: None,
        started_at: None,
        finished_at: None,
        content_present: None,
        contents: Vec::new(),
        payload: None,
    }
}

fn decode_current_key(key: &ChatContentKey) -> Result<(String, String, u64)> {
    let (length, encoded) = key
        .owner
        .as_str()
        .split_once(':')
        .ok_or_else(|| anyhow::anyhow!("invalid current content key"))?;
    let length: usize = length.parse()?;
    let (domain, identity) = encoded
        .split_at_checked(length)
        .ok_or_else(|| anyhow::anyhow!("invalid current content domain"))?;
    match domain {
        "item" => Ok(("entity".into(), identity.into(), 0)),
        "current" => Ok(serde_json::from_str(identity)?),
        _ => anyhow::bail!("historical content cannot become current content"),
    }
}

impl CurrentState {
    pub(in crate::studio) fn cold(
        database: String,
        thread_id: String,
        sequence: u64,
        state: &ThreadSnapshot,
    ) -> Result<Arc<Self>> {
        let mut owner = CurrentOwner {
            cold_revision: Some(sequence),
            ..Default::default()
        };
        owner.resource_versions.insert("atoms", sequence);
        owner.resource_versions.insert("sources", sequence);
        owner.bind(database)?;
        let current = owner.observe(&Thread::placeholder(thread_id), state, sequence, [])?;
        let mut projection = current.projection().clone();
        projection.execution_present = false;
        projection.active = None;
        Ok(Self::with_projection(
            current,
            FrozenCurrentProjection::new(projection),
        ))
    }
    /// Saved producer observations are inert display material, never a running request.
    pub(in crate::studio) fn from_saved(
        saved: &pl_core::thread::current::ThreadCurrent,
    ) -> Result<Arc<Self>> {
        use pl_core::thread::current::SavedModelPhase;
        let mut state = saved.state.to_paused_snapshot();
        state.interaction_collection_revision = saved.snapshot_revision;
        let mut owner = CurrentOwner {
            cold_revision: Some(saved.snapshot_revision),
            ..Default::default()
        };
        owner
            .resource_versions
            .insert("atoms", saved.snapshot_revision);
        owner
            .resource_versions
            .insert("sources", saved.snapshot_revision);
        owner.bind(saved.saved_runtime_epoch.to_string())?;
        let mut active = Vec::new();
        let mut atoms = Vec::new();
        if let Some(call) = &saved.model_call
            && let SavedModelPhase::Streaming { stream } = &call.phase
        {
            let stream = pl_model::completion::ModelStreamCurrent::decode(stream)?;
            ensure!(
                stream.attempt_id == call.source_attempt_id,
                "saved stream attempt differs"
            );
            for part in stream.content_parts {
                let observed = pl_core::model::ObservedPart::new(part.identity);
                let Some((id, key, shape)) = super::live::observation_preview(
                    &call.source_attempt_id,
                    stream.generation,
                    &observed,
                    &ThreadContentLifecycle::streaming(),
                ) else {
                    continue;
                };
                let item = crate::ExecutionItem::new(
                    id.clone(),
                    saved.thread_id.clone(),
                    call.source_turn_id.clone(),
                    0,
                    0,
                    0,
                    0,
                    shape,
                );
                let mut atom = crate::studio::runtime::chat_item::atom(&item);
                atom.attempt_id = Some(call.source_attempt_id.clone());
                atom.lifecycle = ChatAtomLifecycle::Active {
                    started: None,
                    status: ChatActiveStatus::Waiting,
                };
                atom.content_present = Some(!part.text.is_empty());
                active.push((
                    id,
                    key,
                    ContentBlock::from_text(&part.text),
                    atom.text_channel,
                    None,
                ));
                atoms.push(atom);
            }
            for input in stream.tool_inputs {
                let id = super::order::tool_id(&input.call_id);
                active.push((
                    id.clone(),
                    BodyKey::host(TOOL_ARGUMENTS_FIELD),
                    ContentBlock::from_text(&input.input),
                    None,
                    None,
                ));
                atoms.push(paused_tool_atom(
                    id,
                    &call.source_turn_id,
                    Some(call.source_attempt_id.clone()),
                    input.call_id,
                    input.name,
                ));
            }
        }
        for (call_id, progress) in &saved.state.tool_previews {
            let task = saved
                .state
                .tasks
                .values()
                .find(|task| &task.call_id == call_id)
                .ok_or_else(|| anyhow::anyhow!("saved preview has no task"))?;
            let id = super::order::tool_id(call_id);
            for part in &progress.parts {
                active.push((
                    id.clone(),
                    BodyKey::host(format!("{TOOL_RESULT_FIELD}:{}", part.id)),
                    ContentBlock::from_text(&part.text),
                    None,
                    None,
                ));
            }
            atoms.push(paused_tool_atom(
                id,
                &task.turn_id,
                None,
                call_id.clone(),
                task.tool_id.clone(),
            ));
        }
        owner.provenance(Vec::new(), atoms);
        let current = owner.observe(
            &Thread::placeholder(saved.thread_id.clone()),
            &state,
            saved.snapshot_revision,
            active,
        )?;
        let mut projection = current.projection().clone();
        projection.execution_present = false;
        projection.active = None;
        projection.active_turn = None;
        Ok(Self::with_projection(
            current,
            FrozenCurrentProjection::new(projection),
        ))
    }

    pub fn revision(&self) -> u64 {
        self.revision
    }
    pub fn owner_id(&self) -> &str {
        &self.owner_id
    }
    pub fn content(&self, reference: &CurrentContentRef) -> Option<Arc<CurrentContent>> {
        self.references.get(reference).cloned()
    }
    pub fn projection(&self) -> &CurrentProjection {
        self.projection.projection()
    }
    pub fn business_refs(&self) -> ThreadBusinessRefs {
        project_business_refs(self.projection())
    }
    pub fn frozen_projection(&self) -> &Arc<FrozenCurrentProjection> {
        &self.projection
    }
    pub fn entries(&self) -> &Arc<BTreeMap<(String, String), Arc<CurrentEntryWrite>>> {
        &self.entries
    }
    pub fn by_position(&self) -> &Arc<CurrentPositionIndex> {
        &self.by_position
    }
    pub fn active_turn(&self) -> Option<&Turn> {
        self.active_turn.as_ref()
    }
    /// Changes only the bounded head, retaining the original body/collection owners.
    pub(in crate::studio) fn with_projection(
        state: Arc<Self>,
        projection: Arc<FrozenCurrentProjection>,
    ) -> Arc<Self> {
        if Arc::ptr_eq(state.frozen_projection(), &projection) {
            return state;
        }
        Arc::new(Self {
            revision: state.revision,
            owner_id: state.owner_id.clone(),
            references: state.references.clone(),
            projection,
            contents: state.contents.clone(),
            entries: state.entries.clone(),
            by_position: state.by_position.clone(),
            active_turn: state.active_turn.clone(),
            business_bytes: state.business_bytes,
            metadata_bytes: OnceLock::new(),
        })
    }

    pub(super) fn metadata_bytes(&self) -> u64 {
        *self.metadata_bytes.get_or_init(|| {
            let entries = self
                .business_bytes
                .saturating_add((self.contents.len() as u64).saturating_mul(256));
            entries
                .saturating_add(std::mem::size_of::<OnceLock<u64>>() as u64)
                .saturating_add(self.projection.retained_bytes())
        })
    }
}

/// The same lightweight domain-head projection serves State and ordinary readers.
pub(in crate::studio) fn project_business_refs(
    projection: &CurrentProjection,
) -> ThreadBusinessRefs {
    ThreadBusinessRefs {
        plan: projection.plan.clone(),
        interactions: projection.interactions.clone(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use anyhow::Context;

    #[test]
    fn large_current_atoms_page_without_truncation_and_only_metadata_changes_expire_the_collection()
    -> Result<()> {
        let mut owner = CurrentOwner::default();
        let epoch = pl_core::thread::current::RuntimeEpoch::new().to_string();
        owner.bind(epoch.clone())?;
        let thread = Thread::placeholder("large-current");
        let state = ThreadSnapshot::default();
        owner.provenance(
            Vec::new(),
            (0..128)
                .map(|index| {
                    paused_tool_atom(
                        format!("entity-{index}"),
                        "turn",
                        None,
                        format!("call-{index}"),
                        "工具名称".repeat(200),
                    )
                })
                .collect(),
        );
        let first = owner.observe(&thread, &state, 7, [])?;
        assert!(first.projection().atoms.is_empty());
        let reference = first
            .projection()
            .collections
            .iter()
            .find(|head| head.collection == "atoms")
            .context("large collection reference")?
            .clone();
        assert_eq!(reference.owner_id, epoch);
        assert!(serde_json::to_vec(first.projection())?.len() < 32 * 1024);
        let demand = ReadDemand {
            max_items: 3,
            max_bytes: 8192,
        };
        let mut after = None;
        let mut ids = std::collections::BTreeSet::new();
        loop {
            let page = crate::studio::thread_projection::current_page(
                &first,
                &reference,
                after.as_deref(),
                demand,
                Ok,
            )?;
            assert!(page.entries.len() <= 3);
            assert!(serde_json::to_vec(&page)?.len() <= demand.max_bytes as usize);
            for entry in page.entries {
                assert!(ids.insert(entry.id));
            }
            after = page.continuation;
            if after.is_none() {
                break;
            }
        }
        assert_eq!(ids.len(), 128);

        let same = owner.observe(&thread, &state, 8, [])?;
        assert!(
            same.projection().collections.contains(&reference),
            "unrelated Core progress cannot expire this collection"
        );
        owner.atoms[0].tool.as_mut().unwrap().name = "变更后的工具名称".repeat(200);
        let changed = owner.observe(&thread, &state, 8, [])?;
        assert!(!changed.projection().collections.contains(&reference));
        assert!(
            crate::studio::thread_projection::current_page(&changed, &reference, None, demand, Ok)
                .is_err()
        );
        // A captured old cut still owns its original resource, including after a successor exists.
        assert!(
            !crate::studio::thread_projection::current_page(&first, &reference, None, demand, Ok)?
                .entries
                .is_empty()
        );
        Ok(())
    }

    #[test]
    fn text_channel_is_independent_of_display_role_and_body_generation() -> Result<()> {
        let mut owner = CurrentOwner::default();
        owner.bind("database".into())?;
        let thread = Thread::placeholder("thread");
        let state = ThreadSnapshot::default();
        let block = ContentBlock::from_text(&"body".repeat(PREVIEW_BYTES));
        let mut previous: Option<(CurrentContentPreview, u64)> = None;
        for channel in [
            None,
            Some(ThreadTextChannel::Commentary),
            Some(ThreadTextChannel::Final),
        ] {
            let current = owner.observe(
                &thread,
                &state,
                1,
                [("part".into(), BodyKey::Body, block.clone(), channel, None)],
            )?;
            let preview = &current.projection().previews[0];
            let generation = current
                .contents
                .values()
                .next()
                .unwrap()
                .descriptor
                .generation;
            assert_eq!(preview.role, CurrentContentRole::Response);
            assert_eq!(preview.text_channel, channel);
            if let Some((previous, previous_generation)) = &previous {
                assert_eq!(preview.reference, previous.reference);
                assert_eq!(preview.text, previous.text);
                assert_eq!(generation, *previous_generation);
                assert_ne!(preview, previous);
            }
            let wire = serde_json::to_value(current.projection())?;
            match channel {
                None => assert!(wire["previews"][0].get("textChannel").is_none()),
                Some(channel) => {
                    assert_eq!(
                        wire["previews"][0]["textChannel"],
                        serde_json::to_value(channel)?
                    );
                }
            }
            assert_eq!(
                serde_json::from_value::<CurrentProjection>(wire)?,
                *current.projection()
            );
            previous = Some((preview.clone(), generation));
        }
        Ok(())
    }

    #[test]
    fn collapsed_progress_indexes_only_at_the_first_read_or_reliable_handoff() -> Result<()> {
        let mut owner = CurrentOwner::default();
        owner.bind("database".into())?;
        let thread = Thread::placeholder("thread");
        let state = ThreadSnapshot::default();
        let block = ContentBlock::from_text(&"汉📖".repeat(2048));
        let first = owner.observe(
            &thread,
            &state,
            1,
            [("active".into(), BodyKey::Body, block.clone(), None, None)],
        )?;
        assert!(
            first
                .contents
                .values()
                .next()
                .unwrap()
                .indexed
                .get()
                .is_none()
        );
        let appended = ContentBlock::append(&block, "继续");
        let next = owner.observe(
            &thread,
            &state,
            1,
            [("active".into(), BodyKey::Body, appended.clone(), None, None)],
        )?;
        let content = next.contents.values().next().unwrap();
        assert!(
            content.indexed.get().is_none(),
            "collapsed token progress rebuilt a complete range index"
        );
        assert_eq!(
            first.projection().previews[0].text,
            next.projection().previews[0].text
        );
        let accepted = content.content();
        assert!(
            Arc::ptr_eq(&accepted, &content.content()),
            "two readers built distinct indexes for one owner version"
        );
        let frozen = owner.observe(
            &thread,
            &state,
            2,
            [("active".into(), BodyKey::Body, appended.clone(), None, None)],
        )?;
        assert!(
            frozen.entries.is_empty(),
            "active progress became a durable document write"
        );
        assert!(Arc::ptr_eq(
            &accepted,
            &frozen.contents.values().next().unwrap().content()
        ));
        let generation = accepted.descriptor.generation;
        let replacement = owner.observe(
            &thread,
            &state,
            2,
            [(
                "active".into(),
                BodyKey::Body,
                ContentBlock::from_text(&appended.text()),
                None,
                None,
            )],
        )?;
        assert_eq!(
            replacement
                .contents
                .values()
                .next()
                .unwrap()
                .descriptor
                .generation,
            generation + 1,
            "an explicit replacement reused the append lineage"
        );
        Ok(())
    }
}

#[cfg(test)]
mod business_tests {
    use super::*;
    use crate::plan_tool::{AgentSessionPlanState, PlanState};

    fn state(version: u64, text: &str) -> Result<ThreadSnapshot> {
        let plan = AgentSessionPlanState::with_document(PlanState::Approved, version, text, 0);
        let mut state = ThreadSnapshot {
            interaction_collection_revision: 17,
            ..Default::default()
        };
        state.extensions.insert(
            crate::plan_tool::PLAN_EXTENSION.into(),
            pl_core::thread::extensions::ExtensionRecord {
                revision: version,
                payload: crate::plan_tool::encode_plan_state(&plan)?,
            },
        );
        Ok(state)
    }
    #[test]
    fn plan_changes_do_not_invalidate_interactions_and_tokens_do_not_change_business_refs()
    -> Result<()> {
        let mut owner = CurrentOwner::default();
        owner.bind("business-db".into())?;
        let thread = Thread::placeholder("business-thread");
        let old = state(3, "# Original plan\n\nSteps")?;
        let first = owner.observe(&thread, &old, 10, [])?;
        let references = first.business_refs();
        let interactions = references.interactions.as_ref().unwrap();
        let page = super::super::current_page(
            &first,
            interactions,
            None,
            ReadDemand {
                max_items: 1,
                max_bytes: 4096,
            },
            Ok,
        )?;
        assert!(page.entries.is_empty());
        let progress = owner.observe(
            &thread,
            &old,
            10,
            [(
                "part".into(),
                BodyKey::Body,
                ContentBlock::from_text("token"),
                None,
                None,
            )],
        )?;
        assert_eq!(progress.business_refs(), references);
        assert!(Arc::ptr_eq(&first.entries, &progress.entries));
        assert!(Arc::ptr_eq(&first.by_position, &progress.by_position));
        assert!(progress.projection().collections.is_empty());
        let new = state(4, "# New plan\n\nRevised steps")?;
        let next = owner.observe(&thread, &new, 11, [])?;
        assert_eq!(next.business_refs().interactions, references.interactions);
        assert!(Arc::ptr_eq(&first.entries, &next.entries));
        assert_ne!(next.business_refs().plan, references.plan);
        let old_ref = references.plan.unwrap().document.unwrap();
        assert!(
            next.content(&old_ref).is_none(),
            "retired live document unexpectedly reads the latest version"
        );
        Ok(())
    }

    #[test]
    fn interaction_resources_use_core_revisions_across_deletion_and_reopen() -> Result<()> {
        use pl_core::{
            context::OpaquePayload,
            thread::interactions::{InteractionRecord, InteractionRequest, InteractionState},
        };

        let thread = Thread::placeholder("interaction-revisions");
        let mut before = ThreadSnapshot {
            interaction_collection_revision: 41,
            ..Default::default()
        };
        for id in ["first", "second"] {
            let state = if id == "first" {
                InteractionState::Cancelled
            } else {
                InteractionState::Pending
            };
            let revision = if matches!(&state, InteractionState::Pending) {
                1
            } else {
                2
            };
            let id = pl_core::tool::opaque::tool_interaction_id(id);
            before.interactions.insert(
                id.clone(),
                InteractionRecord {
                    created_at: 1,
                    updated_at: 1,
                    continuation_id: None,
                    revision,
                    state,
                    extension_mutations: vec![],
                    request: InteractionRequest {
                        id,
                        turn_id: "turn".into(),
                        payload: OpaquePayload::new(
                            "pl.tool.user-input",
                            1,
                            serde_json::to_string(&vec![UserQuestion {
                                id: "question".into(),
                                header: "Question".into(),
                                question: "Continue?".into(),
                                is_other: true,
                                is_secret: false,
                                options: None,
                            }])?,
                        )?,
                    },
                },
            );
        }
        let mut owner = CurrentOwner::default();
        owner.bind("interaction-db".into())?;
        let first = owner.observe(&thread, &before, 3, [])?;
        let initial = first
            .business_refs()
            .interactions
            .expect("interaction collection");
        let page = super::super::current_page(
            &first,
            &initial,
            None,
            ReadDemand {
                max_items: 1,
                max_bytes: 4096,
            },
            Ok,
        )?;
        let crate::CurrentPayloadData::Inline { bytes } = &page.entries[0].payload else {
            panic!("the small current decision should be inline");
        };
        let active: crate::InteractionRequest = serde_json::from_slice(bytes)?;
        assert_eq!(active.status(), crate::InteractionStatus::Pending);
        assert_eq!(
            active,
            crate::thread_assembler::project_thread_interaction(
                &thread.id,
                &pl_core::tool::opaque::tool_interaction_id("second"),
                &before,
            )?
            .expect("original pending question"),
        );
        assert!(
            page.continuation.is_some(),
            "settled details must remain pageable"
        );

        let mut after = before.clone();
        after
            .interactions
            .remove(&pl_core::tool::opaque::tool_interaction_id("first"));
        after.interaction_collection_revision = 42;
        let next = owner.observe(&thread, &after, 4, [])?;
        let deleted = next
            .business_refs()
            .interactions
            .expect("deleted interaction collection");
        assert_ne!(deleted, initial);
        assert!(
            super::super::current_page(
                &next,
                &initial,
                None,
                ReadDemand {
                    max_items: 1,
                    max_bytes: 4096,
                },
                Ok,
            )
            .is_err(),
            "the pre-deletion collection reference remained readable"
        );

        let cold = CurrentState::cold("interaction-db".into(), thread.id.clone(), 4, &after)?;
        let cold_interactions = cold
            .business_refs()
            .interactions
            .expect("cold interaction collection");
        assert_ne!(
            cold_interactions, deleted,
            "live and reopened Current must not reuse collection generations"
        );
        assert!(
            super::super::current_page(
                &cold,
                &deleted,
                None,
                ReadDemand {
                    max_items: 1,
                    max_bytes: 4096,
                },
                Ok,
            )
            .is_err(),
            "the reopened owner accepted the old live collection reference"
        );

        // A later owner version is a distinct availability generation even with the same members.
        let mut later = after.clone();
        later.interaction_collection_revision = 44;
        let later = owner.observe(&thread, &later, 5, [])?;
        let later = later
            .business_refs()
            .interactions
            .expect("later interaction collection");
        assert_ne!(later, deleted);
        assert_ne!(later, cold_interactions);
        Ok(())
    }
}

//! Effect-local product current and its read owners. No completed-history mirror lives here.

use super::FrozenCurrentProjection;
use crate::studio::storage::history::conversation::current::{
    CurrentContentWrite, CurrentEntryWrite, PreparedCurrent,
};
use crate::studio::{
    conversation_identity::content_owner_key,
    runtime::chat_item::{BodyKey, TOOL_ARGUMENTS_FIELD, TOOL_RESULT_FIELD},
};
use anyhow::{Result, ensure};
use pl_core::{
    chat::{ChatContent, ChatContentKey, ChatContents, ContentData, ContentDescriptor},
    model::ContentBlock,
    thread::ThreadSnapshot,
};
use pl_protocol::*;
use std::{
    collections::BTreeMap,
    ops::Bound::{Excluded, Unbounded},
    sync::{Arc, OnceLock},
};

const PREVIEW_BYTES: usize = 512;
const PREVIEW_COUNT: usize = 4;
pub(super) type ActiveText = (
    String,
    BodyKey,
    Arc<ContentBlock>,
    u64,
    Option<ThreadTextChannel>,
);

#[derive(Debug)]
pub(in crate::studio) struct CurrentContent {
    pub descriptor: ContentDescriptor,
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
pub(in crate::studio) struct CurrentState {
    projection: Arc<FrozenCurrentProjection>,
    /// Bounded real source facts from this owner cut, including not-yet-saved ends.
    source_states: Arc<[ChatSourceState]>,
    contents: Arc<BTreeMap<ChatContentKey, Arc<CurrentContent>>>,
    materialized: OnceLock<Arc<ChatContents>>,
    entries: Arc<BTreeMap<(String, String), Arc<CurrentEntryWrite>>>,
    by_position: Arc<CurrentPositionIndex>,
    active_turn: Option<Turn>,
    /// State baseline from this exact owner cut, independent of current collection reads.
    interactions: Arc<[InteractionRequest]>,
    metadata_bytes: OnceLock<u64>,
}

#[derive(Default)]
pub(super) struct CurrentOwner {
    database_id: Option<String>,
    activity: super::activity::ActivityProjection,
    state: Option<Arc<CurrentState>>,
    plan_extension_revision: Option<u64>,
    frozen_plan_revision: Option<u64>,
    next_position: i64,
    sources: Arc<[ChatSourceState]>,
    atoms: Vec<ChatAtom>,
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
    pub(super) fn database_id(&self) -> Option<&str> {
        self.database_id.as_deref()
    }
    pub(super) fn bind(&mut self, database_id: String) -> Result<()> {
        ensure!(
            !database_id.is_empty(),
            "empty conversation database identity"
        );
        ensure!(
            self.database_id
                .as_ref()
                .is_none_or(|old| old == &database_id),
            "conversation database identity changed within owner"
        );
        self.database_id = Some(database_id);
        Ok(())
    }
    pub(super) fn item_contents(&self) -> Arc<ChatContents> {
        self.state
            .as_ref()
            .map(|state| state.materialized_contents())
            .unwrap_or_default()
    }
    pub(super) fn snapshot(&self) -> Option<Arc<CurrentState>> {
        self.state.clone()
    }

    /// Timeline alone replaces items. Preserve a newer streaming cut if it has
    /// advanced since preparation; otherwise install the same frozen head.
    pub(super) fn adopt_timeline_projection(
        &mut self,
        before: &Arc<FrozenCurrentProjection>,
        after: &Arc<FrozenCurrentProjection>,
    ) {
        if let Some(state) = self.state.take() {
            let projection = if Arc::ptr_eq(state.frozen_projection(), before) {
                after.clone()
            } else {
                state
                    .frozen_projection()
                    .with_items(after.projection().items.clone())
            };
            self.state = Some(CurrentState::with_projection(state, projection));
        }
    }

    pub(super) fn freeze(
        &mut self,
        thread: &Thread,
        state: &ThreadSnapshot,
        sequence: u64,
        active: impl IntoIterator<Item = ActiveText>,
    ) -> Result<(Arc<PreparedCurrent>, Arc<CurrentState>)> {
        let snapshot = self.project(thread, state, sequence, active)?;
        // Current is transport material. Only a complete Plan revision belongs to the
        // independent reliable domain; active body and collection changes never reach SQLite.
        let plan_key = snapshot
            .projection()
            .plan
            .as_ref()
            .and_then(|plan| plan.document.as_ref())
            .and_then(|reference| match &reference.target {
                ContentTarget::Body { owner, key } => {
                    Some(content_owner_key(owner).map(|owner| ChatContentKey {
                        owner,
                        key: key.clone(),
                    }))
                }
                _ => None,
            })
            .transpose()?;
        let plan_revision = snapshot
            .projection()
            .plan
            .as_ref()
            .map(|plan| plan.revision);
        let contents = snapshot
            .contents
            .iter()
            .filter_map(|(key, content)| {
                (plan_revision != self.frozen_plan_revision && plan_key.as_ref() == Some(key)).then(
                    || CurrentContentWrite {
                        content: content.content(),
                        sealed: true,
                    },
                )
            })
            .collect::<Vec<_>>();
        let prepared = PreparedCurrent::new(snapshot.projection.clone(), contents.into());
        self.frozen_plan_revision = plan_revision;
        Ok((Arc::new(prepared), snapshot))
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
        let database_id = self
            .database_id
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("current owner has no database identity"))?;
        let activity = self.activity.observe(&thread.id, state);
        let mut projection = CurrentProjection::empty(sequence, super::status(state));
        projection.sources = self
            .sources
            .iter()
            .filter(|source| {
                matches!(source.lifecycle, ChatSourceLifecycle::Active)
                    || source.ended.is_some_and(|at| at.effect_seq == sequence)
            })
            .cloned()
            .collect();
        projection.atoms = self.atoms.clone();
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
        if let Some(atom) = projection.atoms.iter().find(|atom| {
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
        let mut collection_position = |collection: &str, id: &str| -> Result<i64> {
            if let Some(entry) = self
                .state
                .as_ref()
                .and_then(|state| state.entries.get(&(collection.into(), id.into())))
            {
                return Ok(entry.position);
            }
            next_position = next_position
                .checked_add(1)
                .ok_or_else(|| anyhow::anyhow!("current position exhausted"))?;
            Ok(next_position)
        };
        type MemberBodies = (u64, Vec<(ContentRef, Arc<CurrentContent>)>);
        let mut members: BTreeMap<String, MemberBodies> = BTreeMap::new();
        for (id, position, block, ordinal, text_channel) in active {
            let key = position.as_key();
            let owner = ContentOwner::Item {
                item_id: id.clone(),
            };
            let content_key = ChatContentKey {
                owner: content_owner_key(&owner)?,
                key: key.clone(),
            };
            let content = self.text(content_key, block, true)?;
            let reference = ContentRef {
                database_id: database_id.clone(),
                target: ContentTarget::Body {
                    owner: owner.clone(),
                    key: key.clone(),
                },
            };
            members
                .entry(id.clone())
                .or_insert_with(|| (ordinal, Vec::new()))
                .1
                .push((reference.clone(), content.clone()));
            if projection.previews.len() < PREVIEW_COUNT {
                let role = match position {
                    BodyKey::Part(
                        pl_core::chat::PresentationPart::ReasoningText(_)
                        | pl_core::chat::PresentationPart::SummaryText(_),
                    ) => CurrentContentRole::Reasoning,
                    BodyKey::Host(ref key) if key == TOOL_ARGUMENTS_FIELD => {
                        CurrentContentRole::ToolArguments
                    }
                    BodyKey::Host(ref key) if key == TOOL_RESULT_FIELD => {
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
        for (id, (position, bodies)) in members {
            let position = i64::try_from(position)?;
            let previous_payload = match bodies.as_slice() {
                [(_, content)] => self.state.as_ref().and_then(|previous| {
                    let key = &content.descriptor.key;
                    let old = previous.contents.get(key)?;
                    if !Arc::ptr_eq(old, content) {
                        return None;
                    }
                    // ChatContentKey orders by owner first, so only the two adjacent keys
                    // can disqualify a previously single-body owner.
                    let same_owner = |(neighbor, _): (&ChatContentKey, &Arc<CurrentContent>)| {
                        neighbor.owner == key.owner
                    };
                    if previous
                        .contents
                        .range::<ChatContentKey, _>((Unbounded, Excluded(key)))
                        .next_back()
                        .is_some_and(same_owner)
                        || previous
                            .contents
                            .range::<ChatContentKey, _>((Excluded(key), Unbounded))
                            .next()
                            .is_some_and(same_owner)
                    {
                        return None;
                    }
                    previous
                        .entries
                        .get(&("members".into(), id.clone()))
                        .filter(|entry| entry.position == position)
                        .map(|entry| entry.payload.clone())
                }),
                _ => None,
            };
            let payload = match previous_payload {
                Some(payload) => payload,
                None => {
                    let bodies: Vec<_> = bodies
                        .iter()
                        .map(|(reference, content)| {
                            serde_json::json!({
                                "reference": reference,
                                "byteLength": content.descriptor.byte_length,
                                "generation": content.descriptor.generation,
                            })
                        })
                        .collect();
                    Arc::from(serde_json::to_vec(&bodies)?)
                }
            };
            let entry = CurrentEntryWrite {
                collection: "members".into(),
                position,
                entry_id: id,
                payload,
            };
            entries.insert((entry.collection.clone(), entry.entry_id.clone()), entry);
        }
        // Growing tool/member collections are owned here, not copied into the small head.
        if let Some(activity) = activity.as_ref() {
            for tool in &activity.tools.active {
                let entry = CurrentEntryWrite {
                    collection: "tools".into(),
                    position: collection_position("tools", &tool.call_id)?,
                    entry_id: tool.call_id.clone(),
                    payload: Arc::from(serde_json::to_vec(tool)?),
                };
                entries.insert((entry.collection.clone(), entry.entry_id.clone()), entry);
            }
        }
        let mut interactions = Vec::new();
        for id in state.permissions.keys().chain(state.interactions.keys()) {
            if let Some(interaction) =
                crate::thread_assembler::project_thread_interaction(&thread.id, id, state)?
            {
                let entry = CurrentEntryWrite {
                    collection: "interactions".into(),
                    position: collection_position("interactions", &interaction.interaction_id)?,
                    entry_id: interaction.interaction_id.clone(),
                    payload: Arc::from(serde_json::to_vec(&interaction)?),
                };
                entries.insert((entry.collection.clone(), entry.entry_id.clone()), entry);
                interactions.push(interaction);
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
                && let ContentTarget::Body { owner, key } = &reference.target
            {
                let key = ChatContentKey {
                    owner: content_owner_key(owner)?,
                    key: key.clone(),
                };
                let content = previous
                    .contents
                    .get(&key)
                    .ok_or_else(|| anyhow::anyhow!("current plan lost its content owner"))?;
                contents.insert(key, content.clone());
            }
        } else if let Some(record) = plan_record {
            let plan = crate::plan_tool::decode_plan_state(&record.payload)?;
            let document = plan
                .document
                .as_ref()
                .map(|document| -> Result<_> {
                    let owner = ContentOwner::Current {
                        domain: "plan".into(),
                        id: "document".into(),
                        revision: plan.revision,
                    };
                    let key = ChatContentKey {
                        owner: content_owner_key(&owner)?,
                        key: "document".into(),
                    };
                    let content =
                        self.text(key, ContentBlock::from_text(&document.markdown), false)?;
                    contents.insert(content.descriptor.key.clone(), content);
                    Ok(ContentRef {
                        database_id: database_id.clone(),
                        target: ContentTarget::Body {
                            owner,
                            key: "document".into(),
                        },
                    })
                })
                .transpose()?;
            projection.plan = Some(CurrentPlanHead {
                revision: plan.revision,
                phase: plan.state,
                document,
            });
        }
        for collection in ["tools", "interactions", "members"] {
            let changed = self.state.as_ref().is_none_or(|previous| {
                let old: Vec<_> = previous
                    .entries
                    .iter()
                    .filter(|((name, _), _)| name == collection)
                    .collect();
                let new: Vec<_> = entries
                    .iter()
                    .filter(|((name, _), _)| name == collection)
                    .collect();
                old.len() != new.len()
                    || old.iter().zip(new.iter()).any(|((key, a), (next, b))| {
                        key != next || a.position != b.position || a.payload != b.payload
                    })
            });
            let previous_revision = self
                .state
                .as_ref()
                .and_then(|state| {
                    state
                        .projection()
                        .collections
                        .iter()
                        .find(|reference| reference.collection == collection)
                })
                .map(|reference| reference.revision);
            let revision = if changed {
                previous_revision.map_or(
                    Ok(state.observation_revision.max(sequence)),
                    |previous| {
                        previous
                            .checked_add(1)
                            .ok_or_else(|| anyhow::anyhow!("current collection revision exhausted"))
                    },
                )?
            } else {
                previous_revision.unwrap_or(sequence)
            };
            let reference = CurrentCollectionRef {
                database_id: database_id.clone(),
                collection: collection.into(),
                revision,
            };
            if collection == "interactions" {
                projection.interactions = Some(reference.clone());
            }
            projection.collections.push(reference);
        }
        let entries = entries
            .into_iter()
            .map(|(key, entry)| {
                let owned = self
                    .state
                    .as_ref()
                    .and_then(|state| state.entries.get(&key))
                    .filter(|old| old.position == entry.position && old.payload == entry.payload)
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
        let snapshot = Arc::new(CurrentState {
            projection: FrozenCurrentProjection::new(projection),
            source_states: self.sources.clone(),
            contents: Arc::new(contents),
            materialized: OnceLock::new(),
            entries: Arc::new(entries),
            by_position: Arc::new(by_position),
            active_turn,
            interactions: interactions.into(),
            metadata_bytes: OnceLock::new(),
        });
        self.state = Some(snapshot.clone());
        self.plan_extension_revision = plan_record.map(|record| record.revision);
        self.next_position = next_position;
        Ok(snapshot)
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
        Ok(Arc::new(CurrentContent {
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

impl CurrentState {
    pub(in crate::studio) fn cold(
        database: String,
        thread_id: String,
        sequence: u64,
        state: &ThreadSnapshot,
    ) -> Result<Arc<Self>> {
        let mut owner = CurrentOwner::default();
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
    pub fn projection(&self) -> &CurrentProjection {
        self.projection.projection()
    }
    pub fn frozen_projection(&self) -> &Arc<FrozenCurrentProjection> {
        &self.projection
    }
    pub fn source_states(&self) -> &Arc<[ChatSourceState]> {
        &self.source_states
    }
    pub fn contents(&self) -> &Arc<BTreeMap<ChatContentKey, Arc<CurrentContent>>> {
        &self.contents
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
    pub fn interactions(&self) -> &Arc<[InteractionRequest]> {
        &self.interactions
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
            projection,
            source_states: state.source_states.clone(),
            contents: state.contents.clone(),
            materialized: OnceLock::new(),
            entries: state.entries.clone(),
            by_position: state.by_position.clone(),
            active_turn: state.active_turn.clone(),
            interactions: state.interactions.clone(),
            metadata_bytes: OnceLock::new(),
        })
    }

    fn materialized_contents(&self) -> Arc<ChatContents> {
        self.materialized
            .get_or_init(|| {
                Arc::new(
                    self.contents
                        .iter()
                        .map(|(key, content)| (key.clone(), content.content()))
                        .collect(),
                )
            })
            .clone()
    }
    pub(super) fn metadata_bytes(&self) -> u64 {
        *self.metadata_bytes.get_or_init(|| {
            let entries = self.entries.values().fold(
                (self.contents.len() as u64).saturating_mul(256),
                |bytes, entry| {
                    bytes
                        .saturating_add(entry.payload.len() as u64)
                        .saturating_add(entry.entry_id.len() as u64)
                        .saturating_add(128)
                },
            );
            let entries = entries
                .saturating_add(std::mem::size_of::<OnceLock<u64>>() as u64)
                .saturating_add(self.projection.retained_bytes())
                .saturating_add(
                    serde_json::to_vec(self.source_states.as_ref())
                        .map_or(u64::MAX, |bytes| bytes.len() as u64),
                );
            // An empty interaction slice owns no dynamic budget, exactly like every other empty
            // resident list: only a non-empty slice pays its fat-pointer shell here.
            if self.interactions.is_empty() {
                return entries;
            }
            self.interactions.iter().fold(
                entries.saturating_add(2 * std::mem::size_of::<usize>() as u64),
                |bytes, interaction| {
                    bytes
                        .saturating_add(std::mem::size_of::<InteractionRequest>() as u64)
                        .saturating_add(super::live::interaction_request_bytes(interaction))
                },
            )
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn assert_single_member_payload(state: &CurrentState, id: &str) -> Result<Arc<[u8]>> {
        let owner = ContentOwner::Item { item_id: id.into() };
        let owner_key = content_owner_key(&owner)?;
        let mut bodies = state
            .contents()
            .values()
            .filter(|content| content.descriptor.key.owner == owner_key);
        let body = bodies.next().expect("single member body");
        assert!(bodies.next().is_none());
        let reference = ContentRef {
            database_id: "database".into(),
            target: ContentTarget::Body {
                owner,
                key: body.descriptor.key.key.clone(),
            },
        };
        let expected = serde_json::to_vec(&vec![serde_json::json!({
            "reference": reference,
            "byteLength": body.descriptor.byte_length,
            "generation": body.descriptor.generation,
        })])?;
        let payload = &state.entries()[&("members".into(), id.into())].payload;
        assert_eq!(payload.as_ref(), expected.as_slice());
        Ok(payload.clone())
    }

    fn retained_cut(
        with_interaction: bool,
    ) -> Result<(
        Arc<PreparedCurrent>,
        Arc<CurrentState>,
        super::super::timeline::TimelineUpdate,
    )> {
        let mut owner = CurrentOwner::default();
        owner.bind("database".into())?;
        let thread = Thread::placeholder("thread");
        let body = ContentBlock::from_text("retained body");
        let item = ThreadItem::new(
            "text".into(),
            thread.id.clone(),
            "turn".into(),
            1,
            1,
            1,
            2,
            ThreadItemState::Text(ThreadTextItem::new(
                ThreadTextChannel::Final,
                body.text(),
                Vec::new(),
                ThreadContentLifecycle::streaming(),
            )),
        );
        let mut atom = crate::studio::runtime::chat_item::atom(&item);
        atom.lifecycle = ChatAtomLifecycle::Active {
            started: Some(ChatFactPosition {
                effect_seq: 1,
                suborder: 0,
            }),
            status: ChatActiveStatus::Running,
        };
        let source = ChatSourceState {
            source: atom.source.clone(),
            lifecycle: ChatSourceLifecycle::Active,
            started: Some(ChatFactPosition {
                effect_seq: 1,
                suborder: 0,
            }),
            ended: None,
        };
        owner.provenance(vec![source], vec![atom.clone()]);
        let mut state = ThreadSnapshot::default();
        if with_interaction {
            use pl_core::thread::interactions::{
                InteractionRecord, InteractionRequest as CoreInteractionRequest, InteractionState,
            };
            let id = pl_core::tool::opaque::tool_interaction_id("question");
            state.interactions.insert(
                id.clone(),
                InteractionRecord {
                    created_at: 1,
                    updated_at: 1,
                    continuation_id: None,
                    request: CoreInteractionRequest {
                        id,
                        turn_id: "turn".into(),
                        payload: pl_core::context::OpaquePayload::new(
                            "pl.tool.user-input",
                            1,
                            serde_json::to_string(&vec![UserQuestion {
                                id: "choice".into(),
                                header: "Choice".into(),
                                question: "Which choice?".into(),
                                is_other: true,
                                is_secret: false,
                                options: None,
                            }])?,
                        )?,
                    },
                    revision: 1,
                    state: InteractionState::Pending,
                    extension_mutations: vec![],
                },
            );
        }
        let (prepared, snapshot) = owner.freeze(
            &thread,
            &state,
            3,
            [(
                "text".into(),
                BodyKey::Body,
                body,
                1,
                Some(ThreadTextChannel::Final),
            )],
        )?;
        let mut timeline =
            super::super::TimelineProjection::new("database".into(), "generation".into(), 0);
        timeline.observe(&atom, None)?;
        let mut member = atom.clone();
        member.id = "work".into();
        member.source_order = Some(2);
        member.kind = ChatAtomKind::Reasoning;
        member.delivery = ChatDeliveryKind::Foreground;
        member.text_channel = None;
        member.started_at = Some(2);
        member.contents.clear();
        member.payload = None;
        let started = ChatFactPosition {
            effect_seq: 2,
            suborder: 0,
        };
        member.lifecycle = ChatAtomLifecycle::Active {
            started: Some(started),
            status: ChatActiveStatus::Running,
        };
        timeline.observe(&member, None)?;
        member.completion_item_id = Some(member.id.clone());
        member.completion_seq = Some(1);
        member.finished_at = Some(3);
        member.lifecycle = ChatAtomLifecycle::Terminal {
            started: Some(started),
            ended: Some(ChatFactPosition {
                effect_seq: 3,
                suborder: 0,
            }),
            outcome: ChatTerminalOutcome::Completed,
        };
        timeline.complete(member, 1, None)?;
        let update = timeline.take_update()?;
        assert!(!update.current().is_empty() && !update.members().is_empty());
        assert!(!snapshot.contents().is_empty() && !snapshot.source_states().is_empty());
        Ok((prepared, snapshot, update))
    }

    #[test]
    fn prepared_current_items_invalidate_measured_clone_only() -> Result<()> {
        let (prepared, state, update) = retained_cut(false)?;
        assert!(Arc::ptr_eq(
            prepared.frozen_projection(),
            state.frozen_projection()
        ));
        let canonical = serde_json::to_vec(prepared.projection())?;
        let metadata =
            std::mem::size_of::<OnceLock<u64>>() as u64 + 3 * std::mem::size_of::<usize>() as u64;
        let before = canonical.len() as u64 + metadata;
        assert_eq!(prepared.projection_retained_bytes(), before);
        let mut changed = prepared.as_ref().clone();
        assert!(Arc::ptr_eq(
            changed.frozen_projection(),
            prepared.frozen_projection()
        ));
        assert_eq!(changed.projection_retained_bytes(), before);
        changed.replace_projection(
            changed
                .frozen_projection()
                .with_items(update.current().to_vec()),
        );
        assert!(!Arc::ptr_eq(
            changed.frozen_projection(),
            prepared.frozen_projection()
        ));
        let changed_canonical = serde_json::to_vec(changed.projection())?;
        let expected = changed_canonical.len() as u64 + metadata;
        assert!(expected > before);
        assert_eq!(changed.projection_retained_bytes(), expected);
        assert_eq!(serde_json::to_vec(changed.projection())?, changed_canonical);
        assert_eq!(prepared.projection_retained_bytes(), before);
        assert_eq!(serde_json::to_vec(prepared.projection())?, canonical);
        Ok(())
    }

    #[test]
    fn frozen_heads_share_the_owner_cut_without_retaining_prior_bodies() -> Result<()> {
        let mut owner = CurrentOwner::default();
        owner.bind("database".into())?;
        let thread = Thread::placeholder("thread");
        let (mut prepared, state) = owner.freeze(
            &thread,
            &ThreadSnapshot::default(),
            1,
            [(
                "body".into(),
                BodyKey::Body,
                ContentBlock::from_text("old body"),
                1,
                None,
            )],
        )?;
        let (_, _, update) = retained_cut(false)?;
        let before = state.frozen_projection().clone();
        let after = before.with_items(update.current().to_vec());
        Arc::make_mut(&mut prepared).replace_projection(after.clone());
        let published = CurrentState::with_projection(state.clone(), after.clone());
        owner.adopt_timeline_projection(&before, &after);
        let handoff =
            super::super::CurrentHandoff::new(0, before.clone(), after.clone(), Arc::from([]));
        assert!(Arc::ptr_eq(
            prepared.frozen_projection(),
            published.frozen_projection()
        ));
        assert!(Arc::ptr_eq(handoff.after(), published.frozen_projection()));
        assert!(Arc::ptr_eq(
            owner.snapshot().unwrap().frozen_projection(),
            handoff.after()
        ));
        assert!(
            Arc::ptr_eq(&owner.snapshot().unwrap(), &owner.snapshot().unwrap(),),
            "reading the latest current must not rebuild a decorated state"
        );
        let canonical = serde_json::to_vec(before.projection())?;
        let prior_body = Arc::downgrade(state.contents().values().next().unwrap());
        let newer = owner.observe(
            &thread,
            &ThreadSnapshot::default(),
            2,
            [(
                "body".into(),
                BodyKey::Body,
                ContentBlock::from_text("old body plus new progress"),
                1,
                None,
            )],
        )?;
        // A later progress cut keeps its own metadata and body even when an
        // earlier prepared cut finishes its Timeline publication.
        owner.adopt_timeline_projection(&before, &after);
        let latest = owner.snapshot().unwrap();
        assert_eq!(latest.projection().source_effect_seq, 2);
        assert_eq!(latest.projection().items, after.projection().items);
        assert!(Arc::ptr_eq(latest.contents(), newer.contents()));
        assert!(!Arc::ptr_eq(latest.frozen_projection(), handoff.after()));
        assert_eq!(serde_json::to_vec(before.projection())?, canonical);
        assert_eq!(published.projection().source_effect_seq, 1);
        drop(state);
        drop(published);
        drop(prepared); // A reliable prepared cut now also owns the complete replay material.
        assert!(
            prior_body.upgrade().is_some(),
            "observation must not release the last reliable preparation baseline"
        );
        owner.freeze(
            &thread,
            &ThreadSnapshot::default(),
            2,
            [(
                "body".into(),
                BodyKey::Body,
                newer.contents().values().next().unwrap().block.clone(),
                1,
                None,
            )],
        )?;
        assert!(
            prior_body.upgrade().is_none(),
            "handoff heads must not own prior current bodies"
        );
        assert_eq!(handoff.after().projection().source_effect_seq, 1);
        Ok(())
    }

    fn original_metadata_bytes(state: &CurrentState) -> Result<u64> {
        let entries: u64 = state
            .entries()
            .values()
            .map(|entry| entry.payload.len() as u64 + entry.entry_id.len() as u64 + 128)
            .sum();
        let interactions = if state.interactions().is_empty() {
            0
        } else {
            2 * std::mem::size_of::<usize>() as u64
                + state
                    .interactions()
                    .iter()
                    .map(|interaction| {
                        std::mem::size_of::<InteractionRequest>() as u64
                            + super::super::live::interaction_request_bytes(interaction)
                    })
                    .sum::<u64>()
        };
        Ok(entries
            + state.contents().len() as u64 * 256
            + serde_json::to_vec(state.projection())?.len() as u64
            + serde_json::to_vec(state.source_states().as_ref())?.len() as u64
            + interactions)
    }

    #[test]
    fn current_state_items_reuse_or_remeasure_without_replacing_body_owners() -> Result<()> {
        for with_interaction in [false, true] {
            let (_, state, update) = retained_cut(with_interaction)?;
            assert_eq!(!state.interactions().is_empty(), with_interaction);
            let canonical = serde_json::to_vec(state.projection())?;
            let cache = 2 * std::mem::size_of::<OnceLock<u64>>() as u64
                + 3 * std::mem::size_of::<usize>() as u64;
            let before = original_metadata_bytes(&state)? + cache;
            assert_eq!(state.metadata_bytes(), before);
            let same = CurrentState::with_projection(
                state.clone(),
                state
                    .frozen_projection()
                    .with_items(state.projection().items.clone()),
            );
            assert!(Arc::ptr_eq(&same, &state));
            assert_eq!(same.metadata_bytes(), before);
            let changed = CurrentState::with_projection(
                state.clone(),
                state
                    .frozen_projection()
                    .with_items(update.current().to_vec()),
            );
            assert!(!Arc::ptr_eq(&changed, &state));
            let expected = original_metadata_bytes(&changed)? + cache;
            assert!(expected > before);
            assert_eq!(changed.metadata_bytes(), expected);
            assert!(Arc::ptr_eq(changed.contents(), state.contents()));
            assert!(Arc::ptr_eq(changed.entries(), state.entries()));
            assert!(Arc::ptr_eq(changed.by_position(), state.by_position()));
            let old_bodies = state.materialized_contents();
            let new_bodies = changed.materialized_contents();
            for (key, body) in old_bodies.iter() {
                assert!(Arc::ptr_eq(body, &new_bodies[key]));
                assert_eq!(body.data.range(0, 13)?.as_bytes(), b"retained body");
            }
            assert_eq!(state.metadata_bytes(), before);
            assert_eq!(serde_json::to_vec(state.projection())?, canonical);
        }
        Ok(())
    }

    fn original_handoff_bytes(handoff: &super::super::CurrentHandoff) -> Result<u64> {
        let previews: u64 = handoff
            .before()
            .projection()
            .previews
            .iter()
            .map(|preview| preview.id.len() as u64 + 32)
            .sum();
        Ok(
            serde_json::to_vec(handoff.before().projection())?.len() as u64
                + serde_json::to_vec(handoff.after().projection())?.len() as u64
                + serde_json::to_vec(&(
                    handoff.entries().as_ref(),
                    handoff.members().as_ref(),
                    handoff.sources().as_ref(),
                ))?
                .len() as u64
                + previews,
        )
    }

    #[test]
    fn measured_handoff_clone_publication_preserves_retirement_reserve() -> Result<()> {
        let (_, state, update) = retained_cut(false)?;
        let before = state.frozen_projection().clone();
        assert!(!before.projection().previews.is_empty());
        let entries: Arc<[ChatEntry]> = update
            .current()
            .iter()
            .cloned()
            .map(|item| ChatEntry::Item(Box::new(item)))
            .collect::<Vec<_>>()
            .into();
        let handoff =
            super::super::CurrentHandoff::new(1, before.clone(), before.clone(), entries.clone());
        let canonical = serde_json::to_vec(before.projection())?;
        let cache = 3 * std::mem::size_of::<OnceLock<u64>>() as u64
            + 6 * std::mem::size_of::<usize>() as u64;
        let original = original_handoff_bytes(&handoff)? + cache;
        assert_eq!(handoff.retained_bytes(), original);
        let published = handoff.clone().with_publication(
            "generation".into(),
            state.source_states().clone(),
            update.members().to_vec().into(),
            Arc::from([super::super::CurrentRetirement {
                item_id: before.projection().previews[0].id.clone(),
                through: 1,
            }]),
        );
        let expected = original_handoff_bytes(&published)? + cache;
        assert!(expected > original);
        assert_eq!(published.retained_bytes(), expected);
        assert_eq!(published.projection_generation(), "generation");
        assert_eq!(published.main_through(), 1);
        assert_eq!(published.retirements().len(), 1);
        assert_eq!(
            serde_json::to_vec(published.before().projection())?,
            canonical
        );
        assert_eq!(
            serde_json::to_vec(published.after().projection())?,
            canonical
        );
        assert_eq!(
            serde_json::to_vec(published.entries().as_ref())?,
            serde_json::to_vec(entries.as_ref())?
        );
        let mut split = before.projection().clone();
        split.items = update.current().to_vec();
        assert_eq!(published.projection_after_items(0), split);
        assert_eq!(
            published.projection_after_items(entries.len()),
            *before.projection()
        );
        let without_retirements = published.clone().with_publication(
            published.projection_generation().to_owned(),
            published.sources().clone(),
            published.members().clone(),
            Arc::from([]),
        );
        assert_eq!(
            without_retirements.retained_bytes(),
            expected,
            "retirement reserve must not shrink to the filled retirement count"
        );
        assert_eq!(handoff.retained_bytes(), original);
        assert!(handoff.projection_generation().is_empty());
        assert!(handoff.sources().is_empty() && handoff.members().is_empty());
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
                [("part".into(), BodyKey::Body, block.clone(), 1, channel)],
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
            [("active".into(), BodyKey::Body, block.clone(), 1, None)],
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
            [("active".into(), BodyKey::Body, appended.clone(), 1, None)],
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
        let (prepared, _) = owner.freeze(
            &thread,
            &state,
            2,
            [("active".into(), BodyKey::Body, appended.clone(), 1, None)],
        )?;
        assert!(Arc::ptr_eq(&accepted, &prepared.contents[0].content));
        let generation = accepted.descriptor.generation;
        let replacement = owner.observe(
            &thread,
            &state,
            2,
            [(
                "active".into(),
                BodyKey::Body,
                ContentBlock::from_text(&appended.text()),
                1,
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

    #[test]
    fn member_payload_reuse_keeps_multiple_bodies_in_input_order() -> Result<()> {
        let mut owner = CurrentOwner::default();
        owner.bind("database".into())?;
        let thread = Thread::placeholder("thread");
        let state = ThreadSnapshot::default();
        let first = ContentBlock::from_text("first body");
        let second = ContentBlock::from_text("second body");
        let first_key = BodyKey::Host("z-last".into());
        let body_owner = ContentOwner::Item {
            item_id: "shared".into(),
        };
        let (_, single) = owner.freeze(
            &thread,
            &state,
            1,
            [("shared".into(), first_key.clone(), first.clone(), 1, None)],
        )?;
        let single_payload = assert_single_member_payload(&single, "shared")?;
        let first_value = serde_json::json!({
            "reference": ContentRef {
                database_id: "database".into(),
                target: ContentTarget::Body { owner: body_owner.clone(), key: first_key.as_key() },
            },
            "byteLength": first.len() as u64, "generation": 1,
        });
        let second_value = serde_json::json!({
            "reference": ContentRef {
                database_id: "database".into(),
                target: ContentTarget::Body { owner: body_owner, key: BodyKey::Body.as_key() },
            },
            "byteLength": second.len() as u64, "generation": 1,
        });
        let (_, multiple) = owner.freeze(
            &thread,
            &state,
            2,
            [
                ("shared".into(), first_key.clone(), first.clone(), 1, None),
                ("shared".into(), BodyKey::Body, second.clone(), 1, None),
            ],
        )?;
        let key = ("members".into(), "shared".into());
        let payload = &multiple.entries()[&key].payload;
        let expected = serde_json::to_vec(&vec![first_value.clone(), second_value.clone()])?;
        assert_eq!(payload.as_ref(), expected.as_slice());
        assert_ne!(payload.as_ref(), single_payload.as_ref());
        let (_, reversed) = owner.freeze(
            &thread,
            &state,
            3,
            [
                ("shared".into(), BodyKey::Body, second.clone(), 1, None),
                ("shared".into(), first_key.clone(), first.clone(), 1, None),
            ],
        )?;
        let reversed_expected = serde_json::to_vec(&vec![second_value, first_value])?;
        assert_ne!(expected, reversed_expected);
        assert_eq!(
            reversed.entries()[&key].payload.as_ref(),
            reversed_expected.as_slice()
        );
        assert_eq!(
            payload.as_ref(),
            expected.as_slice(),
            "old cut payload was changed"
        );
        let (_, single_again) = owner.freeze(
            &thread,
            &state,
            4,
            [("shared".into(), first_key.clone(), first.clone(), 1, None)],
        )?;
        let single_again_payload = assert_single_member_payload(&single_again, "shared")?;
        assert!(
            !Arc::ptr_eq(&single_payload, &single_again_payload,),
            "the previous multi-body entry cannot qualify for single-body reuse"
        );
        let (_, unchanged) = owner.freeze(
            &thread,
            &state,
            5,
            [("shared".into(), first_key.clone(), first.clone(), 1, None)],
        )?;
        let unchanged_payload = assert_single_member_payload(&unchanged, "shared")?;
        assert!(Arc::ptr_eq(&single_again_payload, &unchanged_payload,));
        let (_, multiple_again) = owner.freeze(
            &thread,
            &state,
            6,
            [
                ("shared".into(), first_key.clone(), first.clone(), 1, None),
                ("shared".into(), BodyKey::Body, second.clone(), 1, None),
            ],
        )?;
        // The lower key's forward neighbor must reject reuse, just as the upper key's
        // backward neighbor did at the earlier multi -> single transition.
        let (_, lower_key) = owner.freeze(
            &thread,
            &state,
            7,
            [("shared".into(), BodyKey::Body, second, 1, None)],
        )?;
        let lower_payload = assert_single_member_payload(&lower_key, "shared")?;
        assert!(!Arc::ptr_eq(
            &multiple_again.entries()[&key].payload,
            &lower_payload
        ));
        let (_, changed_key) = owner.freeze(
            &thread,
            &state,
            8,
            [("shared".into(), first_key.clone(), first.clone(), 1, None)],
        )?;
        let changed_key_payload = assert_single_member_payload(&changed_key, "shared")?;
        assert!(!Arc::ptr_eq(&lower_payload, &changed_key_payload));
        let (_, changed_position) = owner.freeze(
            &thread,
            &state,
            9,
            [("shared".into(), first_key, first, 9, None)],
        )?;
        let changed_position_payload = assert_single_member_payload(&changed_position, "shared")?;
        assert_eq!(
            changed_position_payload.as_ref(),
            changed_key_payload.as_ref()
        );
        assert!(!Arc::ptr_eq(
            &changed_position_payload,
            &changed_key_payload
        ));
        assert_eq!(changed_position.entries()[&key].position, 9);
        Ok(())
    }
}

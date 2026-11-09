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
    activity_entries: Arc<[ActivityEntry]>,
    /// Bounded real source facts from this owner cut, including not-yet-saved ends.
    source_states: Arc<[ChatSourceState]>,
    contents: Arc<BTreeMap<ChatContentKey, Arc<CurrentContent>>>,
    materialized: OnceLock<Arc<ChatContents>>,
    entries: Arc<BTreeMap<(String, String), Arc<CurrentEntryWrite>>>,
    by_position: Arc<CurrentPositionIndex>,
    active_turn: Option<Turn>,
    /// State baseline from this exact owner cut, independent of current collection reads.
    interactions: Arc<[InteractionRequest]>,
    business_bytes: u64,
    metadata_bytes: OnceLock<u64>,
}

#[derive(Default)]
pub(super) struct CurrentOwner {
    database_id: Option<String>,
    activity: super::activity::ActivityProjection,
    state: Option<Arc<CurrentState>>,
    plan_extension_revision: Option<u64>,
    interaction_revision: Option<u64>,
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
            .filter(|(key, _)| {
                plan_revision != self.frozen_plan_revision && plan_key.as_ref() == Some(*key)
            })
            .map(|(_, content)| CurrentContentWrite {
                content: content.content(),
                sealed: true,
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
        for (id, position, block, _ordinal, text_channel) in active {
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
        let cached_business = self
            .state
            .as_ref()
            .filter(|_| self.interaction_revision == Some(state.interaction_collection_revision));
        let mut interactions = Vec::new();
        if cached_business.is_none() {
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
        projection.interactions = Some(CurrentCollectionRef {
            database_id: database_id.clone(),
            collection: "interactions".into(),
            // The original Core owner versions both transfer and resident slices.
            // Reopening or observing progress must never allocate a resource version.
            revision: state.interaction_collection_revision,
        });
        let (entries, by_position, interactions, business_bytes) =
            if let Some(previous) = cached_business {
                (
                    previous.entries.clone(),
                    previous.by_position.clone(),
                    previous.interactions.clone(),
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
                let business_bytes = entries
                    .values()
                    .fold(0u64, |bytes, entry| {
                        bytes
                            .saturating_add(entry.payload.len() as u64)
                            .saturating_add(entry.entry_id.len() as u64)
                            .saturating_add(128)
                    })
                    .saturating_add(interactions.iter().fold(0u64, |bytes, interaction| {
                        bytes
                            .saturating_add(std::mem::size_of::<InteractionRequest>() as u64)
                            .saturating_add(super::live::interaction_request_bytes(interaction))
                    }))
                    .saturating_add(if interactions.is_empty() {
                        0
                    } else {
                        2 * std::mem::size_of::<usize>() as u64
                    });
                (
                    Arc::new(entries),
                    Arc::new(by_position),
                    Arc::from(interactions),
                    business_bytes,
                )
            };
        let mut activity_entries = projection
            .atoms
            .iter()
            .filter(|atom| matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }))
            .filter_map(|atom| {
                super::activity_identity(atom).map(|identity| ActivityEntry {
                    identity,
                    atom: atom.clone(),
                })
            })
            .collect::<Vec<_>>();
        // A background-started receipt ends the foreground obligation, not the
        // task. Its actual scheduler identity remains independently active.
        for task in state.tasks.values().filter(|task| {
            task.status == pl_core::thread::task::TaskStatus::Running
                && task.acknowledgement.is_some()
        }) {
            let call_id = task.call_id.clone();
            activity_entries.retain(|entry| {
                !matches!(&entry.identity,
                ActivityIdentity::ForegroundTool { call_id: foreground } if foreground == &call_id)
            });
            activity_entries.push(ActivityEntry {
                identity: ActivityIdentity::BackgroundTool {
                    call_id: call_id.clone(),
                },
                atom: ChatAtom {
                    id: super::order::tool_id(&call_id),
                    completion_item_id: None,
                    completion_seq: None,
                    source: ChatSourceId::ForegroundTurn {
                        turn_id: task.turn_id.clone(),
                    },
                    source_state: None,
                    source_order: task.started_sequence,
                    kind: ChatAtomKind::ToolCall,
                    delivery: ChatDeliveryKind::Independent,
                    lifecycle: ChatAtomLifecycle::Active {
                        started: None,
                        status: ChatActiveStatus::Running,
                    },
                    turn_id: Some(task.turn_id.clone()),
                    attempt_id: None,
                    tool: Some(ChatToolIdentity {
                        call_id,
                        name: task.tool_id.clone(),
                    }),
                    wait: None,
                    text_channel: None,
                    started_at: None,
                    finished_at: None,
                    content_present: None,
                    contents: Vec::new(),
                    payload: None,
                },
            });
        }
        let snapshot = Arc::new(CurrentState {
            projection: FrozenCurrentProjection::new(projection),
            activity_entries: activity_entries.into(),
            source_states: self.sources.clone(),
            contents: Arc::new(contents),
            materialized: OnceLock::new(),
            entries,
            by_position,
            active_turn,
            interactions,
            business_bytes,
            metadata_bytes: OnceLock::new(),
        });
        self.state = Some(snapshot.clone());
        self.plan_extension_revision = plan_record.map(|record| record.revision);
        self.interaction_revision = Some(state.interaction_collection_revision);
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
    pub fn business_refs(&self) -> ThreadBusinessRefs {
        project_business_refs(self.projection())
    }
    /// Qualify references against the exact Core business slice used by a State
    /// baseline. Unrelated execution/token revisions may differ; Plan content
    /// and the full typed interaction list with its resource revision may not.
    pub(in crate::studio) fn business_refs_at(
        &self,
        thread_id: &str,
        state: &ThreadSnapshot,
    ) -> Result<ThreadBusinessRefs> {
        ensure!(
            self.projection()
                .interactions
                .as_ref()
                .is_some_and(|reference| {
                    reference.revision == state.interaction_collection_revision
                }),
            pl_core::chat::ChatError::StaleContent
        );
        let interactions = state
            .permissions
            .keys()
            .chain(state.interactions.keys())
            .map(|id| crate::thread_assembler::project_thread_interaction(thread_id, id, state))
            .collect::<std::result::Result<Vec<_>, _>>()?
            .into_iter()
            .flatten()
            .collect::<Vec<_>>();
        ensure!(
            interactions.as_slice() == self.interactions.as_ref(),
            pl_core::chat::ChatError::StaleContent
        );
        let plan = state
            .extensions
            .get(crate::plan_tool::PLAN_EXTENSION)
            .map(|record| crate::plan_tool::decode_plan_state(&record.payload))
            .transpose()?;
        match (plan, self.projection().plan.as_ref()) {
            (None, None) => {}
            (Some(plan), Some(head)) => {
                ensure!(
                    plan.revision == head.revision && plan.state == head.phase,
                    pl_core::chat::ChatError::StaleContent
                );
                match (plan.document.as_ref(), head.document.as_ref()) {
                    (None, None) => {}
                    (Some(document), Some(reference)) => {
                        let ContentTarget::Body { owner, key } = &reference.target else {
                            anyhow::bail!(pl_core::chat::ChatError::StaleContent);
                        };
                        let key = ChatContentKey {
                            owner: content_owner_key(owner)?,
                            key: key.clone(),
                        };
                        let content = self
                            .contents
                            .get(&key)
                            .ok_or(pl_core::chat::ChatError::StaleContent)?;
                        ensure!(
                            ContentBlock::text_eq(
                                &content.block,
                                &ContentBlock::from_text(&document.markdown)
                            ),
                            pl_core::chat::ChatError::StaleContent
                        );
                    }
                    _ => anyhow::bail!(pl_core::chat::ChatError::StaleContent),
                }
            }
            _ => anyhow::bail!(pl_core::chat::ChatError::StaleContent),
        }
        Ok(self.business_refs())
    }
    pub fn activity_entries(&self) -> &Arc<[ActivityEntry]> {
        &self.activity_entries
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
            activity_entries: state.activity_entries.clone(),
            source_states: state.source_states.clone(),
            contents: state.contents.clone(),
            materialized: OnceLock::new(),
            entries: state.entries.clone(),
            by_position: state.by_position.clone(),
            active_turn: state.active_turn.clone(),
            interactions: state.interactions.clone(),
            business_bytes: state.business_bytes,
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
            let entries = self
                .business_bytes
                .saturating_add((self.contents.len() as u64).saturating_mul(256));
            let entries = entries
                .saturating_add(std::mem::size_of::<OnceLock<u64>>() as u64)
                .saturating_add(self.projection.retained_bytes())
                .saturating_add(
                    serde_json::to_vec(self.source_states.as_ref())
                        .map_or(u64::MAX, |bytes| bytes.len() as u64),
                )
                .saturating_add(
                    serde_json::to_vec(self.activity_entries.as_ref())
                        .map_or(u64::MAX, |bytes| bytes.len() as u64),
                );
            entries
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

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
        let (prepared, frozen) = owner.freeze(
            &thread,
            &state,
            2,
            [("active".into(), BodyKey::Body, appended.clone(), 1, None)],
        )?;
        assert!(
            prepared.contents.is_empty(),
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
mod business_tests {
    use super::*;
    fn state(version: u64, text: &str) -> Result<ThreadSnapshot> {
        let plan = AgentSessionPlanState {
            revision: version,
            state: AgentSessionPlanPhase::Approved,
            document: Some(AgentSessionPlanDocument {
                version,
                markdown: text.into(),
                content_hash: crate::canonical_content_hash(text.as_bytes()),
            }),
            ..Default::default()
        };
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
        let references = first.business_refs_at(&thread.id, &old)?;
        assert_eq!(references.interactions.as_ref().unwrap().revision, 17);
        let page = super::super::current_page(
            &first,
            references.interactions.as_ref().unwrap(),
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
                1,
                None,
            )],
        )?;
        assert_eq!(progress.business_refs(), references);
        assert!(Arc::ptr_eq(&first.entries, &progress.entries));
        assert!(Arc::ptr_eq(&first.by_position, &progress.by_position));
        assert!(Arc::ptr_eq(&first.interactions, &progress.interactions));
        assert!(progress.projection().collections.is_empty());
        let new = state(4, "# New plan\n\nRevised steps")?;
        let next = owner.observe(&thread, &new, 11, [])?;
        assert_eq!(next.business_refs().interactions, references.interactions);
        assert!(Arc::ptr_eq(&first.entries, &next.entries));
        assert!(Arc::ptr_eq(&first.interactions, &next.interactions));
        assert_ne!(next.business_refs().plan, references.plan);
        assert!(
            next.business_refs_at(&thread.id, &old).is_err(),
            "mixed-cut State refs accepted"
        );
        let old_ref = references.plan.unwrap().document.unwrap();
        let ContentTarget::Body {
            owner: old_owner,
            key,
        } = old_ref.target
        else {
            panic!("plan body");
        };
        assert!(
            !next.contents().contains_key(&ChatContentKey {
                owner: content_owner_key(&old_owner)?,
                key
            }),
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
            let id = pl_core::tool::opaque::tool_interaction_id(id);
            before.interactions.insert(
                id.clone(),
                InteractionRecord {
                    created_at: 1,
                    updated_at: 1,
                    continuation_id: None,
                    revision: 1,
                    state: InteractionState::Pending,
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
        assert_eq!(
            first
                .business_refs()
                .interactions
                .as_ref()
                .unwrap()
                .revision,
            41
        );

        let mut after = before.clone();
        after
            .interactions
            .remove(&pl_core::tool::opaque::tool_interaction_id("first"));
        after.interaction_collection_revision = 42;
        let next = owner.observe(&thread, &after, 4, [])?;
        let cold = CurrentState::cold("interaction-db".into(), thread.id.clone(), 4, &after)?;
        assert_eq!(next.business_refs(), cold.business_refs());
        assert_eq!(
            next.business_refs_at(&thread.id, &after)?
                .interactions
                .unwrap()
                .revision,
            42
        );
        assert!(next.business_refs_at(&thread.id, &before).is_err());

        // A later A -> B -> A can have the same members but a different owner version.
        let mut later = after.clone();
        later.interaction_collection_revision = 44;
        assert!(next.business_refs_at(&thread.id, &later).is_err());
        // The full list remains an independent qualification, not just the numeric version.
        let mut wrong_members = before;
        wrong_members.interaction_collection_revision = 42;
        assert!(next.business_refs_at(&thread.id, &wrong_members).is_err());
        Ok(())
    }
}

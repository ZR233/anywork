//! Effect-local product current and its read owners. No completed-history mirror lives here.

use crate::studio::storage::history::conversation::current::{
    CurrentContentWrite, CurrentEntryChange, CurrentEntryWrite, PreparedCurrent,
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
    collections::{BTreeMap, BTreeSet},
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

#[derive(Debug)]
pub(in crate::studio) struct CurrentState {
    pub projection: CurrentProjection,
    pub contents: Arc<BTreeMap<ChatContentKey, Arc<CurrentContent>>>,
    materialized: OnceLock<Arc<ChatContents>>,
    pub entries: Arc<BTreeMap<(String, String), Arc<CurrentEntryWrite>>>,
    pub by_position: Arc<BTreeMap<(String, i64, String), Arc<CurrentEntryWrite>>>,
    pub active_turn: Option<Turn>,
    /// State baseline from this exact owner cut, independent of current collection reads.
    pub interactions: Arc<[InteractionRequest]>,
}

#[derive(Default)]
pub(super) struct CurrentOwner {
    database_id: Option<String>,
    activity: super::activity::ActivityProjection,
    state: Option<Arc<CurrentState>>,
    plan_extension_revision: Option<u64>,
    next_position: i64,
    prepared_collections: BTreeMap<String, PreparedCollection>,
}
struct PreparedCollection {
    revision: u64,
    ids: BTreeSet<String>,
}

impl CurrentOwner {
    pub(super) fn activity(&self) -> Option<ThreadActivity> {
        self.activity.current().cloned()
    }
    pub(super) fn retained_bytes(&self) -> u64 {
        self.activity
            .retained_bytes()
            .saturating_add(
                self.state
                    .as_ref()
                    .map_or(0, |state| state.metadata_bytes()),
            )
            .saturating_add(
                self.prepared_collections
                    .values()
                    .flat_map(|collection| &collection.ids)
                    .map(|id| id.len() as u64 + 64)
                    .sum::<u64>(),
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
        let mut changes = Vec::new();
        for reference in &snapshot.projection.collections {
            let previous = self.prepared_collections.get(&reference.collection);
            if previous.is_some_and(|previous| previous.revision == reference.revision) {
                continue;
            }
            let entries = snapshot
                .entries
                .iter()
                .filter(|((collection, _), _)| collection == &reference.collection)
                .map(|(_, entry)| entry)
                .collect::<Vec<_>>();
            let ids = entries
                .iter()
                .map(|entry| entry.entry_id.clone())
                .collect::<BTreeSet<_>>();
            if let Some(previous) = previous {
                changes.extend(previous.ids.difference(&ids).map(|id| {
                    CurrentEntryChange::Remove {
                        collection: reference.collection.clone(),
                        entry_id: id.clone(),
                    }
                }));
            } else {
                changes.push(CurrentEntryChange::Clear {
                    collection: reference.collection.clone(),
                });
            }
            // Every entry body is qualified by this collection revision. Retag unchanged entries
            // as well, while comparing against the last reliable preparation, not token progress.
            changes.extend(
                entries
                    .into_iter()
                    .map(|entry| CurrentEntryChange::Put(entry.as_ref().clone())),
            );
            self.prepared_collections.insert(
                reference.collection.clone(),
                PreparedCollection {
                    revision: reference.revision,
                    ids,
                },
            );
        }
        let plan_owner = snapshot
            .projection
            .plan
            .as_ref()
            .and_then(|plan| plan.document.as_ref())
            .and_then(|reference| match &reference.target {
                ContentTarget::Body { owner, .. } => Some(content_owner_key(owner)),
                _ => None,
            })
            .transpose()?;
        let writes = snapshot
            .contents
            .values()
            .map(|content| CurrentContentWrite {
                content: content.content(),
                sealed: plan_owner.as_ref() == Some(&content.descriptor.key.owner),
            })
            .collect::<Vec<_>>();
        Ok((
            Arc::new(PreparedCurrent {
                projection: snapshot.projection.clone(),
                changes: changes.into(),
                contents: writes.into(),
            }),
            snapshot,
        ))
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
        let active_turn = super::project_active_turn(&thread.id, state, thread.updated_at)?;
        projection.active_turn = active_turn
            .as_ref()
            .and_then(|turn| turn.phase().map(|phase| (turn, phase)))
            .map(|(turn, phase)| -> Result<_> {
                Ok(CurrentTurnHead {
                    id: turn.id.clone(),
                    phase,
                    children_parent_id: Some(
                        pl_core::chat::ChatKey::new("turn", &turn.id)?
                            .as_str()
                            .to_owned(),
                    ),
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
        let mut members: BTreeMap<String, (u64, Vec<serde_json::Value>)> = BTreeMap::new();
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
            members.entry(id.clone()).or_insert_with(||(ordinal,Vec::new())).1.push(serde_json::json!({
                "reference":reference,"byteLength":content.descriptor.byte_length,"generation":content.descriptor.generation
            }));
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
                                .projection
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
            let entry = CurrentEntryWrite {
                collection: "members".into(),
                position: i64::try_from(position)?,
                entry_id: id,
                payload: Arc::from(serde_json::to_vec(&bodies)?),
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
            projection.plan = previous.projection.plan.clone();
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
                        .projection
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
            projection: projection.clone(),
            contents: Arc::new(contents),
            materialized: OnceLock::new(),
            entries: Arc::new(entries),
            by_position: Arc::new(by_position),
            active_turn,
            interactions: interactions.into(),
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
        let entries = self.entries.values().fold(
            (self.contents.len() as u64).saturating_mul(256),
            |bytes, entry| {
                bytes
                    .saturating_add(entry.payload.len() as u64)
                    .saturating_add(entry.entry_id.len() as u64)
                    .saturating_add(128)
            },
        );
        self.interactions.iter().fold(
            entries.saturating_add(2 * std::mem::size_of::<usize>() as u64),
            |bytes, interaction| {
                bytes
                    .saturating_add(std::mem::size_of::<InteractionRequest>() as u64)
                    .saturating_add(super::live::interaction_request_bytes(interaction))
            },
        )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reliable_collections_include_collapsed_progress_and_retag_unchanged_members() -> Result<()> {
        let mut owner = CurrentOwner::default();
        owner.bind("database".into())?;
        let thread = Thread::placeholder("thread");
        let state = ThreadSnapshot::default();
        let a = ContentBlock::from_text("first");
        let b = ContentBlock::from_text("unchanged");
        let (_, first) = owner.freeze(
            &thread,
            &state,
            1,
            [
                ("a".into(), BodyKey::Body, a.clone(), 1, None),
                ("b".into(), BodyKey::Body, b.clone(), 2, None),
            ],
        )?;
        let a = ContentBlock::append(&a, " progress");
        let active = [
            ("a".into(), BodyKey::Body, a, 1, None),
            ("b".into(), BodyKey::Body, b.clone(), 2, None),
        ];
        let progress = owner.observe(&thread, &state, 1, active.clone())?;
        let (prepared, next) = owner.freeze(&thread, &state, 2, active.clone())?;
        let members_revision = |snapshot: &CurrentState| {
            snapshot
                .projection
                .collections
                .iter()
                .find(|reference| reference.collection == "members")
                .unwrap()
                .revision
        };
        assert!(members_revision(&next) > members_revision(&first));
        assert_eq!(members_revision(&next), members_revision(&progress));
        let unchanged = ("members".into(), "b".into());
        assert!(Arc::ptr_eq(
            &first.entries[&unchanged],
            &next.entries[&unchanged]
        ));
        let puts = prepared
            .changes
            .iter()
            .filter_map(|change| match change {
                CurrentEntryChange::Put(entry) if entry.collection == "members" => {
                    Some((entry.entry_id.as_str(), entry.payload.as_ref()))
                }
                _ => None,
            })
            .collect::<BTreeMap<_, _>>();
        assert_eq!(puts.len(), 2, "the new revision must retag every member");
        assert_eq!(
            puts["a"],
            next.entries[&("members".into(), "a".into())]
                .payload
                .as_ref()
        );
        assert_eq!(puts["b"], first.entries[&unchanged].payload.as_ref());
        let (unchanged, _) = owner.freeze(&thread, &state, 3, active)?;
        assert!(unchanged.changes.is_empty());

        let remaining = [("b".into(), BodyKey::Body, b, 2, None)];
        owner.observe(&thread, &state, 3, remaining.clone())?;
        let (prepared, _) = owner.freeze(&thread, &state, 4, remaining)?;
        assert!(prepared.changes.iter().any(|change| matches!(
            change, CurrentEntryChange::Remove { collection, entry_id }
            if collection == "members" && entry_id == "a"
        )));
        assert!(prepared.changes.iter().any(|change| matches!(
            change, CurrentEntryChange::Put(entry)
            if entry.collection == "members" && entry.entry_id == "b"
        )));
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
            let preview = &current.projection.previews[0];
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
            let wire = serde_json::to_value(&current.projection)?;
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
                current.projection
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
            first.projection.previews[0].text,
            next.projection.previews[0].text
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
    fn current_content_appends_replace_generation_and_seal_transfers_the_same_owner() -> Result<()>
    {
        let thread = Thread::placeholder("thread");
        let state = ThreadSnapshot::default();
        let mut owner = CurrentOwner::default();
        owner.bind("database".into())?;
        let prefix = ContentBlock::from_text(&"汉📖".repeat(2048));
        let (_, first) = owner.freeze(
            &thread,
            &state,
            7,
            [("part".into(), BodyKey::Body, prefix.clone(), 1, None)],
        )?;
        let reference = first.projection.previews[0].reference.clone();
        assert!(
            matches!(&reference.target,ContentTarget::Body { owner:ContentOwner::Item { item_id },.. } if item_id=="part")
        );
        let first_content = first.contents.values().next().unwrap().content();
        let ContentData::Text(text) = &first_content.data else {
            panic!("text owner");
        };
        assert!(Arc::ptr_eq(text.block(), &prefix));
        let appended = ContentBlock::append(&prefix, "继续");
        let (prepared, next) = owner.freeze(
            &thread,
            &state,
            8,
            [("part".into(), BodyKey::Body, appended.clone(), 1, None)],
        )?;
        let next_content = next.contents.values().next().unwrap().content();
        assert_eq!(
            next_content.descriptor.generation,
            first_content.descriptor.generation
        );
        assert_eq!(next.projection.previews[0].reference, reference);
        assert_eq!(prepared.projection.source_effect_seq, 8);
        assert_eq!(
            first.projection.source_effect_seq, 7,
            "later current mutated the frozen earlier cut"
        );
        let item = ThreadItem::new(
            "part".into(),
            "thread".into(),
            "turn".into(),
            1,
            1,
            1,
            2,
            ThreadItemState::Text(ThreadTextItem::new(
                ThreadTextChannel::Final,
                appended.text(),
                Vec::new(),
                ThreadContentLifecycle::completed(2),
            )),
        );
        let completed = crate::studio::runtime::chat_item::completion_draft_reusing(
            &item,
            9,
            "database",
            &next.materialized_contents(),
        )?;
        assert!(
            Arc::ptr_eq(completed.contents.values().next().unwrap(), &next_content),
            "seal rebuilt an already owned body"
        );
        let (_, retired) = owner.freeze(&thread, &state, 9, [])?;
        assert!(retired.contents.is_empty());
        assert!(retired.projection.previews.is_empty());
        assert_eq!(
            next_content
                .data
                .range((prefix.len() - 7) as u64, 13)?
                .as_bytes(),
            "汉📖继续".as_bytes()
        );
        let (_, replacement) = owner.freeze(
            &thread,
            &state,
            10,
            [("other".into(), BodyKey::Body, prefix.clone(), 2, None)],
        )?;
        let generation = replacement
            .contents
            .values()
            .next()
            .unwrap()
            .descriptor
            .generation;
        let (_, replacement) = owner.freeze(
            &thread,
            &state,
            11,
            [(
                "other".into(),
                BodyKey::Body,
                ContentBlock::from_text("不同"),
                2,
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
            generation + 1
        );
        Ok(())
    }
}

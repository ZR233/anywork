//! Incremental display ownership. Only reliable, admitted facts enter this fold.
use std::{
    collections::{BTreeMap, BTreeSet, HashMap, VecDeque},
    sync::{Arc, Mutex},
};

use anyhow::{Context, Result, ensure};
use pl_core::chat::{ChatContent, ChatContentKey, ChatItem};
use pl_protocol::{
    ChatActiveStatus, ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatContentRole, ChatDeliveryKind,
    ChatFactPosition, ChatSourceId, ChatSourceLifecycle, ChatSourceState, ChatTerminalOutcome,
    ContentRef, ContentTarget, DisplayBlock, DisplayBlockBody, DisplayBlockRef,
    DisplayContentSource, DisplayMemberHead, DisplayRecord, PayloadData,
};
use serde::{Deserialize, Serialize};

#[cfg(test)]
mod cost;
#[cfg(test)]
use cost::ObservedMap as PresentationMap;
#[cfg(not(test))]
type PresentationMap<K, V> = BTreeMap<K, V>;

pub(in crate::studio) type PresentationHandle = Arc<Mutex<PresentationState>>;

/// Persisted small header, never an array of member identities or bodies.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::studio) struct DisplayHeader {
    pub version: u32,
    pub legacy: bool,
    pub id: String,
    pub source: ChatSourceId,
    pub block_order: u64,
    pub history_pos: Option<u64>,
    pub boundary: Option<ChatFactPosition>,
    pub sealed: bool,
    pub unfinished: u64,
    pub next_member: u64,
    pub revision: u64,
    pub skip_display: bool,
    pub active_since: Option<i64>,
    pub duration_known: bool,
    pub body: DisplayBlockBody,
}

impl DisplayHeader {
    pub fn frozen(&self) -> Option<DisplayBlock> {
        Some(DisplayBlock {
            id: self.id.clone(),
            history_pos: self.history_pos?,
            body: self.body.clone(),
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::studio) struct DisplayMemberWrite {
    pub block_id: String,
    pub association_key: String,
    pub terminal: bool,
    pub head: DisplayMemberHead,
}

#[derive(Clone)]
pub(in crate::studio) struct ObservationInput {
    pub atom: ChatAtom,
    pub state: pl_protocol::ThreadItemState,
    pub thread_id: String,
    pub contents: Vec<Arc<ChatContent>>,
}

#[cfg(test)]
impl ObservationInput {
    pub fn for_test(atom: ChatAtom, contents: Vec<Arc<ChatContent>>) -> Self {
        use pl_protocol::*;
        let state = if atom.kind == ChatAtomKind::ToolCall {
            ThreadItemState::Tool(ThreadToolItem::new(
                ThreadToolInvocation::new(atom.id.clone(), "test".into(), String::new()),
                ThreadToolState::Running(RunningThreadTool::new(String::new())),
            ))
        } else {
            ThreadItemState::Thinking(ThreadThinkingItem::new(
                Vec::new(),
                Vec::new(),
                ThreadContentLifecycle::streaming(),
            ))
        };
        Self {
            atom,
            state,
            thread_id: "test-thread".into(),
            contents,
        }
    }
}

#[derive(Debug, Clone, Serialize)]
pub(in crate::studio) struct DisplayBlockWrite {
    pub header: Arc<DisplayHeader>,
    /// This very Arc is also indexed by the owner's pending prefix.
    pub published: Option<Arc<DisplayBlock>>,
}

#[derive(Debug, Clone, Serialize)]
pub(in crate::studio) struct PreparedDisplayDelta {
    pub effect_seq: u64,
    pub blocks: Vec<DisplayBlockWrite>,
    pub members: Vec<Arc<DisplayMemberWrite>>,
    pub remove_empty: Vec<Arc<DisplayHeader>>,
    pub published_through: u64,
    #[serde(skip)]
    pub contents: Vec<Arc<ChatContent>>,
    #[serde(skip)]
    pub retained_bytes: u64,
}

impl PreparedDisplayDelta {
    pub fn digest(&self) -> Result<String> {
        use sha2::{Digest, Sha256};
        let mut hash = Sha256::new();
        hash.update(serde_json::to_vec(self)?);
        for content in &self.contents {
            let d = &content.descriptor;
            hash.update(serde_json::to_vec(&(
                d.key.owner.as_str(),
                &d.key.key,
                d.generation,
                d.byte_length,
                &d.media_type,
            ))?);
            let mut offset = 0;
            while offset < content.data.len() {
                let bytes = content.data.range(offset as u64, 64 * 1024)?;
                hash.update(bytes.as_bytes());
                offset += bytes.as_bytes().len();
            }
        }
        Ok(hex::encode(hash.finalize()))
    }
}

#[derive(Default)]
struct SourceLane {
    open_work: Option<u64>,
    pending_order: VecDeque<u64>,
}

/// An explicitly bounded capture from one short owner lock.
pub(in crate::studio) struct PresentationCut {
    pub published: u64,
    pub durable: u64,
    pub revision: u64,
    pub open: Vec<Arc<DisplayHeader>>,
    pub pending: Vec<Arc<DisplayBlock>>,
}

pub(in crate::studio) struct DisplayMemberCut {
    pub header: Arc<DisplayHeader>,
    pub overlay: Vec<Arc<DisplayMemberWrite>>,
    pub complete: bool,
}

#[derive(Default)]
pub(in crate::studio) struct PresentationState {
    database: String,
    lanes: HashMap<ChatSourceId, SourceLane>,
    blocks: PresentationMap<u64, Arc<DisplayHeader>>,
    frozen_headers: PresentationMap<u64, Arc<DisplayHeader>>,
    sparse: BTreeSet<u64>,
    retired: BTreeMap<u64, (u64, u64)>, // history_pos -> (effect, block_order)
    by_id: HashMap<String, u64>,
    members: PresentationMap<(u64, u64), Arc<DisplayMemberWrite>>,
    member_locations: HashMap<String, (u64, u64)>,
    location_keys: HashMap<u64, BTreeSet<String>>,
    unfinished_members: BTreeSet<(u64, u64)>,
    observations: BTreeMap<ChatContentKey, (u64, Arc<ChatContent>)>,
    pending: BTreeMap<u64, Arc<DisplayBlock>>,
    published: u64,
    durable: u64,
    revision: u64,
    member_change: u64,
    next_order: u64,
    applied_effect: u64,
    changes: Option<tokio::sync::watch::Sender<u64>>,
    retained: u64,
}

// JSON's tuple encoding is unambiguous, including the typed source discriminant.
pub(in crate::studio) fn member_key(atom: &ChatAtom) -> Result<String> {
    Ok(serde_json::to_string(&(
        &atom.source,
        &atom.id,
        if matches!(atom.source, ChatSourceId::BackgroundResult { .. }) {
            "background-result"
        } else {
            "foreground-obligation"
        },
    ))?)
}

pub(in crate::studio) fn display_member_key(block: &str, atom: &ChatAtom) -> Result<String> {
    Ok(serde_json::to_string(&(
        "display-member-v2",
        block,
        evidence(atom),
        member_key(atom)?,
    ))?)
}

pub(in crate::studio) fn record(
    atom: ChatAtom,
    start_fact: Option<ChatFactPosition>,
) -> DisplayRecord {
    let end_fact = match atom.lifecycle {
        ChatAtomLifecycle::Terminal { ended, .. } => ended,
        ChatAtomLifecycle::Active { .. } => None,
    };
    let content_source = atom.completion_item_id.as_ref().map_or_else(
        || {
            if matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. }) {
                DisplayContentSource::FrozenObservation {
                    captured_at: atom.finished_at,
                    available: true,
                }
            } else {
                DisplayContentSource::CurrentAtom
            }
        },
        |id| DisplayContentSource::CompletedOriginal {
            completion_id: id.clone(),
        },
    );
    DisplayRecord {
        atom,
        start_fact,
        end_fact,
        content_source,
    }
}

pub(in crate::studio) fn lightweight(mut atom: ChatAtom, database: &str) -> ChatAtom {
    if let Some(payload) = &atom.payload {
        let length = match payload {
            PayloadData::Inline { bytes } => bytes.len() as u64,
            PayloadData::Deferred { byte_length, .. } => *byte_length,
        };
        atom.payload = atom
            .completion_item_id
            .as_ref()
            .map(|id| PayloadData::Deferred {
                reference: ContentRef {
                    database_id: database.into(),
                    target: ContentTarget::ItemPayload {
                        item_id: id.clone(),
                    },
                },
                byte_length: length,
            });
    }
    atom
}

pub(in crate::studio) fn work(atom: &ChatAtom) -> bool {
    // Background provenance is independent delivery, not an independent output contract.
    // Its original producer identity survives that delivery override. Do not inspect labels.
    let background_tool = atom.kind == ChatAtomKind::ToolCall
        && matches!(atom.source, ChatSourceId::BackgroundResult { .. })
        && atom
            .tool
            .as_ref()
            .is_some_and(|tool| tool.name != pl_tool::file_display::TOOL_SHOW_FILES);
    background_tool
        || (matches!(
            atom.kind,
            ChatAtomKind::Reasoning
                | ChatAtomKind::ToolCall
                | ChatAtomKind::FileChange
                | ChatAtomKind::Skill
        ) && matches!(atom.source, ChatSourceId::ForegroundTurn { .. })
            && atom.delivery != ChatDeliveryKind::Independent)
}

fn hidden(atom: &ChatAtom) -> bool {
    atom.kind != ChatAtomKind::Text
        && matches!(
            crate::studio::runtime::chat_item::native_read_hint_v1("conversation", atom),
            pl_core::chat::ChatReadHint::Hidden
        )
}

fn evidence(atom: &ChatAtom) -> Option<ChatFactPosition> {
    match atom.lifecycle {
        ChatAtomLifecycle::Active { started, .. } => started,
        ChatAtomLifecycle::Terminal { ended, started, .. } => ended.or(started),
    }
}

fn bytes<T: Serialize>(value: &T) -> Result<u64> {
    Ok(serde_json::to_vec(value)?.len() as u64 + 192)
}

impl PresentationState {
    pub fn accepts_update(&self, atom: &ChatAtom) -> bool {
        member_key(atom)
            .ok()
            .is_some_and(|key| self.member_locations.contains_key(&key))
    }
    pub fn observation_content(&self, key: &ChatContentKey) -> Option<Arc<ChatContent>> {
        self.observations
            .get(key)
            .map(|(_, content)| content.clone())
    }
    pub fn bind(&mut self, database: &str) -> Result<()> {
        ensure!(
            !database.is_empty() && (self.database.is_empty() || self.database == database),
            "display database identity changed"
        );
        self.database = database.into();
        Ok(())
    }

    pub fn retained_bytes(&self) -> u64 {
        self.retained
    }

    pub fn subscribe_members(&mut self) -> tokio::sync::watch::Receiver<u64> {
        self.changes
            .get_or_insert_with(|| tokio::sync::watch::channel(self.member_change).0)
            .subscribe()
    }

    pub fn member_cut(
        &self,
        block_id: &str,
        before: Option<u64>,
        limit: usize,
    ) -> Option<DisplayMemberCut> {
        let order = *self.by_id.get(block_id)?;
        let header = self
            .blocks
            .get(&order)
            .or_else(|| self.frozen_headers.get(&order))?
            .clone();
        Some(DisplayMemberCut {
            header,
            overlay: self.member_heads(block_id, before, limit),
            complete: !self.sparse.contains(&order),
        })
    }

    pub fn capture(
        &self,
        before_order: Option<u64>,
        live_limit: usize,
        after_pos: u64,
        pending_limit: usize,
    ) -> PresentationCut {
        let mut open = self
            .blocks
            .range(..before_order.unwrap_or(u64::MAX))
            .rev()
            .take(live_limit)
            .map(|(_, h)| h.clone())
            .collect::<Vec<_>>();
        open.reverse();
        PresentationCut {
            published: self.published,
            durable: self.durable,
            revision: self.revision,
            open,
            pending: self
                .pending
                .range((
                    std::ops::Bound::Excluded(after_pos),
                    std::ops::Bound::Unbounded,
                ))
                .take(pending_limit)
                .map(|(_, h)| h.clone())
                .collect(),
        }
    }

    /// Resident overlay for a requested block/window. A restored block's saved terminal rows
    /// remain in SQLite; the consumer merges this bounded overlay with that captured durable cut.
    pub fn member_heads(
        &self,
        block_id: &str,
        before: Option<u64>,
        limit: usize,
    ) -> Vec<Arc<DisplayMemberWrite>> {
        let Some(order) = self.by_id.get(block_id).copied() else {
            return Vec::new();
        };
        let mut page = self
            .members
            .range((order, 0)..(order, before.unwrap_or(u64::MAX)))
            .rev()
            .take(limit)
            .map(|(_, m)| m.clone())
            .collect::<Vec<_>>();
        page.reverse();
        page
    }

    pub fn restore(
        &mut self,
        database: &str,
        published: u64,
        next_order: u64,
        effect: u64,
        headers: Vec<DisplayHeader>,
        unfinished: Vec<DisplayMemberWrite>,
    ) -> Result<()> {
        ensure!(
            self.blocks.is_empty() && self.members.is_empty() && self.applied_effect == 0,
            "display owner already restored"
        );
        self.bind(database)?;
        self.published = published;
        self.durable = published;
        self.next_order = next_order;
        self.applied_effect = effect;
        for header in headers {
            ensure!(
                header.history_pos.is_none() && header.version == 2,
                "invalid open display header"
            );
            let lane = self.lanes.entry(header.source.clone()).or_default();
            lane.pending_order.push_back(header.block_order);
            if !header.sealed && matches!(header.body, DisplayBlockBody::Work { .. }) {
                ensure!(
                    lane.open_work.replace(header.block_order).is_none(),
                    "multiple open work blocks"
                );
            }
            self.retained += bytes(&header)?;
            self.sparse.insert(header.block_order);
            self.by_id.insert(header.id.clone(), header.block_order);
            self.blocks.insert(header.block_order, Arc::new(header));
        }
        for member in unfinished {
            ensure!(
                !member.terminal,
                "restore requested terminal display member"
            );
            let order = *self
                .by_id
                .get(&member.block_id)
                .context("unfinished member has no block")?;
            ensure!(
                !self.blocks[&order].sealed,
                "sealed block cannot restore update qualification"
            );
            self.retained += bytes(&member)?;
            self.location_keys
                .entry(order)
                .or_default()
                .insert(member.association_key.clone());
            self.unfinished_members
                .insert((order, member.head.member_order));
            ensure!(
                self.member_locations
                    .insert(
                        member.association_key.clone(),
                        (order, member.head.member_order)
                    )
                    .is_none(),
                "duplicate unfinished display member"
            );
            self.members
                .insert((order, member.head.member_order), Arc::new(member));
        }
        Ok(())
    }

    pub fn confirm(&mut self, effect: u64) {
        self.observations.retain(|_, (at, content)| {
            if *at <= effect {
                self.retained = self
                    .retained
                    .saturating_sub(content.data.len() as u64 + 192);
                false
            } else {
                true
            }
        });
        while let Some((&pos, &(at, order))) = self.retired.first_key_value() {
            if at > effect {
                break;
            }
            self.retired.remove(&pos);
            self.frozen_headers.remove(&order);
            self.sparse.remove(&order);
            self.location_keys.remove(&order);
            if let Some(block) = self.pending.remove(&pos) {
                self.by_id.remove(&block.id);
            }
            let keys = self
                .members
                .range((order, 0)..=(order, u64::MAX))
                .map(|(key, _)| *key)
                .collect::<Vec<_>>();
            for key in keys {
                self.unfinished_members.remove(&key);
                if let Some(member) = self.members.remove(&key) {
                    if self.member_locations.get(&member.association_key) == Some(&key) {
                        self.member_locations.remove(&member.association_key);
                    }
                    self.retained = self
                        .retained
                        .saturating_sub(bytes(member.as_ref()).unwrap_or(u64::MAX));
                }
            }
            self.durable = pos;
        }
    }

    /// Fold only the effect's actual changes. No call from progress/token observation.
    pub(super) fn observation_requests(
        &self,
        effect: u64,
        facts: &[ChatAtom],
        sources: &[ChatSourceState],
    ) -> Result<BTreeMap<String, (ChatFactPosition, DisplayMemberWrite)>> {
        let mut boundaries: BTreeMap<ChatSourceId, Vec<ChatFactPosition>> = BTreeMap::new();
        for atom in facts.iter().filter(|atom| !work(atom) && !hidden(atom)) {
            if !self.member_locations.contains_key(&member_key(atom)?)
                && let Some(at) = evidence(atom)
            {
                boundaries.entry(atom.source.clone()).or_default().push(at);
            }
        }
        for source in sources
            .iter()
            .filter(|source| matches!(source.lifecycle, ChatSourceLifecycle::Ended { .. }))
        {
            if let Some(at) = source.ended {
                boundaries
                    .entry(source.source.clone())
                    .or_default()
                    .push(at);
            }
        }
        for positions in boundaries.values_mut() {
            positions.sort_unstable();
        }
        let terminal_before = |atom: &ChatAtom, boundary| {
            facts.iter().any(|end| {
            end.id == atom.id && end.source == atom.source
                && matches!(end.lifecycle, ChatAtomLifecycle::Terminal { ended: Some(at), .. } if at <= boundary)
        })
        };
        let mut requests = BTreeMap::new();
        for (source, positions) in &boundaries {
            let first = positions[0];
            if let Some(order) = self.lanes.get(source).and_then(|lane| lane.open_work) {
                for position in self
                    .unfinished_members
                    .range((order, 0)..=(order, u64::MAX))
                {
                    let member = &self.members[position];
                    if !terminal_before(&member.head.record.atom, first) {
                        requests.insert(
                            member.association_key.clone(),
                            (first, member.as_ref().clone()),
                        );
                    }
                }
            }
            for atom in facts.iter().filter(|atom| atom.source == *source && work(atom)
                && matches!(atom.lifecycle, ChatAtomLifecycle::Active { started: Some(at), .. } if at.effect_seq == effect)) {
                let key = member_key(atom)?;
                if requests.contains_key(&key) { continue; }
                let Some(at) = evidence(atom) else { continue };
                if let Some(boundary) = positions.iter().copied().find(|boundary| *boundary >= at)
                    && !terminal_before(atom, boundary) {
                    requests.insert(key.clone(), (boundary, DisplayMemberWrite {
                        block_id: String::new(), association_key: key, terminal: false,
                        head: DisplayMemberHead { member_key: String::new(), member_order: 0,
                            record: record(atom.clone(), Some(at)) },
                    }));
                }
            }
        }
        Ok(requests)
    }

    #[cfg(test)]
    pub fn prepare(
        &mut self,
        effect: u64,
        committed_at: i64,
        facts: &[ChatAtom],
        sources: &[ChatSourceState],
        completions: &[Arc<ChatItem>],
    ) -> Result<Arc<PreparedDisplayDelta>> {
        self.prepare_capturing(
            effect,
            committed_at,
            facts,
            sources,
            completions,
            |member| {
                ensure!(
                    member.head.record.atom.contents.is_empty(),
                    "test boundary requires an explicit content cut"
                );
                Ok(ObservationInput::for_test(
                    member.head.record.atom.clone(),
                    Vec::new(),
                ))
            },
        )
    }

    pub fn prepare_capturing(
        &mut self,
        effect: u64,
        committed_at: i64,
        facts: &[ChatAtom],
        sources: &[ChatSourceState],
        completions: &[Arc<ChatItem>],
        mut capture: impl FnMut(&DisplayMemberWrite) -> Result<ObservationInput>,
    ) -> Result<Arc<PreparedDisplayDelta>> {
        ensure!(
            effect > self.applied_effect,
            "display effect already folded"
        );
        // Resolve every fallible observation before modifying this fold. A missing
        // owner/body fails the original retained effect, which can retry unchanged.
        let mut captured = HashMap::new();
        for (key, (_, member)) in self.observation_requests(effect, facts, sources)? {
            captured.insert(key, capture(&member)?);
        }
        for input in captured.values() {
            let atom = &input.atom;
            let material = &input.contents;
            crate::studio::runtime::chat_item::validate_observation(
                &input.state,
                atom,
                &input.thread_id,
            )?;
            ensure!(
                matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }),
                "boundary observation is not active"
            );
            for body in &atom.contents {
                let ContentTarget::Body { owner, key } = &body.reference.target else {
                    anyhow::bail!("boundary observation is not a Body reference");
                };
                let owner = crate::studio::conversation_identity::content_owner_key(owner)?;
                ensure!(
                    material
                        .iter()
                        .any(|content| content.descriptor.key.owner == owner
                            && content.descriptor.key.key == *key),
                    "boundary observation lost its immutable body"
                );
            }
            ensure!(
                !matches!(atom.payload, Some(PayloadData::Deferred { .. })),
                "boundary public payload must be captured, not a mutable reference"
            );
        }
        let mut capture = |member: &DisplayMemberWrite| {
            captured
                .get(&member.association_key)
                .cloned()
                .context("boundary observation was not prepared")
        };
        let completed = completions
            .iter()
            .map(|item| (item.header.item_id.as_str(), item))
            .collect::<HashMap<_, _>>();
        let mut atoms = Vec::with_capacity(facts.len());
        for fact in facts {
            ensure!(
                !matches!(fact.lifecycle, ChatAtomLifecycle::Terminal { .. })
                    || fact.completion_item_id.is_some()
                    || (fact.contents.is_empty() && fact.payload.is_none()),
                "unreceipted terminal must not retain dynamic content"
            );
            let mut atom = fact.clone();
            if let Some(id) = &atom.completion_item_id
                && let Some(item) = completed.get(id.as_str())
            {
                if item.header.query_class != "conversation" {
                    continue;
                }
                atom.completion_seq = Some(item.header.append_seq);
                atom.payload = Some(PayloadData::Deferred {
                    reference: ContentRef {
                        database_id: self.database.clone(),
                        target: ContentTarget::ItemPayload {
                            item_id: id.clone(),
                        },
                    },
                    byte_length: item.header.byte_length,
                });
            }
            atoms.push(lightweight(atom, &self.database));
        }
        // Reject contradictory terminals before touching counters/queues, including conflicts
        // between two facts in this effect. The map is effect-local, not a scan of old members.
        let mut checked: HashMap<String, ChatAtom> = HashMap::new();
        for atom in &atoms {
            if hidden(atom) {
                continue;
            }
            let key = member_key(atom)?;
            let previous = checked.get(&key).or_else(|| {
                self.member_locations
                    .get(&key)
                    .and_then(|p| self.members.get(p))
                    .map(|m| &m.head.record.atom)
            });
            if let Some(previous) = previous {
                if matches!(previous.lifecycle, ChatAtomLifecycle::Terminal { .. }) {
                    ensure!(previous == atom, "contradictory display terminal {key}");
                }
                ensure!(
                    previous.kind == atom.kind && previous.source == atom.source,
                    "display member ownership conflict {key}"
                );
            }
            checked.insert(key, atom.clone());
        }
        let mut touched = BTreeSet::new();
        let mut changed_members = BTreeMap::new();
        let mut remove_empty = Vec::new();
        let mut published = BTreeMap::new();
        let mut contents = Vec::new();
        for atom in atoms {
            if hidden(&atom) {
                continue;
            }
            let key = member_key(&atom)?;
            if let Some(position) = self.member_locations.get(&key).copied() {
                let previous = self
                    .members
                    .get(&position)
                    .context("display location lost member")?;
                if previous.head.record.atom == atom {
                    continue;
                }
                ensure!(!previous.terminal, "frozen display member changed");
                let mut header = self
                    .blocks
                    .get(&position.0)
                    .context("display location lost open block")?
                    .as_ref()
                    .clone();
                ensure!(!header.sealed, "sealed display member is not updatable");
                update_summary(&mut header, Some(&previous.head.record.atom), &atom)?;
                if let DisplayBlockBody::Work { summary, .. } = &mut header.body
                    && let Some(thought) = completed_thinking_summary(&atom, &completed)?
                {
                    summary.thinking_summary = Some(thought);
                }
                let next_record = record(atom.clone(), previous.head.record.start_fact);
                let member = Arc::new(DisplayMemberWrite {
                    block_id: header.id.clone(),
                    association_key: key.clone(),
                    terminal: matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. }),
                    head: DisplayMemberHead {
                        member_key: previous.head.member_key.clone(),
                        member_order: position.1,
                        record: next_record.clone(),
                    },
                });
                if member.terminal {
                    self.unfinished_members.remove(&position);
                }
                self.retained = self
                    .retained
                    .saturating_sub(bytes(previous.as_ref())?)
                    .saturating_add(bytes(member.as_ref())?);
                self.members.insert(position, member.clone());
                changed_members.insert(position, member);
                if let DisplayBlockBody::Single { record } = &mut header.body {
                    **record = next_record;
                }
                self.replace_header(header, committed_at, &mut touched)?;
            } else {
                let order = if work(&atom) {
                    if let Some(order) =
                        self.lanes.get(&atom.source).and_then(|lane| lane.open_work)
                    {
                        order
                    } else {
                        self.create(&atom, &key, true, committed_at, &mut touched)?
                    }
                } else {
                    // TextStarted is already admitted. Independent inputs/background results have
                    // their own typed lane, and never close a foreground lane.
                    self.boundary(
                        (&atom.source, evidence(&atom)),
                        (effect, committed_at),
                        &mut touched,
                        &mut changed_members,
                        &mut contents,
                        &mut capture,
                    )?;
                    self.create(&atom, &key, false, committed_at, &mut touched)?
                };
                let mut header = self.blocks[&order].as_ref().clone();
                header.next_member = header
                    .next_member
                    .checked_add(1)
                    .context("display member order exhausted")?;
                update_summary(&mut header, None, &atom)?;
                if let DisplayBlockBody::Work { summary, .. } = &mut header.body
                    && let Some(thought) = completed_thinking_summary(&atom, &completed)?
                {
                    summary.thinking_summary = Some(thought);
                }
                let member = Arc::new(DisplayMemberWrite {
                    block_id: header.id.clone(),
                    association_key: key.clone(),
                    terminal: matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. }),
                    head: DisplayMemberHead {
                        member_key: display_member_key(&header.id, &atom)?,
                        member_order: header.next_member,
                        record: record(
                            atom.clone(),
                            match atom.lifecycle {
                                ChatAtomLifecycle::Active { started, .. } => started,
                                ChatAtomLifecycle::Terminal { .. } => None,
                            },
                        ),
                    },
                });
                let position = (order, header.next_member);
                self.retained = self.retained.saturating_add(bytes(member.as_ref())?);
                self.location_keys
                    .entry(order)
                    .or_default()
                    .insert(key.clone());
                self.member_locations.insert(key, position);
                if !member.terminal {
                    self.unfinished_members.insert(position);
                }
                self.members.insert(position, member.clone());
                changed_members.insert(position, member);
                self.replace_header(header, committed_at, &mut touched)?;
            }
            self.drain(
                &atom.source,
                (effect, committed_at),
                &mut touched,
                &mut published,
                &mut remove_empty,
            )?;
        }
        for source in sources {
            if matches!(source.lifecycle, ChatSourceLifecycle::Ended { .. }) {
                self.boundary(
                    (&source.source, source.ended),
                    (effect, committed_at),
                    &mut touched,
                    &mut changed_members,
                    &mut contents,
                    &mut capture,
                )?;
                self.drain(
                    &source.source,
                    (effect, committed_at),
                    &mut touched,
                    &mut published,
                    &mut remove_empty,
                )?;
            }
        }
        let mut blocks = Vec::with_capacity(touched.len());
        for order in touched {
            if let Some(header) = self.blocks.get(&order) {
                blocks.push(DisplayBlockWrite {
                    header: header.clone(),
                    published: None,
                });
            } else if let Some((header, block)) = published.remove(&order) {
                blocks.push(DisplayBlockWrite {
                    header,
                    published: Some(block),
                });
            }
        }
        let removed = remove_empty.iter().map(|h| &h.id).collect::<BTreeSet<_>>();
        let mut delta = PreparedDisplayDelta {
            effect_seq: effect,
            blocks,
            members: changed_members
                .into_values()
                .filter(|m| !removed.contains(&m.block_id))
                .collect(),
            remove_empty,
            published_through: self.published,
            contents,
            retained_bytes: 0,
        };
        delta.retained_bytes = bytes(&delta)?.saturating_add(
            delta
                .contents
                .iter()
                .map(|content| content.data.len() as u64 + 192)
                .sum::<u64>(),
        );
        self.applied_effect = effect;
        if let Some(changes) = &self.changes
            && *changes.borrow() != self.member_change
        {
            changes.send_replace(self.member_change);
        }
        Ok(Arc::new(delta))
    }

    fn replace_header(
        &mut self,
        mut header: DisplayHeader,
        committed_at: i64,
        touched: &mut BTreeSet<u64>,
    ) -> Result<()> {
        if !self
            .blocks
            .get(&header.block_order)
            .is_some_and(|old| old.sealed)
        {
            observe_elapsed(&mut header, committed_at);
        }
        if let Some(old) = self
            .blocks
            .insert(header.block_order, Arc::new(header.clone()))
        {
            self.retained = self.retained.saturating_sub(bytes(old.as_ref())?);
        }
        self.retained = self.retained.saturating_add(bytes(&header)?);
        touched.insert(header.block_order);
        self.member_change = self
            .member_change
            .checked_add(1)
            .context("display member notification exhausted")?;
        Ok(())
    }

    fn create(
        &mut self,
        atom: &ChatAtom,
        key: &str,
        is_work: bool,
        committed_at: i64,
        touched: &mut BTreeSet<u64>,
    ) -> Result<u64> {
        self.revision = self
            .revision
            .checked_add(1)
            .context("display structure revision exhausted")?;
        self.next_order = self
            .next_order
            .checked_add(1)
            .filter(|value| *value <= i64::MAX as u64)
            .context("display block order exhausted")?;
        let id = serde_json::to_string(&(
            "display-v2",
            &self.database,
            &atom.source,
            evidence(atom),
            key,
        ))?;
        ensure!(
            !self.by_id.contains_key(&id),
            "display block identity reused"
        );
        let order = self.next_order;
        let lane = self.lanes.entry(atom.source.clone()).or_default();
        lane.pending_order.push_back(order);
        if is_work {
            lane.open_work = Some(order);
        }
        let header = DisplayHeader {
            version: 2,
            legacy: false,
            id: id.clone(),
            source: atom.source.clone(),
            block_order: order,
            history_pos: None,
            boundary: None,
            sealed: false,
            unfinished: 0,
            next_member: 0,
            revision: 0,
            skip_display: false,
            active_since: None,
            duration_known: true,
            body: if is_work {
                DisplayBlockBody::Work {
                    summary: Box::new(pl_protocol::WorkSummary {
                        created_at: Some(committed_at),
                        ..Default::default()
                    }),
                    members: DisplayBlockRef {
                        database_id: self.database.clone(),
                        block_id: id.clone(),
                    },
                }
            } else {
                DisplayBlockBody::Single {
                    record: Box::new(record(
                        atom.clone(),
                        match atom.lifecycle {
                            ChatAtomLifecycle::Active { started, .. } => started,
                            ChatAtomLifecycle::Terminal { .. } => None,
                        },
                    )),
                }
            },
        };
        self.by_id.insert(id, order);
        self.replace_header(header, committed_at, touched)?;
        Ok(order)
    }

    fn boundary(
        &mut self,
        (source, at): (&ChatSourceId, Option<ChatFactPosition>),
        (effect, committed_at): (u64, i64),
        touched: &mut BTreeSet<u64>,
        changed_members: &mut BTreeMap<(u64, u64), Arc<DisplayMemberWrite>>,
        contents: &mut Vec<Arc<ChatContent>>,
        capture: &mut impl FnMut(&DisplayMemberWrite) -> Result<ObservationInput>,
    ) -> Result<()> {
        let Some(at) = at else {
            return Ok(());
        };
        if let Some(order) = self
            .lanes
            .get_mut(source)
            .and_then(|lane| lane.open_work.take())
        {
            let mut header = self.blocks[&order].as_ref().clone();
            // Capture immutable material before revoking membership. No database or
            // completion collection is consulted at this boundary.
            let positions = self
                .unfinished_members
                .range((order, 0)..=(order, u64::MAX))
                .map(|position| (*position, self.members[position].clone()))
                .collect::<Vec<_>>();
            for (position, previous) in positions {
                if !previous.terminal {
                    let input = capture(&previous)?;
                    let mut atom = input.atom;
                    let material = input.contents;
                    ensure!(
                        atom.id == previous.head.record.atom.id && atom.source == header.source,
                        "boundary capture changed member ownership"
                    );
                    update_summary(&mut header, Some(&previous.head.record.atom), &atom)?;
                    let owner = pl_protocol::ContentOwner::DisplayObservation {
                        block_id: header.id.clone(),
                        member_key: previous.head.member_key.clone(),
                    };
                    let owner_key =
                        crate::studio::conversation_identity::content_owner_key(&owner)?;
                    let mut captured = BTreeMap::new();
                    for content in material {
                        let mut value = content.as_ref().clone();
                        let key = value.descriptor.key.key.clone();
                        value.descriptor.key.owner = owner_key.clone();
                        let value = Arc::new(value);
                        captured.insert(key, value);
                    }
                    for body in &mut atom.contents {
                        let ContentTarget::Body { key, .. } = &body.reference.target else {
                            anyhow::bail!("boundary body is not owned content");
                        };
                        ensure!(
                            captured.contains_key(key),
                            "boundary content cut is missing {key}"
                        );
                        body.reference.target = ContentTarget::Body {
                            owner: owner.clone(),
                            key: key.clone(),
                        };
                    }
                    atom.payload = Some(PayloadData::Inline {
                        bytes: crate::studio::runtime::chat_item::observation_payload(
                            &input.state,
                            &atom,
                            &captured.values().cloned().collect::<Vec<_>>(),
                            crate::studio::runtime::chat_item::ObservationStamp {
                                thread_id: &input.thread_id,
                                database_id: &self.database,
                                owner: &owner,
                                boundary: at,
                                captured_at: committed_at,
                            },
                        )?,
                    });
                    if let Some(PayloadData::Inline { bytes }) = atom.payload.take() {
                        let key = "display.payload".to_owned();
                        let content = Arc::new(ChatContent {
                            descriptor: pl_core::chat::ContentDescriptor {
                                key: ChatContentKey {
                                    owner: owner_key,
                                    key: key.clone(),
                                },
                                byte_length: bytes.len() as u64,
                                generation: 1,
                                media_type: Some("application/json".into()),
                            },
                            data: pl_core::chat::ContentData::Bytes(bytes.into()),
                        });
                        atom.payload = Some(PayloadData::Deferred {
                            reference: ContentRef {
                                database_id: self.database.clone(),
                                target: ContentTarget::Body {
                                    owner,
                                    key: key.clone(),
                                },
                            },
                            byte_length: content.descriptor.byte_length,
                        });
                        captured.insert(key, content);
                    }
                    let mut member = previous.as_ref().clone();
                    member.head.record.atom = atom;
                    member.head.record.content_source = DisplayContentSource::FrozenObservation {
                        captured_at: Some(committed_at),
                        available: true,
                    };
                    if let DisplayBlockBody::Work { summary, .. } = &mut header.body
                        && member.head.record.atom.kind == ChatAtomKind::Reasoning
                    {
                        summary.thinking_content = member
                            .head
                            .record
                            .atom
                            .contents
                            .iter()
                            .rev()
                            .find(|body| body.role == ChatContentRole::ReasoningSummary)
                            .or_else(|| member.head.record.atom.contents.last())
                            .map(|body| body.reference.clone());
                        if let Some(thought) =
                            material_summary(&member.head.record.atom, &captured)?
                        {
                            summary.thinking_summary = Some(thought);
                        }
                    }
                    header.revision = header
                        .revision
                        .checked_add(1)
                        .context("display revision exhausted")?;
                    self.retained = self
                        .retained
                        .saturating_sub(bytes(previous.as_ref())?)
                        .saturating_add(bytes(&member)?);
                    let member = Arc::new(member);
                    self.members.insert(position, member.clone());
                    changed_members.insert(position, member);
                    for content in captured.into_values() {
                        self.retained = self
                            .retained
                            .saturating_add(content.data.len() as u64 + 192);
                        self.observations
                            .insert(content.descriptor.key.clone(), (effect, content.clone()));
                        contents.push(content);
                    }
                }
                self.unfinished_members.remove(&position);
            }
            if let Some(keys) = self.location_keys.remove(&order) {
                for key in keys {
                    self.member_locations.remove(&key);
                }
            }
            header.boundary = Some(at);
            header.sealed = true;
            self.replace_header(header, committed_at, touched)?;
        }
        Ok(())
    }

    fn drain(
        &mut self,
        source: &ChatSourceId,
        (effect, _committed_at): (u64, i64),
        touched: &mut BTreeSet<u64>,
        published: &mut BTreeMap<u64, (Arc<DisplayHeader>, Arc<DisplayBlock>)>,
        remove_empty: &mut Vec<Arc<DisplayHeader>>,
    ) -> Result<()> {
        while let Some(order) = self
            .lanes
            .get(source)
            .and_then(|lane| lane.pending_order.front())
            .copied()
        {
            let header = &self.blocks[&order];
            if !header.sealed {
                break;
            }
            let mut header = header.as_ref().clone();
            self.lanes
                .get_mut(source)
                .expect("lane exists")
                .pending_order
                .pop_front();
            self.blocks.remove(&order);
            self.retained = self.retained.saturating_sub(bytes(&header)?);
            if header.skip_display {
                ensure!(
                    matches!(&header.body, DisplayBlockBody::Single { record }
                    if record.atom.content_present == Some(false) && record.atom.kind == ChatAtomKind::Text),
                    "only proven empty text may be removed"
                );
                self.by_id.remove(&header.id);
                let keys = self
                    .members
                    .range((order, 0)..=(order, u64::MAX))
                    .map(|(p, _)| *p)
                    .collect::<Vec<_>>();
                for key in keys {
                    let member = self.members.remove(&key).expect("captured member");
                    self.member_locations.remove(&member.association_key);
                    self.retained = self.retained.saturating_sub(bytes(member.as_ref())?);
                }
                remove_empty.push(Arc::new(header));
            } else {
                self.published = self
                    .published
                    .checked_add(1)
                    .filter(|value| *value <= i64::MAX as u64)
                    .context("display history exhausted")?;
                header.history_pos = Some(self.published);
                let block = Arc::new(header.frozen().expect("assigned display position"));
                self.pending.insert(self.published, block.clone());
                self.retired.insert(self.published, (effect, order));
                let header = Arc::new(header);
                self.frozen_headers.insert(order, header.clone());
                published.insert(order, (header, block));
                touched.insert(order);
            }
            self.revision = self
                .revision
                .checked_add(1)
                .context("display revision exhausted")?;
        }
        if self
            .lanes
            .get(source)
            .is_some_and(|lane| lane.pending_order.is_empty() && lane.open_work.is_none())
        {
            self.lanes.remove(source);
        }
        Ok(())
    }
}

fn observe_elapsed(header: &mut DisplayHeader, committed_at: i64) {
    if let DisplayBlockBody::Work { summary, .. } = &mut header.body {
        summary.elapsed_ms = summary
            .created_at
            .and_then(|created| committed_at.checked_sub(created))
            .and_then(|seconds| u64::try_from(seconds).ok())
            .and_then(|seconds| seconds.checked_mul(1000));
    }
}

fn content_tail_summary(content: &ChatContent) -> Result<Option<String>> {
    let offset = content
        .data
        .len()
        .saturating_sub(super::activity::ACTIVITY_SUMMARY_TAIL_BYTES);
    let bytes = content
        .data
        .range(offset as u64, super::activity::ACTIVITY_SUMMARY_TAIL_BYTES)?;
    for skip in 0..=3.min(bytes.as_bytes().len()) {
        if let Ok(tail) = std::str::from_utf8(&bytes.as_bytes()[skip..]) {
            return Ok(super::activity::thinking_summary_line(tail));
        }
    }
    anyhow::bail!("thinking summary boundary contains invalid UTF-8")
}

fn material_summary(
    atom: &ChatAtom,
    contents: &BTreeMap<String, Arc<ChatContent>>,
) -> Result<Option<String>> {
    for body in atom
        .contents
        .iter()
        .rev()
        .filter(|body| body.role == ChatContentRole::ReasoningSummary)
    {
        let ContentTarget::Body { key, .. } = &body.reference.target else {
            continue;
        };
        let content = contents
            .get(key)
            .context("thinking summary lost its frozen content")?;
        if let Some(summary) = content_tail_summary(content)? {
            return Ok(Some(summary));
        }
    }
    Ok(None)
}

fn completed_thinking_summary(
    atom: &ChatAtom,
    completed: &HashMap<&str, &Arc<ChatItem>>,
) -> Result<Option<String>> {
    if atom.kind != ChatAtomKind::Reasoning
        || !matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. })
    {
        return Ok(None);
    }
    let Some(id) = atom.completion_item_id.as_deref() else {
        return Ok(None);
    };
    let Some(item) = completed.get(id) else {
        return Ok(None);
    };
    for body in atom
        .contents
        .iter()
        .rev()
        .filter(|body| body.role == ChatContentRole::ReasoningSummary)
    {
        let ContentTarget::Body { owner, key } = &body.reference.target else {
            continue;
        };
        let content_key = ChatContentKey {
            owner: crate::studio::conversation_identity::content_owner_key(owner)?,
            key: key.clone(),
        };
        let content = item
            .contents
            .get(&content_key)
            .context("completed thinking summary lost its owned content")?;
        if let Some(summary) = content_tail_summary(content)? {
            return Ok(Some(summary));
        }
    }
    Ok(None)
}

fn update_summary(
    header: &mut DisplayHeader,
    old: Option<&ChatAtom>,
    atom: &ChatAtom,
) -> Result<()> {
    let terminal = matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. });
    let previously_unfinished = header.unfinished;
    header.revision = header
        .revision
        .checked_add(1)
        .context("member revision exhausted")?;
    if old.is_none() {
        header.unfinished = header
            .unfinished
            .checked_add(1)
            .context("unfinished count exhausted")?;
    }
    if terminal {
        header.unfinished = header
            .unfinished
            .checked_sub(1)
            .context("duplicate member terminal")?;
    }
    let DisplayBlockBody::Work { summary, .. } = &mut header.body else {
        let start = match &header.body {
            DisplayBlockBody::Single { record } => record.start_fact,
            _ => None,
        };
        header.body = DisplayBlockBody::Single {
            record: Box::new(record(atom.clone(), start)),
        };
        if terminal {
            header.boundary = evidence(atom);
            header.sealed = true;
            header.skip_display =
                atom.kind == ChatAtomKind::Text && atom.content_present == Some(false);
        }
        return Ok(());
    };
    if old.is_none() {
        summary.total = summary
            .total
            .checked_add(1)
            .context("member count exhausted")?;
        summary.started_at = match (summary.started_at, atom.started_at) {
            (None, at) if summary.total == 1 => at,
            (Some(a), Some(b)) => Some(a.min(b)),
            _ => None,
        };
        // Every member contributes to the proof, including a directly completed member
        // whose unknown start can precede the current overlapping work interval.
        header.duration_known &= atom.started_at.is_some();
        if !header.duration_known {
            summary.duration_ms = None;
        }
        if previously_unfinished == 0 {
            header.active_since = atom
                .started_at
                .map(|start| summary.finished_at.map_or(start, |end| start.max(end)));
        }
    } else if matches!(
        old.map(|a| &a.lifecycle),
        Some(ChatAtomLifecycle::Active {
            status: ChatActiveStatus::Waiting,
            ..
        })
    ) {
        summary.waiting = summary
            .waiting
            .checked_sub(1)
            .context("waiting count underflow")?;
    } else {
        summary.running = summary
            .running
            .checked_sub(1)
            .context("running count underflow")?;
    }
    match atom.lifecycle {
        ChatAtomLifecycle::Active {
            status: ChatActiveStatus::Waiting,
            ..
        } => summary.waiting += 1,
        ChatAtomLifecycle::Active { .. } => summary.running += 1,
        ChatAtomLifecycle::Terminal { outcome, .. } => {
            summary.terminal += 1;
            match outcome {
                ChatTerminalOutcome::Failed => summary.failed += 1,
                ChatTerminalOutcome::Cancelled => summary.cancelled += 1,
                ChatTerminalOutcome::Transferred => summary.transferred += 1,
                ChatTerminalOutcome::Completed => {}
            }
            summary.finished_at = match (summary.finished_at, atom.finished_at) {
                (None, at) if summary.terminal == 1 => at,
                (Some(a), Some(b)) => Some(a.max(b)),
                _ => None,
            };
            if header.unfinished == 0 {
                summary.duration_ms = match (
                    header.duration_known,
                    header.active_since.take(),
                    summary.finished_at,
                ) {
                    (true, Some(start), Some(end)) => end
                        .checked_sub(start)
                        .and_then(|v| u64::try_from(v).ok())
                        .and_then(|v| summary.duration_ms.unwrap_or(0).checked_add(v)),
                    _ => None,
                };
                header.duration_known &= summary.duration_ms.is_some();
            }
        }
    }
    if atom.kind == ChatAtomKind::Reasoning {
        summary.thinking_content = atom
            .contents
            .iter()
            .rev()
            .find(|c| c.role == ChatContentRole::ReasoningSummary)
            .or_else(|| {
                atom.contents
                    .iter()
                    .rev()
                    .find(|c| c.role == ChatContentRole::Body)
            })
            .map(|c| c.reference.clone());
    }
    Ok(())
}

#[cfg(test)]
mod tests;

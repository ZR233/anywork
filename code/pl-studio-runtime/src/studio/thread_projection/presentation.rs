//! Incremental display ownership. Only reliable, admitted facts enter this fold.
use std::{
    collections::{BTreeMap, BTreeSet, HashMap},
    sync::{Arc, Mutex},
};

use anyhow::{Context, Result, ensure};
use pl_core::chat::{ChatContent, ChatContentKey, ChatItem};
#[cfg(test)]
use pl_protocol::{ChatActiveStatus, ChatSourceState};
use pl_protocol::{
    ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatContentRole, ChatDeliveryKind, ChatFactPosition,
    ChatSourceId, ChatTerminalOutcome, ContentRef, ContentTarget, DisplayBlock, DisplayBlockBody,
    DisplayBlockRef, DisplayContentSource, DisplayMemberHead, DisplayRecord, PayloadData,
    SingleVisibility,
};
use serde::{Deserialize, Serialize};
mod observations;

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
    pub id: String,
    pub source: ChatSourceId,
    pub block_order: u64,
    pub history_pos: Option<u64>,
    pub boundary: Option<ChatFactPosition>,
    pub first_content_at: Option<ChatFactPosition>,
    pub sealed: bool,
    pub unfinished: u64,
    pub next_member: u64,
    pub revision: u64,
    pub skip_display: bool,
    #[serde(skip)]
    pub thinking_summary: Option<String>,
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

/// A reliable ContentAvailable phase, distinct from the atom's real start.
#[derive(Debug, Clone, Serialize)]
pub(in crate::studio) struct TextVisible {
    pub atom: ChatAtom,
    pub at: ChatFactPosition,
}

pub(in crate::studio) type ObservationPlan =
    BTreeMap<String, (ChatFactPosition, DisplayMemberWrite)>;

pub(in crate::studio) struct DisplayInput<'a> {
    pub facts: &'a [ChatAtom],
    pub visible: &'a [TextVisible],
    pub observations: Option<&'a ObservationPlan>,
}

/// An explicitly bounded capture from one short owner lock.
pub(in crate::studio) struct PresentationCut {
    pub published: u64,
    pub durable: u64,
    pub revision: u64,
    pub current_work_id: Option<String>,
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
    open_work: Option<u64>,
    blocks: PresentationMap<u64, Arc<DisplayHeader>>,
    frozen_headers: PresentationMap<u64, Arc<DisplayHeader>>,
    sparse: BTreeSet<u64>,
    retired: BTreeMap<u64, (u64, u64)>, // history_pos -> (effect, block_order)
    by_id: HashMap<String, u64>,
    members: PresentationMap<(u64, u64), Arc<DisplayMemberWrite>>,
    current_work_rows: HashMap<String, (u64, u64)>,
    open_texts: HashMap<String, (u64, u64)>,
    unfinished_members: BTreeSet<(u64, u64)>,
    observations: BTreeMap<ChatContentKey, (u64, Arc<ChatContent>)>,
    observation_batches: BTreeMap<u64, Vec<ChatContentKey>>,
    terminal_batches: BTreeMap<u64, Vec<(u64, u64)>>,
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
        ) && atom.delivery != ChatDeliveryKind::Independent)
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

fn independently_visible_text(atom: &ChatAtom) -> Option<ChatFactPosition> {
    // Inbox eligibility was proved by accepted_inbox_draft, not by text or a source-id prefix.
    // Unlike model starts, its nonempty original is already public at reliable admission.
    if atom.kind != ChatAtomKind::Text
        || !matches!(atom.source, ChatSourceId::InboxMessage { .. })
        || atom.delivery != ChatDeliveryKind::Independent
        || atom.content_present != Some(true)
        || atom.completion_item_id.is_none()
    {
        return None;
    }
    match atom.lifecycle {
        ChatAtomLifecycle::Terminal {
            ended: Some(at),
            outcome: ChatTerminalOutcome::Completed,
            ..
        } => Some(at),
        _ => None,
    }
}

enum DisplayOperation<'a> {
    Atom(&'a ChatAtom),
    TextVisible(&'a TextVisible),
}

fn operations<'a>(facts: &'a [ChatAtom], visible: &'a [TextVisible]) -> Vec<DisplayOperation<'a>> {
    let mut result = facts
        .iter()
        .map(DisplayOperation::Atom)
        .chain(visible.iter().map(DisplayOperation::TextVisible))
        .collect::<Vec<_>>();
    result.sort_by_key(|op| match op {
        DisplayOperation::Atom(atom) => (evidence(atom), 0),
        DisplayOperation::TextVisible(text) => (Some(text.at), 1),
    });
    result
}

fn block_identity(database: &str, atom: &ChatAtom, key: &str) -> Result<String> {
    Ok(serde_json::to_string(&(
        "display-v4",
        database,
        &atom.source,
        evidence(atom),
        key,
    ))?)
}

fn bytes<T: Serialize>(value: &T) -> Result<u64> {
    Ok(serde_json::to_vec(value)?.len() as u64 + 192)
}

fn header_bytes(header: &DisplayHeader) -> Result<u64> {
    Ok(bytes(header)?.saturating_add(
        header
            .thinking_summary
            .as_ref()
            .map_or(0, |value| value.len() as u64),
    ))
}

impl PresentationState {
    /// Streaming replaces only the open group's bounded in-memory title. No member
    /// read, durable delta or persisted header revision is produced by progress.
    pub(super) fn observe_thinking_summary(&mut self, summary: &str) {
        let Some(order) = self.open_work else { return };
        let header = self.blocks.get(&order).expect("open Work header");
        if header.thinking_summary.as_deref() == Some(summary) {
            return;
        }
        let previous = header.thinking_summary.as_ref().map_or(0, String::len);
        let mut header = header.as_ref().clone();
        header.thinking_summary = Some(summary.to_owned());
        self.blocks.insert(order, Arc::new(header));
        self.retained = self
            .retained
            .saturating_sub(previous as u64)
            .saturating_add(summary.len() as u64);
    }

    fn admitted(&self, atom: &ChatAtom) -> bool {
        match atom.lifecycle {
            ChatAtomLifecycle::Terminal {
                ended: Some(at), ..
            } => at.effect_seq > self.applied_effect || self.accepts_update(atom),
            ChatAtomLifecycle::Active {
                started: Some(at), ..
            } if at.effect_seq <= self.applied_effect => self.accepts_update(atom),
            _ => true,
        }
    }

    fn location(&self, key: &str) -> Option<(u64, u64)> {
        self.current_work_rows
            .get(key)
            .or_else(|| self.open_texts.get(key))
            .copied()
    }

    pub fn accepts_update(&self, atom: &ChatAtom) -> bool {
        member_key(atom)
            .ok()
            .is_some_and(|key| self.location(&key).is_some())
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
            current_work_id: self.open_work.map(|order| self.blocks[&order].id.clone()),
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
                header.history_pos.is_none() && header.version == 4,
                "invalid open display header"
            );
            if !header.sealed && matches!(header.body, DisplayBlockBody::Work { .. }) {
                ensure!(
                    self.open_work.replace(header.block_order).is_none()
                        && header.block_order == next_order,
                    "multiple open work blocks"
                );
            }
            self.retained += header_bytes(&header)?;
            self.sparse.insert(header.block_order);
            self.by_id.insert(header.id.clone(), header.block_order);
            self.blocks.insert(header.block_order, Arc::new(header));
        }
        for member in unfinished {
            ensure!(
                !member.terminal,
                "restore requested terminal display member"
            );
            ensure!(
                member.association_key == member_key(&member.head.record.atom)?,
                "restored member association differs from its own source or responsibility"
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
            self.unfinished_members
                .insert((order, member.head.member_order));
            let locations = if matches!(self.blocks[&order].body, DisplayBlockBody::Work { .. }) {
                &mut self.current_work_rows
            } else {
                ensure!(
                    member.head.record.atom.kind != ChatAtomKind::Text
                        || self.blocks[&order].first_content_at.is_some(),
                    "visible Text has no content evidence"
                );
                &mut self.open_texts
            };
            ensure!(
                locations
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
        while self
            .observation_batches
            .first_key_value()
            .is_some_and(|(at, _)| *at <= effect)
        {
            let (_, keys) = self
                .observation_batches
                .pop_first()
                .expect("confirmed batch");
            for key in keys {
                if let Some((_, content)) = self.observations.remove(&key) {
                    self.retained = self
                        .retained
                        .saturating_sub(content.data.len() as u64 + 192);
                }
            }
        }
        while self
            .terminal_batches
            .first_key_value()
            .is_some_and(|(at, _)| *at <= effect)
        {
            let (_, positions) = self.terminal_batches.pop_first().expect("confirmed batch");
            for position in positions {
                if let Some(member) = self.members.remove(&position) {
                    debug_assert!(member.terminal);
                    if self.current_work_rows.get(&member.association_key) == Some(&position) {
                        self.current_work_rows.remove(&member.association_key);
                    }
                    if self.open_texts.get(&member.association_key) == Some(&position) {
                        self.open_texts.remove(&member.association_key);
                    }
                    self.sparse.insert(position.0);
                    self.retained = self
                        .retained
                        .saturating_sub(bytes(member.as_ref()).unwrap_or(u64::MAX));
                }
            }
        }
        while let Some((&pos, &(at, order))) = self.retired.first_key_value() {
            if at > effect {
                break;
            }
            self.retired.remove(&pos);
            self.frozen_headers.remove(&order);
            self.sparse.remove(&order);
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
                    if self.current_work_rows.get(&member.association_key) == Some(&key) {
                        self.current_work_rows.remove(&member.association_key);
                    }
                    if self.open_texts.get(&member.association_key) == Some(&key) {
                        self.open_texts.remove(&member.association_key);
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
        visible: &[TextVisible],
    ) -> Result<ObservationPlan> {
        let has_boundary = visible.iter().any(|text| {
            text.at.effect_seq > self.applied_effect
                && member_key(&text.atom).is_ok_and(|key| !self.open_texts.contains_key(&key))
        }) || facts.iter().any(|atom| {
            (atom.kind != ChatAtomKind::Text || independently_visible_text(atom).is_some())
                && !work(atom)
                && !hidden(atom)
                && self.admitted(atom)
        });
        if !has_boundary {
            return Ok(BTreeMap::new());
        }
        // One effect-local terminal index. A later terminal never supplies an earlier cut.
        let mut terminals = HashMap::new();
        for atom in facts {
            if let ChatAtomLifecycle::Terminal {
                ended: Some(at), ..
            } = atom.lifecycle
            {
                terminals
                    .entry(member_key(atom)?)
                    .and_modify(|old: &mut ChatFactPosition| *old = (*old).min(at))
                    .or_insert(at);
            }
        }
        let mut group = self.open_work.map(|order| {
            let header = &self.blocks[&order];
            (header.id.clone(), header.next_member)
        });
        let mut original_group = self.open_work;
        let mut rows: HashMap<String, DisplayMemberWrite> = HashMap::new();
        let mut seen_singles = BTreeSet::new();
        let mut requests = BTreeMap::new();
        for op in operations(facts, visible) {
            let boundary = match op {
                DisplayOperation::Atom(atom) if hidden(atom) || !self.admitted(atom) => continue,
                DisplayOperation::Atom(atom) if work(atom) => {
                    let key = member_key(atom)?;
                    if group.is_none() {
                        group = Some((block_identity(&self.database, atom, &key)?, 0));
                    }
                    let (id, next) = group.as_mut().expect("current Work");
                    let previous = rows.get(&key).or_else(|| {
                        original_group.and_then(|_| {
                            self.current_work_rows
                                .get(&key)
                                .and_then(|position| self.members.get(position))
                                .map(Arc::as_ref)
                        })
                    });
                    let (member_order, row_key, start) = if let Some(previous) = previous {
                        (
                            previous.head.member_order,
                            previous.head.member_key.clone(),
                            previous.head.record.start_fact,
                        )
                    } else {
                        *next = next
                            .checked_add(1)
                            .context("display member order exhausted")?;
                        (
                            *next,
                            display_member_key(id, atom)?,
                            match atom.lifecycle {
                                ChatAtomLifecycle::Active { started, .. } => started,
                                _ => None,
                            },
                        )
                    };
                    rows.insert(
                        key.clone(),
                        DisplayMemberWrite {
                            block_id: id.clone(),
                            association_key: key,
                            terminal: matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. }),
                            head: DisplayMemberHead {
                                member_key: row_key,
                                member_order,
                                record: record(atom.clone(), start),
                            },
                        },
                    );
                    continue;
                }
                DisplayOperation::Atom(atom)
                    if atom.kind == ChatAtomKind::Text
                        && independently_visible_text(atom).is_none() =>
                {
                    continue;
                }
                DisplayOperation::Atom(atom) => {
                    let key = member_key(atom)?;
                    if self.location(&key).is_some() || !seen_singles.insert(key) {
                        continue;
                    }
                    let Some(at) = evidence(atom) else { continue };
                    at
                }
                DisplayOperation::TextVisible(text) => {
                    let key = member_key(&text.atom)?;
                    if text.at.effect_seq <= self.applied_effect
                        || self.open_texts.contains_key(&key)
                        || !seen_singles.insert(key)
                    {
                        continue;
                    }
                    text.at
                }
            };
            if let Some(order) = original_group.take() {
                for position in self
                    .unfinished_members
                    .range((order, 0)..=(order, u64::MAX))
                {
                    let member = &self.members[position];
                    if terminals
                        .get(&member.association_key)
                        .is_none_or(|end| *end > boundary)
                    {
                        requests.insert(
                            member.association_key.clone(),
                            (boundary, member.as_ref().clone()),
                        );
                    }
                }
            }
            for (key, row) in rows.drain() {
                if !row.terminal && terminals.get(&key).is_none_or(|end| *end > boundary) {
                    requests.entry(key).or_insert((boundary, row));
                }
            }
            group = None;
        }
        let _ = effect;
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

    #[cfg(test)]
    pub fn prepare_capturing(
        &mut self,
        effect: u64,
        committed_at: i64,
        facts: &[ChatAtom],
        sources: &[ChatSourceState],
        completions: &[Arc<ChatItem>],
        capture: impl FnMut(&DisplayMemberWrite) -> Result<ObservationInput>,
    ) -> Result<Arc<PreparedDisplayDelta>> {
        // Synthetic display facts in these unit tests carry their content phase in this batch;
        // the atom's real start remains independent. Production always supplies Core evidence.
        let visible = facts
            .iter()
            .filter(|atom| {
                atom.kind == ChatAtomKind::Text
                    && atom.content_present == Some(true)
                    && matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. })
            })
            .map(|atom| TextVisible {
                atom: atom.clone(),
                at: ChatFactPosition {
                    effect_seq: effect,
                    suborder: evidence(atom).map_or(0, |at| at.suborder),
                },
            })
            .collect::<Vec<_>>();
        let _ = sources;
        self.prepare_visible(
            effect,
            committed_at,
            DisplayInput {
                facts,
                visible: &visible,
                observations: None,
            },
            completions,
            capture,
        )
    }

    pub fn prepare_visible(
        &mut self,
        effect: u64,
        committed_at: i64,
        input: DisplayInput<'_>,
        completions: &[Arc<ChatItem>],
        mut capture: impl FnMut(&DisplayMemberWrite) -> Result<ObservationInput>,
    ) -> Result<Arc<PreparedDisplayDelta>> {
        ensure!(
            effect > self.applied_effect,
            "display effect already folded"
        );
        let DisplayInput {
            facts,
            visible,
            observations,
        } = input;
        for text in visible {
            ensure!(
                text.atom.kind == ChatAtomKind::Text && text.at.effect_seq == effect,
                "TextVisible does not belong to this admitted effect"
            );
        }
        // Resolve every fallible observation before modifying this fold. A missing
        // owner/body fails the original retained effect, which can retry unchanged.
        let mut captured = HashMap::new();
        let planned;
        let requests = if let Some(requests) = observations {
            requests
        } else {
            planned = self.observation_requests(effect, facts, visible)?;
            &planned
        };
        for (key, (at, member)) in requests {
            let input = capture(member)?;
            captured.insert(
                key.clone(),
                observations::prepare(&self.database, member, input, *at, committed_at)?,
            );
        }
        let completed = completions
            .iter()
            .map(|item| (item.header.item_id.as_str(), item))
            .collect::<HashMap<_, _>>();
        let mut atoms = Vec::with_capacity(facts.len());
        for fact in facts {
            if !self.admitted(fact) {
                continue;
            }
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
                self.location(&key)
                    .as_ref()
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
        let mut thoughts = HashMap::new();
        for atom in &atoms {
            if let Some(thought) = completed_thinking_summary(atom, &completed)? {
                thoughts.insert(member_key(atom)?, thought);
            }
        }
        let mut touched = BTreeSet::new();
        let mut changed_members = BTreeMap::new();
        let mut remove_empty = Vec::new();
        let mut published = BTreeMap::new();
        let mut contents = Vec::new();
        let mut seen_singles = BTreeSet::new();
        for operation in operations(&atoms, visible) {
            let (atom, first_content_at) = match operation {
                DisplayOperation::Atom(atom) => (atom.clone(), independently_visible_text(atom)),
                DisplayOperation::TextVisible(text) => {
                    let key = member_key(&text.atom)?;
                    if text.at.effect_seq <= self.applied_effect
                        || self.open_texts.contains_key(&key)
                    {
                        continue;
                    }
                    ensure!(
                        text.atom.kind == ChatAtomKind::Text,
                        "content phase is not Text"
                    );
                    (
                        lightweight(text.atom.clone(), &self.database),
                        Some(text.at),
                    )
                }
            };
            if hidden(&atom) {
                continue;
            }
            let key = member_key(&atom)?;
            let location = self.location(&key);
            if atom.kind == ChatAtomKind::Text && first_content_at.is_none() && location.is_none() {
                continue;
            }
            if let Some(position) = location {
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
                update_member_counts(&mut header, Some(&previous.head.record.atom), &atom)?;
                if matches!(header.body, DisplayBlockBody::Work { .. })
                    && let Some(thought) = thoughts.get(&key)
                {
                    header.thinking_summary = Some(thought.clone());
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
                changed_members.insert(position, member.clone());
                if let DisplayBlockBody::Single { record, .. } = &mut header.body {
                    **record = next_record;
                }
                if matches!(header.body, DisplayBlockBody::Single { .. }) && member.terminal {
                    self.open_texts.remove(&key);
                }
                self.replace_header(header, &mut touched)?;
            } else {
                let order = if work(&atom) {
                    if let Some(order) = self.open_work {
                        order
                    } else {
                        self.create(&atom, &key, true, committed_at, &mut touched)?
                    }
                } else {
                    if !seen_singles.insert(key.clone()) {
                        continue;
                    }
                    self.seal_open_work(
                        first_content_at.or_else(|| evidence(&atom)),
                        (effect, committed_at),
                        &mut touched,
                        &mut changed_members,
                        &mut contents,
                        &mut captured,
                    )?;
                    let order = self.create(&atom, &key, false, committed_at, &mut touched)?;
                    let mut header = self.blocks[&order].as_ref().clone();
                    header.first_content_at = first_content_at;
                    self.replace_header(header, &mut touched)?;
                    order
                };
                let mut header = self.blocks[&order].as_ref().clone();
                header.next_member = header
                    .next_member
                    .checked_add(1)
                    .context("display member order exhausted")?;
                update_member_counts(&mut header, None, &atom)?;
                if matches!(header.body, DisplayBlockBody::Work { .. })
                    && let Some(thought) = thoughts.get(&key)
                {
                    header.thinking_summary = Some(thought.clone());
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
                                ChatAtomLifecycle::Terminal { started, .. }
                                    if first_content_at.is_some() =>
                                {
                                    started
                                }
                                ChatAtomLifecycle::Terminal { .. } => None,
                            },
                        ),
                    },
                });
                let position = (order, header.next_member);
                self.retained = self.retained.saturating_add(bytes(member.as_ref())?);
                if work(&atom) {
                    self.current_work_rows.insert(key, position);
                } else if !member.terminal {
                    self.open_texts.insert(key, position);
                }
                if !member.terminal {
                    self.unfinished_members.insert(position);
                }
                self.members.insert(position, member.clone());
                changed_members.insert(position, member);
                self.replace_header(header, &mut touched)?;
            }
            self.drain(
                (effect, committed_at),
                &mut touched,
                &mut published,
                &mut remove_empty,
            )?;
        }
        self.terminal_batches.insert(
            effect,
            changed_members
                .iter()
                .filter_map(|(position, member)| member.terminal.then_some(*position))
                .collect(),
        );
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

    fn replace_header(&mut self, header: DisplayHeader, touched: &mut BTreeSet<u64>) -> Result<()> {
        if let Some(old) = self
            .blocks
            .insert(header.block_order, Arc::new(header.clone()))
        {
            self.retained = self.retained.saturating_sub(header_bytes(old.as_ref())?);
        }
        self.retained = self.retained.saturating_add(header_bytes(&header)?);
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
        let id = block_identity(&self.database, atom, key)?;
        ensure!(
            !self.by_id.contains_key(&id),
            "display block identity reused"
        );
        let order = self.next_order;
        if is_work {
            self.open_work = Some(order);
        }
        let header = DisplayHeader {
            version: 4,
            id: id.clone(),
            source: atom.source.clone(),
            block_order: order,
            history_pos: None,
            boundary: None,
            first_content_at: None,
            sealed: false,
            unfinished: 0,
            next_member: 0,
            revision: 0,
            skip_display: false,
            thinking_summary: None,
            body: if is_work {
                DisplayBlockBody::Work {
                    timing: pl_protocol::WorkTiming {
                        started_at: committed_at,
                        finished_at: None,
                    },
                    members: DisplayBlockRef {
                        database_id: self.database.clone(),
                        block_id: id.clone(),
                    },
                }
            } else {
                DisplayBlockBody::Single {
                    visibility: SingleVisibility::Content,
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
        self.replace_header(header, touched)?;
        Ok(order)
    }

    fn seal_open_work(
        &mut self,
        at: Option<ChatFactPosition>,
        (effect, committed_at): (u64, i64),
        touched: &mut BTreeSet<u64>,
        changed_members: &mut BTreeMap<(u64, u64), Arc<DisplayMemberWrite>>,
        contents: &mut Vec<Arc<ChatContent>>,
        captured: &mut HashMap<String, observations::PreparedObservation>,
    ) -> Result<()> {
        let Some(at) = at else {
            return Ok(());
        };
        if let Some(order) = self.open_work.take() {
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
                    let prepared = captured
                        .remove(&previous.association_key)
                        .context("boundary observation was not prepared")?;
                    let member = prepared.member;
                    ensure!(
                        member.block_id == header.id
                            && member.head.member_key == previous.head.member_key,
                        "prepared boundary display identity differs"
                    );
                    update_member_counts(
                        &mut header,
                        Some(&previous.head.record.atom),
                        &member.head.record.atom,
                    )?;
                    header.revision = header
                        .revision
                        .checked_add(1)
                        .context("display revision exhausted")?;
                    self.retained = self
                        .retained
                        .saturating_sub(bytes(previous.as_ref())?)
                        .saturating_add(bytes(member.as_ref())?);
                    self.members.insert(position, member.clone());
                    changed_members.insert(position, member);
                    for content in prepared.contents {
                        self.retained = self
                            .retained
                            .saturating_add(content.data.len() as u64 + 192);
                        self.observations
                            .insert(content.descriptor.key.clone(), (effect, content.clone()));
                        self.observation_batches
                            .entry(effect)
                            .or_default()
                            .push(content.descriptor.key.clone());
                        contents.push(content);
                    }
                }
                self.unfinished_members.remove(&position);
            }
            self.current_work_rows.clear();
            header.boundary = Some(at);
            header.sealed = true;
            header.thinking_summary = None;
            if let DisplayBlockBody::Work { timing, .. } = &mut header.body {
                timing.finished_at = Some(committed_at);
            }
            self.replace_header(header, touched)?;
        }
        Ok(())
    }

    fn drain(
        &mut self,
        (effect, _committed_at): (u64, i64),
        touched: &mut BTreeSet<u64>,
        published: &mut BTreeMap<u64, (Arc<DisplayHeader>, Arc<DisplayBlock>)>,
        remove_empty: &mut Vec<Arc<DisplayHeader>>,
    ) -> Result<()> {
        loop {
            let order = self.blocks.range(..).next().map(|(order, _)| *order);
            let Some(order) = order else { break };
            let header = &self.blocks[&order];
            if !header.sealed {
                break;
            }
            let mut header = header.as_ref().clone();
            self.blocks.remove(&order);
            self.retained = self.retained.saturating_sub(header_bytes(&header)?);
            if header.skip_display {
                ensure!(
                    matches!(&header.body, DisplayBlockBody::Single { record, .. }
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
                    self.open_texts.remove(&member.association_key);
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
        Ok(())
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

fn update_member_counts(
    header: &mut DisplayHeader,
    old: Option<&ChatAtom>,
    atom: &ChatAtom,
) -> Result<()> {
    let terminal = matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. });
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
    if !matches!(header.body, DisplayBlockBody::Work { .. }) {
        let start = match &header.body {
            DisplayBlockBody::Single { record, .. } => record.start_fact,
            _ => None,
        };
        header.body = DisplayBlockBody::Single {
            record: Box::new(record(atom.clone(), start)),
            visibility: if terminal
                && header.first_content_at.is_some()
                && atom.kind == ChatAtomKind::Text
                && atom.content_present == Some(false)
            {
                SingleVisibility::FinalEmptyAfterContent
            } else {
                SingleVisibility::Content
            },
        };
        if terminal {
            header.boundary = evidence(atom);
            header.sealed = true;
            header.skip_display = false;
        }
        return Ok(());
    };
    Ok(())
}

#[cfg(test)]
mod tests;

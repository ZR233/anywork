//! The single Studio fold over canonical source facts. Completed members live in
//! the original store and the incremental member index, never in this accumulator.
use super::ProjectionError;
use pl_protocol::*;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::result::Result;
use std::sync::OnceLock;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
struct FactKey {
    effect: u64,
    suborder: u32,
    sequence: u64,
    tie: u64,
}
fn position(atom: &ChatAtom, terminal: bool) -> Option<ChatFactPosition> {
    match atom.lifecycle {
        ChatAtomLifecycle::Active { started, .. } => started,
        ChatAtomLifecycle::Terminal { started, ended, .. } => {
            if terminal {
                ended.or(started)
            } else {
                started.or(ended)
            }
        }
    }
}
fn key(atom: &ChatAtom, sequence: Option<u64>, terminal: bool) -> FactKey {
    let at = position(atom, terminal);
    FactKey {
        effect: at.map_or(0, |at| at.effect_seq),
        suborder: at.map_or(0, |at| at.suborder),
        sequence: if terminal {
            sequence.or(atom.source_order)
        } else {
            atom.source_order.or(sequence)
        }
        .unwrap_or(0),
        tie: sequence.or(atom.completion_seq).unwrap_or(0),
    }
}
fn outcome(atom: &ChatAtom) -> Option<ChatTerminalOutcome> {
    match atom.lifecycle {
        ChatAtomLifecycle::Active { .. } => None,
        ChatAtomLifecycle::Terminal { outcome, .. } => Some(outcome),
    }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Class {
    Text,
    Work,
    Status,
}
fn classify(atom: &ChatAtom) -> Class {
    match atom.kind {
        ChatAtomKind::Input | ChatAtomKind::Text => Class::Text,
        ChatAtomKind::Reasoning
        | ChatAtomKind::ToolCall
        | ChatAtomKind::FileChange
        | ChatAtomKind::Skill
            if matches!(atom.source, ChatSourceId::ForegroundTurn { .. })
                && atom.delivery != ChatDeliveryKind::Independent =>
        {
            Class::Work
        }
        _ => Class::Status,
    }
}
fn category(atom: &ChatAtom) -> TimelineCategory {
    match atom.kind {
        ChatAtomKind::Reasoning => TimelineCategory::Thinking,
        ChatAtomKind::FileChange => TimelineCategory::Edit,
        ChatAtomKind::ToolCall => match atom.tool.as_ref().map(|tool| tool.name.as_str()) {
            Some("read_file") => TimelineCategory::Read,
            Some("read_image" | "generate_image" | "show_image") => TimelineCategory::Image,
            Some("exec") => TimelineCategory::Command,
            Some("web_search") => TimelineCategory::Search,
            Some("apply_patch") => TimelineCategory::Edit,
            Some("wait" | "sleep") => TimelineCategory::Wait,
            _ => TimelineCategory::Other,
        },
        _ => TimelineCategory::Other,
    }
}
/// Frozen metadata only. Active wait presentations belong to mutable member
/// heads; payload bytes remain with their original content owner.
pub(in crate::studio) fn lightweight(atom: &ChatAtom) -> ChatAtom {
    let mut atom = atom.clone();
    atom.payload = None;
    atom.wait = None;
    atom.source_state = None;
    atom
}
/// Same-cut mutable member metadata, including the producer's active wait.
fn active_head(atom: &ChatAtom) -> ChatAtom {
    debug_assert!(outcome(atom).is_none());
    let mut atom = atom.clone();
    atom.payload = None;
    atom.source_state = None;
    atom
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::studio) struct MemberChange {
    pub item_id: String,
    pub member_order: u64,
    pub atom: ChatAtom,
    pub payload_bytes: Option<u64>,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
pub(in crate::studio) struct TimelineUpdate {
    facts: Vec<ChatAtom>,
    members: Vec<MemberChange>,
    current: Vec<TimelineItem>,
    recovery: Vec<u8>,
    next_position: u64,
    generation: String,
    #[serde(skip)]
    retained_bytes: OnceLock<u64>,
}
#[derive(Serialize)]
struct TimelineUpdateRetentionView<'a> {
    facts: &'a [ChatAtom],
    members: &'a [MemberChange],
    current: &'a [TimelineItem],
    recovery: &'a [u8],
    next_position: u64,
    generation: &'a str,
}
fn recovery_json_len(recovery: &[u8]) -> u64 {
    recovery
        .iter()
        .enumerate()
        .try_fold(2_u64, |len, (index, byte)| {
            let digits = if *byte < 10 {
                1
            } else if *byte < 100 {
                2
            } else {
                3
            };
            len.checked_add(digits)
                .and_then(|len| len.checked_add(u64::from(index > 0)))
        })
        .unwrap_or(u64::MAX)
}
impl TimelineUpdate {
    pub fn facts(&self) -> &[ChatAtom] {
        &self.facts
    }
    pub fn members(&self) -> &[MemberChange] {
        &self.members
    }
    pub fn current(&self) -> &[TimelineItem] {
        &self.current
    }
    pub fn recovery(&self) -> &[u8] {
        &self.recovery
    }
    pub fn next_position(&self) -> u64 {
        self.next_position
    }
    pub fn generation(&self) -> &str {
        &self.generation
    }
    pub fn retained_bytes(&self) -> u64 {
        *self.retained_bytes.get_or_init(|| {
            let view = TimelineUpdateRetentionView {
                facts: &self.facts,
                members: &self.members,
                current: &self.current,
                recovery: &[],
                next_position: self.next_position,
                generation: &self.generation,
            };
            serde_json::to_vec(&view).map_or(u64::MAX, |bytes| {
                u64::try_from(bytes.len())
                    .ok()
                    .and_then(|len| len.checked_sub(2))
                    .and_then(|len| len.checked_add(recovery_json_len(&self.recovery)))
                    .and_then(|len| len.checked_add(std::mem::size_of::<OnceLock<u64>>() as u64))
                    .unwrap_or(u64::MAX)
            })
        })
    }
}
impl Default for TimelineUpdate {
    fn default() -> Self {
        Self {
            facts: Vec::new(),
            members: Vec::new(),
            current: Vec::new(),
            recovery: br#"{"items":[],"active":{}}"#.to_vec(),
            next_position: 0,
            generation: String::new(),
            retained_bytes: OnceLock::new(),
        }
    }
}
#[derive(Debug, Clone, Serialize, Deserialize)]
struct ActiveMember {
    item_id: String,
    order: u64,
    atom: ChatAtom,
}
#[derive(Debug, Clone, Serialize, Deserialize)]
struct LiveItem {
    source_order: Option<u64>,
    item: TimelineItem,
    anchor: FactKey,
    ready_key: FactKey,
    last_terminal: Option<FactKey>,
    active: u32,
    next_member: u64,
    last_source_order: Option<u64>,
    empty: bool,
}
impl LiveItem {
    fn ready(&self) -> bool {
        self.active == 0
            && (self.item.kind != TimelineItemKind::WorkGroup || self.item.admission_closed)
    }
    fn source_key(&self) -> (bool, u64, FactKey) {
        (
            self.source_order.is_none(),
            self.source_order.unwrap_or(0),
            self.anchor,
        )
    }
}
#[derive(Debug, Serialize, Deserialize)]
struct Recovery {
    items: Vec<LiveItem>,
    active: BTreeMap<String, ActiveMember>,
}
#[derive(Serialize)]
struct RecoveryView<'a> {
    #[serde(serialize_with = "serialize_live_items")]
    items: &'a BTreeMap<u64, LiveItem>,
    active: &'a BTreeMap<String, ActiveMember>,
}
fn serialize_live_items<S: serde::Serializer>(
    items: &BTreeMap<u64, LiveItem>,
    serializer: S,
) -> Result<S::Ok, S::Error> {
    serializer.collect_seq(items.values())
}
type SourceItems = BTreeMap<(bool, u64, FactKey), BTreeSet<u64>>;
#[derive(Debug, Clone)]
pub(in crate::studio) struct TimelineProjection {
    // Only the published TimelineItems migration selects the old rule. Runtime
    // and later named content migrations always use typed-source semantics.
    published_classification: bool,
    database_id: String,
    generation: String,
    next_position: u64,
    items: BTreeMap<u64, LiveItem>,
    item_ids: BTreeMap<String, u64>,
    sources: BTreeMap<ChatSourceId, SourceItems>,
    ready: BTreeSet<(FactKey, u64)>,
    next_item: u64,
    active: BTreeMap<String, ActiveMember>,
    committed: Vec<TimelineItem>,
    changes: Vec<MemberChange>,
    facts: Vec<ChatAtom>,
    retained_bytes: OnceLock<u64>,
}
/// One bounded, already-retained effect's canonical inputs. The same six-part
/// key is used by the durable fact/source merge; every input is a commit point.
pub(in crate::studio) enum TimelineInput {
    Atom {
        atom: Box<ChatAtom>,
        payload: Option<PayloadData>,
    },
    SourceEnd {
        source: ChatSourceState,
    },
}
impl TimelineInput {
    pub fn order(
        &self,
        observed: u64,
    ) -> Result<(u64, u32, u64, u64, String, &'static str), ProjectionError> {
        Ok(match self {
            Self::Atom { atom, .. } => {
                let terminal = outcome(atom).is_some();
                let at = match atom.lifecycle {
                    ChatAtomLifecycle::Active { started, .. } => started,
                    ChatAtomLifecycle::Terminal { ended, .. } => ended,
                };
                (
                    at.map_or(observed, |at| at.effect_seq),
                    at.map_or(0, |at| at.suborder),
                    atom.source_order.or(atom.completion_seq).unwrap_or(0),
                    atom.completion_seq.unwrap_or(0),
                    atom.id.clone(),
                    if terminal { "terminal" } else { "start" },
                )
            }
            Self::SourceEnd { source } => (
                source.ended.map_or(observed, |at| at.effect_seq),
                source.ended.map_or(u32::MAX, |at| at.suborder),
                i64::MAX as u64,
                0,
                serde_json::to_string(&source.source)
                    .map_err(|error| ProjectionError::History(error.to_string()))?,
                "source",
            ),
        })
    }
}
fn overflow() -> ProjectionError {
    ProjectionError::History("timeline order/count exhausted".into())
}
fn add(value: &mut u32) -> Result<(), ProjectionError> {
    *value = value.checked_add(1).ok_or_else(overflow)?;
    Ok(())
}
impl TimelineProjection {
    pub(in crate::studio) fn new(
        database_id: String,
        generation: String,
        next_position: u64,
    ) -> Self {
        Self {
            published_classification: false,
            database_id,
            generation,
            next_position,
            items: BTreeMap::new(),
            item_ids: BTreeMap::new(),
            sources: BTreeMap::new(),
            ready: BTreeSet::new(),
            next_item: 0,
            active: BTreeMap::new(),
            committed: Vec::new(),
            changes: Vec::new(),
            facts: Vec::new(),
            retained_bytes: OnceLock::new(),
        }
    }
    pub(in crate::studio) fn published_classification(&mut self) {
        self.published_classification = true;
    }
    fn classify(&self, atom: &ChatAtom) -> Class {
        if self.published_classification
            && atom.kind == ChatAtomKind::Unknown
            && matches!(atom.source, ChatSourceId::ForegroundTurn { .. })
            && atom.delivery != ChatDeliveryKind::Independent
        {
            Class::Work
        } else {
            classify(atom)
        }
    }
    fn excluded(&self, atom: &ChatAtom) -> bool {
        !self.published_classification && atom.kind == ChatAtomKind::Inference
    }
    pub(in crate::studio) fn generation(&self) -> &str {
        &self.generation
    }
    pub(in crate::studio) fn apply_input(
        &mut self,
        input: TimelineInput,
    ) -> Result<(), ProjectionError> {
        match input {
            TimelineInput::Atom { atom, payload } => {
                if outcome(&atom).is_some() {
                    let sequence = atom.completion_seq.unwrap_or(0);
                    self.complete(*atom, sequence, payload)?;
                } else {
                    self.observe(&atom, None)?;
                }
            }
            TimelineInput::SourceEnd { source } => self.end_source(&source.source),
        }
        self.commit_ready()
    }
    pub(in crate::studio) fn database_id(&self) -> &str {
        &self.database_id
    }
    pub(in crate::studio) fn restore_recovery(
        &mut self,
        bytes: &[u8],
    ) -> Result<(), ProjectionError> {
        let state: Recovery =
            serde_json::from_slice(bytes).map_err(|e| ProjectionError::History(e.to_string()))?;
        for live in &state.items {
            let count = state
                .active
                .values()
                .filter(|member| member.item_id == live.item.id)
                .count();
            let group = live.item.kind == TimelineItemKind::WorkGroup;
            let malformed_group = if group {
                live.item.summary.as_ref().is_none_or(|summary| {
                    summary.active_count != live.active
                        || u64::from(summary.member_count) != live.next_member
                        || summary.active_count > summary.member_count
                }) || live.item.members.is_none()
                    || live.item.payload.is_some()
                    || !live.item.contents.is_empty()
                    || live.item.content_item_id.is_some()
                    || live.item.outcome.is_some()
            } else {
                live.item.summary.is_some() || live.item.members.is_some()
            };
            if count != live.active as usize
                || live.item.position.is_some()
                || live.item.id.is_empty()
                || malformed_group
                || state
                    .items
                    .iter()
                    .filter(|item| item.item.id == live.item.id)
                    .count()
                    != 1
                || live.item.members.as_ref().is_some_and(|reference| {
                    reference.database_id != self.database_id
                        || reference.projection_version != TIMELINE_PROJECTION_VERSION
                        || reference.projection_generation != self.generation
                        || reference.item_id != live.item.id
                })
            {
                return Err(ProjectionError::History(
                    "timeline recovery is inconsistent; original history preserved".into(),
                ));
            }
        }
        for (id, member) in &state.active {
            if id != &member.atom.id
                || outcome(&member.atom).is_some()
                || !state.items.iter().any(|item| {
                    item.item.id == member.item_id
                        && item.item.source == member.atom.source
                        && member.order < item.next_member
                })
            {
                return Err(ProjectionError::History(
                    "timeline recovery has orphan or invalid active member".into(),
                ));
            }
        }
        self.retained_bytes.take();
        self.items.clear();
        self.item_ids.clear();
        self.sources.clear();
        self.ready.clear();
        self.next_item = 0;
        for item in state.items {
            self.insert_item(item)?;
        }
        self.active = state.active;
        Ok(())
    }
    pub(in crate::studio) fn observe(
        &mut self,
        atom: &ChatAtom,
        sequence: Option<u64>,
    ) -> Result<(), ProjectionError> {
        // Current is a bounded preview, not a replay stream. Terminal facts enter
        // exactly once from the original completion publication.
        if outcome(atom).is_some() || atom.kind == ChatAtomKind::TurnReceipt || self.excluded(atom)
        {
            return Ok(());
        }
        if let Some(member) = self.active.get_mut(&atom.id) {
            let next = active_head(atom);
            if member.atom == next {
                return Ok(());
            }
            self.retained_bytes.take();
            member.atom = next.clone();
            if let Some(item) = self
                .items
                .values_mut()
                .find(|item| item.item.id == member.item_id)
                && item.item.kind != TimelineItemKind::WorkGroup
            {
                item.item.contents = next.contents.clone();
            }
            // A mutable active head is not a second start. The first frozen
            // phase remains immutable even when this update shares its batch.
            if self.items.values().any(|item| {
                item.item.id == member.item_id && item.item.kind == TimelineItemKind::WorkGroup
            }) {
                self.changes.push(MemberChange {
                    item_id: member.item_id.clone(),
                    member_order: member.order,
                    atom: next,
                    payload_bytes: None,
                });
            }
            return Ok(());
        }
        self.admit(atom.clone(), sequence, None)
    }
    pub(in crate::studio) fn complete(
        &mut self,
        atom: ChatAtom,
        sequence: u64,
        payload: Option<PayloadData>,
    ) -> Result<(), ProjectionError> {
        self.admit(atom, Some(sequence), payload)
    }
    /// Formal legacy normalization: a frozen source ordinal proves structural
    /// admission, not a historical start event. The stored input remains the
    /// original terminal metadata; no fabricated start/time is saved as a fact.
    pub(in crate::studio) fn admit_legacy_header(
        &mut self,
        atom: &ChatAtom,
    ) -> Result<(), ProjectionError> {
        if atom.kind == ChatAtomKind::TurnReceipt || self.excluded(atom) {
            return Ok(());
        }
        let mut header = lightweight(atom);
        let started = match atom.lifecycle {
            ChatAtomLifecycle::Active { started, .. }
            | ChatAtomLifecycle::Terminal { started, .. } => started,
        };
        header.lifecycle = ChatAtomLifecycle::Active {
            started,
            status: ChatActiveStatus::Running,
        };
        header.finished_at = None;
        header.completion_item_id = None;
        header.completion_seq = None;
        header.content_present = None;
        self.admit(header, atom.completion_seq, None)?;
        if outcome(atom).is_some() && self.classify(atom) == Class::Work {
            // A legacy header is not a real active fact. Keep only the group's
            // unresolved count; its member association is already an incremental
            // SQLite row and is restored one at a time for the actual terminal.
            self.retained_bytes.take();
            self.active.remove(&atom.id);
        }
        Ok(())
    }
    pub(in crate::studio) fn restore_legacy_member(
        &mut self,
        item_id: String,
        order: u64,
        atom: &ChatAtom,
    ) -> Result<(), ProjectionError> {
        if self.active.contains_key(&atom.id) {
            return Ok(());
        }
        if !self
            .items
            .values()
            .any(|item| item.item.id == item_id && item.active > 0)
        {
            return Err(ProjectionError::History(
                "legacy terminal has no unresolved item".into(),
            ));
        }
        self.retained_bytes.take();
        self.active.insert(
            atom.id.clone(),
            ActiveMember {
                item_id,
                order,
                atom: lightweight(atom),
            },
        );
        Ok(())
    }
    pub(in crate::studio) fn refresh_current(
        &mut self,
        atom: &ChatAtom,
    ) -> Result<(), ProjectionError> {
        if self.excluded(atom) {
            return Ok(());
        }
        if !self.active.contains_key(&atom.id) {
            return Err(ProjectionError::History(
                "saved active atom has no canonical start at rebuild cut".into(),
            ));
        }
        self.observe(atom, None)
    }
    fn admit(
        &mut self,
        atom: ChatAtom,
        sequence: Option<u64>,
        payload: Option<PayloadData>,
    ) -> Result<(), ProjectionError> {
        if self.excluded(&atom) {
            // Diagnostics cannot admit a member or close the current work segment.
            return Ok(());
        }
        self.retained_bytes.take();
        let terminal = outcome(&atom).is_some();
        if atom.kind == ChatAtomKind::TurnReceipt
            && outcome(&atom) == Some(ChatTerminalOutcome::Completed)
        {
            self.facts.push(lightweight(&atom));
            self.end_source(&atom.source);
            return Ok(());
        }
        let started = key(&atom, sequence, false);
        let ended = key(&atom, sequence, true);
        let existing = self.active.remove(&atom.id);
        let (index, order, fresh) = if let Some(member) = existing {
            let index = self.item_ids.get(&member.item_id).copied().ok_or_else(|| {
                ProjectionError::History("timeline active member lost its item".into())
            })?;
            (index, member.order, false)
        } else {
            let class = self.classify(&atom);
            if class != Class::Work {
                self.close_group_for(&atom.source, started);
            }
            let open = (class == Class::Work)
                .then(|| {
                    self.items.iter().rev().find_map(|(index, item)| {
                        (item.item.kind == TimelineItemKind::WorkGroup
                            && item.item.source == atom.source
                            && !item.item.admission_closed
                            && atom
                                .source_order
                                .zip(item.last_source_order)
                                .is_none_or(|(a, b)| a >= b))
                        .then_some(*index)
                    })
                })
                .flatten();
            let index = match open {
                Some(index) => index,
                None => {
                    let kind = match class {
                        Class::Text => TimelineItemKind::Text,
                        Class::Work => TimelineItemKind::WorkGroup,
                        Class::Status => TimelineItemKind::Status,
                    };
                    let prefix = match class {
                        Class::Text => "text",
                        Class::Work => "work",
                        Class::Status => "status",
                    };
                    let id = format!("{prefix}:{}", atom.id);
                    self.insert_item(LiveItem {
                        source_order: atom.source_order,
                        item: TimelineItem {
                            id: id.clone(),
                            kind,
                            source: atom.source.clone(),
                            atom_kind: (class != Class::Work).then_some(atom.kind),
                            delivery: atom.delivery,
                            text_channel: atom.text_channel,
                            turn_id: atom.turn_id.clone(),
                            started_at: atom.started_at,
                            finished_at: None,
                            outcome: None,
                            summary: (class == Class::Work).then_some(TimelineGroupSummary {
                                member_count: 0,
                                active_count: 0,
                                failed_count: 0,
                                cancelled_count: 0,
                                categories: Vec::new(),
                                started_at: atom.started_at,
                                finished_at: None,
                            }),
                            members: (class == Class::Work).then(|| TimelineMembersRef {
                                database_id: self.database_id.clone(),
                                projection_version: TIMELINE_PROJECTION_VERSION,
                                projection_generation: self.generation.clone(),
                                item_id: id,
                            }),
                            contents: Vec::new(),
                            payload: None,
                            content_item_id: None,
                            position: None,
                            admission_closed: false,
                        },
                        anchor: started,
                        ready_key: ended,
                        last_terminal: None,
                        active: 0,
                        next_member: 0,
                        last_source_order: None,
                        empty: false,
                    })?
                }
            };
            let item = self.items.get_mut(&index).expect("indexed live item");
            let order = item.next_member;
            item.next_member = order.checked_add(1).ok_or_else(overflow)?;
            item.last_source_order = atom.source_order.or(item.last_source_order);
            (index, order, true)
        };
        let payload_bytes = match &payload {
            Some(PayloadData::Inline { bytes }) => Some(bytes.len() as u64),
            Some(PayloadData::Deferred { byte_length, .. }) => Some(*byte_length),
            None => None,
        };
        let old_ready = self.items[&index].ready_key;
        self.ready.remove(&(old_ready, index));
        let item = self.items.get_mut(&index).expect("indexed live item");
        if fresh {
            add(&mut item.active)?;
            if let Some(summary) = &mut item.item.summary {
                add(&mut summary.member_count)?;
                let cat = category(&atom);
                if let Some(count) = summary
                    .categories
                    .iter_mut()
                    .find(|count| count.category == cat)
                {
                    add(&mut count.count)?;
                } else {
                    summary.categories.push(TimelineCategoryCount {
                        category: cat,
                        count: 1,
                    });
                    summary.categories.sort_by_key(|count| count.category);
                }
            }
        }
        if terminal {
            item.active = item.active.checked_sub(1).ok_or_else(overflow)?;
            item.ready_key = item.ready_key.max(ended);
            if item.last_terminal.is_none_or(|previous| ended >= previous) {
                item.last_terminal = Some(ended);
                item.item.finished_at = atom.finished_at;
            }
        } else {
            self.active.insert(
                atom.id.clone(),
                ActiveMember {
                    item_id: item.item.id.clone(),
                    order,
                    atom: active_head(&atom),
                },
            );
        }
        if let Some(summary) = &mut item.item.summary {
            summary.active_count = item.active;
            summary.finished_at = item.item.finished_at;
            match outcome(&atom) {
                Some(ChatTerminalOutcome::Failed) => add(&mut summary.failed_count)?,
                Some(ChatTerminalOutcome::Cancelled) => add(&mut summary.cancelled_count)?,
                _ => {}
            }
        } else {
            item.item.atom_kind = Some(atom.kind);
            item.item.delivery = atom.delivery;
            item.item.text_channel = atom.text_channel;
            item.item.outcome = outcome(&atom);
            item.item.contents = atom.contents.clone();
            item.item.content_item_id = atom.completion_item_id.clone();
            item.item.payload = payload.or(atom.payload.clone());
            item.empty = atom.content_present == Some(false);
            item.item.admission_closed = terminal;
        }
        self.facts.push(lightweight(&atom));
        if item.item.kind == TimelineItemKind::WorkGroup {
            self.changes.push(MemberChange {
                item_id: item.item.id.clone(),
                member_order: order,
                atom: if terminal {
                    lightweight(&atom)
                } else {
                    active_head(&atom)
                },
                payload_bytes,
            });
        }
        self.refresh_ready(index);
        Ok(())
    }
    fn refresh_ready(&mut self, index: u64) {
        let item = &self.items[&index];
        let eligible = item.item.kind == TimelineItemKind::Status
            || self
                .sources
                .get(&item.item.source)
                .and_then(|items| items.first_key_value())
                .is_some_and(|(key, _)| *key == item.source_key());
        if eligible && item.ready() {
            self.ready.insert((item.ready_key, index));
        }
    }
    fn insert_item(&mut self, item: LiveItem) -> Result<u64, ProjectionError> {
        let index = self.next_item;
        self.next_item = index.checked_add(1).ok_or_else(overflow)?;
        if item.item.kind != TimelineItemKind::Status {
            let key = item.source_key();
            let source = self.sources.entry(item.item.source.clone()).or_default();
            if let Some((first, bucket)) = source.first_key_value()
                && key < *first
            {
                for old in bucket {
                    self.ready.remove(&(self.items[old].ready_key, *old));
                }
            }
            source.entry(key).or_default().insert(index);
        }
        self.item_ids.insert(item.item.id.clone(), index);
        self.items.insert(index, item);
        self.refresh_ready(index);
        Ok(index)
    }
    fn remove_item(&mut self, index: u64) -> LiveItem {
        let item = self.items.remove(&index).expect("ready item exists");
        self.item_ids.remove(&item.item.id);
        if item.item.kind != TimelineItemKind::Status {
            let source = self
                .sources
                .get_mut(&item.item.source)
                .expect("indexed source");
            let key = item.source_key();
            let bucket = source.get_mut(&key).expect("indexed source position");
            bucket.remove(&index);
            if bucket.is_empty() {
                source.remove(&key);
                if let Some((_, next)) = source.first_key_value() {
                    let next: Vec<_> = next.iter().copied().collect();
                    for index in next {
                        self.refresh_ready(index);
                    }
                } else {
                    self.sources.remove(&item.item.source);
                }
            }
        }
        item
    }
    fn close_groups(&mut self, source: &ChatSourceId, at: Option<FactKey>) {
        let indices: Vec<_> = self
            .sources
            .get(source)
            .into_iter()
            .flat_map(|items| items.values())
            .flatten()
            .copied()
            .collect();
        for index in indices {
            let item = self.items.get_mut(&index).expect("indexed source item");
            if item.item.kind == TimelineItemKind::WorkGroup && !item.item.admission_closed {
                self.retained_bytes.take();
                self.ready.remove(&(item.ready_key, index));
                item.item.admission_closed = true;
                if let Some(at) = at {
                    item.ready_key = item.ready_key.max(at);
                }
                self.refresh_ready(index);
            }
        }
    }
    fn close_group_for(&mut self, source: &ChatSourceId, at: FactKey) {
        self.close_groups(source, Some(at));
    }
    pub(in crate::studio) fn end_source(&mut self, source: &ChatSourceId) {
        self.close_groups(source, None);
    }
    pub(in crate::studio) fn commit_ready(&mut self) -> Result<(), ProjectionError> {
        while let Some(&(ready_key, index)) = self.ready.first() {
            let item = &self.items[&index];
            let visible = item.item.kind != TimelineItemKind::Text || !item.empty;
            let next = if visible {
                Some(
                    self.next_position
                        .checked_add(1)
                        .filter(|next| *next <= i64::MAX as u64)
                        .ok_or_else(overflow)?,
                )
            } else {
                None
            };
            self.ready.remove(&(ready_key, index));
            self.retained_bytes.take();
            let mut live = self.remove_item(index);
            if !visible {
                continue;
            }
            live.item.position = Some(self.next_position);
            live.item.admission_closed = true;
            self.next_position = next.expect("visible item has a validated position");
            self.committed.push(live.item);
        }
        Ok(())
    }
    pub(in crate::studio) fn current_items(&self) -> Vec<TimelineItem> {
        let mut streams: Vec<VecDeque<u64>> = self
            .sources
            .values()
            .map(|items| items.values().flatten().copied().collect())
            .collect();
        let mut next = BTreeSet::new();
        for (stream, items) in streams.iter_mut().enumerate() {
            if let Some(index) = items.pop_front() {
                next.insert((self.items[&index].anchor, index, stream));
            }
        }
        for (index, item) in &self.items {
            if item.item.kind == TimelineItemKind::Status {
                next.insert((item.anchor, *index, usize::MAX));
            }
        }
        let mut result = Vec::with_capacity(self.items.len());
        while let Some((_, index, stream)) = next.pop_first() {
            result.push(self.items[&index].item.clone());
            if stream != usize::MAX
                && let Some(index) = streams[stream].pop_front()
            {
                next.insert((self.items[&index].anchor, index, stream));
            }
        }
        result
    }
    pub(in crate::studio) fn take_committed(&mut self) -> Vec<TimelineItem> {
        if !self.committed.is_empty() {
            self.retained_bytes.take();
        }
        std::mem::take(&mut self.committed)
    }
    fn recovery(&self) -> Result<Vec<u8>, ProjectionError> {
        let recovery = serde_json::to_vec(&RecoveryView {
            items: &self.items,
            active: &self.active,
        })
        .map_err(|e| ProjectionError::History(e.to_string()))?;
        if recovery.len() > CHAT_BATCH_MAX_BYTES as usize {
            return Err(ProjectionError::History(
                "timeline recovery exceeds current budget".into(),
            ));
        }
        Ok(recovery)
    }
    pub(in crate::studio) fn check_recovery_budget(&self) -> Result<(), ProjectionError> {
        self.recovery().map(drop)
    }
    pub(in crate::studio) fn take_update(&mut self) -> Result<TimelineUpdate, ProjectionError> {
        let recovery = self.recovery()?;
        let mut update = self.take_changes();
        update.current = self.current_items();
        update.recovery = recovery;
        Ok(update)
    }
    /// Migration drains ordered deltas without freezing the unchanged full head.
    /// Its caller writes the final complete head in the same migration transaction.
    pub(in crate::studio) fn take_changes(&mut self) -> TimelineUpdate {
        if !self.facts.is_empty() || !self.changes.is_empty() {
            self.retained_bytes.take();
        }
        TimelineUpdate {
            facts: std::mem::take(&mut self.facts),
            members: std::mem::take(&mut self.changes),
            current: Vec::new(),
            recovery: Vec::new(),
            next_position: self.next_position,
            generation: self.generation.clone(),
            retained_bytes: OnceLock::new(),
        }
    }
    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        *self.retained_bytes.get_or_init(|| {
            serde_json::to_vec(&(
                &self.items,
                &self.active,
                &self.committed,
                &self.changes,
                &self.facts,
            ))
            .map_or(u64::MAX, |bytes| {
                (bytes.len() as u64)
                    .saturating_add(std::mem::size_of::<OnceLock<u64>>() as u64)
                    .saturating_add(
                        self.items
                            .values()
                            .map(|item| {
                                512_u64
                                    .saturating_add(item.item.id.len() as u64)
                                    .saturating_add(
                                        serde_json::to_vec(&item.item.source)
                                            .map_or(u64::MAX, |bytes| bytes.len() as u64),
                                    )
                            })
                            .fold(0_u64, u64::saturating_add),
                    )
            })
        })
    }
    #[cfg(test)]
    pub(in crate::studio) fn committed(&self) -> &[TimelineItem] {
        &self.committed
    }
}
#[cfg(test)]
mod tests;

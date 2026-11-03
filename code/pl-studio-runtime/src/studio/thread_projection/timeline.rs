//! The single Studio fold over canonical source facts. Completed members live in
//! the original store and the incremental member index, never in this accumulator.
use super::ProjectionError;
use pl_protocol::*;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::result::Result;

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
        | ChatAtomKind::Unknown
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
/// Metadata only. Wait presentations, previews and payload bytes have their own
/// owners and must not become a hidden second content/history store.
pub(in crate::studio) fn lightweight(atom: &ChatAtom) -> ChatAtom {
    let mut atom = atom.clone();
    atom.payload = None;
    atom.wait = None;
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
    pub facts: Vec<ChatAtom>,
    pub members: Vec<MemberChange>,
    pub current: Vec<TimelineItem>,
    pub recovery: Vec<u8>,
    pub next_position: u64,
    pub generation: String,
}
impl TimelineUpdate {
    pub fn retained_bytes(&self) -> u64 {
        serde_json::to_vec(self).map_or(u64::MAX, |bytes| bytes.len() as u64)
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
    fn precedes(&self, other: &Self) -> bool {
        self.item.kind != TimelineItemKind::Status
            && other.item.kind != TimelineItemKind::Status
            && self.item.source == other.item.source
            && match (self.source_order, other.source_order) {
                (Some(left), Some(right)) => {
                    left < right || (left == right && self.anchor < other.anchor)
                }
                (Some(_), None) => true,
                (None, Some(_)) => false,
                (None, None) => self.anchor < other.anchor,
            }
    }
}
#[derive(Debug, Serialize, Deserialize)]
struct Recovery {
    items: Vec<LiveItem>,
    active: BTreeMap<String, ActiveMember>,
}
#[derive(Debug, Clone)]
pub(in crate::studio) struct TimelineProjection {
    database_id: String,
    generation: String,
    next_position: u64,
    items: Vec<LiveItem>,
    active: BTreeMap<String, ActiveMember>,
    committed: Vec<TimelineItem>,
    changes: Vec<MemberChange>,
    facts: Vec<ChatAtom>,
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
            database_id,
            generation,
            next_position,
            items: Vec::new(),
            active: BTreeMap::new(),
            committed: Vec::new(),
            changes: Vec::new(),
            facts: Vec::new(),
        }
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
                    "timeline recovery requires maintenance".into(),
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
        self.items = state.items;
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
        if outcome(atom).is_some() || atom.kind == ChatAtomKind::TurnReceipt {
            return Ok(());
        }
        if let Some(member) = self.active.get_mut(&atom.id) {
            let next = lightweight(atom);
            if member.atom == next {
                return Ok(());
            }
            member.atom = next.clone();
            if let Some(item) = self
                .items
                .iter_mut()
                .find(|item| item.item.id == member.item_id)
                && item.item.kind != TimelineItemKind::WorkGroup
            {
                item.item.contents = next.contents.clone();
            }
            if let Some(fact) = self
                .facts
                .iter_mut()
                .find(|fact| fact.id == atom.id && outcome(fact).is_none())
            {
                *fact = next.clone();
            }
            if self.items.iter().any(|item| {
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
        if atom.kind == ChatAtomKind::TurnReceipt {
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
        if outcome(atom).is_some() && classify(atom) == Class::Work {
            // A legacy header is not a real active fact. Keep only the group's
            // unresolved count; its member association is already an incremental
            // SQLite row and is restored one at a time for the actual terminal.
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
            .iter()
            .any(|item| item.item.id == item_id && item.active > 0)
        {
            return Err(ProjectionError::History(
                "legacy terminal has no unresolved item".into(),
            ));
        }
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
            let index = self
                .items
                .iter()
                .position(|item| item.item.id == member.item_id)
                .ok_or_else(|| {
                    ProjectionError::History("timeline active member lost its item".into())
                })?;
            (index, member.order, false)
        } else {
            let class = classify(&atom);
            if class != Class::Work {
                self.close_group_for(&atom.source, started);
            }
            let open = (class == Class::Work)
                .then(|| {
                    self.items.iter().rposition(|item| {
                        item.item.kind == TimelineItemKind::WorkGroup
                            && item.item.source == atom.source
                            && !item.item.admission_closed
                            && atom
                                .source_order
                                .zip(item.last_source_order)
                                .is_none_or(|(a, b)| a >= b)
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
                    self.items.push(LiveItem {
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
                    });
                    self.items.len() - 1
                }
            };
            let item = &mut self.items[index];
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
        let item = &mut self.items[index];
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
                    atom: lightweight(&atom),
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
                atom: lightweight(&atom),
                payload_bytes,
            });
        }
        Ok(())
    }
    fn close_group_for(&mut self, source: &ChatSourceId, at: FactKey) {
        for item in &mut self.items {
            if item.item.kind == TimelineItemKind::WorkGroup
                && &item.item.source == source
                && !item.item.admission_closed
            {
                item.item.admission_closed = true;
                item.ready_key = item.ready_key.max(at);
            }
        }
    }
    pub(in crate::studio) fn end_source(&mut self, source: &ChatSourceId) {
        for item in &mut self.items {
            if &item.item.source == source && item.item.kind == TimelineItemKind::WorkGroup {
                item.item.admission_closed = true;
            }
        }
    }
    pub(in crate::studio) fn commit_ready(&mut self) -> Result<(), ProjectionError> {
        loop {
            let next = self
                .items
                .iter()
                .enumerate()
                .filter(|(_, item)| item.ready())
                .filter(|(_, item)| !self.items.iter().any(|other| other.precedes(item)))
                .min_by_key(|(_, item)| item.ready_key)
                .map(|(index, _)| index);
            let Some(index) = next else {
                break;
            };
            if self.items[index].item.kind == TimelineItemKind::Text && self.items[index].empty {
                self.items.remove(index);
                continue;
            }
            let next = self
                .next_position
                .checked_add(1)
                .filter(|next| *next <= i64::MAX as u64)
                .ok_or_else(overflow)?;
            let mut live = self.items.remove(index);
            live.item.position = Some(self.next_position);
            live.item.admission_closed = true;
            self.next_position = next;
            self.committed.push(live.item);
        }
        Ok(())
    }
    pub(in crate::studio) fn current_items(&self) -> Vec<TimelineItem> {
        let mut pending: Vec<_> = self.items.iter().collect();
        let mut result = Vec::with_capacity(pending.len());
        while !pending.is_empty() {
            let next = pending
                .iter()
                .enumerate()
                .filter(|(_, item)| !pending.iter().any(|other| other.precedes(item)))
                .min_by_key(|(_, item)| item.anchor)
                .map(|(index, _)| index)
                .expect("source order is acyclic");
            result.push(pending.remove(next).item.clone());
        }
        result
    }
    pub(in crate::studio) fn take_committed(&mut self) -> Vec<TimelineItem> {
        std::mem::take(&mut self.committed)
    }
    pub(in crate::studio) fn take_update(&mut self) -> Result<TimelineUpdate, ProjectionError> {
        let recovery = serde_json::to_vec(&Recovery {
            items: self.items.clone(),
            active: self.active.clone(),
        })
        .map_err(|e| ProjectionError::History(e.to_string()))?;
        if recovery.len() > CHAT_BATCH_MAX_BYTES as usize {
            return Err(ProjectionError::History(
                "timeline recovery exceeds current budget".into(),
            ));
        }
        Ok(TimelineUpdate {
            facts: std::mem::take(&mut self.facts),
            members: std::mem::take(&mut self.changes),
            current: self.current_items(),
            recovery,
            next_position: self.next_position,
            generation: self.generation.clone(),
        })
    }
    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        serde_json::to_vec(&(
            &self.items,
            &self.active,
            &self.committed,
            &self.changes,
            &self.facts,
        ))
        .map_or(u64::MAX, |bytes| bytes.len() as u64)
    }
    #[cfg(test)]
    pub(in crate::studio) fn committed(&self) -> &[TimelineItem] {
        &self.committed
    }
}
#[cfg(test)]
mod tests;

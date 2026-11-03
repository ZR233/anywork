//! The single Studio fold over canonical source facts. Completed members live in
//! the original store and the incremental member index, never in this accumulator.
use std::collections::BTreeMap;
use pl_protocol::*;
use serde::{Deserialize, Serialize};
use super::ProjectionError;

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
struct FactKey { effect: u64, suborder: u32, sequence: u64 }
fn position(atom: &ChatAtom, terminal: bool) -> Option<ChatFactPosition> {
    match atom.lifecycle {
        ChatAtomLifecycle::Active { started, .. } => started,
        ChatAtomLifecycle::Terminal { started, ended, .. } => if terminal { ended.or(started) } else { started.or(ended) },
    }
}
fn key(atom: &ChatAtom, sequence: Option<u64>, terminal: bool) -> FactKey {
    let at = position(atom, terminal);
    FactKey { effect: at.map_or(0, |at| at.effect_seq), suborder: at.map_or(0, |at| at.suborder), sequence: sequence.or(atom.source_order).unwrap_or(0) }
}
fn outcome(atom: &ChatAtom) -> Option<ChatTerminalOutcome> {
    match atom.lifecycle { ChatAtomLifecycle::Active { .. } => None, ChatAtomLifecycle::Terminal { outcome, .. } => Some(outcome) }
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Class { Text, Work, Status }
fn classify(atom: &ChatAtom) -> Class {
    match atom.kind {
        ChatAtomKind::Input | ChatAtomKind::Text => Class::Text,
        ChatAtomKind::Reasoning | ChatAtomKind::ToolCall | ChatAtomKind::FileChange | ChatAtomKind::Skill | ChatAtomKind::Unknown
            if matches!(atom.source, ChatSourceId::ForegroundTurn { .. }) && atom.delivery != ChatDeliveryKind::Independent => Class::Work,
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
}
impl TimelineUpdate {
    pub fn retained_bytes(&self) -> u64 {
        serde_json::to_vec(self).map_or(u64::MAX, |bytes| bytes.len() as u64)
    }
}
impl Default for TimelineUpdate {
    fn default() -> Self {
        Self { facts: Vec::new(), members: Vec::new(), current: Vec::new(),
            recovery: br#"{"items":[],"active":{}}"#.to_vec(), next_position: 0 }
    }
}
#[derive(Debug, Clone, Serialize, Deserialize)]
struct ActiveMember { item_id: String, order: u64, atom: ChatAtom }
#[derive(Debug, Clone, Serialize, Deserialize)]
struct LiveItem {
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
    fn ready(&self) -> bool { self.active == 0 && (self.item.kind != TimelineItemKind::WorkGroup || self.item.admission_closed) }
}
#[derive(Debug, Serialize, Deserialize)]
struct Recovery { items: Vec<LiveItem>, active: BTreeMap<String, ActiveMember> }
#[derive(Debug)]
pub(in crate::studio) struct TimelineProjection {
    database_id: String,
    next_position: u64,
    items: Vec<LiveItem>,
    active: BTreeMap<String, ActiveMember>,
    committed: Vec<TimelineItem>,
    changes: Vec<MemberChange>,
    facts: Vec<ChatAtom>,
}
fn overflow() -> ProjectionError { ProjectionError::History("timeline order/count exhausted".into()) }
fn add(value: &mut u32) -> Result<(), ProjectionError> { *value = value.checked_add(1).ok_or_else(overflow)?; Ok(()) }
impl TimelineProjection {
    pub(in crate::studio) fn new(database_id: String, next_position: u64) -> Self {
        Self { database_id, next_position, items: Vec::new(), active: BTreeMap::new(), committed: Vec::new(), changes: Vec::new(), facts: Vec::new() }
    }
    pub(in crate::studio) fn database_id(&self) -> &str { &self.database_id }
    pub(in crate::studio) fn restore_recovery(&mut self, bytes: &[u8]) -> Result<(), ProjectionError> {
        let state: Recovery = serde_json::from_slice(bytes).map_err(|e| ProjectionError::History(e.to_string()))?;
        for live in &state.items {
            let count = state.active.values().filter(|member| member.item_id == live.item.id).count();
            if count != live.active as usize || live.item.position.is_some()
                || live.item.members.as_ref().is_some_and(|reference| reference.database_id != self.database_id
                    || reference.projection_version != TIMELINE_PROJECTION_VERSION || reference.item_id != live.item.id) {
                return Err(ProjectionError::History("timeline recovery requires maintenance".into()));
            }
        }
        for member in state.active.values() {
            if !state.items.iter().any(|item| item.item.id == member.item_id) { return Err(ProjectionError::History("timeline recovery has orphan active member".into())); }
        }
        self.items = state.items;
        self.active = state.active;
        Ok(())
    }
    pub(in crate::studio) fn observe(&mut self, atom: &ChatAtom, sequence: Option<u64>) -> Result<(), ProjectionError> {
        // Current is a bounded preview, not a replay stream. Terminal facts enter
        // exactly once from the original completion publication.
        if outcome(atom).is_some() { return Ok(()); }
        if let Some(member) = self.active.get_mut(&atom.id) {
            let next = lightweight(atom);
            if member.atom == next { return Ok(()); }
            member.atom = next.clone();
            if let Some(item) = self.items.iter_mut().find(|item| item.item.id == member.item_id)
                && item.item.kind != TimelineItemKind::WorkGroup {
                item.item.contents = next.contents.clone();
            }
            if let Some(fact) = self.facts.iter_mut().find(|fact| fact.id == atom.id && outcome(fact).is_none()) {
                *fact = next.clone();
            }
            if self.items.iter().any(|item| item.item.id == member.item_id && item.item.kind == TimelineItemKind::WorkGroup) {
                self.changes.push(MemberChange { item_id: member.item_id.clone(), member_order: member.order,
                    atom: next, payload_bytes: None });
            }
            return Ok(());
        }
        self.admit(atom.clone(), sequence, None)
    }
    pub(in crate::studio) fn complete(&mut self, atom: ChatAtom, sequence: u64, payload: Option<PayloadData>) -> Result<(), ProjectionError> {
        self.admit(atom, Some(sequence), payload)
    }
    fn admit(&mut self, atom: ChatAtom, sequence: Option<u64>, payload: Option<PayloadData>) -> Result<(), ProjectionError> {
        let terminal = outcome(&atom).is_some();
        if atom.kind == ChatAtomKind::TurnReceipt && outcome(&atom) == Some(ChatTerminalOutcome::Completed) {
            self.facts.push(lightweight(&atom));
            self.end_source(&atom.source);
            return Ok(());
        }
        let started = key(&atom, sequence, false);
        let ended = key(&atom, sequence, true);
        let existing = self.active.remove(&atom.id);
        let (index, order, fresh) = if let Some(member) = existing {
            let index = self.items.iter().position(|item| item.item.id == member.item_id)
                .ok_or_else(|| ProjectionError::History("timeline active member lost its item".into()))?;
            (index, member.order, false)
        } else {
            let class = classify(&atom);
            if class != Class::Work { self.close_group_for(&atom.source, started); }
            let open = (class == Class::Work).then(|| self.items.iter().rposition(|item| {
                item.item.kind == TimelineItemKind::WorkGroup && item.item.source == atom.source && !item.item.admission_closed
                    && atom.source_order.zip(item.last_source_order).is_none_or(|(a,b)| a > b)
            })).flatten();
            let index = match open {
                Some(index) => index,
                None => {
                    let kind = match class { Class::Text => TimelineItemKind::Text, Class::Work => TimelineItemKind::WorkGroup, Class::Status => TimelineItemKind::Status };
                    let prefix = match class { Class::Text => "text", Class::Work => "work", Class::Status => "status" };
                    let id = format!("{prefix}:{}", atom.id);
                    self.items.push(LiveItem {
                        item: TimelineItem {
                            id: id.clone(), kind, source: atom.source.clone(), atom_kind: (class != Class::Work).then_some(atom.kind), delivery: atom.delivery,
                            text_channel: atom.text_channel, turn_id: atom.turn_id.clone(), started_at: atom.started_at, finished_at: None,
                            outcome: None,
                            summary: (class == Class::Work).then_some(TimelineGroupSummary { member_count: 0, active_count: 0, failed_count: 0, cancelled_count: 0, categories: Vec::new(), started_at: atom.started_at, finished_at: None }),
                            members: (class == Class::Work).then(|| TimelineMembersRef { database_id: self.database_id.clone(), projection_version: TIMELINE_PROJECTION_VERSION, item_id: id }),
                            contents: Vec::new(), payload: None, content_item_id: None, position: None, admission_closed: false,
                        },
                        anchor: started, ready_key: ended, last_terminal: None, active: 0, next_member: 0, last_source_order: None, empty: false,
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
                if let Some(count) = summary.categories.iter_mut().find(|count| count.category == cat) { add(&mut count.count)?; }
                else { summary.categories.push(TimelineCategoryCount { category: cat, count: 1 }); summary.categories.sort_by_key(|count| count.category); }
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
            self.active.insert(atom.id.clone(), ActiveMember { item_id: item.item.id.clone(), order, atom: lightweight(&atom) });
        }
        if let Some(summary) = &mut item.item.summary {
            summary.active_count = item.active;
            summary.finished_at = item.item.finished_at;
            match outcome(&atom) { Some(ChatTerminalOutcome::Failed) => add(&mut summary.failed_count)?, Some(ChatTerminalOutcome::Cancelled) => add(&mut summary.cancelled_count)?, _ => {} }
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
            self.changes.push(MemberChange { item_id: item.item.id.clone(), member_order: order, atom: lightweight(&atom), payload_bytes });
        }
        Ok(())
    }
    fn close_group_for(&mut self, source: &ChatSourceId, at: FactKey) {
        for item in &mut self.items {
            if item.item.kind == TimelineItemKind::WorkGroup && &item.item.source == source && !item.item.admission_closed {
                item.item.admission_closed = true;
                item.ready_key = item.ready_key.max(at);
            }
        }
    }
    pub(in crate::studio) fn end_source(&mut self, source: &ChatSourceId) {
        for item in &mut self.items { if &item.item.source == source && item.item.kind == TimelineItemKind::WorkGroup { item.item.admission_closed = true; } }
    }
    pub(in crate::studio) fn commit_ready(&mut self) -> Result<(), ProjectionError> {
        loop {
            let next = self.items.iter().enumerate().filter(|(_,item)| item.ready())
                .filter(|(_,item)| !self.items.iter().any(|other| other.item.source == item.item.source && other.anchor < item.anchor))
                .min_by_key(|(_,item)| item.ready_key).map(|(index,_)| index);
            let Some(index) = next else { break; };
            if self.items[index].item.kind == TimelineItemKind::Text && self.items[index].empty {
                self.items.remove(index);
                continue;
            }
            let next = self.next_position.checked_add(1).filter(|next| *next <= i64::MAX as u64).ok_or_else(overflow)?;
            let mut live = self.items.remove(index);
            live.item.position = Some(self.next_position);
            live.item.admission_closed = true;
            self.next_position = next;
            self.committed.push(live.item);
        }
        Ok(())
    }
    pub(in crate::studio) fn current_items(&self) -> Vec<TimelineItem> {
        let mut items: Vec<_> = self.items.iter().collect();
        items.sort_by_key(|item| item.anchor);
        items.into_iter().map(|item| item.item.clone()).collect()
    }
    pub(in crate::studio) fn take_committed(&mut self) -> Vec<TimelineItem> { std::mem::take(&mut self.committed) }
    pub(in crate::studio) fn take_update(&mut self) -> Result<TimelineUpdate, ProjectionError> {
        let recovery = serde_json::to_vec(&Recovery { items: self.items.clone(), active: self.active.clone() }).map_err(|e| ProjectionError::History(e.to_string()))?;
        if recovery.len() > CHAT_BATCH_MAX_BYTES as usize { return Err(ProjectionError::History("timeline recovery exceeds current budget".into())); }
        Ok(TimelineUpdate { facts: std::mem::take(&mut self.facts), members: std::mem::take(&mut self.changes), current: self.current_items(), recovery, next_position: self.next_position })
    }
    pub(in crate::studio) fn set_next_position(&mut self, position: u64) { self.next_position = position; }
    pub(in crate::studio) fn retained_bytes(&self) -> u64 {
        serde_json::to_vec(&(&self.items, &self.active, &self.committed, &self.changes, &self.facts))
            .map_or(u64::MAX, |bytes| bytes.len() as u64)
    }
    #[cfg(test)]
    pub(in crate::studio) fn committed(&self) -> &[TimelineItem] { &self.committed }
}
#[cfg(test)]
mod tests;

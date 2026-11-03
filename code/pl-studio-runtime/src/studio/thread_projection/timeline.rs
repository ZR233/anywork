//! The single Studio Timeline display projection.
//!
//! Facts stay atomic: the projection only decides which facts form a text,
//! work-group or independent status item, in which order they enter history and
//! which members belong to each item. The same fold is used for live effects,
//! restart recovery and derived-data rebuild, so item identity and order do not
//! depend on a client page, a widget callback or the wall clock.

use std::collections::BTreeMap;

use pl_protocol::{
    ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatDeliveryKind, ChatFactPosition, ChatSourceId,
    ChatTerminalOutcome, PayloadData, TimelineCategory, TimelineCategoryCount,
    TimelineGroupSummary, TimelineItem, TimelineItemKind, TimelineMembersRef,
};

/// Canonical admission position of one observed fact. Facts without a recorded
/// source position keep their completion sequence and never borrow read time.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
struct FactKey {
    effect: u64,
    suborder: u32,
    sequence: u64,
}

fn positions(atom: &ChatAtom) -> (Option<ChatFactPosition>, Option<ChatFactPosition>) {
    match &atom.lifecycle {
        ChatAtomLifecycle::Active { started, .. } => (*started, None),
        ChatAtomLifecycle::Terminal { started, ended, .. } => (*started, *ended),
    }
}

fn fact_key(atom: &ChatAtom, sequence: Option<u64>) -> FactKey {
    let (started, ended) = positions(atom);
    match started.or(ended) {
        Some(position) => FactKey {
            effect: position.effect_seq,
            suborder: position.suborder,
            sequence: sequence.or(atom.source_order).unwrap_or(0),
        },
        None => FactKey {
            effect: 0,
            suborder: 0,
            sequence: sequence.or(atom.source_order).unwrap_or(0),
        },
    }
}

fn terminal_outcome(atom: &ChatAtom) -> Option<ChatTerminalOutcome> {
    match atom.lifecycle {
        ChatAtomLifecycle::Terminal { outcome, .. } => Some(outcome),
        ChatAtomLifecycle::Active { .. } => None,
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

/// Display-only category for one work member. Never used as a grouping rule.
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

fn payload_is_empty(payload: Option<&PayloadData>) -> bool {
    let Some(PayloadData::Inline { bytes }) = payload else {
        return false;
    };
    let Ok(value) = serde_json::from_slice::<serde_json::Value>(bytes) else {
        return false;
    };
    let text = value
        .pointer("/data/text")
        .and_then(serde_json::Value::as_str)
        .unwrap_or_default();
    let attachments = value
        .pointer("/data/attachments")
        .and_then(serde_json::Value::as_array)
        .map_or(0, Vec::len);
    text.trim().is_empty() && attachments == 0
}

#[derive(Debug, Clone)]
struct Member {
    atom: ChatAtom,
    terminal: bool,
    key: FactKey,
    payload: Option<PayloadData>,
}

#[derive(Debug, Clone)]
struct LiveItem {
    item: TimelineItem,
    members: BTreeMap<String, Member>,
    closed: bool,
    anchor: FactKey,
    ready_key: FactKey,
}

impl LiveItem {
    fn new(item: TimelineItem, anchor: FactKey) -> Self {
        Self {
            item,
            members: BTreeMap::new(),
            closed: false,
            anchor,
            ready_key: anchor,
        }
    }

    fn all_terminal(&self) -> bool {
        self.members.values().all(|member| member.terminal)
    }

    fn ready(&self) -> bool {
        let closed = match self.item.kind {
            TimelineItemKind::WorkGroup => self.closed,
            TimelineItemKind::Text | TimelineItemKind::Status => true,
        };
        closed && self.all_terminal()
    }

    fn ordered_members(&self) -> Vec<&Member> {
        let mut members: Vec<_> = self.members.values().collect();
        members.sort_by(|a, b| a.key.cmp(&b.key).then(a.atom.id.cmp(&b.atom.id)));
        members
    }

    fn insert(&mut self, member: Member) {
        self.closed |= self.item.kind != TimelineItemKind::WorkGroup;
        self.ready_key = self.ready_key.max(member.key);
        self.members.insert(member.atom.id.clone(), member);
        self.refresh();
    }

    fn refresh(&mut self) {
        let ordered = self.ordered_members();
        let members: Vec<Member> = ordered.into_iter().cloned().collect();
        self.item.current_members = members.iter().map(|m| m.atom.id.clone()).collect();
        self.item.admission_closed = match self.item.kind {
            TimelineItemKind::WorkGroup => self.closed,
            TimelineItemKind::Text | TimelineItemKind::Status => self.all_terminal(),
        };
        if let Some(first) = members.first() {
            self.item.source = first.atom.source.clone();
            self.item.turn_id = first.atom.turn_id.clone();
        }
        match self.item.kind {
            TimelineItemKind::WorkGroup => {
                let mut categories: BTreeMap<TimelineCategory, u32> = BTreeMap::new();
                let mut active = 0u32;
                let mut failed = 0u32;
                let mut cancelled = 0u32;
                for member in &members {
                    *categories.entry(category(&member.atom)).or_default() += 1;
                    match terminal_outcome(&member.atom) {
                        None => active += 1,
                        Some(ChatTerminalOutcome::Failed) => failed += 1,
                        Some(ChatTerminalOutcome::Cancelled) => cancelled += 1,
                        Some(ChatTerminalOutcome::Completed | ChatTerminalOutcome::Transferred) => {
                        }
                    }
                }
                let started_at = members.first().and_then(|m| m.atom.started_at);
                let finished_at = members
                    .iter()
                    .rev()
                    .find(|m| terminal_outcome(&m.atom).is_some())
                    .and_then(|m| m.atom.finished_at);
                self.item.started_at = started_at;
                self.item.finished_at = finished_at;
                self.item.summary = Some(TimelineGroupSummary {
                    member_count: u32::try_from(members.len()).unwrap_or(u32::MAX),
                    active_count: active,
                    failed_count: failed,
                    cancelled_count: cancelled,
                    categories: categories
                        .into_iter()
                        .map(|(category, count)| TimelineCategoryCount { category, count })
                        .collect(),
                    started_at,
                    finished_at,
                });
                self.item.members = Some(TimelineMembersRef {
                    item_id: self.item.id.clone(),
                });
            }
            TimelineItemKind::Text | TimelineItemKind::Status => {
                if let Some(member) = members.first() {
                    self.item.contents = member.atom.contents.clone();
                    self.item.payload = member.payload.clone();
                    self.item.started_at = member.atom.started_at;
                    self.item.finished_at = member.atom.finished_at;
                }
                self.item.summary = None;
                self.item.members = None;
            }
        }
    }

    fn single(atom: &ChatAtom, kind: TimelineItemKind, sequence: Option<u64>) -> Self {
        let prefix = match kind {
            TimelineItemKind::Text => "text",
            TimelineItemKind::Status => "status",
            TimelineItemKind::WorkGroup => "work",
        };
        let item = TimelineItem {
            id: format!("{prefix}:{}", atom.id),
            kind,
            source: atom.source.clone(),
            atom_kind: Some(atom.kind),
            delivery: atom.delivery,
            text_channel: atom.text_channel,
            turn_id: atom.turn_id.clone(),
            started_at: atom.started_at,
            finished_at: atom.finished_at,
            summary: None,
            members: None,
            contents: atom.contents.clone(),
            payload: None,
            current_members: vec![atom.id.clone()],
            position: None,
            admission_closed: false,
        };
        let key = fact_key(atom, sequence);
        let mut value = Self::new(item, key);
        value.insert(Member {
            atom: atom.clone(),
            terminal: terminal_outcome(atom).is_some(),
            key,
            payload: None,
        });
        value
    }

    fn group(atom: &ChatAtom, sequence: Option<u64>) -> Self {
        let key = fact_key(atom, sequence);
        let item = TimelineItem {
            id: format!("work:{}", atom.id),
            kind: TimelineItemKind::WorkGroup,
            source: atom.source.clone(),
            atom_kind: None,
            delivery: ChatDeliveryKind::Foreground,
            text_channel: None,
            turn_id: atom.turn_id.clone(),
            started_at: None,
            finished_at: None,
            summary: None,
            members: None,
            contents: Vec::new(),
            payload: None,
            current_members: Vec::new(),
            position: None,
            admission_closed: false,
        };
        let mut value = Self::new(item, key);
        value.insert(Member {
            atom: atom.clone(),
            terminal: terminal_outcome(atom).is_some(),
            key,
            payload: None,
        });
        value
    }
}

/// Live fold over ordered canonical facts. It keeps only uncommitted items and
/// the small committed delta of the effect being prepared.
#[derive(Debug)]
pub(in crate::studio) struct TimelineProjection {
    database_id: String,
    next_position: u64,
    items: Vec<LiveItem>,
    committed: Vec<TimelineItem>,
}

impl TimelineProjection {
    pub(in crate::studio) fn new(database_id: String, next_position: u64) -> Self {
        Self {
            database_id,
            next_position,
            items: Vec::new(),
            committed: Vec::new(),
        }
    }

    pub(in crate::studio) fn database_id(&self) -> &str {
        &self.database_id
    }

    /// Restores the open fragments from the persisted current projection. Every
    /// current item must resolve to its member facts; a missing member is a
    /// projection fault, not a reason to invent a new group.
    pub(in crate::studio) fn restore(
        &mut self,
        items: &[TimelineItem],
        atoms: &[ChatAtom],
    ) -> Result<(), super::ProjectionError> {
        let atoms: BTreeMap<&str, &ChatAtom> =
            atoms.iter().map(|atom| (atom.id.as_str(), atom)).collect();
        for item in items {
            let ids: Vec<&str> = item.current_members.iter().map(String::as_str).collect();
            if ids.is_empty() {
                return Err(super::ProjectionError::History(format!(
                    "current timeline item {} has no member facts",
                    item.id
                )));
            }
            let first = atoms.get(ids[0]).ok_or_else(|| {
                super::ProjectionError::History(format!(
                    "current timeline item {} is missing member {}",
                    item.id, ids[0]
                ))
            })?;
            let mut live = LiveItem::new(item.clone(), fact_key(first, None));
            live.closed = item.admission_closed;
            for id in ids {
                let atom = atoms.get(id).ok_or_else(|| {
                    super::ProjectionError::History(format!(
                        "current timeline item {} is missing member {id}",
                        item.id
                    ))
                })?;
                let key = fact_key(atom, None);
                live.insert(Member {
                    atom: (**atom).clone(),
                    terminal: terminal_outcome(atom).is_some(),
                    key,
                    payload: None,
                });
            }
            live.refresh();
            self.items.push(live);
        }
        self.items
            .sort_by(|a, b| a.anchor.cmp(&b.anchor).then(a.item.id.cmp(&b.item.id)));
        Ok(())
    }

    /// Observes an active fact (or an already completed one on a later turn).
    pub(in crate::studio) fn observe(&mut self, atom: &ChatAtom, sequence: Option<u64>) {
        self.admit(
            atom.clone(),
            sequence,
            None,
            terminal_outcome(atom).is_some(),
        );
    }

    /// Observes a frozen completion with its assigned completion sequence.
    pub(in crate::studio) fn complete(
        &mut self,
        atom: ChatAtom,
        sequence: u64,
        payload: Option<PayloadData>,
    ) {
        self.admit(atom, Some(sequence), payload, true);
    }

    fn admit(
        &mut self,
        atom: ChatAtom,
        sequence: Option<u64>,
        payload: Option<PayloadData>,
        terminal: bool,
    ) {
        let key = fact_key(&atom, sequence);
        if let Some(item) = self
            .items
            .iter_mut()
            .find(|item| item.members.contains_key(&atom.id))
        {
            let member = item.members.get_mut(&atom.id).expect("member checked");
            member.atom = atom;
            member.terminal |= terminal;
            if payload.is_some() {
                member.payload = payload;
            }
            member.key = member.key.min(key);
            item.ready_key = item.ready_key.max(key);
            item.refresh();
            return;
        }
        match classify(&atom) {
            Class::Text | Class::Status => {
                self.close_group_for(&atom.source, key);
                let kind = if classify(&atom) == Class::Text {
                    TimelineItemKind::Text
                } else {
                    TimelineItemKind::Status
                };
                let mut item = LiveItem::single(&atom, kind, sequence);
                if let Some(member) = item.members.get_mut(&atom.id) {
                    member.payload = payload;
                }
                item.closed = true;
                item.refresh();
                self.items.push(item);
            }
            Class::Work => {
                let open = self.items.iter().rposition(|item| {
                    item.item.kind == TimelineItemKind::WorkGroup
                        && item.item.source == atom.source
                        && !item.closed
                        && atom.source_order.is_none_or(|order| {
                            item.ordered_members()
                                .last()
                                .and_then(|member| member.atom.source_order)
                                .is_none_or(|last| order > last)
                        })
                });
                let member = Member {
                    atom: atom.clone(),
                    terminal,
                    key,
                    payload: None,
                };
                match open {
                    Some(index) => self.items[index].insert(member),
                    None => self.items.push(LiveItem::group(&atom, sequence)),
                }
            }
        }
        self.items
            .sort_by(|a, b| a.anchor.cmp(&b.anchor).then(a.item.id.cmp(&b.item.id)));
    }

    fn close_group_for(&mut self, source: &ChatSourceId, at: FactKey) {
        for item in &mut self.items {
            if item.item.kind == TimelineItemKind::WorkGroup
                && &item.item.source == source
                && !item.closed
            {
                item.closed = true;
                item.ready_key = item.ready_key.max(at);
                item.item.admission_closed = true;
            }
        }
    }

    /// A reliable source end closes admission for its remaining work groups.
    pub(in crate::studio) fn end_source(&mut self, source: &ChatSourceId) {
        for item in &mut self.items {
            if item.item.kind == TimelineItemKind::WorkGroup && &item.item.source == source {
                item.closed = true;
                item.item.admission_closed = true;
            }
        }
    }

    /// Commits every item whose reliable conditions are met, in canonical order.
    pub(in crate::studio) fn commit_ready(&mut self) {
        loop {
            let Some(index) = self.next_ready() else {
                break;
            };
            let mut item = self.items.remove(index);
            // A text part that carries no text and no attachment is still a real
            // structural boundary, but it must not paint an empty top-level card.
            if item.item.kind == TimelineItemKind::Text {
                let empty = item.members.values().all(|member| {
                    member.atom.contents.is_empty()
                        && member
                            .payload
                            .as_ref()
                            .is_none_or(|payload| payload_is_empty(Some(payload)))
                });
                if empty {
                    continue;
                }
            }
            item.item.position = Some(self.next_position);
            item.item.admission_closed = true;
            self.next_position = self.next_position.saturating_add(1);
            self.committed.push(item.item);
        }
        self.items
            .sort_by(|a, b| a.anchor.cmp(&b.anchor).then(a.item.id.cmp(&b.item.id)));
    }

    fn next_ready(&self) -> Option<usize> {
        let mut best: Option<usize> = None;
        for (index, item) in self.items.iter().enumerate() {
            if !item.ready() {
                continue;
            }
            if self.items.iter().any(|other| {
                other.item.source == item.item.source
                    && (other.anchor, other.item.id.as_str()) < (item.anchor, item.item.id.as_str())
            }) {
                continue;
            }
            best = match best {
                Some(current) => {
                    let current_item = &self.items[current];
                    if (item.ready_key, item.item.id.as_str())
                        < (current_item.ready_key, current_item.item.id.as_str())
                    {
                        Some(index)
                    } else {
                        Some(current)
                    }
                }
                None => Some(index),
            };
        }
        best
    }

    /// Current fragments in display order, with their typed member identities.
    pub(in crate::studio) fn current_items(&self) -> Vec<TimelineItem> {
        let mut items: Vec<TimelineItem> = self
            .items
            .iter()
            .map(|item| {
                let mut value = item.item.clone();
                value.position = None;
                value
            })
            .collect();
        // Canonical anchor order: the same order in live, restart and rebuild.
        let anchors: BTreeMap<&str, FactKey> = self
            .items
            .iter()
            .map(|item| (item.item.id.as_str(), item.anchor))
            .collect();
        items.sort_by(|a, b| {
            anchors
                .get(a.id.as_str())
                .copied()
                .cmp(&anchors.get(b.id.as_str()).copied())
                .then(a.id.cmp(&b.id))
        });
        items
    }

    /// The committed delta of the current effect. Drain only after the effect's
    /// item delta has been frozen into its prepared publication.
    pub(in crate::studio) fn take_committed(&mut self) -> Vec<TimelineItem> {
        std::mem::take(&mut self.committed)
    }

    #[cfg(test)]
    pub(in crate::studio) fn committed(&self) -> &[TimelineItem] {
        &self.committed
    }

    #[cfg(test)]
    pub(in crate::studio) fn current_members(&self) -> Vec<ChatAtom> {
        let mut members: BTreeMap<&str, &Member> = BTreeMap::new();
        for item in &self.items {
            for (id, member) in &item.members {
                members.insert(id.as_str(), member);
            }
        }
        let mut values: Vec<&Member> = members.into_values().collect();
        values.sort_by(|a, b| a.key.cmp(&b.key).then(a.atom.id.cmp(&b.atom.id)));
        values
            .into_iter()
            .map(|member| member.atom.clone())
            .collect()
    }
}

#[cfg(test)]
mod tests;

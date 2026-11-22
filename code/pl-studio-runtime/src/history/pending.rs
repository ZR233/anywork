use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};

use tokio::sync::OwnedSemaphorePermit;

use super::{db::Body, *};

pub(super) struct Reservation {
    pub _events: OwnedSemaphorePermit,
    pub _bytes: OwnedSemaphorePermit,
}

pub(super) struct Accepted {
    pub event: HistoryEvent,
    pub retained_bytes: usize,
    pub body_headers: Vec<Body>,
    pub _reservation: Arc<Reservation>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct WorkRangeSummary {
    pub first_seq: u64,
    pub last_seq: u64,
    pub started_at: Option<i64>,
    pub ended_at: Option<i64>,
    pub run_id: Option<String>,
    pub event_count: u64,
}

#[derive(Clone)]
pub(super) struct Pending {
    pub bytes: usize,
    pub events: BTreeMap<u64, Arc<Accepted>>,
    pub identities: BTreeMap<String, u64>,
    pub bodies: BTreeMap<String, (u64, usize)>,
    pub anchors: BTreeMap<String, u64>,
}

impl Pending {
    pub fn new() -> Self {
        Self {
            bytes: 0,
            events: BTreeMap::new(),
            identities: BTreeMap::new(),
            bodies: BTreeMap::new(),
            anchors: BTreeMap::new(),
        }
    }

    pub fn insert(&mut self, accepted: Arc<Accepted>) -> Result<()> {
        let seq = accepted.event.seq;
        let event_id = accepted.event.event_id.clone();
        self.bytes = self
            .bytes
            .checked_add(accepted.retained_bytes)
            .ok_or_else(|| HistoryError::Integrity("pending byte accounting overflow".into()))?;
        self.identities.insert(event_id, seq);
        for (index, body) in accepted.body_headers.iter().enumerate() {
            self.bodies.insert(body.id.clone(), (seq, index));
        }
        if accepted.event.is_anchor
            && let Some(row_key) = &accepted.event.row_key
        {
            self.anchors.insert(row_key.clone(), seq);
        }
        self.events.insert(seq, accepted);
        Ok(())
    }

    pub fn remove_through(&mut self, through: u64) -> Result<()> {
        let split = through.saturating_add(1);
        let retained = self.events.split_off(&split);
        let removed = std::mem::replace(&mut self.events, retained);
        for (seq, accepted) in removed {
            self.bytes = self.bytes.saturating_sub(accepted.retained_bytes);
            if self.identities.get(&accepted.event.event_id) == Some(&seq) {
                self.identities.remove(&accepted.event.event_id);
            }
            for body in &accepted.body_headers {
                if self.bodies.get(&body.id).is_some_and(|(s, _)| *s == seq) {
                    self.bodies.remove(&body.id);
                }
            }
            if accepted.event.is_anchor
                && let Some(row_key) = &accepted.event.row_key
                && self.anchors.get(row_key) == Some(&seq)
            {
                self.anchors.remove(row_key);
            }
        }
        Ok(())
    }

    pub fn event(&self, id: &str) -> Option<&Arc<Accepted>> {
        self.identities.get(id).and_then(|seq| self.events.get(seq))
    }

    pub fn body(&self, id: &str) -> Option<(&Arc<Accepted>, &Body, usize)> {
        let (seq, index) = self.bodies.get(id)?;
        let accepted = self.events.get(seq)?;
        let header = accepted.body_headers.get(*index)?;
        Some((accepted, header, *index))
    }

    pub fn head(&self, row_key: &str, cut: u64) -> Option<&Arc<Accepted>> {
        self.events
            .range(..=cut)
            .rev()
            .map(|(_, entry)| entry)
            .find(|entry| entry.event.row_key.as_deref() == Some(row_key))
    }

    pub fn latest_divider(&self, upper_seq: u64) -> Option<&Arc<Accepted>> {
        self.events
            .range(..=upper_seq)
            .rev()
            .map(|(_, entry)| entry)
            .find(|entry| entry.event.timeline_role == HistoryTimelineRole::Divider)
    }

    pub fn work_range_summary(&self, lower_excl: u64, upper_incl: u64) -> Option<WorkRangeSummary> {
        if lower_excl >= upper_incl {
            return None;
        }
        let mut first_seq: Option<u64> = None;
        let mut last_seq: Option<u64> = None;
        let mut started_at: Option<i64> = None;
        let mut ended_at: Option<i64> = None;
        let mut run_id: Option<String> = None;
        let mut event_count: u64 = 0;
        let start_incl = lower_excl.saturating_add(1);
        for (&seq, entry) in self.events.range(start_incl..=upper_incl) {
            if entry.event.timeline_role != HistoryTimelineRole::Work {
                continue;
            }
            if first_seq.is_none() {
                first_seq = Some(seq);
            }
            last_seq = Some(seq);
            if let Some(at) = entry.event.occurred_at {
                started_at = Some(started_at.map_or(at, |cur| cur.min(at)));
                ended_at = Some(ended_at.map_or(at, |cur| cur.max(at)));
            }
            if let Some(run) = &entry.event.run_id {
                run_id = Some(run.clone());
            }
            event_count += 1;
        }
        Some(WorkRangeSummary {
            first_seq: first_seq?,
            last_seq: last_seq?,
            started_at,
            ended_at,
            run_id,
            event_count,
        })
    }

    pub fn work_range_events(
        &self,
        after_excl: u64,
        upper_incl: u64,
        limit: usize,
    ) -> Vec<&Arc<Accepted>> {
        if after_excl >= upper_incl || limit == 0 {
            return Vec::new();
        }
        let start_incl = after_excl.saturating_add(1);
        self.events
            .range(start_incl..=upper_incl)
            .map(|(_, entry)| entry)
            .filter(|entry| entry.event.timeline_role == HistoryTimelineRole::Work)
            .take(limit)
            .collect()
    }

    pub fn finish(&self, turn_id: &str, cut: u64) -> Option<&Arc<Accepted>> {
        self.events
            .range(..=cut)
            .rev()
            .map(|(_, entry)| entry)
            .find(|entry| {
                entry.event.turn_id.as_deref() == Some(turn_id)
                    && entry.event.tool_name.as_deref() == Some("finish_turn")
            })
    }

    pub fn business_anchors(
        &self,
        scope: HistoryBusinessRowScope,
        cut: u64,
        before: Option<u64>,
        limit: usize,
        seen_keys: &mut BTreeSet<String>,
    ) -> Vec<&Arc<Accepted>> {
        let upper = before.map_or(cut, |b| b.saturating_sub(1).min(cut));
        let mut results = Vec::new();
        for (_, entry) in self.events.range(..=upper).rev() {
            if !entry.event.is_anchor || entry.event.row_scope != Some(scope) {
                continue;
            }
            let Some(row_key) = &entry.event.row_key else {
                continue;
            };
            if seen_keys.insert(row_key.clone()) {
                results.push(entry);
                if results.len() >= limit {
                    break;
                }
            }
        }
        results
    }

    pub fn matches_query(event: &HistoryEvent, query: &HistoryEventsQuery) -> bool {
        match query {
            HistoryEventsQuery::AllEvents => true,
            HistoryEventsQuery::Entity { entity_id } => {
                event.entity_id.as_deref() == Some(entity_id.as_str())
            }
            HistoryEventsQuery::Turn { turn_id } => {
                event.turn_id.as_deref() == Some(turn_id.as_str())
            }
            HistoryEventsQuery::Source { source } => event.source.as_ref() == Some(source),
            HistoryEventsQuery::Call { call_id } => {
                event.call_id.as_deref() == Some(call_id.as_str())
            }
            HistoryEventsQuery::Message { message_id } => {
                event.message_id.as_deref() == Some(message_id.as_str())
            }
            HistoryEventsQuery::Attempt { run_id, attempt_id } => {
                event.run_id.as_deref() == Some(run_id.as_str())
                    && event.attempt_id.as_deref() == Some(attempt_id.as_str())
            }
            HistoryEventsQuery::Originals { scope } => {
                let Some(original) = &event.original else {
                    return false;
                };
                if let Some(parent) = &scope.parent_id
                    && original.parent_id.as_deref() != Some(parent.as_str())
                {
                    return false;
                }
                match &scope.query_class {
                    crate::ChatClassFilter::All {} => true,
                    crate::ChatClassFilter::Class { value: query_class } => {
                        original.query_class == *query_class
                    }
                }
            }
            HistoryEventsQuery::TextOriginals => event.original.as_ref().is_some_and(|original| {
                matches!(
                    original.original_kind,
                    HistoryEntityKind::Text | HistoryEntityKind::Input
                )
            }),
        }
    }

    pub fn events_matching(
        &self,
        query: &HistoryEventsQuery,
        min_excl: u64,
        max_incl: u64,
        ascending: bool,
        limit: usize,
    ) -> Vec<&Arc<Accepted>> {
        if min_excl >= max_incl || limit == 0 {
            return Vec::new();
        }
        let start_incl = min_excl.saturating_add(1);
        if ascending {
            self.events
                .range(start_incl..=max_incl)
                .map(|(_, entry)| entry)
                .filter(|entry| Self::matches_query(&entry.event, query))
                .take(limit)
                .collect()
        } else {
            self.events
                .range(start_incl..=max_incl)
                .rev()
                .map(|(_, entry)| entry)
                .filter(|entry| Self::matches_query(&entry.event, query))
                .take(limit)
                .collect()
        }
    }

    pub fn original_by_entity(&self, entity_id: &str, cut: u64) -> Option<&Arc<Accepted>> {
        self.events
            .range(..=cut)
            .rev()
            .map(|(_, entry)| entry)
            .find(|entry| {
                entry.event.original.is_some()
                    && entry.event.entity_id.as_deref() == Some(entity_id)
            })
    }

    pub fn latest_original(&self, cut: u64) -> Option<&Arc<Accepted>> {
        self.events
            .range(..=cut)
            .rev()
            .map(|(_, entry)| entry)
            .find(|entry| entry.event.original.is_some())
    }
}

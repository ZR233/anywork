use std::{
    collections::{BTreeMap, BTreeSet},
    sync::Arc,
};
use tokio::sync::OwnedSemaphorePermit;

use super::{HistoryEvent, HistoryEventsQuery, Result, token::Query, types::source_key};

pub(super) struct Reservation {
    pub _events: OwnedSemaphorePermit,
    pub _bytes: OwnedSemaphorePermit,
}
pub(super) struct Accepted {
    pub event: HistoryEvent,
    pub body_headers: Vec<super::db::Body>,
    pub _reservation: Arc<Reservation>,
}

/// Capturing a query clones only this Arc. Copy-on-write updates copy bounded index keys and Arcs,
/// never event bodies. Reservation lifetime includes old roots still held by in-flight queries.
#[derive(Default, Clone)]
pub(super) struct Pending {
    pub events: BTreeMap<u64, Arc<Accepted>>,
    pub identities: BTreeMap<String, u64>,
    pub bodies: BTreeMap<String, (u64, usize)>,
    pub anchors: BTreeMap<String, u64>,
    heads: BTreeMap<String, BTreeSet<u64>>,
    indexes: BTreeMap<Key, BTreeSet<u64>>,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
enum Key {
    Main,
    Members(String),
    Scope(String),
    Entity(String),
    Turn(String),
    Source(String),
    Call(String),
    Message(String),
    Attempt(String, String),
    Originals,
    Class(String),
    Parent(String),
    ParentClass(String, String),
    Text,
    Finish(String),
}

impl Pending {
    fn keys(event: &HistoryEvent) -> Result<Vec<Key>> {
        let h = &event.header;
        let mut keys = Vec::new();
        for (value, key) in [
            (&h.entity_id, Key::Entity as fn(String) -> Key),
            (&h.turn_id, Key::Turn),
            (&h.call_id, Key::Call),
            (&h.message_id, Key::Message),
        ] {
            if let Some(value) = value {
                keys.push(key(value.clone()));
            }
        }
        if let Some(source) = &h.source {
            keys.push(Key::Source(source_key(source)?.1));
        }
        if let (Some(run), Some(attempt)) = (&h.run_id, &h.attempt_id) {
            keys.push(Key::Attempt(run.clone(), attempt.clone()));
        }
        if event.is_anchor
            && let Some(head) = &event.head
        {
            keys.push(Key::Scope(head.scope().into()));
            match head.scope() {
                "work" | "single" => keys.push(Key::Main),
                "member" => {
                    if let Some(group) = &h.group_id {
                        keys.push(Key::Members(group.clone()));
                    }
                }
                _ => {}
            }
        }
        if let Some(original) = &h.original {
            keys.push(Key::Originals);
            keys.push(Key::Class(original.query_class.clone()));
            if original.tool_name.as_deref() == Some(pl_tool::finish_turn::TOOL_FINISH_TURN)
                && let Some(turn) = &h.turn_id
            {
                keys.push(Key::Finish(turn.clone()));
            }
            if let Some(parent) = &original.parent_id {
                keys.push(Key::Parent(parent.clone()));
                keys.push(Key::ParentClass(
                    parent.clone(),
                    original.query_class.clone(),
                ));
            }
            if matches!(
                original.original_kind,
                super::HistoryEntityKind::Input | super::HistoryEntityKind::Text
            ) {
                keys.push(Key::Text);
            }
        }
        Ok(keys)
    }
    pub fn insert(&mut self, accepted: Arc<Accepted>) -> Result<()> {
        let event = &accepted.event;
        let seq = event.header.seq;
        for key in Self::keys(event)? {
            self.indexes.entry(key).or_default().insert(seq);
        }
        if let Some(row) = &event.header.row_key {
            self.heads.entry(row.clone()).or_default().insert(seq);
            if event.is_anchor {
                self.anchors.insert(row.clone(), seq);
            }
        }
        for (ordinal, body) in event.bodies.iter().enumerate() {
            self.bodies.insert(body.body_id.clone(), (seq, ordinal));
        }
        self.identities.insert(event.header.event_id.clone(), seq);
        self.events.insert(seq, accepted);
        Ok(())
    }
    pub fn remove_through(&mut self, through: u64) -> Result<()> {
        let sequences: Vec<_> = self.events.range(..=through).map(|(seq, _)| *seq).collect();
        for seq in sequences {
            let Some(accepted) = self.events.remove(&seq) else {
                continue;
            };
            let event = &accepted.event;
            for key in Self::keys(event)? {
                if let Some(index) = self.indexes.get_mut(&key) {
                    index.remove(&seq);
                    if index.is_empty() {
                        self.indexes.remove(&key);
                    }
                }
            }
            if let Some(row) = &event.header.row_key {
                if let Some(index) = self.heads.get_mut(row) {
                    index.remove(&seq);
                    if index.is_empty() {
                        self.heads.remove(row);
                    }
                }
                if event.is_anchor {
                    self.anchors.remove(row);
                }
            }
            for body in &event.bodies {
                self.bodies.remove(&body.body_id);
            }
            self.identities.remove(&event.header.event_id);
        }
        Ok(())
    }
    pub fn event(&self, id: &str) -> Option<&Arc<Accepted>> {
        self.identities.get(id).and_then(|seq| self.events.get(seq))
    }
    pub fn finish(&self, turn: &str, cut: u64) -> Option<&Arc<Accepted>> {
        self.indexes
            .get(&Key::Finish(turn.into()))?
            .range(..=cut)
            .next_back()
            .and_then(|seq| self.events.get(seq))
    }
    pub fn head(&self, key: &str, cut: u64) -> Option<&Arc<Accepted>> {
        self.heads
            .get(key)?
            .range(..=cut)
            .next_back()
            .and_then(|seq| self.events.get(seq))
    }
    pub fn candidates(
        &self,
        query: &Query,
        cut: u64,
        before: Option<u64>,
        limit: usize,
    ) -> Result<Vec<Arc<Accepted>>> {
        let key = match query {
            Query::Main => Some(Key::Main),
            Query::Group(id) => Some(Key::Members(id.clone())),
            Query::Rows(scope) => Some(Key::Scope(scope.clone())),
            Query::Events(query) => match query {
                HistoryEventsQuery::AllEvents => None,
                HistoryEventsQuery::Entity { entity_id } => Some(Key::Entity(entity_id.clone())),
                HistoryEventsQuery::Turn { turn_id } => Some(Key::Turn(turn_id.clone())),
                HistoryEventsQuery::Call { call_id } => Some(Key::Call(call_id.clone())),
                HistoryEventsQuery::Message { message_id } => {
                    Some(Key::Message(message_id.clone()))
                }
                HistoryEventsQuery::Source { source } => Some(Key::Source(source_key(source)?.1)),
                HistoryEventsQuery::Attempt { run_id, attempt_id } => {
                    Some(Key::Attempt(run_id.clone(), attempt_id.clone()))
                }
                HistoryEventsQuery::TextOriginals => Some(Key::Text),
                HistoryEventsQuery::Originals { scope } => {
                    Some(match (scope.query_class(), scope.parent_id()) {
                        (None, None) => Key::Originals,
                        (Some(class), None) => Key::Class(class.into()),
                        (None, Some(parent)) => Key::Parent(parent.into()),
                        (Some(class), Some(parent)) => {
                            Key::ParentClass(parent.into(), class.into())
                        }
                    })
                }
            },
        };
        let upper = before.map_or(cut, |before| cut.min(before.saturating_sub(1)));
        Ok(match key {
            None => self
                .events
                .range(..=upper)
                .rev()
                .take(limit)
                .map(|(_, value)| value.clone())
                .collect(),
            Some(key) => self
                .indexes
                .get(&key)
                .into_iter()
                .flat_map(|index| index.range(..=upper).rev().take(limit))
                .filter_map(|seq| self.events.get(seq).cloned())
                .collect(),
        })
    }
}

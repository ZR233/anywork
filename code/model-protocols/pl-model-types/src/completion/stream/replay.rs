//! Bounded collection of the provider's replay view, before display filtering.

use super::super::AssistantReplay;
use pl_protocol::{PureError, Result};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

const MAX_REPLAY_BYTES: usize = 16 * 1024 * 1024;

#[derive(Debug, Clone)]
pub enum ReplayUpdate {
    PendingItem { index: Option<u32>, item: Value },
    Item { index: Option<u32>, item: Value },
    Output { items: Vec<Value> },
    TextDelta(String),
}

#[derive(Default)]
pub struct ReplayCollector {
    pending_items: Vec<(Option<u32>, Value)>,
    items: Vec<(Option<u32>, Value)>,
    identities: BTreeMap<String, usize>,
    positions: BTreeSet<u32>,
    terminal: Option<Vec<Value>>,
    bytes: usize,
    chat: Option<String>,
}

impl ReplayCollector {
    pub fn native_item(&self, id: &str) -> Option<&Value> {
        self.items
            .iter()
            .map(|(_, item)| item)
            .chain(self.pending_items.iter().rev().map(|(_, item)| item))
            .chain(self.terminal.iter().flatten())
            .find(|item| item.get("id").and_then(Value::as_str) == Some(id))
    }

    // Canonical block metadata without a corresponding native item still belongs to the native
    // output quota. Actual provider items are retained once and referred to by their identity.
    pub fn replace_block_metadata(
        &mut self,
        old: Option<&Value>,
        new: Option<&Value>,
    ) -> Result<()> {
        if old.is_none() && new.is_none() {
            return Ok(());
        }
        let bytes = |value: Option<&Value>| {
            value
                .map(serde_json::to_vec)
                .transpose()
                .map(|v| v.map_or(0, |v| v.len()))
        };
        self.bytes = bounded((self.bytes - bytes(old)?).checked_add(bytes(new)?))?;
        Ok(())
    }

    pub fn apply(&mut self, update: ReplayUpdate) -> Result<()> {
        match update {
            ReplayUpdate::PendingItem { index, item } => {
                let size = serde_json::to_vec(&item)?.len();
                self.bytes = bounded(self.bytes.checked_add(size))?;
                self.pending_items.push((index, item));
            }
            ReplayUpdate::Item { index, item } => {
                let size = serde_json::to_vec(&item)?.len();
                if let Some(id) = item.get("id").and_then(Value::as_str)
                    && let Some(&position) = self.identities.get(id)
                {
                    let (old_index, old) = &self.items[position];
                    if old_index.is_some() && index.is_some() && *old_index != index || old != &item
                    {
                        return Err(PureError::Protocol(
                            "conflicting completed assistant output item".into(),
                        ));
                    }
                    return Ok(());
                }
                if let Some(index) = index
                    && self.positions.contains(&index)
                {
                    return Err(PureError::Protocol(
                        "duplicate assistant output index".into(),
                    ));
                }
                let same_item = |pending: &Value| {
                    pending.get("id").is_some() && pending.get("id") == item.get("id")
                };
                let replaced = self
                    .pending_items
                    .iter()
                    .filter(|(_, pending)| same_item(pending))
                    .map(|(_, pending)| serde_json::to_vec(pending).expect("JSON value").len())
                    .sum::<usize>();
                let next = bounded((self.bytes - replaced).checked_add(size))?;
                if let Some(index) = index {
                    self.positions.insert(index);
                }
                if let Some(id) = item.get("id").and_then(Value::as_str) {
                    self.identities.insert(id.to_owned(), self.items.len());
                }
                self.pending_items
                    .retain(|(_, pending)| !same_item(pending));
                self.bytes = next;
                self.items.push((index, item));
            }
            ReplayUpdate::Output { items } => {
                bounded(Some(serde_json::to_vec(&items)?.len()))?;
                self.terminal = Some(items);
            }
            ReplayUpdate::TextDelta(delta) => {
                let text = self.chat.get_or_insert_with(String::new);
                bounded(text.len().checked_add(delta.len()))?;
                text.push_str(&delta);
            }
        }
        Ok(())
    }

    pub fn current(&self) -> super::current::ModelStreamReplay {
        use super::current::{ModelStreamReplay, ModelStreamReplayItem};
        let items = |items: &[(Option<u32>, Value)]| {
            items
                .iter()
                .map(|(index, item)| ModelStreamReplayItem {
                    index: *index,
                    item: item.clone(),
                })
                .collect()
        };
        ModelStreamReplay {
            pending_items: items(&self.pending_items),
            items: items(&self.items),
            terminal: self.terminal.clone(),
            chat: self.chat.clone(),
        }
    }

    pub fn finish(&self) -> Result<Option<AssistantReplay>> {
        if let Some(content) = &self.chat {
            return Ok(Some(AssistantReplay::Chat {
                content: content.clone(),
            }));
        }
        let terminal = self.terminal.as_ref();
        // Some compatible endpoints send an abbreviated terminal envelope without item identities.
        // Completed items remain authoritative there; an identity-bearing output is checked whole.
        if let Some(items) = terminal
            && !items.is_empty()
            && items
                .iter()
                .all(|item| item.get("id").and_then(Value::as_str).is_some())
        {
            for (index, done) in &self.items {
                let candidate = index
                    .and_then(|index| items.get(index as usize))
                    .or_else(|| items.iter().find(|item| item.get("id") == done.get("id")));
                if candidate != Some(done) {
                    return Err(PureError::Protocol(
                        "terminal assistant output differs from completed items".into(),
                    ));
                }
            }
            return Ok(Some(AssistantReplay::Responses {
                output: items.clone(),
            }));
        }
        if !self.items.is_empty() {
            let mut items = self.items.iter().collect::<Vec<_>>();
            items.sort_by_key(|(index, _)| index.unwrap_or(u32::MAX));
            for (expected, (index, _)) in items.iter().enumerate() {
                if index.is_some_and(|index| index as usize != expected) {
                    return Err(PureError::Protocol(
                        "incomplete assistant output indices".into(),
                    ));
                }
            }
            return Ok(Some(AssistantReplay::Responses {
                output: items.into_iter().map(|(_, item)| item.clone()).collect(),
            }));
        }
        Ok(terminal.map(|output| AssistantReplay::Responses {
            output: output.clone(),
        }))
    }
}

fn bounded(size: Option<usize>) -> Result<usize> {
    size.filter(|size| *size <= MAX_REPLAY_BYTES)
        .ok_or_else(|| PureError::MemoryError("provider replay output exceeds 16 MiB".into()))
}

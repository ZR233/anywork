//! Small, product-owned current retirement facts for a reliable completion cut.
use std::sync::Arc;

use pl_protocol::{ChatEntry, CurrentProjection};

/// Only an already-exposed preview needs per-item retirement metadata.
#[derive(Debug, Clone)]
pub(in crate::studio) struct CurrentRetirement {
    pub item_id: String,
    pub through: u64,
}

/// Does not retain current bodies, full collections, or the prepared effect's completion payloads.
#[derive(Debug, Clone)]
pub(in crate::studio) struct CurrentHandoff {
    pub sources: Arc<[pl_protocol::ChatSourceState]>,
    pub members: Arc<[super::timeline::MemberChange]>,
    /// Main's proven completed frontier, not the global Session head.
    pub main_through: u64,
    pub before: Arc<CurrentProjection>,
    pub after: Arc<CurrentProjection>,
    pub retirements: Arc<[CurrentRetirement]>,
    /// Actual start/source events, including effects that publish no completion seq.
    pub entries: Arc<[ChatEntry]>,
}

impl CurrentHandoff {
    /// Display handoff is a separate order domain from atomic completion seq.
    /// A split frame retires only its delivered display prefix.
    pub fn projection_after_items(&self, delivered: usize) -> CurrentProjection {
        let mut current = self.after.as_ref().clone();
        let mut suffix = self.entries.iter().skip(delivered).filter_map(|entry| {
            if let ChatEntry::Item(item) = entry {
                let mut item = item.as_ref().clone();
                item.position = None;
                Some(item)
            } else { None }
        }).collect::<Vec<_>>();
        suffix.append(&mut current.items);
        current.items = suffix;
        current
    }
    /// A partial delivery may retire only the previews actually covered by its completed prefix.
    /// Collection handles retain their normal mutable-revision qualification; they are not snapshots.
    pub fn projection_at(&self, through: u64) -> CurrentProjection {
        if through >= self.main_through {
            return self.after.as_ref().clone();
        }
        let mut current = self.before.as_ref().clone();
        current.source_effect_seq = self.after.source_effect_seq;
        current.previews.retain(|preview| {
            !self
                .retirements
                .iter()
                .any(|retirement| retirement.item_id == preview.id && retirement.through <= through)
        });
        current.atoms.retain(|atom| {
            !self
                .retirements
                .iter()
                .any(|retirement| retirement.item_id == atom.id && retirement.through <= through)
        });
        current
    }
}

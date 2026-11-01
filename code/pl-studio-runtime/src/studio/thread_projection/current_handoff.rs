//! Small, product-owned current retirement facts for a reliable completion cut.
use std::sync::Arc;

use pl_protocol::CurrentProjection;

/// Only an already-exposed preview needs per-item retirement metadata.
#[derive(Debug, Clone)]
pub(in crate::studio) struct CurrentRetirement {
    pub item_id: String,
    pub through: u64,
}

/// Does not retain current bodies, full collections, or the prepared effect's completion payloads.
#[derive(Debug, Clone)]
pub(in crate::studio) struct CurrentHandoff {
    /// Main's proven completed frontier, not the global Session head.
    pub main_through: u64,
    pub before: Arc<CurrentProjection>,
    pub after: Arc<CurrentProjection>,
    pub retirements: Arc<[CurrentRetirement]>,
}

impl CurrentHandoff {
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
        current
    }
}

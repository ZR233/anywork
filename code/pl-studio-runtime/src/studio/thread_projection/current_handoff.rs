//! Small, product-owned current retirement facts for a reliable completion cut.
use std::sync::{Arc, OnceLock};

use super::FrozenCurrentProjection;
use pl_protocol::{ChatEntry, CurrentProjection};

/// Only an already-exposed preview needs per-item retirement metadata.
#[derive(Debug, Clone, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub(in crate::studio) struct CurrentRetirement {
    pub item_id: String,
    pub through: u64,
}

/// Does not retain current bodies, full collections, or the prepared effect's completion payloads.
#[derive(Debug, Clone)]
pub(in crate::studio) struct CurrentHandoff {
    projection_generation: String,
    sources: Arc<[pl_protocol::ChatSourceState]>,
    members: Arc<[super::timeline::MemberChange]>,
    /// Main's proven completed frontier, not the global Session head.
    main_through: u64,
    before: Arc<FrozenCurrentProjection>,
    after: Arc<FrozenCurrentProjection>,
    retirements: Arc<[CurrentRetirement]>,
    /// Actual start/source events, including effects that publish no completion seq.
    entries: Arc<[ChatEntry]>,
    retained_bytes: OnceLock<u64>,
}

impl CurrentHandoff {
    pub fn new(
        main_through: u64,
        before: Arc<FrozenCurrentProjection>,
        after: Arc<FrozenCurrentProjection>,
        entries: Arc<[ChatEntry]>,
    ) -> Self {
        Self {
            projection_generation: String::new(),
            sources: Arc::from([]),
            members: Arc::from([]),
            main_through,
            before,
            after,
            retirements: Arc::from([]),
            entries,
            retained_bytes: OnceLock::new(),
        }
    }

    pub fn with_publication(
        mut self,
        projection_generation: String,
        sources: Arc<[pl_protocol::ChatSourceState]>,
        members: Arc<[super::timeline::MemberChange]>,
        retirements: Arc<[CurrentRetirement]>,
    ) -> Self {
        self.retained_bytes.take();
        self.projection_generation = projection_generation;
        self.sources = sources;
        self.members = members;
        self.retirements = retirements;
        self
    }

    pub fn projection_generation(&self) -> &str {
        &self.projection_generation
    }
    pub fn sources(&self) -> &Arc<[pl_protocol::ChatSourceState]> {
        &self.sources
    }
    pub fn members(&self) -> &Arc<[super::timeline::MemberChange]> {
        &self.members
    }
    pub fn main_through(&self) -> u64 {
        self.main_through
    }
    pub fn before(&self) -> &Arc<FrozenCurrentProjection> {
        &self.before
    }
    pub fn after(&self) -> &Arc<FrozenCurrentProjection> {
        &self.after
    }
    pub fn retirements(&self) -> &Arc<[CurrentRetirement]> {
        &self.retirements
    }
    pub fn entries(&self) -> &Arc<[ChatEntry]> {
        &self.entries
    }

    pub fn retained_bytes(&self) -> u64 {
        *self.retained_bytes.get_or_init(|| {
            let projections = [&self.before, &self.after]
                .into_iter()
                .map(|current| current.retained_bytes())
                .fold(0_u64, u64::saturating_add);
            // Reserve every possible exposed-preview retirement before seq assignment;
            // filling the bounded metadata after publish cannot reduce this charge.
            self.before.projection().previews.iter().fold(
                projections
                    .saturating_add(std::mem::size_of::<OnceLock<u64>>() as u64)
                    .saturating_add(
                        serde_json::to_vec(&(
                            self.entries.as_ref(),
                            self.members.as_ref(),
                            self.sources.as_ref(),
                        ))
                        .map_or(u64::MAX, |bytes| bytes.len() as u64),
                    ),
                |bytes, preview| {
                    bytes
                        .saturating_add(preview.id.len() as u64)
                        .saturating_add(32)
                },
            )
        })
    }

    /// Display handoff is a separate order domain from atomic completion seq.
    /// A split frame retires only its delivered display prefix.
    pub fn projection_after_items(&self, delivered: usize) -> CurrentProjection {
        let mut current = self.after.projection().clone();
        let mut suffix = self
            .entries
            .iter()
            .skip(delivered)
            .filter_map(|entry| {
                if let ChatEntry::Item(item) = entry {
                    let mut item = item.as_ref().clone();
                    item.position = None;
                    Some(item)
                } else {
                    None
                }
            })
            .collect::<Vec<_>>();
        suffix.append(&mut current.items);
        current.items = suffix;
        current
    }
}

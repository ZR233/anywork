//! Same-cut transport metadata and the independent reliable facts prepared by its owner.
use super::*;
use crate::studio::thread_projection::FrozenCurrentProjection;
use pl_protocol::CurrentProjection;

#[derive(Debug, Clone)]
pub(crate) struct CurrentEntryWrite {
    pub collection: String,
    pub position: i64,
    pub entry_id: String,
    pub payload: Arc<[u8]>,
}

#[derive(Debug, Clone)]
pub(crate) struct CurrentContentWrite {
    /// A complete Plan document revision. Active bodies are never prepared for storage.
    pub content: Arc<pl_core::chat::ChatContent>,
    pub sealed: bool,
}

#[derive(Debug, Clone)]
pub(crate) struct PreparedTimelineItem {
    pub item: pl_protocol::TimelineItem,
}

#[derive(Debug, Clone)]
pub(crate) struct PreparedCurrent {
    pub(in crate::studio) recovery_interruption: Option<(String, pl_protocol::ChatFactPosition)>,
    pub(in crate::studio) timeline_update:
        Arc<crate::studio::thread_projection::timeline::TimelineUpdate>,
    projection: Arc<FrozenCurrentProjection>,
    pub contents: Arc<[CurrentContentWrite]>,
    pub source_changes: Arc<[pl_protocol::ChatSourceState]>,
    pub timeline: Arc<[PreparedTimelineItem]>,
    pub timeline_commit: u64,
}

impl PreparedCurrent {
    pub(in crate::studio) fn new(
        projection: Arc<FrozenCurrentProjection>,
        contents: Arc<[CurrentContentWrite]>,
    ) -> Self {
        Self {
            recovery_interruption: None,
            timeline_update: Arc::new(Default::default()),
            projection,
            contents,
            source_changes: Arc::from([]),
            timeline: Arc::from([]),
            timeline_commit: 0,
        }
    }
    pub fn projection(&self) -> &CurrentProjection {
        self.projection.projection()
    }
    /// One index domain over typed appends and authorized derived-head updates.
    pub(in crate::studio) fn history_items(
        &self,
    ) -> impl Iterator<Item = &pl_protocol::TimelineItem> {
        self.timeline
            .iter()
            .map(|entry| &entry.item)
            .chain(self.timeline_update.updates())
    }
    pub(in crate::studio) fn history_item(&self, index: usize) -> &pl_protocol::TimelineItem {
        if index < self.timeline.len() {
            &self.timeline[index].item
        } else {
            &self.timeline_update.updates()[index - self.timeline.len()]
        }
    }

    pub(in crate::studio) fn frozen_projection(&self) -> &Arc<FrozenCurrentProjection> {
        &self.projection
    }

    pub(in crate::studio) fn replace_projection(
        &mut self,
        projection: Arc<FrozenCurrentProjection>,
    ) {
        self.projection = projection;
    }
    pub fn projection_retained_bytes(&self) -> u64 {
        self.projection.retained_bytes()
    }
    pub(in crate::studio) fn operation_bytes(&self) -> u64 {
        self.contents
            .iter()
            .fold(std::mem::size_of::<Self>() as u64, |bytes, content| {
                bytes
                    .saturating_add(content.content.descriptor.byte_length)
                    .saturating_add(128)
            })
            .saturating_add(
                self.recovery_interruption
                    .as_ref()
                    .map_or(0, |(attempt, _)| attempt.len() as u64 + 64),
            )
    }
    pub(in crate::studio) fn pending_index_bytes(&self) -> u64 {
        128_u64
            .saturating_add(self.history_items().count() as u64 * 256)
            .saturating_add(
                self.timeline_update
                    .members()
                    .iter()
                    .chain(self.timeline_update.completed_members())
                    .map(|member| 512_u64.saturating_add(member.item_id.len() as u64 * 2))
                    .fold(0, u64::saturating_add),
            )
    }
}

pub(in crate::studio) fn validate_database(
    projection: &CurrentProjection,
    database: &str,
) -> Result<()> {
    for reference in projection
        .collections
        .iter()
        .chain(projection.interactions.iter())
    {
        ensure!(
            reference.database_id == database && !reference.collection.is_empty(),
            "current collection has another database identity"
        );
    }
    for reference in projection
        .previews
        .iter()
        .map(|preview| &preview.reference)
        .chain(
            projection
                .plan
                .iter()
                .filter_map(|plan| plan.document.as_ref()),
        )
        .chain(
            projection
                .atoms
                .iter()
                .flat_map(|atom| atom.contents.iter().map(|content| &content.reference)),
        )
    {
        ensure!(
            reference.database_id == database,
            "current content has another database identity"
        );
    }
    Ok(())
}

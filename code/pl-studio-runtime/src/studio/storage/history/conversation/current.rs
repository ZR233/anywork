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
pub(crate) struct PreparedCurrent {
    /// Alias of the original PreparedEffect's frozen display material, not another queue.
    pub(in crate::studio) display:
        Option<Arc<crate::studio::thread_projection::presentation::PreparedDisplayDelta>>,
    pub(in crate::studio) recovery_interruption: Option<(String, pl_protocol::ChatFactPosition)>,
    /// Actual accepted start/terminal facts, frozen by the existing execution owner.
    pub(in crate::studio) atom_facts: Arc<[pl_protocol::ChatAtom]>,
    projection: Arc<FrozenCurrentProjection>,
    pub contents: Arc<[CurrentContentWrite]>,
    pub source_changes: Arc<[pl_protocol::ChatSourceState]>,
}

impl PreparedCurrent {
    pub(in crate::studio) fn new(
        projection: Arc<FrozenCurrentProjection>,
        contents: Arc<[CurrentContentWrite]>,
    ) -> Self {
        Self {
            display: None,
            recovery_interruption: None,
            atom_facts: Arc::from([]),
            projection,
            contents,
            source_changes: Arc::from([]),
        }
    }
    pub fn projection(&self) -> &CurrentProjection {
        self.projection.projection()
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

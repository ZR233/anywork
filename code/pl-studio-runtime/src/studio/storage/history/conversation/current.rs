//! Same-cut transport metadata and the independent reliable facts prepared by its owner.
use super::*;
use crate::CurrentProjection;
use crate::studio::thread_projection::FrozenCurrentProjection;

#[derive(Debug, Clone)]
pub(crate) struct CurrentContentWrite {
    /// A complete Plan document revision. Active bodies are never prepared for storage.
    pub content: Arc<pl_core::chat::ChatContent>,
    pub sealed: bool,
}

#[derive(Debug, Clone)]
pub(crate) struct PreparedCurrent {
    pub(in crate::studio) recovery_interruption: Option<(String, crate::ChatFactPosition)>,
    /// Actual accepted start/terminal facts, frozen by the existing execution owner.
    pub(in crate::studio) lifecycle:
        Arc<[crate::studio::storage::history::execution_lifecycle::ExecutionLifecycle]>,
    projection: Arc<FrozenCurrentProjection>,
    revision: u64,
    owner_id: Option<String>,
    pub contents: Arc<[CurrentContentWrite]>,
    pub source_changes: Arc<[crate::ChatSourceState]>,
}

impl PreparedCurrent {
    pub(in crate::studio) fn with_identity(
        projection: Arc<FrozenCurrentProjection>,
        contents: Arc<[CurrentContentWrite]>,
        revision: u64,
        owner_id: Option<String>,
    ) -> Self {
        Self {
            recovery_interruption: None,
            lifecycle: Arc::from([]),
            projection,
            revision,
            owner_id,
            contents,
            source_changes: Arc::from([]),
        }
    }
    pub fn projection(&self) -> &CurrentProjection {
        self.projection.projection()
    }
    pub(in crate::studio) fn revision(&self) -> u64 {
        self.revision
    }
    pub(in crate::studio) fn owner_id(&self) -> Option<&str> {
        self.owner_id.as_deref()
    }
}

pub(in crate::studio) fn validate_owner(projection: &CurrentProjection, owner: &str) -> Result<()> {
    for reference in projection
        .collections
        .iter()
        .chain(projection.interactions.iter())
    {
        ensure!(
            reference.owner_id == owner && !reference.collection.is_empty(),
            "current collection has another owner identity"
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
            reference.owner_id == owner,
            "current content has another owner identity"
        );
    }
    Ok(())
}

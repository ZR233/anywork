use std::sync::Arc;

use pl_protocol::InteractionStatus;
use pl_protocol::studio::StudioError;
use pl_protocol::thread_facets::execution::InteractionBrief;
use pl_protocol::thread_facets::identity::ReadScopeIdentity;
use pl_protocol::thread_facets::read::execution::{InteractionBriefPage, InteractionIndexReadHeader};

use super::super::read_budget::{count, protocol, require_budget};
use super::budget::{page, validate_revision};

/// Registered atomically with the index header; not a query over the latest pending set.
pub(super) struct InteractionIndexSource {
    pub(super) revision: u64,
    pub(super) entries: Vec<InteractionBrief>,
}

pub(super) struct InteractionIndexMaterial {
    scope: ReadScopeIdentity,
    source: Arc<InteractionIndexSource>,
    pending: u64,
}

impl InteractionIndexMaterial {
    pub(super) fn new(scope: ReadScopeIdentity, source: Arc<InteractionIndexSource>) -> Result<Self, StudioError> {
        validate_revision(&scope, source.revision)?;
        if source.entries.iter().any(|entry| entry.reference.revision != entry.revision)
            || source.entries.windows(2).any(|pair| pair[0].reference.entry >= pair[1].reference.entry)
        {
            return Err(protocol("Interaction index is not an ordered set of exact-revision refs"));
        }
        let pending = count(source.entries.iter().filter(|entry| entry.status == InteractionStatus::Pending).count())?;
        Ok(Self { scope, source, pending })
    }

    pub(super) fn header(&self) -> Result<InteractionIndexReadHeader, StudioError> {
        let value = InteractionIndexReadHeader { scope: self.scope.clone(),
            total: count(self.source.entries.len())?, pending: self.pending };
        require_budget(&value)?;
        Ok(value)
    }

    pub(super) fn entries(&self, offset: u64, limit: u32) -> Result<InteractionBriefPage, StudioError> {
        let result = page(&self.scope, self.source.entries.len(), offset, limit,
            |index, _| Ok(self.source.entries[index].clone()))?;
        Ok(InteractionBriefPage { scope: result.scope, offset: result.offset, total: result.total,
            items: result.items, next_offset: result.next_offset })
    }
}

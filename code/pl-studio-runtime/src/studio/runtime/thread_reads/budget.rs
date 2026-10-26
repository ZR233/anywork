//! Thread-specific identity and page envelope; byte/UTF-8 rules are runtime-wide.
use pl_protocol::studio::{StudioError, StudioErrorCode};
use pl_protocol::thread_facets::identity::ReadScopeIdentity;
use serde::Serialize;

use super::super::read_budget::{INLINE_BYTES, RESPONSE_BYTES, count, json_bytes, require_budget};

pub(super) fn validate_revision(
    scope: &ReadScopeIdentity,
    revision: u64,
) -> Result<(), StudioError> {
    if scope.source_revision != revision {
        return Err(StudioError::new(
            StudioErrorCode::Superseded,
            "The requested Thread detail revision is no longer available",
            false,
        ));
    }
    Ok(())
}

pub(super) struct PageParts<T> {
    pub(super) scope: ReadScopeIdentity,
    pub(super) offset: u64,
    pub(super) total: u64,
    pub(super) items: Vec<T>,
    pub(super) next_offset: Option<u64>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PageEnvelope<'a, T> {
    scope: &'a ReadScopeIdentity,
    offset: u64,
    total: u64,
    items: &'a [T],
    next_offset: Option<u64>,
}

/// Concrete public pages all have this exact envelope. `limit` is an upper bound, never a reason
/// to split one item or prevent a legal large first item's text from being read by field ID.
pub(super) fn page<T: Serialize>(
    scope: &ReadScopeIdentity,
    total: usize,
    offset: u64,
    limit: u32,
    mut item: impl FnMut(usize, usize) -> Result<T, StudioError>,
) -> Result<PageParts<T>, StudioError> {
    if !(1..=100).contains(&limit) {
        return Err(StudioError::invalid_argument(
            "Read page limit must be in 1..=100",
        ));
    }
    let total_u64 = count(total)?;
    let start = usize::try_from(offset)
        .ok()
        .filter(|offset| *offset <= total)
        .ok_or_else(|| StudioError::invalid_argument("Read page offset exceeds the pinned list"))?;
    let end = start.saturating_add(limit as usize).min(total);
    let mut items = Vec::with_capacity(end - start);
    for index in start..end {
        items.push(item(index, INLINE_BYTES)?);
        let next = count(start + items.len())?;
        let envelope = PageEnvelope {
            scope,
            offset,
            total: total_u64,
            items: &items,
            next_offset: (next < total_u64).then_some(next),
        };
        if json_bytes(&envelope)? <= RESPONSE_BYTES {
            continue;
        }
        items.pop();
        if !items.is_empty() {
            break;
        }
        items.push(item(index, 0)?);
        let next = count(start + items.len())?;
        require_budget(&PageEnvelope {
            scope,
            offset,
            total: total_u64,
            items: &items,
            next_offset: (next < total_u64).then_some(next),
        })?;
    }
    let next = count(start + items.len())?;
    let next_offset = (next < total_u64).then_some(next);
    require_budget(&PageEnvelope {
        scope,
        offset,
        total: total_u64,
        items: &items,
        next_offset,
    })?;
    Ok(PageParts {
        scope: scope.clone(),
        offset,
        total: total_u64,
        items,
        next_offset,
    })
}

//! Product envelopes differ from Thread pages; their UTF-8 and full-JSON rules are shared.
use pl_protocol::products::identity::ProductCollectionRef;
use pl_protocol::studio::StudioError;
use serde::Serialize;

use super::super::read_budget::{INLINE_BYTES, RESPONSE_BYTES, count, json_bytes, protocol, require_budget};

#[derive(Clone, Copy)]
pub(super) enum PageBinding { List(u64), Collection(ProductCollectionRef) }

pub(super) struct PageParts<T> {
    pub(super) total: u64,
    pub(super) items: Vec<T>,
    pub(super) next_offset: Option<u64>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ListEnvelope<'a, T> {
    list_id: u64, offset: u64, total: u64, items: &'a [T], next_offset: Option<u64>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct EntryEnvelope<'a, T> {
    collection: ProductCollectionRef, offset: u64, items: &'a [T], next_offset: Option<u64>,
}

fn bytes<T: Serialize>(binding: PageBinding, offset: u64, total: u64, items: &[T], next_offset: Option<u64>)
    -> Result<usize, StudioError> {
    match binding {
        PageBinding::List(list_id) => json_bytes(&ListEnvelope { list_id, offset, total, items, next_offset }),
        PageBinding::Collection(collection) => json_bytes(&EntryEnvelope { collection, offset, items, next_offset }),
    }
}

pub(super) fn page<T: Serialize>(binding: PageBinding, total: usize, offset: u64, limit: u32,
    mut item: impl FnMut(usize, usize) -> Result<T, StudioError>) -> Result<PageParts<T>, StudioError> {
    if !(1..=100).contains(&limit) {
        return Err(StudioError::invalid_argument("Read page limit must be in 1..=100"));
    }
    let total_u64 = count(total)?;
    if let PageBinding::Collection(collection) = binding && collection.total != total_u64 {
        return Err(protocol("Product collection total differs from its immutable members"));
    }
    let start = usize::try_from(offset).ok().filter(|offset| *offset <= total)
        .ok_or_else(|| StudioError::invalid_argument("Read page offset exceeds the pinned list"))?;
    let end = start.saturating_add(limit as usize).min(total);
    let mut items = Vec::with_capacity(end - start);
    for index in start..end {
        items.push(item(index, INLINE_BYTES)?);
        let next = count(start + items.len())?;
        if bytes(binding, offset, total_u64, &items, (next < total_u64).then_some(next))? <= RESPONSE_BYTES {
            continue;
        }
        items.pop();
        if !items.is_empty() { break; }
        items.push(item(index, 0)?);
        let next = count(start + items.len())?;
        if bytes(binding, offset, total_u64, &items, (next < total_u64).then_some(next))? > RESPONSE_BYTES {
            return Err(pl_protocol::studio::StudioError::new(pl_protocol::studio::StudioErrorCode::Overloaded,
                "Product read item exceeds its transport budget even with deferred text", false));
        }
    }
    let next = count(start + items.len())?;
    let next_offset = (next < total_u64).then_some(next);
    // The concrete public DTO has this exact shape. Its caller also validates the final result.
    match binding {
        PageBinding::List(list_id) => require_budget(&ListEnvelope { list_id, offset, total: total_u64, items: &items, next_offset })?,
        PageBinding::Collection(collection) => require_budget(&EntryEnvelope { collection, offset, items: &items, next_offset })?,
    }
    Ok(PageParts { total: total_u64, items, next_offset })
}

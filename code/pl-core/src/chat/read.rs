//! Demand reads capture D/H and bounded scope-indexed pending Arcs in one short lock. Committed
//! and pending intervals never overlap; no read-after-IO merge, payload decoder or existence query.

use crate::chat::*;
use std::{
    ops::Bound::{Excluded, Included, Unbounded},
    sync::Arc,
};

struct Selection {
    records: Vec<(Arc<ChatItem>, PayloadMode)>,
    remaining: ReadDemand,
    exhausted: bool,
}

fn select_records<'a>(
    records: impl Iterator<Item = &'a Arc<ChatItem>>,
    demand: ReadDemand,
    budget: &dyn ChatBudget,
) -> Selection {
    let mut selection = Selection {
        records: Vec::new(),
        remaining: demand,
        exhausted: false,
    };
    for record in records {
        if selection.remaining.max_items == 0 || selection.remaining.max_bytes == 0 {
            return selection;
        }
        let Some(mode) = select_payload(&record.header, selection.remaining.max_bytes, budget)
        else {
            return selection;
        };
        selection.remaining.max_bytes -= budget.item_bytes(&record.header, mode);
        selection.remaining.max_items -= 1;
        selection.records.push((record.clone(), mode));
    }
    // Exact count/byte fills deliberately keep conservative continuation; no lookahead is required.
    selection.exhausted = selection.remaining.max_items > 0 && selection.remaining.max_bytes > 0;
    selection
}

fn project(records: Vec<(Arc<ChatItem>, PayloadMode)>) -> Vec<ChatPageItem> {
    records
        .into_iter()
        .map(|(record, mode)| ChatPageItem {
            header: record.header.clone(),
            payload: match mode {
                PayloadMode::Inline => PayloadData::Inline(record.payload.clone()),
                PayloadMode::Deferred => PayloadData::Deferred {
                    item_id: record.header.item_id.clone(),
                    byte_length: record.header.byte_length,
                },
            },
        })
        .collect()
}

pub(crate) fn reserve(
    demand: ReadDemand,
    budget: &dyn ChatBudget,
) -> Result<ReadDemand, ChatError> {
    demand.validate()?;
    let max_bytes = demand
        .max_bytes
        .checked_sub(budget.fixed_bytes())
        .filter(|bytes| *bytes > 0)
        .ok_or_else(|| ChatError::InvalidDemand("demand cannot hold an item envelope".into()))?;
    Ok(ReadDemand {
        max_bytes,
        ..demand
    })
}

/// Validate just the bounded port result, not the historical collection. No decoder or merge.
fn validate_history(
    page: &ChatHistoryPage,
    request: &ChatHistoryRequest,
    budget: &dyn ChatBudget,
) -> Result<ReadDemand, ChatError> {
    let mut remaining = request.demand;
    let mut previous = request.after;
    for item in &page.items {
        let header = &item.header;
        if header.append_seq <= previous
            || header.append_seq > request.ceiling
            || (request.query.is_none() && header.append_seq != previous + 1)
            || request
                .before
                .is_some_and(|before| header.append_seq >= before)
            || request
                .query
                .as_ref()
                .is_some_and(|query| !query.matches(header))
            || header.item_id.is_empty()
        {
            return Err(ChatError::Conflict(header.item_id.clone()));
        }
        match &item.payload {
            PayloadData::Inline(bytes) if bytes.len() as u64 == header.byte_length => {}
            PayloadData::Deferred {
                item_id,
                byte_length,
            } if item_id == &header.item_id && *byte_length == header.byte_length => {}
            _ => return Err(ChatError::Conflict(header.item_id.clone())),
        }
        remaining.max_items = remaining
            .max_items
            .checked_sub(1)
            .ok_or_else(|| ChatError::Overloaded("history exceeded item demand".into()))?;
        remaining.max_bytes = remaining
            .max_bytes
            .checked_sub(budget.item_bytes(header, item.payload.mode()))
            .ok_or_else(|| ChatError::Overloaded("history exceeded encoded byte demand".into()))?;
        previous = header.append_seq;
    }
    if request.query.is_none() && page.exhausted && previous != request.ceiling {
        return Err(ChatError::Conflict(
            "incomplete unfiltered history interval".into(),
        ));
    }
    Ok(remaining)
}

impl Session {
    pub(crate) fn validate_epoch(&self, epoch: &TimelineEpoch) -> Result<(), ChatError> {
        if epoch == &self.0.epoch {
            Ok(())
        } else {
            Err(ChatError::EpochMismatch {
                cursor: epoch.clone(),
                session: self.0.epoch.clone(),
            })
        }
    }

    pub async fn page(
        &self,
        request: ChatPageRequest,
        budget: &dyn ChatBudget,
    ) -> Result<ChatPage, ChatError> {
        request.query.validate()?;
        let demand = reserve(request.demand, budget)?;
        if let Some(before) = &request.before {
            self.validate_epoch(&before.epoch)?;
            if before.query != request.query
                || request
                    .ceiling
                    .is_some_and(|ceiling| ceiling != before.ceiling)
                || before.append_seq == 0
                || before.append_seq > before.ceiling
            {
                return Err(ChatError::InvalidArgument(
                    "cursor query or ceiling mismatch".into(),
                ));
            }
        }
        self.ensure_initialized().await?;
        let (head, durable, mut selected) = self.with_timeline(|state| {
            let head = request
                .before
                .as_ref()
                .map(|cursor| cursor.ceiling)
                .or(request.ceiling)
                .unwrap_or(state.head);
            if head > state.head {
                return Err(ChatError::InvalidArgument(
                    "ceiling exceeds published head".into(),
                ));
            }
            let upper = request
                .before
                .as_ref()
                .map_or(head, |cursor| head.min(cursor.append_seq - 1));
            let records = state.pending_index(Some(&request.query));
            let selection = if upper <= state.durable {
                Selection {
                    records: Vec::new(),
                    remaining: demand,
                    exhausted: true,
                }
            } else {
                select_records(
                    records.into_iter().flat_map(|index| {
                        index
                            .range((Excluded(state.durable), Included(upper)))
                            .rev()
                            .map(|(_, record)| record)
                    }),
                    demand,
                    budget,
                )
            };
            Ok((head, state.durable.min(head), selection))
        })?;
        let pending_exhausted = selected.exhausted;
        let mut stored_exhausted = durable == 0;
        let mut stored_items = Vec::new();
        if pending_exhausted
            && selected.remaining.max_items > 0
            && selected.remaining.max_bytes > 0
            && durable > 0
        {
            let history_request = ChatHistoryRequest {
                query: Some(request.query.clone()),
                after: 0,
                before: request.before.as_ref().map(|cursor| cursor.append_seq),
                ceiling: durable,
                demand: selected.remaining,
            };
            let page = self.0.history.page(&history_request, budget).await?;
            validate_history(&page, &history_request, budget)?;
            stored_exhausted = page.exhausted;
            stored_items = page.items;
        }
        selected.records.reverse();
        stored_items.extend(project(selected.records));
        if stored_items.is_empty() && !(pending_exhausted && stored_exhausted) {
            return Err(ChatError::InvalidDemand(
                "demand cannot hold the next item envelope".into(),
            ));
        }
        let before = if pending_exhausted && stored_exhausted {
            None
        } else {
            stored_items.first().map(|item| ChatCursor {
                epoch: self.epoch(),
                query: request.query,
                ceiling: head,
                append_seq: item.header.append_seq,
            })
        };
        Ok(ChatPage {
            epoch: self.epoch(),
            ceiling: head,
            items: stored_items,
            before,
        })
    }

    /// Bounded internal replay from a fixed epoch/position. Filtered sequences may have gaps.
    pub async fn completed_after(
        &self,
        after: ChatCompletionCursor,
        query: Option<ChatQuery>,
        ceiling: Option<u64>,
        demand: ReadDemand,
        budget: &dyn ChatBudget,
    ) -> Result<ChatCompletedBatch, ChatError> {
        self.validate_epoch(&after.epoch)?;
        if let Some(query) = &query {
            query.validate()?;
        }
        let demand = reserve(demand, budget)?;
        self.ensure_initialized().await?;
        let (head, durable, captured) = self.with_timeline(|state| {
            let head = ceiling.unwrap_or(state.head);
            if head > state.head || after.append_seq > head {
                return Err(ChatError::InvalidArgument("invalid replay interval".into()));
            }
            let lower = after.append_seq.max(state.durable);
            // Capture bounded references now; a writer may clear them while history awaits.
            let records = if lower < head {
                state
                    .pending_index(query.as_ref())
                    .into_iter()
                    .flat_map(|index| {
                        index
                            .range((Excluded(lower), Included(head)))
                            .map(|(_, record)| record)
                    })
                    .take(demand.max_items)
                    .cloned()
                    .collect()
            } else {
                Vec::new()
            };
            Ok((head, state.durable.min(head), records))
        })?;
        let mut remaining = demand;
        let mut items = Vec::new();
        if after.append_seq < durable {
            let request = ChatHistoryRequest {
                query: query.clone(),
                after: after.append_seq,
                before: None,
                ceiling: durable,
                demand: remaining,
            };
            let stored = self.0.history.page_after(&request, budget).await?;
            remaining = validate_history(&stored, &request, budget)?;
            if !stored.exhausted {
                if stored.items.is_empty() {
                    return Err(ChatError::InvalidDemand(
                        "replay demand cannot hold next envelope".into(),
                    ));
                }
                let through_seq = stored
                    .items
                    .last()
                    .map_or(after.append_seq, |item| item.header.append_seq);
                return Ok(ChatCompletedBatch {
                    from_seq: after.append_seq,
                    through_seq,
                    items: stored.items,
                });
            }
            items = stored.items;
        }
        let selected = select_records(captured.iter(), remaining, budget);
        let exhausted = selected.exhausted;
        items.extend(project(selected.records));
        // A full captured window may hide additional matches; only advance over filtered gaps when
        // the captured matching index itself was exhausted. Counting one extra reference is unnecessary:
        // a full window advances to its last item and the next call confirms EOF.
        let exhausted = exhausted && captured.len() < demand.max_items;
        let through_seq = if exhausted {
            head
        } else {
            items
                .last()
                .map_or(after.append_seq, |item| item.header.append_seq)
        };
        if through_seq == after.append_seq && head > after.append_seq {
            return Err(ChatError::InvalidDemand(
                "replay demand cannot hold next envelope".into(),
            ));
        }
        Ok(ChatCompletedBatch {
            from_seq: after.append_seq,
            through_seq,
            items,
        })
    }

    pub async fn read_content(
        &self,
        request: ContentReadRequest,
    ) -> Result<ContentWindow, ChatError> {
        request.validate()?;
        self.validate_epoch(&request.epoch)?;
        let captured = self.with_timeline(|state| match &request.reference {
            ContentRef::ItemPayload(id) => state
                .pending_record(id)
                .map(|record| (ContentData::Bytes(record.payload.clone()), 0)),
            ContentRef::Body(key) => state
                .pending_content(key)
                .map(|content| (content.data.clone(), content.descriptor.generation)),
        });
        if let Some((data, generation)) = captured {
            if request
                .generation
                .is_some_and(|expected| expected != generation)
            {
                return Err(ChatError::StaleContent);
            }
            return Ok(ContentWindow {
                offset: request.offset,
                bytes: data.range(request.offset, request.max_bytes)?,
                generation,
                available_through: data.len() as u64,
                sealed: true,
            });
        }
        let window = self.0.history.read_content(&request).await?;
        if request
            .generation
            .is_some_and(|generation| generation != window.generation)
        {
            return Err(ChatError::StaleContent);
        }
        if window.offset != request.offset
            || window.bytes.as_bytes().len() > request.max_bytes
            || !window.sealed
            || window.offset > window.available_through
            || window.bytes.as_bytes().len() as u64 > window.available_through - window.offset
            || (window.bytes.as_bytes().is_empty() && window.offset < window.available_through)
        {
            return Err(ChatError::Conflict("invalid history content range".into()));
        }
        Ok(window)
    }

    pub async fn list_contents(
        &self,
        request: ContentManifestRequest,
        budget: &dyn ChatBudget,
    ) -> Result<ContentManifestPage, ChatError> {
        self.validate_epoch(&request.epoch)?;
        let demand = reserve(request.demand, budget)?;
        if let Some(record) = self.with_timeline(|state| state.pending_record(&request.item_id)) {
            let mut entries = Vec::new();
            let mut remaining = demand;
            let lower = request.after.as_ref().map_or(Unbounded, Excluded);
            let mut exhausted = true;
            for (_, content) in record.contents.range((lower, Unbounded)) {
                let cost = budget.manifest_bytes(&content.descriptor);
                if remaining.max_items == 0 || cost > remaining.max_bytes {
                    exhausted = false;
                    break;
                }
                remaining.max_items -= 1;
                remaining.max_bytes -= cost;
                entries.push(content.descriptor.clone());
            }
            if entries.is_empty() && !exhausted {
                return Err(ChatError::InvalidDemand(
                    "manifest envelope exceeds demand".into(),
                ));
            }
            let next = if exhausted {
                None
            } else {
                entries.last().map(|entry| entry.key.clone())
            };
            return Ok(ContentManifestPage { entries, next });
        }
        let mut request = request;
        request.demand = demand;
        let page = self.0.history.list_contents(&request, budget).await?;
        let mut remaining = demand;
        let mut previous = request.after.as_ref();
        for entry in &page.entries {
            if previous.is_some_and(|previous| &entry.key <= previous) {
                return Err(ChatError::Conflict("unordered content manifest".into()));
            }
            remaining.max_items = remaining
                .max_items
                .checked_sub(1)
                .ok_or_else(|| ChatError::Overloaded("manifest item budget".into()))?;
            remaining.max_bytes = remaining
                .max_bytes
                .checked_sub(budget.manifest_bytes(entry))
                .ok_or_else(|| ChatError::Overloaded("manifest byte budget".into()))?;
            previous = Some(&entry.key);
        }
        if page
            .next
            .as_ref()
            .is_some_and(|next| Some(next) != page.entries.last().map(|entry| &entry.key))
        {
            return Err(ChatError::Conflict(
                "non-progressing content manifest".into(),
            ));
        }
        Ok(page)
    }
}

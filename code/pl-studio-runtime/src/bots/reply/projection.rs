//! Bounded, target-only Final projection. No internal body survives this boundary.

use super::content::{FinalError, MAX_TURN_BODY_BYTES, MAX_TURN_CONTENT_ITEMS};
use pl_protocol::{
    ThreadContentField, ThreadTextChannel, TimelineChange, TimelineDescriptor, TimelineFieldChange,
    TimelineFieldUpdate, TimelineItem, TimelineItemHeader,
};
use std::collections::BTreeMap;
use std::sync::Arc;

#[derive(Clone, PartialEq, Eq)]
struct FinalField {
    text: Arc<String>,
    total_bytes: u64,
}

#[derive(Clone, PartialEq, Eq)]
struct ReplyItem {
    header: TimelineItemHeader,
    revision: u64,
    is_final: bool,
    is_start: bool,
    body: Option<FinalField>,
}

pub(super) struct ReplyProjection {
    thread_id: String,
    turn_id: String,
    items: BTreeMap<String, ReplyItem>,
    covered: bool,
}

impl ReplyProjection {
    pub(super) fn new(thread_id: &str, turn_id: &str) -> Self {
        Self {
            thread_id: thread_id.to_string(),
            turn_id: turn_id.to_string(),
            items: BTreeMap::new(),
            covered: false,
        }
    }

    pub(super) fn add_page(&mut self, items: Vec<TimelineItem>) -> Result<(), FinalError> {
        let changes = items
            .into_iter()
            .map(|item| TimelineChange::Add {
                item: Box::new(item),
            })
            .collect();
        self.apply(changes)
    }

    pub(super) fn has_start(&self) -> bool {
        self.items.values().any(|item| item.is_start)
    }

    pub(super) fn mark_covered(&mut self) {
        self.covered = true;
    }

    pub(super) fn preview(&self) -> Option<String> {
        if !self.covered {
            return None;
        }
        let mut ordered: Vec<_> = self.items.values().collect();
        ordered.sort_by_key(|item| (item.header.ordinal, item.header.id.as_str()));
        let mut text = String::new();
        for item in ordered {
            if !item.is_final {
                continue;
            }
            if let Some(body) = &item.body {
                // A prefix with omitted bytes cannot be followed by another block:
                // that would silently splice a hole into the displayed answer.
                text.push_str(body.text.as_str());
                if body.text.len() as u64 != body.total_bytes {
                    break;
                }
            }
        }
        (!text.trim().is_empty()).then_some(text)
    }

    /// Stage only touched records. Validation precedes all writes, including revision commits.
    pub(super) fn apply(&mut self, changes: Vec<TimelineChange>) -> Result<(), FinalError> {
        let mut staged: BTreeMap<String, Option<ReplyItem>> = BTreeMap::new();
        for change in changes {
            match change {
                TimelineChange::Add { item } => {
                    validate_header(&item.header, &self.thread_id)?;
                    let current = staged
                        .get(&item.header.id)
                        .map_or_else(|| self.items.get(&item.header.id), Option::as_ref);
                    if let Some(current) = current
                        && (current.header.ordinal != item.header.ordinal
                            || item.revision < current.revision
                            || item.revision == current.revision && current.header != item.header)
                    {
                        return Err(gap("Final Add identity or revision conflict"));
                    }
                    if item.header.turn_id != self.turn_id {
                        // An authoritative Add may reclassify a previously retained item.
                        staged.insert(item.header.id, None);
                        continue;
                    }
                    let next = reply_item(*item)?;
                    if let Some(current) = current
                        && current.revision == next.revision
                        && !same_revision(current, &next)
                    {
                        return Err(gap("Final Add changed content without revision"));
                    }
                    staged.insert(next.header.id.clone(), Some(next));
                }
                TimelineChange::Remove { item_id } => {
                    staged.insert(item_id, None);
                }
                TimelineChange::UpdateItem {
                    item_id,
                    expected_revision,
                    revision,
                    header,
                    descriptor,
                    fields,
                    ..
                } => {
                    if let Some(header) = &header {
                        validate_header(header, &self.thread_id)?;
                        if header.id != item_id {
                            return Err(gap("Final patch item identity conflict"));
                        }
                    }
                    let current = staged
                        .get(&item_id)
                        .map_or_else(|| self.items.get(&item_id), Option::as_ref);
                    let Some(current) = current else {
                        if header.as_ref().is_some_and(|h| h.turn_id == self.turn_id) {
                            return Err(gap("patch moved an unknown item into reply target"));
                        }
                        continue;
                    };
                    if current.revision != expected_revision || revision < expected_revision {
                        return Err(gap("Final patch revision is not continuous"));
                    }
                    let mut next = current.clone();
                    if let Some(header) = header {
                        if header.ordinal != current.header.ordinal {
                            return Err(gap("Final patch changed stable order"));
                        }
                        next.header = header;
                    }
                    if next.header.turn_id != self.turn_id {
                        if revision == expected_revision {
                            return Err(gap("Final target changed without revision"));
                        }
                        staged.insert(item_id, None);
                        continue;
                    }
                    if let Some(descriptor) = descriptor {
                        let is_final = is_final(&descriptor);
                        next.is_start = matches!(*descriptor, TimelineDescriptor::Turn(_));
                        if !is_final {
                            next.body = None;
                        }
                        if is_final && !next.is_final {
                            // A former private channel's Unchanged text is not cached here.
                            // Require an authoritative replacement or a fresh baseline.
                            next.body = None;
                            if !fields.iter().any(|field| {
                                field.field == ThreadContentField::Text
                                    && matches!(field.change, TimelineFieldChange::Replace { .. })
                            }) {
                                return Err(gap("Final channel changed without a text baseline"));
                            }
                        }
                        next.is_final = is_final;
                    }
                    let mut saw_text = false;
                    for field in fields {
                        if field.field != ThreadContentField::Text || !next.is_final {
                            continue;
                        }
                        if saw_text {
                            return Err(gap("duplicate Final text field update"));
                        }
                        saw_text = true;
                        apply_field(&mut next.body, field)?;
                    }
                    if revision == expected_revision && !same_revision(current, &next) {
                        return Err(gap("Final content changed without revision"));
                    }
                    next.revision = revision;
                    staged.insert(item_id, Some(next));
                }
            }
        }
        let mut bytes = 0usize;
        let mut count = 0usize;
        for (id, item) in &self.items {
            if !staged.contains_key(id) {
                account(item, &mut bytes, &mut count)?;
            }
        }
        for item in staged.values().flatten() {
            account(item, &mut bytes, &mut count)?;
        }
        for (id, item) in staged {
            match item {
                Some(item) => {
                    self.items.insert(id, item);
                }
                None => {
                    self.items.remove(&id);
                }
            }
        }
        Ok(())
    }
}

fn reply_item(item: TimelineItem) -> Result<ReplyItem, FinalError> {
    let mut body = None;
    let is_final = is_final(&item.descriptor);
    if is_final {
        for field in item.fields {
            if field.field != ThreadContentField::Text {
                continue;
            }
            if body.is_some() || field.text.len() as u64 > field.total_bytes {
                return Err(gap("invalid Final text preview"));
            }
            body = Some(FinalField {
                text: Arc::new(field.text),
                total_bytes: field.total_bytes,
            });
        }
    }
    Ok(ReplyItem {
        header: item.header,
        revision: item.revision,
        is_final,
        is_start: matches!(item.descriptor, TimelineDescriptor::Turn(_)),
        body,
    })
}

fn is_final(descriptor: &TimelineDescriptor) -> bool {
    matches!(descriptor, TimelineDescriptor::Text(text) if text.channel == ThreadTextChannel::Final)
}

fn same_revision(previous: &ReplyItem, next: &ReplyItem) -> bool {
    if previous.header != next.header
        || previous.is_final != next.is_final
        || previous.is_start != next.is_start
    {
        return false;
    }
    match (&previous.body, &next.body) {
        (None, None) => true,
        (Some(previous), Some(next)) => {
            // Page and tail can carry different preview budgets for the same
            // revision. Only prefix length may differ, never authoritative bytes.
            previous.total_bytes == next.total_bytes
                && (previous.text.starts_with(next.text.as_str())
                    || next.text.starts_with(previous.text.as_str()))
        }
        _ => false,
    }
}

fn apply_field(
    body: &mut Option<FinalField>,
    update: TimelineFieldUpdate,
) -> Result<(), FinalError> {
    if update.preview_bytes > update.total_bytes {
        return Err(gap("Final preview exceeds total bytes"));
    }
    match update.change {
        TimelineFieldChange::Remove => {
            if update.preview_bytes != 0 || update.total_bytes != 0 {
                return Err(gap("Final field removal has nonzero bytes"));
            }
            *body = None;
        }
        TimelineFieldChange::Replace { text } => {
            if text.len() as u64 != update.preview_bytes {
                return Err(gap("Final replacement length conflict"));
            }
            *body = Some(FinalField {
                text: Arc::new(text),
                total_bytes: update.total_bytes,
            });
        }
        TimelineFieldChange::Append { text } => {
            let Some(body) = body else {
                return Err(gap("Final append lacks a field baseline"));
            };
            if body
                .text
                .len()
                .checked_add(text.len())
                .map(|len| len as u64)
                != Some(update.preview_bytes)
                || update.total_bytes < body.total_bytes
            {
                return Err(gap("Final append length conflict"));
            }
            Arc::make_mut(&mut body.text).push_str(&text);
            body.total_bytes = update.total_bytes;
        }
        TimelineFieldChange::Unchanged => {
            let Some(body) = body else {
                return Err(gap("Final unchanged field lacks a baseline"));
            };
            if body.text.len() as u64 != update.preview_bytes {
                return Err(gap("Final unchanged preview length conflict"));
            }
            body.total_bytes = update.total_bytes;
        }
    }
    Ok(())
}

fn validate_header(header: &TimelineItemHeader, thread_id: &str) -> Result<(), FinalError> {
    // Pending/discarded inputs legitimately have no Turn binding. Target
    // association is checked by the caller, not by shared header validation.
    if header.thread_id != thread_id || header.id.is_empty() {
        return Err(gap("reply content identity conflict"));
    }
    Ok(())
}

fn account(item: &ReplyItem, bytes: &mut usize, count: &mut usize) -> Result<(), FinalError> {
    *count += 1;
    if let Some(body) = &item.body {
        *bytes = bytes
            .checked_add(body.text.len())
            .ok_or_else(|| gap("reply body size overflow"))?;
    }
    if *count > MAX_TURN_CONTENT_ITEMS || *bytes > MAX_TURN_BODY_BYTES {
        return Err(FinalError::Attention(
            "reply projection exceeded its item or UTF-8 budget".to_string(),
        ));
    }
    Ok(())
}

pub(super) fn gap(message: &str) -> FinalError {
    FinalError::Retryable(message.to_string())
}

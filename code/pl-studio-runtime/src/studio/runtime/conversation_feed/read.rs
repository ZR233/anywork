//! Exact fragment accounting for the feed's existing, frozen candidate list.
use super::*;
use crate::studio::thread_projection::CurrentHandoff;
use anyhow::Context;

#[derive(Clone, Copy)]
pub(super) struct CutMeasure {
    base: usize,
    suffix_bytes: usize,
    suffix_items: usize,
    item_wrapper: usize,
    after_items: usize,
}

// The handoff reserves this fixed metadata in its original retention budget.
const _: () =
    assert!(std::mem::size_of::<Option<CutMeasure>>() <= CurrentHandoff::DELIVERY_MEASURE_BYTES);

fn overflow() -> anyhow::Error {
    anyhow::anyhow!("chat JSON fragment accounting overflow")
}

// Only the adjacent-tag envelope is measured here. The protocol's item itself
// is always serialized by its own Serialize implementation.
#[derive(serde::Serialize)]
#[serde(tag = "kind", content = "value", rename_all = "camelCase")]
enum ItemEnvelope {
    Item(()),
}

impl CutMeasure {
    pub(super) fn new(
        handoff: &CurrentHandoff,
        candidates: &[ChatEntry],
        main: bool,
    ) -> Result<Self> {
        let empty = ChatBatch {
            placement: ChatPlacement::Append,
            entries: Vec::new(),
            before: None,
            current: None,
        };
        let mut measure = Self {
            base: empty.encoded_len()?,
            suffix_bytes: 0,
            suffix_items: 0,
            item_wrapper: serde_json::to_vec(&ItemEnvelope::Item(()))?
                .len()
                .checked_sub(4)
                .ok_or_else(overflow)?,
            after_items: 0,
        };
        if main {
            let after_bytes = handoff.after().json_bytes();
            // MAX is the frozen owner's explicit encoding-failure sentinel.
            ensure!(after_bytes != u64::MAX, "current JSON measurement failed");
            measure.base = measure
                .base
                .checked_sub(4)
                .and_then(|base| base.checked_add(usize::try_from(after_bytes).ok()?))
                .ok_or_else(overflow)?;
            measure.after_items = handoff.after().projection().items.len();
            for entry in candidates {
                if let ChatEntry::Item(item) = entry {
                    let bytes = current_item_bytes(item, serde_json::to_vec(item)?.len())?;
                    measure.suffix_bytes = measure
                        .suffix_bytes
                        .checked_add(bytes)
                        .ok_or_else(overflow)?;
                    measure.suffix_items =
                        measure.suffix_items.checked_add(1).ok_or_else(overflow)?;
                }
            }
        }
        Ok(measure)
    }

    /// The original (Deferred) candidate length also measures its retirement.
    /// Inline optimization changes the delivered entry, never this frozen suffix.
    pub(super) fn after_entry(self, entry: &ChatEntry, entry_bytes: usize) -> Result<Self> {
        let mut next = self;
        if let ChatEntry::Item(item) = entry {
            let item_bytes = entry_bytes
                .checked_sub(self.item_wrapper)
                .ok_or_else(overflow)?;
            let current_bytes = current_item_bytes(item, item_bytes)?;
            next.suffix_bytes = next
                .suffix_bytes
                .checked_sub(current_bytes)
                .ok_or_else(overflow)?;
            next.suffix_items = next.suffix_items.checked_sub(1).ok_or_else(overflow)?;
        }
        Ok(next)
    }

    pub(super) fn frame_bytes_for(
        self,
        entries_bytes: usize,
        entries: usize,
        placement: ChatPlacement,
    ) -> Result<usize> {
        if placement == ChatPlacement::Update {
            return ChatBatch {
                placement,
                entries: Vec::new(),
                before: None,
                current: None,
            }
            .encoded_len()?
            .checked_add(entries_bytes)
            .and_then(|bytes| bytes.checked_add(entries.saturating_sub(1)))
            .ok_or_else(overflow);
        }
        self.frame_bytes(entries_bytes, entries)
    }

    pub(super) fn frame_bytes(self, entries_bytes: usize, entries: usize) -> Result<usize> {
        self.base
            .checked_add(self.suffix_bytes)
            .and_then(|bytes| bytes.checked_add(self.suffix_items.saturating_sub(1)))
            .and_then(|bytes| {
                bytes.checked_add(usize::from(self.suffix_items > 0 && self.after_items > 0))
            })
            .and_then(|bytes| bytes.checked_add(entries_bytes))
            .and_then(|bytes| bytes.checked_add(entries.saturating_sub(1)))
            .ok_or_else(overflow)
    }
}

fn current_item_bytes(item: &TimelineItem, bytes: usize) -> Result<usize> {
    // position is an always-present nullable field. Replace only its serialized
    // fragment with serde's null length; borrow all payload/content metadata.
    bytes
        .checked_sub(serde_json::to_vec(&item.position)?.len())
        .and_then(|bytes| bytes.checked_add(4))
        .context("current item JSON fragment accounting overflow")
}

pub(super) fn entry_json_bytes(entry: &ChatEntry) -> Result<usize> {
    Ok(serde_json::to_vec(entry)?.len())
}

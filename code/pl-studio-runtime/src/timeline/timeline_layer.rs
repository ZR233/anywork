//! Timeline data processing layer: stitches `history.sqlite ∪ Pending` on cold open and paging,
//! buffers live `Work` (`timeline_role = 1`) events, and seals `WorkGroup("work:<first_seq>")`
//! strictly on `Boundary` (`timeline_role = 2`), independently of live status or persistence.

use anyhow::Result;
use base64::Engine as _;

use crate::history::{
    HistoryCut, HistoryDemand, HistoryEventKind, HistoryEventRecord, HistoryReader,
    HistoryTimelineEntry, HistoryTimelinePage, HistoryTimelineRole,
};

use super::decoder::{decode_boundary_item, fold_work_group_members, summarize_work_group};
use super::models::{
    BodyRef, BodyWindow, ConversationEvent, TimelineItem, TimelinePatch, WorkGroupMember,
};

pub const DEFAULT_TIMELINE_PAGE_ROWS: u32 = 64;
pub const TIMELINE_DEMAND_BYTES: u32 = 1024 * 1024;
pub const BODY_CHUNK_READ_BYTES: u32 = 64 * 1024;

fn demand(max_rows: u32) -> HistoryDemand {
    HistoryDemand {
        max_rows: max_rows.clamp(1, 512),
        max_bytes: TIMELINE_DEMAND_BYTES,
    }
}

/// Stateful per-subscription timeline stream & cold-history stitcher.
#[derive(Debug)]
pub struct TimelineDataLayer {
    cut: Option<HistoryCut>,
    cut_seq: u64,
    oldest_boundary_seq: Option<u64>,
    last_boundary_seq: Option<u64>,
    pending_work: Vec<HistoryEventRecord>,
    revision: u64,
}

impl Default for TimelineDataLayer {
    fn default() -> Self {
        Self::new()
    }
}

impl TimelineDataLayer {
    #[must_use]
    pub fn new() -> Self {
        Self {
            cut: None,
            cut_seq: 0,
            oldest_boundary_seq: None,
            last_boundary_seq: None,
            pending_work: Vec::new(),
            revision: 0,
        }
    }

    #[must_use]
    pub fn cut_seq(&self) -> u64 {
        self.cut_seq
    }

    #[must_use]
    pub fn cut(&self) -> Option<&HistoryCut> {
        self.cut.as_ref()
    }

    /// Loads the latest page (`history.sqlite ∪ Pending`) anchored at a consistent `cut`
    /// captured AFTER subscribing to `MetaEventBus`, preventing any miss or duplicate frame.
    ///
    /// Trailing `Work` after the newest boundary always remains buffered until the next boundary,
    /// including idle subscriptions and process restarts. Live status does not determine grouping.
    pub async fn load_initial_page(
        &mut self,
        reader: &HistoryReader,
        limit: u32,
        _is_working_live: bool,
    ) -> Result<TimelinePatch> {
        let (cut, through) = reader.capture_position().await?;
        let page = reader.timeline_page(Some(cut), None, demand(limit)).await?;
        let (items, oldest_boundary, last_boundary, trailing_work) =
            materialize_page_items(reader, &page, None, None, true).await?;

        self.cut = Some(page.cut.clone());
        self.cut_seq = through;
        self.oldest_boundary_seq = oldest_boundary;
        self.last_boundary_seq = last_boundary;
        self.pending_work = trailing_work;
        self.revision += 1;

        Ok(TimelinePatch::Reset {
            items,
            has_more_older: page.next.is_some(),
            older_cursor: page.next,
            revision: self.revision,
        })
    }

    /// Loads an older page (`< cursor`) without disturbing the live subscription frontier,
    /// preserving any `WorkGroup` that sits between this page's newest boundary and the
    /// previously loaded oldest boundary.
    pub async fn load_older(
        &mut self,
        reader: &HistoryReader,
        cursor: String,
        limit: u32,
    ) -> Result<TimelinePatch> {
        let page = reader
            .timeline_page(self.cut.clone(), Some(cursor), demand(limit))
            .await?;
        let (items, oldest_boundary, _, _) =
            materialize_page_items(reader, &page, None, self.oldest_boundary_seq, false).await?;
        if let Some(oldest) = oldest_boundary {
            self.oldest_boundary_seq = Some(match self.oldest_boundary_seq {
                Some(prev) => prev.min(oldest),
                None => oldest,
            });
        }
        Ok(TimelinePatch::PrependOlder {
            items,
            has_more_older: page.next.is_some(),
            older_cursor: page.next,
        })
    }

    /// On-demand 1-shot fetch & folding of all `timeline_role = 1` work events in `(after_seq, before_seq)`,
    /// merging `history.sqlite ∪ Pending` at the latest live head and backfilling cross-range
    /// `tool_called` metadata if missing.
    pub async fn load_work_group_members(
        reader: &HistoryReader,
        after_seq: Option<u64>,
        before_seq: Option<u64>,
    ) -> Result<Vec<WorkGroupMember>> {
        let mut records = fetch_all_work_range(reader, None, after_seq, before_seq).await?;
        // Backfill arguments/contract for tools whose `ToolCalled` started before `after_seq`.
        if let Some(after) = after_seq {
            let mut missing_call_ids = Vec::new();
            let mut seen_called = std::collections::HashSet::new();
            for r in &records {
                if let Some(cid) = &r.call_id {
                    if r.kind == HistoryEventKind::ToolCalled {
                        seen_called.insert(cid.clone());
                    } else if !seen_called.contains(cid) && !missing_call_ids.contains(cid) {
                        missing_call_ids.push(cid.clone());
                    }
                }
            }
            for call_id in missing_call_ids {
                let page = reader
                    .events_page(
                        crate::history::HistoryEventsQuery::Call {
                            call_id: call_id.clone(),
                        },
                        None,
                        None,
                        demand(32),
                    )
                    .await?;
                for prior in page.entries {
                    if prior.seq <= after && prior.kind == HistoryEventKind::ToolCalled {
                        records.insert(0, prior);
                    }
                }
            }
        }
        Ok(fold_work_group_members(records))
    }

    /// Reads one bounded 64 KiB body chunk window (seamlessly merging `Pending` + `history.sqlite`).
    pub async fn read_body_window(
        reader: &HistoryReader,
        body_ref: &BodyRef,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BodyWindow> {
        let clamped = max_bytes.clamp(1, BODY_CHUNK_READ_BYTES);
        let window = reader
            .read_body(
                crate::history::HistoryEventBodyRef {
                    database_id: body_ref.database_id.clone(),
                    body_id: body_ref.body_id.clone(),
                    owner_event_id: body_ref.owner_event_id.clone(),
                    body_key: body_ref.body_key.clone(),
                    byte_start: 0,
                    byte_length: body_ref.byte_length,
                },
                offset,
                clamped,
            )
            .await?;
        let text = String::from_utf8(window.bytes.clone()).ok();
        let bytes_base64 = if text.is_none() {
            Some(base64::engine::general_purpose::STANDARD.encode(&window.bytes))
        } else {
            None
        };
        let eof = window.offset.saturating_add(window.bytes.len() as u64) >= window.total_length;
        Ok(BodyWindow {
            offset: window.offset,
            text,
            bytes_base64,
            total_bytes: window.total_length,
            eof,
        })
    }

    /// Processes a live `HistoryEventRecord` broadcast from `MetaEventBus`.
    /// Buffers `Work` (`1`) in `pending_work` and seals `WorkGroup` only on a grouping separator.
    pub fn on_history_record(
        &mut self,
        record: &HistoryEventRecord,
        input_id: Option<&str>,
    ) -> Vec<ConversationEvent> {
        if record.seq <= self.cut_seq {
            return Vec::new();
        }
        self.cut_seq = record.seq;
        let mut out = Vec::new();

        match record.timeline_role {
            HistoryTimelineRole::Work => {
                self.pending_work.push(record.clone());
            }
            HistoryTimelineRole::Boundary => {
                let mut appended = Vec::new();
                if let Some(group) = self.seal_pending(record.seq) {
                    appended.push(group);
                }
                let item = decode_boundary_item(record);
                let item_id = item.id().to_owned();
                appended.push(item);
                self.last_boundary_seq = Some(record.seq);
                out.push(ConversationEvent::Timeline(TimelinePatch::Append {
                    items: appended,
                }));
                if record.kind == HistoryEventKind::InputAccepted
                    && let Some(input_id) = input_id
                {
                    out.push(ConversationEvent::InputPresented {
                        input_id: input_id.to_owned(),
                        item_id,
                    });
                }
            }
            HistoryTimelineRole::Hidden => {}
        }
        out
    }

    fn seal_pending(&mut self, before_boundary_seq: u64) -> Option<TimelineItem> {
        let after_seq = self.last_boundary_seq;
        let work = std::mem::take(&mut self.pending_work);
        summarize_work_group(&work, after_seq, Some(before_boundary_seq), false)
    }
}

async fn fetch_all_work_range(
    reader: &HistoryReader,
    cut: Option<&HistoryCut>,
    after_seq: Option<u64>,
    before_seq: Option<u64>,
) -> Result<Vec<HistoryEventRecord>> {
    let mut events = Vec::new();
    let mut cursor = None;
    loop {
        let page = reader
            .work_range_page(after_seq, before_seq, cut.cloned(), cursor, demand(256))
            .await?;
        events.extend(page.events);
        match page.next {
            Some(next) => cursor = Some(next),
            None => break,
        }
    }
    Ok(events)
}

async fn materialize_page_items(
    reader: &HistoryReader,
    page: &HistoryTimelinePage,
    prior_boundary_seq: Option<u64>,
    next_page_boundary_seq: Option<u64>,
    is_latest_page: bool,
) -> Result<(
    Vec<TimelineItem>,
    Option<u64>,
    Option<u64>,
    Vec<HistoryEventRecord>,
)> {
    let mut entries_asc: Vec<&HistoryTimelineEntry> = page.entries.iter().collect();
    entries_asc.sort_by_key(|e| e.event.seq);

    let mut items = Vec::with_capacity(entries_asc.len() * 2);

    if entries_asc.is_empty() {
        if page.has_folded_before_oldest {
            let work = fetch_all_work_range(
                reader,
                Some(&page.cut),
                prior_boundary_seq,
                next_page_boundary_seq,
            )
            .await?;
            if !work.is_empty() {
                if is_latest_page {
                    return Ok((items, None, prior_boundary_seq, work));
                }
                if let Some(before_seq) = next_page_boundary_seq
                    && let Some(group) =
                        summarize_work_group(&work, prior_boundary_seq, Some(before_seq), false)
                {
                    items.push(group);
                }
            }
        }
        return Ok((items, None, prior_boundary_seq, Vec::new()));
    }

    if page.has_folded_before_oldest && page.next.is_none() {
        let first_seq = entries_asc[0].event.seq;
        let work = fetch_all_work_range(reader, Some(&page.cut), None, Some(first_seq)).await?;
        if let Some(group) = summarize_work_group(&work, None, Some(first_seq), false) {
            items.push(group);
        }
    }

    let mut trailing_work = Vec::new();
    for (idx, entry) in entries_asc.iter().enumerate() {
        items.push(decode_boundary_item(&entry.event));
        let next_boundary_seq = entries_asc
            .get(idx + 1)
            .map(|next| next.event.seq)
            .or_else(|| {
                (!is_latest_page)
                    .then_some(next_page_boundary_seq)
                    .flatten()
            });
        if entry.has_folded_after {
            let work = fetch_all_work_range(
                reader,
                Some(&page.cut),
                Some(entry.event.seq),
                next_boundary_seq,
            )
            .await?;
            if !work.is_empty() {
                if let Some(next_seq) = next_boundary_seq {
                    if let Some(group) =
                        summarize_work_group(&work, Some(entry.event.seq), Some(next_seq), false)
                    {
                        items.push(group);
                    }
                } else if is_latest_page {
                    trailing_work = work;
                }
            }
        }
    }

    let oldest_boundary = entries_asc.first().map(|e| e.event.seq);
    let last_boundary = entries_asc.last().map(|e| e.event.seq);
    Ok((items, oldest_boundary, last_boundary, trailing_work))
}

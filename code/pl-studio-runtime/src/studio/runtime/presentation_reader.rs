//! Bounded display-head selection. The original reader owns qualification and I/O.
//!
//! Inputs are already indexed newest-first by the presentation owner or display tables;
//! these helpers never enumerate atomic completion history or load member bodies.

use super::{
    ConversationReader,
    conversation_reader::{PresentationTokens, ReadObservation, cancelled, resync},
    presentation_feed::history_batch,
};
use crate::studio::thread_projection::presentation::{BlockOrder, DisplayHeader, display_upper};
use anyhow::{Result, ensure};
use pl_core::chat::ChatError;
use pl_protocol::DisplayBlockState;
use pl_protocol::{
    ChatPlacement, DisplayBlock, DisplayBlockRef, DisplayMemberHead, DisplayMemberPage,
    DisplayMemberWindow, LiveDisplayBlock, LiveDisplayWindow, ReadDemand, TimelineBatch,
};
use serde::Serialize;
use std::sync::Arc;

#[derive(Clone)]
pub(super) struct DisplayReadCut {
    pub published: u64,
    pub last_order: u64,
    pub resident_block_floor: Option<BlockOrder>,
    pub revision: u64,
    pub layout_revision: u64,
    pub execution_present: bool,
    pub current_work_id: Option<String>,
    pub open: Vec<Arc<DisplayHeader>>,
    pub history: Vec<Arc<DisplayHeader>>,
    // The requested bounded history page was selected in the cold metadata transaction.
    history_from_snapshot: bool,
}

impl ConversationReader {
    /// The resource permit belongs to the original lease. No stream or credit lock is involved.
    pub(super) async fn capture_display(
        &self,
        live_before: Option<u64>,
        live_limit: usize,
        history_after: Option<u64>,
        history_limit: usize,
    ) -> Result<DisplayReadCut> {
        display_upper(i64::MAX as u64, live_before)?;
        let permit = self.resources().await?;
        let resources = permit.as_ref().ok_or_else(cancelled)?;
        use crate::studio::conversation_store::{ReadCut, ReadRequest};
        let mut cold_page = false;
        let mut cut = match resources
            .conversation
            .capture(ReadRequest::Display {
                before: live_before,
                limit: live_limit,
                after: history_after,
                history_limit,
            })
            .await?
        {
            ReadCut::Ready {
                source,
                display: Some(cut),
                ..
            } => DisplayReadCut {
                published: cut.published,
                last_order: cut.last_order,
                resident_block_floor: cut.resident_block_floor,
                revision: cut.revision,
                layout_revision: cut.layout_revision,
                execution_present: source.current.projection().execution_present,
                current_work_id: live_before
                    .is_none()
                    .then_some(cut.current_work_id)
                    .flatten(),
                open: cut.open,
                history: cut.history,
                history_from_snapshot: false,
            },
            ReadCut::Cold(Some(snapshot)) => {
                cold_page = true;
                let stored = snapshot
                    .display_cut(
                        resources.database_id.as_deref().ok_or_else(resync)?,
                        live_before,
                        live_limit,
                        history_after,
                        history_limit,
                    )
                    .await?;
                DisplayReadCut {
                    published: stored.published,
                    last_order: stored.last_order,
                    resident_block_floor: None,
                    revision: stored.effect,
                    layout_revision: stored.effect,
                    execution_present: false,
                    current_work_id: stored.current_work_id,
                    open: stored.open,
                    history: stored.history,
                    history_from_snapshot: true,
                }
            }
            ReadCut::Cold(None) => DisplayReadCut {
                published: 0,
                last_order: 0,
                resident_block_floor: Some(BlockOrder::new(1)?),
                revision: 0,
                layout_revision: 0,
                execution_present: false,
                current_work_id: None,
                open: Vec::new(),
                history: Vec::new(),
                history_from_snapshot: true,
            },
            ReadCut::Ready { .. } => unreachable!("display request captures its display cut"),
        };
        self.ensure()?;
        ensure!(cut.published <= cut.last_order, resync());
        let upper = cut
            .last_order
            .min(display_upper(cut.last_order, live_before)?);
        if !cold_page && cut.published < upper && live_limit > 0 {
            let keys = cut
                .open
                .iter()
                .map(|h| h.block_order.get())
                .collect::<Vec<_>>();
            if !crate::studio::thread_projection::presentation::covered_desc(
                cut.resident_block_floor.map(BlockOrder::get),
                cut.published,
                &keys,
                live_limit,
            ) {
                let saved = resources
                    .history
                    .display_block_page(
                        resources.database_id.as_deref().ok_or_else(resync)?,
                        cut.published,
                        upper,
                        live_limit,
                        false,
                    )
                    .await?;
                cut.open = merge_headers(saved, cut.open, cut.published, upper, live_limit, false);
            }
        }
        Ok(cut)
    }

    pub(super) fn cut_live(
        &self,
        cut: &DisplayReadCut,
        demand: ReadDemand,
        tokens: &PresentationTokens,
    ) -> Result<LiveDisplayWindow> {
        let heads = cut
            .open
            .iter()
            .map(|header| LiveDisplayBlock {
                id: header.id.clone(),
                block_order: header.block_order.get(),
                source: Some(header.source.clone()),
                body: header.body.clone(),
                has_unfinished_members: header.unfinished > 0,
                thinking_summary: header.thinking_summary.clone(),
                state: if header.sealed {
                    DisplayBlockState::Sealed
                } else {
                    DisplayBlockState::Open
                },
            })
            .collect::<Vec<_>>();
        live_window(
            cut.revision,
            cut.published,
            cut.execution_present,
            cut.current_work_id.clone(),
            heads.iter().rev(),
            demand,
            |boundary| tokens.live_before(cut.layout_revision, boundary),
        )
    }

    /// SQLite and RAM use exactly the same key range. Captured versions always win.
    pub(super) async fn history_heads(
        &self,
        cut: &DisplayReadCut,
        ceiling: u64,
        before: Option<u64>,
        limit: usize,
    ) -> Result<Vec<DisplayBlock>> {
        let upper = display_upper(ceiling, before)?;
        let heads = self
            .merge_display_history(cut, 0, upper, limit, false)
            .await?;
        heads
            .into_iter()
            .map(|h| h.frozen().ok_or_else(resync))
            .collect()
    }

    async fn merge_display_history(
        &self,
        cut: &DisplayReadCut,
        lower: u64,
        upper: u64,
        limit: usize,
        ascending: bool,
    ) -> Result<Vec<Arc<DisplayHeader>>> {
        if lower >= upper || limit == 0 {
            return Ok(Vec::new());
        }
        let overlay = cut
            .history
            .iter()
            .filter(|h| h.block_order.get() > lower && h.block_order.get() <= upper)
            .cloned()
            .collect::<Vec<_>>();
        let keys = overlay
            .iter()
            .map(|h| h.block_order.get())
            .collect::<Vec<_>>();
        let complete = if ascending {
            cut.resident_block_floor
                .is_some_and(|floor| lower >= floor.get() - 1)
        } else {
            crate::studio::thread_projection::presentation::covered_desc(
                cut.resident_block_floor.map(BlockOrder::get),
                lower,
                &keys,
                limit,
            )
        };
        let saved = if cut.history_from_snapshot || complete {
            Vec::new()
        } else {
            let permit = self.resources().await?;
            let resources = permit.as_ref().ok_or_else(cancelled)?;
            resources
                .history
                .display_block_page(
                    resources.database_id.as_deref().ok_or_else(resync)?,
                    lower,
                    upper,
                    limit,
                    ascending,
                )
                .await?
        };
        self.ensure()?;
        Ok(merge_headers(
            saved, overlay, lower, upper, limit, ascending,
        ))
    }

    fn pack_history(
        &self,
        placement: ChatPlacement,
        mut heads: Vec<DisplayBlock>,
        ceiling: u64,
        live: Option<LiveDisplayWindow>,
        demand: ReadDemand,
        tokens: &PresentationTokens,
    ) -> Result<TimelineBatch> {
        let sizes = heads.iter().map(encoded_size).collect::<Result<Vec<_>>>()?;
        let mut bytes = sizes.iter().sum::<usize>();
        let mut start = 0;
        let live_bytes = live.as_ref().map(encoded_size).transpose()?.unwrap_or(4) - 4;
        loop {
            let before = heads
                .get(start)
                .filter(|head| head.block_order > 1)
                .map(|head| tokens.before(ceiling, head.block_order))
                .transpose()?;
            let envelope = TimelineBatch {
                presentation_version: pl_protocol::PRESENTATION_VERSION,
                placement,
                blocks: Vec::new(),
                before: before.clone(),
                from_order: None,
                through_order: ceiling,
                live: None,
            };
            let count = heads.len() - start;
            if fits(demand, encoded_size(&envelope)? + live_bytes, bytes, count) {
                heads.drain(..start);
                let batch = history_batch(placement, heads, before, ceiling, live, demand)?;
                self.ensure()?;
                return Ok(batch);
            }
            ensure!(count > 1, too_small());
            bytes -= sizes[start];
            start += 1;
        }
    }

    pub(super) async fn initial_timeline(&self, demand: ReadDemand) -> Result<TimelineBatch> {
        demand.validate(1)?;
        let n = demand.max_items as usize;
        let cut = self.capture_display(None, n, None, n).await?;
        self.bind_presentation_ceiling(cut.published)?;
        let tokens = self.presentation_tokens().await?;
        let heads = self.history_heads(&cut, cut.published, None, n).await?;
        // Reserve the exact Set envelope and one newest historical head before selecting live.
        let reserve = TimelineBatch {
            presentation_version: pl_protocol::PRESENTATION_VERSION,
            placement: ChatPlacement::Set,
            blocks: heads.last().cloned().into_iter().collect(),
            before: heads
                .last()
                .filter(|h| h.block_order > 1)
                .map(|h| tokens.before(cut.published, h.block_order))
                .transpose()?,
            from_order: None,
            through_order: cut.published,
            live: None,
        };
        let bytes = (demand.max_bytes as usize)
            .checked_sub(encoded_size(&reserve)?.saturating_sub(4))
            .ok_or_else(too_small)?;
        let live = self.cut_live(
            &cut,
            ReadDemand {
                max_bytes: bytes as u32,
                ..demand
            },
            &tokens,
        )?;
        self.pack_history(
            ChatPlacement::Set,
            heads,
            cut.published,
            Some(live),
            demand,
            &tokens,
        )
    }

    pub async fn load_timeline_older(
        &self,
        before: &str,
        demand: ReadDemand,
    ) -> Result<TimelineBatch> {
        demand.validate(1)?;
        let (ceiling, boundary) = self.display_boundary(before).await?;
        let n = demand.max_items as usize;
        let cut = self.capture_display(Some(boundary), 0, None, n).await?;
        let heads = self.history_heads(&cut, ceiling, Some(boundary), n).await?;
        let tokens = self.presentation_tokens().await?;
        self.pack_history(
            ChatPlacement::Prepend,
            heads,
            ceiling,
            None,
            demand,
            &tokens,
        )
    }

    pub async fn load_live_older(
        &self,
        before: &str,
        demand: ReadDemand,
    ) -> Result<LiveDisplayWindow> {
        demand.validate(1)?;
        let first = self.capture_display(None, 0, Some(u64::MAX), 0).await?;
        let boundary = self
            .live_display_boundary(before, first.layout_revision)
            .await?;
        let cut = self
            .capture_display(Some(boundary), demand.max_items as usize, Some(u64::MAX), 0)
            .await?;
        ensure!(
            cut.layout_revision == first.layout_revision,
            ChatError::StaleContent
        );
        let tokens = self.presentation_tokens().await?;
        let live = self.cut_live(&cut, demand, &tokens)?;
        self.ensure()?;
        Ok(live)
    }

    pub(super) async fn timeline_append_heads(
        &self,
        from: u64,
        through: u64,
        demand: ReadDemand,
    ) -> Result<Vec<DisplayBlock>> {
        demand.validate(1)?;
        let cut = self
            .capture_display(None, 0, Some(from), demand.max_items as usize)
            .await?;
        let heads = self
            .merge_display_history(&cut, from, through, demand.max_items as usize, true)
            .await?;
        heads
            .into_iter()
            .map(|h| h.frozen().ok_or_else(resync))
            .collect()
    }

    pub async fn open_display_members(
        &self,
        reference: DisplayBlockRef,
        window: DisplayMemberWindow,
        demand: ReadDemand,
    ) -> Result<DisplayMembers> {
        demand.validate(1)?;
        let permit = self.resources().await?;
        let resources = permit.as_ref().ok_or_else(cancelled)?;
        ensure!(
            resources.database_id.as_deref() == Some(reference.database_id.as_str()),
            ChatError::StaleContent
        );
        if let DisplayMemberWindow::Before { member_order } = window {
            ensure!(
                member_order > 0,
                ChatError::InvalidArgument("invalid member boundary".into())
            );
        }
        // Register before reading any header/page. Token wakes are filtered by the block revision.
        let changed = Some(resources.conversation.content_changes());
        Ok(DisplayMembers {
            observation: ReadObservation::new(self.clone(), changed),
            reference,
            window,
            demand,
            delivered: None,
            #[cfg(test)]
            cut_barrier: None,
        })
    }

    async fn display_member_page(
        &self,
        reference: &DisplayBlockRef,
        window: DisplayMemberWindow,
        demand: ReadDemand,
        fixed_snapshot: bool,
        delivered: Option<(u64, bool)>,
        #[cfg(test)] cut_barrier: &mut Option<DisplayMemberReadBarrier>,
    ) -> Result<Option<DisplayMemberPage>> {
        let permit = self.resources().await?;
        let resources = permit.as_ref().ok_or_else(cancelled)?;
        ensure!(
            resources.database_id.as_deref() == Some(reference.database_id.as_str()),
            ChatError::StaleContent
        );
        let before = match window {
            DisplayMemberWindow::Latest => None,
            DisplayMemberWindow::Before { member_order } => Some(member_order),
        };
        use crate::studio::conversation_store::{ReadCut, ReadRequest};
        let (hot, cold_snapshot) = match resources
            .conversation
            .capture(ReadRequest::Members {
                block: &reference.block_id,
                before,
                limit: demand.max_items as usize,
            })
            .await?
        {
            ReadCut::Ready { members, .. } => (members, None),
            ReadCut::Cold(snapshot) => (None, snapshot),
        };
        if hot.as_ref().is_some_and(|cut| {
            delivered == Some((cut.header.revision, fixed_snapshot || cut.header.sealed))
        }) {
            return Ok(None);
        }
        #[cfg(test)]
        if let Some(barrier) = cut_barrier.take() {
            // The owner lock is already released; retain the real cut while the test commits.
            ensure!(
                hot.as_ref().is_some_and(|cut| !cut.complete),
                "member-read barrier requires a sparse owner cut"
            );
            barrier
                .entered
                .send(())
                .map_err(|_| anyhow::anyhow!("member-read barrier observer dropped"))?;
            barrier
                .resume
                .await
                .map_err(|_| anyhow::anyhow!("member-read barrier released without resuming"))?;
        }
        let (header, mut members) = match hot {
            Some(cut) if cut.complete => (cut.header, cut.overlay),
            overlay => {
                // Rows which did not yet exist at this captured header cannot enter its window.
                // Previously terminal rows are immutable; every previously unfinished row is in
                // the resident overlay, which replaces any newer SQLite value at that identity.
                let saved_before = overlay
                    .as_ref()
                    .map(|cut| {
                        before
                            .unwrap_or(u64::MAX)
                            .min(cut.header.next_member.saturating_add(1))
                    })
                    .or(before);
                let saved = match cold_snapshot {
                    Some(snapshot) => {
                        snapshot
                            .display_member_page(
                                &reference.database_id,
                                &reference.block_id,
                                saved_before,
                                demand.max_items as usize,
                            )
                            .await?
                    }
                    None => {
                        resources
                            .history
                            .display_member_page(
                                &reference.database_id,
                                &reference.block_id,
                                saved_before,
                                demand.max_items as usize,
                                overlay.as_ref().map(|cut| cut.header.clone()),
                            )
                            .await?
                    }
                };
                match overlay {
                    Some(cut) => {
                        let mut members =
                            saved.entries.into_iter().map(Arc::new).collect::<Vec<_>>();
                        for member in cut.overlay {
                            match members.binary_search_by_key(&member.head.member_order, |m| {
                                m.head.member_order
                            }) {
                                Ok(index) => members[index] = member,
                                Err(index) => members.insert(index, member),
                            }
                        }
                        (cut.header, members)
                    }
                    None => (
                        saved.header,
                        saved.entries.into_iter().map(Arc::new).collect(),
                    ),
                }
            }
        };
        // A cold window is fixed by its original short read, without freezing the business block.
        let stamp = (header.revision, fixed_snapshot || header.sealed);
        if delivered == Some(stamp) {
            return Ok(None);
        }
        members.sort_by_key(|member| member.head.member_order);
        let page = member_page(
            reference.clone(),
            header.revision,
            stamp.1,
            window,
            members.iter().rev().map(|member| &member.head),
            demand,
        )?;
        self.ensure()?;
        Ok(Some(page))
    }
}

fn merge_headers(
    saved: Vec<Arc<DisplayHeader>>,
    overlay: Vec<Arc<DisplayHeader>>,
    lower: u64,
    upper: u64,
    limit: usize,
    ascending: bool,
) -> Vec<Arc<DisplayHeader>> {
    let mut rows = std::collections::BTreeMap::new();
    for header in saved.into_iter().chain(overlay) {
        if header.block_order.get() > lower && header.block_order.get() <= upper {
            rows.insert(header.block_order.get(), header);
        }
    }
    let mut result = if ascending {
        rows.into_values().take(limit).collect::<Vec<_>>()
    } else {
        rows.into_values().rev().take(limit).collect()
    };
    result.sort_by_key(|h| h.block_order.get());
    result
}

#[cfg(test)]
struct DisplayMemberReadBarrier {
    entered: tokio::sync::oneshot::Sender<()>,
    resume: tokio::sync::oneshot::Receiver<()>,
}

pub struct DisplayMembers {
    observation: ReadObservation,
    reference: DisplayBlockRef,
    window: DisplayMemberWindow,
    demand: ReadDemand,
    delivered: Option<(u64, bool)>,
    #[cfg(test)]
    cut_barrier: Option<DisplayMemberReadBarrier>,
}

impl DisplayMembers {
    pub fn cancellation_token(&self) -> tokio_util::sync::CancellationToken {
        self.observation.cancellation_token()
    }
    pub fn request_close(&self) {
        self.observation.request_close();
    }
    pub async fn close(&mut self) -> Result<()> {
        self.request_close();
        self.observation.seal();
        Ok(())
    }
    pub async fn next(&mut self) -> Result<Option<DisplayMemberPage>> {
        while self.observation.next().await? {
            let page = self
                .observation
                .query(self.observation.reader.display_member_page(
                    &self.reference,
                    self.window,
                    self.demand,
                    self.observation.is_fixed_snapshot(),
                    self.delivered,
                    #[cfg(test)]
                    &mut self.cut_barrier,
                ))
                .await?;
            if let Some(page) = page {
                self.delivered = Some((page.revision, page.sealed));
                if page.sealed {
                    self.observation.seal();
                }
                return Ok(Some(page));
            }
        }
        Ok(None)
    }
}

/// Count the actual wire representation without retaining a second encoded snapshot.
pub(super) fn encoded_size(value: &impl Serialize) -> Result<usize> {
    struct Counter(usize);
    impl std::io::Write for Counter {
        fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
            self.0 = self
                .0
                .checked_add(bytes.len())
                .ok_or_else(|| std::io::Error::other("display encoding length overflow"))?;
            Ok(bytes.len())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }
    let mut counter = Counter(0);
    serde_json::to_writer(&mut counter, value)?;
    Ok(counter.0)
}

fn fits(demand: ReadDemand, envelope: usize, entries: usize, count: usize) -> bool {
    count <= demand.max_items as usize
        && envelope
            .checked_add(entries)
            .and_then(|bytes| bytes.checked_add(count.saturating_sub(1)))
            .is_some_and(|bytes| bytes <= demand.max_bytes as usize)
}

fn too_small() -> anyhow::Error {
    ChatError::InvalidDemand(
        "display demand cannot fit one lightweight head and continuation".into(),
    )
    .into()
}

/// Select only the requested latest live heads; continuation is bound by the caller's reader.
/// `newest_first` must be a bounded range/index iterator, not a materialized full live list.
pub(super) fn live_window<'a>(
    revision: u64,
    ready_frontier: u64,
    execution_present: bool,
    current_work_id: Option<String>,
    newest_first: impl IntoIterator<Item = &'a LiveDisplayBlock>,
    demand: ReadDemand,
    mut continuation: impl FnMut(u64) -> Result<String>,
) -> Result<LiveDisplayWindow> {
    demand.validate(1)?;
    let mut result = LiveDisplayWindow {
        revision,
        ready_frontier,
        execution_present,
        current_work_id: current_work_id.clone(),
        blocks: Vec::new(),
        older: None,
    };
    let mut heads = newest_first.into_iter().peekable();
    let mut bytes = 0;
    let mut previous = u64::MAX;
    while let Some(head) = heads.next() {
        ensure!(
            head.block_order > 0 && head.block_order < previous,
            ChatError::Conflict("live display index is not strictly newest-first".into())
        );
        previous = head.block_order;
        let item_bytes = encoded_size(head)?;
        // Optimistically admit using the envelope without a continuation. A complete small list can
        // fit even when its intermediate continuation would be larger than the remaining heads.
        let envelope = LiveDisplayWindow {
            revision,
            ready_frontier,
            execution_present,
            current_work_id: current_work_id.clone(),
            blocks: Vec::new(),
            older: None,
        };
        if !fits(
            demand,
            encoded_size(&envelope)?,
            bytes + item_bytes,
            result.blocks.len() + 1,
        ) {
            ensure!(!result.blocks.is_empty(), too_small());
            result.older = Some(continuation(
                result
                    .blocks
                    .last()
                    .expect("nonempty bounded page")
                    .block_order,
            )?);
            break;
        }
        bytes += item_bytes;
        result.blocks.push(head.clone());
        result.older = if heads.peek().is_some()
            || (result.blocks.len() == demand.max_items as usize
                && head.block_order > ready_frontier.saturating_add(1))
        {
            Some(continuation(head.block_order)?)
        } else {
            None
        };
        if result.blocks.len() == demand.max_items as usize {
            break;
        }
    }
    loop {
        let envelope = LiveDisplayWindow {
            revision,
            ready_frontier,
            execution_present,
            current_work_id: current_work_id.clone(),
            blocks: Vec::new(),
            older: result.older.clone(),
        };
        if fits(demand, encoded_size(&envelope)?, bytes, result.blocks.len()) {
            break;
        }
        let removed = result.blocks.pop().ok_or_else(too_small)?;
        bytes -= encoded_size(&removed)?;
        let oldest = result.blocks.last().ok_or_else(too_small)?;
        result.older = Some(continuation(oldest.block_order)?);
    }
    result.blocks.reverse();
    ensure!(
        current_work_id
            .as_ref()
            .is_none_or(|id| result.blocks.iter().any(|block| {
                &block.id == id
                    && block.state == DisplayBlockState::Open
                    && matches!(block.body, pl_protocol::DisplayBlockBody::Work { .. })
            })),
        too_small()
    );
    ensure!(
        encoded_size(&result)? <= demand.max_bytes as usize,
        too_small()
    );
    Ok(result)
}

/// Select member metadata only. A range seek belongs to the original owner/storage adapter.
pub(super) fn member_page<'a>(
    block: DisplayBlockRef,
    revision: u64,
    sealed: bool,
    window: DisplayMemberWindow,
    newest_first: impl IntoIterator<Item = &'a DisplayMemberHead>,
    demand: ReadDemand,
) -> Result<DisplayMemberPage> {
    demand.validate(1)?;
    let boundary = match window {
        DisplayMemberWindow::Latest => u64::MAX,
        DisplayMemberWindow::Before { member_order } => {
            ensure!(
                member_order > 0,
                ChatError::InvalidArgument("member window boundary must be positive".into())
            );
            member_order
        }
    };
    let mut result = DisplayMemberPage {
        block,
        revision,
        sealed,
        entries: Vec::new(),
        before: None,
    };
    let mut heads = newest_first.into_iter().peekable();
    let mut bytes = 0;
    let mut previous = boundary;
    while let Some(head) = heads.next() {
        ensure!(
            head.member_order > 0 && head.member_order < previous,
            ChatError::Conflict("member index is outside the requested descending window".into())
        );
        previous = head.member_order;
        let item_bytes = encoded_size(head)?;
        let envelope = DisplayMemberPage {
            block: result.block.clone(),
            revision,
            sealed,
            entries: Vec::new(),
            before: None,
        };
        if !fits(
            demand,
            encoded_size(&envelope)?,
            bytes + item_bytes,
            result.entries.len() + 1,
        ) {
            ensure!(!result.entries.is_empty(), too_small());
            result.before = Some(
                result
                    .entries
                    .last()
                    .expect("nonempty bounded page")
                    .member_order,
            );
            break;
        }
        bytes += item_bytes;
        result.entries.push(head.clone());
        result.before = (heads.peek().is_some()
            || (result.entries.len() == demand.max_items as usize && head.member_order > 1))
            .then_some(head.member_order);
        if result.entries.len() == demand.max_items as usize {
            break;
        }
    }
    loop {
        let envelope = DisplayMemberPage {
            block: result.block.clone(),
            revision,
            sealed,
            entries: Vec::new(),
            before: result.before,
        };
        if fits(
            demand,
            encoded_size(&envelope)?,
            bytes,
            result.entries.len(),
        ) {
            break;
        }
        let removed = result.entries.pop().ok_or_else(too_small)?;
        bytes -= encoded_size(&removed)?;
        result.before = Some(result.entries.last().ok_or_else(too_small)?.member_order);
    }
    result.entries.reverse();
    ensure!(
        encoded_size(&result)? <= demand.max_bytes as usize,
        too_small()
    );
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::studio::runtime::conversation_reader::ReadObservation;
    use anyhow::Context as _;
    use futures::poll;
    use pl_protocol::{
        ChatAtom, ChatAtomKind, ChatAtomLifecycle, ChatDeliveryKind, ChatScope, ChatSourceId,
        ChatTerminalOutcome, DisplayBlockBody,
    };
    use std::task::Poll;
    use tokio::sync::watch;

    fn demand(max_items: u32) -> ReadDemand {
        ReadDemand {
            max_items,
            max_bytes: 16 * 1024,
        }
    }

    fn reference() -> DisplayBlockRef {
        DisplayBlockRef {
            database_id: "database".into(),
            block_id: "work".into(),
        }
    }

    fn head(order: u64) -> LiveDisplayBlock {
        LiveDisplayBlock {
            has_unfinished_members: false,
            thinking_summary: None,
            id: format!("block-{order}"),
            block_order: order,
            source: Some(ChatSourceId::ForegroundTurn {
                turn_id: "turn".into(),
            }),
            body: DisplayBlockBody::Work {
                timing: Default::default(),
                members: reference(),
            },
            state: pl_protocol::DisplayBlockState::Open,
        }
    }

    fn member(order: u64) -> DisplayMemberHead {
        let id = format!("member-{order}");
        DisplayMemberHead {
            member_key: id.clone(),
            member_order: order,
            record: pl_protocol::DisplayRecord {
                atom: ChatAtom {
                    id,
                    completion_item_id: None,
                    completion_seq: None,
                    source: ChatSourceId::ForegroundTurn {
                        turn_id: "turn".into(),
                    },
                    source_state: None,
                    source_order: Some(order),
                    kind: ChatAtomKind::ToolCall,
                    delivery: ChatDeliveryKind::Foreground,
                    lifecycle: ChatAtomLifecycle::Terminal {
                        started: None,
                        ended: None,
                        outcome: ChatTerminalOutcome::Cancelled,
                    },
                    turn_id: Some("turn".into()),
                    attempt_id: None,
                    tool: None,
                    wait: None,
                    text_channel: None,
                    started_at: None,
                    finished_at: None,
                    content_present: None,
                    contents: Vec::new(),
                    payload: None,
                },
                start_fact: None,
                end_fact: None,
                content_source: pl_protocol::DisplayContentSource::FrozenObservation {
                    captured_at: None,
                    available: true,
                },
            },
        }
    }

    #[test]
    fn live_pages_are_newest_first_selected_but_delivered_in_original_order() -> Result<()> {
        let heads: Vec<_> = (1..=5).map(head).collect();
        let page = live_window(
            10,
            4,
            true,
            None,
            heads.iter().rev(),
            demand(2),
            |boundary| Ok(format!("qualified:{boundary}")),
        )?;
        assert_eq!(
            page.blocks
                .iter()
                .map(|b| b.block_order)
                .collect::<Vec<_>>(),
            [4, 5]
        );
        assert_eq!(page.older.as_deref(), Some("qualified:4"));
        let next = live_window(
            10,
            4,
            true,
            None,
            heads.iter().rev().filter(|head| head.block_order < 4),
            demand(2),
            |boundary| Ok(format!("qualified:{boundary}")),
        )?;
        assert_eq!(
            next.blocks
                .iter()
                .map(|b| b.block_order)
                .collect::<Vec<_>>(),
            [2, 3]
        );
        assert_eq!(next.older.as_deref(), Some("qualified:2"));
        let last = live_window(
            10,
            4,
            true,
            None,
            heads[..1].iter().rev(),
            demand(1),
            |_| anyhow::bail!("a complete last page must not request a cursor"),
        )?;
        assert_eq!(last.blocks[0].block_order, 1);
        assert!(last.older.is_none());
        Ok(())
    }

    #[test]
    fn current_work_cannot_be_omitted_by_a_latest_window_item_or_byte_budget() -> Result<()> {
        let mut heads = [head(1), head(2)];
        heads[0].state = DisplayBlockState::Sealed;
        let latest = live_window(
            3,
            0,
            false,
            Some(heads[1].id.clone()),
            heads.iter().rev(),
            demand(1),
            |at| Ok(format!("before:{at}")),
        )?;
        assert_eq!(latest.current_work_id.as_deref(), Some("block-2"));
        assert_eq!(latest.blocks.len(), 1);
        assert_eq!(latest.blocks[0].id, "block-2");
        let bytes = encoded_size(&latest)? as u32;
        let too_small = ReadDemand {
            max_items: 1,
            max_bytes: bytes - 1,
        };
        assert!(
            live_window(
                3,
                0,
                false,
                Some(heads[1].id.clone()),
                heads.iter().rev(),
                too_small,
                |at| Ok(format!("before:{at}"))
            )
            .is_err()
        );
        assert!(
            live_window(
                3,
                0,
                false,
                Some(heads[0].id.clone()),
                heads.iter().rev(),
                demand(1),
                |at| Ok(format!("before:{at}"))
            )
            .is_err()
        );
        let older = live_window(
            3,
            0,
            false,
            None,
            heads[..1].iter().rev(),
            demand(1),
            |_| anyhow::bail!("complete old page"),
        )?;
        assert!(older.current_work_id.is_none());
        assert_eq!(older.blocks[0].id, "block-1");
        Ok(())
    }

    #[test]
    fn byte_budget_includes_utf8_and_continuation_without_rejecting_complete_small_list()
    -> Result<()> {
        let mut heads = [head(1), head(2)];
        heads[1].id = "显示头".repeat(40);
        let complete = live_window(1, 0, true, None, heads.iter().rev(), demand(2), |_| {
            Ok("cursor".repeat(1000))
        })?;
        let exact_bytes = encoded_size(&complete)? as u32;
        let exact = ReadDemand {
            max_items: 2,
            max_bytes: exact_bytes,
        };
        assert_eq!(
            live_window(1, 0, true, None, heads.iter().rev(), exact, |_| {
                Ok("cursor".repeat(1000))
            })?,
            complete
        );
        let undersized = ReadDemand {
            max_bytes: 1,
            ..exact
        };
        assert!(
            live_window(1, 0, true, None, heads.iter().rev(), undersized, |_| Ok(
                "c".into()
            ))
            .is_err()
        );
        // The JSON byte counter uses the same encoding as the transport, not character count.
        assert_eq!(
            encoded_size(&complete)?,
            serde_json::to_vec(&complete)?.len()
        );
        Ok(())
    }

    #[test]
    fn member_windows_preserve_stable_orders_and_real_terminal_without_body() -> Result<()> {
        let members: Vec<_> = (1..=5).map(member).collect();
        let page = member_page(
            reference(),
            8,
            false,
            DisplayMemberWindow::Latest,
            members.iter().rev(),
            demand(2),
        )?;
        assert_eq!(
            page.entries
                .iter()
                .map(|m| m.member_order)
                .collect::<Vec<_>>(),
            [4, 5]
        );
        assert_eq!(page.before, Some(4));
        assert!(!page.sealed);
        assert!(
            page.entries
                .iter()
                .all(|m| m.record.atom.completion_item_id.is_none())
        );
        assert!(page.entries.iter().all(|m| m.record.atom.payload.is_none()));
        let frozen = member_page(
            reference(),
            9,
            true,
            DisplayMemberWindow::Before { member_order: 4 },
            members[..3].iter().rev(),
            demand(2),
        )?;
        assert_eq!(
            frozen
                .entries
                .iter()
                .map(|m| m.member_order)
                .collect::<Vec<_>>(),
            [2, 3]
        );
        assert_eq!(frozen.before, Some(2));
        assert!(frozen.sealed);
        assert_eq!(frozen.block, page.block);
        assert!(
            member_page(
                reference(),
                9,
                true,
                DisplayMemberWindow::Before { member_order: 4 },
                members.iter().rev(),
                demand(2),
            )
            .is_err()
        );
        Ok(())
    }

    #[tokio::test]
    async fn v364_member_cut_survives_commit_confirm_cleanup_before_its_sqlite_read() -> Result<()>
    {
        use crate::{
            runtime_test_support::Environment,
            studio::runtime::conversation_feed::tests::completed_runs::{Harness, finish, start},
        };
        use anyhow::Context as _;
        use tokio::sync::oneshot;

        let env = Environment::new(vec![], vec![]).await?;
        let result = async {
        let mut h = Harness::new(&env).await?;
        let saved = h
            .effect(
                vec![start("saved-prefix", true)],
                vec![finish("saved-prefix", true, "durable prefix")?],
            )
            .await?;
        let saved_member = saved.display.as_ref().context("saved display")?.members[0]
            .head
            .clone();
        h.save(&saved).await?;
        h.projection.presentation().lock().unwrap().confirm(saved.sequence);
        drop(saved);

        let pending = h
            .effect(
                vec![start("terminal-overlay", true)],
                vec![finish("terminal-overlay", true, "pending terminal body")?],
            )
            .await?;
        let delta = pending.display.as_ref().context("pending display")?;
        let pending_member = delta.members[0].head.clone();
        let terminal_row = Arc::downgrade(&delta.members[0]);
        let original_payload = Arc::downgrade(&pending.completions[0].payload);
        let original_contents = Arc::downgrade(&pending.completions[0].contents);
        let reference = DisplayBlockRef {
            database_id: h.history.conversation_database_id().await?.context("database")?,
            block_id: delta.blocks[0].header.id.clone(),
        };
        let mut feed = env.runtime.open_timeline_feed(&h.thread.id, demand(1)).await?;
        let reader = feed.reader().clone();
        let cut = reader.capture_display(None, 1, None, 0).await?;
        assert_eq!((cut.published, cut.last_order), (0, 1));
        assert_eq!(h.session.durable_seq(), 1);
        assert_eq!(cut.current_work_id.as_deref(), Some(reference.block_id.as_str()));
        let captured_revision = cut.open[0].revision;
        let captured_head = Arc::downgrade(&cut.open[0]);
        assert!(matches!(
            &cut.open[0].body,
            DisplayBlockBody::Work { timing: summary, .. } if summary.finished_at.is_none()
        ));
        assert_eq!(
            h.projection.presentation().lock().unwrap().resident_member_count(),
            1,
            "saved prefix is sparse; only the unsaved terminal overlay is resident"
        );

        let mut members = reader
            .open_display_members(reference.clone(), DisplayMemberWindow::Latest, demand(2))
            .await?;
        let (entered, captured) = oneshot::channel();
        let (resume, released) = oneshot::channel();
        members.cut_barrier = Some(DisplayMemberReadBarrier { entered, resume: released });
        let old_page = {
            let reading = members.next();
            tokio::pin!(reading);
            tokio::time::timeout(crate::runtime_test_support::integration_test_deadline()?, async {
                tokio::select! {
                    reached = captured => reached.context("member cut was not reached"),
                    result = &mut reading => anyhow::bail!("member read completed before its cut barrier: {result:?}"),
                }
            })
            .await??;

            // The production writer COMMIT completes before either owner confirms or read resumes.
            h.save(&pending).await?;
            assert_eq!(h.session.durable_seq(), 2);
            h.projection.presentation().lock().unwrap().confirm(pending.sequence);
            drop(pending);
            assert_eq!(
                h.projection.presentation().lock().unwrap().resident_member_count(),
                0,
                "confirm releases the open tail's durable terminal row without waiting for the query"
            );
            assert_eq!(terminal_row.strong_count(), 1, "only the in-flight read cut owns this row");
            assert!(original_payload.upgrade().is_none(), "durable original payload is no longer resident");
            assert!(original_contents.upgrade().is_none(), "durable original bodies are no longer resident");

            // Advance the very same tail again. The paused read must not adopt this newer head/row.
            let newer = h
                .effect(
                    vec![start("after-cut", true)],
                    vec![finish("after-cut", true, "newer than the captured cut")?],
                )
                .await?;
            let newer_member = newer.display.as_ref().context("newer display")?.members[0]
                .head
                .clone();
            assert_eq!(newer.display.as_ref().unwrap().blocks[0].header.id, reference.block_id);
            h.save(&newer).await?;
            h.projection.presentation().lock().unwrap().confirm(newer.sequence);
            drop(newer);
            assert_eq!((cut.published, cut.last_order), (0, 1));
            assert!(matches!(
                &cut.open[0].body,
                DisplayBlockBody::Work { timing: summary, .. } if summary.finished_at.is_none()
            ));
            drop(cut);
            assert_eq!(captured_head.strong_count(), 1, "the actual query retains its captured head");
            resume.send(()).map_err(|_| anyhow::anyhow!("paused read dropped before release"))?;
            let old_page = tokio::time::timeout(
                crate::runtime_test_support::integration_test_deadline()?,
                reading,
            )
            .await??
            .context("captured member page")?;
            (old_page, newer_member)
        };
        let (old_page, newer_member) = old_page;
        assert_eq!(old_page.block, reference);
        assert_eq!(old_page.revision, captured_revision);
        assert!(!old_page.sealed);
        assert_eq!(old_page.entries, [saved_member.clone(), pending_member.clone()]);
        assert!(old_page.before.is_none());
        assert!(terminal_row.upgrade().is_none(), "completed query drops its last overlay reference");
        assert!(captured_head.upgrade().is_none(), "completed query drops its old header reference");
        members.close().await?;
        drop(members);

        let latest_cut = reader.capture_display(None, 1, None, 0).await?;
        assert_eq!(latest_cut.current_work_id.as_deref(), Some(reference.block_id.as_str()));
        assert!(matches!(
            &latest_cut.open[0].body,
            DisplayBlockBody::Work { timing: summary, .. } if summary.finished_at.is_none()
        ));
        assert!(!latest_cut.open[0].sealed);
        assert_eq!(
            h.projection.presentation().lock().unwrap().resident_member_count(),
            0
        );
        let mut latest = reader
            .open_display_members(reference.clone(), DisplayMemberWindow::Latest, demand(2))
            .await?;
        let newest = latest.next().await?.context("latest member page")?;
        assert_eq!(newest.revision, latest_cut.open[0].revision);
        assert!(newest.revision > captured_revision);
        assert_eq!(newest.entries, [pending_member, newer_member]);
        let mut older = reader
            .open_display_members(
                reference,
                DisplayMemberWindow::Before { member_order: newest.before.context("older prefix")? },
                demand(2),
            )
            .await?;
        let prefix = older.next().await?.context("saved prefix page")?;
        assert_eq!(prefix.entries, [saved_member]);
        assert!(prefix.before.is_none());
        assert_eq!(
            prefix.entries.iter().chain(&newest.entries)
                .map(|member| member.member_order).collect::<Vec<_>>(),
            [1, 2, 3],
            "the captured overlay's stable key/order is neither lost nor duplicated after cleanup"
        );
        older.close().await?;
        latest.close().await?;
        reader.close().await?;
        feed.close().await?;
        Ok::<_, anyhow::Error>(())
    }
    .await;
        env.finish(result).await
    }

    #[tokio::test]
    async fn display_cursors_and_observation_reuse_real_reader_qualification() -> Result<()> {
        use crate::runtime_test_support::Environment;
        let env = Environment::new(vec![], vec![]).await?;
        let result = async {
            let thread_a = env
                .runtime
                .create_thread(&env.project.id, "presentation A")
                .await?;
            let thread_b = env
                .runtime
                .create_thread(&env.project.id, "presentation B")
                .await?;
            let mut a1 = env
                .runtime
                .open_conversation_feed(&thread_a.id, ChatScope::Main, demand(1))
                .await?;
            let mut b = env
                .runtime
                .open_conversation_feed(&thread_b.id, ChatScope::Main, demand(1))
                .await?;
            a1.reader().bind_presentation_ceiling(12)?;
            b.reader().bind_presentation_ceiling(12)?;
            let tokens = a1.reader().presentation_tokens().await?;
            let history = tokens.before(12, 8)?;
            let live = tokens.live_before(3, 5)?;
            assert_eq!(a1.reader().display_boundary(&history).await?, (12, 8));
            assert_eq!(a1.reader().live_display_boundary(&live, 3).await?, 5);
            let stale = a1
                .reader()
                .live_display_boundary(&live, 4)
                .await
                .expect_err("structural revision must invalidate only live continuation");
            assert!(matches!(
                stale.downcast_ref::<ChatError>(),
                Some(ChatError::StaleContent)
            ));
            assert_eq!(a1.reader().display_boundary(&history).await?, (12, 8));
            assert!(b.reader().display_boundary(&history).await.is_err());
            assert!(a1.reader().display_boundary(&live).await.is_err());

            // Shared pull lifecycle: close wakes an already parked next without a receive/credit lock.
            let (changes, changed) = watch::channel(0);
            let mut observation = ReadObservation::new(a1.reader().clone(), Some(changed));
            assert!(observation.next().await?);
            let cancellation = observation.cancellation_token();
            {
                let waiting = observation.next();
                tokio::pin!(waiting);
                assert!(matches!(poll!(&mut waiting), Poll::Pending));
                cancellation.cancel();
                assert!(matches!(
                    waiting
                        .await
                        .expect_err("close must wake next")
                        .downcast_ref::<ChatError>(),
                    Some(ChatError::Cancelled)
                ));
            }
            // Closing this view does not retire the borrowed reader or its other windows.
            a1.reader().ensure()?;
            drop(observation);
            assert_eq!(changes.receiver_count(), 0);

            let (changes, changed) = watch::channel(0);
            let mut sealed = ReadObservation::new(a1.reader().clone(), Some(changed));
            assert!(!sealed.is_fixed_snapshot());
            assert!(sealed.next().await?);
            sealed.seal();
            assert!(
                !sealed.is_fixed_snapshot(),
                "closing a hot watch does not make it a cold snapshot"
            );
            assert_eq!(changes.receiver_count(), 0);
            assert!(!sealed.next().await?);

            let (changes, changed) = watch::channel(0);
            let mut interrupted = ReadObservation::new(a1.reader().clone(), Some(changed));
            assert!(interrupted.next().await?);
            drop(changes);
            let lost = interrupted
                .next()
                .await
                .expect_err("a hot watch cannot end as a successful fixed EOF");
            assert_eq!(
                lost.downcast_ref::<pl_protocol::studio::StudioError>()
                    .context("typed watch discontinuity")?
                    .reason(),
                Some(pl_protocol::studio::StudioErrorReason::ConversationResyncRequired.label())
            );
            assert!(!interrupted.is_fixed_snapshot());

            a1.reader().close().await?;
            let mut a2 = env
                .runtime
                .open_conversation_feed(&thread_a.id, ChatScope::Main, demand(1))
                .await?;
            a2.reader().bind_presentation_ceiling(12)?;
            assert!(a1.reader().display_boundary(&history).await.is_err());
            assert!(a2.reader().display_boundary(&history).await.is_err());
            let current = a2.reader().presentation_tokens().await?.before(12, 8)?;
            assert_eq!(a2.reader().display_boundary(&current).await?, (12, 8));
            a1.close().await?;
            b.close().await?;
            a2.reader().close().await?;
            a2.close().await?;
            Ok::<_, anyhow::Error>(())
        }
        .await;
        env.finish(result).await
    }
}

//! Bounded display-head selection. The original reader owns qualification and I/O.
//!
//! Inputs are already indexed newest-first by the presentation owner or display tables;
//! these helpers never enumerate atomic completion history or load member bodies.

use super::{
    ConversationReader,
    conversation_reader::{PresentationTokens, ReadObservation, cancelled, resync},
    presentation_feed::history_batch,
};
use crate::studio::thread_projection::presentation::DisplayHeader;
use anyhow::{Result, ensure};
use pl_core::chat::ChatError;
use pl_protocol::DisplayBlockState;
use pl_protocol::{
    ChatPlacement, DisplayBlock, DisplayBlockRef, DisplayMemberHead, DisplayMemberPage,
    DisplayMemberWindow, LiveDisplayBlock, LiveDisplayWindow, ReadDemand, TimelineBatch,
};
use serde::Serialize;
use std::sync::Arc;

#[cfg(test)]
mod tests;

pub(super) struct DisplayReadCut {
    pub published: u64,
    pub durable: u64,
    pub revision: u64,
    pub execution_present: bool,
    pub current_work_id: Option<String>,
    pub open: Vec<Arc<DisplayHeader>>,
    pub pending: Vec<Arc<DisplayBlock>>,
}

impl ConversationReader {
    /// The resource permit belongs to the original lease. No stream or credit lock is involved.
    pub(super) async fn capture_display(
        &self,
        live_before: Option<u64>,
        live_limit: usize,
        pending_after: Option<u64>,
        pending_limit: usize,
    ) -> Result<DisplayReadCut> {
        let permit = self.resources().await?;
        let resources = permit.as_ref().ok_or_else(cancelled)?;
        let cut = if let Some(source) = resources
            .source
            .as_ref()
            .and_then(|s| s.current_conversation())
        {
            let owner = source
                .presentation
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let boundary = pending_after.unwrap_or_else(|| {
                owner
                    .capture(None, 0, 0, 0)
                    .published
                    .saturating_sub(pending_limit as u64)
            });
            let cut = owner.capture(live_before, live_limit, boundary, pending_limit);
            DisplayReadCut {
                published: cut.published,
                durable: cut.durable,
                revision: cut.revision,
                execution_present: source.current.projection().execution_present,
                current_work_id: live_before
                    .is_none()
                    .then_some(cut.current_work_id)
                    .flatten(),
                open: cut.open,
                pending: cut.pending,
            }
        } else {
            match resources.database_id.as_deref() {
                Some(database) => {
                    let stored = resources
                        .history
                        .display_cut(database, live_before, live_limit)
                        .await?;
                    DisplayReadCut {
                        published: stored.published,
                        durable: stored.published,
                        revision: stored.effect,
                        execution_present: false,
                        current_work_id: stored.current_work_id,
                        open: stored.open,
                        pending: Vec::new(),
                    }
                }
                None => DisplayReadCut {
                    published: 0,
                    durable: 0,
                    revision: 0,
                    execution_present: false,
                    current_work_id: None,
                    open: Vec::new(),
                    pending: Vec::new(),
                },
            }
        };
        self.ensure()?;
        ensure!(cut.durable <= cut.published, resync());
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
                block_order: header.block_order,
                source: Some(header.source.clone()),
                body: header.body.clone(),
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
            |boundary| tokens.live_before(cut.revision, boundary),
        )
    }

    /// Fill only the captured durable prefix, using a new short SQLite snapshot after capture.
    async fn history_heads(
        &self,
        cut: &DisplayReadCut,
        ceiling: u64,
        before: Option<u64>,
        limit: usize,
    ) -> Result<Vec<DisplayBlock>> {
        let mut heads = cut
            .pending
            .iter()
            .filter(|head| {
                head.history_pos <= ceiling && before.is_none_or(|b| head.history_pos < b)
            })
            .rev()
            .take(limit)
            .map(|head| head.as_ref().clone())
            .collect::<Vec<_>>();
        heads.reverse();
        let durable_ceiling = cut.durable.min(ceiling);
        let durable_before = heads.first().map(|head| head.history_pos).or(before);
        if heads.len() < limit && durable_ceiling > 0 && durable_before.is_none_or(|b| b > 1) {
            let permit = self.resources().await?;
            let resources = permit.as_ref().ok_or_else(cancelled)?;
            let mut durable = resources
                .history
                .display_history_heads(
                    resources.database_id.as_deref().ok_or_else(resync)?,
                    0,
                    durable_ceiling,
                    durable_before,
                    limit - heads.len(),
                    false,
                )
                .await?
                .into_iter()
                .map(|head| head.as_ref().clone())
                .collect::<Vec<_>>();
            durable.append(&mut heads);
            heads = durable;
        }
        self.ensure()?;
        let expected_end = ceiling.min(before.map_or(u64::MAX, |before| before - 1));
        ensure!(
            heads.last().map(|head| head.history_pos).unwrap_or(0) == expected_end,
            resync()
        );
        for pair in heads.windows(2) {
            ensure!(
                pair[0].history_pos.checked_add(1) == Some(pair[1].history_pos),
                resync()
            );
        }
        Ok(heads)
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
                .filter(|head| head.history_pos > 1)
                .map(|head| tokens.before(ceiling, head.history_pos))
                .transpose()?;
            let envelope = TimelineBatch {
                presentation_version: pl_protocol::PRESENTATION_VERSION,
                placement,
                blocks: Vec::new(),
                before: before.clone(),
                from_pos: None,
                through_pos: ceiling,
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
        let cut = self.capture_display(None, n + 1, None, n + 1).await?;
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
                .filter(|h| h.history_pos > 1)
                .map(|h| tokens.before(cut.published, h.history_pos))
                .transpose()?,
            from_pos: None,
            through_pos: cut.published,
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
        let cut = self
            .capture_display(None, 0, Some(boundary.saturating_sub(n as u64 + 1)), n + 1)
            .await?;
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
        let boundary = self.live_display_boundary(before, first.revision).await?;
        let cut = self
            .capture_display(
                Some(boundary),
                demand.max_items as usize + 1,
                Some(u64::MAX),
                0,
            )
            .await?;
        ensure!(cut.revision == first.revision, ChatError::StaleContent);
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
        let ceiling = from
            .saturating_add(u64::from(demand.max_items))
            .min(through);
        let cut = self
            .capture_display(None, 0, Some(from), demand.max_items as usize)
            .await?;
        let mut heads = Vec::new();
        if from < cut.durable.min(ceiling) {
            let permit = self.resources().await?;
            let resources = permit.as_ref().ok_or_else(cancelled)?;
            heads = resources
                .history
                .display_history_heads(
                    resources.database_id.as_deref().ok_or_else(resync)?,
                    from,
                    cut.durable.min(ceiling),
                    None,
                    (cut.durable.min(ceiling) - from) as usize,
                    true,
                )
                .await?
                .into_iter()
                .map(|head| head.as_ref().clone())
                .collect();
        }
        heads.extend(
            cut.pending
                .into_iter()
                .filter(|head| head.history_pos > from && head.history_pos <= ceiling)
                .map(|head| head.as_ref().clone()),
        );
        self.ensure()?;
        Ok(heads)
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
        let changed = resources
            .source
            .as_ref()
            .and_then(|source| source.current_conversation())
            .map(|source| {
                source
                    .presentation
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .subscribe_members()
            });
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
        let hot = if let Some(source) = resources
            .source
            .as_ref()
            .and_then(|source| source.current_conversation())
        {
            let owner = source
                .presentation
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let header = owner.member_cut(&reference.block_id, before, 0);
            if header
                .as_ref()
                .is_some_and(|cut| delivered == Some((cut.header.revision, cut.header.sealed)))
            {
                return Ok(None);
            }
            owner.member_cut(&reference.block_id, before, demand.max_items as usize + 1)
        } else {
            None
        };
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
                let saved = resources
                    .history
                    .display_member_page(
                        &reference.database_id,
                        &reference.block_id,
                        saved_before,
                        demand.max_items as usize + 1,
                    )
                    .await?;
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
        let stamp = (header.revision, header.sealed);
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
    history_through: u64,
    execution_present: bool,
    current_work_id: Option<String>,
    newest_first: impl IntoIterator<Item = &'a LiveDisplayBlock>,
    demand: ReadDemand,
    mut continuation: impl FnMut(u64) -> Result<String>,
) -> Result<LiveDisplayWindow> {
    demand.validate(1)?;
    let mut result = LiveDisplayWindow {
        revision,
        history_through,
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
            history_through,
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
        result.older = heads
            .peek()
            .map(|_| continuation(head.block_order))
            .transpose()?;
        if result.blocks.len() == demand.max_items as usize {
            break;
        }
    }
    loop {
        let envelope = LiveDisplayWindow {
            revision,
            history_through,
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
        result.before = heads.peek().map(|_| head.member_order);
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

//! 统一读取：Latest/Before 完成页、订阅基线、内部 after 补发窗口与按身份详情。
//!
//! 三条读取能力都不拥有可见行、阅读位置或视口几何，也都不跨 `.await` 持有时间线锁。统一次序固定：
//!
//! 1. 同一短锁内捕获完成代际、上界 H 与范围内 `limit + 1` 条有界 pending 引用；
//! 2. 锁外开启一次新的短数据库读（端口契约），限制 `append_seq <= H`，不复用捕获前的旧快照；
//! 3. 再入短锁，把捕获引用、存储行与当前 pending 合并：按身份与序号校验、去重、排序；
//! 4. 预算与有界预览在所有锁之外计算。
//!
//! 提交/回收发生在捕获之后时，读取仍持有不可变引用；发生在捕获之前时，后开的数据库读已经能看见；
//! 两边命中只返回一项。读取不 flush、不触发 writer，也不克隆全部 pending。

use std::{collections::BTreeMap, sync::Arc};

use crate::chat::{
    ChatCompletionCursor, ChatCursor, ChatDetailChunk, ChatDetailCursor, ChatDetailRequest,
    ChatError, ChatItem, ChatPage, ChatPageRequest, MAX_PAGE_ITEMS, PAGE_PREVIEW_BYTES, Session,
    item::same_payload,
};

/// 单个补发批次最多交付的条目数；与单页上限一致。
const MAX_BATCH_ITEMS: usize = MAX_PAGE_ITEMS;

impl Session {
    /// Reads one stateless page: newest, or strictly older than `before`.
    ///
    /// The page is assembled from two bounded sources — the session's pending records, which hold
    /// completions that are visible but not necessarily durable yet, and one short keyset read of
    /// committed history limited to the captured head — and the two are merged and validated again
    /// under the timeline lock after the read. `has_older` only comes from a proven older identity
    /// (a dropped candidate or the store's existence check), never from a short page.
    ///
    /// # Errors
    /// [`ChatError::InvalidArgument`] for an unsupported limit, [`ChatError::EpochMismatch`] when
    /// `before` was minted by another run generation, [`ChatError::Conflict`] when the merged
    /// candidates disagree about one identity or one sequence, plus the host's own typed storage
    /// and preview failures.
    pub async fn page(&self, request: ChatPageRequest) -> Result<ChatPage, ChatError> {
        let limit = request.limit()?;
        if let Some(before) = &request.before {
            before.validate_epoch(&self.0.epoch)?;
        }
        self.ensure_initialized().await?;
        let before = request.before;
        // Step 1: capture the head and a bounded pending window for the requested range.
        let (head, captured) = self.with_timeline(|state| {
            let before_seq = before.as_ref().map_or(u64::MAX, |cursor| cursor.append_seq);
            (
                state.head,
                state.pending_window(0, before_seq, limit.saturating_add(1)),
            )
        });
        // Step 2: one fresh short storage read outside every lock.
        let stored = self.0.history.page(before.as_ref(), head, limit).await?;
        // The captured head and Arc records form this read's snapshot. Publications
        // after that head belong to the already-registered tail, never this page.
        let mut records = captured;
        records.extend(stored.items.into_iter().map(Arc::new));
        let candidates = merge_records(records)?;
        // Step 4: bound and select outside every lock; the host codec may refuse a budget.
        let bounded = self.bound_all(candidates)?;
        Ok(self.select_page(bounded, limit, stored.has_more, before.as_ref()))
    }

    /// Captures the latest small page as one consistent subscription baseline.
    ///
    /// This is the single builder of a tail baseline: the first frame of a subscription uses it, so a
    /// first frame can never present a memory-only tail as if it were the authoritative newest page.
    /// The shape is the shared page contract — newest [`DEFAULT_PAGE_ITEMS`] records inside the page
    /// preview budget, the real older boundary and a proven `has_older` — plus the completed cursor
    /// of the newest record.
    ///
    /// # Errors
    /// Same as [`Session::page`].
    pub(crate) async fn capture_latest_baseline(
        &self,
    ) -> Result<crate::chat::ChatTailBaseline, ChatError> {
        let page = self.page(ChatPageRequest::latest()).await?;
        let epoch = page.epoch.clone();
        Ok(crate::chat::ChatTailBaseline {
            epoch: page.epoch,
            completed_cursor: page
                .items
                .last()
                .map(|item| ChatCompletionCursor::new(epoch, item.append_seq)),
            items: page.items,
            before: page.before,
            has_older: page.has_older,
        })
    }

    /// Opens one bounded tail subscription over this session.
    ///
    /// The wake receiver is registered **before** the consistent baseline is captured, so nothing
    /// published while the capture awaits can be missed: a completion that lands during the read is
    /// either already inside the baseline page or still ahead of the baseline cursor, and the first
    /// wake delivers it. The registered receiver stays owned by this future until the tail takes
    /// it; a failed or cancelled capture drops it and releases demand without spawning background
    /// work.
    ///
    /// # Errors
    /// The host's own typed storage and preview failures, plus [`ChatError::Conflict`] when merged
    /// candidates disagree about one identity or sequence.
    pub async fn subscribe_tail(&self) -> Result<crate::chat::ChatTail, ChatError> {
        let watch = self.0.changed.subscribe();
        let baseline = self.capture_latest_baseline().await?;
        Ok(crate::chat::ChatTail::new(self.clone(), watch, baseline))
    }

    /// Resumes one bounded tail subscription from an already-delivered completion position.
    ///
    /// The wake receiver is registered before the state capture, so completions landing in between
    /// are delivered by the first batch. The subscription never captures the latest page as its
    /// baseline: it continues from `after` exactly — a reconnecting consumer is refilled from its
    /// own last accepted position, not skipped to the head. The one-shot
    /// [`ChatTail::initial`](crate::chat::ChatTail::initial) frame is a placeholder that echoes the
    /// resume cursor (empty items, no boundary, `completed_cursor = after`); the runtime consumes it
    /// and does not publish it to the presentation owner. A resume position is the accepted sequence,
    /// not a paging boundary, so it carries no synthetic item identity.
    ///
    /// # Errors
    /// [`ChatError::EpochMismatch`] when `after` was minted by another run generation,
    /// [`ChatError::InvalidArgument`] when `after` names a sequence beyond the published head, plus
    /// the host's own typed storage failures from the seed read.
    pub async fn subscribe_after(
        &self,
        after: ChatCompletionCursor,
    ) -> Result<crate::chat::ChatTail, ChatError> {
        if after.epoch != self.0.epoch {
            return Err(ChatError::EpochMismatch {
                cursor: after.epoch,
                session: self.0.epoch.clone(),
            });
        }
        let watch = self.0.changed.subscribe();
        self.ensure_initialized().await?;
        let head = self.with_timeline(|state| state.head);
        if after.append_seq > head {
            return Err(ChatError::InvalidArgument(format!(
                "resume position {} is beyond the published head {head}",
                after.append_seq
            )));
        }
        Ok(crate::chat::ChatTail::new(
            self.clone(),
            watch,
            crate::chat::ChatTailBaseline {
                epoch: self.0.epoch.clone(),
                items: Vec::new(),
                before: None,
                has_older: false,
                completed_cursor: Some(after),
            },
        ))
    }

    /// One bounded ascending window of the completions in `(after, head]`.
    ///
    /// This is the internal catch-up read behind a tail, independent of the public Latest/Before
    /// paging. When the range starts at or after the captured durable prefix the pending records
    /// already prove the whole window and no database read is opened; otherwise one fresh
    /// `page_after` read fills the committed part and the merge under the timeline lock adds the
    /// rest. The window is bounded by item count and page preview bytes from the newest end of the
    /// window, so a lagging consumer is refilled continuously instead of being skipped to the head.
    ///
    /// # Errors
    /// [`ChatError::Conflict`] when the merged candidates disagree about one identity or one
    /// sequence, plus the host's own typed storage and preview failures.
    pub(crate) async fn completed_after(
        &self,
        after_seq: u64,
    ) -> Result<(Vec<ChatItem>, u64), ChatError> {
        self.ensure_initialized().await?;
        let (head, durable, captured) = self.with_timeline(|state| {
            (
                state.head,
                state.durable,
                state.pending_after(after_seq, state.head, MAX_BATCH_ITEMS.saturating_add(1)),
            )
        });
        if head <= after_seq {
            return Ok((Vec::new(), after_seq));
        }
        if after_seq >= durable {
            // Everything in (after, head] is still pending; the memory window is complete.
            let merged = merge_records(captured)?;
            let bounded = self.bound_all(merged)?;
            return self.take_batch(bounded, after_seq);
        }
        let stored = self
            .0
            .history
            .page_after(after_seq, head, MAX_BATCH_ITEMS)
            .await?;
        let mut records = captured;
        records.extend(stored.items.into_iter().map(Arc::new));
        let candidates = merge_records(records)?;
        let bounded = self.bound_all(candidates)?;
        self.take_batch(bounded, after_seq)
    }

    /// Reads one bounded block of a field's complete body.
    ///
    /// A pending record is served from the session's own complete copy without any storage IO; a
    /// record the writer already confirmed is read once from history. Records are immutable, so
    /// there is no revision to go stale and no re-check after the await: whichever source answers
    /// carries the same sealed payload for that identity.
    ///
    /// A continuation is only valid for the item and field it was produced for: reusing a token from
    /// another field or identity is rejected instead of silently reading from a guessed offset.
    ///
    /// # Errors
    /// [`ChatError::InvalidArgument`] for an unsupported block size or an illegal continuation,
    /// [`ChatError::NotFound`] for an unknown item or field, and the host's own storage failures.
    pub async fn read_detail(
        &self,
        request: ChatDetailRequest,
    ) -> Result<ChatDetailChunk, ChatError> {
        let block_bytes = request.block_bytes()?;
        if let Some(cursor) = &request.continuation {
            cursor.validate(&request)?;
        }
        let offset = request
            .continuation
            .as_ref()
            .map_or(0, ChatDetailCursor::offset);
        if let Some(record) = self.with_timeline(|state| state.pending_record(&request.item_id)) {
            return detail_chunk(&record, &request, offset, block_bytes);
        }
        let stored = self
            .0
            .history
            .item(&request.item_id)
            .await?
            .ok_or_else(|| ChatError::NotFound(request.item_id.clone()))?;
        detail_chunk(&stored, &request, offset, block_bytes)
    }

    /// Bounds every record through the host codec, outside every lock.
    fn bound_all(&self, records: Vec<Arc<ChatItem>>) -> Result<Vec<ChatItem>, ChatError> {
        let mut bounded = Vec::with_capacity(records.len());
        for record in records {
            bounded.push(self.0.history.bounded(&record)?);
        }
        Ok(bounded)
    }

    /// Selects the returned page from ascending candidates that are already strictly older.
    fn select_page(
        &self,
        items: Vec<ChatItem>,
        limit: usize,
        proven_older: bool,
        before: Option<&ChatCursor>,
    ) -> ChatPage {
        let mut items = items;
        if let Some(before) = before {
            items.retain(|item| item.append_seq < before.append_seq);
        }
        let mut has_older = proven_older;
        let excess = items.len().saturating_sub(limit);
        if excess > 0 {
            items.drain(..excess);
            has_older = true;
        }
        // Page preview bytes are bounded from the newest end, so a page dropped by the budget still
        // reports a real next boundary instead of pretending the history ended.
        let mut used = 0usize;
        let mut keep = 0usize;
        for item in items.iter().rev() {
            let bytes = item.resident_bytes();
            if keep > 0 && used.saturating_add(bytes) > PAGE_PREVIEW_BYTES {
                break;
            }
            used = used.saturating_add(bytes);
            keep += 1;
        }
        if keep < items.len() {
            items.drain(..items.len() - keep);
            has_older = true;
        }
        let has_older = has_older && !items.is_empty();
        let before = if has_older {
            items
                .first()
                .map(|item| ChatCursor::of(&self.0.epoch, item))
        } else {
            None
        };
        ChatPage {
            epoch: self.0.epoch.clone(),
            items,
            before,
            has_older,
        }
    }

    /// Bounds one ascending catch-up window by item count and page bytes over its oldest prefix.
    ///
    /// The window continues an already-delivered position, so a budget cut keeps the oldest part and
    /// leaves the remainder for the next batch; the returned sequence names the record actually
    /// delivered last, never a position the caller did not receive.
    fn take_batch(
        &self,
        mut items: Vec<ChatItem>,
        after_seq: u64,
    ) -> Result<(Vec<ChatItem>, u64), ChatError> {
        items.retain(|item| item.append_seq > after_seq);
        if items.is_empty() {
            return Err(ChatError::Conflict(format!(
                "completion history ended before the captured head after {after_seq}"
            )));
        }
        let mut used = 0usize;
        let mut keep = 0usize;
        for item in items.iter().take(MAX_BATCH_ITEMS) {
            let expected = after_seq + keep as u64 + 1;
            if item.append_seq != expected {
                return Err(ChatError::Conflict(format!(
                    "completion gap after {after_seq}: expected {expected}, found {}",
                    item.append_seq
                )));
            }
            let bytes = item.resident_bytes();
            if keep > 0 && used.saturating_add(bytes) > PAGE_PREVIEW_BYTES {
                break;
            }
            used = used.saturating_add(bytes);
            keep += 1;
        }
        if keep < items.len() {
            items.truncate(keep);
        }
        if items.len() > MAX_BATCH_ITEMS {
            items.truncate(MAX_BATCH_ITEMS);
        }
        let through = items.last().map_or(after_seq, |item| item.append_seq);
        Ok((items, through))
    }
}

/// One block of a field's complete body, on a UTF-8 boundary.
fn detail_chunk(
    record: &ChatItem,
    request: &ChatDetailRequest,
    offset: u64,
    block_bytes: usize,
) -> Result<ChatDetailChunk, ChatError> {
    let Some(preview) = record.fields.get(&request.field) else {
        return Err(ChatError::NotFound(format!(
            "{}:{}",
            record.item_id, request.field
        )));
    };
    let total_bytes = preview.total_bytes;
    if offset > total_bytes {
        return Err(ChatError::InvalidArgument(format!(
            "continued offset {offset} exceeds the {total_bytes} bytes of {}:{}",
            record.item_id, request.field
        )));
    }
    let start = usize::try_from(offset).map_err(|_| {
        ChatError::InvalidArgument(format!(
            "continued offset {offset} does not fit this platform"
        ))
    })?;
    let (text, end) = preview.block.range(start, block_bytes).ok_or_else(|| {
        ChatError::InvalidArgument(format!(
            "continued offset {offset} is not a UTF-8 boundary of {}:{}",
            record.item_id, request.field
        ))
    })?;
    let continuation = (end < preview.block.len())
        .then(|| ChatDetailCursor::new(record.item_id.clone(), request.field.clone(), end as u64));
    Ok(ChatDetailChunk {
        item_id: record.item_id.clone(),
        field: request.field.clone(),
        text,
        total_bytes,
        continuation,
    })
}

/// Merges candidates from every source into one ordered, de-duplicated, validated list.
///
/// Records are immutable, so one identity appearing through both a captured pending reference and a
/// committed storage row must be the very same record: a duplicate is collapsed, while the same
/// identity or the same sequence carrying a different payload is a typed conflict rather than an
/// arbitrary winner.
fn merge_records(records: Vec<Arc<ChatItem>>) -> Result<Vec<Arc<ChatItem>>, ChatError> {
    let mut by_seq: BTreeMap<u64, Arc<ChatItem>> = BTreeMap::new();
    let mut by_id: BTreeMap<String, (u64, Arc<ChatItem>)> = BTreeMap::new();
    for record in records {
        if let Some((seq, existing)) = by_id.get(&record.item_id) {
            if *seq != record.append_seq || !same_payload(existing, &record) {
                return Err(ChatError::Conflict(record.item_id.clone()));
            }
            continue;
        }
        if let Some(existing) = by_seq.get(&record.append_seq) {
            if existing.item_id != record.item_id || !same_payload(existing, &record) {
                return Err(ChatError::Conflict(record.item_id.clone()));
            }
            continue;
        }
        by_id.insert(record.item_id.clone(), (record.append_seq, record.clone()));
        by_seq.insert(record.append_seq, record);
    }
    Ok(by_seq.into_values().collect())
}

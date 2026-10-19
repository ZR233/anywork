//! 内容读取：无状态页、有界尾部订阅的建立与按身份详情。
//!
//! 三条读取能力都不拥有可见行、阅读位置或视口几何，也都不跨 `.await` 持有时间线锁：
//!
//! 1. 锁内只捕获有界预览候选与版本水位；
//! 2. 存储读取在锁外完成；
//! 3. 提交前在同一次时间线临界区里把读取期间发布的新 revision、保存确认与终态事实合回候选；
//! 4. 通知只是唤醒信号，内容帧由订阅者相对自己的交付基线各算一次。

use crate::chat::{
    ChatCursor, ChatDetailChunk, ChatDetailCursor, ChatDetailRequest, ChatError, ChatItem,
    ChatPage, ChatPageRequest, ChatTail, ChatTailBaseline, DEFAULT_PAGE_ITEMS, PAGE_PREVIEW_BYTES,
    item::merge_items,
    session::{
        RECENT_BYTES, RECENT_ITEMS, Session, TimelineState, resident_item,
        unreadable_preview_boundary, withdrawals_since,
    },
};

impl Session {
    /// Reads one stateless page: newest, or strictly older than `before`.
    ///
    /// The page is assembled from two bounded sources — the session's preview cache, which holds
    /// facts that are not durable yet, and one short keyset read of durable history — and the two are
    /// merged again under the timeline lock after the read, so a revision, save acknowledgement or
    /// terminal fact published while the read awaited is never replaced by the older copy. `has_older`
    /// only comes from a proven older identity (a dropped candidate, a published preview frontier
    /// or the store's existence check), never from a short page. An unreadable preview cannot be
    /// crossed to return an older durable row as a sparse EOF.
    ///
    /// Candidate *references* are captured before the storage step, so the same commit also drops the
    /// ones the authority withdrew meanwhile: a released speculative preview must not come back through
    /// the reference that was captured while it was still live. Facts published *after* the withdrawal
    /// are unaffected: they enter through the current page candidates read after storage, so a new order
    /// admitted under the same identity is still returned normally.
    ///
    /// # Errors
    /// [`ChatError::InvalidArgument`] for an unsupported limit, [`ChatError::ReadInvalidated`] when the
    /// withdrawal window can no longer be proven (retry the read), plus the host's own typed storage
    /// and preview failures.
    pub async fn page(&self, request: ChatPageRequest) -> Result<ChatPage, ChatError> {
        let limit = request.limit()?;
        let before = request.before;
        let (since, memory, frontier) = self.with_timeline(|state| {
            let memory = page_candidates(state, before.as_ref());
            let frontier = unreadable_preview_boundary(state, &memory, before.as_ref());
            (state.version, memory, frontier)
        });
        let stored = self.0.history.page(before.as_ref(), limit).await?;
        let proven_older = stored.has_older;
        let (candidates, preview_gap) = self.with_timeline(|state| {
            let mut memory = memory;
            // Reconcile both captured references and the captured unreadable frontier;
            // neither can survive a withdrawal or an unprovable publication window.
            if !memory.is_empty() || frontier.is_some() {
                let withdrawn = withdrawals_since(state, since)?;
                if frontier
                    .as_ref()
                    .is_some_and(|boundary| withdrawn.contains(boundary.item_id.as_str()))
                {
                    return Err(ChatError::ReadInvalidated);
                }
                memory.retain(|item| !withdrawn.contains(item.item_id.as_str()));
            }
            readable_suffix(
                state,
                merge_items(
                    stored
                        .items
                        .into_iter()
                        .chain(page_candidates(state, before.as_ref()))
                        .chain(memory),
                ),
                before.as_ref(),
                frontier.as_ref().filter(|_| state.version != since),
            )
        })?;
        // Bounding is host codec work: it runs outside every lock and may refuse a preview budget.
        let mut bounded = Vec::with_capacity(candidates.len());
        for item in candidates {
            bounded.push(self.0.history.bounded(&item)?);
        }
        // Only the bounded previews enter the session's own cache: a page never makes the hot preview
        // tail resident with whole bodies, and a withdrawn identity is never seeded back.
        self.hydrate(since, &bounded)?;
        Ok(select_page(
            bounded,
            limit,
            proven_older || preview_gap,
            before.as_ref(),
        ))
    }

    /// Opens one bounded tail observation over this session.
    ///
    /// The observation is registered *before* the cold page is read, so nothing published while the
    /// read awaits can be missed. The baseline itself is captured by
    /// [`Session::capture_latest_baseline`], i.e. by the same consistent read a resynchronization
    /// uses, so a first frame and a later resync can never disagree about the newest page.
    ///
    /// # Errors
    /// The host's own typed storage and preview failures.
    pub async fn subscribe_tail(&self) -> Result<ChatTail, ChatError> {
        let watch = self.0.changed.subscribe();
        let baseline = self.capture_latest_baseline().await?;
        Ok(ChatTail::new(self.clone(), watch, baseline))
    }

    /// Captures the latest small page as one consistent baseline.
    ///
    /// This is the single builder of a tail baseline: the first frame of a connection and an explicit
    /// resynchronization both use it, so neither can present a memory-only tail as if it were the
    /// authoritative newest page. The shape is the shared page contract — newest
    /// [`DEFAULT_PAGE_ITEMS`] items inside the page preview budget, the real older boundary and a
    /// proven `has_older` — with the session version captured under the same critical section as the
    /// memory merge.
    ///
    /// Necessary references are captured before the storage read, the short keyset read happens
    /// outside every lock, and the result is reconciled with the facts published meanwhile — the newer
    /// revision, save and terminal facts *and* the identities the authority withdrew — before the
    /// version is committed. The version and the filtered items therefore come from one critical
    /// section: a baseline can never claim a version that already covers a removal while still listing
    /// the removed identity.
    ///
    /// # Errors
    /// [`ChatError::ReadInvalidated`] when the withdrawal window can no longer be proven (the caller
    /// retries the resynchronization), plus the host's own typed storage and preview failures.
    pub(crate) async fn capture_latest_baseline(&self) -> Result<ChatTailBaseline, ChatError> {
        let (since, memory, frontier) = self.with_timeline(|state| {
            let memory = page_candidates(state, None);
            let frontier = unreadable_preview_boundary(state, &memory, None);
            (state.version, memory, frontier)
        });
        let stored = self.0.history.page(None, DEFAULT_PAGE_ITEMS).await?;
        let proven_older = stored.has_older;
        let (version, candidates, preview_gap) = self.with_timeline(|state| {
            let mut memory = memory;
            if !memory.is_empty() || frontier.is_some() {
                let withdrawn = withdrawals_since(state, since)?;
                if frontier
                    .as_ref()
                    .is_some_and(|boundary| withdrawn.contains(boundary.item_id.as_str()))
                {
                    return Err(ChatError::ReadInvalidated);
                }
                memory.retain(|item| !withdrawn.contains(item.item_id.as_str()));
            }
            let (candidates, preview_gap) = readable_suffix(
                state,
                merge_items(
                    stored
                        .items
                        .into_iter()
                        .chain(page_candidates(state, None))
                        .chain(memory),
                ),
                None,
                frontier.as_ref().filter(|_| state.version != since),
            )?;
            Ok((state.version, candidates, preview_gap))
        })?;
        let mut bounded = Vec::with_capacity(candidates.len());
        for item in candidates {
            bounded.push(self.0.history.bounded(&item)?);
        }
        Ok(latest_baseline(
            version,
            bounded,
            proven_older || preview_gap,
        ))
    }

    /// Reads one bounded block of a field's complete body.
    ///
    /// In-flight content is served from the session's own complete copy; a durable item is read once
    /// from history. The block is taken from the shared [`ContentBlock`] by byte range, so neither the
    /// already-delivered prefix nor the remaining text is materialized first, and the returned cursor
    /// always points at a legal UTF-8 boundary.
    ///
    /// A storage read is only a source of *this* revision's bytes: after it returns, the session's
    /// current fact is checked again. If the identity moved to another revision — even to a bounded
    /// preview — or lost the field while the read awaited, the request fails as stale/missing instead
    /// of serving an older durable snapshot. An empty field and a removed field therefore stay
    /// distinguishable, and a cold row can never override newer authoritative content.
    ///
    /// A continuation is only valid for the item, field and revision it was produced for: reusing a
    /// token from another field, identity or revision is rejected instead of silently reading from a
    /// guessed offset.
    ///
    /// # Errors
    /// [`ChatError::InvalidArgument`] for an unsupported block size or an illegal continuation,
    /// [`ChatError::NotFound`] for an unknown item or field, [`ChatError::StaleRevision`] when the
    /// item's content version moved, and the host's own storage failures.
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
        let resident = self.with_timeline(|state| memory_item(state, &request.item_id));
        if let Some(item) = resident.filter(|item| item.field_is_complete(&request.field)) {
            return detail_chunk(&item, &request, offset, block_bytes);
        }
        let stored = self.0.history.item(&request.item_id).await?;
        // 读后同权威再核：await 期间发布的更高 revision 或字段移除优先于这条冷行。
        let current = self.with_timeline(|state| memory_item(state, &request.item_id));
        if let Some(current) = current {
            if current.revision != request.revision {
                return Err(ChatError::StaleRevision {
                    item_id: current.item_id.clone(),
                    field: request.field.clone(),
                    revision: request.revision,
                });
            }
            if !current.fields.contains_key(&request.field) {
                return Err(ChatError::NotFound(format!(
                    "{}:{}",
                    current.item_id, request.field
                )));
            }
        }
        let item = stored.ok_or_else(|| ChatError::NotFound(request.item_id.clone()))?;
        detail_chunk(&item, &request, offset, block_bytes)
    }
}

fn detail_chunk(
    item: &ChatItem,
    request: &ChatDetailRequest,
    offset: u64,
    block_bytes: usize,
) -> Result<ChatDetailChunk, ChatError> {
    if item.revision != request.revision {
        return Err(ChatError::StaleRevision {
            item_id: item.item_id.clone(),
            field: request.field.clone(),
            revision: request.revision,
        });
    }
    let Some(preview) = item.fields.get(&request.field) else {
        return Err(ChatError::NotFound(format!(
            "{}:{}",
            item.item_id, request.field
        )));
    };
    if !preview.is_complete() {
        // The complete body was not available for this field; a truncated preview must never be
        // served as if it were the whole text.
        return Err(ChatError::Overloaded(format!(
            "{}:{} is only available as a bounded preview",
            item.item_id, request.field
        )));
    }
    let total_bytes = preview.total_bytes;
    if offset > total_bytes {
        return Err(ChatError::InvalidArgument(format!(
            "continued offset {offset} exceeds the {total_bytes} bytes of {}:{}",
            item.item_id, request.field
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
            item.item_id, request.field
        ))
    })?;
    let continuation = (end < preview.block.len()).then(|| {
        ChatDetailCursor::new(
            item.item_id.clone(),
            request.field.clone(),
            item.revision,
            end as u64,
        )
    });
    Ok(ChatDetailChunk {
        item_id: item.item_id.clone(),
        field: request.field.clone(),
        revision: item.revision,
        text,
        total_bytes,
        continuation,
    })
}

/// 由一次一致读取得到的最新小页基线。
///
/// 它复用同一份页契约（[`DEFAULT_PAGE_ITEMS`] 条上限、[`PAGE_PREVIEW_BYTES`] 页预览预算、真实边界与
/// 真实 `has_older`），因此大条目时实际条数可以少于 32，但边界与 `has_older` 一定来自真实事实：
/// `proven_older` 来自存储或已发布预览身份的存在性证明；截断到小页同样证明更旧内容存在，
/// 条数本身从不被当作 EOF。
pub(crate) fn latest_baseline(
    version: u64,
    items: Vec<ChatItem>,
    proven_older: bool,
) -> ChatTailBaseline {
    let page = select_page(items, DEFAULT_PAGE_ITEMS, proven_older, None);
    ChatTailBaseline {
        version,
        items: page.items,
        before: page.before,
        has_older: page.has_older,
    }
}

/// A readable suffix cannot cross a published preview whose body left the hot
/// cache before reliable ownership. The missing identity proves older content;
/// if there is no readable suffix, retry instead of reporting a sparse EOF.
fn readable_suffix(
    state: &TimelineState,
    mut candidates: Vec<ChatItem>,
    before: Option<&ChatCursor>,
    captured_frontier: Option<&ChatCursor>,
) -> Result<(Vec<ChatItem>, bool), ChatError> {
    // Reliable admission can release the speculative reservation while SQL is
    // awaiting. That does not make its body part of this read's older snapshot.
    let boundary = unreadable_preview_boundary(state, &candidates, before)
        .into_iter()
        .chain(captured_frontier.cloned())
        .max();
    let Some(boundary) = boundary else {
        return Ok((candidates, false));
    };
    candidates.retain(|item| ChatCursor::of(item) > boundary);
    if candidates.is_empty() {
        return Err(ChatError::ReadInvalidated);
    }
    Ok((candidates, true))
}

/// One page of the session's preview cache, ordered by `(order, identity)`.
pub(crate) fn page_candidates(state: &TimelineState, before: Option<&ChatCursor>) -> Vec<ChatItem> {
    let mut items = merge_items(
        state
            .recent
            .iter()
            .cloned()
            .chain(state.unsaved_previews.values().cloned()),
    );
    if let Some(before) = before {
        items.retain(|item| ChatCursor::of(item) < *before);
    }
    items
}

/// The session's bounded hot preview tail: at most [`RECENT_ITEMS`] newest preview items and
/// [`RECENT_BYTES`] of preview bytes.
pub(crate) fn tail_candidates(state: &TimelineState) -> Vec<ChatItem> {
    let mut items = page_candidates(state, None);
    let mut used = 0usize;
    let mut keep = 0usize;
    for item in items.iter().rev() {
        let bytes = item.resident_bytes();
        if keep == RECENT_ITEMS || used.saturating_add(bytes) > RECENT_BYTES {
            break;
        }
        used = used.saturating_add(bytes);
        keep += 1;
    }
    if keep < items.len() {
        items.drain(..items.len() - keep);
    }
    items
}

/// Selects the returned page from ascending candidates that are already strictly older.
fn select_page(
    items: Vec<ChatItem>,
    limit: usize,
    proven_older: bool,
    before: Option<&ChatCursor>,
) -> ChatPage {
    let mut items = items;
    if let Some(before) = before {
        items.retain(|item| ChatCursor::of(item) < *before);
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
        items.first().map(ChatCursor::of)
    } else {
        None
    };
    ChatPage {
        items,
        before,
        has_older,
    }
}

/// The complete in-memory copy of one identity, if the session still holds it.
pub(crate) fn memory_item(state: &TimelineState, item_id: &str) -> Option<ChatItem> {
    resident_item(state, item_id).or_else(|| {
        state
            .recent
            .iter()
            .find(|item| item.item_id == item_id)
            .cloned()
    })
}

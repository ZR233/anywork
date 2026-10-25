//! Shared test environment for the public Timeline content API.
//!
//! The fakes only provide storage and a controllable read barrier; the merge, page selection,
//! continuity and detail rules under test stay in production code.
#![allow(dead_code)]

use std::{
    collections::BTreeMap,
    sync::{
        Arc, Mutex, OnceLock, Weak,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
};

use pl_core::{
    chat::{
        ChatCursor, ChatError, ChatField, ChatHistory, ChatHistoryPage, ChatItem, ChatLifecycle,
        Session, presentation_item_id, presentation_prefix,
    },
    model::ContentBlock,
};
use tokio::sync::Semaphore;

/// In-memory durable history: a keyset store keyed by order.
#[derive(Debug, Default)]
pub struct Stored {
    pub items: BTreeMap<u64, ChatItem>,
}

impl Stored {
    pub fn with(items: impl IntoIterator<Item = ChatItem>) -> Self {
        let mut stored = Self::default();
        for item in items {
            stored.insert(item);
        }
        stored
    }

    pub fn insert(&mut self, item: ChatItem) {
        self.items.insert(item.order, item);
    }
}

impl ChatHistory for Stored {
    async fn latest_allocated_order(&self) -> Result<u64, ChatError> {
        Ok(self.items.keys().next_back().copied().unwrap_or(0))
    }

    async fn page(
        &self,
        before: Option<&ChatCursor>,
        limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        let mut selected: Vec<ChatItem> = self
            .items
            .values()
            .filter(|item| before.is_none_or(|boundary| ChatCursor::of(item) < *boundary))
            .rev()
            .take(limit + 1)
            .cloned()
            .collect();
        // `has_older` comes from the real extra row, never from the page being short.
        let has_older = selected.len() > limit;
        selected.truncate(limit);
        selected.reverse();
        Ok(ChatHistoryPage {
            items: selected,
            has_older,
        })
    }

    async fn item(&self, item_id: &str) -> Result<Option<ChatItem>, ChatError> {
        Ok(self
            .items
            .values()
            .find(|item| item.item_id == item_id)
            .cloned())
    }
}

/// A storage boundary that lets a producer publish while one public read awaits IO.
#[derive(Debug)]
pub struct HistoryGate {
    entered: Semaphore,
    release: Semaphore,
}

impl HistoryGate {
    pub fn new() -> Self {
        Self {
            entered: Semaphore::new(0),
            release: Semaphore::new(0),
        }
    }

    /// Waits until one read has actually entered the gated storage call.
    pub async fn entered(&self) {
        self.entered.acquire().await.unwrap().forget();
    }

    /// Lets the gated read continue.
    pub fn release(&self) {
        self.release.add_permits(1);
    }

    async fn pause(&self) {
        self.entered.add_permits(1);
        self.release.acquire().await.unwrap().forget();
    }
}

/// Storage whose page and item reads can be held open at a known point.
#[derive(Debug)]
pub struct GatedHistory {
    inner: Stored,
    pub page_gate: Option<Arc<HistoryGate>>,
    pub item_gate: Option<Arc<HistoryGate>>,
}

impl GatedHistory {
    pub fn new(inner: Stored) -> Self {
        Self {
            inner,
            page_gate: None,
            item_gate: None,
        }
    }
}

impl ChatHistory for GatedHistory {
    async fn latest_allocated_order(&self) -> Result<u64, ChatError> {
        self.inner.latest_allocated_order().await
    }

    async fn page(
        &self,
        before: Option<&ChatCursor>,
        limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        if let Some(gate) = &self.page_gate {
            gate.pause().await;
        }
        self.inner.page(before, limit).await
    }

    async fn item(&self, item_id: &str) -> Result<Option<ChatItem>, ChatError> {
        if let Some(gate) = &self.item_gate {
            gate.pause().await;
        }
        self.inner.item(item_id).await
    }
}

/// Counts complete-by-identity reads so a test can prove a detail read hits storage exactly once.
#[derive(Debug)]
pub struct Counting {
    inner: Stored,
    pub item_reads: Arc<AtomicUsize>,
    pub page_reads: Arc<AtomicUsize>,
}

impl Counting {
    pub fn new(inner: Stored) -> Self {
        Self {
            inner,
            item_reads: Arc::new(AtomicUsize::new(0)),
            page_reads: Arc::new(AtomicUsize::new(0)),
        }
    }
}

impl ChatHistory for Counting {
    async fn latest_allocated_order(&self) -> Result<u64, ChatError> {
        self.inner.latest_allocated_order().await
    }

    async fn page(
        &self,
        before: Option<&ChatCursor>,
        limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        self.page_reads.fetch_add(1, Ordering::Relaxed);
        self.inner.page(before, limit).await
    }

    async fn item(&self, item_id: &str) -> Result<Option<ChatItem>, ChatError> {
        self.item_reads.fetch_add(1, Ordering::Relaxed);
        // Yield so two concurrent callers genuinely interleave before either can cache a body.
        tokio::task::yield_now().await;
        self.inner.item(item_id).await
    }
}

/// Decodes a fresh large body per point read, remembering only a weak reference to the last body.
/// A metadata reader retaining full decoded items is detected at the next read, without measuring
/// allocator/RSS behavior or keeping the fixture's own copies of the large bodies.
#[derive(Debug)]
pub struct GeneratedBodies {
    pub item_reads: Arc<AtomicUsize>,
    pub last_body: Arc<Mutex<Weak<ContentBlock>>>,
    body_bytes: usize,
}

impl GeneratedBodies {
    pub fn new(body_bytes: usize) -> Self {
        Self {
            item_reads: Arc::new(AtomicUsize::new(0)),
            last_body: Arc::new(Mutex::new(Weak::new())),
            body_bytes,
        }
    }
}

impl ChatHistory for GeneratedBodies {
    async fn latest_allocated_order(&self) -> Result<u64, ChatError> {
        Ok(0)
    }

    async fn page(
        &self,
        _before: Option<&ChatCursor>,
        _limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        Err(ChatError::History(
            std::io::Error::other("unexpected history page scan").into(),
        ))
    }

    async fn item(&self, item_id: &str) -> Result<Option<ChatItem>, ChatError> {
        let mut last = self.last_body.lock().unwrap();
        if last.upgrade().is_some() {
            return Err(ChatError::History(
                std::io::Error::other("previous decoded body is still retained").into(),
            ));
        }
        let order = self.item_reads.fetch_add(1, Ordering::Relaxed) as u64 + 1;
        let item = identified(item_id, order, 7, &"x".repeat(self.body_bytes), true);
        *last = Arc::downgrade(item.body().unwrap());
        Ok(Some(item))
    }
}

/// Records the largest page a storage double was ever asked for, to prove bounded reads.
#[derive(Debug)]
pub struct BoundedReads {
    inner: Stored,
    pub largest_page: Arc<Mutex<usize>>,
}

impl BoundedReads {
    pub fn new(inner: Stored) -> Self {
        Self {
            inner,
            largest_page: Arc::new(Mutex::new(0)),
        }
    }
}

impl ChatHistory for BoundedReads {
    async fn latest_allocated_order(&self) -> Result<u64, ChatError> {
        self.inner.latest_allocated_order().await
    }

    async fn page(
        &self,
        before: Option<&ChatCursor>,
        limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        {
            let mut largest = self
                .largest_page
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            *largest = (*largest).max(limit);
        }
        self.inner.page(before, limit).await
    }

    async fn item(&self, item_id: &str) -> Result<Option<ChatItem>, ChatError> {
        self.inner.item(item_id).await
    }
}

/// A host codec that never bounds anything.
///
/// The shared single-item limit is checked on whatever a host returns, so an override like this must
/// still be reported as a resource limit instead of handing the session an oversized preview.
#[derive(Debug)]
pub struct IgnoresBudget {
    inner: Stored,
}

impl IgnoresBudget {
    pub fn new(inner: Stored) -> Self {
        Self { inner }
    }
}

impl ChatHistory for IgnoresBudget {
    fn bounded(&self, item: &ChatItem) -> Result<ChatItem, ChatError> {
        Ok(item.clone())
    }

    async fn latest_allocated_order(&self) -> Result<u64, ChatError> {
        self.inner.latest_allocated_order().await
    }

    async fn page(
        &self,
        before: Option<&ChatCursor>,
        limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        self.inner.page(before, limit).await
    }

    async fn item(&self, item_id: &str) -> Result<Option<ChatItem>, ChatError> {
        self.inner.item(item_id).await
    }
}

/// Storage whose host codec bounds every field preview to a small budget.
///
/// This is the documented host hook (`ChatHistory::bounded`), reduced so a test can observe a capped
/// preview while the original body keeps growing; the merge and continuity rules stay in production.
#[derive(Debug)]
pub struct Bounded {
    inner: Stored,
    cap: usize,
}

impl Bounded {
    pub fn new(inner: Stored, cap: usize) -> Self {
        Self { inner, cap }
    }
}

impl ChatHistory for Bounded {
    fn bounded(&self, item: &ChatItem) -> Result<ChatItem, ChatError> {
        let mut preview = item.clone();
        for value in preview.fields.values_mut() {
            let (block, _kept) = ContentBlock::prefix_at(&value.block, self.cap);
            value.block = block;
        }
        Ok(preview)
    }

    async fn latest_allocated_order(&self) -> Result<u64, ChatError> {
        self.inner.latest_allocated_order().await
    }

    async fn page(
        &self,
        before: Option<&ChatCursor>,
        limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        self.inner.page(before, limit).await
    }

    async fn item(&self, item_id: &str) -> Result<Option<ChatItem>, ChatError> {
        self.inner.item(item_id).await
    }
}

/// Storage that answers a bounded number of reads and then fails.
///
/// It proves a resynchronization capture is reported as a typed failure instead of a fake end of
/// content.
#[derive(Debug)]
pub struct FailAfter {
    inner: Stored,
    remaining: Arc<AtomicUsize>,
}

impl FailAfter {
    pub fn new(inner: Stored, successes: usize) -> Self {
        Self {
            inner,
            remaining: Arc::new(AtomicUsize::new(successes)),
        }
    }
}

impl ChatHistory for FailAfter {
    async fn latest_allocated_order(&self) -> Result<u64, ChatError> {
        self.inner.latest_allocated_order().await
    }

    async fn page(
        &self,
        before: Option<&ChatCursor>,
        limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        if self.remaining.load(Ordering::SeqCst) == 0 {
            return Err(ChatError::History(
                std::io::Error::other("unreadable timeline page").into(),
            ));
        }
        self.remaining.fetch_sub(1, Ordering::SeqCst);
        self.inner.page(before, limit).await
    }

    async fn item(&self, item_id: &str) -> Result<Option<ChatItem>, ChatError> {
        self.inner.item(item_id).await
    }
}

/// Storage whose next page read fails on demand and then reads normally again.
///
/// This is the capture boundary a resynchronization waits on: the observation must come out of a
/// failed capture exactly as it went in, and the retry of the very same range must be able to
/// succeed. A permanently failing store cannot show the second half of that.
#[derive(Debug)]
pub struct FailsOnce {
    inner: Stored,
    pub fail_next_page: Arc<AtomicBool>,
}

impl FailsOnce {
    pub fn new(inner: Stored) -> Self {
        Self {
            inner,
            fail_next_page: Arc::new(AtomicBool::new(false)),
        }
    }
}

impl ChatHistory for FailsOnce {
    async fn latest_allocated_order(&self) -> Result<u64, ChatError> {
        self.inner.latest_allocated_order().await
    }

    async fn page(
        &self,
        before: Option<&ChatCursor>,
        limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        if self.fail_next_page.swap(false, Ordering::SeqCst) {
            return Err(ChatError::History(
                std::io::Error::other("unreadable timeline page").into(),
            ));
        }
        self.inner.page(before, limit).await
    }

    async fn item(&self, item_id: &str) -> Result<Option<ChatItem>, ChatError> {
        self.inner.item(item_id).await
    }
}

/// Static metadata that carries no product structure.
pub fn empty_meta() -> Arc<[u8]> {
    static EMPTY: OnceLock<Arc<[u8]>> = OnceLock::new();
    EMPTY.get_or_init(|| Arc::from(b"{}".as_slice())).clone()
}

/// A complete item with one body field.
pub fn item(order: u64, revision: u64, text: &str, terminal: bool) -> ChatItem {
    identified(&format!("item-{order}"), order, revision, text, terminal)
}

/// A complete item with an explicit identity and one body field.
pub fn identified(
    item_id: &str,
    order: u64,
    revision: u64,
    text: &str,
    terminal: bool,
) -> ChatItem {
    let mut fields = BTreeMap::new();
    fields.insert(ChatField::Body, ContentBlock::from_text(text));
    ChatItem::complete(pl_core::chat::ChatItemParts {
        item_id: item_id.to_owned(),
        turn_id: "turn-1".to_owned(),
        order,
        revision,
        fields,
        meta: empty_meta(),
        saved: false,
        lifecycle: if terminal {
            ChatLifecycle::Terminal
        } else {
            ChatLifecycle::Streaming
        },
    })
}

/// A complete item with arbitrary field contents.
pub fn with_fields(
    item_id: &str,
    order: u64,
    revision: u64,
    fields: impl IntoIterator<Item = (ChatField, String)>,
    terminal: bool,
) -> ChatItem {
    let fields = fields
        .into_iter()
        .map(|(field, text)| (field, ContentBlock::from_text(&text)))
        .collect();
    ChatItem::complete(pl_core::chat::ChatItemParts {
        item_id: item_id.to_owned(),
        turn_id: "turn-1".to_owned(),
        order,
        revision,
        fields,
        meta: empty_meta(),
        saved: false,
        lifecycle: if terminal {
            ChatLifecycle::Terminal
        } else {
            ChatLifecycle::Streaming
        },
    })
}

/// The same identity with `delta` appended to its body along the shared block chain.
///
/// The append keeps the producer's block lineage, so a reader receives a typed append instead of an
/// authoritative replacement — exactly what a streamed revision looks like.
pub fn appended(previous: &ChatItem, revision: u64, delta: &str) -> ChatItem {
    let body = previous
        .body()
        .expect("the fixture item carries a body field");
    let block = ContentBlock::append(body, delta);
    let mut next = previous.clone();
    next.revision = revision;
    // A streamed revision is unacknowledged until the writer confirms exactly it.
    next.saved = false;
    next.fields.insert(
        ChatField::Body,
        pl_core::chat::ChatFieldPreview {
            total_bytes: block.len() as u64,
            block,
        },
    );
    next
}

/// The body text actually shown for one item.
pub fn body_text(item: &ChatItem) -> String {
    item.body().map_or_else(String::new, |block| block.text())
}

/// One attempt's streamed output identity.
pub fn presentation(attempt: &str, provider_item: &str) -> String {
    presentation_item_id(
        attempt,
        0,
        provider_item,
        Some(pl_core::chat::PresentationPart::OutputText(0)),
    )
}

/// One attempt's speculative prefix.
pub fn attempt_prefix(attempt: &str) -> String {
    presentation_prefix(attempt)
}

/// Takes the one-shot first frame off an observation.
pub fn take_initial(tail: &mut pl_core::chat::ChatTail) -> pl_core::chat::ChatTailBaseline {
    tail.initial()
        .expect("the observation hands its first frame over once")
}

/// A preview-only copy of `item`: each field keeps at most `keep` bytes plus its complete length.
///
/// This is what a host codec returns when the body does not fit the display budget, so a test can hold
/// an incomplete preview in memory without inventing a second content source.
pub fn preview_of(item: &ChatItem, keep: usize) -> ChatItem {
    let mut preview = item.clone();
    for value in preview.fields.values_mut() {
        let (block, _kept) = ContentBlock::prefix_at(&value.block, keep);
        value.block = block;
    }
    preview
}

/// A complete item that the writer already acknowledged.
pub fn saved_item(order: u64, revision: u64, text: &str, terminal: bool) -> ChatItem {
    let mut item = item(order, revision, text, terminal);
    item.saved = true;
    item
}

/// The session's current hot preview page, newest last.
pub async fn visible(session: &Session, limit: usize) -> Vec<ChatItem> {
    session
        .page(pl_core::chat::ChatPageRequest::latest().with_limit(limit))
        .await
        .expect("preview page is readable")
        .items
}

/// One visible item by identity.
pub async fn visible_item(session: &Session, item_id: &str) -> Option<ChatItem> {
    visible(session, 100)
        .await
        .into_iter()
        .find(|item| item.item_id == item_id)
}

//! Shared test environment for the public Timeline completion API.
//!
//! The fakes only provide storage and controllable read barriers; the admission, merge, page
//! selection, catch-up and detail rules under test stay in production code. `Stored` exposes a
//! writer-side handle so a test can land committed rows exactly like the real history writer does.
#![allow(dead_code)]

use std::{
    collections::BTreeMap,
    sync::{
        Arc, Mutex, OnceLock,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
};

use pl_core::{
    chat::{
        ChatCursor, ChatDraft, ChatError, ChatField, ChatHistory, ChatHistoryPage, ChatItem,
        ChatItemParts, Session, TimelineEpoch, presentation_item_id, presentation_prefix,
    },
    model::ContentBlock,
};
use tokio::sync::Semaphore;

/// In-memory durable history: a keyset store keyed by completion sequence.
#[derive(Debug, Clone, Default)]
pub struct Stored {
    map: Arc<Mutex<BTreeMap<u64, ChatItem>>>,
}

impl Stored {
    pub fn with(records: impl IntoIterator<Item = ChatItem>) -> Self {
        let stored = Self::default();
        for record in records {
            stored.insert(record);
        }
        stored
    }

    /// The writer-side landing of one committed record.
    pub fn insert(&self, record: ChatItem) {
        self.map
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .insert(record.append_seq, record);
    }

    pub fn len(&self) -> usize {
        self.map
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .len()
    }

    pub fn remove(&self, append_seq: u64) {
        self.map
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .remove(&append_seq);
    }

    pub fn by_id(&self, item_id: &str) -> Option<ChatItem> {
        self.map
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .values()
            .find(|record| record.item_id == item_id)
            .cloned()
    }

    fn rows(&self, keep: impl Fn(&ChatItem) -> bool) -> BTreeMap<u64, ChatItem> {
        self.map
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .values()
            .filter(|record| keep(record))
            .map(|record| (record.append_seq, record.clone()))
            .collect()
    }
}

impl ChatHistory for Stored {
    async fn latest_append_seq(&self) -> Result<u64, ChatError> {
        Ok(self
            .map
            .lock()
            .unwrap_or_else(|error| error.into_inner())
            .keys()
            .next_back()
            .copied()
            .unwrap_or(0))
    }

    async fn page(
        &self,
        before: Option<&ChatCursor>,
        ceiling: u64,
        limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        let mut selected: Vec<ChatItem> = self
            .rows(|record| {
                record.append_seq <= ceiling
                    && before.is_none_or(|boundary| record.append_seq < boundary.append_seq)
            })
            .into_values()
            .rev()
            .take(limit.saturating_add(1))
            .collect();
        // `has_more` comes from the real extra row, never from the page being short.
        let has_more = selected.len() > limit;
        selected.truncate(limit);
        selected.reverse();
        Ok(ChatHistoryPage {
            items: selected,
            has_more,
        })
    }

    async fn page_after(
        &self,
        after: u64,
        ceiling: u64,
        limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        let mut selected: Vec<ChatItem> = self
            .rows(|record| record.append_seq > after && record.append_seq <= ceiling)
            .into_values()
            .take(limit.saturating_add(1))
            .collect();
        let has_more = selected.len() > limit;
        selected.truncate(limit);
        Ok(ChatHistoryPage {
            items: selected,
            has_more,
        })
    }

    async fn item(&self, item_id: &str) -> Result<Option<ChatItem>, ChatError> {
        Ok(self.by_id(item_id))
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

/// Storage whose page, page_after and item reads can be held open at a known point.
#[derive(Debug, Clone)]
pub struct GatedHistory {
    inner: Stored,
    pub page_gate: Option<Arc<HistoryGate>>,
    pub after_gate: Option<Arc<HistoryGate>>,
    pub item_gate: Option<Arc<HistoryGate>>,
    pub captured_item_gate: Option<Arc<HistoryGate>>,
    capture_next_item: Arc<AtomicBool>,
}

impl GatedHistory {
    pub fn new(inner: Stored) -> Self {
        Self {
            inner,
            page_gate: None,
            after_gate: None,
            item_gate: None,
            captured_item_gate: None,
            capture_next_item: Arc::new(AtomicBool::new(true)),
        }
    }
}

impl ChatHistory for GatedHistory {
    async fn latest_append_seq(&self) -> Result<u64, ChatError> {
        self.inner.latest_append_seq().await
    }

    async fn page(
        &self,
        before: Option<&ChatCursor>,
        ceiling: u64,
        limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        if let Some(gate) = &self.page_gate {
            gate.pause().await;
        }
        self.inner.page(before, ceiling, limit).await
    }

    async fn page_after(
        &self,
        after: u64,
        ceiling: u64,
        limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        if let Some(gate) = &self.after_gate {
            gate.pause().await;
        }
        self.inner.page_after(after, ceiling, limit).await
    }

    async fn item(&self, item_id: &str) -> Result<Option<ChatItem>, ChatError> {
        if let Some(gate) = &self.captured_item_gate {
            let item = self.inner.item(item_id).await?;
            if self.capture_next_item.swap(false, Ordering::SeqCst) {
                gate.pause().await;
            }
            return Ok(item);
        }
        if let Some(gate) = &self.item_gate {
            gate.pause().await;
        }
        self.inner.item(item_id).await
    }
}

/// Counts complete-by-identity reads so a test can prove a detail read hits storage exactly once.
#[derive(Debug, Clone)]
pub struct Counting {
    inner: Stored,
    pub item_reads: Arc<AtomicUsize>,
}

impl Counting {
    pub fn new(inner: Stored) -> Self {
        Self {
            inner,
            item_reads: Arc::new(AtomicUsize::new(0)),
        }
    }
}

impl ChatHistory for Counting {
    async fn latest_append_seq(&self) -> Result<u64, ChatError> {
        self.inner.latest_append_seq().await
    }

    async fn page(
        &self,
        before: Option<&ChatCursor>,
        ceiling: u64,
        limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        self.inner.page(before, ceiling, limit).await
    }

    async fn page_after(
        &self,
        after: u64,
        ceiling: u64,
        limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        self.inner.page_after(after, ceiling, limit).await
    }

    async fn item(&self, item_id: &str) -> Result<Option<ChatItem>, ChatError> {
        self.item_reads.fetch_add(1, Ordering::Relaxed);
        // Yield so two concurrent callers genuinely interleave before either can cache a body.
        tokio::task::yield_now().await;
        self.inner.item(item_id).await
    }
}

/// Records the largest page and after-range a storage double was ever asked for, to prove bounded
/// reads.
#[derive(Debug, Clone)]
pub struct BoundedReads {
    inner: Stored,
    pub largest_page: Arc<Mutex<usize>>,
    pub largest_after: Arc<Mutex<usize>>,
}

impl BoundedReads {
    pub fn new(inner: Stored) -> Self {
        Self {
            inner,
            largest_page: Arc::new(Mutex::new(0)),
            largest_after: Arc::new(Mutex::new(0)),
        }
    }
}

impl ChatHistory for BoundedReads {
    async fn latest_append_seq(&self) -> Result<u64, ChatError> {
        self.inner.latest_append_seq().await
    }

    async fn page(
        &self,
        before: Option<&ChatCursor>,
        ceiling: u64,
        limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        {
            let mut largest = self
                .largest_page
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            *largest = (*largest).max(limit);
        }
        self.inner.page(before, ceiling, limit).await
    }

    async fn page_after(
        &self,
        after: u64,
        ceiling: u64,
        limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        {
            let mut largest = self
                .largest_after
                .lock()
                .unwrap_or_else(|error| error.into_inner());
            *largest = (*largest).max(limit);
        }
        self.inner.page_after(after, ceiling, limit).await
    }

    async fn item(&self, item_id: &str) -> Result<Option<ChatItem>, ChatError> {
        self.inner.item(item_id).await
    }
}

/// Fails the next page read once with a typed storage failure.
#[derive(Debug, Clone)]
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
    async fn latest_append_seq(&self) -> Result<u64, ChatError> {
        self.inner.latest_append_seq().await
    }

    async fn page(
        &self,
        before: Option<&ChatCursor>,
        ceiling: u64,
        limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        if self.fail_next_page.swap(false, Ordering::SeqCst) {
            return Err(ChatError::History(
                std::io::Error::other("unreadable timeline page").into(),
            ));
        }
        self.inner.page(before, ceiling, limit).await
    }

    async fn page_after(
        &self,
        after: u64,
        ceiling: u64,
        limit: usize,
    ) -> Result<ChatHistoryPage, ChatError> {
        self.inner.page_after(after, ceiling, limit).await
    }

    async fn item(&self, item_id: &str) -> Result<Option<ChatItem>, ChatError> {
        self.inner.item(item_id).await
    }
}

/// Static metadata that carries no product structure.
pub fn empty_meta() -> Arc<[u8]> {
    static EMPTY: OnceLock<Arc<[u8]>> = OnceLock::new();
    EMPTY.get_or_init(|| Arc::from(b"{}".to_vec())).clone()
}

/// One explicit, distinct run generation for a test session.
pub fn epoch(name: &str) -> TimelineEpoch {
    TimelineEpoch::new(name).expect("a test epoch is non-empty")
}

/// One complete completion draft with a body field.
pub fn draft(item_id: &str, text: &str) -> ChatDraft {
    ChatDraft::new(item_id)
        .with_meta(empty_meta())
        .with_text(ChatField::Body, text)
}

/// One complete completion draft with an explicit Turn binding.
pub fn draft_with_turn(item_id: &str, text: &str, turn_id: &str) -> ChatDraft {
    draft(item_id, text).with_turn_id(turn_id)
}

/// One complete completion draft with arbitrary field contents.
pub fn draft_with_fields(
    item_id: &str,
    fields: impl IntoIterator<Item = (ChatField, String)>,
) -> ChatDraft {
    let mut builder = ChatDraft::new(item_id).with_meta(empty_meta());
    for (field, text) in fields {
        builder = builder.with_text(field, &text);
    }
    builder
}

/// One complete sequenced record with a body field, as the store keeps it.
pub fn record(append_seq: u64, text: &str) -> ChatItem {
    record_identified(&format!("item-{append_seq}"), append_seq, text)
}

/// One complete sequenced record with an explicit identity, as the store keeps it.
pub fn record_identified(item_id: &str, append_seq: u64, text: &str) -> ChatItem {
    ChatItem::complete(ChatItemParts {
        item_id: item_id.to_owned(),
        turn_id: None,
        append_seq,
        source_effect_seq: None,
        sealed_at: None,
        fields: [(ChatField::Body, ContentBlock::from_text(text))].into(),
        meta: empty_meta(),
    })
}

/// One complete sequenced record with arbitrary field contents, as the store keeps it.
pub fn record_with_fields(
    item_id: &str,
    append_seq: u64,
    fields: impl IntoIterator<Item = (ChatField, String)>,
) -> ChatItem {
    let fields = fields
        .into_iter()
        .map(|(field, text)| (field, ContentBlock::from_text(&text)))
        .collect();
    ChatItem::complete(ChatItemParts {
        item_id: item_id.to_owned(),
        turn_id: None,
        append_seq,
        source_effect_seq: None,
        sealed_at: None,
        fields,
        meta: empty_meta(),
    })
}

/// The body text actually shown for one record.
pub fn body_text(record: &ChatItem) -> String {
    record.body().map_or_else(String::new, |block| block.text())
}

/// One attempt's completion identity.
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

/// Takes the one-shot first frame off a subscription.
pub fn take_initial(tail: &mut pl_core::chat::ChatTail) -> pl_core::chat::ChatTailBaseline {
    tail.initial()
        .expect("the subscription hands its first frame over once")
}

/// Publishes one batch, lands every returned record in the store and confirms the durable prefix,
/// exactly the sequence the real writer performs.
pub async fn publish_and_commit(
    session: &Session,
    stored: &Stored,
    batch: Vec<ChatDraft>,
) -> Arc<[Arc<ChatItem>]> {
    let records = session
        .publish_batch(batch)
        .await
        .expect("the completion batch is admitted");
    for published in records.iter() {
        stored.insert((**published).clone());
    }
    if let Some(last) = records.last() {
        session
            .confirm_durable(last.append_seq)
            .expect("the durable prefix is confirmed");
    }
    records
}

/// The session's current visible completion page, newest last.
pub async fn visible(session: &Session, limit: usize) -> Vec<ChatItem> {
    session
        .page(pl_core::chat::ChatPageRequest::latest().with_limit(limit))
        .await
        .expect("completion page is readable")
        .items
}

/// One visible record by identity.
pub async fn visible_item(session: &Session, item_id: &str) -> Option<ChatItem> {
    visible(session, 100)
        .await
        .into_iter()
        .find(|record| record.item_id == item_id)
}

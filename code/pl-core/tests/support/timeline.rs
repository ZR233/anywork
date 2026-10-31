//! Controlled storage fixtures. Selection/ownership under test remains in Session; the fake port
//! models indexed header-first IO and records EXACT requests and payload/range bytes fetched.
#![allow(dead_code)]

use pl_core::chat::*;
use std::{
    collections::BTreeMap,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicUsize, Ordering},
    },
};
use tokio::sync::Semaphore;

#[derive(Debug, Default)]
pub struct Reads {
    pub pages: Mutex<Vec<ChatHistoryRequest>>,
    pub afters: Mutex<Vec<ChatHistoryRequest>>,
    pub item: AtomicUsize,
    pub payload_bytes: AtomicUsize,
    pub ranges: Mutex<Vec<ContentReadRequest>>,
    pub manifests: AtomicUsize,
    pub validations: Mutex<Vec<ChatContentKey>>,
}

#[derive(Debug, Clone, Default)]
pub struct Stored {
    map: Arc<Mutex<BTreeMap<u64, ChatItem>>>,
    pub reads: Arc<Reads>,
    pub fail_page: Arc<AtomicBool>,
    pub fail_validation: Arc<AtomicBool>,
}
impl Stored {
    pub fn with(records: impl IntoIterator<Item = ChatItem>) -> Self {
        let stored = Self::default();
        for record in records {
            stored.insert(record);
        }
        stored
    }
    pub fn insert(&self, record: ChatItem) {
        self.map
            .lock()
            .unwrap()
            .insert(record.header.append_seq, record);
    }
    pub fn len(&self) -> usize {
        self.map.lock().unwrap().len()
    }
    pub fn remove(&self, seq: u64) {
        self.map.lock().unwrap().remove(&seq);
    }
    pub fn by_id(&self, id: &str) -> Option<ChatItem> {
        self.map
            .lock()
            .unwrap()
            .values()
            .find(|record| record.header.item_id == id)
            .cloned()
    }
    fn select(
        &self,
        request: &ChatHistoryRequest,
        budget: &dyn ChatBudget,
        descending: bool,
    ) -> Result<ChatHistoryPage, ChatError> {
        if self.fail_page.swap(false, Ordering::SeqCst) {
            return Err(ChatError::History(Box::new(std::io::Error::other(
                "controlled read failure",
            ))));
        }
        let map = self.map.lock().unwrap();
        let iter = map.values().filter(|record| {
            record.header.append_seq > request.after
                && record.header.append_seq <= request.ceiling
                && request
                    .before
                    .is_none_or(|before| record.header.append_seq < before)
                && request
                    .query
                    .as_ref()
                    .is_none_or(|query| query.matches(&record.header))
        });
        let iter: Box<dyn Iterator<Item = &ChatItem>> = if descending {
            Box::new(iter.rev())
        } else {
            Box::new(iter)
        };
        let mut remaining = request.demand;
        let mut items = Vec::new();
        let mut exhausted = true;
        for record in iter {
            if remaining.max_items == 0 || remaining.max_bytes == 0 {
                exhausted = false;
                break;
            }
            let Some(mode) = select_payload(&record.header, remaining.max_bytes, budget) else {
                exhausted = false;
                break;
            };
            remaining.max_items -= 1;
            remaining.max_bytes -= budget.item_bytes(&record.header, mode);
            let payload = match mode {
                PayloadMode::Inline => {
                    self.reads
                        .payload_bytes
                        .fetch_add(record.payload.len(), Ordering::SeqCst);
                    PayloadData::Inline(record.payload.clone())
                }
                PayloadMode::Deferred => PayloadData::Deferred {
                    item_id: record.header.item_id.clone(),
                    byte_length: record.header.byte_length,
                },
            };
            items.push(ChatPageItem {
                header: record.header.clone(),
                payload,
            });
        }
        if descending {
            items.reverse();
        }
        Ok(ChatHistoryPage { items, exhausted })
    }
}

impl ChatHistory for Stored {
    async fn latest_append_seq(&self) -> Result<u64, ChatError> {
        Ok(self
            .map
            .lock()
            .unwrap()
            .last_key_value()
            .map_or(0, |(seq, _)| *seq))
    }
    async fn page(
        &self,
        request: &ChatHistoryRequest,
        budget: &dyn ChatBudget,
    ) -> Result<ChatHistoryPage, ChatError> {
        self.reads.pages.lock().unwrap().push(request.clone());
        self.select(request, budget, true)
    }
    async fn page_after(
        &self,
        request: &ChatHistoryRequest,
        budget: &dyn ChatBudget,
    ) -> Result<ChatHistoryPage, ChatError> {
        self.reads.afters.lock().unwrap().push(request.clone());
        self.select(request, budget, false)
    }
    async fn item(&self, id: &str) -> Result<Option<ChatItem>, ChatError> {
        self.reads.item.fetch_add(1, Ordering::SeqCst);
        Ok(self.by_id(id))
    }
    async fn validate_content(&self, content: &ChatContent) -> Result<(), ChatError> {
        self.reads
            .validations
            .lock()
            .unwrap()
            .push(content.descriptor.key.clone());
        if self.fail_validation.swap(false, Ordering::SeqCst) {
            return Err(ChatError::History(Box::new(std::io::Error::other(
                "controlled validation failure",
            ))));
        }
        let stored = self
            .map
            .lock()
            .unwrap()
            .values()
            .find_map(|record| record.contents.get(&content.descriptor.key).cloned());
        if let Some(stored) = stored {
            if stored.descriptor != content.descriptor {
                return Err(ChatError::Conflict(content.descriptor.key.key.clone()));
            }
            for offset in (0..stored.data.len()).step_by(64 * 1024) {
                let old = stored.data.range(offset as u64, 64 * 1024)?;
                let new = content.data.range(offset as u64, 64 * 1024)?;
                if old.as_bytes() != new.as_bytes() {
                    return Err(ChatError::Conflict(content.descriptor.key.key.clone()));
                }
            }
        }
        Ok(())
    }
    async fn list_contents(
        &self,
        request: &ContentManifestRequest,
        budget: &dyn ChatBudget,
    ) -> Result<ContentManifestPage, ChatError> {
        self.reads.manifests.fetch_add(1, Ordering::SeqCst);
        let record = self
            .by_id(&request.item_id)
            .ok_or_else(|| ChatError::NotFound(request.item_id.clone()))?;
        let mut entries = Vec::new();
        let mut remaining = request.demand;
        let mut exhausted = true;
        for (key, content) in record
            .contents
            .iter()
            .filter(|(key, _)| request.after.as_ref().is_none_or(|after| *key > after))
        {
            let cost = budget.manifest_bytes(&content.descriptor);
            if remaining.max_items == 0 || cost > remaining.max_bytes {
                exhausted = false;
                break;
            }
            remaining.max_items -= 1;
            remaining.max_bytes -= cost;
            entries.push(content.descriptor.clone());
            assert_eq!(key, &content.descriptor.key);
        }
        if entries.is_empty() && !exhausted {
            return Err(ChatError::InvalidDemand("manifest envelope".into()));
        }
        Ok(ContentManifestPage {
            next: if exhausted {
                None
            } else {
                entries.last().map(|entry| entry.key.clone())
            },
            entries,
        })
    }
    async fn read_content(&self, request: &ContentReadRequest) -> Result<ContentWindow, ChatError> {
        self.reads.ranges.lock().unwrap().push(request.clone());
        let (data, generation) = match &request.reference {
            ContentRef::ItemPayload(id) => (
                ContentData::Bytes(
                    self.by_id(id)
                        .ok_or_else(|| ChatError::NotFound(id.clone()))?
                        .payload,
                ),
                0,
            ),
            ContentRef::Body(key) => {
                let content = self
                    .map
                    .lock()
                    .unwrap()
                    .values()
                    .find_map(|record| record.contents.get(key).cloned())
                    .ok_or_else(|| ChatError::NotFound(key.key.clone()))?;
                (content.data.clone(), content.descriptor.generation)
            }
        };
        if request
            .generation
            .is_some_and(|expected| expected != generation)
        {
            return Err(ChatError::StaleContent);
        }
        Ok(ContentWindow {
            offset: request.offset,
            bytes: data.range(request.offset, request.max_bytes)?,
            generation,
            available_through: data.len() as u64,
            sealed: true,
        })
    }
}

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
    pub async fn entered(&self) {
        self.entered.acquire().await.unwrap().forget();
    }
    pub fn release(&self) {
        self.release.add_permits(1);
    }
    pub async fn pause(&self) {
        self.entered.add_permits(1);
        self.release.acquire().await.unwrap().forget();
    }
}

#[derive(Debug, Clone)]
pub struct GatedHistory {
    pub inner: Stored,
    pub page_gate: Option<Arc<HistoryGate>>,
    pub after_gate: Option<Arc<HistoryGate>>,
    pub content_gate: Option<Arc<HistoryGate>>,
    pub captured_item_gate: Option<Arc<HistoryGate>>,
    pub captured_validation_gate: Option<Arc<HistoryGate>>,
    capture_next_item: Arc<AtomicBool>,
    capture_next_validation: Arc<AtomicBool>,
}
impl GatedHistory {
    pub fn new(inner: Stored) -> Self {
        Self {
            inner,
            page_gate: None,
            after_gate: None,
            content_gate: None,
            captured_item_gate: None,
            captured_validation_gate: None,
            capture_next_item: Arc::new(AtomicBool::new(true)),
            capture_next_validation: Arc::new(AtomicBool::new(true)),
        }
    }
}
impl ChatHistory for GatedHistory {
    async fn latest_append_seq(&self) -> Result<u64, ChatError> {
        self.inner.latest_append_seq().await
    }
    async fn page(
        &self,
        request: &ChatHistoryRequest,
        budget: &dyn ChatBudget,
    ) -> Result<ChatHistoryPage, ChatError> {
        if let Some(gate) = &self.page_gate {
            gate.pause().await;
        }
        self.inner.page(request, budget).await
    }
    async fn page_after(
        &self,
        request: &ChatHistoryRequest,
        budget: &dyn ChatBudget,
    ) -> Result<ChatHistoryPage, ChatError> {
        if let Some(gate) = &self.after_gate {
            gate.pause().await;
        }
        self.inner.page_after(request, budget).await
    }
    async fn item(&self, id: &str) -> Result<Option<ChatItem>, ChatError> {
        let item = self.inner.item(id).await?;
        if let Some(gate) = &self.captured_item_gate
            && self.capture_next_item.swap(false, Ordering::SeqCst)
        {
            gate.pause().await;
        }
        Ok(item)
    }
    async fn validate_content(&self, content: &ChatContent) -> Result<(), ChatError> {
        let result = self.inner.validate_content(content).await;
        if let Some(gate) = &self.captured_validation_gate
            && self.capture_next_validation.swap(false, Ordering::SeqCst)
        {
            gate.pause().await;
        }
        result
    }
    async fn list_contents(
        &self,
        request: &ContentManifestRequest,
        budget: &dyn ChatBudget,
    ) -> Result<ContentManifestPage, ChatError> {
        self.inner.list_contents(request, budget).await
    }
    async fn read_content(&self, request: &ContentReadRequest) -> Result<ContentWindow, ChatError> {
        if let Some(gate) = &self.content_gate {
            gate.pause().await;
        }
        self.inner.read_content(request).await
    }
}

/// Conservative JSON-like encoding budget: count worst-case escaping, not raw payload length.
#[derive(Debug, Default)]
pub struct Budget {
    pub visited: Mutex<Vec<u64>>,
}
impl ChatBudget for Budget {
    fn fixed_bytes(&self) -> usize {
        64
    }
    fn item_bytes(&self, header: &ChatItemHeader, mode: PayloadMode) -> usize {
        self.visited.lock().unwrap().push(header.append_seq);
        let payload = match mode {
            PayloadMode::Inline => usize::try_from(header.byte_length)
                .unwrap()
                .saturating_mul(6),
            PayloadMode::Deferred => 64,
        };
        64 + header.item_id.len() * 6 + payload
    }
    fn manifest_bytes(&self, descriptor: &ContentDescriptor) -> usize {
        128 + 6
            * (descriptor.key.owner.as_str().len()
                + descriptor.key.key.len()
                + descriptor.media_type.as_ref().map_or(0, String::len))
    }
}

pub fn epoch(name: &str) -> TimelineEpoch {
    TimelineEpoch::new(name).unwrap()
}
pub fn query() -> ChatQuery {
    ChatQuery::new("conversation", None)
}
pub fn demand(items: usize) -> ReadDemand {
    ReadDemand::new(items, 1024 * 1024)
}
pub fn latest(items: usize) -> ChatPageRequest {
    ChatPageRequest::latest(query(), demand(items))
}
pub fn draft(id: &str, text: &str) -> ChatDraft {
    ChatDraft::new(id, "conversation", Arc::from(text.as_bytes()))
}
pub fn record(seq: u64, text: &str) -> ChatItem {
    record_identified(&format!("item-{seq}"), seq, text)
}
pub fn record_identified(id: &str, seq: u64, text: &str) -> ChatItem {
    ChatItem::complete(draft(id, text), seq)
}
pub fn sequences(items: &[ChatPageItem]) -> Vec<u64> {
    items.iter().map(|item| item.header.append_seq).collect()
}
pub async fn visible(session: &Session, items: usize) -> Vec<ChatPageItem> {
    session
        .page(latest(items), &Budget::default())
        .await
        .unwrap()
        .items
}
pub async fn publish_and_commit(session: &Session, stored: &Stored, drafts: Vec<ChatDraft>) {
    let records = session.publish_batch(drafts).await.unwrap();
    for record in records.iter() {
        stored.insert((**record).clone());
    }
    if let Some(record) = records.last() {
        session.confirm_durable(record.header.append_seq).unwrap();
    }
}
pub fn with_body(mut draft: ChatDraft, key: &str, data: ContentData) -> ChatDraft {
    let key = ChatContentKey {
        owner: ChatKey::new("item", &draft.item_id).unwrap(),
        key: key.into(),
    };
    let content = Arc::new(ChatContent {
        descriptor: ContentDescriptor {
            key: key.clone(),
            byte_length: data.len() as u64,
            generation: 7,
            media_type: None,
        },
        data,
    });
    Arc::make_mut(&mut draft.contents).insert(key, content);
    draft
}
pub fn content_request(reference: ContentRef, offset: u64, max_bytes: usize) -> ContentReadRequest {
    ContentReadRequest {
        epoch: epoch("run-1"),
        reference,
        offset,
        max_bytes,
        generation: None,
    }
}

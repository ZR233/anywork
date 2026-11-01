//! Independent, revocable read qualification. Queries never take the feed's receive/credit lock.
use super::thread_observation::{ObservationSlot, ThreadLiveFeed};
use crate::studio::{storage::history::HistoryStore, thread_projection::CurrentState};
use anyhow::{Result, ensure};
use core::ChatBudget as _;
use pl_core::chat as core;
use pl_protocol::*;
use serde::{Deserialize, Serialize};
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};
use tokio::sync::{RwLock, watch};
use tokio_util::sync::CancellationToken;

#[derive(Clone)]
pub struct ConversationReader {
    pub(super) inner: Arc<ReadLease>,
}
pub(super) struct ReadLease {
    pub id: String,
    pub thread_id: String,
    pub scope: ChatScope,
    pub ceiling: u64,
    pub slot: Arc<ObservationSlot>,
    pub epoch: u64,
    cancel: CancellationToken,
    resources: RwLock<Option<ReadResources>>,
    resync: AtomicBool,
}
pub(super) struct ReadResources {
    pub history: HistoryStore,
    pub session: core::Session,
    pub database_id: Option<String>,
    pub source: Option<Arc<ThreadLiveFeed>>,
    pub thread: Thread,
    pub recovery: crate::studio::StudioRecoveryRegistry,
}
struct ReadPermit<'a> {
    lease: &'a ReadLease,
    guard: Option<tokio::sync::RwLockReadGuard<'a, Option<ReadResources>>>,
}
impl std::ops::Deref for ReadPermit<'_> {
    type Target = Option<ReadResources>;
    fn deref(&self) -> &Self::Target {
        self.guard
            .as_deref()
            .expect("a live read permit always owns its guard")
    }
}
impl Drop for ReadPermit<'_> {
    fn drop(&mut self) {
        drop(self.guard.take());
        if self.lease.cancel.is_cancelled()
            && let Ok(mut resources) = self.lease.resources.try_write()
        {
            resources.take();
        }
    }
}
impl std::fmt::Debug for ConversationReader {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("ConversationReader")
            .field("thread_id", &self.thread_id())
            .field("subscription_id", &self.subscription_id())
            .finish_non_exhaustive()
    }
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
struct Cursor {
    lease: String,
    database: Option<String>,
    scope: ChatScope,
    epoch: String,
    ceiling: u64,
    kind: CursorKind,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(tag = "kind", deny_unknown_fields)]
enum CursorKind {
    Before {
        boundary: u64,
    },
    Manifest {
        item: String,
        after: String,
    },
    Current {
        reference: CurrentCollectionRef,
        after: String,
    },
}

pub(super) fn query(scope: &ChatScope) -> Result<core::ChatQuery> {
    Ok(core::ChatQuery::new(
        scope.query_class(),
        scope
            .parent_id()
            .map(|parent| core::ChatKey::from_encoded(parent.to_owned()))
            .transpose()?,
    ))
}
pub(super) fn core_demand(demand: ReadDemand) -> Result<core::ReadDemand> {
    demand.validate(1)?;
    Ok(core::ReadDemand::new(
        demand.max_items as usize,
        demand.max_bytes as usize,
    ))
}
pub(super) fn resync() -> anyhow::Error {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Busy,
        "Conversation source continuity changed; open a new handle",
        true,
    )
    .with_reason(
        pl_protocol::studio::StudioErrorReason::ConversationResyncRequired,
        serde_json::Value::Null,
    )
    .into()
}
fn cancelled() -> anyhow::Error {
    core::ChatError::Cancelled.into()
}
fn stale() -> anyhow::Error {
    core::ChatError::StaleContent.into()
}

impl ConversationReader {
    pub(super) fn new(
        id: String,
        scope: ChatScope,
        ceiling: u64,
        slot: Arc<ObservationSlot>,
        epoch: u64,
        resources: ReadResources,
    ) -> Self {
        Self {
            inner: Arc::new(ReadLease {
                thread_id: resources.thread.id.clone(),
                id,
                scope,
                ceiling,
                slot,
                epoch,
                cancel: CancellationToken::new(),
                resync: AtomicBool::new(false),
                resources: RwLock::new(Some(resources)),
            }),
        }
    }
    pub fn thread_id(&self) -> &str {
        &self.inner.thread_id
    }
    pub fn subscription_id(&self) -> &str {
        &self.inner.id
    }
    pub(super) fn ensure(&self) -> Result<()> {
        if self.inner.resync.load(Ordering::Acquire) {
            return Err(resync());
        }
        if self.inner.cancel.is_cancelled() {
            return Err(cancelled());
        }
        if !self.inner.slot.is_current(self.inner.epoch) {
            self.invalidate();
            return Err(resync());
        }
        Ok(())
    }
    pub(super) fn invalidate(&self) {
        self.inner.resync.store(true, Ordering::Release);
        self.inner.cancel.cancel();
        if let Ok(mut resources) = self.inner.resources.try_write() {
            resources.take();
        }
    }
    pub fn request_close(&self) {
        self.inner.cancel.cancel();
        if let Ok(mut resources) = self.inner.resources.try_write() {
            resources.take();
        }
    }
    pub async fn close(&self) -> Result<()> {
        self.request_close();
        self.inner.resources.write().await.take();
        Ok(())
    }
    async fn resources(&self) -> Result<ReadPermit<'_>> {
        self.ensure()?;
        let guard = tokio::select! { biased; _=self.inner.cancel.cancelled()=>return Err(self.ensure().err().unwrap_or_else(cancelled)), read=self.inner.resources.read()=>read };
        let read = ReadPermit {
            lease: &self.inner,
            guard: Some(guard),
        };
        self.ensure()?;
        if let Some(resources) = read.as_ref() {
            resources
                .recovery
                .ensure_thread_read_access(&resources.thread)?;
        } else {
            return Err(cancelled());
        }
        Ok(read)
    }
    fn token(&self, resources: &ReadResources, kind: CursorKind) -> Result<String> {
        Ok(serde_json::to_string(&Cursor {
            lease: self.inner.id.clone(),
            database: resources.database_id.clone(),
            scope: self.inner.scope.clone(),
            epoch: resources.session.epoch().as_str().into(),
            ceiling: self.inner.ceiling,
            kind,
        })?)
    }
    fn cursor(&self, resources: &ReadResources, token: &str) -> Result<CursorKind> {
        ensure!(
            token.len() <= CHAT_BATCH_MAX_BYTES as usize,
            core::ChatError::InvalidArgument("continuation is too large".into())
        );
        let cursor: Cursor = serde_json::from_str(token).map_err(|_| {
            core::ChatError::InvalidArgument("invalid conversation continuation".into())
        })?;
        ensure!(
            cursor.lease == self.inner.id
                && cursor.database == resources.database_id
                && cursor.scope == self.inner.scope
                && cursor.epoch == resources.session.epoch().as_str()
                && cursor.ceiling == self.inner.ceiling,
            core::ChatError::InvalidArgument(
                "continuation belongs to another read qualification".into()
            )
        );
        Ok(cursor.kind)
    }
    pub(super) async fn before(&self, boundary: Option<u64>) -> Result<Option<String>> {
        let guard = self.resources().await?;
        let r = guard.as_ref().ok_or_else(cancelled)?;
        boundary
            .map(|boundary| self.token(r, CursorKind::Before { boundary }))
            .transpose()
    }
    pub(super) async fn budget(&self, current: Option<CurrentProjection>) -> Result<JsonBudget> {
        let guard = self.resources().await?;
        let r = guard.as_ref().ok_or_else(cancelled)?;
        let token = self.token(r, CursorKind::Before { boundary: u64::MAX })?;
        Ok(JsonBudget::new(
            r.database_id.clone().unwrap_or_default(),
            current,
            token,
        ))
    }
    pub async fn load_older(&self, before: &str, demand: ReadDemand) -> Result<ChatBatch> {
        let guard = self.resources().await?;
        let r = guard.as_ref().ok_or_else(cancelled)?;
        let CursorKind::Before { boundary } = self.cursor(r, before)? else {
            return Err(
                core::ChatError::InvalidArgument("not a history continuation".into()).into(),
            );
        };
        ensure!(
            boundary > 0 && boundary <= self.inner.ceiling,
            core::ChatError::InvalidArgument("invalid exclusive boundary".into())
        );
        let budget = JsonBudget::new(
            r.database_id.clone().unwrap_or_default(),
            None,
            self.token(r, CursorKind::Before { boundary: u64::MAX })?,
        );
        let page = r
            .session
            .page(
                core::ChatPageRequest::before(
                    core::ChatCursor {
                        epoch: r.session.epoch(),
                        query: query(&self.inner.scope)?,
                        ceiling: self.inner.ceiling,
                        append_seq: boundary,
                    },
                    core_demand(demand)?,
                ),
                &budget,
            )
            .await?;
        let batch = ChatBatch {
            placement: ChatPlacement::Prepend,
            messages: messages(page.items, &budget.database_id),
            before: page
                .before
                .map(|cursor| {
                    self.token(
                        r,
                        CursorKind::Before {
                            boundary: cursor.append_seq,
                        },
                    )
                })
                .transpose()?,
            current: None,
        };
        self.finish_batch(batch, demand)
    }
    pub(super) fn finish_batch(&self, batch: ChatBatch, demand: ReadDemand) -> Result<ChatBatch> {
        self.ensure()?;
        batch.validate_for(&self.inner.scope)?;
        ensure!(
            batch.encoded_len()? <= demand.max_bytes as usize,
            core::ChatError::InvalidDemand("encoded chat batch exceeds demand".into())
        );
        Ok(batch)
    }
    pub async fn list_contents(
        &self,
        item_id: &str,
        continuation: Option<&str>,
        demand: ReadDemand,
    ) -> Result<ContentManifestPage> {
        let guard = self.resources().await?;
        let r = guard.as_ref().ok_or_else(cancelled)?;
        let after = continuation
            .map(|token| -> Result<_> {
                match self.cursor(r, token)? {
                    CursorKind::Manifest { item, after } if item == item_id => Ok(after),
                    _ => Err(core::ChatError::InvalidArgument(
                        "not this manifest continuation".into(),
                    )
                    .into()),
                }
            })
            .transpose()?;
        let database = r.database_id.as_deref().ok_or_else(stale)?;
        let owner = crate::studio::conversation_identity::content_owner_key(&ContentOwner::Item {
            item_id: item_id.into(),
        })?;
        let mut budget = JsonBudget::new(
            database.into(),
            None,
            self.token(
                r,
                CursorKind::Manifest {
                    item: item_id.into(),
                    after: String::new(),
                },
            )?,
        );
        budget.manifest_item = Some(item_id.into());
        let token = self.token(
            r,
            CursorKind::Manifest {
                item: item_id.into(),
                after: String::new(),
            },
        )?;
        budget.fixed = serde_json::to_vec(&ContentManifestPage {
            entries: Vec::new(),
            continuation: Some(token.clone()),
        })?
        .len();
        budget.manifest_cursor = Some(serde_json::from_str(&token)?);
        let active = r
            .source
            .as_ref()
            .and_then(|source| source.current_conversation())
            .map(|source| source.current.clone());
        let entries = active
            .as_ref()
            .map(|state| {
                state
                    .contents
                    .values()
                    .filter(|content| content.descriptor.key.owner == owner)
                    .map(|content| content.descriptor.clone())
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();
        let (descriptors, next) = if entries.is_empty() {
            let page = r
                .session
                .list_contents(
                    core::ContentManifestRequest {
                        epoch: r.session.epoch(),
                        item_id: item_id.into(),
                        after: after.map(|key| core::ChatContentKey {
                            owner: owner.clone(),
                            key,
                        }),
                        demand: core_demand(demand)?,
                    },
                    &budget,
                )
                .await?;
            (page.entries, page.next.map(|key| key.key))
        } else {
            core_demand(demand)?;
            let mut selected = Vec::new();
            let mut bytes = budget.fixed_bytes();
            let mut next = None;
            let iter = entries
                .into_iter()
                .filter(|entry| after.as_ref().is_none_or(|after| entry.key.key > *after))
                .peekable();
            for entry in iter {
                let size = core::ChatBudget::manifest_bytes(&budget, &entry);
                if selected.len() == demand.max_items as usize
                    || bytes.saturating_add(size) > demand.max_bytes as usize
                {
                    next = selected
                        .last()
                        .map(|entry: &core::ContentDescriptor| entry.key.key.clone());
                    ensure!(
                        !selected.is_empty(),
                        core::ChatError::InvalidDemand("manifest envelope does not fit".into())
                    );
                    break;
                }
                bytes += size;
                selected.push(entry);
            }
            (selected, next)
        };
        let entries = descriptors
            .into_iter()
            .map(|descriptor| manifest_entry(database, item_id, descriptor))
            .collect::<Result<Vec<_>>>()?;
        let page = ContentManifestPage {
            entries,
            continuation: next
                .map(|after| {
                    self.token(
                        r,
                        CursorKind::Manifest {
                            item: item_id.into(),
                            after,
                        },
                    )
                })
                .transpose()?,
        };
        self.ensure()?;
        ensure!(
            serde_json::to_vec(&page)?.len() <= demand.max_bytes as usize,
            core::ChatError::InvalidDemand("manifest encoding exceeds demand".into())
        );
        Ok(page)
    }
    pub async fn read_content(
        &self,
        reference: &ContentRef,
        range: ContentRange,
    ) -> Result<ContentWindow> {
        ensure!(
            range.max_bytes > 0 && range.max_bytes <= CONTENT_WINDOW_MAX_BYTES,
            core::ChatError::InvalidDemand("invalid content range".into())
        );
        let guard = self.resources().await?;
        let r = guard.as_ref().ok_or_else(cancelled)?;
        ensure!(
            r.database_id.as_deref() == Some(reference.database_id.as_str()),
            core::ChatError::StaleContent
        );
        let source = r
            .source
            .as_ref()
            .and_then(|source| source.current_conversation());
        if let ContentTarget::Body { owner, key } = &reference.target {
            let content_key = core::ChatContentKey {
                owner: crate::studio::conversation_identity::content_owner_key(owner)?,
                key: key.clone(),
            };
            if let Some(content) = source
                .as_ref()
                .and_then(|source| source.current.contents.get(&content_key))
            {
                let content = content.content();
                let bytes = content.data.range(range.offset, range.max_bytes as usize)?;
                self.ensure()?;
                return Ok(ContentWindow {
                    offset: range.offset,
                    bytes: bytes.as_bytes().to_vec(),
                    generation: content.descriptor.generation.to_string(),
                    available_through: content.descriptor.byte_length,
                    sealed: matches!(owner, ContentOwner::Current { .. }),
                });
            }
            if let ContentOwner::Current {
                domain,
                id,
                revision,
            } = owner
            {
                let state = source.as_ref().map(|source| &source.current);
                if let Some(collection) = domain.strip_prefix("collection:")
                    && let Some(state) = state
                {
                    ensure!(
                        state
                            .projection
                            .collections
                            .iter()
                            .any(|reference| reference.collection == collection
                                && reference.revision == *revision),
                        core::ChatError::StaleContent
                    );
                    let entry = state
                        .entries
                        .get(&(collection.into(), id.clone()))
                        .ok_or_else(stale)?;
                    let data = core::ContentData::Bytes(entry.payload.clone());
                    let bytes = data.range(range.offset, range.max_bytes as usize)?;
                    self.ensure()?;
                    return Ok(ContentWindow {
                        offset: range.offset,
                        bytes: bytes.as_bytes().to_vec(),
                        generation: revision.to_string(),
                        available_through: entry.payload.len() as u64,
                        sealed: true,
                    });
                }
                if state.is_some() {
                    return Err(stale());
                }
            }
        }
        let reference = match &reference.target {
            ContentTarget::ItemPayload { item_id } => {
                core::ContentRef::ItemPayload(item_id.clone())
            }
            ContentTarget::Body { owner, key } => core::ContentRef::Body(core::ChatContentKey {
                owner: crate::studio::conversation_identity::content_owner_key(owner)?,
                key: key.clone(),
            }),
        };
        let window = r
            .session
            .read_content(core::ContentReadRequest {
                epoch: r.session.epoch(),
                reference,
                offset: range.offset,
                max_bytes: range.max_bytes as usize,
                generation: None,
            })
            .await?;
        self.ensure()?;
        Ok(ContentWindow {
            offset: window.offset,
            bytes: window.bytes.as_bytes().to_vec(),
            generation: window.generation.to_string(),
            available_through: window.available_through,
            sealed: window.sealed,
        })
    }
    pub async fn page_current(
        &self,
        reference: &CurrentCollectionRef,
        continuation: Option<&str>,
        demand: ReadDemand,
    ) -> Result<CurrentCollectionPage> {
        core_demand(demand)?;
        let guard = self.resources().await?;
        let r = guard.as_ref().ok_or_else(cancelled)?;
        ensure!(
            r.database_id.as_deref() == Some(reference.database_id.as_str()),
            core::ChatError::StaleContent
        );
        let after = continuation
            .map(|token| -> Result<_> {
                match self.cursor(r, token)? {
                    CursorKind::Current {
                        reference: original,
                        after,
                    } if original == *reference => Ok(after),
                    _ => Err(core::ChatError::InvalidArgument(
                        "not this current continuation".into(),
                    )
                    .into()),
                }
            })
            .transpose()?;
        let source = r
            .source
            .as_ref()
            .and_then(|source| source.current_conversation());
        let encode = |after| {
            self.token(
                r,
                CursorKind::Current {
                    reference: reference.clone(),
                    after,
                },
            )
        };
        let page = if let Some(source) = source {
            current_page(&source.current, reference, after.as_deref(), demand, encode)?
        } else {
            r.history
                .page_current(reference, after.as_deref(), demand, &encode)
                .await?
        };
        self.ensure()?;
        ensure!(
            serde_json::to_vec(&page)?.len() <= demand.max_bytes as usize,
            core::ChatError::InvalidDemand("current page exceeds demand".into())
        );
        Ok(page)
    }
    pub async fn watch_content(
        &self,
        reference: &ContentRef,
        range: ContentRange,
    ) -> Result<ContentWatch> {
        ensure!(
            range.max_bytes > 0 && range.max_bytes <= CONTENT_WINDOW_MAX_BYTES,
            core::ChatError::InvalidDemand("invalid content range".into())
        );
        let guard = self.resources().await?;
        let r = guard.as_ref().ok_or_else(cancelled)?;
        ensure!(
            r.database_id.as_deref() == Some(reference.database_id.as_str()),
            core::ChatError::StaleContent
        );
        let changed = r.source.as_ref().map(|source| source.content_changes());
        let (_, slot_changed) = self.inner.slot.capture();
        Ok(ContentWatch {
            reader: self.clone(),
            reference: reference.clone(),
            range,
            changed,
            slot_changed,
            initial: true,
            last: None,
            cancel: CancellationToken::new(),
        })
    }
}

#[derive(PartialEq, Eq)]
struct WindowStamp {
    generation: String,
    offset: u64,
    available_through: u64,
    sealed: bool,
    digest: String,
}
impl From<&ContentWindow> for WindowStamp {
    fn from(window: &ContentWindow) -> Self {
        Self {
            generation: window.generation.clone(),
            offset: window.offset,
            available_through: window.available_through,
            sealed: window.sealed,
            digest: crate::canonical_content_hash(&window.bytes),
        }
    }
}

pub struct ContentWatch {
    reader: ConversationReader,
    reference: ContentRef,
    range: ContentRange,
    changed: Option<watch::Receiver<u64>>,
    slot_changed: watch::Receiver<u64>,
    initial: bool,
    last: Option<WindowStamp>,
    cancel: CancellationToken,
}
impl ContentWatch {
    /// Capture before placing the watch behind a receive mutex, so close can wake that receiver.
    pub fn cancellation_token(&self) -> CancellationToken {
        self.cancel.clone()
    }
    pub fn request_close(&self) {
        self.cancel.cancel();
    }
    pub async fn recv(&mut self) -> Result<Option<ContentWindow>> {
        loop {
            if self.cancel.is_cancelled() {
                return Err(cancelled());
            }
            self.reader.ensure()?;
            if !self.initial {
                if self.last.as_ref().is_some_and(|window| window.sealed) {
                    return Ok(None);
                }
                let Some(changed) = self.changed.as_mut() else {
                    return Ok(None);
                };
                tokio::select! { biased;
                    _=self.cancel.cancelled()=>return Err(cancelled()),
                    _=self.reader.inner.cancel.cancelled()=>return Err(self.reader.ensure().err().unwrap_or_else(cancelled)),
                    _=self.slot_changed.changed()=>return Err(resync()),
                    result=changed.changed()=>if result.is_err() { return Err(resync()); }
                }
            }
            self.initial = false;
            let window = self
                .reader
                .read_content(&self.reference, self.range.clone())
                .await?;
            let stamp = WindowStamp::from(&window);
            if self.last.as_ref() != Some(&stamp) {
                self.last = Some(stamp);
                return Ok(Some(window));
            }
        }
    }
    pub async fn close(&mut self) -> Result<()> {
        self.request_close();
        self.changed = None;
        self.last = None;
        Ok(())
    }
}

pub(super) struct JsonBudget {
    pub database_id: String,
    fixed: usize,
    manifest_item: Option<String>,
    manifest_cursor: Option<Cursor>,
}
impl JsonBudget {
    pub(super) fn new(
        database_id: String,
        current: Option<CurrentProjection>,
        continuation: String,
    ) -> Self {
        let batch = ChatBatch {
            placement: ChatPlacement::Prepend,
            messages: Vec::new(),
            before: Some(continuation),
            current,
        };
        Self {
            database_id,
            fixed: serde_json::to_vec(&batch).map_or(usize::MAX, |bytes| bytes.len()),
            manifest_item: None,
            manifest_cursor: None,
        }
    }
}
impl core::ChatBudget for JsonBudget {
    fn fixed_bytes(&self) -> usize {
        self.fixed
    }
    fn item_bytes(&self, header: &core::ChatItemHeader, mode: core::PayloadMode) -> usize {
        let payload = match mode {
            core::PayloadMode::Inline => PayloadData::Inline { bytes: Vec::new() },
            core::PayloadMode::Deferred => PayloadData::Deferred {
                reference: ContentRef {
                    database_id: self.database_id.clone(),
                    target: ContentTarget::ItemPayload {
                        item_id: header.item_id.clone(),
                    },
                },
                byte_length: header.byte_length,
            },
        };
        let base = serde_json::to_vec(&ChatMessage {
            id: header.item_id.clone(),
            payload,
        })
        .map_or(usize::MAX, |bytes| bytes.len().saturating_add(1));
        if mode == core::PayloadMode::Inline {
            base.saturating_add(
                usize::try_from(header.byte_length)
                    .unwrap_or(usize::MAX)
                    .saturating_mul(4),
            )
        } else {
            base
        }
    }
    fn manifest_bytes(&self, descriptor: &core::ContentDescriptor) -> usize {
        let entry = manifest_entry(
            &self.database_id,
            self.manifest_item.as_deref().unwrap_or("item"),
            descriptor.clone(),
        )
        .and_then(|entry| Ok(serde_json::to_vec(&entry)?.len().saturating_add(1)))
        .unwrap_or(usize::MAX);
        let continuation = self
            .manifest_cursor
            .as_ref()
            .and_then(|cursor| {
                let mut next = cursor.clone();
                next.kind = CursorKind::Manifest {
                    item: self.manifest_item.clone()?,
                    after: descriptor.key.key.clone(),
                };
                let before = serde_json::to_vec(&serde_json::to_string(cursor).ok()?)
                    .ok()?
                    .len();
                let after = serde_json::to_vec(&serde_json::to_string(&next).ok()?)
                    .ok()?
                    .len();
                Some(after.saturating_sub(before))
            })
            .unwrap_or(0);
        entry.saturating_add(continuation)
    }
}
pub(super) fn messages(items: Vec<core::ChatPageItem>, database_id: &str) -> Vec<ChatMessage> {
    items
        .into_iter()
        .map(|item| ChatMessage {
            id: item.header.item_id,
            payload: match item.payload {
                core::PayloadData::Inline(bytes) => PayloadData::Inline {
                    bytes: bytes.to_vec(),
                },
                core::PayloadData::Deferred {
                    item_id,
                    byte_length,
                } => PayloadData::Deferred {
                    reference: ContentRef {
                        database_id: database_id.into(),
                        target: ContentTarget::ItemPayload { item_id },
                    },
                    byte_length,
                },
            },
        })
        .collect()
}
fn manifest_entry(
    database: &str,
    item_id: &str,
    descriptor: core::ContentDescriptor,
) -> Result<ContentManifestEntry> {
    Ok(ContentManifestEntry {
        key: descriptor.key.key.clone(),
        payload: serde_json::to_vec(
            &serde_json::json!({"byteLength":descriptor.byte_length,"generation":descriptor.generation,"mediaType":descriptor.media_type}),
        )?,
        reference: ContentRef {
            database_id: database.into(),
            target: ContentTarget::Body {
                owner: ContentOwner::Item {
                    item_id: item_id.into(),
                },
                key: descriptor.key.key,
            },
        },
    })
}
fn current_page(
    state: &CurrentState,
    reference: &CurrentCollectionRef,
    after: Option<&str>,
    demand: ReadDemand,
    encode: impl Fn(String) -> Result<String>,
) -> Result<CurrentCollectionPage> {
    ensure!(
        state
            .projection
            .collections
            .iter()
            .any(|current| current == reference),
        core::ChatError::StaleContent
    );
    let boundary = after
        .map(serde_json::from_str::<(i64, String)>)
        .transpose()?;
    use std::ops::Bound::{Excluded, Included};
    let lower = match boundary {
        Some((position, id)) => Excluded((reference.collection.clone(), position, id)),
        None => Included((reference.collection.clone(), i64::MIN, String::new())),
    };
    let upper = Excluded((
        format!("{}\0", reference.collection),
        i64::MIN,
        String::new(),
    ));
    let mut page = CurrentCollectionPage {
        revision: reference.revision,
        entries: Vec::new(),
        continuation: None,
    };
    let mut selected_bytes = 0usize;
    for (_, entry) in state.by_position.range((lower, upper)) {
        if page.entries.len() == demand.max_items as usize {
            return Ok(page);
        }
        let token = encode(serde_json::to_string(&(entry.position, &entry.entry_id))?)?;
        let fixed = serde_json::to_vec(&CurrentCollectionPage {
            revision: reference.revision,
            entries: Vec::new(),
            continuation: Some(token.clone()),
        })?
        .len();
        let mut candidate = CurrentCollectionEntry {
            id: entry.entry_id.clone(),
            position: entry.position,
            payload: PayloadData::Inline { bytes: Vec::new() },
        };
        let overhead = serde_json::to_vec(&candidate)?
            .len()
            .saturating_add(usize::from(!page.entries.is_empty()));
        let inline = overhead.saturating_add(entry.payload.len().saturating_mul(4));
        if fixed.saturating_add(selected_bytes).saturating_add(inline) <= demand.max_bytes as usize
        {
            candidate.payload = PayloadData::Inline {
                bytes: entry.payload.to_vec(),
            };
        } else {
            candidate.payload = PayloadData::Deferred {
                reference: ContentRef {
                    database_id: reference.database_id.clone(),
                    target: ContentTarget::Body {
                        owner: ContentOwner::Current {
                            domain: format!("collection:{}", reference.collection),
                            id: entry.entry_id.clone(),
                            revision: reference.revision,
                        },
                        key: "entry".into(),
                    },
                },
                byte_length: entry.payload.len() as u64,
            };
        }
        let cost = serde_json::to_vec(&candidate)?
            .len()
            .saturating_add(usize::from(!page.entries.is_empty()));
        if fixed.saturating_add(selected_bytes).saturating_add(cost) > demand.max_bytes as usize {
            ensure!(
                !page.entries.is_empty(),
                core::ChatError::InvalidDemand("current envelope does not fit".into())
            );
            return Ok(page);
        }
        selected_bytes = selected_bytes.saturating_add(cost);
        page.entries.push(candidate);
        page.continuation = Some(token);
    }
    page.continuation = None;
    Ok(page)
}

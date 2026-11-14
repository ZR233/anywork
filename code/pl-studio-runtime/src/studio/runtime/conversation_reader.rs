//! Independent, revocable read qualification. Queries never take the feed's receive/credit lock.
use super::thread_observation::ObservationSlot;
use crate::studio::storage::history::HistoryStore;
use crate::studio::thread_projection::current_page;
use anyhow::{Result, ensure};
use core::ChatBudget as _;
use pl_core::chat as core;
use pl_protocol::*;
use serde::{Deserialize, Serialize};
use std::sync::{
    Arc, OnceLock,
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
    pub effect_cut: u64,
    presentation_ceiling: OnceLock<u64>,
    pub slot: Arc<ObservationSlot>,
    cancel: CancellationToken,
    runtime_closed: CancellationToken,
    resources: RwLock<Option<ReadResources>>,
    resync: AtomicBool,
}
pub(super) struct ReadResources {
    /// Bounded metadata at this read cut; never retains a body or a current collection.
    pub history: HistoryStore,
    pub session: core::Session,
    pub database_id: Option<String>,
    pub conversation: crate::studio::conversation_store::ConversationReadHandle,
    pub thread: Thread,
    pub recovery: crate::studio::StudioRecoveryRegistry,
}
pub(super) struct ReadPermit<'a> {
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
    version: u32,
    index_version: u32,
    thread_id: String,
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
    DisplayBefore {
        presentation_version: u32,
        ceiling: u64,
        boundary: u64,
    },
    LiveDisplayBefore {
        presentation_version: u32,
        revision: u64,
        boundary: u64,
    },
}

/// A short-query copy of the existing cursor binding, not an independent read qualification.
/// Its caller must still recheck the original reader before delivering a result.
pub(super) struct PresentationTokens {
    binding: Cursor,
    ceiling: u64,
}

impl PresentationTokens {
    fn encode(&self, kind: CursorKind) -> Result<String> {
        let mut cursor = self.binding.clone();
        cursor.kind = kind;
        Ok(serde_json::to_string(&cursor)?)
    }
    pub(super) fn before(&self, ceiling: u64, boundary: u64) -> Result<String> {
        ensure!(
            boundary > 0 && boundary <= ceiling.saturating_add(1) && ceiling == self.ceiling,
            core::ChatError::InvalidArgument("invalid display history boundary".into())
        );
        self.encode(CursorKind::DisplayBefore {
            presentation_version: PRESENTATION_VERSION,
            ceiling,
            boundary,
        })
    }
    pub(super) fn live_before(&self, revision: u64, boundary: u64) -> Result<String> {
        ensure!(
            boundary > 0,
            core::ChatError::InvalidArgument("invalid live display boundary".into())
        );
        self.encode(CursorKind::LiveDisplayBefore {
            presentation_version: PRESENTATION_VERSION,
            revision,
            boundary,
        })
    }
}

pub(super) fn query(scope: &ChatScope) -> Result<core::ChatQuery> {
    let mut query = core::ChatQuery::new(
        scope.query_class(),
        scope
            .parent_id()
            .map(|parent| core::ChatKey::from_encoded(parent.to_owned()))
            .transpose()?,
    );
    query.selection = match scope {
        ChatScope::Main => core::ChatSelection::RunHeads,
        ChatScope::Run { reference } => core::ChatSelection::Run {
            start_seq: reference.start_seq,
        },
        ChatScope::Children { .. } => core::ChatSelection::Records,
    };
    Ok(query)
}
pub(super) fn core_demand(demand: ReadDemand) -> Result<core::ReadDemand> {
    demand.validate(1)?;
    Ok(core::ReadDemand::new(
        demand.max_items as usize,
        demand.max_bytes as usize,
    ))
}
#[track_caller]
pub(super) fn resync() -> anyhow::Error {
    let error = pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Busy,
        "Conversation source continuity changed; open a new handle",
        true,
    )
    .with_reason(
        pl_protocol::studio::StudioErrorReason::ConversationResyncRequired,
        serde_json::Value::Null,
    );
    let caller = std::panic::Location::caller();
    tracing::debug!(
        target: "conversation_continuity",
        correlation_id = %error.correlation_id,
        source_file = caller.file(),
        source_line = caller.line(),
        "conversation resynchronization required"
    );
    error.into()
}
pub(super) fn cancelled() -> anyhow::Error {
    core::ChatError::Cancelled.into()
}
fn stale() -> anyhow::Error {
    core::ChatError::StaleContent.into()
}

impl ConversationReader {
    pub async fn read_business_refs(&self) -> Result<ThreadBusinessRefs> {
        let guard = self.resources().await?;
        let resources = guard.as_ref().ok_or_else(cancelled)?;
        let current = tokio::select! { biased;
            _ = self.inner.cancel.cancelled() => return Err(cancelled()),
            current = resources.conversation.current_state() => current?,
        };
        let references =
            current.map_or_else(ThreadBusinessRefs::empty, |current| current.business_refs());
        self.ensure()?;
        Ok(references)
    }
    pub(super) fn new(
        id: String,
        scope: ChatScope,
        ceiling: u64,
        effect_cut: u64,
        slot: Arc<ObservationSlot>,
        runtime_closed: CancellationToken,
        resources: ReadResources,
    ) -> Self {
        let reader = Self {
            inner: Arc::new(ReadLease {
                thread_id: resources.thread.id.clone(),
                id,
                scope,
                ceiling,
                effect_cut,
                presentation_ceiling: OnceLock::new(),
                slot,
                cancel: runtime_closed.child_token(),
                runtime_closed,
                resync: AtomicBool::new(false),
                resources: RwLock::new(Some(resources)),
            }),
        };
        reader.inner.slot.register_reader(&reader);
        reader
    }
    pub fn thread_id(&self) -> &str {
        &self.inner.thread_id
    }
    pub fn subscription_id(&self) -> &str {
        &self.inner.id
    }
    pub(crate) fn ensure(&self) -> Result<()> {
        if self.inner.runtime_closed.is_cancelled() {
            self.invalidate();
            return Err(resync());
        }
        if self.inner.resync.load(Ordering::Acquire) {
            return Err(resync());
        }
        if self.inner.cancel.is_cancelled() {
            return Err(cancelled());
        }
        let identity_changed = self.inner.resources.try_read().ok().is_some_and(|guard| {
            guard.as_ref().is_some_and(|resources| {
                !resources
                    .conversation
                    .identity_matches(resources.database_id.as_deref())
            })
        });
        if identity_changed {
            self.invalidate();
            return Err(resync());
        }
        Ok(())
    }
    #[track_caller]
    pub(super) fn invalidate(&self) {
        let caller = std::panic::Location::caller();
        tracing::debug!(
            target: "conversation_continuity",
            subscription_id = self.subscription_id(),
            thread_id = self.thread_id(),
            source_file = caller.file(),
            source_line = caller.line(),
            "conversation reader invalidated"
        );
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
    pub(super) async fn resources(&self) -> Result<ReadPermit<'_>> {
        self.ensure()?;
        let guard = tokio::select! { biased; _=self.inner.cancel.cancelled()=>return Err(self.ensure().err().unwrap_or_else(cancelled)), read=self.inner.resources.read()=>read };
        let read = ReadPermit {
            lease: &self.inner,
            guard: Some(guard),
        };
        self.ensure()?;
        if let Some(resources) = read.as_ref() {
            tokio::select! { biased;
                _ = self.inner.cancel.cancelled() => return Err(cancelled()),
                ready = resources.conversation.wait_initialization() => ready?,
            }
            resources
                .recovery
                .ensure_thread_read_access(&resources.thread)?;
        } else {
            return Err(cancelled());
        }
        Ok(read)
    }
    fn cursor_binding(&self, resources: &ReadResources, kind: CursorKind) -> Cursor {
        Cursor {
            version: 2,
            index_version: COMPLETED_READ_INDEX_VERSION,
            thread_id: self.thread_id().into(),
            lease: self.inner.id.clone(),
            database: resources.database_id.clone(),
            scope: self.inner.scope.clone(),
            epoch: resources.session.epoch().as_str().into(),
            ceiling: self.inner.ceiling,
            kind,
        }
    }
    fn token(&self, resources: &ReadResources, kind: CursorKind) -> Result<String> {
        Ok(serde_json::to_string(
            &self.cursor_binding(resources, kind),
        )?)
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
                && cursor.version == 2
                && cursor.index_version == COMPLETED_READ_INDEX_VERSION
                && cursor.thread_id == self.thread_id()
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
    pub(super) async fn budget(&self) -> Result<JsonBudget> {
        let guard = self.resources().await?;
        let r = guard.as_ref().ok_or_else(cancelled)?;
        let token = self.token(r, CursorKind::Before { boundary: u64::MAX })?;
        Ok(JsonBudget::new(
            r.database_id.clone().unwrap_or_default(),
            token,
        ))
    }
    /// Bind once to the first presentation cut of this original read lease.
    pub(super) fn bind_presentation_ceiling(&self, ceiling: u64) -> Result<()> {
        self.ensure()?;
        let pinned = self.inner.presentation_ceiling.get_or_init(|| ceiling);
        ensure!(*pinned == ceiling, resync());
        Ok(())
    }
    pub(super) async fn display_boundary(&self, before: &str) -> Result<(u64, u64)> {
        let guard = self.resources().await?;
        let resources = guard.as_ref().ok_or_else(cancelled)?;
        let CursorKind::DisplayBefore {
            presentation_version: PRESENTATION_VERSION,
            ceiling,
            boundary,
        } = self.cursor(resources, before)?
        else {
            return Err(
                core::ChatError::InvalidArgument("not a display history cursor".into()).into(),
            );
        };
        ensure!(
            boundary > 0
                && boundary <= ceiling.saturating_add(1)
                && self.inner.presentation_ceiling.get() == Some(&ceiling),
            core::ChatError::InvalidArgument("invalid display history boundary".into())
        );
        Ok((ceiling, boundary))
    }
    pub(super) async fn presentation_tokens(&self) -> Result<PresentationTokens> {
        let guard = self.resources().await?;
        let resources = guard.as_ref().ok_or_else(cancelled)?;
        let ceiling = self
            .inner
            .presentation_ceiling
            .get()
            .copied()
            .ok_or_else(resync)?;
        Ok(PresentationTokens {
            binding: self.cursor_binding(
                resources,
                CursorKind::LiveDisplayBefore {
                    presentation_version: PRESENTATION_VERSION,
                    revision: 0,
                    boundary: 1,
                },
            ),
            ceiling,
        })
    }
    pub(super) async fn live_display_boundary(
        &self,
        before: &str,
        current_revision: u64,
    ) -> Result<u64> {
        let guard = self.resources().await?;
        let resources = guard.as_ref().ok_or_else(cancelled)?;
        let CursorKind::LiveDisplayBefore {
            presentation_version: PRESENTATION_VERSION,
            revision,
            boundary,
        } = self.cursor(resources, before)?
        else {
            return Err(
                core::ChatError::InvalidArgument("not a live display cursor".into()).into(),
            );
        };
        ensure!(revision == current_revision, core::ChatError::StaleContent);
        ensure!(
            boundary > 0,
            core::ChatError::InvalidArgument("invalid live display boundary".into())
        );
        Ok(boundary)
    }
    pub(super) async fn annotate_source_states(
        &self,
        entries: &mut [CompletedEntry],
        known: &[ChatSourceState],
        effect_cut: u64,
    ) -> Result<()> {
        let guard = self.resources().await?;
        let resources = guard.as_ref().ok_or_else(cancelled)?;
        let source = resources.conversation.current_conversation();
        let mut states = known.to_vec();
        if let Some(source) = source {
            states.extend(
                source
                    .current
                    .source_states()
                    .iter()
                    .filter(|state| !known.iter().any(|known| known.source == state.source))
                    .cloned(),
            );
        }
        tokio::select! { biased;
            _ = self.inner.cancel.cancelled() => return Err(cancelled()),
            result = annotate_sources(entries, &resources.history, &states, effect_cut) => result?,
        };
        self.ensure()
    }

    #[tracing::instrument(
        target = "conversation_work", level = "debug", name = "conversation_read",
        skip_all,
        fields(operation = "older", thread_id = self.thread_id(), lease_id = self.subscription_id(),
            trace_id, max_items = demand.max_items, max_bytes = demand.max_bytes)
    )]
    pub async fn load_older(&self, before: &str, demand: ReadDemand) -> Result<ChatBatch> {
        let trace_id = crate::studio::ids::new_id("read");
        tracing::Span::current().record("trace_id", &trace_id);
        let started = std::time::Instant::now();
        tracing::debug!(target: "conversation_work", "read started");
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
            self.token(r, CursorKind::Before { boundary: u64::MAX })?,
        )
        .for_scope(&self.inner.scope);
        let page = r
            .session
            .page(
                core::ChatPageRequest::before(
                    core::ChatCursor {
                        version: core::CHAT_CURSOR_VERSION,
                        index_version: core::CHAT_INDEX_VERSION,
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
        let mut batch = ChatBatch {
            placement: ChatPlacement::Prepend,
            entries: entries(page.items, &budget.database_id)?,
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
            from_seq: None,
            through_seq: self.inner.ceiling,
        };
        let source = r.conversation.current_conversation();
        annotate_sources(
            &mut batch.entries,
            &r.history,
            source
                .as_ref()
                .map_or(&[], |source| source.current.source_states().as_ref()),
            self.inner.effect_cut,
        )
        .await?;
        let batch = self.finish_batch(batch, demand)?;
        tracing::debug!(
            target: "conversation_work",
            returned = batch.entries.len(),
            elapsed_us = started.elapsed().as_micros() as u64,
            "read completed"
        );
        Ok(batch)
    }
    /// Header-first point lookup on the original completion collection. Queries
    /// keep their independent read permit and never wait for stream credit.
    pub async fn read_completed(
        &self,
        record_id: &str,
        demand: ReadDemand,
    ) -> Result<CompletedEntry> {
        let guard = self.resources().await?;
        let r = guard.as_ref().ok_or_else(cancelled)?;
        let budget = JsonBudget::new(r.database_id.clone().unwrap_or_default(), String::new());
        let item = tokio::select! { biased;
            _ = self.inner.cancel.cancelled() => return Err(cancelled()),
            result = r.session.read_item(core::ChatItemRequest {
                epoch: r.session.epoch(), item_id: record_id.into(),
                ceiling: None, demand: core_demand(demand)?,
            }, &budget) => result?,
        }
        .ok_or_else(|| core::ChatError::NotFound(record_id.into()))?;
        let mut entries = entries(vec![item], &budget.database_id)?;
        let current = r.conversation.current_conversation();
        annotate_sources(
            &mut entries,
            &r.history,
            current
                .as_ref()
                .map_or(&[], |source| source.current.source_states()),
            current.as_ref().map_or(self.inner.effect_cut, |source| {
                source.current.projection().source_effect_seq
            }),
        )
        .await?;
        self.ensure()?;
        let entry = entries.pop().expect("one point-read result");
        ensure!(
            serde_json::to_vec(&entry)?.len() <= demand.max_bytes as usize,
            core::ChatError::InvalidDemand("completed envelope exceeds demand".into())
        );
        Ok(entry)
    }
    pub(super) fn finish_batch(&self, batch: ChatBatch, demand: ReadDemand) -> Result<ChatBatch> {
        self.ensure()?;
        batch.validate_for(&self.inner.scope)?;
        ensure!(
            batch.entries.len() <= demand.max_items as usize,
            core::ChatError::InvalidDemand("chat entry count exceeds demand".into())
        );
        for entry in &batch.entries {
            let atom = &entry.atom;
            ensure!(
                atom.source_state
                    .as_ref()
                    .is_none_or(|state| state.source == atom.source),
                core::ChatError::Conflict(
                    "source annotation identity differs from its atom".into()
                )
            );
        }
        let encoded_bytes = batch.encoded_len()?;
        ensure!(
            encoded_bytes <= demand.max_bytes as usize,
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
            .conversation
            .current_conversation()
            .map(|source| source.current.clone());
        let entries = active
            .as_ref()
            .map(|state| {
                state
                    .contents()
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
        tracing::debug!(
            target: "conversation_work",
            thread_id = self.thread_id(),
            trace_id = self.subscription_id(),
            content_range_requests = 1,
            content_database_id = reference.database_id.as_str(),
            content_target = ?reference.target,
            content_offset = range.offset,
            content_max_bytes = range.max_bytes,
            "content range started"
        );
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
        let source = r.conversation.current_conversation();
        if let ContentTarget::Body { owner, key } = &reference.target {
            if matches!(owner, ContentOwner::DisplayObservation { .. }) {
                let content_key = core::ChatContentKey {
                    owner: crate::studio::conversation_identity::content_owner_key(owner)?,
                    key: key.clone(),
                };
                let content = source.as_ref().and_then(|source| {
                    source
                        .presentation
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .observation_content(&content_key)
                });
                if let Some(content) = content {
                    let bytes = content.data.range(range.offset, range.max_bytes as usize)?;
                    self.ensure()?;
                    return Ok(ContentWindow {
                        offset: range.offset,
                        bytes: bytes.as_bytes().to_vec(),
                        generation: content.descriptor.generation.to_string(),
                        available_through: content.descriptor.byte_length,
                        sealed: true,
                    });
                }
                // A frozen observation never borrows the latest current atom. The
                // original Session/storage path below reads this exact sealed namespace.
            }
            // Cold Plan bytes must come from their original sealed content
            // store. Reconstructing the document from checkpoint state here
            // would hide missing/corrupt saved content blocks.
            let cold = if source.is_none()
                && matches!(owner, ContentOwner::Current { domain, .. } if domain == "collection:interactions")
            {
                r.conversation.current_state().await?
            } else {
                None
            };
            let current = source
                .as_ref()
                .map(|source| &source.current)
                .or(cold.as_ref());
            let content_key = core::ChatContentKey {
                owner: crate::studio::conversation_identity::content_owner_key(owner)?,
                key: key.clone(),
            };
            if let Some(content) = current.and_then(|current| current.contents().get(&content_key))
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
                let state = current;
                if let Some(collection) = domain.strip_prefix("collection:")
                    && let Some(state) = state
                {
                    ensure!(
                        state
                            .projection()
                            .interactions
                            .as_ref()
                            .is_some_and(|reference| reference.collection == collection
                                && reference.revision == *revision),
                        core::ChatError::StaleContent
                    );
                    let entry = state
                        .entries()
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
        let core_reference = match &reference.target {
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
                reference: core_reference,
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
        let current = r.conversation.current_state().await?.ok_or_else(stale)?;
        let encode = |after| {
            self.token(
                r,
                CursorKind::Current {
                    reference: reference.clone(),
                    after,
                },
            )
        };
        let page = current_page(&current, reference, after.as_deref(), demand, encode)?;
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
        let changed = Some(r.conversation.content_changes());
        Ok(ContentWatch {
            observation: ReadObservation::new(self.clone(), changed),
            reference: reference.clone(),
            range,
            last: None,
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
    observation: ReadObservation,
    reference: ContentRef,
    range: ContentRange,
    last: Option<WindowStamp>,
}
impl ContentWatch {
    /// Capture before placing the watch behind a receive mutex, so close can wake that receiver.
    pub fn cancellation_token(&self) -> CancellationToken {
        self.observation.cancellation_token()
    }
    pub fn request_close(&self) {
        self.observation.request_close();
    }
    pub async fn recv(&mut self) -> Result<Option<ContentWindow>> {
        loop {
            if !self.observation.next().await? {
                return Ok(None);
            }
            let window = self
                .observation
                .query(
                    self.observation
                        .reader
                        .read_content(&self.reference, self.range.clone()),
                )
                .await?;
            let stamp = WindowStamp::from(&window);
            if self.last.as_ref() != Some(&stamp) {
                if window.sealed {
                    self.observation.seal();
                }
                self.last = Some(stamp);
                return Ok(Some(window));
            }
        }
    }
    pub async fn close(&mut self) -> Result<()> {
        self.request_close();
        self.observation.seal();
        self.last = None;
        Ok(())
    }
}

/// Shared pull-observation lifecycle for content and display-member windows.
/// The query itself still borrows the original reader's resources/qualification.
pub(super) struct ReadObservation {
    pub(super) reader: ConversationReader,
    changed: Option<watch::Receiver<u64>>,
    /// Fixed at registration; dropping a live watch during close/seal cannot grant this status.
    fixed_snapshot: bool,
    initial: bool,
    cancel: CancellationToken,
}

impl ReadObservation {
    /// Register the domain watch before construction/capturing the first query window.
    pub(super) fn new(reader: ConversationReader, changed: Option<watch::Receiver<u64>>) -> Self {
        let cancel = reader.inner.cancel.child_token();
        let fixed_snapshot = changed.is_none();
        Self {
            reader,
            changed,
            fixed_snapshot,
            initial: true,
            cancel,
        }
    }
    pub(super) fn cancellation_token(&self) -> CancellationToken {
        self.cancel.clone()
    }
    pub(super) fn is_fixed_snapshot(&self) -> bool {
        self.fixed_snapshot
    }
    pub(super) fn request_close(&self) {
        self.cancel.cancel();
    }
    pub(super) fn seal(&mut self) {
        self.changed = None;
    }
    fn cancelled(&self) -> anyhow::Error {
        self.reader.ensure().err().unwrap_or_else(cancelled)
    }
    /// Local close cancels this view's read without revoking sibling views or execution.
    pub(super) async fn query<T>(
        &self,
        query: impl std::future::Future<Output = Result<T>>,
    ) -> Result<T> {
        self.reader.ensure()?;
        let value = tokio::select! { biased;
            _ = self.cancel.cancelled() => return Err(self.cancelled()),
            value = query => value?,
        };
        self.reader.ensure()?;
        ensure!(!self.cancel.is_cancelled(), self.cancelled());
        Ok(value)
    }
    /// `&mut self` enforces one in-flight next. No resource/receive/credit lock is held here.
    pub(super) async fn next(&mut self) -> Result<bool> {
        self.reader.ensure()?;
        ensure!(!self.cancel.is_cancelled(), self.cancelled());
        if self.initial {
            self.initial = false;
            return Ok(true);
        }
        let Some(changed) = self.changed.as_mut() else {
            return Ok(false);
        };
        tokio::select! { biased;
            _ = self.cancel.cancelled() => return Err(self.cancelled()),
            result = changed.changed() => ensure!(result.is_ok(), resync()),
        }
        self.reader.ensure()?;
        Ok(true)
    }
}

pub(super) struct JsonBudget {
    pub database_id: String,
    main: bool,
    deferred_only: bool,
    fixed: usize,
    manifest_item: Option<String>,
    manifest_cursor: Option<Cursor>,
}
impl JsonBudget {
    pub(super) fn new(database_id: String, continuation: String) -> Self {
        let batch = ChatBatch {
            placement: ChatPlacement::Prepend,
            entries: Vec::new(),
            before: Some(continuation),
            from_seq: None,
            through_seq: i64::MAX as u64,
        };
        Self {
            database_id,
            main: false,
            deferred_only: false,
            fixed: serde_json::to_vec(&batch).map_or(usize::MAX, |bytes| bytes.len()),
            manifest_item: None,
            manifest_cursor: None,
        }
    }
    pub(super) fn for_scope(mut self, scope: &ChatScope) -> Self {
        self.main = matches!(scope, ChatScope::Main);
        self
    }
    pub(super) fn headers_only(mut self) -> Self {
        self.deferred_only = true;
        self
    }
}
impl core::ChatBudget for JsonBudget {
    fn allow_inline(&self, header: &core::ChatItemHeader) -> bool {
        !self.deferred_only
            && (!self.main || matches!(header.read_hint, core::ChatReadHint::Single))
    }
    fn fixed_bytes(&self) -> usize {
        self.fixed
    }
    fn item_bytes(&self, header: &core::ChatItemHeader, mode: core::PayloadMode) -> usize {
        if self.main && mode == core::PayloadMode::Inline {
            let Ok(atom) = serde_json::from_slice::<ChatAtom>(&header.metadata) else {
                return usize::MAX;
            };
            if crate::studio::runtime::chat_item::native_read_class_v1(&header.query_class, &atom)
                .main_presentation
                != MainPresentation::Single
            {
                return usize::MAX;
            }
        }
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
        let base = completed_entry(header, payload)
            .and_then(|mut entry| {
                entry.atom.source_state = Some(ChatSourceState {
                    source: entry.atom.source.clone(),
                    lifecycle: ChatSourceLifecycle::Ended {
                        outcome: ChatTerminalOutcome::Transferred,
                    },
                    started: Some(ChatFactPosition {
                        effect_seq: u64::MAX,
                        suborder: u32::MAX,
                    }),
                    ended: Some(ChatFactPosition {
                        effect_seq: u64::MAX,
                        suborder: u32::MAX,
                    }),
                });
                Ok(serde_json::to_vec(&entry)?)
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
pub(super) async fn annotate_sources(
    entries: &mut [CompletedEntry],
    history: &HistoryStore,
    known: &[ChatSourceState],
    effect_cut: u64,
) -> Result<()> {
    let ids = entries
        .iter()
        .map(|entry| entry.atom.source.clone())
        .collect::<std::collections::BTreeSet<_>>();
    let mut states = Vec::with_capacity(ids.len());
    let mut missing = Vec::new();
    for id in ids {
        if let Some(state) = known.iter().find(|state| state.source == id) {
            // Legacy observed lifecycle without fact positions cannot be projected backwards
            // from a newer owner cut. Its original as-of storage evidence remains authoritative.
            if (state.started.is_none() && state.ended.is_none())
                || (state.started.is_none()
                    && state.ended.is_some_and(|at| at.effect_seq > effect_cut))
            {
                missing.push(id);
                continue;
            }
            let mut state = state.clone();
            if state.ended.is_some_and(|at| at.effect_seq > effect_cut) {
                state.ended = None;
                state.lifecycle = if state.started.is_some_and(|at| at.effect_seq <= effect_cut) {
                    ChatSourceLifecycle::Active
                } else {
                    ChatSourceLifecycle::Unknown
                };
            }
            if state.started.is_some_and(|at| at.effect_seq > effect_cut) {
                state.started = None;
                state.lifecycle = ChatSourceLifecycle::Unknown;
            }
            states.push(state);
        } else {
            missing.push(id);
        }
    }
    states.extend(history.conversation_sources(&missing, effect_cut).await?);
    annotate_atoms(entries, &states)
}

pub(super) fn annotate_atoms(
    entries: &mut [CompletedEntry],
    states: &[ChatSourceState],
) -> Result<()> {
    let mut by_source = std::collections::BTreeMap::new();
    for state in states {
        if let Some(old) = by_source.insert(&state.source, state) {
            ensure!(
                old == state,
                core::ChatError::Conflict("conflicting source states in one read cut".into())
            );
        }
    }
    for entry in entries {
        let atom = &mut entry.atom;
        ensure!(
            atom.source_state
                .as_ref()
                .is_none_or(|state| state.source == atom.source),
            core::ChatError::Conflict("source annotation identity differs from its atom".into())
        );
        let state = by_source.get(&atom.source).ok_or_else(|| {
            core::ChatError::Conflict("read cut has no state for the atom's source identity".into())
        })?;
        atom.source_state = Some((*state).clone());
    }
    Ok(())
}

pub(super) fn completed_entry(
    header: &core::ChatItemHeader,
    payload: PayloadData,
) -> Result<CompletedEntry> {
    let mut atom: ChatAtom = serde_json::from_slice(&header.metadata)?;
    ensure!(
        atom.completion_item_id
            .as_deref()
            .is_none_or(|id| id == header.item_id)
            && atom
                .completion_seq
                .is_none_or(|seq| seq == header.append_seq)
            && atom.payload.is_none()
            && atom.source_state.is_none()
            && matches!(atom.lifecycle, ChatAtomLifecycle::Terminal { .. }),
        core::ChatError::Conflict("completion metadata differs from its frozen header".into())
    );
    atom.completion_item_id = Some(header.item_id.clone());
    atom.completion_seq = Some(header.append_seq);
    atom.payload = Some(payload);
    let class = crate::studio::runtime::chat_item::native_read_class_v1(&header.query_class, &atom);
    ensure!(
        class.hint == header.read_hint,
        core::ChatError::Conflict("native read class differs from completion index".into())
    );
    Ok(CompletedEntry {
        record_id: header.item_id.clone(),
        completion_seq: header.append_seq,
        run: header.run.map(|run| CompletionRunPosition {
            start_seq: run.start_seq,
            ordinal: run.ordinal,
        }),
        main_presentation: class.main_presentation,
        atom,
    })
}
pub(super) fn entries(
    items: Vec<core::ChatPageItem>,
    database_id: &str,
) -> Result<Vec<CompletedEntry>> {
    items
        .into_iter()
        .map(|item| {
            let payload = match item.payload {
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
            };
            completed_entry(&item.header, payload)
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

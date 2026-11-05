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
    pub projection_generation: String,
    generation: watch::Receiver<String>,
    member_window: std::sync::Mutex<std::collections::BTreeMap<String, ChatSourceId>>,
    pub id: String,
    pub thread_id: String,
    pub scope: ChatScope,
    pub ceiling: u64,
    pub effect_cut: u64,
    pub slot: Arc<ObservationSlot>,
    pub epoch: u64,
    cancel: CancellationToken,
    resources: RwLock<Option<ReadResources>>,
    resync: AtomicBool,
}
pub(super) struct ReadResources {
    pub projection_generation: String,
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
    projection_generation: String,
    projection_version: u32,
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
        effect_cut: u64,
        slot: Arc<ObservationSlot>,
        epoch: u64,
        resources: ReadResources,
    ) -> Self {
        let reader = Self {
            inner: Arc::new(ReadLease {
                projection_generation: resources.projection_generation.clone(),
                generation: resources.history.timeline_generation_changes(),
                member_window: std::sync::Mutex::new(Default::default()),
                thread_id: resources.thread.id.clone(),
                id,
                scope,
                ceiling,
                effect_cut,
                slot,
                epoch,
                cancel: CancellationToken::new(),
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
    pub(super) fn select_member_window(&self, entries: &[ChatEntry]) {
        if !matches!(self.inner.scope, ChatScope::GroupMembers { .. }) {
            return;
        }
        let mut window = self
            .inner
            .member_window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        // Loaded terminal members are immutable and need no resident interest.
        // Keep only opened active facts (already bounded by the original current
        // admission budget), including an earlier page still waiting on a part.
        for entry in entries {
            if let ChatEntry::Atom(atom) = entry {
                if matches!(atom.lifecycle, ChatAtomLifecycle::Active { .. }) {
                    window.insert(atom.id.clone(), atom.source.clone());
                } else {
                    window.remove(&atom.id);
                }
            }
        }
    }
    pub(super) fn observes_member(&self, id: &str, order: u64) -> bool {
        // The initial page freezes only the older-page boundary. New members
        // of this same group still belong to its live append tail, including a
        // member first observed at its reliable terminal handoff. Older hidden
        // members must not be materialized by an unrelated update.
        order >= self.inner.ceiling
            || self
                .inner
                .member_window
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .contains_key(id)
    }
    pub(super) fn observes_source(&self, source: &ChatSourceId) -> bool {
        self.inner
            .member_window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .values()
            .any(|value| value == source)
    }
    pub(crate) fn ensure(&self) -> Result<()> {
        if self.inner.resync.load(Ordering::Acquire) {
            return Err(resync());
        }
        if self.inner.cancel.is_cancelled() {
            return Err(cancelled());
        }
        if *self.inner.generation.borrow() != self.inner.projection_generation
            || !self.inner.slot.is_current(self.inner.epoch)
        {
            self.invalidate();
            return Err(resync());
        }
        Ok(())
    }
    pub(super) fn invalidate(&self) {
        self.inner
            .member_window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clear();
        self.inner.resync.store(true, Ordering::Release);
        self.inner.cancel.cancel();
        if let Ok(mut resources) = self.inner.resources.try_write() {
            resources.take();
        }
    }
    pub fn request_close(&self) {
        self.inner
            .member_window
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clear();
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
            projection_generation: self.inner.projection_generation.clone(),
            projection_version: TIMELINE_PROJECTION_VERSION,
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
            cursor.projection_generation == self.inner.projection_generation
                && cursor.lease == self.inner.id
                && cursor.projection_version == TIMELINE_PROJECTION_VERSION
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
    /// Crate-local consumer proof at an already-delivered current cut. Uses the
    /// original owner metadata, or its durable source row after retention; never
    /// advances the read cut, activates execution, flushes or reads a body.
    pub(crate) async fn source_ended_at(&self, source: &ChatSourceId, cut: u64) -> Result<bool> {
        let guard = self.resources().await?;
        let resources = guard.as_ref().ok_or_else(cancelled)?;
        let retained = resources
            .source
            .as_ref()
            .and_then(|owner| owner.current_conversation());
        if let Some(state) = retained.as_ref().and_then(|current| {
            current
                .current
                .source_states()
                .iter()
                .find(|state| &state.source == source)
        }) && state.ended.is_some_and(|at| at.effect_seq <= cut)
            && matches!(state.lifecycle, ChatSourceLifecycle::Ended { .. })
        {
            self.ensure()?;
            return Ok(true);
        }
        let states = resources
            .history
            .conversation_sources(std::slice::from_ref(source), cut)
            .await?;
        self.ensure()?;
        Ok(states
            .iter()
            .any(|state| matches!(state.lifecycle, ChatSourceLifecycle::Ended { .. })))
    }
    pub(super) async fn annotate_source_states(
        &self,
        entries: &mut [ChatEntry],
        known: &[ChatSourceState],
        effect_cut: u64,
    ) -> Result<()> {
        let guard = self.resources().await?;
        let resources = guard.as_ref().ok_or_else(cancelled)?;
        let source = resources
            .source
            .as_ref()
            .and_then(|source| source.current_conversation());
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
        if !matches!(self.inner.scope, ChatScope::Children { .. }) {
            return self.display_older(r, boundary, demand).await;
        }
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
            current: None,
        };
        let source = r
            .source
            .as_ref()
            .and_then(|source| source.current_conversation());
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
    async fn display_older(
        &self,
        resources: &ReadResources,
        boundary: u64,
        demand: ReadDemand,
    ) -> Result<ChatBatch> {
        let token = self.token(
            resources,
            CursorKind::Before {
                boundary: i64::MAX as u64,
            },
        )?;
        let budget = JsonBudget::new(
            resources.database_id.clone().unwrap_or_default(),
            None,
            token,
        );
        let page = tokio::select! { biased;
            _ = self.inner.cancel.cancelled() => return Err(cancelled()),
            page = resources.history.timeline_page(&self.inner.scope, Some(boundary), self.inner.ceiling,
                self.inner.effect_cut, demand, core::ChatBudget::fixed_bytes(&budget)) => page?,
        };
        let mut batch = ChatBatch {
            placement: ChatPlacement::Prepend,
            entries: page.entries,
            before: page
                .before
                .map(|boundary| self.token(resources, CursorKind::Before { boundary }))
                .transpose()?,
            current: None,
        };
        annotate_sources(
            &mut batch.entries,
            &resources.history,
            &[],
            self.inner.effect_cut,
        )
        .await?;
        self.select_member_window(&batch.entries);
        self.inline_timeline_payloads(&mut batch, demand).await?;
        self.finish_batch(batch, demand)
    }

    /// Resolve frame-budgeted Text/Status and explicitly opened member envelopes
    /// through their original content owner. WorkGroup headers never read members.
    pub(super) async fn inline_timeline_payloads(
        &self,
        batch: &mut ChatBatch,
        demand: ReadDemand,
    ) -> Result<()> {
        use crate::studio::storage::history::conversation::timeline;
        if matches!(self.inner.scope, ChatScope::Children { .. }) {
            return Ok(());
        }
        let mut used = batch.encoded_len()?;
        let indices: Vec<_> =
            if batch.placement == ChatPlacement::Prepend || batch.placement == ChatPlacement::Set {
                (0..batch.entries.len()).rev().collect()
            } else {
                (0..batch.entries.len()).collect()
            };
        for index in indices {
            if !matches!(
                (&self.inner.scope, &batch.entries[index]),
                (ChatScope::Main, ChatEntry::Item(_))
                    | (ChatScope::GroupMembers { .. }, ChatEntry::Atom(_))
            ) {
                continue;
            }
            let Some(inline) = timeline::inline_entry_bytes(&batch.entries[index])? else {
                continue;
            };
            let original_bytes = timeline::entry_bytes(&batch.entries[index])?;
            if used.saturating_sub(original_bytes).saturating_add(inline)
                > demand.max_bytes as usize
            {
                continue;
            }
            let (payload, content_item_id) = match &batch.entries[index] {
                ChatEntry::Item(item) => (&item.payload, item.content_item_id.as_deref()),
                ChatEntry::Atom(atom) => (&atom.payload, atom.completion_item_id.as_deref()),
                ChatEntry::Source(_) => unreachable!(),
            };
            let Some(
                original @ PayloadData::Deferred {
                    reference,
                    byte_length,
                },
            ) = payload
            else {
                unreachable!()
            };
            ensure!(
                matches!(&reference.target,ContentTarget::ItemPayload {item_id}
                if content_item_id==Some(item_id.as_str())),
                core::ChatError::StaleContent
            );
            let original = original.clone();
            let window = self
                .read_content(
                    reference,
                    ContentRange {
                        offset: 0,
                        max_bytes: (*byte_length as u32).max(1),
                    },
                )
                .await?;
            ensure!(
                window.sealed
                    && window.available_through == *byte_length
                    && window.bytes.len() as u64 == *byte_length,
                core::ChatError::Conflict("frozen timeline payload differs from its header".into())
            );
            let payload = match &mut batch.entries[index] {
                ChatEntry::Item(item) => &mut item.payload,
                ChatEntry::Atom(atom) => &mut atom.payload,
                ChatEntry::Source(_) => unreachable!(),
            };
            *payload = Some(PayloadData::Inline {
                bytes: window.bytes,
            });
            let encoded = batch.encoded_len()?;
            if encoded > demand.max_bytes as usize {
                let payload = match &mut batch.entries[index] {
                    ChatEntry::Item(item) => &mut item.payload,
                    ChatEntry::Atom(atom) => &mut atom.payload,
                    ChatEntry::Source(_) => unreachable!(),
                };
                *payload = Some(original);
            } else {
                used = encoded;
            }
        }
        self.ensure()
    }

    pub(super) fn finish_batch(&self, batch: ChatBatch, demand: ReadDemand) -> Result<ChatBatch> {
        self.ensure()?;
        batch.validate_for(&self.inner.scope)?;
        ensure!(
            batch.entries.len() <= demand.max_items as usize,
            core::ChatError::InvalidDemand("chat entry count exceeds demand".into())
        );
        for entry in &batch.entries {
            if let ChatEntry::Atom(atom) = entry {
                ensure!(
                    atom.source_state
                        .as_ref()
                        .is_none_or(|state| state.source == atom.source),
                    core::ChatError::Conflict(
                        "source annotation identity differs from its atom".into()
                    )
                );
            }
        }
        let encoded_bytes = batch.encoded_len()?;
        ensure!(
            encoded_bytes <= demand.max_bytes as usize,
            core::ChatError::InvalidDemand("encoded chat batch exceeds demand".into())
        );
        if tracing::enabled!(target: "conversation_work", tracing::Level::DEBUG) {
            let (atom_entries, inline_payload_bytes) =
                batch
                    .entries
                    .iter()
                    .fold((0_usize, 0_usize), |counts, entry| {
                        if let ChatEntry::Atom(atom) = entry {
                            let bytes = match &atom.payload {
                                Some(PayloadData::Inline { bytes }) => bytes.len(),
                                _ => 0,
                            };
                            (counts.0 + 1, counts.1 + bytes)
                        } else {
                            counts
                        }
                    });
            // This is a validated product batch, not an ACK or a disk-IO measurement.
            // Reuse the mandatory budget encoding; diagnostics never read a body.
            tracing::debug!(
                target: "conversation_work",
                thread_id = self.thread_id(),
                lease_id = self.subscription_id(),
                placement = ?batch.placement,
                atom_entries,
                source_entries = batch.entries.len() - atom_entries,
                batch_encoded_bytes = encoded_bytes,
                inline_payload_bytes,
                has_before = batch.before.is_some(),
                "bounded chat batch validated"
            );
        }
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
                .and_then(|source| source.current.contents().get(&content_key))
            {
                let content = content.content();
                let bytes = content.data.range(range.offset, range.max_bytes as usize)?;
                tracing::debug!(
                    target: "conversation_work",
                    thread_id = self.thread_id(), trace_id = self.subscription_id(),
                    content_bytes = bytes.as_bytes().len(),
                    content_database_id = reference.database_id.as_str(),
                    content_target = ?reference.target,
                    content_offset = range.offset,
                    "content range completed"
                );
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
                            .projection()
                            .collections
                            .iter()
                            .any(|reference| reference.collection == collection
                                && reference.revision == *revision),
                        core::ChatError::StaleContent
                    );
                    let entry = state
                        .entries()
                        .get(&(collection.into(), id.clone()))
                        .ok_or_else(stale)?;
                    let data = core::ContentData::Bytes(entry.payload.clone());
                    let bytes = data.range(range.offset, range.max_bytes as usize)?;
                    tracing::debug!(
                        target: "conversation_work",
                        thread_id = self.thread_id(), trace_id = self.subscription_id(),
                        content_bytes = bytes.as_bytes().len(),
                        content_database_id = reference.database_id.as_str(),
                        content_target = ?reference.target,
                        content_offset = range.offset,
                        "content range completed"
                    );
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
        tracing::debug!(
            target: "conversation_work",
            thread_id = self.thread_id(), trace_id = self.subscription_id(),
            content_bytes = window.bytes.as_bytes().len(),
            content_database_id = reference.database_id.as_str(),
            content_target = ?reference.target,
            content_offset = range.offset,
            "content range completed"
        );
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
            generation_changed: self.inner.generation.clone(),
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
    generation_changed: watch::Receiver<String>,
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
                    _=self.slot_changed.changed()=>{self.reader.invalidate();return Err(resync());},
                    _=self.generation_changed.changed()=>{self.reader.invalidate();return Err(resync());},
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
            entries: Vec::new(),
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
        let base = completion_atom(header, payload)
            .and_then(|mut atom| {
                atom.source_state = Some(ChatSourceState {
                    source: atom.source.clone(),
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
                // A read-cut annotation is part of the single Atom's item budget, never another row.
                Ok(serde_json::to_vec(&ChatEntry::Atom(Box::new(atom)))?)
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
    entries: &mut [ChatEntry],
    history: &HistoryStore,
    known: &[ChatSourceState],
    effect_cut: u64,
) -> Result<()> {
    let ids = entries
        .iter()
        .filter_map(|entry| match entry {
            ChatEntry::Atom(atom) => Some(atom.source.clone()),
            _ => None,
        })
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

pub(super) fn annotate_atoms(entries: &mut [ChatEntry], states: &[ChatSourceState]) -> Result<()> {
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
        let atom = match entry {
            ChatEntry::Atom(atom) => atom,
            // Timeline items already carry the product projection's identity,
            // summary and terminal outcome. Atomic source annotations belong
            // only to member/Children entries.
            ChatEntry::Item(_) => continue,
            ChatEntry::Source(_) => {
                return Err(core::ChatError::Conflict(
                    "ordinary page contains a source event".into(),
                )
                .into());
            }
        };
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

fn completion_atom(header: &core::ChatItemHeader, payload: PayloadData) -> Result<ChatAtom> {
    let mut atom: ChatAtom = serde_json::from_slice(&header.metadata)?;
    ensure!(
        atom.completion_item_id.as_deref() == Some(header.item_id.as_str())
            && atom.payload.is_none()
            && atom.completion_seq.is_none()
            && atom.source_state.is_none(),
        "completion metadata does not name its frozen item"
    );
    atom.completion_seq = Some(header.append_seq);
    atom.payload = Some(payload);
    Ok(atom)
}

pub(super) fn entries(items: Vec<core::ChatPageItem>, database_id: &str) -> Result<Vec<ChatEntry>> {
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
            Ok(ChatEntry::Atom(Box::new(completion_atom(
                &item.header,
                payload,
            )?)))
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
            .projection()
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
    for (_, entry) in state.by_position().range((lower, upper)) {
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

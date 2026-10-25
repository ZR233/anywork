//! 会话内容源：事实准入、无状态页、有界尾部订阅与按身份详情。
//!
//! 会话只拥有事实与有界预览，不拥有可见行、阅读位置或视口几何。因此这里没有窗口注册表、焦点、
//! 双向翻页或“展开整条”的操作回执；缓存退出只释放预览，不删除事实，也不产生尾部删除通知。
//!
//! 锁与等待的形状固定为：
//!
//! 1. 锁内只捕获有界内存候选与版本水位，绝不跨 `.await` 持锁；
//! 2. 存储读取在锁外完成；
//! 3. 提交前在同一次时间线临界区内把读取期间发布的新 revision、保存确认与终态事实合回候选；
//! 4. 通知只是唤醒信号（最新值），不是内容事件日志：内容帧由订阅者相对自己的交付基线各算一次。

use std::{
    collections::{BTreeMap, BTreeSet, VecDeque},
    fmt,
    sync::{Arc, Mutex, MutexGuard, Weak},
};

use tokio::sync::watch;

use crate::chat::{
    ChatCursor, ChatError, ChatHistory, ChatItem, ChatItemMetadata, ChatLifecycle,
    history::ErasedChatHistory,
    item::same_content,
    metadata::{item_metadata_fingerprint, metadata_fingerprint},
    read::memory_item,
};
use crate::model::ContentBlock;

/// 热预览允许保留的条目数上限。
pub(crate) const RECENT_ITEMS: usize = 100;
/// 热预览允许保留的字节上限。
pub(crate) const RECENT_BYTES: usize = 8 * 1024 * 1024;
/// 终态身份标记的上限；每个标记只是一对数字，远小于它保护的正文。
const TERMINAL_ITEMS: usize = 4096;
/// 连续性元数据的条目上限。
///
/// 每个条目只记录触及的身份与其发布水位，不持有正文或静态结构。订阅者落后超过该窗口就无法再
/// 证明连续，必须显式重同步，而不是猜一个补丁。
const CHANGE_LOG_ENTRIES: usize = 512;
/// 单次发布最多记录的身份数；超出即标记不可证明，订阅者按重同步处理。
const MAX_LOGGED_IDENTITIES: usize = 256;

/// 本次发布触及的一个身份，以及它是内容事实还是真实删除。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ChangedIdentity {
    pub(crate) item_id: Arc<str>,
    pub(crate) removed: bool,
    published: Option<PublishedRevision>,
}

impl ChangedIdentity {
    fn item(item: &ChatItem, metadata_fingerprint: Option<[u8; 32]>) -> Self {
        Self {
            item_id: Arc::from(item.item_id.as_str()),
            removed: false,
            published: Some(PublishedRevision {
                order: item.order,
                revision: item.revision,
                saved: item.saved,
                lifecycle: item.lifecycle,
                metadata_fingerprint,
            }),
        }
    }

    pub(crate) fn removed(item_id: impl Into<Arc<str>>) -> Self {
        Self {
            item_id: item_id.into(),
            removed: true,
            published: None,
        }
    }
}

/// A publication's small progress proof, not a second readable item. Once a newer item leaves the
/// cache, an older retained effect or cold row cannot answer for it merely because its ID matches.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct PublishedRevision {
    order: u64,
    revision: u64,
    saved: bool,
    lifecycle: ChatLifecycle,
    /// A shell/index proof, not recoverable metadata. A save acknowledgement has no new shell:
    /// its retained effect can be older than a same-revision preview already published meanwhile.
    metadata_fingerprint: Option<[u8; 32]>,
}

/// 一次发布在连续性元数据里的记录。
#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct ChangeEntry {
    pub(crate) version: u64,
    pub(crate) identities: Vec<ChangedIdentity>,
    /// 身份列表被截断：这次发布无法被完整表达，订阅者必须重同步。
    pub(crate) overflow: bool,
}

#[derive(Clone, Copy)]
struct OrderReservation {
    order: u64,
    /// None until a speculative identity has actually been published.
    preview_revision: Option<u64>,
    preview_terminal: bool,
}

#[derive(Default)]
pub(crate) struct TimelineState {
    pub(crate) recent: VecDeque<ChatItem>,
    recent_bytes: usize,
    // The reliable effect owner is elsewhere. These references remain until the exact
    // revision is committed, even if the corresponding item leaves every preview cache.
    unsaved: BTreeMap<String, ChatItem>,
    pub(crate) unsaved_previews: BTreeMap<String, ChatItem>,
    unsaved_order: BTreeMap<u64, String>,
    // Large speculative previews can be read while the model is still streaming. They
    // are not reliable history. Each entry shares the producer's immutable content block; the number
    // of live identities is bounded upstream and the entries are released on terminal admission.
    active_previews: BTreeMap<String, ChatItem>,
    allocated: BTreeMap<String, OrderReservation>,
    allocated_order: BTreeMap<u64, String>,
    // Terminal identities recalled after their item leaves the recent cache, bounded to `TERMINAL_ITEMS`.
    // Each entry keeps the stable order and terminal revision, so a late preview for a committed
    // identity that was cache-evicted is still rejected instead of resurrecting a body.
    terminal: BTreeMap<String, (u64, u64)>,
    // The same markers indexed by order for bounded eviction: the smallest order is dropped first.
    terminal_order: BTreeMap<u64, String>,
    // Monotonic order watermark: the greatest order whose terminal marker was evicted from
    // `terminal`. Order slots are allocated strictly increasing and never reused, so any
    // speculative publication at or below this floor without a live reservation is a late update.
    terminal_floor: u64,
    highest_order: u64,
    pub(crate) version: u64,
    /// Monotone waterline of the greatest version produced by a frame boundary that must be delivered
    /// without coalescing (a new identity, an execution terminal admission, a save acknowledgement, a
    /// field removal or an authoritative replacement). A waiter compares it against its own delivered
    /// version to tell a pending boundary (`urgent > seen`) from ordinary already-started text.
    pub(crate) urgent: u64,
    /// 有限的连续性元数据：最近若干次发布各自触及的身份。
    pub(crate) log: VecDeque<ChangeEntry>,
}

/// The minimal product-agnostic progress fact one session publishes to its observers.
///
/// `version` is the monotone content version that a patch's `from`/`to` refer to. `urgent` is the
/// boundary waterline described on [`TimelineState::urgent`]. Both are plain numbers, so an observer
/// can decide readiness outside every lock while inspecting neither a body nor a diff.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct ChatProgress {
    pub(crate) version: u64,
    pub(crate) urgent: u64,
}

/// Advances the content version, folds in the boundary waterline and records the touched identities.
fn bump_version(
    state: &mut TimelineState,
    urgent: bool,
    identities: Vec<ChangedIdentity>,
) -> ChatProgress {
    state.version = state.version.wrapping_add(1);
    if urgent {
        state.urgent = state.version;
    }
    let overflow = identities.len() > MAX_LOGGED_IDENTITIES;
    let mut identities = identities;
    identities.truncate(MAX_LOGGED_IDENTITIES);
    state.log.push_back(ChangeEntry {
        version: state.version,
        identities,
        overflow,
    });
    while state.log.len() > CHANGE_LOG_ENTRIES {
        state.log.pop_front();
    }
    ChatProgress {
        version: state.version,
        urgent: state.urgent,
    }
}

/// The identities this session really withdrew strictly after `since`.
///
/// Withdrawals are recorded in the same bounded publication log the tail diff uses, so no second fact
/// source, tombstone store or schema is introduced: a read that captured candidate references before
/// its storage step can ask what the authority released while it awaited.
///
/// **Any** real removal inside the window invalidates the references a read had already captured. A
/// later content publication of the same identity does *not* clear it here, and that is deliberate: the
/// captured reference is the body from *before* the removal, so it is stale even when a new order and a
/// new revision were admitted under the same identity string. New facts do not depend on this set to
/// become visible — they enter every read through the current page candidates read after storage, which
/// is why this is not a tombstone and never needs eviction. Cache eviction, save hand-off and terminal
/// admission are not withdrawals and never appear here, so released speculation stays separable from
/// the facts that must survive.
///
/// # Errors
/// [`ChatError::ReadInvalidated`] when the range is no longer covered by the bounded log — trimmed, or
/// containing a publication whose identity list overflowed. Continuity cannot be proven then, and the
/// caller retries rather than guessing a deletion or a resurrection.
pub(crate) fn withdrawals_since(
    state: &TimelineState,
    since: u64,
) -> Result<BTreeSet<Arc<str>>, ChatError> {
    let mut withdrawn = BTreeSet::new();
    if state.version <= since {
        return Ok(withdrawn);
    }
    let Some(first) = state.log.front() else {
        return Err(ChatError::ReadInvalidated);
    };
    let Some(last) = state.log.back() else {
        return Err(ChatError::ReadInvalidated);
    };
    // Every publication logs exactly one entry for its own version, so a range is provable only when
    // the log still starts at or before the first version after `since` and ends at the current one.
    if first.version > since.saturating_add(1) || last.version != state.version {
        return Err(ChatError::ReadInvalidated);
    }
    for entry in &state.log {
        if entry.version <= since {
            continue;
        }
        if entry.overflow {
            return Err(ChatError::ReadInvalidated);
        }
        for identity in &entry.identities {
            if identity.removed {
                // The identities are shared with the log, so a withdrawal set costs reference counts,
                // not a copy of the content or of the pending range.
                withdrawn.insert(identity.item_id.clone());
            }
        }
    }
    Ok(withdrawn)
}

pub(crate) struct SessionInner {
    pub(crate) history: Arc<dyn ErasedChatHistory>,
    order_seed: tokio::sync::OnceCell<u64>,
    pub(crate) timeline: Mutex<TimelineState>,
    pub(crate) changed: watch::Sender<ChatProgress>,
}

/// Shared timeline data for one session. Reading content neither starts a model nor transfers the
/// ownership of an uncommitted effect to a subscriber.
#[derive(Clone)]
pub struct Session(pub(crate) Arc<SessionInner>);

/// A registry reference that does not keep an idle history connection open.
#[derive(Debug, Clone)]
pub struct WeakSession(Weak<SessionInner>);

impl WeakSession {
    pub fn upgrade(&self) -> Option<Session> {
        self.0.upgrade().map(Session)
    }
}

impl fmt::Debug for Session {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Session").finish_non_exhaustive()
    }
}

impl Session {
    pub fn new(history: impl ChatHistory) -> Self {
        let (changed, _) = watch::channel(ChatProgress {
            version: 0,
            urgent: 0,
        });
        Self(Arc::new(SessionInner {
            history: Arc::new(history),
            order_seed: tokio::sync::OnceCell::new(),
            timeline: Mutex::new(TimelineState::default()),
            changed,
        }))
    }

    pub fn downgrade(&self) -> WeakSession {
        WeakSession(Arc::downgrade(&self.0))
    }

    /// Runs `read` under the timeline lock. The closure must not await or perform storage IO.
    pub(crate) fn with_timeline<R>(&self, read: impl FnOnce(&TimelineState) -> R) -> R {
        let state = self.lock_timeline();
        read(&state)
    }

    pub(crate) fn lock_timeline(&self) -> MutexGuard<'_, TimelineState> {
        self.0
            .timeline
            .lock()
            .unwrap_or_else(|error| error.into_inner())
    }

    /// Returns an order already assigned to an item, without allocating a new one.
    pub fn assigned_order(&self, item_id: &str) -> Option<u64> {
        order_for_identity(&self.lock_timeline(), item_id)
    }

    /// Whether this session already holds one identity's terminal fact.
    ///
    /// True once the identity is terminal (or remembered by its terminal marker after its body left
    /// the preview cache), and never cleared by a save acknowledgement. It stays false while an
    /// acknowledged identity still runs (a background tool result keeps streaming). A producer uses
    /// it to decide whether a late speculative frame is new content or a stale update to a row
    /// durable history owns: the position and body of a committed identity are final, so a preview
    /// for it is ignored instead of replacing — and later releasing — committed content.
    pub fn is_committed(&self, item_id: &str) -> bool {
        committed_identity(&self.lock_timeline(), item_id)
    }

    /// The content revision this session currently holds for one identity, if it is resident.
    ///
    /// A projection that re-seeds itself asks this to recover the baseline of an in-flight preview
    /// the session already owns; it is the session's own fact, never a second content cache.
    pub fn resident_revision(&self, item_id: &str) -> Option<u64> {
        memory_item(&self.lock_timeline(), item_id).map(|item| item.revision)
    }

    /// Reads the durable order ceiling once while activating a producer. This does not
    /// create a history database or start the model; after it succeeds the synchronous
    /// admission path can allocate orders without storage IO.
    pub async fn initialize_order_allocator(&self) -> Result<(), ChatError> {
        self.0
            .order_seed
            .get_or_try_init(|| self.0.history.latest_allocated_order())
            .await?;
        Ok(())
    }

    /// Allocates an order during synchronous effect admission. The producer must first
    /// initialize this session's allocator; repeated identities retain their order.
    pub fn reserve_order_in_memory(&self, item_id: &str) -> Result<u64, ChatError> {
        let seed = *self
            .0
            .order_seed
            .get()
            .ok_or(ChatError::OrderNotInitialized)?;
        let mut state = self.lock_timeline();
        if let Some(order) = order_for_identity(&state, item_id) {
            return Ok(order);
        }
        let order = state
            .highest_order
            .max(seed)
            .checked_add(1)
            .filter(|order| *order <= i64::MAX as u64)
            .ok_or(ChatError::OrderExhausted)?;
        state.highest_order = order;
        state.allocated.insert(
            item_id.to_owned(),
            OrderReservation {
                order,
                preview_revision: None,
                preview_terminal: false,
            },
        );
        state.allocated_order.insert(order, item_id.to_owned());
        Ok(order)
    }

    /// Reserves a session-local order from asynchronous clients. The first call reads
    /// the persisted ceiling; subsequent calls allocate entirely in memory.
    pub async fn reserve_order(&self, item_id: &str) -> Result<u64, ChatError> {
        {
            let state = self.lock_timeline();
            if let Some(order) = order_for_identity(&state, item_id) {
                return Ok(order);
            }
        }
        self.initialize_order_allocator().await?;
        self.reserve_order_in_memory(item_id)
    }

    /// Abandons a reservation whose item never became visible. The number is not reused.
    /// Published previews require explicit withdrawal, even after their body was cache-evicted.
    pub fn release_unpublished_order(&self, item_id: &str) {
        let mut state = self.lock_timeline();
        // A committed identity is never "unpublished": its order belongs to the durable row, so
        // releasing it here would let a later preview claim a placement the history already owns.
        if committed_content(&state, item_id)
            || state
                .allocated
                .get(item_id)
                .is_some_and(|slot| slot.preview_revision.is_some())
        {
            return;
        }
        if let Some(slot) = state.allocated.remove(item_id) {
            state.allocated_order.remove(&slot.order);
        }
    }

    /// Updates an item in place. A duplicate revision is accepted only with identical data.
    /// The caller retains its immutable effect until the history writer confirms it.
    pub fn publish(&self, item: ChatItem) -> Result<(), ChatError> {
        self.publish_inner(item, true)
    }

    /// Live provider previews have no accepted history effect yet. They are visible
    /// while the request runs, but cannot claim reliable-unsaved ownership.
    pub fn publish_preview(&self, item: ChatItem) -> Result<(), ChatError> {
        self.publish_inner(item, false)
    }

    pub fn drop_preview(&self, item_id: &str) {
        self.drop_previews_matching(|candidate| candidate == item_id);
    }

    /// Releases speculative identities after the host has committed the terminal effect.
    /// Never call this during a failed write: a retry needs the same reserved orders.
    pub fn drop_previews_with_prefix(&self, prefix: &str) {
        self.drop_previews_matching(|candidate| candidate.starts_with(prefix));
    }

    /// Releases speculative identities after a commit, except the identities it just confirmed.
    ///
    /// The host writes exactly one batch per commit and knows which identities that transaction
    /// saved. Excluding them makes the release correct even when the session itself never saw the
    /// terminal publication — an effect the owner installed behind is folded into the snapshot
    /// without a live publish — so a confirmed body and its position are never released as if they
    /// were still speculative.
    pub fn drop_previews_with_prefix_except<'a>(
        &self,
        prefix: &str,
        confirmed: impl IntoIterator<Item = &'a str>,
    ) {
        let confirmed: BTreeSet<&str> = confirmed.into_iter().collect();
        self.drop_previews_matching(|candidate| {
            candidate.starts_with(prefix) && !confirmed.contains(candidate)
        });
    }

    fn drop_previews_matching(&self, matches: impl Fn(&str) -> bool) {
        let mut state = self.lock_timeline();
        // Releasing speculative identities may only ever remove a row this session never terminated.
        // The writer releases an attempt's previews right after it confirms the batch it just saved,
        // and a slow producer can publish one more revision of that same identity between the
        // confirmation and this release. Dropping it would erase committed content from every
        // reader and discard its position even though durable history owns that exact identity. The
        // terminal fact therefore protects an identity here exactly as it protects it from a late
        // preview.
        let mut candidates: BTreeSet<String> = state.allocated.keys().cloned().collect();
        candidates.extend(state.recent.iter().map(|item| item.item_id.clone()));
        let abandoned: BTreeSet<String> = candidates
            .into_iter()
            .filter(|id| {
                matches(id) && !state.unsaved.contains_key(id) && !committed_content(&state, id)
            })
            .collect();
        if abandoned.is_empty() {
            return;
        }
        // Only an identity that is visible right now is a deletion a reader can observe; a merely
        // reserved identity never reached anyone.
        let visible: Vec<ChangedIdentity> = abandoned
            .iter()
            .filter(|id| {
                state
                    .allocated
                    .get(*id)
                    .is_some_and(|slot| slot.preview_revision.is_some())
                    || state.recent.iter().any(|item| &item.item_id == *id)
            })
            .map(|id| ChangedIdentity::removed(Arc::<str>::from(id.as_str())))
            .collect();
        for id in &abandoned {
            if let Some(slot) = state.allocated.remove(id) {
                state.allocated_order.remove(&slot.order);
            }
            state.active_previews.remove(id);
        }
        state
            .recent
            .retain(|item| !abandoned.contains(&item.item_id));
        state.recent_bytes = state.recent.iter().map(ChatItem::resident_bytes).sum();
        if !visible.is_empty() {
            let progress = bump_version(&mut state, true, visible);
            self.0.changed.send_replace(progress);
        }
    }

    fn publish_inner(&self, item: ChatItem, reliable: bool) -> Result<(), ChatError> {
        // A reliable publication owns the uncommitted effect (whether or not the identity is already
        // terminal), so it must carry complete content rather than a bounded preview. A terminal item
        // with a partial body is rejected here too, without waiting for the writer.
        if reliable && !item.saved && !item.is_complete() {
            return Err(ChatError::Conflict(item.item_id));
        }
        // The host codec may bound or rewrite the item, so the visible copy is built before the
        // timeline lock: a concurrent publication never waits behind codec work, and no database or
        // codec call runs under the lock.
        let visible = self.0.history.bounded(&item)?;
        // Metadata hashing is bounded structure work, not body hashing, and happens outside the
        // timeline lock. Same-revision shell/index changes remain legal admission facts.
        let published = ChangedIdentity::item(&item, Some(item_metadata_fingerprint(&item)));
        let mut state = self.lock_timeline();
        if item.order == 0 || item.order > i64::MAX as u64 {
            return Err(ChatError::Conflict(item.item_id));
        }
        // A speculative preview never reopens or overwrites an identity this session already holds as
        // terminal: the committed body, its position and its terminal revision are final. That
        // decision belongs to the two branches that already own it below — the resident row and the
        // terminal marker — so a late preview keeps reporting the same typed conflict the public
        // contract has always reported, and, because it never replaces the committed row, the writer's
        // later preview release cannot erase that row either.
        if state
            .unsaved_order
            .get(&item.order)
            .is_some_and(|existing| existing != &item.item_id)
            || state
                .allocated_order
                .get(&item.order)
                .is_some_and(|existing| existing != &item.item_id)
            || state
                .terminal_order
                .get(&item.order)
                .is_some_and(|existing| existing != &item.item_id)
            || state
                .allocated
                .get(&item.item_id)
                .is_some_and(|slot| slot.order != item.order)
            || state
                .recent
                .iter()
                .any(|existing| existing.order == item.order && existing.item_id != item.item_id)
        {
            return Err(ChatError::Conflict(item.item_id));
        }
        if state.allocated.get(&item.item_id).is_some_and(|slot| {
            slot.preview_terminal
                && (item.is_streaming()
                    || (!reliable
                        && slot
                            .preview_revision
                            .is_some_and(|revision| item.revision > revision)))
        }) {
            return Err(ChatError::Conflict(item.item_id));
        }
        if state
            .allocated
            .get(&item.item_id)
            .and_then(|slot| slot.preview_revision)
            .is_some_and(|revision| revision > item.revision)
        {
            return Ok(());
        }
        let resident = state
            .unsaved
            .get(&item.item_id)
            .or_else(|| state.recent.iter().find(|old| old.item_id == item.item_id));
        // Whether this admission is a frame boundary that must not wait for the coalescing window.
        // A pure append-only advance of an already-known identity is ordinary text; everything else
        // (a new identity, a terminal admission, a save receipt, new static metadata, a removed or
        // authoritatively replaced field) is a boundary a reader must see at once.
        let boundary = publication_is_boundary(resident, &item);
        if let Some(previous) = resident {
            if previous.order != item.order
                || (!previous.turn_id.is_empty()
                    && previous.turn_id != item.turn_id
                    && !((item.saved && !previous.saved)
                        || (item.is_terminal() && previous.is_streaming())
                        || (reliable && item.is_terminal() && item.revision > previous.revision)))
            {
                return Err(ChatError::Conflict(item.item_id));
            }
            if previous.revision > item.revision {
                return Ok(());
            }
            // A streaming preview is never newer content for a terminal identity: the producer cannot
            // advance it again. A strictly older revision was a stale duplicate and was ignored above,
            // but a preview at the terminal revision or beyond is a late update and is rejected instead
            // of replacing — and, through the writer's later release, erasing — the committed row.
            if !reliable && item.is_streaming() && previous.is_terminal() {
                return Err(ChatError::Conflict(item.item_id));
            }
            if previous.revision == item.revision {
                if ((previous.is_complete()
                    && item.is_complete()
                    && !same_content(previous, &item))
                    || previous.turn_id != item.turn_id)
                    && (reliable || previous.saved || state.unsaved.contains_key(&item.item_id))
                    && !((item.saved && !previous.saved)
                        || (item.is_terminal() && previous.is_streaming()))
                {
                    return Err(ChatError::Conflict(item.item_id));
                }
                if previous.saved && !item.saved {
                    return Ok(());
                }
                if previous.is_terminal() && item.is_streaming() {
                    return Ok(());
                }
            }
        } else if let Some(&(terminal_order, terminal_revision)) = state.terminal.get(&item.item_id)
        {
            if item.order != terminal_order {
                return Err(ChatError::Conflict(item.item_id));
            }
            // The terminal identity already left the preview cache, so memory holds no body to compare
            // against. An older revision is a stale duplicate and is ignored; a preview at the
            // terminal revision or beyond cannot resurrect a stale body. Reliable terminal updates
            // still belong to the authoritative publisher and durable writer.
            if item.revision < terminal_revision {
                return Ok(());
            }
            // New reliable terminal facts (input binding, resource supplements) remain legal
            // after eviction. Content completion prohibits previews, not authoritative revisions.
            if item.is_streaming() || (!reliable && item.revision > terminal_revision) {
                return Err(ChatError::Conflict(item.item_id));
            }
        } else if item.order <= state.terminal_floor
            && !state.allocated.contains_key(&item.item_id)
            && !(reliable && item.is_terminal())
        {
            // The marker for this order was evicted, but an order slot is allocated strictly
            // increasing and never reused for another identity. A speculative publication below the
            // evicted-terminal floor without a live reservation can therefore only be a late update
            // for an identity this session already committed, so it is rejected rather than
            // resurrecting a stale body. Durable history stays the ultimate owner of the content.
            return Err(ChatError::Conflict(item.item_id));
        }
        state.highest_order = state.highest_order.max(item.order);
        state.active_previews.remove(&item.item_id);
        if item.is_terminal() {
            remember_terminal(&mut state, &item.item_id, item.order, item.revision);
        }
        // A speculative preview keeps its complete in-memory content so a reliable effect can still
        // show the whole in-flight body. The entries share the producer's content block, so retaining
        // them does not keep a second full copy, and they are released on terminal admission.
        if !reliable && item.is_streaming() && !visible.is_complete() {
            state
                .active_previews
                .insert(item.item_id.clone(), item.clone());
        }
        if reliable || item.saved {
            state.allocated.remove(&item.item_id);
            state.allocated_order.remove(&item.order);
        } else {
            // Reuse the reservation's identity/order ownership as the continuity
            // frontier. Evicting a preview body must not erase its existence.
            state.allocated.insert(
                item.item_id.clone(),
                OrderReservation {
                    order: item.order,
                    preview_revision: Some(item.revision),
                    preview_terminal: item.is_terminal(),
                },
            );
            state
                .allocated_order
                .insert(item.order, item.item_id.clone());
        }
        state.recent.retain(|old| old.item_id != item.item_id);
        state.recent_bytes = state.recent.iter().map(ChatItem::resident_bytes).sum();
        // The reliable uncommitted owner is retained until the exact revision is acknowledged, so a
        // terminal item that is not yet saved still keeps its whole body for the writer.
        if !item.saved && reliable {
            state.unsaved_order.insert(item.order, item.item_id.clone());
            state.unsaved.insert(item.item_id.clone(), item.clone());
            state
                .unsaved_previews
                .insert(item.item_id.clone(), visible.clone());
        } else if state
            .unsaved
            .get(&item.item_id)
            .is_some_and(|previous| previous.revision == item.revision)
        {
            state.unsaved_order.remove(&item.order);
            state.unsaved.remove(&item.item_id);
            state.unsaved_previews.remove(&item.item_id);
        }
        state.recent_bytes = state.recent_bytes.saturating_add(visible.resident_bytes());
        state.recent.push_back(visible);
        state
            .recent
            .make_contiguous()
            .sort_by_key(|item| item.order);
        while state.recent.len() > RECENT_ITEMS || state.recent_bytes > RECENT_BYTES {
            let Some(old) = state.recent.pop_front() else {
                break;
            };
            state.recent_bytes -= old.resident_bytes();
        }
        // A cache eviction is not a deletion: it only releases this session's preview. The reader
        // keeps whatever it was already delivered and never receives a `Remove` for it.
        let identities = vec![published];
        let progress = bump_version(&mut state, boundary, identities);
        self.0.changed.send_replace(progress);
        Ok(())
    }

    /// An older writer acknowledgement cannot mark a newer revision as durable.
    ///
    /// The history writer only confirms the exact identity and revision of a batch the Thread's live
    /// projection already published, so the confirmation this consumes is the durable receipt of a
    /// body the session holds. This flips the save watermark `saved` only: it never advances the
    /// execution lifecycle, never releases an identity that is still producing content, and never
    /// rejects a later revision. A terminal item stays terminal whether or not it is acknowledged,
    /// and a streaming item stays streaming after acknowledgement.
    pub fn confirm_saved(&self, item_id: &str, revision: u64) {
        let mut state = self.lock_timeline();
        let mut confirmed = None;
        if state
            .unsaved
            .get(item_id)
            .is_some_and(|item| item.revision == revision)
            && let Some(mut item) = state.unsaved.remove(item_id)
        {
            state.unsaved_order.remove(&item.order);
            state.unsaved_previews.remove(item_id);
            item.saved = true;
            confirmed = Some(ChangedIdentity::item(&item, None));
        }
        if let Some(item) = state
            .recent
            .iter_mut()
            .find(|item| item.item_id == item_id && item.revision == revision && !item.saved)
        {
            item.saved = true;
            confirmed = Some(ChangedIdentity::item(item, None));
        }
        if let Some(confirmed) = confirmed {
            // A save acknowledgement is a frame boundary, not ordinary started text.
            let progress = bump_version(&mut state, true, vec![confirmed]);
            self.0.changed.send_replace(progress);
        }
    }

    /// Seeds the preview cache with rows a page just proved, without ever overwriting resident facts.
    /// Seeds bounded previews read from storage into the hot preview cache.
    ///
    /// `since` is the source version the read captured its candidates with. Seeding is not a plain
    /// "insert what is missing": an identity the authority withdrew while the read awaited must not be
    /// written back — that is exactly how a released speculative preview would return as a ghost. The
    /// same critical section proves the window, excludes every withdrawn identity and adopts the
    /// survivors, so no withdrawal can land between "validated" and "seeded".
    ///
    /// # Errors
    /// [`ChatError::ReadInvalidated`] when the withdrawal window is no longer provable. Nothing is
    /// seeded in that case, so a retry starts from the same state instead of a half-filled cache.
    pub(crate) fn hydrate(&self, since: u64, items: &[ChatItem]) -> Result<(), ChatError> {
        if items.is_empty() {
            return Ok(());
        }
        let mut state = self.lock_timeline();
        let withdrawn = withdrawals_since(&state, since)?;
        for item in items {
            if withdrawn.contains(item.item_id.as_str())
                || state.unsaved.contains_key(&item.item_id)
                || state.recent.iter().any(|old| old.item_id == item.item_id)
            {
                continue;
            }
            state.recent_bytes = state.recent_bytes.saturating_add(item.resident_bytes());
            state.recent.push_back(item.clone());
        }
        state
            .recent
            .make_contiguous()
            .sort_by_key(|item| item.order);
        while state.recent.len() > RECENT_ITEMS || state.recent_bytes > RECENT_BYTES {
            let Some(old) = state.recent.pop_front() else {
                break;
            };
            state.recent_bytes -= old.resident_bytes();
        }
        Ok(())
    }
}

/// The complete in-memory copy of an in-flight identity, if the session still holds one.
///
/// Reliable effects keep their whole item until their revision is committed, and speculative
/// previews keep theirs until terminal admission; both share the producer's content block.
pub(crate) fn resident_item(state: &TimelineState, item_id: &str) -> Option<ChatItem> {
    state
        .unsaved
        .get(item_id)
        .or_else(|| state.active_previews.get(item_id))
        .cloned()
}

/// Borrow candidates from the existing owners without retaining their content blocks. A saved
/// publication may be newer than an older still-pending reliable effect, so readers reconcile all
/// owners rather than assuming the first resident copy is the newest one.
pub(crate) fn memory_items<'a>(
    state: &'a TimelineState,
    item_id: &'a str,
) -> impl Iterator<Item = &'a ChatItem> {
    state
        .unsaved
        .get(item_id)
        .into_iter()
        .chain(state.active_previews.get(item_id))
        .chain(
            state
                .recent
                .iter()
                .filter(move |item| item.item_id == item_id),
        )
}

/// Check a readable candidate against the same bounded progress facts that admission and tail
/// continuity already own. Reservations without a published preview are not item existence facts;
/// a historical removal is not a durable tombstone. No missing shell is reconstructed from numbers.
pub(crate) fn validate_metadata(
    state: &TimelineState,
    item_id: &str,
    metadata: Option<&ChatItemMetadata>,
) -> Result<(), ChatError> {
    let preview = state.allocated.get(item_id).and_then(|slot| {
        slot.preview_revision.map(|revision| PublishedRevision {
            order: slot.order,
            revision,
            saved: false,
            lifecycle: if slot.preview_terminal {
                ChatLifecycle::Terminal
            } else {
                ChatLifecycle::Streaming
            },
            metadata_fingerprint: None,
        })
    });
    let terminal = state
        .terminal
        .get(item_id)
        .map(|&(order, revision)| PublishedRevision {
            order,
            revision,
            saved: false,
            lifecycle: ChatLifecycle::Terminal,
            metadata_fingerprint: None,
        });
    let published = state
        .log
        .iter()
        .rev()
        .flat_map(|entry| &entry.identities)
        .filter(|identity| identity.item_id.as_ref() == item_id)
        .take_while(|identity| !identity.removed)
        .filter_map(|identity| identity.published);
    let mut same_revision = false;
    let mut latest_shell = None;
    for fact in preview.into_iter().chain(terminal).chain(published) {
        if metadata.is_none_or(|item| {
            item.order != fact.order
                || item.revision < fact.revision
                || item.lifecycle < fact.lifecycle
                || (item.revision == fact.revision && fact.saved && !item.saved)
        }) {
            return Err(ChatError::ReadInvalidated);
        }
        same_revision |= metadata.is_some_and(|item| item.revision == fact.revision);
        // Publications are visited newest first. A late save ACK contributes numeric progress,
        // never an old shell, and earlier same-revision shells must not reject the latest one.
        if latest_shell.is_none() {
            latest_shell = fact
                .metadata_fingerprint
                .map(|fingerprint| (fact.revision, fingerprint));
        }
    }
    if same_revision
        && !metadata.is_some_and(|item| {
            latest_shell.is_some_and(|(revision, fingerprint)| {
                item.revision == revision && metadata_fingerprint(item) == fingerprint
            })
        })
    {
        // Numeric markers survive cache eviction, but cannot prove Turn/meta/field facts. Missing
        // or expired shell proof is unreadable, not permission to reuse a same-revision cold shell.
        return Err(ChatError::ReadInvalidated);
    }
    Ok(())
}

/// Highest published speculative identity that this read cannot materialize.
/// Unpublished reservations are not content. No body is retained by this proof.
pub(crate) fn unreadable_preview_boundary(
    state: &TimelineState,
    candidates: &[ChatItem],
    before: Option<&ChatCursor>,
) -> Option<ChatCursor> {
    if state.allocated_order.is_empty() {
        return None;
    }
    let available: BTreeMap<_, _> = candidates
        .iter()
        .map(|item| {
            (
                item.item_id.as_str(),
                (item.order, item.revision, item.is_terminal()),
            )
        })
        .collect();
    let ceiling = before.map_or(u64::MAX, |boundary| boundary.order);
    state
        .allocated_order
        .range(..=ceiling)
        .rev()
        .find_map(|(&order, id)| {
            let slot = state.allocated.get(id)?;
            let revision = slot.preview_revision?;
            let boundary = ChatCursor::new(order, id.clone());
            if before.is_some_and(|before| boundary >= *before)
                || available.get(id.as_str()).is_some_and(
                    |&(candidate_order, candidate_revision, terminal)| {
                        candidate_order == order
                            && candidate_revision >= revision
                            && (!slot.preview_terminal || terminal)
                    },
                )
            {
                return None;
            }
            Some(boundary)
        })
}

pub(crate) fn order_for_identity(state: &TimelineState, item_id: &str) -> Option<u64> {
    state
        .allocated
        .get(item_id)
        .map(|slot| slot.order)
        .or_else(|| state.unsaved.get(item_id).map(|item| item.order))
        .or_else(|| {
            state
                .recent
                .iter()
                .find(|item| item.item_id == item_id)
                .map(|item| item.order)
        })
}

/// Whether one identity already reached its terminal fact in this session.
///
/// A committed identity is recalled by its terminal marker after the body left the preview cache, or
/// is still resident as a terminal item: once true, the body and its position are owned by durable
/// history and no speculative frame may replace them. A save acknowledgement is deliberately *not*
/// part of it — an acknowledged identity that is still running (a background tool result) keeps
/// streaming its content, and only its terminal fact makes a late preview stale.
fn committed_identity(state: &TimelineState, item_id: &str) -> bool {
    state.terminal.contains_key(item_id)
        || state
            .unsaved
            .get(item_id)
            .is_some_and(ChatItem::is_terminal)
        || state
            .recent
            .iter()
            .any(|item| item.item_id == item_id && item.is_terminal())
}

/// Whether one identity's row in this session must never be released as a stale preview.
///
/// It is terminal (committed content) or acknowledged (`saved`): the writer already confirmed that
/// exact revision durable, so the row is history rather than a speculative frame — even while a
/// running tool keeps streaming newer revisions of the same identity.
fn committed_content(state: &TimelineState, item_id: &str) -> bool {
    committed_identity(state, item_id)
        || state.unsaved.get(item_id).is_some_and(|item| item.saved)
        || state
            .recent
            .iter()
            .any(|item| item.item_id == item_id && item.saved)
}

/// Recalls one terminal identity, evicting the smallest-order marker past `TERMINAL_ITEMS`.
///
/// Each marker keeps the order and terminal revision, so it is tiny compared with the body it
/// protects. Eviction folds the dropped order into the session's `terminal_floor`, so an evicted
/// identity is still rejected by the order watermark instead of needing an unbounded tombstone.
fn remember_terminal(state: &mut TimelineState, item_id: &str, order: u64, revision: u64) {
    state.terminal.insert(item_id.to_owned(), (order, revision));
    state.terminal_order.insert(order, item_id.to_owned());
    while state.terminal_order.len() > TERMINAL_ITEMS {
        let Some(evicted_order) = state.terminal_order.keys().next().copied() else {
            break;
        };
        let Some(evicted_id) = state.terminal_order.remove(&evicted_order) else {
            break;
        };
        state.terminal.remove(&evicted_id);
        state.terminal_floor = state.terminal_floor.max(evicted_order);
    }
}

/// Whether admitting `next` over `previous` is a frame boundary that must not wait for coalescing.
///
/// A boundary is a new identity (no resident predecessor), an execution-terminal admission, a save
/// receipt, a change to the static metadata or turn binding, or a field that was removed or
/// authoritatively replaced rather than appended. A pure append-only advance of an already-known
/// identity is ordinary already-started text and may be merged. The comparison is by shared block
/// lineage, so deciding the priority never materializes a body.
fn publication_is_boundary(previous: Option<&ChatItem>, next: &ChatItem) -> bool {
    let Some(previous) = previous else {
        return true;
    };
    if previous.item_id != next.item_id
        || previous.order != next.order
        || previous.lifecycle != next.lifecycle
        || previous.saved != next.saved
        || previous.turn_id != next.turn_id
        || previous.meta != next.meta
        || previous.fields.len() != next.fields.len()
    {
        return true;
    }
    next.fields.iter().any(|(field, preview)| {
        let Some(previous_preview) = previous.fields.get(field) else {
            return true;
        };
        !Arc::ptr_eq(&previous_preview.block, &preview.block)
            && ContentBlock::appended_since(&preview.block, &previous_preview.block).is_none()
    })
}

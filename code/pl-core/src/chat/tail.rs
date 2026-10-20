//! 有界尾部订阅：一致基线、连续补丁与显式重同步。
//!
//! 一条订阅只持有三类有界状态：捕获的初始基线、自己**已交付**条目的连续性副本，以及两个版本水位。
//! 它不重放全部 token、不保留订阅以来的事件日志，也不随历史增长。若变化已经越过可证明连续的范围
//! （连续性窗口溢出、身份已不在热预览也无法从本地副本表达），就返回带原因和最新小页的
//! [`ChatTailResync`] 式重同步，而不是交付一个猜出来的补丁或静默跳过。
//!
//! 通知只是唤醒信号：普通正文合并进一个固定合帧窗口，首字、终态、保存确认、字段删除、权威替换与
//! 真实删除立即就绪；合帧 deadline 一旦锚定就不被后续增量重启。

use std::{
    collections::{BTreeMap, BTreeSet, VecDeque},
    sync::Arc,
    time::Duration,
};

use tokio::sync::watch;

use crate::{
    chat::{
        ChatError, ChatField, ChatItem, ChatLifecycle, Session,
        read::tail_candidates,
        session::{ChangeEntry, ChangedIdentity, ChatProgress, RECENT_BYTES, RECENT_ITEMS},
    },
    model::ContentBlock,
};

/// Bound on how long ordinary already-started text is merged into one delivered frame.
///
/// The deadline is anchored when a waiter first observes an ordinary coalesced change and is **not**
/// restarted by a later delta, so a running stream is delivered at a fixed cadence rather than being
/// pushed out token by token. Boundaries (a first byte, an execution terminal admission, a save
/// acknowledgement, a field removal or an authoritative replacement) never wait for it.
const COALESCE_WINDOW: Duration = Duration::from_millis(33);

/// Whether a delivered frame is an immediate boundary or merged ordinary text.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChatUpdatePriority {
    /// A boundary that must be applied without any coalescing wait.
    Immediate,
    /// Ordinary already-started text merged into one frame.
    Coalesced,
}

/// Typed change for one content field, derived from the shared block lineage.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FieldChange {
    /// The field is gone from the item; the consumer drops its copy.
    Remove,
    /// The content is unchanged while the item revision or bounded status advanced. A consumer must
    /// still commit the enclosing item revision, so a version-only frame is never an empty patch.
    Unchanged,
    /// The field still extends the consumer's baseline; these bytes are new.
    Append(String),
    /// The field no longer extends the consumer's baseline; use this whole authoritative block.
    Replace(Arc<ContentBlock>),
}

/// One field delta inside a batched [`TailChange::UpdateItem`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FieldUpdate {
    pub field: ChatField,
    pub change: FieldChange,
    /// 该字段完整正文的 UTF-8 字节数；预览被截断时仍是原文长度。
    ///
    /// 消费者据此知道自己手上的预览之外还有多少正文，不必读取整段全文再自行推断。
    pub total_bytes: u64,
    /// 本次交付的预览字节数。
    pub preview_bytes: u64,
}

/// One change of a delivered patch, expressed by identity rather than by visible index.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TailChange {
    /// An authoritative item the subscription had not delivered yet.
    Add { item: ChatItem },
    /// Every content and state change of one identity, committed in a single step.
    ///
    /// The item's content version advances at most once per delivered change: a consumer validates
    /// its local item against one `expected_revision`, applies any updated `meta` shell and every
    /// field delta, and only then commits `revision`, `saved` and `lifecycle`. A save acknowledgement
    /// at the same revision is a legal update that carries no new content revision.
    UpdateItem {
        item_id: String,
        expected_revision: u64,
        revision: u64,
        /// 条目级省略量：所有字段完整长度与本次预览字节数之差的合计。
        omitted_bytes: u64,
        /// Save watermark of the item after this change, independent of `revision` and `lifecycle`.
        saved: bool,
        /// Execution terminal fact of the item after this change.
        lifecycle: ChatLifecycle,
        /// Updated static metadata when `previous.meta != next.meta`; `None` when unchanged.
        meta: Option<Arc<[u8]>>,
        fields: Vec<FieldUpdate>,
    },
    /// A real removal: the identity no longer exists. A preview-cache eviction is never one.
    Remove { item_id: String },
}

/// One continuous patch relative to the subscription's own delivered version.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatTailPatch {
    /// The subscription version this patch continues from; always the receiver's delivered version.
    pub from: u64,
    /// The subscription version after this patch; always greater than `from`.
    pub to: u64,
    pub changes: Vec<TailChange>,
    pub priority: ChatUpdatePriority,
}

/// Why a subscription could not continue with a continuous patch.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ChatResyncReason {
    /// The receiver fell behind the bounded continuity window.
    Lagging,
    /// A change touched an identity the receiver's copy can no longer be reconciled with.
    Unavailable,
}

/// The latest small page captured for one observation.
///
/// `version` is the subscription's own content version at capture time; it is independent of any
/// item revision and of any persistence watermark.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatTailBaseline {
    pub version: u64,
    pub items: Vec<ChatItem>,
    /// 请求更旧一页时要原样回传的严格边界；只有 `has_older` 为真时给出。
    pub before: Option<crate::chat::ChatCursor>,
    /// 是否真的还有更旧内容：来自同次一致读取的真实存在性证明，不凭条数猜 EOF。
    pub has_older: bool,
}

impl ChatTailBaseline {
    /// An empty baseline, used once an observation released its content.
    pub fn empty() -> Self {
        Self {
            version: 0,
            items: Vec::new(),
            before: None,
            has_older: false,
        }
    }

    /// Reports whether this baseline carries no content (a closed or empty observation).
    pub fn is_empty(&self) -> bool {
        self.items.is_empty()
    }
}

/// One delivered observation frame: a continuous patch, or an explicit new baseline.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChatTailUpdate {
    Patch(ChatTailPatch),
    /// The changes since the receiver's baseline cannot be expressed continuously.
    ///
    /// The receiver re-baselines from the latest small page instead of stitching disjoint facts.
    Resync {
        reason: ChatResyncReason,
        baseline: ChatTailBaseline,
    },
}

/// One bounded tail observation over a session.
///
/// The type is the single-consumer guarantee: [`ChatTail::next`] takes `&mut self`, so two pending
/// reads on the same observation are impossible by construction. It holds a strong content reference
/// to the session — not an execution-owner pin — so idle retirement of the owner is unaffected, and
/// closing one observation stops neither the producer nor the history writer.
///
/// The observation owns exactly one content baseline at a time. The first frame is **handed over
/// once** by [`ChatTail::initial`], after which only the bounded continuity copy (at most
/// [`RECENT_ITEMS`] items and [`RECENT_BYTES`] of preview bytes) is retained; a resynchronization
/// replaces it outright instead of keeping a second newest page.
pub struct ChatTail {
    session: Option<Session>,
    watch: watch::Receiver<ChatProgress>,
    /// The first frame, until the consumer takes it once.
    initial: Option<ChatTailBaseline>,
    /// The items this observation actually delivered, kept as its bounded continuity copy.
    retained: BTreeMap<String, ChatItem>,
    /// The version this observation has delivered; every patch `from` refers to it.
    delivered: u64,
    /// The highest version this observation has already looked at, whether or not it produced a
    /// frame. It is the level-triggered wake watermark, so a skipped version never re-fires the wait.
    seen: u64,
}

/// What one synchronous critical section resolved the pending version into.
enum Frame {
    /// A continuous patch relative to this observation's delivered version.
    Patch(ChatTailPatch),
    /// Nothing this observation can deliver; wait again.
    Nothing,
    /// Continuity is no longer provable; the caller must capture an authoritative baseline.
    ///
    /// No watermark is advanced on this path, so a cancelled or failed capture leaves the observation
    /// exactly where it was and the next call retries instead of parking forever.
    Resync(ChatResyncReason),
}

impl ChatTail {
    pub(crate) fn new(
        session: Session,
        watch: watch::Receiver<ChatProgress>,
        baseline: ChatTailBaseline,
    ) -> Self {
        let retained = baseline
            .items
            .iter()
            .map(|item| (item.item_id.clone(), item.clone()))
            .collect();
        let version = baseline.version;
        Self {
            session: Some(session),
            watch,
            initial: Some(baseline),
            retained,
            delivered: version,
            seen: version,
        }
    }

    /// Hands the captured first frame over to the consumer, once.
    ///
    /// The baseline is moved out: this observation never keeps a second copy of the newest page, so a
    /// long-lived connection costs one bounded continuity baseline, not "first page + continuity copy".
    /// Reading it never queries history and never opens a second observation.
    ///
    /// # Errors
    /// [`ChatError::Cancelled`] once the observation is closed, and [`ChatError::Conflict`] when the
    /// first frame was already taken — the frame is a single hand-off, not a repeatable getter.
    pub fn initial(&mut self) -> Result<ChatTailBaseline, ChatError> {
        if self.session.is_none() {
            return Err(ChatError::Cancelled);
        }
        self.initial.take().ok_or_else(|| {
            ChatError::Conflict(
                "the captured first frame was already taken by this observation".to_owned(),
            )
        })
    }

    /// Waits for, and returns, the next deliverable frame.
    ///
    /// `Ok(None)` only means the session no longer publishes progress; an error is never turned into
    /// a normal end of content.
    ///
    /// # Errors
    /// [`ChatError::Cancelled`] once the observation is closed, [`ChatError::Conflict`] when the first
    /// frame has not been taken yet, and the host's own typed storage/preview failures for a
    /// resynchronization.
    pub async fn next(&mut self) -> Result<Option<ChatTailUpdate>, ChatError> {
        if self.initial.is_some() {
            return Err(ChatError::Conflict(
                "the captured first frame must be taken before awaiting tail updates".to_owned(),
            ));
        }
        loop {
            let Some(session) = self.session.clone() else {
                return Err(ChatError::Cancelled);
            };
            if !self.wait_ready().await {
                return Ok(None);
            }
            match self.frame(&session)? {
                Frame::Patch(patch) => return Ok(Some(ChatTailUpdate::Patch(patch))),
                Frame::Nothing => {}
                Frame::Resync(reason) => {
                    // 锁外重建权威最新小页：取消或失败都不提交任何水位，下一次调用会重试。
                    let baseline = session.capture_latest_baseline().await?;
                    self.commit(&baseline);
                    return Ok(Some(ChatTailUpdate::Resync { reason, baseline }));
                }
            }
        }
    }

    /// Releases this observation's content baseline and its session reference.
    ///
    /// The observation itself derives no background task, so a caller cancels a pending
    /// [`ChatTail::next`] future before closing or dropping it. Closing one observation stops
    /// neither other observations nor the producer or the history writer.
    pub fn close(&mut self) {
        self.retained.clear();
        self.initial = None;
        self.session = None;
    }

    /// One synchronous commit point: diff the pending version against this observation's copy.
    ///
    /// Every fact is resolved against the observation's own copy plus a local overlay, and nothing is
    /// written back until the whole range has proved to be one continuous patch that is actually
    /// returned. There is no await inside, so staging, the single write-back, the bound and both
    /// watermarks are one atomic step for a delivered frame.
    ///
    /// The staging is what makes a resynchronization safe: the caller captures the new baseline across
    /// an await that can fail or be cancelled, so a `Resync` (or an error) must leave the continuity
    /// copy *exactly* as it was. Mutating the copy per fact and then handing the caller a resync would
    /// keep facts that were never delivered, and the retry would diff against them — reporting
    /// "no change" for a change the consumer never received.
    ///
    /// A range that resolves into nothing the consumer can see is **not** a delivery: the continuity copy
    /// and `delivered` stay where they are, because a patch's `from` has to line up with what the
    /// receiver really holds. Only `seen` advances, so the wake does not fire again for a version
    /// already examined.
    ///
    /// The overlay holds only the identities this frame touched, so staging costs the size of the
    /// pending range instead of a second copy of the bounded continuity tail.
    fn frame(&mut self, session: &Session) -> Result<Frame, ChatError> {
        let state = session.lock_timeline();
        let to = state.version;
        // Waterline discipline, branch by branch: this version was already examined, so nothing moves.
        if to == self.seen {
            return Ok(Frame::Nothing);
        }
        let from = self.delivered;
        // A duplicate wake for content this observation already delivered: only the wake watermark
        // catches up, `delivered` stays the consumer's real watermark.
        if to == from {
            self.seen = to;
            return Ok(Frame::Nothing);
        }
        // Continuity cannot be proven at all: neither watermark moves and the copy is untouched, so a
        // failed or cancelled capture is retried instead of parking on a half-advanced observation.
        let Some(facts) = changes_since(&state.log, from, to) else {
            return Ok(Frame::Resync(ChatResyncReason::Lagging));
        };
        let horizon: BTreeMap<String, ChatItem> = tail_candidates(&state)
            .into_iter()
            .map(|item| (item.item_id.clone(), item))
            .collect();
        // Staged outcome of this frame: `None` is a removal, `Some` an upsert. It is the only thing the
        // loop writes, so every early return below leaves `self.retained` untouched.
        let mut staged: BTreeMap<String, Option<ChatItem>> = BTreeMap::new();
        let mut changes = Vec::new();
        let mut boundary = false;
        for fact in facts {
            let item_id = fact.item_id.as_ref();
            let previous = match staged.get(item_id) {
                Some(mutation) => mutation.as_ref(),
                None => self.retained.get(item_id),
            };
            if fact.removed {
                // A real removal is a self-contained, idempotent fact: it names the identity the
                // authority dropped and carries no state the receiver has to already hold. Whether this
                // observation happens to keep a copy is irrelevant — the consumer may have loaded that
                // identity from a page outside the bounded tail, and "not in my continuity copy" is not
                // the same as "nothing happened". A receiver that does not have the identity applies it
                // as an empty operation; dropping the fact here would leave that receiver showing
                // content the authority already released.
                changes.push(TailChange::Remove {
                    item_id: item_id.to_owned(),
                });
                staged.insert(item_id.to_owned(), None);
                boundary = true;
                continue;
            }
            let Some(current) = horizon.get(item_id) else {
                // A logged content fact is a real change of this identity: it cannot be reported as
                // "no change this observation shows". Once the identity has left the bounded preview
                // tail there is nothing left to diff it against, so continuity is unprovable and the
                // observation must re-baseline explicitly instead of advancing past a change the
                // consumer never received. A cache eviction on its own is not a fact and never
                // reaches this branch; a real removal is handled above as `Remove`.
                return Ok(Frame::Resync(ChatResyncReason::Unavailable));
            };
            let update = previous.and_then(|previous| update_item(previous, current));
            let known = previous.is_some();
            staged.insert(item_id.to_owned(), Some(current.clone()));
            match update {
                Some((change, is_boundary)) => {
                    boundary |= is_boundary;
                    changes.push(change);
                }
                None if !known => {
                    changes.push(TailChange::Add {
                        item: current.clone(),
                    });
                    boundary = true;
                }
                None => {}
            }
        }
        if changes.is_empty() {
            // Nothing is handed to the consumer, so the consumer watermark does not move: `delivered`
            // is the version this observation actually delivered, and `from` of the next patch has to
            // line up with what the receiver really holds. Only the wake watermark advances, and the
            // undelivered staging is discarded — there was no frame, so there is nothing to adopt.
            // Adopting it here would move the continuity copy ahead of the consumer, which is exactly
            // the gap this guard prevents.
            self.seen = to;
            return Ok(Frame::Nothing);
        }
        // The one write-back, for a frame that is really going out: apply the staging, bound the copy,
        // then advance both watermarks together.
        for (item_id, mutation) in staged {
            match mutation {
                Some(item) => {
                    self.retained.insert(item_id, item);
                }
                None => {
                    self.retained.remove(&item_id);
                }
            }
        }
        bound_retained(&mut self.retained);
        self.seen = to;
        self.delivered = to;
        Ok(Frame::Patch(ChatTailPatch {
            from,
            to,
            changes,
            priority: if boundary {
                ChatUpdatePriority::Immediate
            } else {
                ChatUpdatePriority::Coalesced
            },
        }))
    }

    /// Adopts an authoritative baseline captured outside every lock.
    fn commit(&mut self, baseline: &ChatTailBaseline) {
        self.retained = baseline
            .items
            .iter()
            .map(|item| (item.item_id.clone(), item.clone()))
            .collect();
        self.delivered = baseline.version;
        self.seen = baseline.version;
    }

    /// Lock-free readiness wait: only the version and boundary waterline are read.
    ///
    /// Returns `false` only when the session no longer publishes progress.
    async fn wait_ready(&self) -> bool {
        let mut waiter = self.watch.clone();
        // Anchored once, on the first observation of a pending coalesced change, and never restarted.
        let mut deadline: Option<tokio::time::Instant> = None;
        loop {
            let progress = *waiter.borrow_and_update();
            if progress.version == self.seen {
                if waiter.changed().await.is_err() {
                    return false;
                }
                continue;
            }
            if progress.urgent > self.seen {
                return true;
            }
            let coalesce =
                *deadline.get_or_insert_with(|| tokio::time::Instant::now() + COALESCE_WINDOW);
            tokio::select! {
                biased;
                () = tokio::time::sleep_until(coalesce) => return true,
                changed = waiter.changed() => {
                    if changed.is_err() {
                        return false;
                    }
                }
            }
        }
    }
}

/// Every identity touched by the versions in `(delivered, to]`, or `None` when that range is no
/// longer covered by the bounded continuity window.
fn changes_since(
    log: &VecDeque<ChangeEntry>,
    delivered: u64,
    to: u64,
) -> Option<Vec<ChangedIdentity>> {
    let first = log.front()?;
    let last = log.back()?;
    if last.version != to {
        return None;
    }
    // `delivered` starts at the registration version, which may predate the oldest logged entry.
    if first.version > delivered.saturating_add(1) {
        return None;
    }
    let mut facts = Vec::new();
    for entry in log {
        if entry.version <= delivered {
            continue;
        }
        if entry.overflow {
            return None;
        }
        facts.extend(entry.identities.iter().cloned());
    }
    Some(facts)
}

/// Bounds one observation's continuity copy to the newest [`RECENT_ITEMS`] items and
/// [`RECENT_BYTES`] of preview bytes.
fn bound_retained(retained: &mut BTreeMap<String, ChatItem>) {
    let mut ordered: Vec<(u64, String)> = retained
        .values()
        .map(|item| (item.order, item.item_id.clone()))
        .collect();
    ordered.sort_by(|left, right| right.0.cmp(&left.0).then_with(|| right.1.cmp(&left.1)));
    let mut keep = BTreeSet::new();
    let mut used = 0usize;
    for (_, item_id) in ordered {
        if keep.len() == RECENT_ITEMS {
            break;
        }
        let bytes = retained.get(&item_id).map_or(0, ChatItem::resident_bytes);
        if !keep.is_empty() && used.saturating_add(bytes) > RECENT_BYTES {
            break;
        }
        used = used.saturating_add(bytes);
        keep.insert(item_id);
    }
    retained.retain(|item_id, _| keep.contains(item_id));
}

/// Whether two copies describe the same delivered frame: same identity, watermark and bounded state.
///
/// Content is compared by shared block pointer together with its complete length, so a burst of
/// appends does not materialize text and a preview that grew past the budget is still a change.
fn same_frame(left: &ChatItem, right: &ChatItem) -> bool {
    left.item_id == right.item_id
        && left.order == right.order
        && left.revision == right.revision
        && left.lifecycle == right.lifecycle
        && left.saved == right.saved
        && left.turn_id == right.turn_id
        && left.meta == right.meta
        && left.fields.len() == right.fields.len()
        && left.fields.iter().all(|(field, preview)| {
            right.fields.get(field).is_some_and(|other| {
                Arc::ptr_eq(&preview.block, &other.block)
                    && preview.total_bytes == other.total_bytes
            })
        })
}

/// Batched content change for one identity, or `None` when nothing changed.
///
/// Every field delta of the identity travels under one `expected_revision` / `revision` commit, and a
/// version-only or bounded-status-only change still produces a (field-delta-free) update so a consumer
/// never keeps a stale revision. The returned flag marks a boundary: the execution lifecycle, save
/// watermark or static metadata changed, or a field was removed or authoritatively replaced rather
/// than appended.
fn update_item(previous: &ChatItem, next: &ChatItem) -> Option<(TailChange, bool)> {
    if same_frame(previous, next) {
        return None;
    }
    let mut fields = Vec::new();
    for (field, preview) in &next.fields {
        let change = match previous.fields.get(field) {
            Some(previous_preview) if Arc::ptr_eq(&previous_preview.block, &preview.block) => {
                FieldChange::Unchanged
            }
            Some(previous_preview) => {
                match ContentBlock::appended_since(&preview.block, &previous_preview.block) {
                    Some(text) if text.is_empty() => FieldChange::Unchanged,
                    Some(text) => FieldChange::Append(text),
                    // A bounded preview that has already reached its cap stops extending: the bytes
                    // it shows are identical even though the original body keeps growing, so this is a
                    // metadata-only change rather than an authoritative replacement.
                    None if ContentBlock::text_eq(&preview.block, &previous_preview.block) => {
                        FieldChange::Unchanged
                    }
                    None => FieldChange::Replace(preview.block.clone()),
                }
            }
            None => FieldChange::Replace(preview.block.clone()),
        };
        fields.push(FieldUpdate {
            field: field.clone(),
            change,
            total_bytes: preview.total_bytes,
            preview_bytes: preview.block.len() as u64,
        });
    }
    // A field present before but gone now is an explicit removal, not a silently dropped delta.
    for field in previous.fields.keys() {
        if !next.fields.contains_key(field) {
            fields.push(FieldUpdate {
                field: field.clone(),
                change: FieldChange::Remove,
                total_bytes: 0,
                preview_bytes: 0,
            });
        }
    }
    let meta =
        (previous.meta != next.meta || previous.turn_id != next.turn_id).then(|| next.meta.clone());
    let boundary = previous.lifecycle != next.lifecycle
        || previous.saved != next.saved
        || meta.is_some()
        || fields
            .iter()
            .any(|delta| matches!(&delta.change, FieldChange::Remove | FieldChange::Replace(_)));
    let change = TailChange::UpdateItem {
        item_id: next.item_id.clone(),
        expected_revision: previous.revision,
        revision: next.revision,
        omitted_bytes: next.omitted_bytes(),
        saved: next.saved,
        lifecycle: next.lifecycle,
        meta,
        fields,
    };
    Some((change, boundary))
}

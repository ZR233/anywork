//! 会话完成集合：发布准入、完成序号分配、pending 生命周期与运行代际。
//!
//! [`Session`] 是一个注册会话内完成事实、pending 与统一读取的唯一所有者，保持产品无关：
//!
//! - 普通新事实用 [`Session::prepare_fresh`] 和 [`Session::admit_prepared`] 同步内存准入，宿主在
//!   可靠业务接纳边界证明身份并串行化发布；完成与展示共享一次原子提交。
//! - 未知身份、导入和重放用 [`Session::publish_batch`] 校验历史身份及载荷；同身份同载荷幂等，
//!   异载荷为类型化冲突，已持久身份同样检查。两条入口共用完成原件、索引和序号分配规则；
//! - [`Session::confirm_durable`] 只在 writer 真实提交了连续前缀后回收 pending；保存确认不发
//!   内容事件，也不改变任何已发布记录；
//! - 读取不在这里：见 `read` 模块的互不重叠区间读取。锁的纪律固定为锁内只做同步、有界的工作，
//!   绝不跨 `.await` 持锁，不 flush，不克隆全部 pending。
//!
//! `timelineEpoch` 是宿主构建 Session 时注入的不透明运行代际：重启或重建必然由宿主提供新 epoch，
//! 旧 epoch 的游标按类型化错误拒绝，而不是被新集合静默重解释。

use std::{
    collections::BTreeMap,
    fmt,
    sync::{Arc, Mutex, MutexGuard, Weak},
};

use tokio::sync::watch;

use crate::chat::{
    ChatContent, ChatContentKey, ChatDraft, ChatError, ChatHistory, ChatItem, ChatKey,
    ChatPublicationSeed, ChatQuery, ChatRunSeed, ChatSelection, TimelineEpoch,
    history::ErasedChatHistory, item::draft_matches_record,
};

/// 会话的完成集合状态。所有字段只在短临界区内被读写。
#[derive(Default)]
pub(crate) struct TimelineState {
    /// 是否已经从持久化读取过完成上界种子。
    initialized: bool,
    /// 完成可见上界 H：已发布（立即可查询）的最大 `append_seq`。
    pub(crate) head: u64,
    /// 连续持久化前缀 D：writer 已确认真实提交的最大 `append_seq`。
    pub(crate) durable: u64,
    last_visible: Option<ChatRunSeed>,
    /// 按序 pending 的完整不可变记录，覆盖 `(durable, head]`。
    ///
    /// 每条记录与 writer 持有的是同一个 `Arc`：回收前读取只拿有界引用，不复制正文。pending 的
    /// 条数与字节预算由外层可靠队列提供，本层不丢最旧项、不做无界复制。
    pending: BTreeMap<u64, Arc<ChatItem>>,
    pending_ids: BTreeMap<String, u64>,
    by_class: BTreeMap<String, BTreeMap<u64, Arc<ChatItem>>>,
    visible_by_class: BTreeMap<String, BTreeMap<u64, Arc<ChatItem>>>,
    by_run: BTreeMap<(String, u64), BTreeMap<u64, Arc<ChatItem>>>,
    by_parent_class: BTreeMap<(ChatKey, String), BTreeMap<u64, Arc<ChatItem>>>,
    pending_contents: BTreeMap<ChatContentKey, BTreeMap<u64, Arc<ChatContent>>>,
}

impl TimelineState {
    /// Pending completion records and distinct content keys, not the number of Arc references
    /// retained by the secondary indexes or external readers/writers.
    pub(super) fn pending_counts(&self) -> (usize, usize) {
        (self.pending.len(), self.pending_contents.len())
    }

    /// Select membership before iteration; hidden pending entries are never visited.
    pub(crate) fn pending_index(
        &self,
        query: Option<&ChatQuery>,
    ) -> Option<&BTreeMap<u64, Arc<ChatItem>>> {
        match query {
            None => Some(&self.pending),
            Some(ChatQuery {
                query_class,
                parent_id: None,
                selection: ChatSelection::Records,
            }) => self.by_class.get(query_class),
            Some(ChatQuery {
                query_class,
                selection: ChatSelection::RunHeads,
                ..
            }) => self.visible_by_class.get(query_class),
            Some(ChatQuery {
                query_class,
                selection: ChatSelection::Run { start_seq },
                ..
            }) => self.by_run.get(&(query_class.clone(), *start_seq)),
            Some(ChatQuery {
                query_class,
                parent_id: Some(parent),
                ..
            }) => self
                .by_parent_class
                .get(&(parent.clone(), query_class.clone())),
        }
    }

    /// The pending record of one identity, if it is still awaiting its durable confirmation.
    pub(crate) fn pending_record(&self, item_id: &str) -> Option<Arc<ChatItem>> {
        let seq = self.pending_ids.get(item_id)?;
        self.pending.get(seq).cloned()
    }

    pub(crate) fn pending_content(&self, key: &ChatContentKey) -> Option<Arc<ChatContent>> {
        self.pending_contents
            .get(key)?
            .first_key_value()
            .map(|(_, content)| content.clone())
    }

    fn insert(&mut self, record: Arc<ChatItem>) {
        let header = &record.header;
        self.pending_ids
            .insert(header.item_id.clone(), header.append_seq);
        self.by_class
            .entry(header.query_class.clone())
            .or_default()
            .insert(header.append_seq, record.clone());
        if let Some(run) = header.run {
            self.visible_by_class
                .entry(header.query_class.clone())
                .or_default()
                .insert(header.append_seq, record.clone());
            self.by_run
                .entry((header.query_class.clone(), run.start_seq))
                .or_default()
                .insert(header.append_seq, record.clone());
        }
        if let Some(parent) = &header.parent_id {
            self.by_parent_class
                .entry((parent.clone(), header.query_class.clone()))
                .or_default()
                .insert(header.append_seq, record.clone());
        }
        for (key, content) in record.contents.iter() {
            self.pending_contents
                .entry(key.clone())
                .or_default()
                .insert(header.append_seq, content.clone());
        }
        self.pending.insert(header.append_seq, record);
    }

    fn remove_indexes(&mut self, record: &ChatItem) {
        let header = &record.header;
        self.pending_ids.remove(&header.item_id);
        if let Some(run) = header.run {
            if let Some(index) = self.visible_by_class.get_mut(&header.query_class) {
                index.remove(&header.append_seq);
                if index.is_empty() {
                    self.visible_by_class.remove(&header.query_class);
                }
            }
            let key = (header.query_class.clone(), run.start_seq);
            if let Some(index) = self.by_run.get_mut(&key) {
                index.remove(&header.append_seq);
                if index.is_empty() {
                    self.by_run.remove(&key);
                }
            }
        }
        if let Some(index) = self.by_class.get_mut(&header.query_class) {
            index.remove(&header.append_seq);
            if index.is_empty() {
                self.by_class.remove(&header.query_class);
            }
        }
        if let Some(parent) = &header.parent_id {
            let key = (parent.clone(), header.query_class.clone());
            if let Some(index) = self.by_parent_class.get_mut(&key) {
                index.remove(&header.append_seq);
                if index.is_empty() {
                    self.by_parent_class.remove(&key);
                }
            }
        }
        for key in record.contents.keys() {
            if let Some(index) = self.pending_contents.get_mut(key) {
                index.remove(&header.append_seq);
                if index.is_empty() {
                    self.pending_contents.remove(key);
                }
            }
        }
    }
}

pub(crate) struct SessionInner {
    pub(crate) history: Arc<dyn ErasedChatHistory>,
    /// 宿主注入的运行代际；构造即固定，生命周期内不变。
    pub(crate) epoch: TimelineEpoch,
    seq_seed: tokio::sync::OnceCell<ChatPublicationSeed>,
    pub(crate) timeline: Mutex<TimelineState>,
    /// 只承载完成上界的唤醒水位。保存确认不发内容事件；内容帧由读取方相对自己的交付位置计算。
    pub(crate) changed: watch::Sender<u64>,
}

/// Shared completion collection for one session. Reading content neither starts a model nor
/// transfers the ownership of an uncommitted effect to a subscriber.
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

/// 尚未发布的内存准入计划；其中原件尚不能作为可读完成事实公开。
pub struct ChatAdmission {
    epoch: TimelineEpoch,
    expected_head: u64,
    records: Arc<[Arc<ChatItem>]>,
    fresh: Vec<Arc<ChatItem>>,
    seed: ChatPublicationSeed,
}
impl ChatAdmission {
    pub fn records(&self) -> &Arc<[Arc<ChatItem>]> {
        &self.records
    }
    pub fn head_seq(&self) -> u64 {
        self.seed.head_seq
    }
}

impl Session {
    /// 初始化完成序号种子。执行宿主在开放新事实准入之前调用一次。
    pub async fn initialize(&self) -> Result<(), ChatError> {
        self.ensure_initialized().await
    }

    /// 为已可靠接纳的新事实准备内存批次；不查询历史、不消耗序号。
    ///
    /// 宿主必须在 effect/input/message 接纳边界证明身份为新，并串行化准备及提交。
    /// 未知外部身份、导入或重放使用 `publish_batch` 的历史校验入口。
    pub fn prepare_fresh(&self, batch: Vec<ChatDraft>) -> Result<ChatAdmission, ChatError> {
        let drafts = collapse_batch(batch)?;
        let state = self.lock_timeline();
        if !state.initialized {
            return Err(ChatError::InvalidArgument(
                "completion admission is not initialized".into(),
            ));
        }
        let mut seed = ChatPublicationSeed {
            head_seq: state.head,
            last_visible: state.last_visible.clone(),
        };
        let mut records = Vec::with_capacity(drafts.len());
        let mut fresh = Vec::with_capacity(drafts.len());
        let mut contents = BTreeMap::new();
        for draft in drafts {
            if let Some(record) = state.pending_record(&draft.item_id) {
                if !draft_matches_record(&draft, &record) {
                    return Err(ChatError::Conflict(draft.item_id));
                }
                records.push(record);
                continue;
            }
            for (key, content) in draft.contents.iter() {
                if state
                    .pending_content(key)
                    .is_some_and(|old| old != *content)
                    || contents
                        .insert(key.clone(), content.clone())
                        .is_some_and(|old| old != *content)
                {
                    return Err(ChatError::Conflict(key.key.clone()));
                }
            }
            let (seq, run) = seed.advance(&draft.read_hint)?;
            let record = Arc::new(ChatItem::complete(draft, seq, run));
            records.push(record.clone());
            fresh.push(record);
        }
        records.sort_by_key(|record| record.header.append_seq);
        Ok(ChatAdmission {
            epoch: self.epoch(),
            expected_head: state.head,
            records: records.into(),
            fresh,
            seed,
        })
    }

    /// 一次提交已经准备好的批次。宿主同步应用其已验证投影，再发完成通知。
    /// 准备后若其他发布者推进了 head，原计划明确失败且不修改任何状态。
    pub fn admit_prepared(
        &self,
        plan: ChatAdmission,
        apply: impl FnOnce(),
    ) -> Result<Arc<[Arc<ChatItem>]>, ChatError> {
        let mut state = self.lock_timeline();
        if plan.epoch != self.epoch() || plan.expected_head != state.head {
            return Err(ChatError::StaleContent);
        }
        for record in plan.fresh {
            state.insert(record);
        }
        state.head = plan.seed.head_seq;
        state.last_visible = plan.seed.last_visible;
        apply();
        self.0.changed.send_replace(state.head);
        Ok(plan.records)
    }

    /// 以宿主注入的不透明运行代际构建会话。
    ///
    /// 宿主在**每次**构建（含重启、重建）Session 时提供一个新的唯一 epoch；Core 不生成也不解释
    /// 它。同一代际在会话生命周期内不变，旧代际的游标按 [`ChatError::EpochMismatch`] 拒绝。
    pub fn new(history: impl ChatHistory, epoch: TimelineEpoch) -> Self {
        let (changed, _) = watch::channel(0);
        Self(Arc::new(SessionInner {
            history: Arc::new(history),
            epoch,
            seq_seed: tokio::sync::OnceCell::new(),
            timeline: Mutex::new(TimelineState::default()),
            changed,
        }))
    }

    pub fn downgrade(&self) -> WeakSession {
        WeakSession(Arc::downgrade(&self.0))
    }

    /// 本会话的完成代际。
    pub fn epoch(&self) -> TimelineEpoch {
        self.0.epoch.clone()
    }

    /// 当前完成可见上界 H（尚未初始化种子的冷会话为 0）。
    pub fn head_seq(&self) -> u64 {
        self.with_timeline(|state| state.head)
    }

    /// 已确认连续持久化前缀 D（尚未初始化种子的冷会话为 0）。
    pub fn durable_seq(&self) -> u64 {
        self.with_timeline(|state| state.durable)
    }

    /// Whether a tail observation is open or capturing its initial baseline.
    ///
    /// This is an instantaneous delivery-demand hint, not a synchronization boundary: another
    /// observer may register or close immediately after it returns. It must never gate authoritative
    /// facts, pending retention or wake maintenance. A closed [`super::ChatTail`] no longer
    /// contributes demand even if the object itself is retained.
    pub fn has_subscribers(&self) -> bool {
        self.0.changed.receiver_count() != 0
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

    /// Reads the persisted completion ceiling once and seeds H/D. The first publish or read of a
    /// cold session runs this; it does not create a history database and does not start the model.
    pub(crate) async fn ensure_initialized(&self) -> Result<(), ChatError> {
        if self.with_timeline(|state| state.initialized) {
            return Ok(());
        }
        let seed = self
            .0
            .seq_seed
            .get_or_try_init(|| self.0.history.publication_seed())
            .await?;
        seed.validate()?;
        let mut state = self.lock_timeline();
        if !state.initialized {
            state.head = seed.head_seq;
            state.durable = seed.head_seq;
            state.last_visible = seed.last_visible.clone();
            state.initialized = true;
            self.0.changed.send_replace(state.head);
        }
        Ok(())
    }

    /// Publishes one batch of complete, not-yet-sequenced completions.
    ///
    /// The whole batch is validated before anything becomes visible: identities must be non-empty
    /// and unique (same payload twice inside one batch collapses to one), and every identity is
    /// checked against the session's pending records **and** the persisted store under the same
    /// idempotency-or-conflict rule. Sequences are then assigned consecutively from the current
    /// head in one short critical section, the batch becomes queryable atomically, and the returned
    /// frozen records are the very `Arc` objects the session keeps in pending — the writer submits
    /// those and later calls [`Session::confirm_durable`] with the last sequence it committed.
    ///
    /// A late completion that started earlier is ordered by this publication, not by its start: it
    /// receives a later sequence and must not be inserted back ahead of an earlier completion.
    ///
    /// # Errors
    /// [`ChatError::InvalidArgument`] for an empty identity, [`ChatError::Conflict`] when the same
    /// identity carries a different payload, [`ChatError::SeqExhausted`] when the consecutive
    /// assignment would leave the signed 64-bit range (the whole batch fails without partial
    /// publication), plus the host's own typed storage failures.
    pub async fn publish_batch(
        &self,
        batch: Vec<ChatDraft>,
    ) -> Result<Arc<[Arc<ChatItem>]>, ChatError> {
        let drafts = collapse_batch(batch)?;
        if drafts.is_empty() {
            return Ok(Arc::from(Vec::new()));
        }
        self.ensure_initialized().await?;
        loop {
            let captured_durable = self.durable_seq();
            // Pass 1 (short lock): pending is the authority for (D, H]; a hit resolves as idempotent or
            // conflict without any storage IO.
            let (mut records, unresolved) = self.resolve_pending(drafts.clone())?;
            // Pass 2 (storage, outside every lock): the same identity rules against persisted records,
            // bounded by the batch size. Each call is a fresh short read on the port.
            let mut fresh = Vec::with_capacity(unresolved.len());
            for draft in unresolved {
                match self.0.history.item(&draft.item_id).await? {
                    Some(persisted) => {
                        persisted.header.validate_run()?;
                        if !draft_matches_record(&draft, &persisted) {
                            return Err(ChatError::Conflict(draft.item_id));
                        }
                        records.push(Arc::new(persisted));
                    }
                    None => fresh.push(draft),
                }
            }
            // Content owners can outlive the item that first introduced them. Reclaiming pending
            // must not make a durable key available for different bytes. Validate each unique key
            // outside the Session lock, then recheck D and pending below before any publication.
            let mut durable_contents = BTreeMap::new();
            for draft in &fresh {
                for (key, content) in draft.contents.iter() {
                    if durable_contents
                        .insert(key, content)
                        .is_some_and(|old| old != content)
                    {
                        return Err(ChatError::Conflict(key.key.clone()));
                    }
                }
            }
            for content in durable_contents.values() {
                self.0.history.validate_content(content).await?;
            }
            // Pass 3 (one short critical section): a concurrent publish may have admitted one of these
            // identities between the passes, so the re-resolution, the sequence assignment and the
            // insertion all happen under the same lock — the batch becomes visible atomically.
            let mut state = self.lock_timeline();
            // A concurrent writer may have committed and reclaimed an identity while
            // the unlocked read still saw its old snapshot. Retry against fresh
            // storage before assigning another sequence to that identity.
            if state.durable != captured_durable {
                continue;
            }
            let mut to_publish = Vec::with_capacity(fresh.len());
            for draft in fresh {
                match state.pending_record(&draft.item_id) {
                    Some(record) => {
                        if !draft_matches_record(&draft, &record) {
                            return Err(ChatError::Conflict(draft.item_id));
                        }
                        records.push(record);
                    }
                    None => to_publish.push(draft),
                }
            }
            let additions = to_publish.len() as u64;
            state
                .head
                .checked_add(additions)
                .filter(|head| *head <= i64::MAX as u64)
                .ok_or(ChatError::SeqExhausted)?;
            // Validate shared content identities before mutating any index.
            let mut content_keys = BTreeMap::new();
            for draft in &to_publish {
                for (key, content) in draft.contents.iter() {
                    if state
                        .pending_content(key)
                        .is_some_and(|old| old != *content)
                        || content_keys
                            .insert(key, content)
                            .is_some_and(|old| old != content)
                    {
                        return Err(ChatError::Conflict(key.key.clone()));
                    }
                }
            }
            // Allocate the entire batch privately. A later ordinal/arithmetic error cannot leave
            // an earlier item or any secondary index published.
            let mut seed = ChatPublicationSeed {
                head_seq: state.head,
                last_visible: state.last_visible.clone(),
            };
            let mut candidates = Vec::with_capacity(to_publish.len());
            for draft in to_publish {
                let (seq, run) = seed.advance(&draft.read_hint)?;
                candidates.push(Arc::new(ChatItem::complete(draft, seq, run)));
            }
            for record in candidates {
                state.insert(record.clone());
                records.push(record);
            }
            let published = seed.head_seq > state.head;
            if published {
                state.head = seed.head_seq;
                state.last_visible = seed.last_visible;
                // The wake carries the completion head only; the subscription computes its own content
                // frame from its delivered position. send_replace never blocks, so the notification is
                // part of the same atomic publication.
                self.0.changed.send_replace(state.head);
            }
            records.sort_by_key(|record| record.header.append_seq);
            let (head, durable) = (state.head, state.durable);
            let (pending_completion_records, pending_content_keys) = state.pending_counts();
            drop(state);
            if published {
                tracing::debug!(
                    target: "conversation_work",
                    head,
                    durable,
                    pending_completion_records,
                    pending_content_keys,
                    published_records = additions,
                    "completion publication"
                );
            }
            return Ok(Arc::from(records));
        }
    }

    /// Splits drafts into already-pending records (idempotent hits) and unresolved drafts.
    fn resolve_pending(
        &self,
        drafts: Vec<ChatDraft>,
    ) -> Result<(Vec<Arc<ChatItem>>, Vec<ChatDraft>), ChatError> {
        let state = self.lock_timeline();
        let mut records = Vec::new();
        let mut unresolved = Vec::with_capacity(drafts.len());
        for draft in drafts {
            match state.pending_record(&draft.item_id) {
                Some(record) => {
                    if !draft_matches_record(&draft, &record) {
                        return Err(ChatError::Conflict(draft.item_id));
                    }
                    records.push(record);
                }
                None => unresolved.push(draft),
            }
        }
        Ok((records, unresolved))
    }

    /// Advances the durable prefix after the writer really committed it.
    ///
    /// `through` must name a contiguous published prefix: the greatest sequence the writer's
    /// transaction landed. Pending records at or below it are reclaimed; anything above stays
    /// pending and queryable. This acknowledgement publishes no content event and changes no
    /// record — reading a reclaimed item continues from durable history.
    ///
    /// # Errors
    /// [`ChatError::InvalidArgument`] when `through` names a sequence beyond the published head.
    pub fn confirm_durable(&self, through: u64) -> Result<(), ChatError> {
        let mut state = self.lock_timeline();
        if through > state.head {
            return Err(ChatError::InvalidArgument(format!(
                "durable confirmation {through} is beyond the published head {}",
                state.head
            )));
        }
        if through <= state.durable {
            return Ok(());
        }
        let previous_durable = state.durable;
        let (pending_completion_records_before, pending_content_keys_before) =
            state.pending_counts();
        state.durable = through;
        let reclaimed: Vec<u64> = state
            .pending
            .range(..=through)
            .map(|(seq, _)| *seq)
            .collect();
        for seq in reclaimed {
            if let Some(record) = state.pending.remove(&seq) {
                state.remove_indexes(&record);
            }
        }
        let (head, durable) = (state.head, state.durable);
        let (pending_completion_records, pending_content_keys) = state.pending_counts();
        drop(state);
        tracing::debug!(
            target: "conversation_work",
            head,
            durable,
            previous_durable,
            pending_completion_records_before,
            pending_content_keys_before,
            pending_completion_records,
            pending_content_keys,
            "durable confirmation"
        );
        Ok(())
    }
}

/// Validates identities and collapses intra-batch duplicates.
///
/// The same identity with the same payload twice in one batch is one completion, not two sequences;
/// the same identity with a different payload fails the whole batch before anything is published.
fn collapse_batch(batch: Vec<ChatDraft>) -> Result<Vec<ChatDraft>, ChatError> {
    let mut collapsed: Vec<ChatDraft> = Vec::with_capacity(batch.len());
    let mut positions = BTreeMap::new();
    for draft in batch {
        draft.validate()?;
        if let Some(&position) = positions.get(&draft.item_id) {
            if collapsed[position] != draft {
                return Err(ChatError::Conflict(draft.item_id));
            }
            continue;
        }
        positions.insert(draft.item_id.clone(), collapsed.len());
        collapsed.push(draft);
    }
    Ok(collapsed)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scope_selection_borrows_the_membership_index_not_the_global_pending_collection() {
        let mut state = TimelineState::default();
        let parent = ChatKey::new("call", "one").unwrap();
        let query = ChatQuery::new("activity", Some(parent.clone()));
        let mut chosen = ChatDraft::new("chosen", "activity", Arc::from([1]));
        chosen.parent_id = Some(parent);
        let chosen = Arc::new(ChatItem::complete(chosen, 1, None));
        state.insert(chosen.clone());
        for seq in 2..=8193 {
            state.insert(Arc::new(ChatItem::complete(
                ChatDraft::new(format!("hidden-{seq}"), "activity", Arc::from([2])),
                seq,
                None,
            )));
        }
        let index = state.pending_index(Some(&query)).unwrap();
        assert_eq!(
            index.len(),
            1,
            "the iteration source itself excludes hidden items"
        );
        assert!(Arc::ptr_eq(index.first_key_value().unwrap().1, &chosen));
        assert_eq!(
            state
                .pending_index(Some(&ChatQuery::new("activity", None)))
                .unwrap()
                .len(),
            8193
        );
        let class_index = state.by_class.get("activity").unwrap();
        assert!(std::ptr::eq(
            state
                .pending_index(Some(&ChatQuery::new("activity", None)))
                .unwrap(),
            class_index,
        ));
        state.pending.remove(&1);
        state.remove_indexes(&chosen);
        assert!(
            state.pending_index(Some(&query)).is_none(),
            "commit removes empty scope indexes"
        );
        assert!(state.pending_record("chosen").is_none());
    }
}

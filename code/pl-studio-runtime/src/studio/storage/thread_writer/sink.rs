//! Writer startup, Core callbacks and ordered durable processing.

use super::*;

/// How long one writer incarnation may keep retrying a transient storage conflict before it must
/// report it.
///
/// A short `SQLITE_BUSY`/`SQLITE_LOCKED`/`SQLITE_IOERR` is a self-healing conflict: the accepted
/// effects stay queued in order and the same `step` writes them again, so surfacing the error would
/// turn a conflict that resolves on its own into a terminal persistence failure that blocks the
/// next model admission. Only a conflict that outlives this window — or a structural, constraint
/// or corruption error, which is never retried — is reported and keeps failing the drain.
const RETRYABLE_BUSY_WINDOW: Duration = Duration::from_secs(30);
/// Identity source for live per-Thread writer incarnations.
///
/// The coordinator keys its per-Thread watermarks by this value so a stopped writer can release
/// only its own state, and a replacement incarnation is never mistaken for the writer it replaced.
static NEXT_WRITER_INCARNATION: AtomicUsize = AtomicUsize::new(1);

pub(super) enum Step {
    /// Progress was made; the loop runs another unit immediately.
    Progressed,
    /// Nothing to do yet; every admitted effect already carries its own checkpoint, so the loop
    /// just waits for the next admission or retry notification.
    Idle,
    /// Coalesce until the oldest obligation's fixed deadline, or until notified.
    Coalescing(Instant),
}

pub(super) struct Inner {
    pub(super) store: StudioStore,
    pub(super) thread: crate::Thread,
    pub(super) conversation: Arc<crate::studio::conversation_store::ConversationStore>,
    /// This writer incarnation's coordinator identity; see [`NEXT_WRITER_INCARNATION`].
    pub(super) owner: usize,
    /// One durable history reader for the life of this writer.
    ///
    /// The history database is the single ordinal/identity allocator, so the writer opens it once
    /// instead of per effect; the pool has one connection, so every batch stays a short
    /// single-writer transaction and two consecutive effects cannot interleave their allocations.
    pub(super) history: tokio::sync::OnceCell<HistoryStore>,
    pub(super) channel: Arc<HistoryChannel>,
    pub(super) changed: Arc<tokio::sync::Notify>,
    history_observer_stop: tokio::sync::watch::Sender<bool>,
}

impl Drop for Inner {
    fn drop(&mut self) {
        self.history_observer_stop.send_replace(true);
    }
}

/// Cloneable sink attached to one core owner incarnation.
#[derive(Clone)]
pub(crate) struct ThreadStorageSink(pub(super) Arc<Inner>);

/// One actual writer incarnation, retained through attachment and all close joins.
#[derive(Debug)]
pub(crate) struct ThreadStorageBinding {
    pub(crate) conversation: Arc<crate::studio::conversation_store::ConversationStore>,
    pub(crate) incarnation: usize,
    pub(crate) storage: ThreadStorageSink,
    pub(crate) channel: Arc<HistoryChannel>,
}

impl ThreadStorageBinding {
    pub(crate) fn new(
        storage: ThreadStorageSink,
        channel: Arc<HistoryChannel>,
        conversation: Arc<crate::studio::conversation_store::ConversationStore>,
    ) -> Self {
        Self {
            storage,
            channel,
            conversation,
            incarnation: NEXT_WRITER_INCARNATION.fetch_add(1, Ordering::Relaxed),
        }
    }
}

impl Drop for ThreadStorageBinding {
    fn drop(&mut self) {
        self.conversation.detach_execution(self);
    }
}

impl std::fmt::Debug for ThreadStorageSink {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ThreadStorageSink")
            .field("thread_id", &self.0.thread.id)
            .finish_non_exhaustive()
    }
}

pub(super) fn lock_progress(inner: &Inner) -> std::sync::MutexGuard<'_, Progress> {
    inner
        .channel
        .progress
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

/// Encoded size of one effect, or `u64::MAX` when it cannot be encoded.
fn encoded_bytes(effect: &pl_core::thread::ThreadEffectBatch) -> u64 {
    effect
        .encode()
        .map_or(u64::MAX, |payload| payload.content().len() as u64)
}

/// Accepted output bytes that can transfer to the operation's durable fact.
fn retained_output_draw(progress: &Progress, operation: &str, want: u64) -> u64 {
    progress
        .operation_output
        .get(operation)
        .map_or(0, |output| output.retained().min(want))
}

/// Transfers already charged output to its producing operation's fact without charging twice.
/// Unrelated facts must fit the remaining budget; they cannot spend another operation's output.
/// The plan is computed before admission mutates either counter.
fn output_transfer_plan(
    progress: &Progress,
    funding: Option<&str>,
    bytes: u64,
) -> (Vec<(String, u64)>, u64) {
    let mut plan = Vec::new();
    let mut covered = 0_u64;
    if let Some(operation) = funding {
        let take = retained_output_draw(progress, operation, bytes);
        if take > 0 {
            covered += take;
            plan.push((operation.to_owned(), take));
        }
    }
    (plan, covered)
}

/// The writer's single durable history reader, opened on first use.
///
/// The handle comes from the per-Thread shared writer registry, so this sink's effect commit and a
/// live subscription's ordinal reservation share one ordered writer identity — one SQLite write
/// connection — instead of two independent writers racing for `history.sqlite`'s write lock. Reads
/// stay on their own read-only connections in WAL, so they are never queued behind this one.
pub(super) async fn history_store(inner: &Inner) -> Result<HistoryStore> {
    let opened = inner
        .history
        .get_or_try_init(|| async { inner.store.history(&inner.thread.id).await })
        .await?;
    Ok(opened.clone())
}

/// Publishes the current queue state so `wait_for_drain` and the product snapshot never report a
/// Thread as finished while an admitted History export is still queued.
pub(super) fn report(inner: &Inner, progress: &Progress) {
    report_with_calls(inner, progress, Some(inner.store.calls()));
}

/// History-only observers pass no capability to sample or republish global calls state.
fn report_with_calls(
    inner: &Inner,
    progress: &Progress,
    calls: Option<&crate::studio::storage::calls::CallsStore>,
) {
    inner.channel.report(progress);
    let pending = progress
        .effects
        .front()
        .zip(progress.effects.back())
        .map(|(first, last)| PendingSequenceRange {
            first: first.sequence,
            last: last.sequence,
        });
    debug_assert_eq!(
        pending.map_or(0, PendingSequenceRange::count),
        progress.effects.len() as u64
    );
    let pending_bytes = progress
        .effect_bytes
        .saturating_add(progress.queue_metadata_bytes);
    // Only admitted History exports contribute here. Current has its own writer and dirty bit.
    let pending_operations = progress.effects.len() as u64;
    let now = crate::studio::unix_seconds();
    let oldest_pending_age_millis =
        progress
            .pending_saved_at
            .first_key_value()
            .map(|(saved_at, _)| {
                u64::try_from(now.saturating_sub(*saved_at))
                    .unwrap_or(0)
                    .saturating_mul(1000)
            });
    let max_admitted = progress
        .effects
        .back()
        .map(|queued| queued.sequence)
        .unwrap_or(0);
    let metrics = ThreadPersistenceMetrics {
        fault_generation: progress.fault_generation,
        fault: progress.fault,
        history_admitted_sequence: max_admitted.max(progress.durable),
        history_durable_sequence: progress.durable,
        pending_operations,
        pending_bytes,
        in_flight_bytes: progress.in_flight_bytes,
        oldest_pending_age_millis,
        pressure_paused: progress.pressure_paused,
    };
    inner.store.thread_persistence().report(
        &inner.thread.id,
        inner.owner,
        ThreadPersistenceReport {
            pending,
            error: progress.error.clone(),
            metrics,
        },
        calls,
    );
}

fn clear_recovered_fault(progress: &mut Progress) -> bool {
    if progress.retry_requested && progress.durable >= progress.fault_target {
        progress.error = None;
        progress.fault = None;
        progress.retry_requested = false;
        // The retry named this generation and the fixed target really landed, so an explicit
        // continue would be accepted now: that verified fact is what the UI is allowed to show.
        progress.fault_recovered = true;
        true
    } else {
        false
    }
}

impl ThreadStorageSink {
    pub(crate) async fn new(store: StudioStore, thread: crate::Thread) -> Result<Self> {
        let catalog = store.catalog();
        let registered = catalog
            .agent_by_thread(&thread.id)
            .context("Thread is not registered in the Studio catalog")?;
        let session_workspace = catalog
            .get_session(&registered.session_id)
            .map(|session| session.workspace_id)
            .context("session is not registered in the Studio catalog")?;
        anyhow::ensure!(
            session_workspace == thread.workspace_id
                && store.workspaces().get(&thread.workspace_id).is_some(),
            "Thread {} Project identity is not registered in workspaces",
            thread.id
        );
        // Complete any one-shot format upgrade before reserving a new writer
        // incarnation. Maintenance must never retire this initializer's channel.
        let history = store.history(&thread.id).await?;
        let owner = NEXT_WRITER_INCARNATION.fetch_add(1, Ordering::Relaxed);
        let registration = store.thread_persistence().claim(&thread.id, owner)?;
        let channel = registration.channel.clone();
        let conversation = store.conversation_store(&thread.id).await?;
        let mut workers = channel.workers.lock().await;
        ensure!(
            !channel.stopping.is_cancelled(),
            "history writer is stopping"
        );
        // A preceding incarnation may still be finishing one write. Observe its committed
        // watermark and seed this incarnation while holding the channel's single-writer lease.
        let writer_lease = channel.step_lock.lock().await;
        let (history_observer_stop, mut stop_observer) = tokio::sync::watch::channel(false);
        let inner = Arc::new(Inner {
            store,
            thread,
            conversation,
            owner,
            history: tokio::sync::OnceCell::new(),
            changed: channel.changed.clone(),
            channel: channel.clone(),
            history_observer_stop,
        });
        let mut history_updates = channel.subscribe();
        // Report the shared queue only after this incarnation has initialized its durable fence.
        // Registration alone cannot discharge a predecessor's obligations: this report proves
        // which retained facts are adopted and which have already become durable.
        {
            let progress = lock_progress(&inner);
            report(&inner, &progress);
        }
        publish_accounting(&inner, &history).await;
        drop(writer_lease);
        let observer = Arc::downgrade(&inner);
        let observer_stop = channel.stopping.clone();
        workers.push(tokio::spawn(async move {
            loop {
                tokio::select! {
                    result = history_updates.changed() => {
                        if result.is_err() {
                            break;
                        }
                        let Some(inner) = observer.upgrade() else {
                            break;
                        };
                        // Every incarnation must report shared history recovery for itself.
                        // This observer owns no calls watermark or accounting refresh work.
                        let progress = lock_progress(&inner);
                        report_with_calls(&inner, &progress, None);
                    },
                    _ = stop_observer.changed() => break,
                    () = observer_stop.cancelled() => break,
                }
            }
        }));
        let worker = inner.clone();
        let watchdog = Arc::downgrade(&inner);
        let watchdog_stop = channel.stopping.clone();
        workers.push(tokio::spawn(async move {
            while let Some(inner) = watchdog.upgrade() {
                inner.channel.detect_stall();
                drop(inner);
                tokio::select! {
                        () = tokio::time::sleep(Duration::from_secs(10)) => {},
                        () = watchdog_stop.cancelled() => break,
                }
            }
        }));
        workers.push(tokio::spawn(async move {
            let inner = worker;
            let _registration = registration;
            // 连续可重试失败的起点；任何一次成功的推进都清零。只有持续超过窗口才升级上报。
            let mut retrying_since: Option<Instant> = None;
            loop {
                // A deletion stop is published under progress before cancellation. Finish any
                // current SQL step, then leave without retries or a final preservation write.
                if inner.channel.stopping.is_cancelled() && lock_progress(&inner).deleting {
                    return;
                }
                retry_accounting(&inner);
                // The task keeps the persistence owner alive while it owes facts, even when the
                // last Thread or GUI handle is dropped. The same owner finishes its bounded
                // Summary handoff without making diagnostic failure a reliable-save failure.
                if inner.channel.stopping.is_cancelled() || Arc::strong_count(&inner) == 1 {
                    let reliable_clean = {
                        let progress = lock_progress(&inner);
                        let clean = progress.effects.is_empty() && progress.error.is_none();
                        if clean {
                            // Another incarnation may have completed the shared queue. Publish
                            // this owner's final obligations even if its observer was cancelled.
                            report(&inner, &progress);
                        }
                        clean
                    };
                    if reliable_clean {
                        let due = lock_progress(&inner)
                            .pending_accounting
                            .as_ref()
                            .map(|pending| pending.retry_at);
                        let Some(due) = due else {
                            return;
                        };
                        // Do not select the already-cancelled stop token while handing off:
                        // that would busy-loop instead of honoring the bounded retry deadline.
                        tokio::time::sleep_until(due).await;
                        continue;
                    }
                }
                let paused = {
                    let progress = lock_progress(&inner);
                    progress.error.is_some()
                        && !progress.retry_requested
                        && progress.fault != Some(crate::HistoryFault::QueueFull)
                };
                if paused {
                    // 通道可以把一个本 incarnation 自己没失败过的 Thread 标成失败：投影无法完成的
                    // 事实永远不会被交接，writer 因此既不写也不报错。协调器聚合的错误正是进程级
                    // drain 等待的那个事实，所以这里把通道的故障转成协调器可见的错误；否则暂停的
                    // 队列会把停机变成无界等待，而不是带着真实原因的显式失败。
                    {
                        let progress = lock_progress(&inner);
                        report(&inner, &progress);
                    }
                    tokio::select! {
                        () = inner.changed.notified() => {},
                        () = accounting_retry_due(&inner) => {},
                        () = inner.channel.stopping.cancelled() => {},
                    }
                    continue;
                }
                match step(&inner).await {
                    Ok(Step::Progressed) => {
                        retrying_since = None;
                        continue;
                    }
                    Ok(Step::Idle) => {
                        // Upstream preparation and delivery capacity are event-driven.
                        // The existing watchdog owns oldest-undurable stage detection.
                        tokio::select! {
                            () = inner.changed.notified() => {}
                            () = accounting_retry_due(&inner) => {}
                            () = inner.channel.stopping.cancelled() => {}
                        }
                    }
                    Ok(Step::Coalescing(deadline)) => {
                        tokio::select! {
                            () = tokio::time::sleep_until(deadline) => {}
                            () = inner.changed.notified() => {}
                            () = accounting_retry_due(&inner) => {}
                            () = inner.channel.stopping.cancelled() => {}
                        }
                    }
                    Err(error) => {
                        let message = error.to_string();
                        let now = Instant::now();
                        let since = *retrying_since.get_or_insert(now);
                        if !is_retryable_write(&message)
                            || now.saturating_duration_since(since) >= RETRYABLE_BUSY_WINDOW
                        {
                            let kind = crate::HistoryFault::WriteFailed;
                            record_error(
                                &inner,
                                kind,
                                FaultTarget::Queued,
                                message,
                                &safe_error_reasons(&error),
                            );
                            retrying_since = None;
                        } else {
                            note_absorbed_conflict(&inner);
                            tokio::select! {
                                () = tokio::time::sleep(Duration::from_secs(1)) => {},
                                () = inner.store.thread_persistence().retry_notified() => {},
                                () = accounting_retry_due(&inner) => {},
                                () = inner.channel.stopping.cancelled() => {},
                            }
                        }
                    }
                }
            }
        }));
        drop(workers);
        Ok(Self(inner))
    }

    pub(crate) fn binding(&self) -> ThreadStorageBinding {
        ThreadStorageBinding::new(
            self.clone(),
            self.0.channel.clone(),
            self.0.conversation.clone(),
        )
    }
}

/// Performs one unit of durable work.
pub(super) async fn step(inner: &Inner) -> Result<Step> {
    let _single_writer = inner.channel.step_lock.lock().await;
    {
        let mut progress = lock_progress(inner);
        // An explicit retry can arrive after an outstanding SQL call completed the fault's
        // fixed fence. Settle it even when no later effect can trigger a commit.
        if clear_recovered_fault(&mut progress) {
            report(inner, &progress);
        }
        // Another attached writer may have failed while this worker waited for step_lock.
        // The pre-lock loop check is not permission to retry that newly published generation.
        if progress.error.is_some()
            && !progress.retry_requested
            && progress.fault != Some(crate::HistoryFault::QueueFull)
        {
            return Ok(Step::Idle);
        }
    }
    let selected = {
        let mut progress = lock_progress(inner);
        let resident_pressure = {
            let index = inner.channel.order_index.lock_state();
            index.resident_blocked
                || HistoryChannel::other_resident_bytes(&progress)
                    .saturating_add(inner.channel.order_index.retained_bytes())
                    .saturating_add(inner.channel.delivery_bytes.load(Ordering::Acquire))
                    >= MAX_HISTORY_THREAD_BYTES
        };
        match batch::select(
            &mut progress,
            Instant::now(),
            inner.channel.process_bytes.load(Ordering::Acquire),
            resident_pressure,
        ) {
            batch::Selection::Idle => return Ok(Step::Idle),
            batch::Selection::Wait(deadline) => return Ok(Step::Coalescing(deadline)),
            batch::Selection::Ready(selected) => selected,
        }
    };
    batch::persist(inner, &selected).await?;
    let mut progress = lock_progress(inner);
    let index = inner.channel.order_index.lock_state();
    let mut released_bytes = 0_u64;
    for candidate in &selected {
        ensure!(
            progress
                .effects
                .front()
                .is_some_and(|head| head.sequence == candidate.sequence),
            "history queue head changed before acknowledgement"
        );
        let committed = progress.effects.pop_front().expect("checked queue head");
        let bytes = committed.bytes;
        let prepared_bytes = committed.prepared_bytes;
        progress.release_saved_at(committed.write.effect.committed_at);
        progress.prepared_bytes = progress.prepared_bytes.saturating_sub(prepared_bytes);
        progress.effect_bytes -= bytes;
        released_bytes = released_bytes
            .saturating_add(bytes)
            .saturating_add(PENDING_AGE_METADATA_BYTES);
        progress.durable = committed.sequence;
    }
    progress.in_flight = None;
    // Advancing the queue head is progress even when the next head has the same stage.
    progress.stage = None;
    progress.last_progress_at = None;
    progress.refresh_head_stage(Instant::now());
    #[cfg(test)]
    let sequence = progress.durable;
    inner.channel.commit_residents(&progress, &index);
    drop(index);
    clear_recovered_fault(&mut progress);
    report(inner, &progress);
    drop(progress);
    inner.channel.release_process_bytes(released_bytes);
    inner.changed.notify_one();
    #[cfg(test)]
    {
        // Publish only after the writer's own local and queued handles were both released.
        // A terminal producer may still pin them; the history test distinguishes that owner.
        drop(selected);
        inner.channel.effects_released.send_replace(sequence);
    }
    Ok(Step::Progressed)
}

/// Seeds the absolute accounting projection at reopen; normal commits return their own result.
async fn publish_accounting(inner: &Inner, history: &HistoryStore) {
    let result = async {
        let reader = history.reader();
        let Some(accounting) = reader.accounting(None).await? else {
            return Ok(());
        };
        let mut costs = Vec::new();
        let mut cursor = None;
        loop {
            let page = reader
                .costs_page(
                    None,
                    cursor,
                    crate::history::HistoryDemand {
                        max_rows: 512,
                        max_bytes: 1024 * 1024,
                    },
                )
                .await?;
            for entry in page.entries {
                let crate::history::HistoryBusinessRowHead::Cost(cost) = entry.head else {
                    continue;
                };
                costs.push(cost);
            }
            let Some(next) = page.next else {
                break;
            };
            cursor = Some(next);
        }
        let revision = accounting
            .updated_at
            .max(costs.iter().map(|cost| cost.updated_at).max().unwrap_or(0))
            as u64;
        let mut purposes =
            std::collections::BTreeMap::<Option<String>, Vec<crate::RuntimeCostAmount>>::new();
        for cost in costs {
            purposes
                .entry(cost.purpose)
                .or_default()
                .push(crate::RuntimeCostAmount {
                    currency: cost.currency,
                    amount: cost.cost_total,
                });
        }
        submit_accounting(
            inner,
            crate::studio::storage::calls::SessionUsageProjection {
                root_thread_id: inner.thread.root_thread_id.clone(),
                thread_id: inner.thread.id.clone(),
                revision,
                has_unpriced_usage: accounting.has_unpriced_usage,
                purpose_costs: purposes
                    .into_iter()
                    .map(|(purpose, estimated_costs)| {
                        crate::studio::storage::calls::PurposeUsageProjection {
                            purpose,
                            estimated_costs,
                        }
                    })
                    .collect(),
            },
        );
        Ok::<_, anyhow::Error>(())
    }
    .await;
    if let Err(error) = result {
        tracing::warn!(%error, "读取独立累计统计投影失败");
    }
}

/// Retain only the latest committed absolute projection; retries never re-read the checkpoint.
pub(super) fn submit_accounting(
    inner: &Inner,
    projection: crate::studio::storage::calls::SessionUsageProjection,
) {
    {
        let mut progress = lock_progress(inner);
        if progress
            .pending_accounting
            .as_ref()
            .is_some_and(|pending| pending.projection.revision > projection.revision)
        {
            return;
        }
        progress.pending_accounting = Some(PendingAccounting {
            projection,
            attempts: 0,
            retry_at: Instant::now(),
        });
    }
    retry_accounting(inner);
    inner.changed.notify_one();
}

fn retry_accounting(inner: &Inner) {
    // Admission is synchronous and nonblocking. Keep the shared owner state locked through it so
    // overlapping writer incarnations cannot consume the same retry or overwrite a newer Summary.
    let mut progress = lock_progress(inner);
    let Some(pending) = progress.pending_accounting.as_mut() else {
        return;
    };
    if pending.retry_at > Instant::now() {
        return;
    }
    pending.attempts += 1;
    pending.retry_at = Instant::now() + Duration::from_millis(100 << (pending.attempts - 1));
    let result = inner
        .store
        .calls()
        .replace_session_usage(pending.projection.clone());
    match result {
        Ok(()) => {
            progress.pending_accounting = None;
        }
        Err(error) => {
            tracing::warn!(%error, "累计统计投影未受理，可靠会话累计值已保存");
            if pending.attempts >= 5 {
                // A bounded, explicit best-effort gap, repaired from authority at reopen.
                inner.store.calls().mark_statistics_gap();
                progress.pending_accounting = None;
            }
        }
    }
}

async fn accounting_retry_due(inner: &Inner) {
    let due = lock_progress(inner)
        .pending_accounting
        .as_ref()
        .map(|pending| pending.retry_at);
    if let Some(due) = due {
        tokio::time::sleep_until(due).await;
    } else {
        std::future::pending::<()>().await;
    }
}

#[derive(Clone, Copy)]
pub(super) enum FaultTarget {
    Queued,
    NextWrite,
}

pub(super) fn record_error(
    inner: &Inner,
    kind: crate::HistoryFault,
    target: FaultTarget,
    message: String,
    reasons: &[&str],
) {
    {
        let mut progress = lock_progress(inner);
        progress.fault_generation = progress.fault_generation.saturating_add(1);
        progress.fault_target = progress
            .effects
            .back()
            .map_or(progress.durable, |queued| queued.sequence);
        if matches!(target, FaultTarget::NextWrite) {
            // Rejecting a ticket did not save any new fact. Equal old watermarks cannot
            // verify repair; a later successful write must cross this failure boundary.
            progress.fault_target = progress
                .fault_target
                .max(progress.durable.saturating_add(1));
        }
        progress.retry_requested = false;
        progress.fault = Some(kind);
        progress.error = Some(message);
        progress.fault_recovered = false;
        // A failed publication is no longer being serialized; the retained checkpoint stays queued
        // for retry, and the metric must not keep reporting it as actively saving.
        progress.in_flight_bytes = 0;
        inner.channel.diagnose(
            &progress,
            Instant::now(),
            if kind == crate::HistoryFault::BlobFailed {
                "blob_fence"
            } else {
                "history_writer"
            },
            kind,
            reasons,
        );
        report(inner, &progress);
    }
    inner.changed.notify_one();
}

pub(super) fn safe_error_reasons(error: &anyhow::Error) -> Vec<&'static str> {
    error
        .chain()
        .take(4)
        .map(|cause| {
            if let Some(io) = cause.downcast_ref::<std::io::Error>() {
                match io.kind() {
                    std::io::ErrorKind::NotFound => "io_not_found",
                    std::io::ErrorKind::PermissionDenied => "io_permission_denied",
                    std::io::ErrorKind::TimedOut => "io_timed_out",
                    std::io::ErrorKind::Interrupted => "io_interrupted",
                    _ => "io_error",
                }
            } else if cause.is::<sea_orm::DbErr>() {
                "database_error"
            } else if cause.is::<sea_orm::sqlx::Error>() {
                "sql_driver_error"
            } else {
                "redacted_error"
            }
        })
        .collect()
}

/// Keeps the observable metrics honest while one retryable conflict is absorbed.
///
/// The failed step is no longer writing, so the in-flight byte gauge must not keep claiming a write
/// in progress; the queued effects stay counted, so the process-wide drain still waits and this
/// incarnation never looks settled. No error is published, so `pressure()`/`cold_error` stay clear
/// and the next model admission is not failed by a conflict the writer is still resolving.
fn note_absorbed_conflict(inner: &Inner) {
    let mut progress = lock_progress(inner);
    progress.in_flight_bytes = 0;
    report(inner, &progress);
}

impl ThreadStorageSink {
    fn storage_status(&self, thread_id: &str, inspect_idle: bool) -> StorageIdleStatus {
        if thread_id != self.0.thread.id {
            return StorageIdleStatus {
                pressure: StoragePressure {
                    error: Some(storage_error("Thread persistence owner mismatch")),
                    ..Default::default()
                },
                reclaimable_thread_bytes: None,
            };
        }
        let progress = lock_progress(&self.0);
        // The Thread's budget covers every resident body this Thread presents, and one of them only
        // once: the effects still queued, the prepared product batches the reliable handoff still
        // retains (the writer's queue length alone would under-report a Thread whose projection is
        // already done but whose save is not), the bodies its live projection and report accumulator
        // keep after their batch became durable, and the accepted bytes retained by in-flight
        // model/tool output. Those accepted bytes are what a Thread about to publish its result
        // holds; leaving them out would report a Thread as idle while a call is buffering its answer.
        let reserved = progress
            .operation_output
            .values()
            .fold(0_u64, |total, output| {
                total.saturating_add(output.retained())
            });
        let delivery_bytes = self.0.channel.delivery_bytes.load(Ordering::Acquire);
        let (index_bytes, reclaimable) = if inspect_idle {
            let index = self.0.channel.order_index.lock_state();
            let index_bytes = self.0.channel.order_index.retained_bytes();
            // A durable projection is reconstructible, but an unfinished source, handoff,
            // delivery or output reservation remains an obligation of this incarnation.
            let reclaimable = if progress.effects.is_empty()
                && progress.in_flight.is_none()
                && progress.projection_pending.is_none()
                && progress.operation_output.is_empty()
                && delivery_bytes == 0
                && self.0.channel.delivery_admissions.load(Ordering::Acquire) == 0
                && index.is_idle()
            {
                Some(progress.projection_bytes.saturating_add(index_bytes))
            } else {
                None
            };
            (index_bytes, reclaimable)
        } else {
            // Ordinary pressure reads stay on the existing atomic accounting path.
            (self.0.channel.order_index.retained_bytes(), None)
        };
        let bytes = progress
            .effect_bytes
            .saturating_add(progress.queue_metadata_bytes)
            .saturating_add(progress.prepared_bytes)
            .saturating_add(progress.projection_bytes)
            .saturating_add(index_bytes)
            .saturating_add(delivery_bytes)
            .saturating_add(reserved);
        let pressure = StoragePressure {
            thread_bytes: bytes,
            store_bytes: self.0.channel.process_bytes.load(Ordering::Acquire),
            // Typed durability receipt: the owner releases the live effect window from this at a
            // storage safety point instead of waiting for an explicit `flush` command.
            durable_sequence: progress.durable,
            // Typed fault category: the history channel already classifies its own failure, so no
            // consumer has to read the error text to know what failed.
            fault: progress.fault.map(storage_fault_kind),
            fault_generation: progress.fault_generation,
            // The writer's own recovery receipt, named by generation: `fault_recovered` means the
            // retry of *this* generation reached the fixed durable target, so the owner can require
            // that exact verdict before releasing the fault it holds instead of accepting an older
            // generation's success.
            recovered_generation: progress
                .fault_recovered
                .then_some(progress.fault_generation),
            error: progress.error.as_deref().map(storage_error),
        };
        StorageIdleStatus {
            pressure,
            reclaimable_thread_bytes: reclaimable,
        }
    }
}

impl ThreadStorageSink {
    pub(crate) fn reserve_observed_item(
        &self,
        thread_id: &str,
        attempt_id: &str,
        item_id: &str,
    ) -> Result<(), ColdStoreError> {
        if thread_id != self.0.thread.id {
            return Err(ColdStoreError {
                source: Box::new(std::io::Error::other("Thread persistence owner mismatch")),
            });
        }
        // The kernel reserves a raw provider presentation identity synchronously, before a
        // coalescing preview can discard it. The Runtime's own execution-order index answers:
        // the live projection draws from the same index, so the preview frame and the terminal
        // commit of one identity always resolve the same ordinal without a second allocator.
        let result = self
            .0
            .channel
            .order_index
            .reserve_observed(attempt_id, item_id);
        if let Err(error) = &result {
            record_error(
                &self.0,
                if error.is::<ExecutionIndexBudgetFull>() {
                    crate::HistoryFault::QueueFull
                } else {
                    crate::HistoryFault::WriteFailed
                },
                FaultTarget::Queued,
                error.to_string(),
                &safe_error_reasons(error),
            );
        } else {
            let progress = lock_progress(&self.0);
            report(&self.0, &progress);
        }
        result.map(|_| ()).map_err(|source| ColdStoreError {
            source: source.into_boxed_dyn_error(),
        })
    }

    pub(crate) fn subscribe_pressure(
        &self,
        thread_id: &str,
    ) -> Option<tokio::sync::watch::Receiver<()>> {
        (thread_id == self.0.thread.id).then(|| self.0.channel.pressure_changed.subscribe())
    }

    pub(crate) fn reserve_operation_output(
        &self,
        thread_id: &str,
        operation_id: &str,
        max_bytes: u64,
    ) -> Result<u64, ColdStoreError> {
        if thread_id != self.0.thread.id {
            return Err(cold_error("Thread persistence owner mismatch"));
        }
        self.0
            .channel
            .reserve_operation_output(operation_id, max_bytes)
            .ok_or_else(|| {
                // No headroom is backpressure, not a failed save: the caller waits at a storage
                // safety point and retries, and the Thread resumes by itself once the budget frees
                // up. Latching a hard fault here would turn a transient wait into a pause that only
                // an explicit resume could release.
                cold_error(&format!(
                    "reliable budget exhausted reserving operation {operation_id}"
                ))
            })
    }

    pub(crate) fn charge_operation_output(
        &self,
        thread_id: &str,
        operation_id: &str,
        accepted_bytes: u64,
    ) -> Result<(), ColdStoreError> {
        if thread_id != self.0.thread.id {
            return Err(cold_error("Thread persistence owner mismatch"));
        }
        // The typed refusal a ceiling cannot hold must reach the caller unchanged: it is what makes
        // the producer cancel the call with the bytes it already has instead of buffering output
        // this process could not retain.
        self.0
            .channel
            .charge_operation_output(operation_id, accepted_bytes)
    }

    pub(crate) fn release_operation_output(&self, thread_id: &str, operation_id: &str) {
        if thread_id == self.0.thread.id {
            self.0.channel.release_operation_output(operation_id);
        }
    }

    pub(crate) fn pressure(&self, thread_id: &str) -> StoragePressure {
        self.storage_status(thread_id, false).pressure
    }

    pub(crate) fn idle_status(&self, thread_id: &str) -> StorageIdleStatus {
        self.storage_status(thread_id, true)
    }

    pub(crate) fn admit_export(
        &self,
        thread_id: &str,
        write: Arc<HistoryExport>,
    ) -> Result<(), ColdStoreError> {
        if self.0.channel.stopping.is_cancelled() {
            return Err(cold_error("history writer is stopped"));
        }
        if thread_id != self.0.thread.id
            || write.effect.thread_id != thread_id
            || write.effect.sequence == 0
        {
            // A contract failure is terminal for this sink and never a transient conflict: publish it
            // so `pressure().error` — the one report core mirrors into its own storage latch — agrees
            // with the error this call returns instead of letting the latch look recovered.
            record_error(
                &self.0,
                crate::HistoryFault::WriteFailed,
                FaultTarget::NextWrite,
                "Thread persistence ticket mismatch".to_owned(),
                &["ticket_mismatch"],
            );
            return Err(ColdStoreError {
                source: Box::new(std::io::Error::other("Thread persistence ticket mismatch")),
            });
        }
        let sequence = write.effect.sequence;
        #[cfg(feature = "benchmarks")]
        self.0
            .store
            .calls()
            .observation()
            .increment(BenchMetric::EffectEncode);
        let bytes = encoded_bytes(&write.effect);
        let mut progress = lock_progress(&self.0);
        if progress.stopped {
            return Err(cold_error("history writer is stopped"));
        }
        if sequence > progress.durable && progress.queue_offset(sequence).is_none() {
            let expected = progress.effects.back().map_or_else(
                || progress.durable.checked_add(1),
                |tail| tail.sequence.checked_add(1),
            );
            if expected != Some(sequence) {
                let message = format!(
                    "Thread {thread_id} persistence sequence {sequence} does not follow {}",
                    expected.map_or_else(
                        || "the exhausted sequence space".to_owned(),
                        |expected| { format!("write_seq {expected}") }
                    )
                );
                if progress.error.is_none() {
                    progress.fault_generation = progress.fault_generation.saturating_add(1);
                    progress.retry_requested = false;
                }
                progress.fault_target = progress.fault_target.max(sequence);
                progress.fault = Some(crate::HistoryFault::WriteFailed);
                progress.error = Some(message.clone());
                progress.fault_recovered = false;
                report(&self.0, &progress);
                drop(progress);
                self.0.changed.notify_one();
                return Err(cold_error(&message));
            }
            let mut index = self.0.channel.order_index.lock_state();
            let queued_bytes = progress
                .effect_bytes
                .saturating_add(progress.queue_metadata_bytes)
                .saturating_add(self.0.channel.order_index.retained_bytes());
            // The fact takes over the bytes of its own operation's reservation instead of being
            // charged next to them; only bytes not already charged need new headroom.
            let (transfer, covered) = output_transfer_plan(
                &progress,
                write.output_claim.as_deref(),
                bytes.saturating_add(PENDING_AGE_METADATA_BYTES),
            );
            let added = bytes
                .saturating_add(PENDING_AGE_METADATA_BYTES)
                .saturating_sub(covered);
            // Preserve the admission checks' short-circuit order. In particular, never reserve
            // process bytes when an earlier limit refuses the ticket, or reserve twice for logging.
            let rejection_kind = if progress.effects.len() >= MAX_HISTORY_BATCHES {
                Some("slot")
            } else if queued_bytes
                .checked_add(bytes.saturating_add(PENDING_AGE_METADATA_BYTES))
                .is_none_or(|total| total > MAX_HISTORY_THREAD_BYTES)
            {
                Some("thread_bytes")
            } else if added > 0 && !self.0.channel.reserve(added) {
                Some("process_budget")
            } else {
                None
            };
            if let Some(rejection_kind) = rejection_kind {
                let message =
                    format!("history queue full for Thread {thread_id} at write_seq {sequence}");
                tracing::debug!(
                    target: "conversation_work",
                    operation = "history_admission",
                    rejection_kind,
                    thread_id,
                    write_seq = sequence,
                    queued_effects = progress.effects.len(),
                    // Same retained-byte scope as the Thread admission check, not the broader
                    // pressure gauge that also includes projection/prepared/output residents.
                    queued_thread_bytes = queued_bytes,
                    effect_bytes = bytes,
                    thread_bytes_increment = bytes.saturating_add(PENDING_AGE_METADATA_BYTES),
                    process_bytes_increment = added,
                    // Other Threads can change this atomic after reserve refused; this is an
                    // observation, not the failed compare/update's exact budget value.
                    process_bytes_observed = self.0.channel.process_bytes.load(Ordering::Acquire),
                    head = ?progress.effects.front().map(|effect| effect.sequence),
                    admitted = progress.effects.back().map_or(progress.durable, |effect| effect.sequence),
                    durable = progress.durable,
                    stage = ?progress.stage.map(HistoryStage::as_str),
                    fault_generation = progress.fault_generation,
                    "history admission refused"
                );
                drop(index);
                report(&self.0, &progress);
                self.0.changed.notify_one();
                return Err(ColdStoreError {
                    source: Box::new(pl_core::thread::cold::StorageAdmissionBackpressure(message)),
                });
            }
            if let Err(error) = self.0.channel.order_index.reserve_boundaries_locked(
                &mut index,
                &write.effect,
                added,
            ) {
                // Roll back only this admission's process claim; notifications follow the locks.
                self.0
                    .channel
                    .process_bytes
                    .fetch_sub(added, Ordering::AcqRel);
                let message = error.to_string();
                if error.is::<ExecutionIndexBudgetFull>() {
                    drop(index);
                    report(&self.0, &progress);
                    self.0.changed.notify_one();
                    return Err(ColdStoreError {
                        source: Box::new(pl_core::thread::cold::StorageAdmissionBackpressure(
                            message,
                        )),
                    });
                }
                if progress.error.is_none() {
                    progress.fault_generation = progress.fault_generation.saturating_add(1);
                    progress.retry_requested = false;
                }
                progress.fault_target = progress.fault_target.max(sequence);
                progress.fault = Some(crate::HistoryFault::WriteFailed);
                progress.error = Some(message.clone());
                progress.fault_recovered = false;
                drop(index);
                report(&self.0, &progress);
                self.0.changed.notify_one();
                return Err(cold_error(&message));
            }
            for (operation, taken) in transfer {
                if let Some(output) = progress.operation_output.get_mut(&operation) {
                    output.transferred += taken;
                }
            }
            let admitted_at = Instant::now();
            progress.effects.push_back(QueuedEffect {
                _conversation: Some(self.0.conversation.clone()),
                sequence,
                admitted_at,
                write: write.clone(),
                bytes,
                // The projection owner takes this entry over from the same queue, in this order.
                prepared: None,
                prepared_bytes: 0,
            });
            progress.refresh_head_stage(admitted_at);
            progress.effect_bytes += bytes;
            progress.admit_saved_at(write.effect.committed_at);
            self.0.channel.commit_residents(&progress, &index);
            drop(index);
        }
        // 首次受理从 checkpoint 继承已折叠的累计摘要，然后只折叠本 incarnation 的新 effect。
        if progress.usage.applied_sequence == 0 && write.state.usage_summary.applied_sequence > 0 {
            progress.usage = write.state.usage_summary.clone();
        }
        progress.pressure_paused = write.state.persistence.pressure_paused;
        report(&self.0, &progress);
        drop(progress);
        self.0.changed.notify_one();
        Ok(())
    }

    pub(crate) fn read_tool_task(
        &self,
        thread_id: &str,
        task_id: &str,
    ) -> impl std::future::Future<
        Output = Result<Option<pl_core::thread::cold::DurableToolTask>, ColdStoreError>,
    > + Send {
        let store = self.0.store.clone();
        let owner = self.0.thread.id.clone();
        let task_id = task_id.to_owned();
        // Before flush the original reliable queue still owns these exact producer facts.
        // Cloning under its lock bridges reclamation into the immutable History read below.
        let pending = lock_progress(&self.0)
            .effects
            .iter()
            .rev()
            .find_map(|queued| {
                let effect = &queued.write.effect;
                let task = effect.tasks.iter().find(|task| task.id == task_id)?;
                let delivery = effect
                    .deliveries
                    .iter()
                    .find(|delivery| delivery.call_id == task.call_id)?;
                Some(pl_core::thread::cold::DurableToolTask {
                    task: task.clone(),
                    delivery: Some(delivery.clone()),
                })
            });
        async move {
            if thread_id != owner {
                return Err(cold_error("Thread persistence owner mismatch"));
            }
            if let Some(pending) = pending {
                return Ok(Some(pending));
            }
            let history = store
                .history(&owner)
                .await
                .map_err(|error| cold_error(&error.to_string()))?;
            let reader = history.reader();
            let result = crate::studio::storage::tool_task::read(&reader, &task_id).await;
            reader.close().await;
            result.map_err(|error| cold_error(&error.to_string()))
        }
    }
}

fn storage_error(message: &str) -> Arc<ColdStoreError> {
    Arc::new(ColdStoreError {
        source: Box::new(std::io::Error::other(message.to_owned())),
    })
}

/// The protocol's typed history fault as the core storage fault the owner mirrors.
///
/// Both sides are already typed values: this is a rename, not a classification. Core therefore never
/// sees an error string that it would have to interpret to know what failed.
fn storage_fault_kind(fault: crate::HistoryFault) -> pl_core::thread::cold::StorageFaultKind {
    use crate::HistoryFault;
    use pl_core::thread::cold::StorageFaultKind;
    match fault {
        HistoryFault::QueueFull => StorageFaultKind::QueueFull,
        HistoryFault::WriteFailed => StorageFaultKind::WriteFailed,
        HistoryFault::WriterUnavailable => StorageFaultKind::WriterUnavailable,
        HistoryFault::NoProgress => StorageFaultKind::NoProgress,
        HistoryFault::CheckpointFailed => StorageFaultKind::CheckpointFailed,
        HistoryFault::BlobFailed => StorageFaultKind::BlobFailed,
    }
}

/// One typed cold-store failure without the shared-error wrapper.
pub(super) fn cold_error(message: &str) -> ColdStoreError {
    ColdStoreError {
        source: Box::new(std::io::Error::other(message.to_owned())),
    }
}

impl pl_core::thread::history_sink::HistorySink for ThreadStorageSink {
    fn fold_usage(&self, summary: &mut UsageSummary, effect: &pl_core::thread::ThreadEffectBatch) {
        match crate::studio::thread_projection::PreparedAccounting::prepare(effect) {
            Ok(accounting) => accounting.fold_into(summary),
            Err(error) => record_error(
                &self.0,
                crate::HistoryFault::WriteFailed,
                FaultTarget::NextWrite,
                error.to_string(),
                &["accounting_contract"],
            ),
        }
    }
    fn reserve_observed_item(
        &self,
        thread: &str,
        attempt: &str,
        item: &str,
    ) -> Result<(), ColdStoreError> {
        ThreadStorageSink::reserve_observed_item(self, thread, attempt, item)
    }
    fn reserve_operation_output(
        &self,
        thread: &str,
        operation: &str,
        max: u64,
    ) -> Result<u64, ColdStoreError> {
        ThreadStorageSink::reserve_operation_output(self, thread, operation, max)
    }
    fn charge_operation_output(
        &self,
        thread: &str,
        operation: &str,
        bytes: u64,
    ) -> Result<(), ColdStoreError> {
        ThreadStorageSink::charge_operation_output(self, thread, operation, bytes)
    }
    fn release_operation_output(&self, thread: &str, operation: &str) {
        ThreadStorageSink::release_operation_output(self, thread, operation)
    }
    fn pressure(&self, thread: &str) -> StoragePressure {
        ThreadStorageSink::pressure(self, thread)
    }
    fn idle_status(&self, thread: &str) -> StorageIdleStatus {
        ThreadStorageSink::idle_status(self, thread)
    }
    fn subscribe_pressure(&self, thread: &str) -> Option<tokio::sync::watch::Receiver<()>> {
        ThreadStorageSink::subscribe_pressure(self, thread)
    }
    fn admit(&self, thread: &str, export: Arc<HistoryExport>) -> Result<(), ColdStoreError> {
        self.admit_export(thread, export)
    }
    fn read_tool_task(
        &self,
        thread: &str,
        task: &str,
    ) -> impl std::future::Future<
        Output = Result<Option<pl_core::thread::cold::DurableToolTask>, ColdStoreError>,
    > + Send {
        ThreadStorageSink::read_tool_task(self, thread, task)
    }
}

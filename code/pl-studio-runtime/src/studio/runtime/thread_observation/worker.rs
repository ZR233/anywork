//! Drive the projection from committed Thread and storage progress.

use super::directory;
use super::live_owner::{HandoffMode, LiveOwner, PendingHandoff};
use super::registry::ObservationServices;
use super::slot::ObservationSlot;
use crate::studio::storage::thread_writer::HistoryChannel;
use anyhow::{Context, Result};
use pl_core::thread::{HistoryExport, ThreadHandle, ThreadLifecycle, ThreadSnapshot};
use std::sync::Arc;
use tokio::sync::{Notify, broadcast, watch};

#[derive(Clone, Default)]
pub(in crate::studio::runtime) struct Progress {
    pub(super) initialized: bool,
    pub(super) applied: u64,
    /// Newest commit this projection owner had handed over when it applied `applied`.
    ///
    /// The durable barrier of a settled observation waits for exactly this ticket. It is not the
    /// absolute commit watermark: a Thread re-activated in this process starts from a fresh reliable
    /// channel whose commits are already durable, so waiting for the checkpoint's sequence would wait
    /// for a watermark that can never move.
    pub(super) handoff: u64,
    pub(super) error: Option<Arc<anyhow::Error>>,
    pub(super) finished: bool,
}

pub(super) struct WorkerState {
    /// Frozen at observer installation, before any asynchronous history preparation can finish late.
    pub(super) native_directory: Option<crate::studio::product_event_bus::NativeAgentObservation>,
    pub(super) deletion: tokio_util::sync::CancellationToken,
    pub(super) join_failure: std::sync::Mutex<Option<Arc<anyhow::Error>>>,
    pub(super) terminal_transfer: Arc<
        std::sync::Mutex<Option<Arc<crate::thread_assembler::review_dispatch::TerminalDelivery>>>,
    >,
    pub(super) progress: watch::Sender<Progress>,
    pub(super) retry: Notify,
    /// The Thread's reliable admission channel, shared with its history writer.
    ///
    /// An explicit synchronization asks the writer that took the projection's handoff how far
    /// it is durable. Live processing never waits for that barrier. The handle is captured
    /// here, at observation time, so the barrier observes the very incarnation the writer admits
    /// into instead of a channel that a cleanly detached predecessor already released.
    pub(super) channel: Arc<HistoryChannel>,
    /// Explicit reconciliation is observation only, even when it catches a newly committed Turn.
    pub(super) reconciliation_through: Arc<std::sync::atomic::AtomicU64>,
    pub(super) observed_before_execution: bool,
}
fn product_revision(
    snapshot: &ThreadSnapshot,
) -> (
    u64,
    ThreadLifecycle,
    Option<pl_core::thread::ActiveExecution>,
) {
    (
        snapshot.commit_sequence,
        snapshot.lifecycle,
        snapshot.execution.clone(),
    )
}

pub(super) async fn run(
    projector: ObservationServices,
    id: String,
    thread: ThreadHandle,
    state: Arc<WorkerState>,
    recovered_through: u64,
    slot: Arc<ObservationSlot>,
    mut catalogs: broadcast::Receiver<()>,
) {
    use futures::FutureExt;
    let mut updates = thread.subscribe();
    let mut handoff = state.channel.subscribe();
    let mut persistence = projector.store.thread_persistence().subscribe();
    let mut settings = projector.settings_updates.clone();
    settings.borrow_and_update();
    let mut settings_open = true;
    let mut current = thread.snapshot();
    let continuous = state.observed_before_execution;
    let mut worker = ProjectionWorker {
        services: projector,
        id,
        thread,
        state,
        recovered_through,
        slot,
        live: None,
        live_floor: recovered_through,
        continuous,
    };
    // Execution preparation and retirement can change without a history commit. The directory must
    // follow that identity as well as committed facts, but not pay for preview-only publications.
    // The live projection still follows every owner snapshot through the same single publisher.
    let mut projected = None;
    loop {
        let issue_id = format!("tool-cleanup:{}", worker.id);
        let issue = (!current.tool_cleanup.failures.is_empty()
            || current.runtime_bundle.model_cleanup_failure.is_some())
        .then(|| crate::studio::StudioRecoveryIssue {
            id: issue_id.clone(),
            scope: crate::studio::StudioRecoveryIssueScope::Thread,
            category: crate::studio::StudioRecoveryIssueCategory::ToolCatalog,
            impact: crate::studio::StudioRecoveryImpact::Advisory,
            action: crate::studio::StudioRecoveryIssueAction::Retry,
            workspace_id: None,
            thread_id: Some(worker.id.clone()),
            worktree: None,
            message: current
                .tool_cleanup
                .failures
                .iter()
                .map(|failure| format!("{}: {}", failure.tool_id, failure.error))
                .chain(
                    current
                        .runtime_bundle
                        .model_cleanup_failure
                        .iter()
                        .map(|error| format!("Model session: {error}")),
                )
                .collect::<Vec<_>>()
                .join("; "),
        });
        worker.services.recovery.update_if_current(
            &issue_id,
            issue,
            || {
                worker
                    .services
                    .session_of(&worker.id)
                    .and_then(|session| session.observed_thread(&worker.id))
                    .is_some_and(|thread| thread.same_instance(&worker.thread))
            },
            |issues| {
                worker.services.events.emit_recovery_state(issues);
            },
        );
        let revision = product_revision(&current);
        let products = projected.as_ref() != Some(&revision);
        // Read the coordinator's newest typed facts before publishing: a storage change is a fact
        // this pass has to carry, exactly like a commit or a preview it also projects.
        let detail = persistence
            .borrow_and_update()
            .threads
            .iter()
            .find(|detail| detail.thread_id == worker.id)
            .cloned();
        // The projection stays isolated behind `catch_unwind`, so a panicking projection is
        // still reported as an error instead of taking down the observation worker.
        // A closed physical owner hands its final Current to the independent JSON writer before
        // archive reconciliation. A failed History write cannot postpone that final save/join.
        let mut current_close = if current.lifecycle == ThreadLifecycle::Closed {
            if let Some(live) = worker.live.as_ref() {
                Some(
                    live.retained
                        .store
                        .close_current(
                            &worker.thread,
                            crate::thread_assembler::ClosePurpose::Preserve,
                        )
                        .await,
                )
            } else {
                None
            }
        } else {
            None
        };
        let mut result =
            std::panic::AssertUnwindSafe(worker.project(&current, products, detail.as_ref()))
                .catch_unwind()
                .await
                .unwrap_or_else(|_| Err(anyhow::anyhow!("Thread product projection panicked")));
        if current.lifecycle == ThreadLifecycle::Closed
            && current_close.is_none()
            && let Some(live) = worker.live.as_ref()
        {
            current_close = Some(
                live.retained
                    .store
                    .close_current(
                        &worker.thread,
                        crate::thread_assembler::ClosePurpose::Preserve,
                    )
                    .await,
            );
        }
        if let Some(Err(close)) = current_close {
            result = Err(match result {
                Ok(()) => close,
                Err(archive) => {
                    archive.context(format!("independent Current close also failed: {close:#}"))
                }
            });
        }
        match result {
            Ok(()) => {
                worker.continuous = true;
                if products {
                    projected = Some(revision);
                }
                let finished = current.lifecycle == ThreadLifecycle::Closed;
                worker.state.progress.send_replace(Progress {
                    initialized: true,
                    applied: current.commit_sequence,
                    handoff: worker.state.channel.handoff_ticket(),
                    error: None,
                    finished: false,
                });
                if finished {
                    // 固定目标 ticket：只等待本次观察已受理的产品写入，不等待整个系统空闲。
                    let target = worker.services.writer.admitted_ticket();
                    match worker.services.writer.flush_through(target).await {
                        Ok(()) => {
                            if let (Some(exporter), Some(live)) =
                                (&worker.services.run_export, &worker.live)
                            {
                                let status_value =
                                    crate::studio::thread_projection::status(&current);
                                let status = serde_json::to_value(status_value)
                                    .ok()
                                    .and_then(|value| value.as_str().map(str::to_owned));
                                let (aborted, error) = match &current.input_execution {
                                    pl_core::thread::input::InputExecution::Failed { error } => {
                                        (false, Some(error.to_string()))
                                    }
                                    pl_core::thread::input::InputExecution::Interrupting {
                                        ..
                                    } => (true, None),
                                    _ => (false, None),
                                };
                                let (history_cut, history_seq) =
                                    match live.history_reader.capture_position().await {
                                        Ok(position) => position,
                                        Err(error) => {
                                            worker.state.progress.send_modify(|progress| {
                                                progress.error = Some(Arc::new(error.into()));
                                                progress.finished = true;
                                            });
                                            return;
                                        }
                                    };
                                exporter.record_thread_final_cut(
                                    crate::studio::runtime::run_export::RetiredThreadCut {
                                        thread_id: worker.id.clone(),
                                        through_effect_seq: current.commit_sequence,
                                        history: live.history_reader.clone(),
                                        history_cut,
                                        history_seq,
                                        summary: live.retained.usage.clone(),
                                        status,
                                        aborted,
                                        error,
                                    },
                                );
                            }
                            if let Some(live) = &worker.live
                                && let Err(error) = live
                                    .retained
                                    .store
                                    .close_current(
                                        &worker.thread,
                                        crate::thread_assembler::ClosePurpose::Preserve,
                                    )
                                    .await
                            {
                                worker.state.progress.send_modify(|progress| {
                                    progress.error = Some(Arc::new(error));
                                    progress.finished = true;
                                });
                                return;
                            }
                            worker
                                .state
                                .progress
                                .send_modify(|progress| progress.finished = true);
                            return;
                        }
                        Err(error) => {
                            worker.continuous = false;
                            worker.live_floor = worker.live_floor.max(current.commit_sequence);
                            worker
                                .state
                                .reconciliation_through
                                .fetch_max(worker.live_floor, std::sync::atomic::Ordering::AcqRel);
                            worker.state.progress.send_modify(|progress| {
                                progress.error = Some(Arc::new(anyhow::Error::new(error)));
                                progress.finished = false;
                            });
                        }
                    }
                }
            }
            Err(error) => {
                // Archive faults do not revoke the original Current publisher. Its latest RAM
                // preview and State keep following this physical owner without a history read.
                if let Some(live) = worker.live.as_mut() {
                    if let Err(current_error) = live.stream(&current, detail.as_ref()).await {
                        worker.state.progress.send_modify(|progress| {
                            progress.error = Some(Arc::new(current_error));
                        });
                    }
                    live.observe_storage(&current, detail.as_ref());
                }
                worker.continuous = false;
                worker.live_floor = worker.live_floor.max(current.commit_sequence);
                worker
                    .state
                    .reconciliation_through
                    .fetch_max(current.commit_sequence, std::sync::atomic::Ordering::AcqRel);
                worker
                    .state
                    .progress
                    .send_modify(|progress| progress.error = Some(Arc::new(error)));
            }
        }
        if current.lifecycle == ThreadLifecycle::Closed {
            tokio::select! {
                () = worker.state.retry.notified() => {}
                _ = handoff.changed() => {}
            }
            current = worker.thread.snapshot();
            continue;
        }
        tokio::select! {
            () = worker.state.retry.notified() => current = worker.thread.snapshot(),
            // A handoff the writer is waiting for may be the only reason this worker still has work
            // to do; re-run the projection so a deferred admission is taken over and saved.
            _ = handoff.changed() => current = worker.thread.snapshot(),
            // A typed storage change with no owner frame still has to reach subscribers; re-run the
            // pass so the owner republishes the state it just read.
            _ = persistence.changed() => current = worker.thread.snapshot(),
            changed = settings.changed(), if settings_open => {
                settings_open = changed.is_ok();
                settings.borrow_and_update();
                current = worker.thread.snapshot();
            }
            // Availability may change with no core publication or business
            // commit. The same owner reprojects against the new catalog.
            change = catalogs.recv(), if !catalogs.is_closed() => {
                match change {
                    Ok(_) | Err(broadcast::error::RecvError::Lagged(_)) => {
                        current = worker.thread.snapshot();
                    }
                    Err(broadcast::error::RecvError::Closed) => {}
                }
            }
            update = updates.next() => match update {
                Some(snapshot) => current = snapshot,
                None => {
                    let final_snapshot = worker.thread.snapshot();
                    if final_snapshot.lifecycle == ThreadLifecycle::Closed {
                        // Physical close can retire the subscription before this consumer takes
                        // its last update. The original owner still retains its final snapshot;
                        // process that real Closed state and complete Current/History shutdown.
                        current = final_snapshot;
                        continue;
                    }
                    worker.continuous = false;
                    worker.live_floor = worker.live_floor.max(worker.thread.snapshot().commit_sequence);
                    worker.state.reconciliation_through.fetch_max(worker.live_floor, std::sync::atomic::Ordering::AcqRel);
                    worker.state.progress.send_modify(|progress| progress.error = Some(Arc::new(anyhow::anyhow!("Thread subscription ended before its final projection"))));
                    tokio::select! {
                        () = worker.state.retry.notified() => {}
                        _ = handoff.changed() => {}
                    }
                    current = worker.thread.snapshot();
                }
            }
        }
    }
}

/// Everything one Thread's observation worker carries across a projection: the product services, the
/// owner handle it reads committed effects from, its progress and retry channel, the feed it
/// broadcasts on and the live projection it folds into.
///
/// Keeping this as one domain value is what lets the worker project without threading nine
/// independent arguments through every call; the live projection above stays a pure function of one
/// effect.
struct ProjectionWorker {
    services: ObservationServices,
    id: String,
    thread: ThreadHandle,
    state: Arc<WorkerState>,
    /// Committed watermark the Thread already had when this projection was seeded. Terminal reports
    /// for Turns at or below it are repairs, not fresh continuations, so they do not wake a parent.
    recovered_through: u64,
    slot: Arc<ObservationSlot>,
    live: Option<LiveOwner>,
    /// Commits already visible at installation or across an observation failure cannot first-send.
    live_floor: u64,
    continuous: bool,
}

async fn transfer_terminal(services: &ObservationServices, state: &WorkerState) -> Result<()> {
    let pending = state
        .terminal_transfer
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .clone();
    let Some(pending) = pending else {
        return Ok(());
    };
    let channel = pending
        .channel
        .as_ref()
        .context("terminal transfer has no history channel")?;
    anyhow::ensure!(
        channel.handoff_ticket() >= pending.sequence
            || channel.delivery_retry_mark().0 >= pending.sequence,
        "terminal transfer precedes handoff"
    );
    services
        .require_session(&pending.thread.id)?
        .start_terminal_delivery(pending.clone())
        .await?;
    let mut slot = state
        .terminal_transfer
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if slot
        .as_ref()
        .is_some_and(|current| Arc::ptr_eq(current, &pending))
    {
        *slot = None;
    }
    Ok(())
}

/// Waits until the history writer's durable watermark covers the handoff ticket `sequence`.
///
/// This deliberately does not use `Thread::flush`. That barrier targets *every commit the owner has
/// admitted*, including ones this projection has not handed over yet, and the writer refuses to save
/// a fact no projection holds — so an observer waiting on it would wait for its own next step, and
/// the request itself travels through the owner's command queue, which a running Turn only reaches at
/// its own safety points. Waiting for this projection's own handoff ticket asks for exactly the
/// commits it already prepared, in the order they were prepared, so it always completes, and a
/// channel that never saw a handoff (`0`) is trivially durable instead of waiting for a watermark a
/// re-activated Thread's fresh channel can no longer move.
///
/// The writer publishes its terminal diagnostic on the same channel, so a storage failure ends this
/// barrier with the real reason instead of hanging on a watermark that can no longer advance.
pub(super) async fn await_history_durable(
    channel: &HistoryChannel,
    id: &str,
    sequence: u64,
) -> Result<()> {
    channel.await_handoff_durable(id, sequence).await
}

/// The write this owner owes work on next: the retained handoff first, then the reliable queue.
///
/// The retained batch wins even when its queue entry has already left the unprojected set — the
/// owner still owes its report and handoff — and queue work is only picked up with no batch
/// retained, so a retry never depends on the queue still listing the commit.
fn next_projection_write(
    pending: &Option<PendingHandoff>,
    channel: &HistoryChannel,
) -> Option<Arc<HistoryExport>> {
    pending
        .as_ref()
        .map(|pending| Arc::clone(&pending.write))
        .or_else(|| channel.next_unprojected())
}

/// Resolves the association from the resident directory, reading storage on a cache miss.
async fn product_association(services: &ObservationServices, id: &str) -> Result<crate::Thread> {
    if let Some(thread) = services.events.thread_snapshot(id)? {
        return Ok(thread);
    }
    let association = services
        .store
        .read_thread(id)
        .await?
        .context("observed Thread has no product association")?;
    Ok(crate::Thread::from(association))
}

// The worker carries the projection owner, its feed and the product watermark across one projection;
// splitting them into a context struct would only hide the same state behind one more indirection.
impl ProjectionWorker {
    /// Takes over every admitted fact this projection owner has not folded yet, projects the current
    /// streaming overlay and, when `products` is set, the product directory and billing facts they
    /// imply.
    ///
    /// The reliable admission queue is the one source of committed work: a fact enters it when core
    /// commits it and leaves it only once this owner folded it *and* the durable store saved it, so
    /// the projection never races the owner's command queue or the disk. Facts the owner had already
    /// folded into the snapshot this projection was seeded from are taken over without being replayed
    /// as live frames.
    ///
    /// # Errors
    /// Returns a projection, storage association or directory failure. The worker reports it through
    /// its progress channel and retries the same watermark instead of skipping a commit.
    async fn project(
        &mut self,
        snapshot: &ThreadSnapshot,
        products: bool,
        persistence: Option<&crate::ThreadPersistenceSnapshot>,
    ) -> Result<()> {
        let Self {
            services,
            id,
            thread,
            state,
            recovered_through,
            slot,
            live,
            live_floor,
            continuous,
            ..
        } = self;
        let recovered_through = *recovered_through;
        transfer_terminal(services, state).await?;
        if !*continuous {
            *live_floor = (*live_floor).max(snapshot.commit_sequence);
        }
        if live.is_none() {
            let product = product_association(services, id).await?;
            *live = Some(
                LiveOwner::open(
                    services,
                    thread,
                    snapshot,
                    product,
                    Arc::clone(slot),
                    state.clone(),
                    persistence,
                )
                .await?,
            );
        }
        let live = live
            .as_mut()
            .expect("live projection owner was just installed");
        live.stream(snapshot, persistence).await?;
        live.observe_storage(snapshot, persistence);
        live.first_send &= *continuous;
        // The projection owner is the single producer of realtime content: it folds every admitted
        // fact exactly once, publishes it into the shared session and broadcasts the typed change,
        // whether or not a GUI is open.
        //
        // The association the owner was installed with is what identifies a parent or a billing
        // root; it never changes for a Thread, so a commit does not re-read the directory DTO for it.
        let mut newest_commit_at = 0_i64;
        loop {
            // One projection includes table scans and encoding, not one cheap iterator item.
            // Yield between complete handoffs instead of spending only one cooperative credit
            // per effect; writer progress must not depend on exhausting a whole batch of them.
            tokio::task::yield_now().await;
            // The retained handoff is completed before any new queue work: its write is the very
            // Arc the queue admitted, so even a queue entry that already disappeared cannot make
            // this owner forget or re-project the commit it still owes.
            let retained_mode = live.retained.pending.as_ref().map(|pending| pending.mode);
            let mut next = next_projection_write(&live.retained.pending, &live.channel);
            if next.is_none() {
                let after = live.channel.subscribe().borrow().admitted_sequence;
                if let Some(export) = thread
                    .history_export_page(after, std::num::NonZeroUsize::new(1).unwrap())?
                    .into_iter()
                    .next()
                {
                    let sequence = export.effect.sequence;
                    live.binding.storage.admit_export(id, export.clone())?;
                    // The reliable native queue now owns the original export even if its disk
                    // writer fails. Current saving has no dependency on this acknowledgement.
                    thread.release_history_through(sequence)?;
                    next = next_projection_write(&live.retained.pending, &live.channel);
                }
            }
            let Some(write) = next else {
                break;
            };
            // Core admits effects before publishing its snapshot. Do not cross that publication
            // boundary: after a zero-demand decision, a later receiver registers before capturing a
            // snapshot that must already cover this effect. Otherwise admission could race receiver
            // registration and leave a skipped commit out of both baseline and feed. The existing
            // snapshot watch wakes us when this watermark advances; the reliable queue retains work.
            // A retained batch is retried along its original mode instead of being parked again.
            // finish_pending also checks terminal coverage against this same handle's current cut;
            // neither its frozen transfer nor another observation generation can supply that cut.
            if retained_mode.is_none() && write.effect.sequence > snapshot.commit_sequence {
                break;
            }
            let sequence = write.effect.sequence;
            if let Some(mode) = retained_mode {
                // Same batch, same mode: no re-seed, no re-fold, no re-projection and no
                // re-decided delivery — only the report preparation and the handoff are retried.
                let _parent_report = live.finish_pending(services, snapshot).await?;
                if mode == HandoffMode::Live {
                    newest_commit_at = newest_commit_at.max(write.effect.committed_at);
                }
                transfer_terminal(services, state).await?;
                continue;
            }
            if sequence <= recovered_through {
                // A fact the owner committed before this projection existed: it is already part of
                // the snapshot the projection was seeded from, so it is folded for durability only.
                live.prepare_behind(services, &write, snapshot).await?;
                transfer_terminal(services, state).await?;
                continue;
            }
            live.advance(services, &write, snapshot).await?;
            newest_commit_at = newest_commit_at.max(write.effect.committed_at);
            transfer_terminal(services, state).await?;
        }
        // Streaming previews change without a commit and belong to the same publisher.
        live.stream(snapshot, persistence).await?;
        // The typed storage state is one owner fact: it is republished here whether this pass was
        // triggered by a commit, a preview or the coordinator's own typed status changing.
        live.observe_storage(snapshot, persistence);
        if !products {
            return Ok(());
        }
        // The directory DTO is re-read for a product refresh, because a concurrent title, mode or
        // archive operation owns those fields and a preview-only pass must not pay for the lookup.
        let mut product = product_association(services, id).await?;
        product.status = crate::studio::thread_projection::status(snapshot);
        product.updated_at = product.updated_at.max(newest_commit_at);
        // The directory summary is derived from the same reliable owner as the terminal report: the
        // in-memory projection; unobserved old Turns do not trigger a History read.
        let summary = match snapshot
            .turns
            .last()
            .filter(|turn| turn.state != pl_core::thread::TurnState::Running)
        {
            Some(turn) => live
                .retained
                .projection
                .turn_result(&turn.turn_id)
                .and_then(|result| result.final_text()),
            None => None,
        };
        directory::publish(
            services,
            product,
            live.native_directory.as_ref(),
            snapshot,
            summary,
        )
        .await?;
        Ok(())
    }
}

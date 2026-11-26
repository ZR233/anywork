//! Single realtime projection and retained reliable handoff.

use super::registry::ObservationServices;
use super::slot::ObservationSlot;
use super::worker::WorkerState;
use super::{billing, reports};
use crate::studio::storage::thread_writer::{
    HistoryChannel, PendingProjectionRetention, ProjectionRetention, ProjectionTransfer,
};
use crate::studio::thread_projection::{
    LiveProjection, project_activity, project_interactions, storage_state,
};
use crate::thread_assembler::agent_review::ReviewDeliverySource;
use crate::timeline::{MetaEventBus, SessionMetaSnapshot};
use anyhow::{Context, Result};
use pl_core::thread::{HistoryExport, ThreadHandle, ThreadSnapshot, UsageSummary};
use std::sync::Arc;

/// 同一稳定 Store 的串行执行驱动；借用投影，退出时将原批次归还 Store。
pub(in crate::studio) struct RetainedProjection {
    pub(in crate::studio) projection: LiveProjection,
    pub(in crate::studio) pending: Option<PendingHandoff>,
    pub(super) usage: UsageSummary,
}

pub(super) struct ProjectionLease {
    pub(super) store: Arc<crate::studio::conversation_store::ConversationStore>,
    value: Option<RetainedProjection>,
}
impl ProjectionLease {
    fn claim(store: Arc<crate::studio::conversation_store::ConversationStore>) -> Result<Self> {
        let value = store.take_projection()?;
        Ok(Self { store, value })
    }
}
impl std::ops::Deref for ProjectionLease {
    type Target = RetainedProjection;
    fn deref(&self) -> &Self::Target {
        self.value.as_ref().expect("initialized projection lease")
    }
}
impl std::ops::DerefMut for ProjectionLease {
    fn deref_mut(&mut self) -> &mut Self::Target {
        self.value.as_mut().expect("initialized projection lease")
    }
}
impl Drop for ProjectionLease {
    fn drop(&mut self) {
        self.store.retain_projection(self.value.take());
    }
}

pub(super) struct LiveOwner {
    pub(super) history_reader: crate::history::HistoryReader,
    pub(super) native_directory: Option<crate::studio::product_event_bus::NativeAgentObservation>,
    terminal_transfer: Arc<
        std::sync::Mutex<Option<Arc<crate::thread_assembler::review_dispatch::TerminalDelivery>>>,
    >,
    terminal_revocation: Arc<std::sync::atomic::AtomicU64>,
    terminal_floor: u64,
    pub(super) first_send: bool,
    config: crate::config::ConfigRuntime,
    qualification_revision: u64,
    pub(super) retained: ProjectionLease,
    pub(super) binding: Arc<crate::studio::ThreadStorageBinding>,
    activity_published: Option<crate::ThreadActivity>,
    runtime_published: Option<crate::ThreadRuntimeSnapshot>,
    model_route_published: Option<crate::ThreadModelRouteSnapshot>,
    storage_published: Option<crate::ThreadStorageState>,
    last_turn_published: Option<crate::Turn>,
    meta_revision: u64,
    pub(super) channel: Arc<HistoryChannel>,
    thread: crate::Thread,
    pub(super) bus: MetaEventBus,
    slot: Arc<ObservationSlot>,
    attached_commit_floor: u64,
}

/// Which path a retained handoff batch came from; a retry never re-decides it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum HandoffMode {
    /// The realtime path: accounting folded and the projection advanced with the delivery decision
    /// of the moment it was projected.
    Live,
    /// A commit the owner already held before this projection existed: folded for durability only,
    /// it never gains realtime publication rights.
    Behind,
}

/// One committed batch this projection owner prepared but has not handed to the writer yet.
pub(in crate::studio) struct PendingHandoff {
    pub(in crate::studio) write: Arc<HistoryExport>,
    pub(in crate::studio) prepared: Arc<crate::studio::thread_projection::PreparedEffect>,
    pub(in crate::studio) admitted: bool,
    terminal: Option<Arc<crate::thread_assembler::review_dispatch::TerminalDelivery>>,
    pub(super) mode: HandoffMode,
}

impl PendingHandoff {
    pub(in crate::studio) fn extra_retained_bytes(&self) -> u64 {
        0
    }

    fn hand_over(
        &self,
        channel: &HistoryChannel,
        slot: &ObservationSlot,
    ) -> Result<Option<Arc<pl_core::thread::inbox::ThreadMessage>>> {
        let sequence = self.prepared.sequence;
        if !self.admitted && !channel.prepare(Arc::clone(&self.prepared)) {
            anyhow::bail!("reliable channel refused the handoff of live Thread commit {sequence}");
        }
        if let Some(turn) = crate::studio::thread_projection::prepared_terminal_turn(&self.prepared)
        {
            slot.set_last_turn(Arc::new(turn));
        }
        Ok(self.prepared.parent_report.clone())
    }
}

impl LiveOwner {
    pub(super) async fn open(
        projector: &ObservationServices,
        handle: &ThreadHandle,
        snapshot: &ThreadSnapshot,
        thread: crate::Thread,
        slot: Arc<ObservationSlot>,
        state: Arc<WorkerState>,
        persistence: Option<&crate::ThreadPersistenceSnapshot>,
    ) -> Result<Self> {
        let channel = state.channel.clone();
        let id = thread.id.as_str();
        let conversation = projector.store.conversation_store(id).await?;
        let binding = projector
            .session_of(id)
            .map(|session| session.projection_storage_binding(id))
            .transpose()?
            .flatten()
            .context("execution has no storage binding")?;
        conversation.attach_execution(&binding).await?;
        conversation.attach_current(handle.clone()).await?;
        let history = projector.store.history(id).await?;
        let history_reader = history.reader();
        let runtime_epoch = handle.runtime_epoch();
        let bus = MetaEventBus::open(thread.clone(), history.clone(), runtime_epoch);
        match handle.attach_event_sink(Arc::new(bus.sink())).await {
            Ok(()) | Err(pl_core::thread::ThreadError::Closed) => {}
            Err(error) => return Err(error.into()),
        }
        let attached_commit_floor = handle.snapshot().commit_sequence;
        slot.install_bus(bus.clone());
        let usage = snapshot.usage_summary.clone();
        let runtime_epoch = handle.runtime_epoch();
        let initialized = conversation
            .initialize_projection(Arc::new({
                let channel = channel.clone();
                let thread = thread.clone();
                let snapshot = snapshot.clone();
                let usage = usage.clone();
                move || {
                    let (channel, thread, snapshot, usage, history, runtime_epoch) = (
                        channel.clone(),
                        thread.clone(),
                        snapshot.clone(),
                        usage.clone(),
                        history.clone(),
                        runtime_epoch,
                    );
                    Box::pin(async move {
                        let mut projection = LiveProjection::new();
                        projection.bind_execution(
                            channel.order_index(),
                            runtime_epoch,
                            history.database_id().to_owned(),
                        )?;
                        projection.mark_bus_admitted();
                        projection.restore_current(&thread, &snapshot)?;
                        Ok(RetainedProjection {
                            projection,
                            pending: None,
                            usage,
                        })
                    })
                }
            }))
            .await;
        if let Err(error) = initialized {
            slot.retire_bus(&bus);
            bus.close().await;
            return match conversation
                .close_current(handle, crate::thread_assembler::ClosePurpose::Preserve)
                .await
            {
                Ok(()) => Err(error),
                Err(close) => Err(error.context(format!(
                    "closing current after projection initialization failure: {close:#}"
                ))),
            };
        }
        let retained = match ProjectionLease::claim(conversation.clone()) {
            Ok(retained) => retained,
            Err(error) => {
                slot.retire_bus(&bus);
                bus.close().await;
                return match conversation
                    .close_current(handle, crate::thread_assembler::ClosePurpose::Preserve)
                    .await
                {
                    Ok(()) => Err(error),
                    Err(close) => Err(error.context(format!(
                        "closing current after projection ownership failure: {close:#}"
                    ))),
                };
            }
        };
        let storage_published = persistence.map(|detail| storage_state(snapshot, detail));
        let runtime = crate::studio::thread_projection::project_runtime(
            id,
            snapshot,
            thread.updated_at,
            &usage,
        )?;
        let mut model_route = crate::studio::model_route::projected(snapshot)?;
        let (config, catalog) = projector.config.read_with_catalog()?;
        crate::studio::model_route::annotate_availability(
            model_route.as_mut(),
            &thread,
            &config.config,
        )?;
        let runtime_published = Some(runtime);
        let model_route_published = model_route;
        let last_turn_published = slot.last_turn().map(|turn| (*turn).clone());
        let mut owner = Self {
            history_reader,
            native_directory: state.native_directory.clone(),
            terminal_transfer: state.terminal_transfer.clone(),
            terminal_revocation: state.reconciliation_through.clone(),
            terminal_floor: state.progress.borrow().applied,
            first_send: state.observed_before_execution,
            config: projector.config.clone(),
            qualification_revision: catalog.revision,
            retained,
            binding,
            activity_published: None,
            runtime_published,
            model_route_published,
            storage_published,
            last_turn_published,
            meta_revision: 1,
            channel,
            thread,
            bus,
            slot,
            attached_commit_floor,
        };
        owner.publish_retained()?;
        owner.publish_session_meta(snapshot)?;
        Ok(owner)
    }

    /// Publishes how much this projection currently retains in its own tables.
    ///
    /// The projection owns the retained bodies and the Turn report accumulator, and both outlive
    /// the batch the writer already committed. The reliable channel's budget is what pauses new
    /// model/tool admission at a safe gap, so it has to see this number; nothing here waits for a
    /// GUI, because the owner publishes whether or not anyone is subscribed.
    fn retention(&self) -> ProjectionRetention {
        // The activity summary and its bounded resident detail are resident facts of the same owner,
        // so they belong to the same Thread budget instead of living outside it.
        let mut bytes = self.retained.projection.retained_bytes();
        // The pending handoff batch is real resident product content this owner still holds. It is
        // charged here — under the same Thread budget — until the reliable channel takes it over;
        // the queue's own `ThreadWrite` Arc is the very object admission already charged, so only
        // the prepared content is added and no body is counted twice in steady state.
        let pending = self.retained.pending.as_ref().and_then(|pending| {
            bytes = bytes.saturating_add(pending.extra_retained_bytes());
            (!pending.admitted).then(|| PendingProjectionRetention {
                sequence: pending.prepared.sequence,
                prepared_bytes: pending.prepared.retained_bytes(),
            })
        });
        ProjectionRetention {
            resident_bytes: bytes,
            pending,
        }
    }

    fn publish_retained(&self) -> Result<()> {
        self.channel.set_projection_retention(self.retention())
    }

    /// Projects one admitted write into the session, broadcasts its live changes and hands the very
    /// same immutable batch to the Thread's reliable save channel.
    ///
    /// The batch is published before it is handed over, so the writer can only ever confirm a body
    /// the shared window already holds: there is no save-before-publish interleaving to lose.
    ///
    /// The producer cut and retained RAM material supply every projection fact. No History lookup
    /// supplements a released body, and the writer never re-projects an execution effect.
    pub(super) async fn advance(
        &mut self,
        services: &ObservationServices,
        write: &Arc<HistoryExport>,
        snapshot: &ThreadSnapshot,
    ) -> Result<Option<Arc<pl_core::thread::inbox::ThreadMessage>>> {
        self.project_write(services, write, snapshot).await
    }

    /// Folds one admitted write into the shared session and the reliable save channel.
    async fn project_write(
        &mut self,
        services: &ObservationServices,
        write: &Arc<HistoryExport>,
        snapshot: &ThreadSnapshot,
    ) -> Result<Option<Arc<pl_core::thread::inbox::ThreadMessage>>> {
        let effect = &write.effect;
        anyhow::ensure!(
            self.retained.pending.is_none(),
            "a retained handoff must finish before projecting another effect"
        );
        let started = std::time::Instant::now();
        if effect.sequence <= self.attached_commit_floor {
            self.bus.emit_core_event(pl_core::thread::CoreEvent::Durable(Arc::new(
                pl_core::thread::CoreCommitEvent {
                    thread_id: self.thread.id.clone(),
                    sequence: effect.sequence,
                    export: Arc::clone(write),
                },
            )));
        }
        let prepared = match self
            .retained
            .projection
            .prepare_committed(&self.thread, effect, &write.state)
        {
            Ok(prepared) => prepared,
            Err(error) => {
                self.channel.fail_projection(
                    effect.sequence,
                    format!("live Thread projection failed: {error}"),
                );
                return Err(anyhow::anyhow!("live Thread projection failed: {error}"));
            }
        };
        prepared.accounting.fold_into(&mut self.retained.usage);
        self.retained.pending = Some(PendingHandoff {
            admitted: false,
            write: Arc::clone(write),
            prepared,
            terminal: None,
            mode: HandoffMode::Live,
        });
        self.publish_retained()?;
        let result = self.finish_pending(services, snapshot).await;
        tracing::debug!(
            target: "conversation_work",
            thread_id = self.thread.id,
            projection_handoff_elapsed_us = started.elapsed().as_micros() as u64,
            success = result.is_ok(),
            "live owner projection and handoff"
        );
        result
    }

    pub(super) async fn finish_pending(
        &mut self,
        services: &ObservationServices,
        snapshot: &ThreadSnapshot,
    ) -> Result<Option<Arc<pl_core::thread::inbox::ThreadMessage>>> {
        self.publish_retained()?;
        self.prepare_parent_report()?;
        self.prepare_terminal_delivery(services)?;
        self.prepare_handoff(services, snapshot)?;
        self.binding.conversation.admit_prepared(
            &self.binding,
            &self.channel,
            &mut self.retained,
        )?;
        self.publish_retained()?;
        if let (Some(exporter), Some(pending)) = (&services.run_export, &self.retained.pending)
            && (pending.mode == HandoffMode::Live
                || exporter.should_admit_behind_effect(&self.thread.id, pending.prepared.sequence))
        {
            self.bus.wait_admitted_commit(pending.prepared.sequence).await;
            let owner_id = self
                .retained
                .projection
                .owner_id()
                .unwrap_or(&self.thread.id);
            Box::pin(exporter.admit_live_handoff(
                &self.thread.id,
                &pending.prepared.accounting,
                &pending.prepared.history_events,
                &self.retained.usage,
                owner_id,
                snapshot.commit_sequence,
                &self.history_reader,
            ))
            .await;
        }
        let report = self.handover_pending(services)?;
        let latest_last_turn = self.slot.last_turn().map(|turn| (*turn).clone());
        if latest_last_turn != self.last_turn_published {
            self.last_turn_published = latest_last_turn;
            self.publish_session_meta(snapshot)?;
        }
        Ok(report)
    }

    /// Freezes the managed terminal-delivery authority beside the retained batch.
    ///
    /// The delivery is not published to `WorkerState` yet: while `HistoryChannel::prepare` may still
    /// refuse the batch, this pending slot remains its sole owner. That prevents the next worker pass
    /// from starting delivery before the reliable handoff and keeps cancellation/retry on one batch.
    fn prepare_terminal_delivery(&mut self, services: &ObservationServices) -> Result<()> {
        let Some(pending) = self.retained.pending.as_ref() else {
            return Ok(());
        };
        if pending.terminal.is_some() {
            return Ok(());
        }
        let Some(original) = pending.prepared.parent_report.clone() else {
            return Ok(());
        };
        // Ordinary effects have no terminal material to transfer. Measure only after that
        // qualification; the retained batch cannot change during these synchronous borrows.
        let before = self.retention();
        let pending = self
            .retained
            .pending
            .as_mut()
            .expect("terminal batch was checked above");
        anyhow::ensure!(
            self.terminal_transfer
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .is_none(),
            "terminal responsibility has not been handed over"
        );
        let authority = Arc::new(
            crate::thread_assembler::review_dispatch::TerminalAuthority::capture(
                &pending.write.state,
            )?,
        );
        let finish = pending.prepared.parent_finish.clone();
        let bytes = self
            .channel
            .terminal_material_bytes(&authority, &original, finish.as_deref());
        let source = before
            .pending
            .context("terminal batch has no charged identity")?;
        let prepared_bytes = source
            .prepared_bytes
            .checked_sub(pending.prepared.parent_report_retained_bytes())
            .context("terminal report exceeds its prepared batch charge")?;
        let transfer = ProjectionTransfer {
            source,
            after: ProjectionRetention {
                resident_bytes: before.resident_bytes,
                pending: Some(PendingProjectionRetention {
                    sequence: source.sequence,
                    prepared_bytes,
                }),
            },
        };
        let sequence = pending.write.effect.sequence;
        let Some(prepared) = Arc::get_mut(&mut pending.prepared) else {
            anyhow::bail!(
                "live Thread pending batch of commit {sequence} is unexpectedly shared before terminal retention"
            );
        };
        let retention = services
            .store
            .thread_persistence()
            .retain_terminal_material(&self.thread.id, &self.channel, bytes, Some(transfer))?;
        prepared.terminal_retention = Some(retention.clone());
        pending.terminal = Some(Arc::new(
            crate::thread_assembler::review_dispatch::TerminalDelivery {
                thread: self.thread.clone(),
                sequence,
                authority,
                original,
                finish,
                source: if self.first_send && sequence > self.terminal_floor {
                    ReviewDeliverySource::LiveTerminal
                } else {
                    ReviewDeliverySource::Reconciliation
                },
                revocation: self.terminal_revocation.clone(),
                channel: Some(self.channel.clone()),
                wake: sequence > self.terminal_floor,
                _material: Some(retention),
            },
        ));
        // The report moved from the pending-batch estimate to the managed terminal-material charge.
        // Publish the new absolute projection value before attempting the synchronous handoff.
        self.publish_retained()?;
        Ok(())
    }

    fn prepare_terminal_runtime(
        &self,
        services: &ObservationServices,
        snapshot: &ThreadSnapshot,
        sequence: u64,
        committed_at: i64,
    ) -> Result<()> {
        // Only this worker's original ThreadHandle supplies the live cut, including on retry.
        // Same-generation observation revisions are monotonic with its commit sequence, so a newer
        // accepted cut also covers this terminal; checkpoint revisions cannot establish that fact.
        anyhow::ensure!(
            snapshot.commit_sequence >= sequence,
            "terminal handoff requires its owner's snapshot through commit {} (got {})",
            sequence,
            snapshot.commit_sequence,
        );
        let accepted = services.events.patch_thread_runtime(
            self.native_directory.as_ref(),
            crate::studio::thread_projection::status(snapshot),
            committed_at,
            snapshot,
            None,
        )?;
        if self.native_directory.is_some()
            && accepted.is_none()
            && !services
                .events
                .native_observation_covers(self.native_directory.as_ref(), snapshot)
        {
            // A revoked token or resource is not an accepted cut.
            self.slot.retire_bus(&self.bus);
        }
        Ok(())
    }

    fn prepare_handoff(
        &self,
        services: &ObservationServices,
        snapshot: &ThreadSnapshot,
    ) -> Result<()> {
        let Some(pending) = &self.retained.pending else {
            return Ok(());
        };
        if crate::studio::thread_projection::prepared_terminal_turn(&pending.prepared).is_some() {
            // Behind also publishes a retained terminal, including a restart commit not saved yet.
            // Qualify the current live cut before any handoff, never the historical transfer's state.
            // This preserves newer Turns, version/token guards and explicit close; Behind still
            // produces no realtime frames. A failed patch leaves the original batch pending.
            self.prepare_terminal_runtime(
                services,
                snapshot,
                pending.write.effect.sequence,
                pending.write.effect.committed_at,
            )?;
        }
        if pending.mode == HandoffMode::Live {
            billing::record(
                &services.performance,
                &self.thread.root_thread_id,
                &pending.prepared.accounting,
            )?;
        }
        Ok(())
    }

    /// Hands the retained batch to the reliable channel, or keeps it fully retained.
    ///
    /// Nothing in here awaits: the channel's decision, the terminal and realtime publications, the
    /// slot release and the budget update form one boundary, so the batch is either still this
    /// owner's responsibility with an explicit refusal, or handed over with its facts published
    /// exactly once. `prepare` accepting is the explicit handoff, not a durability confirmation —
    /// durability remains the writer's own watermark.
    fn handover_pending(
        &mut self,
        _services: &ObservationServices,
    ) -> Result<Option<Arc<pl_core::thread::inbox::ThreadMessage>>> {
        let Some(pending) = self.retained.pending.as_ref() else {
            return Ok(None);
        };
        let sequence = pending.prepared.sequence;
        let handed_over = pending.hand_over(&self.channel, &self.slot);
        let report = match handed_over {
            Ok(report) => report,
            Err(error) => {
                // A durable replay has no queue entry to accept. Its stored original remains the
                // receipt, and the managed delivery may only reconcile from that durable source.
                if self.channel.delivery_retry_mark().0 < sequence {
                    return Err(error);
                }
                if let Some(terminal) = self
                    .retained
                    .pending
                    .as_mut()
                    .and_then(|pending| pending.terminal.as_mut())
                {
                    let terminal = Arc::make_mut(terminal);
                    terminal
                        .revocation
                        .fetch_max(sequence, std::sync::atomic::Ordering::AcqRel);
                    terminal.source = ReviewDeliverySource::Reconciliation;
                    terminal.wake = false;
                }
                None
            }
        };
        let terminal = self
            .retained
            .pending
            .as_mut()
            .and_then(|pending| pending.terminal.take());
        if let Some(terminal) = terminal {
            let mut transfer = self
                .terminal_transfer
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            assert!(
                transfer.is_none(),
                "terminal responsibility was validated before admission"
            );
            *transfer = Some(terminal);
        }
        self.retained.pending = None;
        self.publish_retained()?;
        Ok(report)
    }

    /// Freezes the original terminal report of the retained batch into its prepared content.
    ///
    /// Every await in here belongs to the pending slot: the slot keeps holding the original write
    /// and prepared content, a local clone carries the waits, and only a fully successful build is
    /// written back. A failure or a cancelled wait leaves the slot exactly as it was, so the next
    /// pass reuses the same batch instead of rebuilding the report from a later checkpoint.
    fn prepare_parent_report(&mut self) -> Result<()> {
        let (write, prepared) = match self.retained.pending.as_ref() {
            Some(pending) => (Arc::clone(&pending.write), Arc::clone(&pending.prepared)),
            None => return Ok(()),
        };
        let Some(turn) = write.effect.turn.as_ref().filter(|turn| {
            turn.state != pl_core::thread::TurnState::Running
                && self.thread.parent_thread_id.is_some()
        }) else {
            return Ok(());
        };
        // The retry of a batch whose report already exists reuses the original copy: the report is
        // the frozen receipt of this very commit, never rebuilt from a DTO or a newer checkpoint.
        if prepared.parent_report.is_some() {
            return Ok(());
        }
        let turn = turn.clone();
        let result = self
            .retained
            .projection
            .turn_result(&turn.turn_id)
            .cloned()
            .unwrap_or_default();
        // The report is built from read-only local clones while the slot keeps the only prepared
        // batch; only once the complete message exists are the clones dropped, so the write-back
        // below takes the slot's single strong reference and never copies the whole batch.
        let report = reports::terminal_message(
            &self.thread,
            &write.state,
            &turn,
            write.effect.sequence,
            &result,
        )?;
        drop(prepared);
        let shared = {
            let Some(pending) = self.retained.pending.as_mut() else {
                unreachable!(
                    "the pending handoff slot cannot vanish while its owner prepares its report"
                );
            };
            match Arc::get_mut(&mut pending.prepared) {
                Some(batch) => {
                    batch.parent_report = Some(Arc::new(report));
                    batch.parent_finish = result.finish.map(Arc::new);
                    None
                }
                // Before the handoff only this owner holds the batch; a second strong reference
                // is an internal invariant violation, reported while the slot stays retained.
                None => Some(pending.write.effect.sequence),
            }
        };
        if let Some(sequence) = shared {
            anyhow::bail!(
                "live Thread pending batch of commit {sequence} is unexpectedly shared before its handoff"
            );
        }
        // The report is now part of the retained batch: the Thread budget sees it before any
        // handoff attempt, and a refused handoff keeps the batch together with its report.
        self.publish_retained()?;
        Ok(())
    }

    /// Hands one admitted effect this owner installed *behind* to the reliable save channel.
    ///
    /// The Thread's initialization commits before the assembler publishes the observation, so those
    /// effects are already part of the snapshot this projection was seeded from and are never
    /// replayed as live frames. The history writer still owes them a durable row, so the same single
    /// projection folds their content into memory here — once, and never the writer projecting the
    /// effect itself.
    pub(super) async fn prepare_behind(
        &mut self,
        services: &ObservationServices,
        write: &Arc<HistoryExport>,
        snapshot: &ThreadSnapshot,
    ) -> Result<()> {
        if write.effect.sequence <= self.attached_commit_floor {
            self.bus.emit_core_event(pl_core::thread::CoreEvent::Durable(Arc::new(
                pl_core::thread::CoreCommitEvent {
                    thread_id: self.thread.id.clone(),
                    sequence: write.effect.sequence,
                    export: Arc::clone(write),
                },
            )));
        }
        let projected =
            self.retained
                .projection
                .prepare_committed(&self.thread, &write.effect, &write.state);
        let prepared = match projected {
            Ok(prepared) => prepared,
            Err(error) => {
                self.channel.fail_projection(
                    write.effect.sequence,
                    format!("live Thread projection failed: {error}"),
                );
                return Err(anyhow::anyhow!("live Thread projection failed: {error}"));
            }
        };
        if let Some(pending) = self.retained.pending.as_ref() {
            anyhow::bail!(
                "live projection still owes the handoff of commit {} before taking over commit {}",
                pending.write.effect.sequence,
                write.effect.sequence
            );
        }
        self.retained.pending = Some(PendingHandoff {
            admitted: false,
            write: Arc::clone(write),
            prepared,
            terminal: None,
            mode: HandoffMode::Behind,
        });
        self.publish_retained()?;
        self.finish_pending(services, snapshot).await?;
        Ok(())
    }

    pub(super) async fn stream(
        &mut self,
        snapshot: &ThreadSnapshot,
        persistence: Option<&crate::ThreadPersistenceSnapshot>,
    ) -> Result<()> {
        self.observe_runtime(snapshot).await?;
        self.observe_activity(snapshot);
        self.observe_storage(snapshot, persistence);
        self.publish_session_meta(snapshot)?;
        Ok(())
    }

    async fn observe_runtime(&mut self, snapshot: &ThreadSnapshot) -> Result<()> {
        let at = self
            .runtime_published
            .as_ref()
            .map_or(self.thread.updated_at, |runtime| runtime.updated_at);
        let mut runtime = crate::studio::thread_projection::project_runtime(
            &self.thread.id,
            snapshot,
            at,
            &snapshot.usage_summary,
        )?;
        let mut model_route = crate::studio::model_route::projected(snapshot)?;
        let same_identity = match (self.model_route_published.as_ref(), model_route.as_ref()) {
            (Some(previous), Some(current)) => {
                previous.account_id == current.account_id
                    && previous.model_id == current.model_id
                    && previous.effort == current.effort
                    && previous.revision == current.revision
            }
            (None, None) => true,
            _ => false,
        };
        let qualification_revision = if self.config.model_catalog_revision()?
            == self.qualification_revision
            && same_identity
        {
            if let (Some(previous), Some(current)) =
                (self.model_route_published.as_ref(), model_route.as_mut())
            {
                current.available = previous.available;
                current.unavailable_reason = previous.unavailable_reason.clone();
            }
            self.qualification_revision
        } else {
            let (config, catalog) = self.config.read_with_catalog()?;
            crate::studio::model_route::annotate_availability(
                model_route.as_mut(),
                &self.thread,
                &config.config,
            )?;
            catalog.revision
        };
        if self.runtime_published.as_ref() == Some(&runtime)
            && self.model_route_published == model_route
        {
            self.qualification_revision = qualification_revision;
            return Ok(());
        }
        runtime.updated_at = crate::studio::unix_seconds();
        runtime.usage.updated_at = runtime.updated_at;
        self.qualification_revision = qualification_revision;
        self.model_route_published.clone_from(&model_route);
        self.runtime_published = Some(runtime);
        Ok(())
    }

    fn observe_activity(&mut self, snapshot: &ThreadSnapshot) {
        let activity =
            project_activity(&self.thread.id, snapshot, self.activity_published.as_ref());
        if activity != self.activity_published {
            self.activity_published = activity;
        }
    }

    pub(super) fn observe_storage(
        &mut self,
        snapshot: &ThreadSnapshot,
        persistence: Option<&crate::ThreadPersistenceSnapshot>,
    ) {
        if let Some(through) = persistence.and_then(|detail| detail.history_durable_sequence) {
            self.retained.projection.confirm_sources(through);
        }
        let storage = persistence.map(|detail| storage_state(snapshot, detail));
        if storage != self.storage_published {
            self.storage_published = storage;
            let _ = self.publish_session_meta(snapshot);
        }
    }

    fn publish_session_meta(&mut self, snapshot: &ThreadSnapshot) -> Result<()> {
        self.meta_revision = self.meta_revision.saturating_add(1);
        let active_turn = crate::studio::thread_projection::project_active_turn(
            &self.thread.id,
            snapshot,
            crate::studio::unix_seconds(),
        )?;
        let last_turn = self
            .slot
            .last_turn()
            .map(|turn| (*turn).clone())
            .or_else(|| self.last_turn_published.clone());
        let interactions = project_interactions(&self.thread.id, snapshot)?;
        let pending_interaction_count = u32::try_from(interactions.len()).unwrap_or(u32::MAX);
        let plan = self
            .runtime_published
            .as_ref()
            .and_then(|runtime| runtime.plan.clone());
        let context_metrics = self
            .runtime_published
            .as_ref()
            .map(|runtime| runtime.usage.clone());
        let status = crate::studio::thread_projection::status(snapshot);
        let mode = crate::studio::thread_projection::saved_mode(snapshot).ok().flatten();
        let meta = SessionMetaSnapshot {
            thread_id: self.thread.id.clone(),
            status,
            title: Some(self.thread.title.clone()),
            parent_thread_id: self.thread.parent_thread_id.clone(),
            root_thread_id: self.thread.root_thread_id.clone(),
            owner_epoch: self.bus.runtime_epoch().to_string(),
            revision: self.meta_revision,
            active_turn,
            last_turn,
            activity: self.activity_published.clone(),
            usage: snapshot.usage_summary.clone(),
            context_metrics,
            model_route: self.model_route_published.clone(),
            runtime: self.runtime_published.clone(),
            storage_state: self.storage_published.clone(),
            interactions,
            pending_interaction_count,
            plan,
            mode,
            execution_present: snapshot.execution.is_some(),
        };
        self.bus.update_session_meta(meta);
        Ok(())
    }
}

impl Drop for LiveOwner {
    fn drop(&mut self) {
        self.slot.retire_bus(&self.bus);
        self.binding.conversation.detach_execution(&self.binding);
    }
}

//! Single realtime projection and retained reliable handoff.

use super::live_feed::{ThreadLiveEvent, ThreadLiveFeed};
use super::registry::ObservationServices;
use super::worker::WorkerState;
use super::{billing, reports};
use crate::studio::storage::thread_writer::{
    HistoryChannel, PendingProjectionRetention, ProjectionRetention, ProjectionTransfer,
};
use crate::studio::thread_projection::{LiveEvent, LiveProjection, storage_state};
use crate::thread_assembler::agent_review::ReviewDeliverySource;
use anyhow::{Context, Result};
use pl_core::thread::{HistoryExport, ThreadHandle, ThreadSnapshot, UsageSummary};
use std::sync::Arc;

/// 同一稳定 Store 的串行执行驱动；借用投影，退出时将原批次归还 Store。
///
/// It lives in the Thread's observation worker, so a GUI opening and closing never changes who
/// projects or who publishes content: every committed effect is projected exactly once into the
/// shared chat session, and its typed changes are broadcast to whichever subscribers exist. The same
/// batch is handed to the Thread's reliable admission channel, so the history writer commits the
/// content this owner published instead of projecting the effect a second time.
/// Store 保留投影和至多一个原交接批次；执行驱动仅在租约期间借用它。
pub(in crate::studio) struct RetainedProjection {
    pub(in crate::studio) projection: LiveProjection,
    pub(in crate::studio) pending: Option<PendingHandoff>,
    pub(in crate::studio) baseline: Option<Arc<crate::studio::thread_projection::CurrentState>>,
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
    /// The Thread's only activity projection: the same owner derives it from the snapshot it just
    /// published, so activity never becomes a second fact source and never reads SQL.
    /// Last activity already broadcast, so an unchanged projection does not produce a frame.
    activity_published: Option<crate::ThreadActivity>,
    runtime_published: Option<crate::ThreadRuntimeSnapshot>,
    model_route_published: Option<crate::ThreadModelRouteSnapshot>,
    /// Last typed storage state this owner published to its feed.
    ///
    /// The owner derives it from the owner snapshot plus the coordinator's typed watch, so a
    /// subscriber mirrors the value instead of recomputing it from its own copies. It is kept as one
    /// value so a change of fault kind, generation, watermark or phase is all one comparison.
    storage_published: Option<crate::ThreadStorageState>,
    /// The Thread's reliable admission channel, shared with the history writer.
    pub(super) channel: Arc<HistoryChannel>,
    thread: crate::Thread,
    feed: Arc<ThreadLiveFeed>,
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
///
/// This is not a second ledger: it is the single in-flight handoff of the owner's serial pass, at
/// most one batch, holding the very `ThreadWrite` the reliable queue admitted and the prepared
/// content the writer will commit. Retaining it closes the window between the report preparation
/// and the handoff — a failure, a cancelled wait or an explicit retry re-enters this same batch
/// instead of projecting the same commit a second time and bumping its content revisions.
pub(in crate::studio) struct PendingHandoff {
    pub(in crate::studio) write: Arc<HistoryExport>,
    pub(in crate::studio) prepared: Arc<crate::studio::thread_projection::PreparedEffect>,
    pub(in crate::studio) admitted: bool,
    /// Managed terminal delivery prepared from the same frozen report, still owned here until the
    /// reliable channel accepts this batch (or proves the same sequence already durable).
    terminal: Option<Arc<crate::thread_assembler::review_dispatch::TerminalDelivery>>,
    /// The delivery changes the live path decided when it projected the commit; `None` on the
    /// behind path and when the projection produced no frame.
    changes: Option<Vec<LiveEvent>>,
    pub(super) mode: HandoffMode,
}

impl PendingHandoff {
    /// Delivery changes owned here in addition to the shared prepared batch.
    pub(in crate::studio) fn extra_retained_bytes(&self) -> u64 {
        // The prepared batch is measured by its owning projection (`PreparedEffect::retained_bytes`,
        // the one implementation the writer shares); the delivery changes are this owner's own
        // residents and are charged element by element.
        let mut bytes = 0_u64;
        if let Some(changes) = self.changes.as_ref() {
            for event in changes {
                bytes = bytes.saturating_add(event.retained_bytes());
            }
            // The Vec's spare capacity is resident too: every used element's shell is already part
            // of its own estimate, so only the unused slots add their element size here.
            let spare = changes.capacity() - changes.len();
            bytes = bytes.saturating_add(
                u64::try_from(spare)
                    .unwrap_or(u64::MAX)
                    .saturating_mul(std::mem::size_of::<LiveEvent>() as u64),
            );
        }
        bytes
    }

    /// Attaches the prepared batch to the reliable queue and publishes the accepted facts.
    ///
    /// # Errors
    /// The channel refused the handoff — the sequence is already durable or is not an admitted
    /// commit of this channel. The batch stays fully retained with its identity, so the refusal
    /// reaches the caller instead of a silent loss or a re-projection.
    fn hand_over(
        &self,
        channel: &HistoryChannel,
        feed: &ThreadLiveFeed,
    ) -> Result<Option<Arc<pl_core::thread::inbox::ThreadMessage>>> {
        let sequence = self.prepared.sequence;
        if !self.admitted && !channel.prepare(Arc::clone(&self.prepared)) {
            anyhow::bail!("reliable channel refused the handoff of live Thread commit {sequence}");
        }
        // Only the prepared content is authoritative for the terminal fact — never the optional
        // delivery changes, which a zero-subscriber commit may not carry at all.
        if let Some(turn) = crate::studio::thread_projection::prepared_terminal_turn(&self.prepared)
        {
            feed.publish_last_turn(Arc::new(turn));
        }
        if self.mode == HandoffMode::Live {
            feed.publish(|| match self.changes.as_ref() {
                Some(changes) => ThreadLiveEvent::Committed {
                    sequence,
                    changes: changes.clone(),
                },
                None => ThreadLiveEvent::UnframedCommit { sequence },
            });
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
        feed: Arc<ThreadLiveFeed>,
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
        feed.bind_conversation(&conversation, handle.runtime_epoch().to_string());
        let history = projector.store.history(id).await?;
        let history_reader = history.reader();
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
                        // Current starts a new runtime epoch; it must not replay R1 history into
                        // R2's live publication rights. Late facts query HistoryReader by owner.
                        projection.restore_current(&thread, &snapshot)?;
                        let baseline = projection.current_state();
                        Ok(RetainedProjection {
                            projection,
                            pending: None,
                            baseline,
                            usage,
                        })
                    })
                }
            }))
            .await;
        if let Err(error) = initialized {
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
        // Publish the first activity only after this snapshot's admitted completions have been
        // folded below. Seeding the summary here would suppress that first shared content publish.
        let activity_published = None;
        // The owner is the single source of the typed storage state: publish the value it was
        // installed with, so a subscriber that opened before this first pass sees the authoritative
        // fact instead of an unset placeholder.
        let storage_published = persistence.map(|detail| storage_state(snapshot, detail));
        // A subscriber may already have an older catalog baseline while this
        // owner initializes. Publish the initial qualification too; its source
        // stamps let a current subscriber discard it without manufacturing a gap.
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
        let compact_runtime = feed.compact_runtime(runtime.clone())?;
        feed.publish(|| ThreadLiveEvent::Runtime {
            observation_revision: snapshot.observation_revision,
            catalog_revision: catalog.revision,
            runtime: Arc::new(compact_runtime),
            model_route: model_route.clone(),
        });
        let runtime_published = Some(runtime);
        let model_route_published = model_route;
        feed.publish_storage(storage_published.clone());
        let owner = Self {
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
            activity_published,
            runtime_published,
            model_route_published,
            storage_published,
            channel,
            thread,
            feed,
        };
        // The seeded facts are already resident, so the Thread's budget covers them from the moment
        // the owner is installed instead of only after its first commit.
        owner.publish_retained()?;
        // Terminal Turn history is served by the independent HistoryReader. Replaying it into the
        // new runtime epoch would recreate presentation restore and can publish an old run's fact.
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
        // A receiver may register while this effect is being prepared or retained before handoff.
        // Freeze its typed State facts in the original charged slot regardless of current demand;
        // only the outward envelope is optional. Otherwise that receiver loses a reliable commit.
        let started = std::time::Instant::now();
        let projected = self
            .retained
            .projection
            .prepare(&self.thread, effect, &write.state, true);
        let (changes, prepared) = match projected {
            Ok(projected) => projected,
            Err(error) => {
                // The writer saves exactly what this owner projects, so a projection this owner cannot
                // complete is a fact that cannot be handed over or saved. Report it so the durable
                // barrier fails closed with the real reason instead of waiting forever.
                self.channel.fail_projection(
                    effect.sequence,
                    format!("live Thread projection failed: {error}"),
                );
                return Err(anyhow::anyhow!("live Thread projection failed: {error}"));
            }
        };
        prepared.accounting.fold_into(&mut self.retained.usage);
        // The folded commit is already resident in the shared session, so this owner retains the
        // whole handoff — the original write, the prepared batch, the delivery decision it made and
        // its mode — before the first await of the parent-report preparation. A failure, a
        // cancellation or a retry inside that window re-enters the same retained batch instead of
        // projecting the commit a second time, which would bump content revisions for the same fact.
        if let Some(pending) = self.retained.pending.as_ref() {
            anyhow::bail!(
                "live projection still owes the handoff of commit {} before projecting commit {}",
                pending.write.effect.sequence,
                effect.sequence
            );
        }
        self.retained.pending = Some(PendingHandoff {
            admitted: false,
            write: Arc::clone(write),
            prepared,
            terminal: None,
            changes,
            mode: HandoffMode::Live,
        });
        self.publish_retained()?;
        let result = self.finish_pending(services, snapshot).await;
        tracing::debug!(
            target: "conversation_work",
            thread_id = self.thread.id,
            current_revision = self
                .retained
                .projection
                .current_state()
                .map_or(0, |current| current.revision()),
            projection_handoff_elapsed_us = started.elapsed().as_micros() as u64,
            success = result.is_ok(),
            "live owner projection and handoff"
        );
        result
    }

    /// Prepares the retained batch's original parent report, then hands the batch over.
    /// The snapshot is the current cut of this worker's original ThreadHandle, including on retry;
    /// the frozen transfer remains the source of the report and content, never of runtime versions.
    pub(super) async fn finish_pending(
        &mut self,
        services: &ObservationServices,
        snapshot: &ThreadSnapshot,
    ) -> Result<Option<Arc<pl_core::thread::inbox::ThreadMessage>>> {
        // 原批次先保留，全部可失败准备先完成；发布与可靠交接只推进同一冻结批次。
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
            let export_current = self
                .retained
                .projection
                .current_state()
                .context("export current owner is missing")?;
            Box::pin(exporter.admit_live_handoff(
                &self.thread.id,
                &pending.prepared.accounting,
                &pending.prepared.history_events,
                &self.retained.usage,
                export_current.as_ref(),
                &self.history_reader,
            ))
            .await;
        }
        self.handover_pending(services)
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
        if accepted.is_none()
            && !services
                .events
                .native_observation_covers(self.native_directory.as_ref(), snapshot)
        {
            // A revoked token or resource is not an accepted cut. End only this obsolete feed's
            // outward delivery; its original reliable content and parent-transfer duties continue.
            self.feed.close_delivery();
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
        let handed_over = pending.hand_over(&self.channel, &self.feed);
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
        // The behind batch is retained the same way before its report await; its mode keeps it from
        // ever gaining realtime publication rights on a retry.
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
            changes: None,
            mode: HandoffMode::Behind,
        });
        self.publish_retained()?;
        self.finish_pending(services, snapshot).await?;
        Ok(())
    }

    /// Projects the uncommitted streaming preview of the current owner snapshot.
    ///
    /// The preview is written into the shared session — the one content window — and emits no
    /// content frame; current activity and runtime facts are published separately.
    pub(super) async fn stream(&mut self, snapshot: &ThreadSnapshot) -> Result<()> {
        self.retained
            .projection
            .stream(&self.thread, snapshot)
            .map_err(|error| anyhow::anyhow!("live Thread preview failed: {error}"))?;
        self.observe_runtime(snapshot).await?;
        self.observe_activity(snapshot).await?;
        if let Some(current) = self.retained.projection.current_state() {
            self.feed.publish_conversation(current)?;
        }
        Ok(())
    }

    /// Execution residency is live-only; next-admission availability also consumes current config.
    /// Derive runtime from the latest owner snapshot after folding all admitted usage,
    /// never from an effect's storage checkpoint. Stable timestamps allow deduplication.
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
        let runtime = self.runtime_published.insert(runtime);
        let compact_runtime = self.feed.compact_runtime(runtime.clone())?;
        self.feed.publish(|| ThreadLiveEvent::Runtime {
            observation_revision: snapshot.observation_revision,
            catalog_revision: self.qualification_revision,
            runtime: Arc::new(compact_runtime),
            model_route,
        });
        Ok(())
    }

    /// Re-derives the Thread's current activity from the snapshot this owner just published.
    ///
    /// The activity is an independent projection of the same facts: a phase change, a new foreground
    /// tool or an interaction change reaches it through the owner snapshot, never through `effect`.
    /// Shared producer versions cover body changes even when the bounded summary stays identical.
    /// The completion ceiling also advances independently of the activity summary.
    async fn observe_activity(&mut self, snapshot: &ThreadSnapshot) -> Result<()> {
        let activity = self.retained.projection.current_activity();
        let activity_changed = activity != self.activity_published;
        if !activity_changed {
            return Ok(());
        }
        self.activity_published = activity;
        let compact_activity = self
            .feed
            .compact_activity(self.activity_published.clone())?;
        // One shared handle per published change: every subscriber clones that handle, never the body.
        self.feed.publish(|| ThreadLiveEvent::Activity {
            observation_revision: snapshot.observation_revision,
            activity: compact_activity.map(Arc::new),
        });
        Ok(())
    }

    /// Republishes the typed storage state this owner derives, only when it really changed.
    ///
    /// A storage pause, a pressure warning, the explicit-resume latch or a durable receipt change
    /// nothing about the content or the activity, so they need their own fact: the owner watches the
    /// coordinator's typed status directly and republishes here even when no other frame arrived, so
    /// a parked subscriber learns about a save failure without waiting for an unrelated commit.
    pub(super) fn observe_storage(
        &mut self,
        snapshot: &ThreadSnapshot,
        persistence: Option<&crate::ThreadPersistenceSnapshot>,
    ) {
        if let Some(through) = persistence.and_then(|detail| detail.history_durable_sequence) {
            self.retained.projection.confirm_sources(through);
        }
        let storage = persistence.map(|detail| storage_state(snapshot, detail));
        if storage == self.storage_published {
            return;
        }
        self.storage_published = storage.clone();
        self.feed.publish_storage(storage);
    }
}

impl Drop for LiveOwner {
    fn drop(&mut self) {
        self.binding.conversation.detach_execution(&self.binding);
    }
}

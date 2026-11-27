//! Private serial execution and atomic publication.
use super::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum ClosePurpose {
    Preserve,
    Delete,
}

#[derive(Clone)]
pub(super) struct PendingCall {
    pub(super) context: ContextSnapshot,
    pub(super) model_projection: Option<OpaquePayload>,
    pub(super) turn_id: String,
    pub(super) call: crate::model::ModelToolCall,
    pub(super) executor: crate::tool::opaque::FrozenTool,
    pub(super) parent_call_id: Option<String>,
    pub(super) nested_plan: Option<Arc<crate::tool::opaque::ToolPlan>>,
}

pub(super) struct NestedScope {
    pub plan: Arc<crate::tool::opaque::ToolPlan>,
    pub context: crate::context::ContextSnapshot,
    pub model_projection: Option<OpaquePayload>,
    pub invocations: Arc<std::sync::Mutex<Vec<String>>>,
}

pub(super) enum PendingWrite {
    History(Arc<HistoryExport>),
}
impl PendingWrite {
    pub(super) fn effect(&self) -> &Arc<ThreadEffectBatch> {
        match self {
            Self::History(export) => &export.effect,
        }
    }
}

pub(super) struct PendingEffect {
    pub(super) write: PendingWrite,
    /// Encoded byte length of this effect, measured at most once while it stays pending.
    ///
    /// Pressure admission must not re-serialize the whole still-pending queue on every model step:
    /// that made a long Turn quadratic in its commit count. The measurement is memoized here, so an
    /// effect is serialized once no matter how many admission checks observe it, and a Thread with
    /// an attached store (whose queue drains on every publish) never serializes it here at all.
    pub(super) encoded_bytes: Option<u64>,
}

pub(super) struct Owner {
    pub(super) active: Option<super::execution::ActiveRun>,
    pub(super) primary: Option<super::execution::PrimaryWork>,
    pub(super) closing: Option<super::execution::Closing>,
    pub(super) runtime_epoch: current::RuntimeEpoch,
    pub(super) current_call: Option<current::CurrentModelCall>,
    pub(super) current_capture: Option<crate::model::CurrentCaptureHandle>,
    pub(super) current_dirty: watch::Sender<u64>,
    pub(super) current_model_running: bool,
    pub(super) current_snapshot_missing: bool,
    pub(super) is_current_owner: bool,
    pub(super) current_saved_execution: Option<ActiveExecution>,
    pub(super) current_saved_lifecycle: Option<ThreadLifecycle>,
    pub(super) current_task_start_ordinal: u64,
    pub(super) current_retired_previews:
        std::collections::BTreeMap<String, current::SavedToolProgress>,
    pub(super) final_current:
        watch::Sender<Option<Result<current::ThreadCurrent, Arc<current::CurrentError>>>>,
    pub(super) runtime_binding: Option<RuntimeBinding>,
    pub(super) pending_bundle: Option<super::runtime_bundle::PendingBundle>,
    pub(super) bundle_generation: u64,
    pub(super) runtime_model_jobs: usize,
    pub(super) retired_runtime_models: Vec<(DynModelSession, Arc<ModelError>)>,
    pub(super) revoked_runtime_tools: bool,
    pub(super) authorization_dirty: Arc<std::sync::atomic::AtomicBool>,
    pub(super) executing_authorities:
        std::collections::BTreeMap<String, crate::tool::opaque::ExecutionAuthority>,
    pub(super) pending_runtime_facts: std::collections::BTreeMap<String, RuntimeFact>,
    pub(super) context_preparation: Option<context_preparation::ContextPreparer>,
    pub(super) compaction_call: Option<context_preparation::CompactionCall>,
    pub(super) pending_context_compactions: Vec<ContextCompactionEvent>,
    pub(super) model_progress: Option<(String, watch::Receiver<crate::model::ModelProgress>)>,
    pub(super) model_members: Option<super::model_members::MemberCall>,
    /// Outstanding receipt confirmations and auxiliary producer retirements, excluding ordinary flushes.
    pub(super) model_settlement_jobs: usize,
    pub(super) model_settlements:
        std::collections::BTreeMap<String, super::model_settlement::SettlementCall>,
    pub(super) pending_model_members: Vec<crate::model::ModelCompletedMember>,
    pub(super) pending_model_sub_attempt_settlements: Vec<crate::model::ModelSubAttemptSettlement>,
    pub(super) pending_model_member_starts: Vec<crate::model::ModelStartedMember>,
    pub(super) pending_model_member_content_available:
        Vec<crate::model::ModelContentAvailableMember>,
    pub(super) pending_model_connection_events: Vec<crate::model::ModelConnectionEvent>,
    pub(super) permission_leases:
        std::collections::BTreeMap<String, crate::tool::opaque::ExecutionAuthority>,
    pub(super) stopping_turn: Option<String>,
    pub(super) driver: input::ExecutionDriver,
    pub(super) pending_step_preemptions: Vec<StepPreemptionEvent>,
    pub(super) task_commands: mpsc::WeakSender<handle::LoopEvent>,
    pub(super) event_bus: events::EventBus,
    pub(super) progress_tracker: events::ModelProgressTracker,
    pub(super) completed_tasks: Arc<std::sync::RwLock<task_access::CompletedTaskLedger>>,
    pub(super) background:
        futures::stream::FuturesUnordered<super::tool_execution::ToolExecutionFuture>,
    pub(super) nested_sequence: u64,
    pub(super) nested_plans: std::collections::BTreeMap<String, NestedScope>,
    pub(super) executions:
        crate::tool::task::ExecutionTasks<super::tool_execution::ToolExecutionCompletion>,
    pub(super) nested_replies:
        std::collections::BTreeMap<String, oneshot::Sender<Result<ToolCompletion, ThreadError>>>,
    pub(super) interrupt: cancellation::InterruptHandle,
    pub(super) id: String,
    pub(super) model: Option<DynModelSession>,
    /// Availability while prepare temporarily borrows the session out of `model`.
    /// Cleared before publishing its result, so poison/close still comes from the session.
    pub(super) capacity: ContextCapacity,
    pub(super) effect_window: Arc<EffectWindow>,
    pub(super) pending_effects: std::collections::VecDeque<PendingEffect>,
    pub(super) cold: Option<cold::StorageHandle>,
    pub(super) cold_error: Option<Arc<cold::ColdStoreError>>,
    /// `(fault_generation, durability fence)` a latched storage fault must be recovered to, fixed
    /// when that generation's fault is first observed. `None` means this owner owes no recovery.
    /// It is captured once so a later admission while paused cannot move the target that "recovery
    /// succeeded" is verified against.
    pub(super) fault_fence: Option<(u64, u64)>,
    /// Fault generation the attached backend itself reported, if the current latch came from it.
    ///
    /// A backend-named generation is only recovered once that backend verifies the generation's own
    /// recovery; a generation this owner latched by itself (its own reliable-output truncation) has
    /// no backend retry to wait for, so its own fixed fence is the proof. Tracking which generation
    /// the backend owns is what keeps an older, already-verified verdict from releasing a newer
    /// fault.
    pub(super) store_fault_generation: Option<u64>,
    /// Newest generation the backend reported as verified-recovered, as a typed value.
    ///
    /// It is the backend's own receipt ([`crate::thread::cold::StoragePressure::recovered_generation`]),
    /// not a second fact source: the owner is the only place that compares it with the fault it is
    /// holding.
    pub(super) verified_recovery_generation: Option<u64>,
    /// Typed storage fault this owner latched itself, independent of the backend's report.
    ///
    /// An in-flight model/tool result that exceeded the reliable retention budget is a fact about
    /// this Thread's own work, not about the backend: a healthy backend report must not clear it
    /// before an explicit resume names the generation it releases.
    pub(super) local_fault: Option<cold::StorageFaultKind>,
    /// Accepted producer output that still has to be stored, keyed by its stable identity.
    ///
    /// One entry per failed capture/archive operation, so two parallel tools that both failed keep
    /// their own obligation instead of one overwriting the other; the pause stays until *every*
    /// entry of the generation is retried and its bytes really stored, so a healthy history write can
    /// never stand in for an archive that failed. Empty for a pure reliable-budget truncation, whose
    /// accepted bytes the reliable writer saves with the fence. Each value carries the fault
    /// generation it was latched under, so a stale retry cannot clear a newer obligation. Live
    /// execution state, never persisted.
    pub(super) output_obligations:
        std::collections::BTreeMap<String, (u64, Arc<dyn cold::OutputRetryObligation>)>,
    /// Completion of the one original output retry in flight; callers own their own waits.
    pub(super) output_retry_active: Option<CancellationToken>,
    pub(super) maintenance: futures::stream::FuturesUnordered<
        futures::future::BoxFuture<'static, super::execution::MaintenanceCompletion>,
    >,
    pub(super) tool_waiters: std::collections::BTreeMap<String, super::execution::ToolWaiter>,
    /// The attached backend cannot be replaced; never reopen its known-closed notification source.
    pub(super) pressure_watch_closed: bool,
    /// Repaired resource references whose committed result is not resident yet, keyed by call id.
    ///
    /// A producer can report its failed archive the moment it happens, so the user may retry before
    /// the operation has finished and committed its result. The reference must not be dropped then:
    /// it is kept here until the result it supplements is committed, and a repeated repair of the
    /// same call and reference never duplicates. It is released by the commit that applies it, so it
    /// is bounded by the operations still finishing, never by history.
    pub(super) pending_output_repairs:
        std::collections::BTreeMap<String, Vec<crate::context::ResourceReference>>,
    /// Stable identities of obligations this generation already re-stored.
    ///
    /// A producer reports the same failure twice — once through its live channel and again on the
    /// return path — and the return path can arrive *after* the retry already stored the bytes.
    /// Remembering which identities were satisfied keeps that late repeat from re-arming an
    /// obligation the Thread already discharged, so the pause cannot come back for a fact that is
    /// already durable. Bounded by the operations that failed in this generation and cleared when
    /// the generation is released, exactly like the obligations themselves.
    pub(super) satisfied_output_obligations: std::collections::BTreeSet<String>,
    /// Whether the reliable budget could not fund the next operation's live output.
    ///
    /// Nothing was lost, so this is backpressure: admission waits at the storage safety point and
    /// resumes by itself once the budget can hold the quota again.
    pub(super) output_backpressure: bool,
    /// Hysteresis latch of the byte-threshold pressure, so the backpressure above stays a separate
    /// fact instead of being folded into the latch the thresholds own.
    pub(super) threshold_paused: bool,
    /// Live-output quotas held for operations that are still producing a result.
    ///
    /// One entry per in-flight model call or tool call, removed at the same boundary that hands the
    /// result over, so the map is bounded by the number of concurrent operations and never grows
    /// with history.
    pub(super) task_metadata: std::collections::BTreeMap<String, crate::model::OutputBudget>,
    pub(super) operation_budgets:
        std::collections::BTreeMap<String, std::sync::Arc<crate::model::OutputBudget>>,
    /// Owner-owned wakeup every in-flight operation's budget reports its first refusal through.
    ///
    /// A producer charges its output off the owner's stack, so this is how a truncation reaches the
    /// owner the moment it happens: the owner latches the typed fault from `output_refusals` instead
    /// of waiting for the call to return. It is the same fault the release path latches, published by
    /// the same owner, so it is not a second fact source.
    pub(super) output_refusals: tokio::sync::watch::Sender<Option<crate::model::OutputRefusal>>,
    pub(super) output_refusal_rx: tokio::sync::watch::Receiver<Option<crate::model::OutputRefusal>>,
    /// Operations whose transient ceiling is held back until their fact is handed to the queue.
    ///
    /// Bounded by the number of concurrent operations: an entry is added only when a call ended
    /// while the reliable queue still retained its fact, and it is drained at the exact boundary the
    /// queue empties.
    pub(super) deferred_output_releases: std::collections::BTreeSet<String>,
    /// Operation whose reserved output ceiling funds the next effect this owner publishes.
    ///
    /// Set by the call site that is about to commit one of an in-flight operation's own facts, so the
    /// store can transfer exactly that operation's reservation onto the fact instead of charging the
    /// same output twice or spending an unrelated operation's reserved headroom. Consumed by
    /// [`Owner::publish`]; a publish that commits nothing drops it, and the operation's own boundary
    /// then releases its still-untransferred ceiling.
    pub(super) pending_output_claim: Option<String>,
    pub(super) resources: Option<crate::context::ResourceAccess>,
    pub(super) retry_plan: Option<(String, crate::tool::opaque::ToolPlan)>,
    pub(super) published: ThreadSnapshot,
    pub(super) state: ThreadSnapshot,
    pub(super) publish: watch::Sender<super::subscription::OwnerPublication>,
    pub(super) tools: crate::tool::opaque::ToolManager,
    pub(super) pending: std::collections::BTreeMap<String, PendingCall>,
}

impl Owner {
    /// Allocates the live identity of the execution this owner is about to run.
    ///
    /// It exists before any Turn record and before the first storage wait, so a stop names this one
    /// generation instead of inferring a target from the newest Turn. UUIDv4 identities are never
    /// reconstructed from a restored Turn or counter. The legacy checkpoint ordinal is still
    /// advanced for its existing consumers, but grants no authority to address a new execution.
    /// Entering the real Turn only fills the Turn reference and moves the phase.
    pub(super) fn begin_execution(&mut self) -> Result<(), ThreadError> {
        if self.state.execution.is_some() {
            return Ok(());
        }
        let sequence = self
            .state
            .execution_sequence
            .checked_add(1)
            .ok_or(ThreadError::RevisionExhausted)?;
        self.state.execution_sequence = sequence;
        self.state.execution = Some(ActiveExecution {
            id: uuid::Uuid::new_v4().to_string(),
            phase: ExecutionPhase::Preparing,
            turn_id: None,
        });
        self.event_bus.emit(events::CoreEvent::Live(
            events::CoreLiveEvent::RunActivity {
                execution: self.state.execution.clone(),
            },
        ));
        self.publish_snapshot();
        Ok(())
    }

    /// Records that the owned execution really entered its Turn.
    pub(super) fn enter_running_execution(&mut self, turn_id: &str) {
        let changed = match self.state.execution.as_mut() {
            Some(execution) if execution.turn_id.is_none() => {
                execution.turn_id = Some(turn_id.to_owned());
                execution.phase = ExecutionPhase::Running;
                true
            }
            Some(execution) if execution.turn_id.as_deref() == Some(turn_id) => {
                let changed = execution.phase != ExecutionPhase::Running;
                execution.phase = ExecutionPhase::Running;
                changed
            }
            Some(_) | None => false,
        };
        if changed {
            self.event_bus.emit(events::CoreEvent::Live(
                events::CoreLiveEvent::RunActivity {
                    execution: self.state.execution.clone(),
                },
            ));
            self.publish_snapshot();
        }
    }

    /// Publishes a preparation phase of the live execution, if one exists.
    ///
    /// An accepted stop is latched: a later phase report never overwrites `Stopping` while the
    /// interrupted generation is still settling.
    pub(super) fn note_execution_phase(&mut self, phase: ExecutionPhase) {
        let changed = match self.state.execution.as_mut() {
            Some(execution)
                if execution.phase != phase && execution.phase != ExecutionPhase::Stopping =>
            {
                execution.phase = phase;
                true
            }
            Some(_) | None => false,
        };
        if changed {
            self.event_bus.emit(events::CoreEvent::Live(
                events::CoreLiveEvent::RunActivity {
                    execution: self.state.execution.clone(),
                },
            ));
            self.publish_snapshot();
        }
    }

    /// Releases the live execution identity on every exit path of its Turn.
    ///
    /// The owner is serial and owns at most one execution, so the execution this Turn ran is the one
    /// that either already names the Turn or is still preparing for it.
    pub(super) fn finish_execution(&mut self, turn_id: &str) {
        self.finish_execution_with_emit(turn_id, true);
    }

    pub(super) fn finish_execution_with_emit(&mut self, turn_id: &str, emit: bool) {
        let owned = self.state.execution.as_ref().is_some_and(|execution| {
            execution.turn_id.is_none() || execution.turn_id.as_deref() == Some(turn_id)
        });
        if owned {
            self.state.execution = None;
            if emit {
                self.event_bus.emit(events::CoreEvent::Live(
                    events::CoreLiveEvent::RunActivity { execution: None },
                ));
                self.publish_snapshot();
            }
        }
    }

    /// Leaves owed work behind as a durable point before a close has to cut it.
    ///
    /// Only a Thread that really has live or queued work forms one, so an idle Thread that finished
    /// normally does not become continuable just because the process is going away. The point is part
    /// of the same checkpoint boundary as the close, so the final saved state says what was still
    /// owed; it is never a reason to start anything by itself.
    pub(super) fn form_host_shutdown(&mut self) {
        let source_turn = self
            .state
            .turns
            .iter()
            .rev()
            .find(|turn| turn.state == TurnState::Running)
            .map(|turn| turn.turn_id.clone())
            .or_else(|| {
                self.state
                    .execution
                    .as_ref()
                    .and_then(|execution| execution.turn_id.clone())
            });
        let owed = source_turn.is_some()
            || self.state.execution.is_some()
            || self
                .state
                .attempts
                .last()
                .is_some_and(|attempt| attempt.status == AttemptStatus::Running)
            || self
                .state
                .inputs
                .iter()
                .any(|record| record.state == input::InputState::Pending)
            || self.state.wake_messages_through > self.state.consumed_messages;
        if !owed {
            return;
        }
        let source = source_turn.as_ref().map_or_else(
            || "shutdown".to_owned(),
            |turn_id| format!("turn:{turn_id}"),
        );
        self.form_continuation(ContinuationReason::HostShutdown, source_turn, &source);
    }

    pub(super) async fn run(
        mut self,
        mut user_rx: mpsc::Receiver<UserCommand>,
        mut event_rx: mpsc::Receiver<LoopEvent>,
    ) {
        use futures::StreamExt;
        let mut pressure_updates = self.subscribe_pressure();
        let mut pressure_subscribed = self.cold.is_some();
        let mut user_open = true;
        loop {
            let drained_full = self.drain_ready(&mut user_rx, &mut event_rx);
            if !pressure_subscribed && self.cold.is_some() {
                pressure_updates = self.subscribe_pressure();
                pressure_subscribed = true;
                self.admit_cold();
                self.refresh_storage_pressure();
                self.publish_snapshot();
            }
            if self.tools.poll_cleanup() {
                self.publish_snapshot();
            }
            match self.start_ready_work() {
                Ok(true) => {
                    tokio::task::yield_now().await;
                    continue;
                }
                Ok(false) if drained_full => {
                    tokio::task::yield_now().await;
                    continue;
                }
                Ok(false) => (),
                Err(error) => {
                    self.fail_owner_work(error);
                    tokio::task::yield_now().await;
                    continue;
                }
            }
            if self.closing.is_none()
                && self.primary.is_none()
                && self.active.is_none()
                && ((!user_open)
                    || (self.state.lifecycle == ThreadLifecycle::Closed
                        && self.final_current.borrow().is_some()))
            {
                self.handoff_final_current();
                return;
            }
            let cancelled = self.interrupt.active_token().filter(|t| !t.is_cancelled());
            let deadline = self.batch_deadline();
            tokio::select! {
                biased;
                // Tier 0: immediate cancellation
                () = async { match cancelled { Some(token) => token.cancelled().await, None => std::future::pending().await } } => self.publish_snapshot(),
                // Tier 1: user commands & lifecycle control
                command = user_rx.recv(), if user_open => match command {
                    Some(command) => self.handle_user_command(command),
                    None => { user_open = false; self.begin_closing(ClosePurpose::Preserve, None); }
                },
                // Tier 2: internal runtime, model, tool, inbox events
                event = event_rx.recv(), if !event_rx.is_closed() || !event_rx.is_empty() => if let Some(event) = event { self.handle_loop_event(event); },
                completion = async { match self.primary.as_mut() { Some(work) => (&mut work.future).await, None => std::future::pending().await } } => {
                    self.primary = None;
                    if let Err(error) = self.accept_primary(completion) { self.fail_owner_work(error); }
                },
                Some(completion) = self.background.next(), if !self.background.is_empty() => self.finish_background(completion),
                Some(completion) = self.maintenance.next(), if !self.maintenance.is_empty() => self.finish_maintenance(completion),
                Some(admission) = async { match self.model_members.as_mut() { Some(call) => call.receiver.recv().await, None => std::future::pending().await } }, if self.model_members.as_ref().is_some_and(|call| !call.receiver.is_closed() || !call.receiver.is_empty()) => self.admit_model_member(admission),
                Some(reply) = async { match self.compaction_call.as_mut() { Some(call) => call.receiver.recv().await, None => std::future::pending().await } }, if self.compaction_call.as_ref().is_some_and(|call| !call.receiver.is_closed() || !call.receiver.is_empty()) => self.admit_context_compaction(reply),
                changed = async { match self.model_progress.as_mut() { Some((_, receiver)) => receiver.changed().await, None => std::future::pending().await } } => {
                    if changed.is_ok() {
                        if let Some((attempt_id, receiver)) = &self.model_progress {
                            let progress = receiver.borrow().clone();
                            self.progress_tracker.observe(attempt_id, &progress, &self.event_bus);
                        }
                        self.publish_snapshot();
                    } else {
                        if let Some((attempt_id, receiver)) = &self.model_progress {
                            let progress = receiver.borrow().clone();
                            self.progress_tracker.observe(attempt_id, &progress, &self.event_bus);
                            if let Some(call) = self.model_members.as_mut() {
                                call.generation = progress.observation().generation;
                            }
                        }
                        self.progress_tracker.clear(&self.event_bus);
                        self.model_progress = None;
                    }
                },
                changed = self.output_refusal_rx.changed() => if changed.is_ok() {
                    let refusal = self.output_refusal_rx.borrow_and_update().clone();
                    if let Some(refusal) = refusal && self.operation_budgets.contains_key(&refusal.operation_id) { self.latch_output_budget_fault(&refusal.operation_id, refusal.accepted, refusal.limit); }
                },
                () = self.tools.next_cleanup(), if self.tools.has_cleanup() => self.publish_snapshot(),
                () = async { match deadline { Some(deadline) => tokio::time::sleep_until(deadline).await, None => std::future::pending().await } } => (),
                changed = async { match pressure_updates.as_mut() { Some(updates) => updates.changed().await.is_ok(), None => std::future::pending::<bool>().await } } => {
                    if !changed { pressure_updates = None; self.pressure_watch_closed = true; }
                    self.admit_cold(); self.refresh_storage_pressure();
                    if self.cold_error.is_some() { self.state.persistence.resume_required = true; }
                    self.publish_snapshot();
                },
            }
        }
    }

    /// Bounded priority drain: Tier 1 user commands always drain before Tier 2 events and ready
    /// background/maintenance completions. Returns true when the per-tick budget was saturated so
    /// the caller yields fairly before returning to `select!`.
    fn drain_ready(
        &mut self,
        user_rx: &mut mpsc::Receiver<UserCommand>,
        event_rx: &mut mpsc::Receiver<LoopEvent>,
    ) -> bool {
        use futures::{FutureExt, StreamExt};
        const DRAIN_BUDGET: usize = 32;
        let mut drained = 0;
        while drained < DRAIN_BUDGET {
            if let Ok(command) = user_rx.try_recv() {
                self.handle_user_command(command);
            } else if let Ok(event) = event_rx.try_recv() {
                self.handle_loop_event(event);
            } else if let Some(Some(completion)) = self.background.next().now_or_never() {
                self.finish_background(completion);
            } else if let Some(Some(completion)) = self.maintenance.next().now_or_never() {
                self.finish_maintenance(completion);
            } else {
                return false;
            }
            drained += 1;
        }
        true
    }

    fn handle_user_command(&mut self, command: UserCommand) {
        if self.interrupt.is_closing()
            && matches!(
                command,
                UserCommand::CurrentResume { .. }
                    | UserCommand::Turn(_, _)
                    | UserCommand::ResolveInteraction(_, _)
                    | UserCommand::CancelInteraction(_, _)
            )
        {
            command.reject();
            return;
        }
        match command {
            UserCommand::CurrentResume {
                epoch,
                expected_stop_generation,
                input,
                reply,
            } => match self.prepare_current_resume(epoch, expected_stop_generation, input) {
                Ok(input) => {
                    match self.start_run(input, super::execution::RunReply::Current(reply), None) {
                        Err((error, reply)) => reply.reject(error),
                        Ok(()) => self.active.as_mut().unwrap().restored = true,
                    }
                }
                Err(error) => {
                    let _ = reply.send(Err(error));
                }
            },
            UserCommand::ResolveInteraction(resolution, reply) => {
                let _ = reply.send(self.resolve_interaction(resolution));
            }
            UserCommand::CancelInteraction(cancellation, reply) => {
                let _ = reply.send(self.cancel_interaction(cancellation));
            }
            UserCommand::ResolvePermission(resolution, reply) => {
                let _ = reply.send(self.resolve_execution_permission(resolution));
            }
            UserCommand::ContinueMessage(message, options, receipt, reply) => {
                let _ = reply.send(self.continue_message(message, options, receipt.as_deref()));
            }
            UserCommand::Resume(request, options, reply) => {
                let _ = reply.send(self.resume(request, options));
            }
            UserCommand::InterruptTurn { expected, reply } => {
                let active = self
                    .state
                    .turns
                    .iter()
                    .rev()
                    .find(|turn| turn.state == TurnState::Running)
                    .map(|turn| turn.turn_id.clone())
                    .or_else(|| self.stopping_turn.clone());
                let result = match active {
                    Some(turn_id) if expected.as_ref().is_some_and(|id| id != &turn_id) => {
                        Err(ThreadError::InvalidIdentity)
                    }
                    Some(turn_id) => {
                        self.stopping_turn = Some(turn_id.clone());
                        self.pause_execution();
                        self.note_execution_phase(ExecutionPhase::Stopping);
                        let result = self.cancel_turn_tasks(&turn_id);
                        let interrupted = self.interrupt.interrupt();
                        self.publish_snapshot();
                        result.map(|()| interrupted)
                    }
                    None => {
                        self.pause_execution();
                        self.publish_snapshot();
                        Ok(false)
                    }
                };
                let _ = reply.send(result);
            }
            UserCommand::InterruptExecution { expected, reply } => {
                let current = self.state.execution.clone();
                let result = match current {
                    Some(execution) if execution.id == expected => {
                        let turn_id = execution.turn_id.clone();
                        self.note_execution_phase(ExecutionPhase::Stopping);
                        self.pause_execution();
                        let source = turn_id
                            .as_ref()
                            .map_or_else(|| "execution".to_owned(), |id| format!("turn:{id}"));
                        self.form_continuation(
                            ContinuationReason::UserStop,
                            turn_id.clone(),
                            &source,
                        );
                        let tasks = turn_id.as_ref().map_or(Ok(()), |turn_id| {
                            self.stopping_turn = Some(turn_id.clone());
                            self.cancel_turn_tasks(turn_id)
                        });
                        let cancelled = self.interrupt.interrupt();
                        self.publish().and(tasks).map(|()| cancelled)
                    }
                    Some(_) | None => Err(ThreadError::InvalidIdentity),
                };
                let _ = reply.send(result);
            }
            UserCommand::CancelRunningTurn { expected, reply } => {
                let running = self
                    .state
                    .turns
                    .iter()
                    .any(|turn| turn.state == TurnState::Running && turn.turn_id == expected);
                let result = if running {
                    self.stopping_turn = Some(expected.clone());
                    let result = self.cancel_turn_tasks(&expected);
                    let interrupted = self.active.as_ref().is_some_and(|run| {
                        run.turn_cancel.cancel();
                        true
                    });
                    self.publish_snapshot();
                    result.map(|()| interrupted)
                } else {
                    Ok(false)
                };
                let _ = reply.send(result);
            }
            UserCommand::SubmitInput(input, drive, reply) => {
                let result = self.submit_immediate_input(input, drive);
                let _ = reply.send(result);
            }
            UserCommand::DiscardInput(id, reply) => {
                let _ = reply.send(self.discard_input(&id));
            }
            UserCommand::DrivePending(options, reply) => {
                let _ = reply.send(self.drive_pending(options));
            }
            UserCommand::PauseExecution(reply) => {
                self.pause_execution();
                let _ = reply.send(());
            }
            UserCommand::CancelTask(id, reply) => {
                let _ = reply.send(self.cancel_task(&id));
            }
            UserCommand::Flush(reply) => self.start_flush(reply),
            UserCommand::BeginIdleClose(reply) => {
                let idle = self.active.is_none()
                    && !self
                        .state
                        .turns
                        .iter()
                        .any(|turn| turn.state == TurnState::Running)
                    && !self
                        .state
                        .inputs
                        .iter()
                        .any(|record| record.state == input::InputState::Pending)
                    && !self
                        .state
                        .tasks
                        .values()
                        .any(|task| task.status == task::TaskStatus::Running)
                    && !self
                        .state
                        .interactions
                        .values()
                        .any(|record| record.state == interactions::InteractionState::Pending)
                    && !self
                        .state
                        .permissions
                        .values()
                        .any(|record| record.state == permissions::PermissionState::Pending)
                    && !self
                        .state
                        .inbox
                        .iter()
                        .any(|record| record.sequence > self.state.consumed_messages)
                    && self.pending.is_empty()
                    && self.pending_effects.is_empty()
                    && self.output_obligations.is_empty()
                    && self.pending_output_repairs.is_empty()
                    && self.operation_budgets.is_empty()
                    && !self.state.persistence.resume_required
                    && self.cold_error.is_none()
                    && !self.cold.as_ref().is_some_and(|store| {
                        let status = store.idle_status(&self.id);
                        status.reclaimable_thread_bytes != Some(status.pressure.thread_bytes)
                            || status.pressure.durable_sequence < self.state.commit_sequence
                            || status.pressure.error.is_some()
                    });
                let idle = if idle {
                    self.interrupt.begin_close();
                    self.state.lifecycle = ThreadLifecycle::Closing;
                    match self.publish() {
                        Ok(()) => true,
                        Err(error) => {
                            self.driver.fail(Arc::new(error));
                            false
                        }
                    }
                } else {
                    false
                };
                let _ = reply.send(idle);
            }
            UserCommand::Turn(input, reply) => {
                if let Err((error, reply)) =
                    self.start_run(input, super::execution::RunReply::Turn(reply), None)
                {
                    reply.reject(error);
                }
            }
            UserCommand::Close(purpose, reply) => {
                self.begin_closing(purpose, Some(reply));
            }
        }
    }

    fn handle_loop_event(&mut self, event: LoopEvent) {
        if self.interrupt.is_closing()
            && matches!(
                event,
                LoopEvent::ContextPreparation(_, _)
                    | LoopEvent::Reveal(_, _)
                    | LoopEvent::RequestInteraction(_, _)
                    | LoopEvent::Application(_, _)
                    | LoopEvent::Resources(_, _)
                    | LoopEvent::Retry { .. }
                    | LoopEvent::AttachHistory(_, _)
                    | LoopEvent::AttachEventSink(_, _)
                    | LoopEvent::Capacity(_, _)
                    | LoopEvent::PatchRuntimeFacts(_, _)
                    | LoopEvent::UpdateFacts(_, _)
                    | LoopEvent::CompactContext(_, _, _)
                    | LoopEvent::ReplaceContext(_, _)
                    | LoopEvent::Execute(_, _, _)
                    | LoopEvent::Step(_, _)
            )
        {
            event.reject();
            return;
        }
        match event {
            LoopEvent::ReadCurrent { captured, reply } => {
                let _ = reply.send(self.read_current(captured));
            }
            LoopEvent::ReadResume(request, reply) => {
                let _ = reply.send(self.read_resume(&request));
            }
            LoopEvent::InvokeNested {
                caller,
                executor,
                tool_id,
                arguments,
                cancellation,
                reply,
            } => match self.begin_nested(caller, executor, tool_id, arguments, cancellation) {
                Ok(id) => {
                    self.nested_replies.insert(id, reply);
                }
                Err(error) => {
                    let _ = reply.send(Err(error));
                }
            },
            LoopEvent::InstallRuntimeBundle(update, batch, reply) => {
                let result = if self.interrupt.is_closing()
                    || self.state.lifecycle != ThreadLifecycle::Open
                {
                    Err(ThreadError::Closed)
                } else {
                    self.queue_runtime_bundle(*update, batch.take().unwrap_or_default())
                };
                let _ = reply.send(result);
            }
            LoopEvent::RuntimeAuthorizationChanged => {
                if let Err(error) = self.retire_revoked_runtime_tools() {
                    self.fail_owner_work(error);
                }
            }
            LoopEvent::RegisterTools(tools, reply) => {
                let tools = tools.take().unwrap_or_default();
                self.tools.retain_candidates(&tools);
                let result = if self.state.lifecycle == ThreadLifecycle::Open
                    && !self.interrupt.is_closing()
                {
                    let result = self
                        .tools
                        .replace(tools)
                        .and_then(|()| self.revoke_stale_permissions());
                    result.and_then(|()| {
                        self.state.discovered_tools = self.tools.discovery();
                        self.publish()
                    })
                } else {
                    drop(tools);
                    Err(ThreadError::Closed)
                };
                if result.is_err() {
                    self.publish_snapshot();
                }
                let _ = reply.send(result);
            }
            LoopEvent::RetryToolCleanup(reply) => {
                self.tools.retry_cleanup();
                self.retry_retired_runtime_models();
                self.publish_snapshot();
                let _ = reply.send(Ok(()));
            }
            LoopEvent::RetireTools(batch, reply) => {
                let tools = batch.take().unwrap_or_default();
                self.tools.retain_candidates(&tools);
                drop(tools);
                self.publish_snapshot();
                let _ = reply.send(Ok(()));
            }
            LoopEvent::QueueRuntimeFacts(facts, reply) => {
                let _ = reply.send(self.queue_runtime_facts(facts));
            }
            LoopEvent::ToolProgress {
                caller,
                executor,
                update,
                reply,
            } => {
                let result = self.report_tool_progress(caller, executor, update);
                let _ = reply.send(result);
            }
            LoopEvent::ToolOutputStorageFault {
                caller,
                executor,
                fault,
                reply,
            } => {
                let result = self.report_tool_output_storage_fault(caller, executor, fault);
                let _ = reply.send(result);
            }
            LoopEvent::RequestPermission {
                caller,
                authority,
                payload,
                reply,
            } => {
                let _ = reply.send(self.request_execution_permission(caller, authority, payload));
            }
            LoopEvent::OpenAuxiliaryModel {
                caller,
                turn_id,
                reply,
            } => {
                let _ = reply.send(self.open_auxiliary_model_settlement(caller, turn_id));
            }
            LoopEvent::SettleModel { settlement, reply } => {
                self.admit_model_settlement(settlement, reply);
            }
            LoopEvent::VerifyModelSettlement { settlement, reply } => {
                self.verify_saved_model_settlement(settlement, reply);
            }
            LoopEvent::RecordTaskObservation {
                caller,
                payload,
                reply,
            } => {
                let running = self
                    .state
                    .tasks
                    .get(&caller)
                    .is_some_and(|task| task.status == task::TaskStatus::Running);
                let id = format!("tool-observation:{}", payload.format());
                let result = if running {
                    let expected_revision =
                        self.state.extensions.get(&id).map(|record| record.revision);
                    self.mutate_extensions(vec![extensions::ExtensionMutation::Put {
                        id,
                        expected_revision,
                        payload,
                    }])
                    .map(|_| ())
                } else {
                    Err(ThreadError::TaskAccessExpired)
                };
                let _ = reply.send(result);
            }
            LoopEvent::ValidateExecution {
                caller,
                executor,
                reply,
            } => {
                let result = if self.state.lifecycle != ThreadLifecycle::Open
                    || self.interrupt.is_closing()
                {
                    Err(ThreadError::Closed)
                } else if !self
                    .state
                    .tasks
                    .get(&caller)
                    .is_some_and(|task| task.status == task::TaskStatus::Running)
                    || self
                        .executions
                        .token(&caller)
                        .is_some_and(|token| token.is_cancelled())
                {
                    Err(ThreadError::TaskAccessExpired)
                } else if !executor.remains_authorized(&self.tools) {
                    Err(ThreadError::ToolPermissionRevoked)
                } else {
                    Ok(())
                };
                let _ = reply.send(result);
            }
            LoopEvent::ToolCancelTask {
                caller,
                authorization,
                target,
                reply,
            } => {
                let result = match self.state.tasks.get(&caller) {
                    Some(task) if task.status == task::TaskStatus::Running => {
                        if self
                            .tools
                            .permits_task_cancellation(&task.tool_id, authorization.as_ref())
                        {
                            self.cancel_task(&target)
                        } else {
                            Err(ThreadError::TaskAccessDenied)
                        }
                    }
                    Some(_) | None => Err(ThreadError::TaskAccessExpired),
                };
                let _ = reply.send(result);
            }
            LoopEvent::RetryHistoryAdmission(reply) => {
                let _ = reply.send(self.retry_history_admission());
            }
            LoopEvent::ResumeStorage { generation, reply } => {
                let result = if self.interrupt.is_closing() {
                    Err(ThreadError::Closed)
                } else {
                    self.resume_storage(generation)
                };
                let _ = reply.send(result);
            }
            LoopEvent::RetryOutputStorage(reply) => {
                self.start_output_retry(reply);
            }
            LoopEvent::Message(message, drive, reply) => {
                let result = if self.interrupt.is_closing() {
                    Err(ThreadError::Closed)
                } else {
                    self.receive_message(message, drive, None)
                };
                let _ = reply.send(result);
            }
            LoopEvent::MessageWithExtensions {
                message,
                mutations,
                reply,
            } => {
                let result = if self.interrupt.is_closing() {
                    Err(ThreadError::Closed)
                } else {
                    self.receive_message_with_extensions(message, mutations)
                };
                let _ = reply.send(result);
            }
            LoopEvent::MutateExtensions(mutations, reply) => {
                let result = if self.interrupt.is_closing() {
                    Err(ThreadError::Closed)
                } else {
                    self.mutate_extensions(mutations)
                };
                let _ = reply.send(result);
            }
            LoopEvent::WakeAcceptedMessage {
                id,
                sequence,
                options,
                reply,
            } => {
                let _ = reply.send(self.wake_accepted_message(&id, sequence, options));
            }
            LoopEvent::ContextPreparation(preparation, reply) => {
                self.context_preparation = preparation;
                let _ = reply.send(Ok(()));
            }
            LoopEvent::Reveal(ids, reply) => {
                let result = self
                    .tools
                    .reveal(&ids)
                    .map_err(ThreadError::from)
                    .and_then(|()| {
                        self.state.discovered_tools = self.tools.discovery();
                        self.publish()
                    });
                let _ = reply.send(result);
            }
            LoopEvent::RequestInteraction(request, reply) => {
                let _ = reply.send(self.request_interaction(request));
            }
            LoopEvent::Application(update, reply) => {
                let _ = reply.send(self.update_application(update));
            }
            LoopEvent::Resources(resources, reply) => {
                let result = if self.state.lifecycle == ThreadLifecycle::Open {
                    if !self
                        .resources
                        .as_ref()
                        .is_some_and(|current| current.same_service(&resources))
                    {
                        self.retry_plan = None;
                    }
                    self.resources = Some(resources);
                    Ok(())
                } else {
                    Err(ThreadError::Closed)
                };
                let _ = reply.send(result);
            }
            LoopEvent::Retry {
                source,
                attempt,
                cancellation,
                reply,
            } => {
                self.schedule_retry(source, attempt, cancellation, reply);
            }
            LoopEvent::AttachHistory(store, reply) => {
                let result = if self.cold.is_some() || self.state.lifecycle != ThreadLifecycle::Open
                {
                    Err(ThreadError::InvalidIdentity)
                } else {
                    self.cold = Some(store.into_storage());
                    self.admit_cold();
                    self.publish_snapshot();
                    Ok(())
                };
                let _ = reply.send(result);
            }
            LoopEvent::AttachEventSink(sink, reply) => {
                self.event_bus.attach_sink(sink);
                let _ = reply.send(Ok(()));
            }
            LoopEvent::Capacity(capacity, reply) => {
                let result = if self.state.lifecycle == ThreadLifecycle::Open {
                    self.capacity = capacity;
                    Ok(())
                } else {
                    Err(ThreadError::Closed)
                };
                let _ = reply.send(result);
            }
            LoopEvent::PatchRuntimeFacts(facts, reply) => {
                let _ = reply.send(self.patch_runtime_facts(facts));
            }
            LoopEvent::UpdateFacts(facts, reply) => {
                let _ = reply.send(self.update_facts(facts));
            }
            LoopEvent::CompactContext(revision, cancellation, reply) => {
                self.schedule_compaction(revision, cancellation, reply);
            }
            LoopEvent::ReplaceContext(replacement, reply) => {
                let _ = reply.send(self.replace_context(replacement));
            }
            LoopEvent::Execute(id, cancellation, reply) => {
                self.schedule_tool(id, cancellation, reply);
            }
            LoopEvent::Step(input, reply) => {
                self.schedule_step(input, None, super::execution::RunReply::Step(reply));
            }
        }
    }

    /// Subscribes to the attached backend's storage-change notification.
    ///
    /// `None` while no store is attached: there is no storage fact to wait on then, so the idle loop
    /// arms nothing instead of polling.
    pub(super) fn subscribe_pressure(&self) -> Option<watch::Receiver<()>> {
        if self.pressure_watch_closed {
            return None;
        }
        self.cold
            .as_ref()
            .and_then(|store| store.subscribe_pressure(&self.id))
    }

    pub(super) fn publish_snapshot(&self) {
        let mut snapshot = self.state.clone();
        snapshot.tool_cleanup = self.tools.cleanup_state();
        snapshot.tool_progress.retain(|id, _| {
            snapshot.lifecycle == ThreadLifecycle::Open
                && snapshot
                    .tasks
                    .get(id)
                    .is_some_and(|task| task.status == task::TaskStatus::Running)
        });
        // 正在被取消或关闭的尝试不产生任何可确认的速度：这类快照保留观察到的内容与失败
        // 观察，但撤销整组 live 用量与耗时，消费者因此回退到 canonical 成对样本。门控在
        // 每次发布时重新计算，所以随后到达的在途观察也无法把这个代次的 pair 复活。
        //
        // 直接取消或正在软抢占中的尝试不保留活体速度采样；明确停轮、关闭或显式取消的 Turn
        // 撤回实时测量，让消费者回退到 canonical 样本。
        let live_measurement_withdrawn = self.stopping_turn.is_some()
            || self.interrupt.is_closing()
            || self.interrupt.active_cancelled()
            || self
                .active
                .as_ref()
                .is_some_and(|run| run.is_step_preempted(false));
        snapshot.model_progress = self
            .model_progress
            .as_ref()
            .filter(|(id, _)| {
                snapshot.attempts.last().is_some_and(|attempt| {
                    &attempt.attempt_id == id && attempt.status == AttemptStatus::Running
                })
            })
            .map(|(id, receiver)| {
                let mut progress = receiver.borrow().clone();
                if live_measurement_withdrawn {
                    progress.withdraw_live_usage();
                }
                crate::model::ActiveModelProgress {
                    attempt_id: id.clone(),
                    progress,
                }
            });
        snapshot.input_execution = if let Some(error) = self.driver.error() {
            input::InputExecution::Failed {
                error: error.clone(),
            }
        } else if let Some(turn_id) = &self.stopping_turn {
            input::InputExecution::Interrupting {
                turn_id: turn_id.clone(),
            }
        } else if let Some(input_id) = self.active.as_ref().and_then(|run| {
            run.primary_input_id
                .clone()
                .or_else(|| run.current_step_inputs.first().cloned())
        }) {
            input::InputExecution::Running { input_id }
        } else if self.driver.options().is_some()
            && self.state.lifecycle == ThreadLifecycle::Open
            && !self.interrupt.is_closing()
        {
            input::InputExecution::Ready
        } else {
            input::InputExecution::Paused
        };
        snapshot.model_available = self.model.as_ref().map_or(
            self.primary
                .as_ref()
                .is_some_and(|work| work.model_available),
            DynModelSession::is_available,
        );

        snapshot.observation_revision = self
            .publish
            .borrow()
            .observation_revision
            .checked_add(1)
            .expect("Thread observation revision exhausted");
        self.publish
            .send_replace(super::subscription::OwnerPublication {
                snapshot,
                binding: self.runtime_binding.clone(),
            });
        self.current_dirty.send_modify(|revision| {
            *revision = revision
                .checked_add(1)
                .expect("current dirty revision exhausted");
        });
    }

    pub(super) fn publish(&mut self) -> Result<(), ThreadError> {
        self.publish_primary()?;
        if self.interrupt.is_deleting() {
            return Ok(());
        }
        // The repair supplements a result that must already be committed. Keep it in its
        // own effect so the snapshot of the original result never includes the supplement.
        if self.flush_pending_output_repairs() {
            self.publish_once()?;
        }
        Ok(())
    }

    /// Publishes the effect carrying this mutation and returns its exact sequence.
    pub(super) fn publish_primary(&mut self) -> Result<Option<u64>, ThreadError> {
        // Reserve both resource cuts before consuming effect buffers, claims or sequence numbers.
        let revision = self.state.interaction_collection_revision_for(
            &self.published,
            &self.state.interactions,
            &self.state.permissions,
        )?;
        if self.interrupt.is_deleting() {
            // Deletion still publishes real execution/resource state to resident waiters, but
            // never creates a new cold-store obligation for the content being removed.
            self.state.interaction_collection_revision = revision;
            self.published = self.state.clone();
            self.publish_snapshot();
            return Ok(None);
        }
        if self.retry_plan.as_ref().is_some_and(|(id, plan)| {
            !self.state.attempts.last().is_some_and(|attempt| {
                &attempt.attempt_id == id
                    && match attempt.status {
                        AttemptStatus::Running => true,
                        AttemptStatus::Failed | AttemptStatus::Cancelled => {
                            attempt.input_revision == self.state.context.revision
                                && plan.retry_compatible(&self.tools.freeze())
                        }
                        _ => false,
                    }
            })
        }) {
            self.retry_plan = None;
        }
        let previous = self.state.commit_sequence;
        self.publish_once()?;
        Ok((self.state.commit_sequence > previous).then_some(self.state.commit_sequence))
    }

    /// Commits the resident facts as exactly one effect batch and emits `CoreEvent::Durable`.
    fn publish_once(&mut self) -> Result<(), ThreadError> {
        let history_progress = self.state.tool_progress.clone();
        let revision = self.state.interaction_collection_revision_for(
            &self.published,
            &self.state.interactions,
            &self.state.permissions,
        )?;
        for (id, progress) in &self.state.tool_progress {
            if let Some(task) = self.state.tasks.get(id)
                && (self.state.lifecycle != ThreadLifecycle::Open
                    || task.status != task::TaskStatus::Running)
            {
                self.current_retired_previews.insert(
                    task.call_id.clone(),
                    current::SavedToolProgress::capture(self.runtime_epoch, progress),
                );
            }
        }
        self.state.tool_progress.retain(|id, _| {
            self.state.lifecycle == ThreadLifecycle::Open
                && self
                    .state
                    .tasks
                    .get(id)
                    .is_some_and(|task| task.status == task::TaskStatus::Running)
        });
        let sequence = self.state.commit_sequence.saturating_add(1);
        let Some(effect) = ThreadEffectBatch::between(
            &self.id,
            &self.published,
            &self.state,
            sequence,
            super::model_members::MemberEffects {
                completed: std::mem::take(&mut self.pending_model_members).into(),
                started: std::mem::take(&mut self.pending_model_member_starts).into(),
                content_available: std::mem::take(&mut self.pending_model_member_content_available),
                settlements: std::mem::take(&mut self.pending_model_sub_attempt_settlements).into(),
                connections: std::mem::take(&mut self.pending_model_connection_events).into(),
            },
            std::mem::take(&mut self.pending_context_compactions).into(),
            std::mem::take(&mut self.pending_step_preemptions).into(),
        ) else {
            self.pending_output_claim = None;
            return Ok(());
        };
        let mut output_claim = self.pending_output_claim.take();
        let mut encoded_bytes = None;
        if let Some(budget) = output_claim
            .as_ref()
            .and_then(|operation| self.operation_budgets.get(operation))
            .filter(|budget| budget.tracks_member_claims())
        {
            let funded = crate::model::encoded_member_bytes(&effect)
                .map_err(|source| cold::ColdStoreError {
                    source: Box::new(source),
                })
                .and_then(|bytes| {
                    encoded_bytes = Some(bytes);
                    budget.register_output_claim(bytes)
                });
            if funded.is_err() {
                output_claim = None;
            }
        }
        let effect = Arc::new(effect);
        self.state.interaction_collection_revision = revision;
        self.state.commit_sequence = sequence;
        if let Some(store) = &self.cold {
            store.fold_usage(&mut self.state.usage_summary, &effect);
        } else {
            super::usage::fold_effect(&mut self.state.usage_summary, &effect);
        }
        // Only newly committed terminal revisions belong here. Republishing unrelated work must
        // never overwrite an original delivery after retain_live_facts has pruned it.
        {
            let mut ledger = self
                .completed_tasks
                .write()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            for task in effect.tasks.iter() {
                if task.status != task::TaskStatus::Running {
                    let delivery = effect
                        .deliveries
                        .iter()
                        .find(|d| d.call_id == task.call_id)
                        .cloned();
                    ledger.record(task.clone(), delivery);
                }
            }
        }
        let mut history_state = self.state.clone();
        history_state.tool_progress = history_progress;
        history_state.model_progress =
            self.model_progress
                .as_ref()
                .map(|(id, receiver)| crate::model::ActiveModelProgress {
                    attempt_id: id.clone(),
                    progress: receiver.borrow().clone(),
                });
        let export = Arc::new(HistoryExport {
            effect,
            state: history_state,
            output_claim,
        });
        self.retain_live_facts()?;
        self.published = self.state.clone();
        self.effect_window.push_current(export.clone());
        self.pending_effects.push_back(PendingEffect {
            write: PendingWrite::History(export.clone()),
            encoded_bytes,
        });
        self.event_bus.emit(events::CoreEvent::Durable(Arc::new(
            events::CoreCommitEvent {
                thread_id: self.id.clone(),
                sequence,
                export,
            },
        )));
        self.admit_cold();
        self.publish_snapshot();
        Ok(())
    }

    fn retain_live_facts(&mut self) -> Result<(), ThreadError> {
        self.state.retain_live_facts()?;
        self.current_retired_previews.retain(|call_id, _| {
            self.state
                .tasks
                .values()
                .any(|task| &task.call_id == call_id)
        });
        Ok(())
    }

    /// Names the reservation that funds the facts the next [`Owner::publish`] commits.
    ///
    /// An in-flight model/tool call holds a reliable output ceiling (see
    /// [`Owner::reserve_operation_output`]) that funds *everything* that call commits on this
    /// owner's stack — its task/attempt lifecycle rows as well as the eventual result. Naming the
    /// operation here is what lets the reliable channel take those bytes over from that one ceiling:
    /// without it a routine intermediate row (a task turning `Running`) would have to fit unrelated
    /// free headroom and could be refused — and latched as a storage fault — while the very ceiling
    /// reserved for it sat unused. The claim is consumed by exactly one publish, so a commit that
    /// turns out to produce no fact simply drops it.
    pub(super) fn claim_output(&mut self, operation: impl Into<String>) {
        self.pending_output_claim = Some(operation.into());
    }
}

#[cfg(test)]
mod close_tests {
    use super::ClosePurpose;
    use crate::{
        context::{ContextContent, OpaquePayload},
        model::{
            DynModelSession, ModelError, ModelRequest, ModelSession, ModelStepOutput,
            ModelToolCall, PreparedModelCall,
        },
        thread::{
            HistoryExport, ModelStepLimit, ThreadError, ThreadHandle, ThreadLifecycle, TurnInput,
            UsageSummary,
            cold::{
                ColdStoreError, StorageAdmissionBackpressure, StorageIdleStatus, StoragePressure,
            },
            history_sink::{HistorySink, HistorySinkHandle},
            input::{InputPurpose, ThreadInput},
        },
        tool::{
            ToolOutput,
            opaque::{CallContext, Registration, ToolError},
        },
    };
    use pl_agent_tool::{Tool, ToolDefinition, ToolHandle};
    use std::sync::{
        Arc, LazyLock,
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
    };
    use tokio_util::sync::CancellationToken;

    struct BackgroundModel {
        issued: bool,
        closed: Arc<AtomicUsize>,
    }

    impl ModelSession for BackgroundModel {
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> Result<PreparedModelCall, ModelError> {
            let tool_calls = if std::mem::replace(&mut self.issued, true) {
                vec![]
            } else {
                vec![ModelToolCall {
                    presentation_contract: None,
                    rejection: None,
                    call_id: "held-call".into(),
                    tool_id: "held".into(),
                    arguments: OpaquePayload::text("held"),
                }]
            };
            Ok(PreparedModelCall::new(async move {
                Ok(ModelStepOutput {
                    turn_action: Default::default(),
                    attempt_id: request.attempt_id,
                    base_context_revision: request.context.revision,
                    content: vec![ContextContent::Text {
                        text: "background work accepted".into(),
                    }],
                    tool_calls,
                    private_context: None,
                    usage: Default::default(),
                })
            }))
        }

        async fn close(&mut self) -> Result<(), ModelError> {
            self.closed.fetch_add(1, Ordering::SeqCst);
            Ok(())
        }
    }

    #[derive(Debug, Default)]
    struct HeldTool {
        started: CancellationToken,
        cancelled: CancellationToken,
        release: CancellationToken,
        joined: AtomicBool,
        close_attempts: AtomicUsize,
    }

    struct HeldToolInstance(Arc<HeldTool>);

    impl Tool for HeldToolInstance {
        type Input = OpaquePayload;
        type Context = CallContext;
        type Output = ToolOutput;
        type Error = ToolError;

        fn definition(&self) -> &ToolDefinition {
            static DEFINITION: LazyLock<ToolDefinition> = LazyLock::new(|| {
                ToolDefinition::text("held", "Text tool for thread close tests")
                    .expect("valid definition")
            });
            &DEFINITION
        }

        async fn execute(
            &self,
            _: OpaquePayload,
            context: CallContext,
        ) -> Result<ToolOutput, ToolError> {
            self.0.started.cancel();
            context.cancellation.cancelled().await;
            self.0.cancelled.cancel();
            self.0.release.cancelled().await;
            self.0.joined.store(true, Ordering::SeqCst);
            Err(ToolError::new(ThreadError::Cancelled))
        }

        async fn close(&self) -> Result<(), ToolError> {
            assert!(self.0.joined.load(Ordering::SeqCst));
            if self.0.close_attempts.fetch_add(1, Ordering::SeqCst) == 0 {
                return Err(ToolError::new(std::io::Error::other(
                    "resource close failed once",
                )));
            }
            Ok(())
        }
    }

    #[derive(Debug, Default)]
    struct SaveProbe {
        admitted: AtomicU64,
        durable: AtomicU64,
        admissions: AtomicUsize,
        fail_admit: AtomicBool,
        block_backpressure: AtomicBool,
    }

    impl HistorySink for Arc<SaveProbe> {
        fn fold_usage(
            &self,
            summary: &mut UsageSummary,
            effect: &crate::thread::ThreadEffectBatch,
        ) {
            crate::thread::usage::fold_effect(summary, effect);
        }
        fn reserve_observed_item(&self, _: &str, _: &str, _: &str) -> Result<(), ColdStoreError> {
            Ok(())
        }
        fn reserve_operation_output(
            &self,
            _: &str,
            _: &str,
            max: u64,
        ) -> Result<u64, ColdStoreError> {
            Ok(max)
        }
        fn charge_operation_output(&self, _: &str, _: &str, _: u64) -> Result<(), ColdStoreError> {
            Ok(())
        }
        fn release_operation_output(&self, _: &str, _: &str) {}
        fn subscribe_pressure(&self, _: &str) -> Option<tokio::sync::watch::Receiver<()>> {
            None
        }
        fn admit(&self, _: &str, export: Arc<HistoryExport>) -> Result<(), ColdStoreError> {
            self.admissions.fetch_add(1, Ordering::SeqCst);
            if self.block_backpressure.load(Ordering::SeqCst) {
                return Err(ColdStoreError {
                    source: Box::new(StorageAdmissionBackpressure("queue full".into())),
                });
            }
            if self.fail_admit.load(Ordering::SeqCst) {
                return Err(ColdStoreError {
                    source: Box::new(std::io::Error::other(
                        "final save must be skipped for deletion",
                    )),
                });
            }
            let seq = export.effect.sequence;
            self.admitted.fetch_max(seq, Ordering::SeqCst);
            self.durable.fetch_max(seq, Ordering::SeqCst);
            Ok(())
        }
        fn pressure(&self, _: &str) -> StoragePressure {
            StoragePressure {
                durable_sequence: self.durable.load(Ordering::SeqCst),
                ..Default::default()
            }
        }
        fn idle_status(&self, thread_id: &str) -> StorageIdleStatus {
            StorageIdleStatus {
                pressure: self.pressure(thread_id),
                reclaimable_thread_bytes: Some(0),
            }
        }
    }

    async fn close(thread: &ThreadHandle, purpose: ClosePurpose) -> Result<(), ThreadError> {
        match purpose {
            ClosePurpose::Preserve => thread.close().await,
            ClosePurpose::Delete => thread.close_for_deletion().await,
        }
    }

    async fn exercise_close(purpose: ClosePurpose) {
        let model_closed = Arc::new(AtomicUsize::new(0));
        let thread = ThreadHandle::start(
            "close-purpose".into(),
            DynModelSession::new(BackgroundModel {
                issued: false,
                closed: model_closed.clone(),
            }),
        )
        .unwrap();
        let store = Arc::new(SaveProbe::default());
        thread
            .attach_history(HistorySinkHandle::new(store.clone()))
            .await
            .unwrap();
        let registration =
            Registration::prepare("held".into(), OpaquePayload::text("held")).unwrap();
        let tool = Arc::new(HeldTool::default());
        thread
            .register_tools(vec![
                registration.attach(ToolHandle::new(HeldToolInstance(tool.clone()))),
            ])
            .await
            .unwrap();
        thread
            .run_turn(TurnInput {
                turn_id: "background".into(),
                attempt_prefix: "attempt".into(),
                content: vec![ContextContent::Text {
                    text: "start background work".into(),
                }],
                max_model_steps: ModelStepLimit::Limited(3.try_into().unwrap()),
                cancellation: CancellationToken::new(),
            })
            .await
            .unwrap();
        tool.started.cancelled().await;
        thread
            .submit_input(
                ThreadInput {
                    id: "queued-before-close".into(),
                    purpose: InputPurpose::Message,
                    payload: OpaquePayload::text("pending work"),
                    context: vec![ContextContent::Text {
                        text: "pending work".into(),
                    }],
                },
                None,
            )
            .await
            .unwrap();
        assert!(thread.snapshot().continuation.is_none());
        let admissions = store.admissions.load(Ordering::SeqCst);
        store.fail_admit.store(true, Ordering::SeqCst);
        let mut closing = Box::pin(close(&thread, purpose));
        tokio::select! {
            result = &mut closing => panic!("close skipped the real task join: {result:?}"),
            () = tool.cancelled.cancelled() => {}
        }
        assert!(!tool.joined.load(Ordering::SeqCst));
        assert!(futures::poll!(&mut closing).is_pending());
        tool.release.cancel();
        assert!(closing.await.is_err(), "first resource close must fail");
        assert!(tool.joined.load(Ordering::SeqCst));
        assert_eq!(model_closed.load(Ordering::SeqCst), 1);

        match purpose {
            ClosePurpose::Delete => {
                close(&thread, purpose).await.unwrap();
                assert_eq!(store.admissions.load(Ordering::SeqCst), admissions);
                assert!(thread.snapshot().continuation.is_none());
            }
            ClosePurpose::Preserve => {
                assert!(
                    close(&thread, purpose).await.is_err(),
                    "save failure is retained"
                );
                assert!(store.admissions.load(Ordering::SeqCst) > admissions);
                assert!(thread.snapshot().continuation.is_some());
                store.fail_admit.store(false, Ordering::SeqCst);
                close(&thread, purpose).await.unwrap();
            }
        }
        assert_eq!(thread.snapshot().lifecycle, ThreadLifecycle::Closed);
        assert!(tool.close_attempts.load(Ordering::SeqCst) >= 2);
        assert_eq!(model_closed.load(Ordering::SeqCst), 1);
        assert!(matches!(
            close(&thread, purpose).await,
            Err(ThreadError::Closed)
        ));
    }

    #[tokio::test]
    async fn deletion_close_joins_background_and_retries_resources_without_final_save() {
        tokio::time::timeout(
            std::time::Duration::from_secs(10),
            exercise_close(ClosePurpose::Delete),
        )
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn preserving_close_joins_background_and_retains_final_save_failure() {
        tokio::time::timeout(
            std::time::Duration::from_secs(10),
            exercise_close(ClosePurpose::Preserve),
        )
        .await
        .unwrap();
    }

    struct ActiveModel {
        started: CancellationToken,
        call_dropped: Arc<AtomicBool>,
        closing: CancellationToken,
        release: CancellationToken,
        closed: Arc<AtomicBool>,
    }

    struct CallDrop(Arc<AtomicBool>);
    impl Drop for CallDrop {
        fn drop(&mut self) {
            self.0.store(true, Ordering::SeqCst);
        }
    }

    impl ModelSession for ActiveModel {
        async fn prepare(
            &mut self,
            request: ModelRequest,
        ) -> Result<PreparedModelCall, ModelError> {
            let started = self.started.clone();
            let dropped = self.call_dropped.clone();
            Ok(PreparedModelCall::new(async move {
                let _call = CallDrop(dropped);
                started.cancel();
                request.cancellation.cancelled().await;
                Err(ModelError {
                    context_recovery: None,
                    kind: crate::model::ModelFailureKind::Cancelled,
                    details: None,
                    usage: Box::default(),
                    source: None,
                })
            }))
        }

        async fn close(&mut self) -> Result<(), ModelError> {
            assert!(self.call_dropped.load(Ordering::SeqCst));
            self.closing.cancel();
            self.release.cancelled().await;
            self.closed.store(true, Ordering::SeqCst);
            Ok(())
        }
    }

    async fn exercise_active_turn_close(purpose: ClosePurpose) {
        let started = CancellationToken::new();
        let closing = CancellationToken::new();
        let release = CancellationToken::new();
        let call_dropped = Arc::new(AtomicBool::new(false));
        let model_closed = Arc::new(AtomicBool::new(false));
        let thread = ThreadHandle::start(
            "active-close".into(),
            DynModelSession::new(ActiveModel {
                started: started.clone(),
                call_dropped: call_dropped.clone(),
                closing: closing.clone(),
                release: release.clone(),
                closed: model_closed.clone(),
            }),
        )
        .unwrap();
        let store = Arc::new(SaveProbe::default());
        thread
            .attach_history(HistorySinkHandle::new(store.clone()))
            .await
            .unwrap();
        let running = {
            let thread = thread.clone();
            tokio::spawn(async move {
                thread
                    .run_turn(TurnInput {
                        turn_id: "still-running".into(),
                        attempt_prefix: "active-attempt".into(),
                        content: vec![ContextContent::Text {
                            text: "execute".into(),
                        }],
                        max_model_steps: ModelStepLimit::Limited(3.try_into().unwrap()),
                        cancellation: CancellationToken::new(),
                    })
                    .await
            })
        };
        started.cancelled().await;
        assert!(thread.snapshot().execution.is_some());
        let admissions = store.admissions.load(Ordering::SeqCst);
        store.fail_admit.store(true, Ordering::SeqCst);
        let mut closing_thread = Box::pin(close(&thread, purpose));
        tokio::select! {
            result = &mut closing_thread => panic!("close skipped model cleanup: {result:?}"),
            () = closing.cancelled() => {}
        }
        assert!(call_dropped.load(Ordering::SeqCst));
        assert!(!model_closed.load(Ordering::SeqCst));
        assert!(futures::poll!(&mut closing_thread).is_pending());
        assert!(matches!(
            running.await.unwrap(),
            Err(ThreadError::Cancelled)
        ));
        assert_eq!(
            thread.snapshot().continuation.is_some(),
            purpose == ClosePurpose::Preserve
        );
        release.cancel();
        let result = closing_thread.await;
        assert!(model_closed.load(Ordering::SeqCst));
        match purpose {
            ClosePurpose::Delete => {
                result.unwrap();
                assert_eq!(store.admissions.load(Ordering::SeqCst), admissions);
                assert!(thread.snapshot().continuation.is_none());
            }
            ClosePurpose::Preserve => {
                assert!(result.is_err());
                assert!(store.admissions.load(Ordering::SeqCst) > admissions);
                let continuation = thread.snapshot().continuation.clone().unwrap();
                assert_eq!(
                    continuation.reason,
                    Some(crate::thread::ContinuationReason::HostShutdown)
                );
                store.fail_admit.store(false, Ordering::SeqCst);
                thread.close().await.unwrap();
            }
        }
    }

    #[tokio::test]
    async fn deletion_close_cancels_active_model_without_recovery_or_final_flush() {
        tokio::time::timeout(
            std::time::Duration::from_secs(10),
            exercise_active_turn_close(ClosePurpose::Delete),
        )
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn preserving_close_cancels_active_model_with_host_shutdown_and_final_flush() {
        tokio::time::timeout(
            std::time::Duration::from_secs(10),
            exercise_active_turn_close(ClosePurpose::Preserve),
        )
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn deletion_seal_releases_an_existing_preservation_wait_without_confirming_it() {
        tokio::time::timeout(std::time::Duration::from_secs(10), async {
            let thread = ThreadHandle::start_current("blocked-flush".into(), None).unwrap();
            let store = Arc::new(SaveProbe {
                block_backpressure: AtomicBool::new(true),
                ..Default::default()
            });
            thread
                .attach_history(HistorySinkHandle::new(store.clone()))
                .await
                .unwrap();
            thread
                .submit_input(
                    ThreadInput {
                        id: "owed-before-flush".into(),
                        purpose: InputPurpose::Message,
                        payload: OpaquePayload::text("unsaved input"),
                        context: vec![ContextContent::Text {
                            text: "unsaved input".into(),
                        }],
                    },
                    None,
                )
                .await
                .unwrap();
            let admissions = store.admissions.load(Ordering::SeqCst);
            thread.prepare_close_for_deletion();
            thread.close_for_deletion().await.unwrap();
            assert_eq!(store.admissions.load(Ordering::SeqCst), admissions);
            assert_eq!(thread.snapshot().lifecycle, ThreadLifecycle::Closed);
        })
        .await
        .unwrap();
    }

    #[derive(Debug)]
    struct AdmissionRetryProbe {
        rejected: AtomicBool,
        admissions: AtomicUsize,
        durable: AtomicU64,
        changes: tokio::sync::watch::Sender<()>,
    }

    impl HistorySink for Arc<AdmissionRetryProbe> {
        fn fold_usage(&self, _: &mut UsageSummary, _: &crate::thread::ThreadEffectBatch) {}
        fn reserve_observed_item(&self, _: &str, _: &str, _: &str) -> Result<(), ColdStoreError> {
            Ok(())
        }
        fn reserve_operation_output(
            &self,
            _: &str,
            _: &str,
            max: u64,
        ) -> Result<u64, ColdStoreError> {
            Ok(max)
        }
        fn charge_operation_output(&self, _: &str, _: &str, _: u64) -> Result<(), ColdStoreError> {
            Ok(())
        }
        fn release_operation_output(&self, _: &str, _: &str) {}
        fn subscribe_pressure(&self, _: &str) -> Option<tokio::sync::watch::Receiver<()>> {
            Some(self.changes.subscribe())
        }
        fn admit(&self, _: &str, export: Arc<HistoryExport>) -> Result<(), ColdStoreError> {
            self.admissions.fetch_add(1, Ordering::SeqCst);
            if self.rejected.load(Ordering::SeqCst) {
                return Err(ColdStoreError {
                    source: Box::new(StorageAdmissionBackpressure("first batch delayed".into())),
                });
            }
            self.durable.store(export.effect.sequence, Ordering::SeqCst);
            Ok(())
        }
        fn pressure(&self, _: &str) -> StoragePressure {
            StoragePressure {
                durable_sequence: self.durable.load(Ordering::SeqCst),
                ..Default::default()
            }
        }
        fn idle_status(&self, thread_id: &str) -> StorageIdleStatus {
            StorageIdleStatus {
                pressure: self.pressure(thread_id),
                reclaimable_thread_bytes: Some(0),
            }
        }
    }

    async fn pressure_after_close_seal(purpose: ClosePurpose) {
        let thread = ThreadHandle::start_current("pressure-close-seal".into(), None).unwrap();
        let store = Arc::new(AdmissionRetryProbe {
            rejected: AtomicBool::new(true),
            admissions: AtomicUsize::new(0),
            durable: AtomicU64::new(0),
            changes: tokio::sync::watch::channel(()).0,
        });
        thread
            .attach_history(HistorySinkHandle::new(store.clone()))
            .await
            .unwrap();
        thread
            .submit_input(
                ThreadInput {
                    id: "rejected-batch".into(),
                    purpose: InputPurpose::Message,
                    payload: OpaquePayload::text("pending deletion"),
                    context: vec![],
                },
                None,
            )
            .await
            .unwrap();
        let before = thread.snapshot();
        let admissions = store.admissions.load(Ordering::SeqCst);
        assert!(
            admissions > 0,
            "the first batch must really have been offered"
        );
        let mut updates = thread.subscribe();
        let mut preserving_close = Box::pin(thread.close());
        match purpose {
            ClosePurpose::Delete => thread.prepare_close_for_deletion(),
            ClosePurpose::Preserve => assert!(futures::poll!(&mut preserving_close).is_pending()),
        }
        store.rejected.store(false, Ordering::SeqCst);
        store.changes.send_replace(());
        // Await the owner's real publication, rather than assuming a scheduler delay.
        loop {
            let update = updates.next().await.expect("pressure observation");
            if update.observation_revision > before.observation_revision {
                break;
            }
        }
        if purpose == ClosePurpose::Delete {
            assert_eq!(store.admissions.load(Ordering::SeqCst), admissions);
            assert_eq!(
                thread.snapshot().persistence.admitted_sequence,
                before.persistence.admitted_sequence
            );
            assert_eq!(store.durable.load(Ordering::SeqCst), 0);
            assert_eq!(
                thread.snapshot().persistence.durable_sequence,
                before.persistence.durable_sequence
            );
        } else {
            assert!(store.admissions.load(Ordering::SeqCst) > admissions);
            assert!(store.durable.load(Ordering::SeqCst) > 0);
        }
        match purpose {
            ClosePurpose::Delete => thread.close_for_deletion().await.unwrap(),
            ClosePurpose::Preserve => preserving_close.await.unwrap(),
        }
        if purpose == ClosePurpose::Delete {
            assert_eq!(store.admissions.load(Ordering::SeqCst), admissions);
            assert_eq!(store.durable.load(Ordering::SeqCst), 0);
        }
    }

    #[tokio::test]
    async fn deletion_pressure_seal_does_not_readmit_a_rejected_pending_batch() {
        tokio::time::timeout(
            std::time::Duration::from_secs(10),
            pressure_after_close_seal(ClosePurpose::Delete),
        )
        .await
        .unwrap();
    }

    #[tokio::test]
    async fn preserving_pressure_seal_still_retries_a_rejected_pending_batch() {
        tokio::time::timeout(
            std::time::Duration::from_secs(10),
            pressure_after_close_seal(ClosePurpose::Preserve),
        )
        .await
        .unwrap();
    }
}

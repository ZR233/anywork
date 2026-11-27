//! Execution decisions belong to the owner; futures own only the concrete I/O they perform.
use super::model_step::StepWork;
use super::*;
use futures::{FutureExt, future::BoxFuture};
use std::future::Future;

pub(super) struct PrimaryWork {
    pub(super) future: BoxFuture<'static, PrimaryCompletion>,
    pub(super) model_available: bool,
}
impl PrimaryWork {
    pub(super) fn new(
        model_available: bool,
        future: impl Future<Output = PrimaryCompletion> + Send + 'static,
    ) -> Self {
        Self {
            future: Box::pin(future),
            model_available,
        }
    }
}

pub(super) enum PrimaryCompletion {
    Preparation {
        step: StepWork,
        completion: context_preparation::PreparationCompletion,
        forced: bool,
    },
    PreparedModel {
        model: DynModelSession,
        step: StepWork,
        result: Result<crate::model::PreparedModelCall, ModelError>,
    },
    Model {
        model: DynModelSession,
        step: StepWork,
        exit: crate::model::ModelCallExit,
    },
    ExecutionsJoined(
        crate::tool::task::ExecutionTasks<super::tool_execution::ToolExecutionCompletion>,
    ),
    ClosedModel {
        model: DynModelSession,
        result: Result<(), ModelError>,
    },
    ClosedTools {
        tools: crate::tool::opaque::ToolManager,
        result: Result<(), crate::tool::opaque::ToolError>,
    },
}

pub(super) enum RunReply {
    Driver,
    Turn(oneshot::Sender<Result<TurnCompletion, ThreadError>>),
    Step(oneshot::Sender<Result<ModelStepOutput, ThreadError>>),
    Current(oneshot::Sender<Result<TurnCompletion, current::CurrentError>>),
    Compact(oneshot::Sender<Result<ContextSnapshot, ThreadError>>),
}

impl RunReply {
    pub(super) fn reject(self, error: ThreadError) {
        match self {
            Self::Driver => (),
            Self::Turn(reply) => {
                let _ = reply.send(Err(error));
            }
            Self::Step(reply) => {
                let _ = reply.send(Err(error));
            }
            Self::Current(reply) => {
                let _ = reply.send(Err(current::CurrentError::Owner(Arc::new(error))));
            }
            Self::Compact(reply) => {
                let _ = reply.send(Err(error));
            }
        }
    }
}

pub(super) enum RunPhase {
    Starting,
    NextStep {
        content: Vec<ContextContent>,
        retry_of: Option<String>,
    },
    Preparing,
    RequestReady(Box<StepWork>),
    ToolBatch(ToolBatch),
    Settling(Result<TurnCompletion, ThreadError>),
}

pub(super) struct ActiveRun {
    pub(super) input: TurnInput,
    pub(super) primary_input_id: Option<String>,
    pub(super) turn_cancel: CancellationToken,
    pub(super) step_preempt: CancellationToken,
    pub(super) preempt_triggers: Vec<String>,
    pub(super) current_step_inputs: Vec<String>,
    pub(super) reply: RunReply,
    pub(super) phase: RunPhase,
    pub(super) started: tokio::time::Instant,
    pub(super) steps: u32,
    pub(super) attempt_seq: u32,
    pub(super) next_attempt: Option<String>,
    pub(super) recovery_used: bool,
    pub(super) operation_id: Option<String>,
    pub(super) start_stops: u64,
    pub(super) restored: bool,
    // Own the cancellation installation until all primary work really returns.
    pub(super) _cancellation: cancellation::ActiveExecution,
}

impl ActiveRun {
    pub(super) fn is_turn_cancelled(&self, closing: bool) -> bool {
        closing || self.turn_cancel.is_cancelled()
    }

    pub(super) fn is_step_preempted(&self, closing: bool) -> bool {
        !closing
            && !self.turn_cancel.is_cancelled()
            && self.step_preempt.is_cancelled()
            && !self.preempt_triggers.is_empty()
    }

    pub(super) fn preempt_step(&mut self, trigger_input_id: &str) {
        if !self
            .preempt_triggers
            .iter()
            .any(|id| id == trigger_input_id)
        {
            self.preempt_triggers.push(trigger_input_id.to_owned());
        }
        self.step_preempt.cancel();
    }

    pub(super) fn reset_step_preempt(&mut self) -> Vec<String> {
        self.step_preempt = self.turn_cancel.child_token();
        std::mem::take(&mut self.preempt_triggers)
    }
}

pub(super) struct ToolBatch {
    pub(super) output: ModelStepOutput,
    pub(super) next: usize,
    pub(super) waiting: std::collections::BTreeSet<String>,
    pub(super) deadline: Option<tokio::time::Instant>,
    pub(super) foreground: bool,
    pub(super) control: Option<crate::tool::ToolControl>,
    pub(super) receipt_operation: Option<String>,
}

pub(super) struct ToolWaiter {
    pub(super) deadline: Option<tokio::time::Instant>,
    pub(super) reply: oneshot::Sender<Result<ToolDispatch, ThreadError>>,
}

pub(super) struct Closing {
    pub(super) purpose: owner::ClosePurpose,
    pub(super) reply: Option<oneshot::Sender<Result<(), ThreadError>>>,
    pub(super) stage: CloseStage,
}

#[derive(Clone, Copy)]
pub(super) enum CloseStage {
    Join,
    Model,
    Tools,
    Flush,
    Finish,
}

pub(super) enum MaintenanceCompletion {
    RuntimeModelOpened {
        generation: u64,
        result: Result<DynModelSession, ThreadError>,
    },
    RetiredRuntimeModel {
        model: DynModelSession,
        result: Result<(), ModelError>,
    },
    ModelSettlement {
        sequence: u64,
        result: Result<(), crate::model::ModelMemberError>,
        reply: oneshot::Sender<Result<(), crate::model::ModelMemberError>>,
    },
    RetireModelSettlement(String),
    OutputRetry {
        results: Vec<(
            String,
            u64,
            Result<cold::OutputRetryOutcome, cold::ColdStoreError>,
        )>,
        reply: oneshot::Sender<super::cold::OutputRetryReply>,
        finished: CancellationToken,
    },
}

impl Owner {
    pub(super) fn finish_maintenance(&mut self, completion: MaintenanceCompletion) {
        match completion {
            MaintenanceCompletion::RuntimeModelOpened { generation, result } => {
                self.finish_runtime_model_open(generation, result);
            }
            MaintenanceCompletion::RetiredRuntimeModel { model, result } => {
                self.finish_retired_runtime_model(model, result);
            }
            MaintenanceCompletion::OutputRetry {
                results,
                reply,
                finished,
            } => {
                let result = self.finish_output_retry(results);
                self.output_retry_active = None;
                let _ = reply.send(super::cold::OutputRetryReply::Finished(result));
                finished.cancel();
            }
            MaintenanceCompletion::ModelSettlement {
                sequence,
                result,
                reply,
            } => {
                self.model_settlement_jobs -= 1;
                if result.is_ok() {
                    self.confirm_flush(sequence);
                }
                let _ = reply.send(result);
            }
            MaintenanceCompletion::RetireModelSettlement(attempt) => {
                self.model_settlement_jobs -= 1;
                self.retire_model_settlement(&attempt);
            }
        }
    }

    pub(super) fn start_flush(&mut self, reply: oneshot::Sender<Result<(), ThreadError>>) {
        let result = self.check_flush_health();
        self.publish_snapshot();
        let _ = reply.send(result);
    }

    pub(super) fn fail_owner_work(&mut self, error: ThreadError) {
        if self.active.is_some() {
            self.settle_run(Err(error));
        } else if let Some(closing) = self.closing.take() {
            self.publish_snapshot();
            if let Some(reply) = closing.reply {
                let _ = reply.send(Err(error));
            } else {
                tracing::error!(thread = self.id, %error, "abandoned owner shutdown failed");
            }
        } else {
            self.driver.fail(Arc::new(error));
            self.pause_execution();
        }
    }

    pub(super) fn preempt_or_wake_active_run(
        &mut self,
        trigger_input_id: &str,
        reopen_settling: bool,
    ) {
        if self.interrupt.is_closing() || self.stopping_turn.is_some() {
            return;
        }
        let Some(run) = self.active.as_mut() else {
            return;
        };
        if run.is_turn_cancelled(false) {
            return;
        }
        match &run.phase {
            RunPhase::Preparing | RunPhase::RequestReady(_) => {
                run.preempt_step(trigger_input_id);
                self.publish_snapshot();
            }
            RunPhase::Settling(Ok(completion))
                if reopen_settling
                    && !matches!(run.reply, RunReply::Step(_))
                    && completion.outcome == TurnOutcome::Completed
                    && !matches!(
                        self.driver,
                        input::ExecutionDriver::Stopped | input::ExecutionDriver::Failed(_)
                    ) =>
            {
                run.phase = RunPhase::NextStep {
                    content: Vec::new(),
                    retry_of: None,
                };
                self.publish_snapshot();
            }
            RunPhase::Starting
            | RunPhase::NextStep { .. }
            | RunPhase::ToolBatch(_)
            | RunPhase::Settling(_) => {}
        }
    }

    fn soft_preempt_preparing_step(&mut self, step: StepWork) -> Result<(), ThreadError> {
        let mut run = self.active.take().ok_or(ThreadError::InvalidIdentity)?;
        let trigger_input_ids = run.reset_step_preempt();
        run.current_step_inputs.clear();
        let attempt_id = step.input.attempt_id.clone();
        self.pending_step_preemptions.push(StepPreemptionEvent {
            seq: self.state.commit_sequence.saturating_add(1),
            turn_id: run.input.turn_id.clone(),
            attempt_id: Some(attempt_id.clone()),
            phase: PreemptedStepPhase::Preparing,
            trigger_input_ids,
            partial_record_id: None,
        });
        run.phase = RunPhase::NextStep {
            content: step.input.content,
            retry_of: step.retry_of,
        };
        self.active = Some(run);
        self.finish_step(&attempt_id);
        self.publish()?;
        Ok(())
    }

    pub(super) fn schedule_step(
        &mut self,
        input: StepInput,
        retry_of: Option<String>,
        reply: RunReply,
    ) {
        if let Err(error) = self.validate_step_identity(&input) {
            reply.reject(error);
            return;
        }
        let turn = TurnInput {
            turn_id: input.turn_id.clone(),
            attempt_prefix: input.attempt_id.clone(),
            content: Vec::new(),
            max_model_steps: ModelStepLimit::Limited(std::num::NonZeroU32::new(1).unwrap()),
            cancellation: input.cancellation.clone(),
        };
        if let Err((error, reply)) = self.start_run(turn, reply, None) {
            reply.reject(error);
            return;
        }
        let run = self.active.as_mut().unwrap();
        run.next_attempt = Some(input.attempt_id);
        run.phase = RunPhase::NextStep {
            content: input.content,
            retry_of,
        };
    }

    pub(super) fn schedule_retry(
        &mut self,
        source: String,
        attempt: String,
        cancellation: CancellationToken,
        reply: oneshot::Sender<Result<ModelStepOutput, ThreadError>>,
    ) {
        let valid = self
            .state
            .attempts
            .last()
            .filter(|a| a.attempt_id == source);
        let Some(previous) = valid else {
            let _ = reply.send(Err(ThreadError::InvalidIdentity));
            return;
        };
        if !matches!(
            previous.status,
            AttemptStatus::Failed | AttemptStatus::Cancelled
        ) || previous.input_revision != self.state.context.revision
        {
            let _ = reply.send(Err(ThreadError::InvalidContext));
            return;
        }
        if !self
            .retry_plan
            .as_ref()
            .is_some_and(|(id, plan)| id == &source && plan.retry_compatible(&self.tools.freeze()))
        {
            let _ = reply.send(Err(ThreadError::InvalidContext));
            return;
        }
        self.schedule_step(
            StepInput {
                turn_id: previous.turn_id.clone(),
                attempt_id: attempt,
                content: Vec::new(),
                cancellation,
            },
            Some(source),
            RunReply::Step(reply),
        );
    }

    pub(super) fn schedule_compaction(
        &mut self,
        revision: u64,
        cancellation: CancellationToken,
        reply: oneshot::Sender<Result<ContextSnapshot, ThreadError>>,
    ) {
        let validation = self.ensure_idle().and_then(|()| {
            if revision == self.state.context.revision {
                Ok(())
            } else {
                Err(ThreadError::ContextConflict {
                    expected: revision,
                    actual: self.state.context.revision,
                })
            }
        });
        if let Err(error) = validation {
            let _ = reply.send(Err(error));
            return;
        }
        let turn_id = format!("compaction:{}", uuid::Uuid::new_v4());
        let input = TurnInput {
            turn_id: turn_id.clone(),
            attempt_prefix: turn_id,
            content: Vec::new(),
            max_model_steps: ModelStepLimit::Unlimited,
            cancellation,
        };
        if let Err((error, reply)) = self.start_run(input, RunReply::Compact(reply), None) {
            reply.reject(error);
            return;
        }
        let run = self.active.as_ref().unwrap();
        let step = StepInput {
            turn_id: run.input.turn_id.clone(),
            attempt_id: self.turn_attempt_identity(&run.input.attempt_prefix, 0),
            content: Vec::new(),
            cancellation: run.input.cancellation.clone(),
        };
        let result = self
            .freeze_step(step, self.tools.freeze(), None)
            .and_then(|step| self.start_preparing_step(step, true));
        if let Err(error) = result {
            self.fail_owner_work(error);
        }
    }

    pub(super) fn schedule_tool(
        &mut self,
        id: String,
        cancellation: CancellationToken,
        reply: oneshot::Sender<Result<ToolDispatch, ThreadError>>,
    ) {
        let foreground = self
            .pending
            .get(&id)
            .is_some_and(|call| call.executor.requires_foreground_execution());
        let result = (|| {
            if !self.storage_admission_ready() {
                return Err(ThreadError::StoragePressure);
            }
            self.try_reserve_operation_output(&super::tool_execution::tool_output_operation(&id))?;
            self.begin_tool_execution(id.clone(), cancellation)
        })();
        match result {
            Ok(execution) => {
                let deadline = (!foreground)
                    .then(|| tokio::time::Instant::now() + std::time::Duration::from_secs(1));
                self.tool_waiters.insert(id, ToolWaiter { deadline, reply });
                self.background.push(execution);
            }
            Err(error) => {
                let _ = reply.send(Err(error));
            }
        }
    }

    fn expire_tool_waiters(&mut self) -> Result<(), ThreadError> {
        let now = tokio::time::Instant::now();
        let expired: Vec<_> = self
            .tool_waiters
            .iter()
            .filter(|(_, waiter)| waiter.deadline.is_some_and(|d| d <= now))
            .map(|(id, _)| id.clone())
            .collect();
        for id in expired {
            let ToolWaiter { reply, .. } = self.tool_waiters.remove(&id).unwrap();
            let _ = reply.send(
                self.acknowledge_task(&id)
                    .map(|task| ToolDispatch::Running(Box::new(task))),
            );
        }
        Ok(())
    }

    pub(super) fn batch_deadline(&self) -> Option<tokio::time::Instant> {
        let batch = match self.active.as_ref().map(|r| &r.phase) {
            Some(RunPhase::ToolBatch(batch)) if !batch.waiting.is_empty() => batch.deadline,
            _ => None,
        };
        batch
            .into_iter()
            .chain(
                self.tool_waiters
                    .values()
                    .filter_map(|waiter| waiter.deadline),
            )
            .min()
    }

    fn dispatch_tool_batch(
        &mut self,
        batch: &mut ToolBatch,
        cancellation: &CancellationToken,
    ) -> Result<bool, ThreadError> {
        let expired = batch
            .deadline
            .is_some_and(|d| d <= tokio::time::Instant::now());
        if expired {
            // Already-admitted tasks keep their original window even when History is blocked.
            // Only new dispatch waits for storage; these funded local receipts retire the timer.
            for call in &batch.output.tool_calls[..batch.next] {
                if batch.waiting.remove(&call.call_id) {
                    self.acknowledge_task(&call.call_id)?;
                }
            }
        }
        if !self.storage_admission_ready() {
            return Ok(false);
        }
        if batch.receipt_operation.is_none() && !batch.output.tool_calls.is_empty() {
            let operation = format!("batch-receipts:{}", batch.output.attempt_id);
            let mut bytes = 0_u64;
            for call in &batch.output.tool_calls {
                let pending = self
                    .pending
                    .get(&call.call_id)
                    .ok_or(ThreadError::MissingCall)?;
                let receipt = task::TaskRecord {
                    id: format!("task:{}", call.call_id),
                    parent_call_id: None,
                    invocation: Some(call.clone()),
                    call_id: call.call_id.clone(),
                    tool_id: call.tool_id.clone(),
                    turn_id: pending.turn_id.clone(),
                    revision: u64::MAX,
                    status: task::TaskStatus::Running,
                    cancel_requested: false,
                    acknowledgement: Some(task::TaskAcknowledgement {
                        record_id: format!("task-receipt:{}", uuid::Uuid::max()),
                        context_revision: u64::MAX,
                    }),
                    started_sequence: Some(u64::MAX),
                };
                let running = crate::model::encoded_member_bytes(&receipt)
                    .map_err(|_| ThreadError::InvalidOutput)?;
                let (record, delivery) = super::tool_execution::capacity_result(pending, u64::MAX)?;
                let failure = crate::model::encoded_member_bytes(&(record, delivery))
                    .map_err(|_| ThreadError::InvalidOutput)?;
                bytes = bytes
                    .checked_add(running.max(failure).max(512))
                    .ok_or(ThreadError::RevisionExhausted)?;
            }
            let reservation = crate::model::OutputBudget::reserve(
                self.cold.clone(),
                &self.id,
                &operation,
                bytes,
                None,
            );
            let Ok(reservation) = reservation else {
                self.pause_for_output_capacity();
                return Ok(false);
            };
            if reservation.charge(bytes).is_err() {
                reservation.release();
                self.pause_for_output_capacity();
                return Ok(false);
            }
            self.operation_budgets
                .insert(operation.clone(), Arc::new(reservation));
            batch.receipt_operation = Some(operation);
            self.output_capacity_admitted();
        }
        if batch.control.is_some() {
            batch.next = batch.output.tool_calls.len();
            return Ok(false);
        }
        if batch.foreground && !batch.waiting.is_empty() {
            return Ok(false);
        }
        if batch.foreground {
            batch.foreground = false;
            batch.deadline = None;
        }
        for _ in 0..8 {
            let Some(call) = batch.output.tool_calls.get(batch.next) else {
                return Ok(false);
            };
            let foreground = self
                .pending
                .get(&call.call_id)
                .is_some_and(|p| p.executor.requires_foreground_execution());
            if foreground && !batch.waiting.is_empty() {
                return Ok(false);
            }
            let operation = super::tool_execution::tool_output_operation(&call.call_id);
            let execution = self.try_reserve_operation_output(&operation).and_then(|_| {
                self.begin_tool_execution(call.call_id.clone(), cancellation.clone())
            });
            let mut execution = match execution {
                Ok(execution) => execution,
                Err(ThreadError::StoragePressure) => {
                    self.finish_operation_output(&operation);
                    self.reject_tool_capacity(
                        &call.call_id,
                        batch
                            .receipt_operation
                            .as_deref()
                            .ok_or(ThreadError::InvalidIdentity)?,
                    )?;
                    batch.next += 1;
                    continue;
                }
                Err(error) => {
                    self.finish_operation_output(&operation);
                    return Err(error);
                }
            };
            // A completion already available after the segment deadline needs no Running receipt.
            if expired && let Some(completion) = (&mut execution).now_or_never() {
                let completion = self.commit_tool_execution(completion)?;
                if let Some(output) = completion.successful_output()
                    && output.control() != crate::tool::ToolControl::Continue
                {
                    batch.control = Some(output.control());
                }
                batch.next += 1;
                continue;
            }
            self.background.push(execution);
            batch.waiting.insert(call.call_id.clone());
            batch.next += 1;
            if foreground {
                batch.foreground = true;
                batch.deadline = None;
                return Ok(false);
            }
            batch.deadline.get_or_insert_with(|| {
                tokio::time::Instant::now() + std::time::Duration::from_secs(1)
            });
            if expired {
                self.acknowledge_task(&call.call_id)?;
                batch.waiting.remove(&call.call_id);
            }
        }
        Ok(batch.next < batch.output.tool_calls.len())
    }

    pub(super) fn begin_closing(
        &mut self,
        purpose: owner::ClosePurpose,
        reply: Option<oneshot::Sender<Result<(), ThreadError>>>,
    ) {
        if self.closing.is_some() {
            if let Some(reply) = reply {
                let _ = reply.send(Err(ThreadError::InputRequiresIdle));
            }
            return;
        }
        self.state.lifecycle = ThreadLifecycle::Closing;
        self.cancel_auxiliary_model_calls();
        self.reject_pending_bundle(ThreadError::Closed);
        self.retry_retired_runtime_models();
        if purpose == owner::ClosePurpose::Preserve && !self.interrupt.is_deleting() {
            self.form_host_shutdown();
        }
        self.executions.stop_admission();
        for id in self.executions.keys() {
            let _ = self.cancel_task(&id);
        }
        self.closing = Some(Closing {
            purpose,
            reply,
            stage: CloseStage::Join,
        });
        if purpose == owner::ClosePurpose::Delete || self.interrupt.is_deleting() {
            self.publish_snapshot();
        } else if let Err(error) = self.publish() {
            self.fail_owner_work(error);
        }
    }

    fn advance_close(&mut self) -> Result<bool, ThreadError> {
        if !self.background.is_empty() {
            return Ok(false);
        }
        let stage = self.closing.as_ref().unwrap().stage;
        match stage {
            CloseStage::Join => {
                if self.closing.as_ref().unwrap().purpose != owner::ClosePurpose::Delete
                    && !self.interrupt.is_deleting()
                {
                    self.cancel_pending_calls(None)?;
                }
                self.pending.clear();
                self.retry_plan = None;
                self.closing.as_mut().unwrap().stage = CloseStage::Model;
                let executions = std::mem::take(&mut self.executions);
                self.primary = Some(PrimaryWork::new(false, async move {
                    executions.join().await;
                    PrimaryCompletion::ExecutionsJoined(executions)
                }));
            }
            CloseStage::Model => {
                if self.runtime_model_jobs != 0 {
                    return Ok(false);
                }
                if let Some((_, error)) = self.retired_runtime_models.first() {
                    return Err(ThreadError::Model(error.clone()));
                }
                self.closing.as_mut().unwrap().stage = CloseStage::Tools;
                if let Some(mut model) = self.model.take() {
                    self.primary = Some(PrimaryWork::new(false, async move {
                        let result = model.close().await;
                        PrimaryCompletion::ClosedModel { model, result }
                    }));
                }
            }
            CloseStage::Tools => {
                self.closing.as_mut().unwrap().stage = CloseStage::Flush;
                let mut tools = std::mem::take(&mut self.tools);
                self.primary = Some(PrimaryWork::new(false, async move {
                    let result = tools.close().await;
                    PrimaryCompletion::ClosedTools { tools, result }
                }));
            }
            CloseStage::Flush => {
                let deleting = self.closing.as_ref().unwrap().purpose
                    == owner::ClosePurpose::Delete
                    || self.interrupt.is_deleting();
                // The original calls can still deliver incurred receipts while unwinding.
                // Wait for their retirement and save confirmations before the final fence.
                // Ordinary flush requests may await that fence themselves and must not block it.
                if !deleting && self.model_settlement_jobs != 0 {
                    return Ok(false);
                }
                if !deleting && self.cold.as_ref().is_some_and(|store| store.0.is_history()) {
                    self.refresh_storage_pressure();
                    self.check_model_settlements_saved()?;
                }
                self.resources = None;
                self.state.lifecycle = ThreadLifecycle::Closed;
                if deleting {
                    // All original producers have returned and resource cleanup has completed.
                    for (_, metadata) in std::mem::take(&mut self.task_metadata) {
                        metadata.release();
                    }
                    for (_, budget) in std::mem::take(&mut self.operation_budgets) {
                        budget.release();
                    }
                    self.publish_snapshot();
                    self.closing.as_mut().unwrap().stage = CloseStage::Finish;
                } else {
                    let publication = self.publish();
                    self.state.lifecycle = ThreadLifecycle::Closing;
                    self.publish_snapshot();
                    publication?;
                    match self.check_flush_health() {
                        Ok(()) => {
                            self.closing.as_mut().unwrap().stage = CloseStage::Finish;
                        }
                        Err(ThreadError::Storage(error))
                            if error.source.is::<cold::StorageAdmissionBackpressure>() =>
                        {
                            return Ok(false);
                        }
                        Err(error) => return Err(error),
                    }
                }
            }
            CloseStage::Finish => {
                if !self.maintenance.is_empty() {
                    return Ok(false);
                }
                self.state.lifecycle = ThreadLifecycle::Closed;
                self.publish_snapshot();
                self.handoff_final_current();
                if let Some(reply) = self.closing.take().and_then(|c| c.reply) {
                    let _ = reply.send(Ok(()));
                }
                return Ok(false);
            }
        }
        Ok(self.primary.is_none())
    }

    pub(super) fn start_run(
        &mut self,
        mut input: TurnInput,
        reply: RunReply,
        primary_input_id: Option<String>,
    ) -> Result<(), (ThreadError, RunReply)> {
        if self.active.is_some() || self.primary.is_some() {
            return Err((ThreadError::InputRequiresIdle, reply));
        }
        if self.current_saved_lifecycle.is_some() {
            return Err((ThreadError::CurrentPaused, reply));
        }
        if self.state.lifecycle != ThreadLifecycle::Open || self.interrupt.is_closing() {
            return Err((ThreadError::Closed, reply));
        }
        if input.turn_id.is_empty()
            || input.attempt_prefix.is_empty()
            || (!matches!(reply, RunReply::Step(_) | RunReply::Compact(_))
                && self.state.turns.iter().any(|t| t.turn_id == input.turn_id))
        {
            return Err((ThreadError::InvalidIdentity, reply));
        }
        let cancellation = self.interrupt.activate(&input.cancellation);
        let turn_cancel = cancellation.token.clone();
        let step_preempt = turn_cancel.child_token();
        input.cancellation = turn_cancel.clone();
        if let Err(error) = self.begin_execution() {
            return Err((error, reply));
        }
        let first = StepInput {
            turn_id: input.turn_id.clone(),
            attempt_id: self.turn_attempt_identity(&input.attempt_prefix, 0),
            content: input.content.clone(),
            cancellation: step_preempt.clone(),
        };
        self.begin_current_step(&first, &self.tools.freeze());
        self.active = Some(ActiveRun {
            input,
            primary_input_id,
            turn_cancel,
            step_preempt,
            preempt_triggers: Vec::new(),
            current_step_inputs: Vec::new(),
            reply,
            phase: RunPhase::Starting,
            started: tokio::time::Instant::now(),
            steps: 0,
            attempt_seq: 1,
            operation_id: None,
            start_stops: self.interrupt.stops(),
            restored: false,
            next_attempt: Some(first.attempt_id),
            recovery_used: false,
            _cancellation: cancellation,
        });
        Ok(())
    }

    /// Only bounded, local transitions run here. Returning true requests another fair loop tick.
    pub(super) fn start_ready_work(&mut self) -> Result<bool, ThreadError> {
        self.expire_tool_waiters()?;
        self.retire_revoked_runtime_tools()?;
        let pending_input_model = self.pending_input_model();
        self.install_ready_bundle();
        if self.primary.is_some() {
            return Ok(false);
        }
        if self
            .active
            .as_ref()
            .is_some_and(|r| r.is_turn_cancelled(self.interrupt.is_closing()))
        {
            let settling = matches!(
                self.active.as_ref().map(|r| &r.phase),
                Some(RunPhase::Settling(_))
            );
            if !settling {
                self.settle_run(Err(ThreadError::Cancelled));
            }
        }
        let Some(mut run) = self.active.take() else {
            if self.closing.is_some() {
                return self.advance_close();
            }
            return self.start_immediate_work();
        };
        let phase = std::mem::replace(&mut run.phase, RunPhase::Preparing);
        match phase {
            RunPhase::Starting => {
                // A model replacement can wait for open or old tool leases while the mailbox
                // accepts the next input. Keep that input at the turn boundary until installation.
                if matches!(run.reply, RunReply::Driver)
                    && let Some(model) = pending_input_model
                    && self.state.runtime_bundle.model_identity.as_ref() != Some(&model)
                {
                    if self.pending_input_model().is_some() {
                        run.phase = RunPhase::Starting;
                        self.active = Some(run);
                        return Ok(false);
                    }
                    self.active = Some(run);
                    self.settle_run(Err(ThreadError::StaleRuntimeBundle));
                    return Ok(true);
                }
                if !matches!(run.reply, RunReply::Step(_) | RunReply::Compact(_)) {
                    let mut turns = self.state.turns.to_vec();
                    turns.push(TurnRecord {
                        turn_id: run.input.turn_id.clone(),
                        input_id: run.primary_input_id.clone(),
                        state: TurnState::Running,
                        model_steps: 0,
                        elapsed_ms: None,
                    });
                    self.state.turns = turns.into();
                }
                self.enter_running_execution(&run.input.turn_id);
                let content = std::mem::take(&mut run.input.content);
                run.phase = RunPhase::NextStep {
                    content,
                    retry_of: None,
                };
                self.active = Some(run);
                self.publish()?;
                Ok(true)
            }
            RunPhase::NextStep { content, retry_of } => {
                if !self.storage_admission_ready() {
                    run.phase = RunPhase::NextStep { content, retry_of };
                    self.active = Some(run);
                    return Ok(false);
                }
                let attempt_id = if let Some(attempt_id) = run.next_attempt.take() {
                    attempt_id
                } else {
                    let attempt_seq = run.attempt_seq;
                    let Some(next_seq) = run.attempt_seq.checked_add(1) else {
                        self.active = Some(run);
                        return Err(ThreadError::RevisionExhausted);
                    };
                    run.attempt_seq = next_seq;
                    self.turn_attempt_identity(&run.input.attempt_prefix, attempt_seq)
                };
                let _ = run.reset_step_preempt();
                let input = StepInput {
                    turn_id: run.input.turn_id.clone(),
                    attempt_id,
                    content,
                    cancellation: run.step_preempt.clone(),
                };
                self.active = Some(run);
                let step = self.freeze_step(input, self.tools.freeze(), retry_of)?;
                self.start_preparing_step(step, false)?;
                Ok(self.primary.is_none())
            }
            RunPhase::RequestReady(step) => {
                if run.is_step_preempted(self.interrupt.is_closing()) {
                    self.active = Some(run);
                    self.soft_preempt_preparing_step(*step)?;
                    return Ok(true);
                }
                if !self.storage_admission_ready() {
                    run.phase = RunPhase::RequestReady(step);
                    self.active = Some(run);
                    return Ok(false);
                }
                let operation = step.input.attempt_id.clone();
                if self.try_reserve_operation_output(&operation).is_err() {
                    run.phase = RunPhase::RequestReady(step);
                    self.active = Some(run);
                    self.pause_for_output_capacity();
                    return Ok(false);
                }
                self.output_capacity_admitted();
                self.active = Some(run);
                let repair = step.recovery_error.clone();
                self.build_model_request(*step)
                    .map_err(|error| super::model_step::with_model_repair(repair, error))?;
                Ok(false)
            }
            RunPhase::ToolBatch(mut batch) => {
                let dispatch = self.dispatch_tool_batch(&mut batch, &run.input.cancellation);
                let more = match dispatch {
                    Ok(more) => more,
                    Err(error) => {
                        run.phase = RunPhase::ToolBatch(batch);
                        self.active = Some(run);
                        return Err(error);
                    }
                };
                if batch.waiting.is_empty() && batch.next == batch.output.tool_calls.len() {
                    if let Some(operation) = batch.receipt_operation.take() {
                        self.settle_operation_output(&operation);
                    }
                    let outcome = match batch.control {
                        Some(crate::tool::ToolControl::AwaitInteraction) => {
                            Some(TurnOutcome::WaitingInteraction)
                        }
                        Some(crate::tool::ToolControl::EndTurn) => Some(TurnOutcome::Completed),
                        _ if run.input.max_model_steps.reached(run.steps) => {
                            Some(TurnOutcome::StepLimit)
                        }
                        _ => None,
                    };
                    run.phase = match outcome {
                        Some(outcome) => RunPhase::Settling(Ok(TurnCompletion {
                            model_steps: run.steps,
                            outcome,
                            last_output: batch.output,
                        })),
                        None => RunPhase::NextStep {
                            content: Vec::new(),
                            retry_of: None,
                        },
                    };
                    self.active = Some(run);
                    Ok(true)
                } else {
                    run.phase = RunPhase::ToolBatch(batch);
                    self.active = Some(run);
                    Ok(more)
                }
            }
            RunPhase::Settling(result) => {
                if !matches!(run.reply, RunReply::Step(_))
                    && matches!(
                        &result,
                        Ok(completion) if completion.outcome == TurnOutcome::Completed
                    )
                    && !self.interrupt.is_closing()
                    && self.stopping_turn.is_none()
                    && !matches!(
                        self.driver,
                        input::ExecutionDriver::Stopped | input::ExecutionDriver::Failed(_)
                    )
                    && !run.input.max_model_steps.reached(run.steps)
                    && self.has_pending_immediate_inputs()
                    && !self.has_pending_model_switch()
                {
                    run.phase = RunPhase::NextStep {
                        content: Vec::new(),
                        retry_of: None,
                    };
                    self.active = Some(run);
                    return Ok(true);
                }
                if matches!(result, Err(ThreadError::Cancelled))
                    && self.state.tasks.values().any(|t| {
                        t.turn_id == run.input.turn_id && t.status == task::TaskStatus::Running
                    })
                {
                    run.phase = RunPhase::Settling(result);
                    self.active = Some(run);
                    return Ok(false);
                }
                self.finish_run(run, result)?;
                Ok(true)
            }
            RunPhase::Preparing => {
                self.active = Some(run);
                Ok(false)
            }
        }
    }

    fn stage_model_request(&mut self, step: StepWork) -> Result<(), ThreadError> {
        self.active
            .as_mut()
            .ok_or(ThreadError::InvalidIdentity)?
            .phase = RunPhase::RequestReady(Box::new(step));
        Ok(())
    }

    pub(super) fn start_preparing_step(
        &mut self,
        mut step: StepWork,
        forced: bool,
    ) -> Result<(), ThreadError> {
        self.apply_pending_runtime_facts()
            .map_err(|error| step.repair_failure(error))?;
        self.enter_model_execution(ModelExecutionPhase::PreparingContext);
        match self
            .start_context_preparation(
                &step.input,
                &mut step.plan,
                &step.frozen_input,
                forced,
                step.compaction_applied,
                if forced {
                    step.retry_of.as_deref()
                } else {
                    None
                },
            )
            .map_err(|error| step.repair_failure(error))?
        {
            Some(work) => {
                self.primary = Some(PrimaryWork::new(false, async move {
                    PrimaryCompletion::Preparation {
                        step,
                        completion: work.await,
                        forced,
                    }
                }));
                Ok(())
            }
            None if forced => Err(step.repair_failure(ThreadError::InvalidContext)),
            None => self.stage_model_request(step),
        }
    }

    pub(super) fn accept_primary(
        &mut self,
        completion: PrimaryCompletion,
    ) -> Result<(), ThreadError> {
        match completion {
            PrimaryCompletion::Preparation {
                mut step,
                completion,
                forced,
            } => {
                let has_compaction_candidate = completion.has_compaction_candidate();
                let result = self.finish_context_preparation(
                    &step.input,
                    &mut step.plan,
                    completion,
                    forced && step.recovery_error.is_some(),
                );
                if matches!(result, Err(ThreadError::Cancelled))
                    && !matches!(
                        self.active.as_ref().map(|r| &r.reply),
                        Some(RunReply::Compact(_))
                    )
                    && self
                        .active
                        .as_ref()
                        .is_some_and(|r| r.is_step_preempted(self.interrupt.is_closing()))
                {
                    self.soft_preempt_preparing_step(step)?;
                    return Ok(());
                }
                if !has_compaction_candidate
                    && step.preparation_refresh == 0
                    && matches!(
                        result,
                        Err(ThreadError::ContextConflict { .. }
                            | ThreadError::ExtensionConflict { .. })
                    )
                {
                    step.preparation_refresh += 1;
                    self.start_preparing_step(step, forced)?;
                } else {
                    let compacted = result.map_err(|error| step.repair_failure(error))?;
                    if forced && !compacted {
                        return Err(step.repair_failure(ThreadError::InvalidContext));
                    }
                    if forced && step.retry_of.is_some() {
                        step.retry_of = None;
                        step.compaction_applied = true;
                        self.start_preparing_step(step, false)?;
                        return Ok(());
                    }
                    if matches!(
                        self.active.as_ref().map(|r| &r.reply),
                        Some(RunReply::Compact(_))
                    ) {
                        let run = self.active.take().unwrap();
                        self.finish_step(&step.input.attempt_id);
                        self.finish_execution(&run.input.turn_id);
                        if let RunReply::Compact(reply) = run.reply {
                            let _ = reply.send(Ok(self.state.context.clone()));
                        }
                    } else if self
                        .active
                        .as_ref()
                        .is_some_and(|r| r.is_step_preempted(self.interrupt.is_closing()))
                    {
                        self.soft_preempt_preparing_step(step)?;
                    } else {
                        self.stage_model_request(step)?;
                    }
                }
            }
            PrimaryCompletion::PreparedModel {
                model,
                mut step,
                result,
            } => {
                self.model = Some(model);
                if self
                    .active
                    .as_ref()
                    .is_some_and(|r| r.is_step_preempted(self.interrupt.is_closing()))
                {
                    self.soft_preempt_preparing_step(step)?;
                    return Ok(());
                }
                if step.input.cancellation.is_cancelled() {
                    return Err(ThreadError::Cancelled);
                }
                match result {
                    Ok(prepared) => {
                        let primary = step.recovery_error.clone();
                        self.admit_prepared_model(step, prepared)
                            .map_err(|repair| {
                                super::model_step::with_model_repair(primary, repair)
                            })?;
                    }
                    Err(error)
                        if error.kind == crate::model::ModelFailureKind::ContextLimit
                            && self.active.as_ref().is_some_and(|r| !r.recovery_used) =>
                    {
                        // This preparation never reached dispatch. Release its unused call and
                        // output reservation before rebuilding the same pending step.
                        self.finish_step(&step.input.attempt_id);
                        self.active.as_mut().unwrap().recovery_used = true;
                        step.recovery_error = Some(Arc::new(error));
                        self.start_preparing_step(step, true)?;
                    }
                    Err(error) => {
                        self.finish_step(&step.input.attempt_id);
                        return Err(step.repair_failure(ThreadError::Model(Arc::new(error))));
                    }
                }
            }
            PrimaryCompletion::Model { model, step, exit } => {
                self.model = Some(model);
                let result = self.reduce_model_result(&step, exit);
                self.finish_step(&step.input.attempt_id);
                self.accept_step_result(step, result)?;
            }
            PrimaryCompletion::ExecutionsJoined(executions) => self.executions = executions,
            PrimaryCompletion::ClosedModel { model, result } => {
                if let Err(error) = result {
                    self.model = Some(model);
                    return Err(ThreadError::Model(Arc::new(error)));
                }
            }
            PrimaryCompletion::ClosedTools { tools, result } => {
                self.tools = tools;
                result.map_err(|error| ThreadError::Tool(Arc::new(error)))?;
            }
        }
        Ok(())
    }

    fn accept_step_result(
        &mut self,
        step: StepWork,
        result: Result<ModelStepOutput, ThreadError>,
    ) -> Result<(), ThreadError> {
        let mut run = self.active.take().ok_or(ThreadError::InvalidIdentity)?;
        if matches!(result, Err(ThreadError::Cancelled))
            && run.is_step_preempted(self.interrupt.is_closing())
        {
            let _ = run.reset_step_preempt();
            run.current_step_inputs.clear();
            run.phase = RunPhase::NextStep {
                content: Vec::new(),
                retry_of: None,
            };
            self.active = Some(run);
            return Ok(());
        }
        run.current_step_inputs.clear();
        let Some(steps) = run.steps.checked_add(1) else {
            self.active = Some(run);
            return Err(ThreadError::RevisionExhausted);
        };
        run.steps = steps;
        match result {
            Ok(output) => {
                if matches!(run.reply, RunReply::Step(_)) {
                    run.phase = RunPhase::Settling(Ok(TurnCompletion {
                        model_steps: run.steps,
                        outcome: TurnOutcome::Completed,
                        last_output: output,
                    }));
                } else if output.tool_calls.is_empty()
                    && output.turn_action == crate::model::ModelTurnAction::Finish
                {
                    if !run.input.max_model_steps.reached(run.steps)
                        && !matches!(
                            self.driver,
                            input::ExecutionDriver::Stopped | input::ExecutionDriver::Failed(_)
                        )
                        && self.has_pending_immediate_inputs()
                        && !self.has_pending_model_switch()
                    {
                        run.phase = RunPhase::NextStep {
                            content: Vec::new(),
                            retry_of: None,
                        };
                    } else {
                        run.phase = RunPhase::Settling(Ok(TurnCompletion {
                            model_steps: run.steps,
                            outcome: TurnOutcome::Completed,
                            last_output: output,
                        }));
                    }
                } else {
                    run.phase = RunPhase::ToolBatch(ToolBatch {
                        output,
                        next: 0,
                        waiting: Default::default(),
                        deadline: None,
                        foreground: false,
                        control: None,
                        receipt_operation: None,
                    });
                }
            }
            Err(ThreadError::ModelOutput(reason))
                if reason.is_correctable() && !run.input.max_model_steps.reached(run.steps) =>
            {
                run.phase = RunPhase::NextStep {
                    content: vec![ContextContent::Text {
                        text: Arc::from(reason.correction_feedback()),
                    }],
                    retry_of: Some(step.input.attempt_id),
                };
            }
            Err(ThreadError::Model(error))
                if error.kind == crate::model::ModelFailureKind::ContextLimit
                    && !run.recovery_used
                    && error.context_recovery.as_ref().is_some_and(|recovery| {
                        recovery.belongs_to(&self.id, &step.input.turn_id, &step.input.attempt_id)
                    })
                    && !run.input.max_model_steps.reached(run.steps) =>
            {
                run.recovery_used = true;
                let attempt_seq = run.attempt_seq;
                let Some(next_seq) = run.attempt_seq.checked_add(1) else {
                    self.active = Some(run);
                    return Err(ThreadError::RevisionExhausted);
                };
                run.attempt_seq = next_seq;
                let input = StepInput {
                    turn_id: run.input.turn_id.clone(),
                    attempt_id: self.turn_attempt_identity(&run.input.attempt_prefix, attempt_seq),
                    content: Vec::new(),
                    cancellation: run.step_preempt.clone(),
                };
                self.active = Some(run);
                let mut recovery = self
                    .freeze_step(input, self.tools.freeze(), Some(step.input.attempt_id))
                    .map_err(|repair| {
                        super::model_step::with_model_repair(Some(error.clone()), repair)
                    })?;
                recovery.recovery_error = Some(error);
                return self.start_preparing_step(recovery, true);
            }
            Err(error) => {
                let error = if step
                    .recovery_error
                    .as_ref()
                    .and_then(|error| error.context_recovery.as_ref())
                    .is_some_and(|grant| !grant.is_consumed())
                {
                    step.repair_failure(error)
                } else {
                    error
                };
                run.phase = RunPhase::Settling(Err(error));
            }
        }
        self.active = Some(run);
        Ok(())
    }

    pub(super) fn settle_run(&mut self, result: Result<TurnCompletion, ThreadError>) {
        if let Some(run) = self.active.as_mut() {
            run.phase = RunPhase::Settling(result);
        }
    }

    fn finish_run(
        &mut self,
        run: ActiveRun,
        result: Result<TurnCompletion, ThreadError>,
    ) -> Result<(), ThreadError> {
        let turn_id = &run.input.turn_id;
        if let Some(attempt_id) = self
            .current_call
            .as_ref()
            .map(|call| call.source_attempt_id.clone())
        {
            self.finish_step(&attempt_id);
        }
        if run.restored && result.is_err() {
            self.current_saved_lifecycle = Some(ThreadLifecycle::Open);
            self.pause_execution();
        }
        let result = if result.is_err() {
            match self.cancel_pending_calls(Some(turn_id)) {
                Ok(()) => result,
                Err(error) => Err(error),
            }
        } else {
            result
        };
        let mut turns = self.state.turns.to_vec();
        if let Some(turn) = turns.iter_mut().find(|t| &t.turn_id == turn_id) {
            turn.elapsed_ms = Some(
                run.started
                    .elapsed()
                    .as_millis()
                    .try_into()
                    .unwrap_or(u64::MAX),
            );
            turn.model_steps = run.steps;
            turn.state = match &result {
                Ok(completion) => TurnState::Finished(completion.outcome),
                Err(ThreadError::Cancelled) if self.stopping_turn.as_ref() == Some(turn_id) => {
                    TurnState::Interrupted
                }
                Err(ThreadError::Cancelled) => TurnState::Cancelled,
                Err(error) => super::turn::failed_turn(error),
            };
        }
        self.state.turns = turns.into();
        if let Some(reason) = self.turn_continuation_reason(&result) {
            self.form_continuation(reason, Some(turn_id.clone()), &format!("turn:{turn_id}"));
        }
        if let Some(id) = &run.operation_id
            && let Some(operation) = self
                .state
                .continuation_operations
                .iter_mut()
                .find(|op| &op.request.operation_id == id)
            && operation.disposition == ContinuationDisposition::Scheduled
        {
            operation.disposition =
                ContinuationDisposition::NotExecuted(if self.interrupt.is_closing() {
                    ContinuationNotExecuted::Closed
                } else if matches!(result, Err(ThreadError::Cancelled)) {
                    ContinuationNotExecuted::Stopped
                } else {
                    ContinuationNotExecuted::PreparationFailed
                });
        }
        self.output_backpressure = false;
        self.refresh_storage_pressure();
        let receipts: Vec<_> = self
            .operation_budgets
            .keys()
            .filter(|operation| operation.starts_with("batch-receipts:"))
            .cloned()
            .collect();
        for operation in receipts {
            self.settle_operation_output(&operation);
        }
        let cleared_execution = self.state.execution.as_ref().is_some_and(|execution| {
            execution.turn_id.is_none() || execution.turn_id.as_deref() == Some(turn_id)
        });
        self.finish_execution_with_emit(turn_id, false);
        self.finish_current_work_if_idle();
        let result = match self.publish() {
            Ok(()) => result,
            Err(error) => {
                self.publish_snapshot();
                Err(error)
            }
        };
        if cleared_execution {
            self.event_bus.emit(events::CoreEvent::Live(
                events::CoreLiveEvent::RunActivity { execution: None },
            ));
            self.publish_snapshot();
        }
        let was_stopping = self.stopping_turn.as_ref() == Some(&run.input.turn_id);
        match run.reply {
            RunReply::Driver => match result {
                Ok(TurnCompletion {
                    outcome: TurnOutcome::Completed,
                    ..
                }) => (),
                Err(ThreadError::Cancelled)
                    if self.driver.options().is_some()
                        && run.start_stops == self.interrupt.stops()
                        && was_stopping => {}
                Err(ThreadError::Cancelled) | Ok(_) => self.pause_execution(),
                Err(error) => {
                    self.driver.fail(Arc::new(error));
                    self.pause_execution();
                }
            },
            RunReply::Turn(reply) => {
                let _ = reply.send(result);
            }
            RunReply::Step(reply) => {
                let _ = reply.send(result.map(|r| r.last_output));
            }
            RunReply::Current(reply) => {
                let _ = reply.send(result.map_err(|e| current::CurrentError::Owner(Arc::new(e))));
            }
            RunReply::Compact(reply) => {
                let _ = reply.send(result.map(|_| self.state.context.clone()));
            }
        }
        if was_stopping
            && !self.state.tasks.values().any(|task| {
                task.turn_id == run.input.turn_id && task.status == task::TaskStatus::Running
            })
        {
            self.stopping_turn = None;
            self.publish_snapshot();
        }
        Ok(())
    }
}

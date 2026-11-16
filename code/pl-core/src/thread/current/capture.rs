//! Two-phase owner reads. Producer capture is awaited by the caller, not inside dispatch_mailbox.

use super::*;
use crate::model::CurrentCaptureHandle;
use crate::thread::cancellation::ActiveExecution;
use crate::thread::{
    Owner, StepInput, ThreadError, ThreadHandle, TurnInput, mailbox::MailboxCommand,
};

/// The sole owner-local resume authority. A spent claim stays bounded to one entry, so a refused
/// preparation cannot revive it after its attempt has left the resident journal. Saved current
/// data never creates this claim; only the authorized resume transition does.
pub(crate) struct CurrentResumeClaim {
    epoch: RuntimeEpoch,
    execution_id: String,
    turn_id: String,
    attempt_id: String,
    authorized_stops: u64,
    cancellation: CancellationToken,
    spent: bool,
    recovery: Option<SavedRecovery>,
}

struct SavedRecovery {
    attempt_id: String,
    call: Option<CurrentModelCall>,
    execution: Option<crate::thread::ActiveExecution>,
    lifecycle: ThreadLifecycle,
    dispatched: bool,
}

impl CurrentResumeClaim {
    fn new(request: &CurrentResumeRequest, recovery: SavedRecovery) -> Self {
        Self {
            epoch: request.runtime_epoch,
            execution_id: request.execution_id.clone(),
            turn_id: request.request.turn_id.clone(),
            attempt_id: request.request.attempt_id.clone(),
            authorized_stops: request.authorized_stops,
            cancellation: request.request.cancellation.clone(),
            spent: false,
            recovery: Some(recovery),
        }
    }

    fn is_live(&self, epoch: RuntimeEpoch, stops: u64) -> bool {
        !self.spent
            && self.epoch == epoch
            && self.authorized_stops == stops
            && !self.cancellation.is_cancelled()
    }
}

#[derive(Debug)]
pub(crate) struct CapturedStream {
    pub epoch: RuntimeEpoch,
    pub attempt_id: String,
    pub stream: Result<OpaquePayload, Arc<ModelError>>,
}

#[derive(Debug)]
pub(crate) enum CurrentRead {
    Complete(Box<ThreadCurrent>),
    Capture {
        epoch: RuntimeEpoch,
        attempt_id: String,
        handle: CurrentCaptureHandle,
    },
}

impl ThreadHandle {
    /// User-authorized local recovery under compare-and-swap. The synchronous validator must
    /// confirm the original provider/options; an incompatibility or concurrent input keeps paused.
    /// The returned request has fresh live cancellation and no old progress/resource handles.
    pub async fn prepare_current_resume(
        &self,
        turn_id: String,
        validate_parameters: impl FnOnce(Option<&OpaquePayload>) -> Result<(), ModelError>,
    ) -> Result<CurrentResumeRequest, CurrentError> {
        if turn_id.is_empty() {
            return Err(CurrentError::InvalidIdentity);
        }
        let (reply, response) = tokio::sync::oneshot::channel();
        self.mailbox
            .send(MailboxCommand::ReconcileCurrent { reply })
            .await
            .map_err(|_| CurrentError::Closed)?;
        let current = response.await.map_err(|_| CurrentError::Closed)??;
        let expected_revision = current.snapshot_revision;
        let identity = ExecutionIdentity::new(self.runtime_epoch, turn_id);
        validate_parameters(
            current
                .model_call
                .as_ref()
                .and_then(|call| call.prepared_parameters.as_ref()),
        )
        .map_err(|error| CurrentError::Model(Arc::new(error)))?;
        let (reply, response) = tokio::sync::oneshot::channel();
        self.mailbox
            .send(MailboxCommand::ResumeCurrent {
                expected_revision,
                identity,
                reply,
            })
            .await
            .map_err(|_| CurrentError::Closed)?;
        response.await.map_err(|_| CurrentError::Closed)?
    }

    /// The same UUIDv4 for every Turn and idle interval of this physical owner.
    pub fn runtime_epoch(&self) -> RuntimeEpoch {
        self.runtime_epoch
    }

    /// Clones a coherent logical current, with a complete producer snapshot if streaming.
    /// Revalidates epoch/attempt/phase after capture; stale responses never enter a current object.
    /// This operation has no persistence or history dependency.
    pub async fn capture_current(
        &self,
        cancellation: CancellationToken,
    ) -> Result<ThreadCurrent, CurrentError> {
        let mut captured = None;
        loop {
            if cancellation.is_cancelled() {
                return Err(CurrentError::Cancelled);
            }
            if let Some(result) = self.final_current.borrow().as_ref() {
                return result.clone().map_err(CurrentError::Final);
            }
            let (reply, response) = tokio::sync::oneshot::channel();
            tokio::select! {
                biased;
                () = cancellation.cancelled() => return Err(CurrentError::Cancelled),
                result = self.mailbox.send(MailboxCommand::ReadCurrent { captured: captured.take(), reply }) => {
                    if result.is_err() {
                        return self.final_current.borrow().as_ref().cloned()
                            .ok_or(CurrentError::Closed)?.map_err(CurrentError::Final);
                    }
                }
            }
            let read = tokio::select! {
                biased;
                () = cancellation.cancelled() => return Err(CurrentError::Cancelled),
                result = response => result.map_err(|_| CurrentError::Closed)??,
            };
            match read {
                CurrentRead::Complete(current) => return Ok(*current),
                CurrentRead::Capture {
                    epoch,
                    attempt_id,
                    handle,
                } => {
                    // The owner continues polling prepared.execute while this handle waits. In
                    // particular, mailbox dispatch never blocks the producer that must answer it.
                    let stream = handle
                        .capture(epoch, &attempt_id, cancellation.clone())
                        .await
                        .map_err(Arc::new);
                    captured = Some(CapturedStream {
                        epoch,
                        attempt_id,
                        stream,
                    });
                }
            }
        }
    }
}

impl Owner {
    pub(in crate::thread) fn current_recovery_parameters(
        &self,
        input: &StepInput,
    ) -> Option<OpaquePayload> {
        self.current_resume_claim
            .as_ref()
            .filter(|claim| claim.spent && claim.turn_id == input.turn_id)
            .and_then(|claim| claim.recovery.as_ref())
            .filter(|saved| saved.attempt_id == input.attempt_id)
            .and_then(|saved| saved.call.as_ref())
            .and_then(|call| call.prepared_parameters.clone())
    }

    pub(in crate::thread) fn note_current_recovery_dispatch(&mut self, input: &StepInput) {
        if let Some(saved) = self
            .current_resume_claim
            .as_mut()
            .filter(|claim| claim.turn_id == input.turn_id)
            .and_then(|claim| claim.recovery.as_mut())
            .filter(|saved| saved.attempt_id == input.attempt_id)
        {
            saved.dispatched = true;
        }
    }

    pub(in crate::thread) fn advance_current_recovery(&mut self, source: &str, next: &StepInput) {
        if let Some(saved) = self
            .current_resume_claim
            .as_mut()
            .filter(|claim| claim.turn_id == next.turn_id)
            .and_then(|claim| claim.recovery.as_mut())
            .filter(|saved| saved.attempt_id == source)
        {
            saved.attempt_id = next.attempt_id.clone();
        }
    }

    pub(in crate::thread) fn finish_current_recovery_step(
        &mut self,
        turn_id: &str,
        attempt_id: &str,
        result: &Result<crate::model::ModelStepOutput, ThreadError>,
    ) {
        let Some(claim) = self
            .current_resume_claim
            .as_mut()
            .filter(|claim| claim.turn_id == turn_id)
        else {
            return;
        };
        let retain = matches!(result, Err(ThreadError::Model(error))
            if matches!(error.kind, crate::model::ModelFailureKind::ContextLimit | crate::model::ModelFailureKind::IncompatibleContext));
        if claim
            .recovery
            .as_ref()
            .is_some_and(|saved| saved.attempt_id == attempt_id && saved.dispatched)
            && !retain
        {
            claim.recovery = None;
        }
    }

    pub(in crate::thread) fn pause_current_recovery(&mut self, turn_id: &str) {
        let Some(saved) = self
            .current_resume_claim
            .as_ref()
            .filter(|claim| claim.spent && claim.turn_id == turn_id)
            .and_then(|claim| claim.recovery.as_ref())
        else {
            return;
        };
        // Keep admitted input and concurrently arrived facts in RAM. Only the uncompleted model
        // binding returns to its saved material; a spent/cancelled claim is never rearmed.
        self.current_call = saved.call.clone();
        self.current_saved_execution = saved.execution.clone();
        self.current_saved_lifecycle = Some(saved.lifecycle);
        self.current_snapshot_missing = false;
        self.current_capture = None;
        self.current_updates = None;
        self.pause_inputs();
    }

    pub(in crate::thread) fn current_resume_stops(&self) -> Option<u64> {
        self.current_resume_claim
            .as_ref()
            .filter(|claim| claim.is_live(self.runtime_epoch, self.interrupt.stops()))
            .map(|claim| claim.authorized_stops)
    }

    pub(in crate::thread) fn accepts_current_resume(
        &self,
        epoch: RuntimeEpoch,
        execution_id: &str,
        turn_id: &str,
        attempt_id: &str,
        authorized_stops: u64,
    ) -> bool {
        self.current_resume_claim.as_ref().is_some_and(|claim| {
            claim.is_live(self.runtime_epoch, self.interrupt.stops())
                && claim.epoch == epoch
                && claim.execution_id == execution_id
                && claim.turn_id == turn_id
                && claim.attempt_id == attempt_id
                && claim.authorized_stops == authorized_stops
        })
    }

    /// Validates and spends authority before any wait or logical-current mutation. The returned
    /// execution is owned by the original qualification token, independent of a caller's new token.
    pub(in crate::thread) fn admit_current_step(
        &mut self,
        input: &StepInput,
    ) -> Result<Option<ActiveExecution>, ThreadError> {
        let pre_admitted = self.current_resume_stops().is_some();
        self.validate_step_identity(input, pre_admitted)?;
        let mut resumed = None;
        if let Some(claim) = &mut self.current_resume_claim {
            if !pre_admitted {
                if claim.attempt_id == input.attempt_id {
                    return Err(ThreadError::InvalidIdentity);
                }
                // A separately authorized fresh entry may replace a revoked preparation. No
                // running future owns this unspent claim; retire only its old live execution.
                if !claim.spent {
                    claim.spent = true;
                    if self
                        .state
                        .execution
                        .as_ref()
                        .is_some_and(|execution| execution.id == claim.execution_id)
                    {
                        self.state.execution = None;
                    }
                }
                claim.recovery = None;
            } else {
                if claim.turn_id != input.turn_id
                    || claim.attempt_id != input.attempt_id
                    || !input.content.is_empty()
                {
                    return Err(ThreadError::InvalidIdentity);
                }
                claim.spent = true;
                // A cancellation between validation and activation creates a cancelled child.
                // The stop comparison and installation retain InterruptHandle's atomic boundary.
                resumed = Some(
                    self.interrupt
                        .activate(&claim.cancellation, Some(claim.authorized_stops)),
                );
            }
        }
        Ok(resumed)
    }

    pub(in crate::thread) fn first_turn_attempt_identity(
        &self,
        input: &TurnInput,
    ) -> Result<String, ThreadError> {
        if let Some(claim) = &self.current_resume_claim {
            if claim.is_live(self.runtime_epoch, self.interrupt.stops()) {
                if input.attempt_prefix != claim.attempt_id {
                    return Err(ThreadError::InvalidIdentity);
                }
                return Ok(claim.attempt_id.clone());
            }
            if input.attempt_prefix == claim.attempt_id {
                return Err(ThreadError::InvalidIdentity);
            }
        }
        Ok(self.turn_attempt_identity(&input.attempt_prefix, 0))
    }

    fn install_current_business_state(
        &mut self,
        current: &ThreadCurrent,
        execution: Option<super::super::ActiveExecution>,
    ) -> Result<(), CurrentError> {
        let mut state = current.state.to_paused_snapshot();
        state.execution = execution;
        state.commit_sequence = self.state.commit_sequence;
        state.execution_sequence = self.state.execution_sequence;
        state.interaction_collection_revision = self
            .state
            .interaction_collection_revision
            .checked_add(u64::from(
                state.interactions != self.state.interactions
                    || state.permissions != self.state.permissions,
            ))
            .ok_or(CurrentError::RevisionExhausted)?;
        self.state = state;
        self.published = self.state.clone();
        self.current_call = current.model_call.clone();
        self.current_task_start_ordinal = Some(current.state.task_start_ordinal);
        self.current_retired_previews = current.state.tool_previews.clone();
        self.current_snapshot_missing = false;
        Ok(())
    }

    pub(in crate::thread) fn reconcile_current_for_resume(
        &mut self,
    ) -> Result<ThreadCurrent, CurrentError> {
        if self.current_saved_lifecycle.is_none() {
            return Err(CurrentError::NotPaused);
        }
        if self.interrupt.is_closing() {
            return Err(CurrentError::Closed);
        }
        let CurrentRead::Complete(mut current) = self.read_current(None)? else {
            return Err(CurrentError::NotPaused);
        };
        current.reconcile_saved_local_state()?;
        self.install_current_business_state(&current, None)?;
        self.publish_snapshot();
        current.check_model_waits()?;
        let CurrentRead::Complete(current) = self.read_current(None)? else {
            return Err(CurrentError::NotPaused);
        };
        Ok(*current)
    }

    pub(in crate::thread) fn turn_attempt_identity(&self, prefix: &str, step: u32) -> String {
        if self.current_task_start_ordinal.is_none() {
            return format!("{prefix}:{step}");
        }
        Uuid::new_v4().to_string()
    }

    pub(in crate::thread) fn resume_current_transition(
        &mut self,
        revision: u64,
        identity: ExecutionIdentity,
    ) -> Result<CurrentResumeRequest, CurrentError> {
        if self.current_saved_lifecycle.is_none() {
            return Err(CurrentError::NotPaused);
        }
        if self.interrupt.is_closing() {
            return Err(CurrentError::Closed);
        }
        if identity.runtime_epoch != self.runtime_epoch
            || revision != self.publish.borrow().observation_revision
        {
            return Err(CurrentError::StateConflict);
        }
        let plan = self.tools.freeze();
        let CurrentRead::Complete(mut current) = self.read_current(None)? else {
            return Err(CurrentError::NotPaused);
        };
        if let Some(call) = current.model_call.as_ref()
            && (call.tools != plan.declarations()
                || call.tool_call_mode != plan.call_mode()
                || call.solo_tool_ids != plan.solo_tool_ids())
        {
            return Err(CurrentError::IncompatibleTools);
        }
        let mut recovery = SavedRecovery {
            attempt_id: identity.attempt_id.clone(),
            call: current.model_call.clone(),
            execution: current.state.execution.clone(),
            lifecycle: current.state.lifecycle,
            dispatched: false,
        };
        let mut request = current.prepare_after_user_resume_with_catalog(
            identity,
            |_| Ok(()),
            Some((plan.declarations(), plan.call_mode(), plan.solo_tool_ids())),
        )?;
        // Direct input now belongs to confirmed context, including if model binding is refused.
        if let Some(call) = &mut recovery.call
            && let SavedModelPhase::Preparing { pending_step_input } = &mut call.phase
        {
            *pending_step_input = None;
        }
        request.authorized_stops = self.interrupt.stops();
        self.install_current_business_state(&current, current.state.execution.clone())?;
        self.current_saved_execution = None;
        self.current_saved_lifecycle = None;
        self.current_resume_claim = Some(CurrentResumeClaim::new(&request, recovery));
        self.publish_snapshot();
        Ok(request)
    }

    pub(in crate::thread) fn finish_current_work_if_idle(&mut self) {
        if !self.current_model_running
            && self.pending.is_empty()
            && self.uncommitted_tools.is_empty()
            && self.state.tasks.is_empty()
            && self.state.continuation.is_none()
            && self.state.turns.is_empty()
            && self.state.interactions.is_empty()
            && self.state.inbox.is_empty()
        {
            self.current_call = None;
            self.current_retired_previews.clear();
        }
    }

    pub(in crate::thread) fn begin_current_step(
        &mut self,
        input: &StepInput,
        plan: &crate::tool::opaque::ToolPlan,
    ) {
        if self
            .current_call
            .as_ref()
            .is_some_and(|call| call.source_attempt_id == input.attempt_id)
        {
            if self.active_inputs.is_empty()
                && !input.content.is_empty()
                && let Some(call) = &mut self.current_call
                && matches!(call.phase, SavedModelPhase::Preparing { .. })
            {
                call.phase = SavedModelPhase::Preparing {
                    pending_step_input: Some(PendingStepInput {
                        content: input.content.clone(),
                    }),
                };
            }
            return;
        }
        self.current_retired_previews
            .retain(|call, _| self.state.tasks.values().any(|task| task.call_id == *call));
        self.current_call = Some(CurrentModelCall {
            source_run_id: self.runtime_epoch,
            source_execution_id: self
                .state
                .execution
                .as_ref()
                .map(|execution| execution.id.clone())
                .unwrap_or_else(|| Uuid::new_v4().to_string()),
            source_turn_id: input.turn_id.clone(),
            source_attempt_id: input.attempt_id.clone(),
            tools: plan.declarations(),
            tool_call_mode: plan.call_mode(),
            solo_tool_ids: plan.solo_tool_ids(),
            prepared_parameters: None,
            phase: SavedModelPhase::Preparing {
                pending_step_input: (self.active_inputs.is_empty() && !input.content.is_empty())
                    .then(|| PendingStepInput {
                        content: input.content.clone(),
                    }),
            },
        });
        self.current_capture = None;
        self.current_updates = None;
        self.current_model_running = false;
        self.current_snapshot_missing = false;
        self.publish_snapshot();
    }

    pub(in crate::thread) fn read_current(
        &self,
        captured: Option<CapturedStream>,
    ) -> Result<CurrentRead, CurrentError> {
        let mut model_call = self.current_call.clone();
        if self.current_model_running {
            let call = model_call.as_mut().ok_or(CurrentError::MissingStream)?;
            let matching = captured.filter(|captured| {
                captured.epoch == self.runtime_epoch
                    && captured.attempt_id == call.source_attempt_id
            });
            if let Some(captured) = matching {
                call.phase = SavedModelPhase::Streaming {
                    stream: captured.stream.map_err(CurrentError::Model)?,
                };
            } else {
                return Ok(CurrentRead::Capture {
                    epoch: self.runtime_epoch,
                    attempt_id: call.source_attempt_id.clone(),
                    handle: self
                        .current_capture
                        .clone()
                        .ok_or(CurrentError::MissingStream)?,
                });
            }
        } else if self.current_snapshot_missing {
            return Err(CurrentError::MissingStream);
        }
        let mut state = ThreadCurrentState::from_snapshot(&self.state, self.runtime_epoch)?;
        if let Some(ordinal) = self.current_task_start_ordinal {
            state.tasks = self.state.tasks.clone();
            state.task_start_ordinal = ordinal;
        }
        if let Some(lifecycle) = self.current_saved_lifecycle {
            if self.state.lifecycle == ThreadLifecycle::Open {
                state.lifecycle = lifecycle;
            }
            state.execution = self.current_saved_execution.clone();
        }
        for (call_id, preview) in &self.current_retired_previews {
            state
                .tool_previews
                .entry(call_id.clone())
                .or_insert_with(|| preview.clone());
        }
        // A result can have finished while the old reliable commit is blocked. It is nevertheless
        // known current data and must never be downgraded to an unknown external operation.
        let mut deliveries = state.deliveries.to_vec();
        let mut next_message = state.inbox_sequence;
        for completion in self.uncommitted_tools.values() {
            let call = &completion.call;
            if deliveries
                .iter()
                .any(|delivery| delivery.call_id == call.call.call_id)
            {
                continue;
            }
            let (output, outcome) = if let Some(delivery) = &completion.pending_delivery {
                (delivery.output.clone(), delivery.outcome.clone())
            } else {
                let (mut output, mut outcome) =
                    super::super::tool_execution::observed_completion(completion);
                if completion.cancellation.is_cancelled() {
                    outcome = super::super::ToolOutcome::Cancelled;
                }
                super::super::tool_execution::annotate_failure_context(&mut output, &outcome);
                (output, outcome)
            };
            let mut delivered_context =
                super::super::tool_execution::model_delivery_context(&output, &outcome);
            let target = if let Some(parent_call_id) = &call.parent_call_id {
                ToolDeliveryTarget::Nested {
                    parent_call_id: parent_call_id.clone(),
                }
            } else if let Some(task) = state
                .tasks
                .get(&format!("task:{}", call.call.call_id))
                .filter(|task| task.acknowledgement.is_some())
            {
                next_message = next_message
                    .checked_add(1)
                    .ok_or(CurrentError::RevisionExhausted)?;
                delivered_context = super::super::background::result_context(
                    task,
                    task::TaskStatus::from_outcome(&outcome),
                    delivered_context,
                );
                ToolDeliveryTarget::Inbox {
                    message_id: format!("task-result:{next_message}"),
                }
            } else {
                ToolDeliveryTarget::CallResult
            };
            deliveries.push(ToolDelivery {
                target,
                call_id: call.call.call_id.clone(),
                tool_id: call.call.tool_id.clone(),
                output,
                delivered_context,
                outcome,
            });
        }
        state.deliveries = deliveries.into();
        let current = ThreadCurrent {
            schema_version: CURRENT_SCHEMA_VERSION,
            thread_id: self.id.clone(),
            saved_runtime_epoch: self.runtime_epoch,
            snapshot_revision: self.publish.borrow().observation_revision,
            saved_at: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .map_err(|_| CurrentError::ClockRange)?
                .as_millis()
                .try_into()
                .map_err(|_| CurrentError::ClockRange)?,
            state,
            model_call,
        };
        Ok(CurrentRead::Complete(Box::new(current)))
    }

    pub(in crate::thread) fn handoff_final_current(&self) {
        let result = match self.read_current(None) {
            Ok(CurrentRead::Complete(current)) => Ok(*current),
            Ok(CurrentRead::Capture { .. }) => Err(Arc::new(CurrentError::MissingStream)),
            Err(error) => Err(Arc::new(error)),
        };
        self.final_current.send_replace(Some(result));
    }
}

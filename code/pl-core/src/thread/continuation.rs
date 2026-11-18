//! Resume is a one-shot owner control, independent of user inputs and History durability.
use super::*;

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResumeRequest {
    pub operation_id: String,
    pub expected_continuation_token: String,
    #[serde(default)]
    pub request_digest: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase", tag = "kind", content = "reason")]
pub enum ContinuationDisposition {
    Scheduled,
    Effective,
    NotExecuted(ContinuationNotExecuted),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ContinuationNotExecuted {
    Stopped,
    PreparationFailed,
    RestoredPaused,
    Closed,
}

#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContinuationOperation {
    pub request: ResumeRequest,
    pub acceptance_epoch: current::RuntimeEpoch,
    pub execution_id: String,
    pub turn_id: String,
    pub accepted_revision: u64,
    pub disposition: ContinuationDisposition,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ContinuationRead {
    Known(ContinuationOperation),
    NotAccepted,
}

impl Owner {
    pub(super) fn read_resume(
        &self,
        request: &ResumeRequest,
    ) -> Result<ContinuationRead, ThreadError> {
        if let Some(operation) = self
            .state
            .continuation_operations
            .iter()
            .find(|op| op.request.operation_id == request.operation_id)
        {
            if operation.request.expected_continuation_token != request.expected_continuation_token
                || request
                    .request_digest
                    .as_ref()
                    .is_some_and(|digest| operation.request.request_digest.as_ref() != Some(digest))
            {
                return Err(ThreadError::InvalidIdentity);
            }
            return Ok(ContinuationRead::Known(operation.clone()));
        }
        if self
            .state
            .continuation
            .as_ref()
            .is_some_and(|point| point.id == request.expected_continuation_token)
        {
            Ok(ContinuationRead::NotAccepted)
        } else {
            Err(ThreadError::StaleContinuation)
        }
    }

    pub(super) fn resume(
        &mut self,
        request: ResumeRequest,
        options: input::InputDriverOptions,
    ) -> Result<ContinuationOperation, ThreadError> {
        if request.operation_id.is_empty() {
            return Err(ThreadError::InvalidIdentity);
        }
        match self.read_resume(&request)? {
            ContinuationRead::Known(operation) => {
                if operation.request != request {
                    return Err(ThreadError::InvalidIdentity);
                }
                return Ok(operation);
            }
            ContinuationRead::NotAccepted => (),
        }
        self.validate_continuation_admission()?;
        if self.active.is_some()
            || self.primary.is_some()
            || self.state.tasks.values().any(|t| {
                t.status == task::TaskStatus::Running
                    && self
                        .executions
                        .token(&t.id)
                        .is_some_and(|token| token.is_cancelled())
            })
        {
            return Err(ThreadError::InputRequiresIdle);
        }
        let turn_id = uuid::Uuid::new_v4().to_string();
        let mut input = TurnInput {
            turn_id: turn_id.clone(),
            attempt_prefix: turn_id.clone(),
            content: Vec::new(),
            max_model_steps: options.max_model_steps,
            cancellation: CancellationToken::new(),
        };
        let restored = self.current_saved_lifecycle.is_some();
        if restored {
            input = self
                .prepare_current_resume(self.runtime_epoch, self.interrupt.stops(), input)
                .map_err(|e| ThreadError::CurrentResume(Arc::new(e)))?;
        } else {
            input.content = self.freeze_next_input_batch().unwrap_or_default();
        }
        let accepted_revision = self
            .state
            .commit_sequence
            .checked_add(1)
            .ok_or(ThreadError::RevisionExhausted)?;
        self.policy.enable(options);
        self.start_run(input, super::execution::RunReply::Driver)
            .map_err(|(error, _)| error)?;
        let execution_id = self
            .state
            .execution
            .as_ref()
            .ok_or(ThreadError::InvalidIdentity)?
            .id
            .clone();
        let operation = ContinuationOperation {
            request,
            acceptance_epoch: self.runtime_epoch,
            execution_id,
            turn_id,
            accepted_revision,
            disposition: ContinuationDisposition::Scheduled,
        };
        self.active.as_mut().unwrap().restored = restored;
        self.active.as_mut().unwrap().operation_id = Some(operation.request.operation_id.clone());
        self.state.continuation = None;
        self.state
            .continuation_operations
            .push_back(operation.clone());
        while self.state.continuation_operations.len() > 64 {
            self.state.continuation_operations.pop_front();
        }
        self.publish()?;
        Ok(operation)
    }

    pub(super) fn mark_resume_effective(&mut self) {
        let Some(id) = self.active.as_ref().and_then(|r| r.operation_id.as_ref()) else {
            return;
        };
        if let Some(operation) = self
            .state
            .continuation_operations
            .iter_mut()
            .find(|op| &op.request.operation_id == id)
        {
            operation.disposition = ContinuationDisposition::Effective;
        }
    }

    pub(super) fn continue_input(
        &mut self,
        input: input::ThreadInput,
        options: input::InputDriverOptions,
    ) -> Result<input::InputRecord, ThreadError> {
        if let Some(receipt) = input::duplicate_input_receipt(&self.state, &input)? {
            return Ok(receipt);
        }
        self.validate_continuation_admission()?;
        let record = self.accept_input_with_policy(input, input::InputPolicy::StartOrQueue)?;
        self.input_batch_through = Some(record.ordinal);
        self.request_continuation(options);
        Ok(record)
    }

    pub(super) fn continue_message(
        &mut self,
        message: inbox::ThreadMessage,
        options: input::InputDriverOptions,
        receipt: Option<&str>,
    ) -> Result<u64, ThreadError> {
        if let Some(id) = receipt
            && let Some(saved) = inbox::message_receipt(&self.state, id, &message)?
        {
            return Ok(saved.sequence);
        }
        if let Some(sequence) = self.accepted_message_receipt(&message)? {
            return Ok(sequence);
        }
        self.validate_continuation_admission()?;
        let sequence = self.receive_message(message, Some(options), receipt)?;
        self.request_continuation(options);
        Ok(sequence)
    }

    fn validate_continuation_admission(&mut self) -> Result<(), ThreadError> {
        if self.state.lifecycle != ThreadLifecycle::Open || self.interrupt.is_closing() {
            return Err(ThreadError::Closed);
        }
        if self
            .state
            .interactions
            .values()
            .any(|record| record.state == interactions::InteractionState::Pending)
            || self
                .state
                .permissions
                .values()
                .any(|record| record.state == permissions::PermissionState::Pending)
        {
            return Err(ThreadError::PendingInteraction);
        }
        self.refresh_storage_pressure();
        if self.state.persistence.pressure_paused {
            return Err(ThreadError::StoragePressure);
        }
        if let Some(error) = &self.cold_error {
            return Err(ThreadError::Storage(error.clone()));
        }
        Ok(())
    }

    pub(super) fn form_continuation(
        &mut self,
        reason: ContinuationReason,
        source_turn_id: Option<String>,
        source: &str,
    ) {
        if self
            .state
            .continuation
            .as_ref()
            .is_some_and(|p| p.same_fact(source_turn_id.as_deref(), Some(reason)))
        {
            return;
        }
        let mut point = ContinuationPoint::new(
            self.state.commit_sequence,
            source,
            source_turn_id,
            Some(reason),
        );
        point.id = uuid::Uuid::new_v4().to_string();
        self.state.continuation = Some(point);
    }

    fn request_continuation(&mut self, options: input::InputDriverOptions) {
        self.policy.enable(options);
        if let Some(run) = &self.active {
            let turn_id = run.input.turn_id.clone();
            self.interrupted_turn = Some(turn_id.clone());
            if let Err(error) = self.cancel_turn_tasks(&turn_id) {
                self.policy.fail(Arc::new(error));
            }
            if let Some(run) = self.active.as_ref() {
                run.input.cancellation.cancel();
            }
        }
        self.publish_snapshot();
    }

    pub(super) fn cancel_turn_tasks(&mut self, turn_id: &str) -> Result<(), ThreadError> {
        let tasks: Vec<_> = self
            .state
            .tasks
            .values()
            .filter(|task| task.turn_id == turn_id && task.status == task::TaskStatus::Running)
            .map(|task| task.id.clone())
            .collect();
        for task in tasks {
            self.cancel_task(&task)?;
        }
        Ok(())
    }

    /// Wait in the owner loop for physical task completion, servicing the mailbox throughout.
    pub(super) fn continuation_ready(&mut self) -> bool {
        let Some(turn_id) = &self.interrupted_turn else {
            return true;
        };
        if self
            .state
            .turns
            .iter()
            .any(|turn| &turn.turn_id == turn_id && turn.state == TurnState::Running)
            || self
                .state
                .tasks
                .values()
                .any(|task| &task.turn_id == turn_id && task.status == task::TaskStatus::Running)
        {
            return false;
        }
        self.interrupted_turn = None;
        self.publish_snapshot();
        true
    }

    pub(super) fn driveable(&self, record: &input::InputRecord) -> bool {
        record.state == input::InputState::Pending
            && record.input.purpose == input::InputPurpose::Message
    }
}

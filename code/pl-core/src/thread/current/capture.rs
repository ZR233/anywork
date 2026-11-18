//! Two-phase owner reads. Producer capture is awaited by the caller, not inside dispatch_mailbox.

use super::*;
use crate::model::CurrentCaptureHandle;
use crate::thread::{Owner, StepInput, ThreadHandle, TurnInput, mailbox::MailboxCommand};

#[derive(Debug)]
pub(crate) struct CapturedStream {
    pub epoch: RuntimeEpoch,
    pub attempt_id: String,
    pub handle: CurrentCaptureHandle,
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
    /// The same UUIDv4 for every Turn and idle interval of this physical owner.
    pub fn runtime_epoch(&self) -> RuntimeEpoch {
        self.runtime_epoch
    }

    /// Small coalescing save notifications, independent of UI snapshot delivery.
    pub fn subscribe_current_dirty(&self) -> tokio::sync::watch::Receiver<u64> {
        self.current_dirty.clone()
    }

    /// Clones a coherent logical current, with a complete producer snapshot if streaming.
    /// Revalidates epoch/attempt/phase after capture; stale responses never enter a current object.
    /// This operation has no persistence or history dependency.
    pub async fn capture_current(
        &self,
        cancellation: CancellationToken,
    ) -> Result<ThreadCurrent, CurrentError> {
        let started = std::time::Instant::now();
        let mut producer_captures = 0usize;
        let result = tokio::time::timeout(
            std::time::Duration::from_secs(1),
            self.capture_current_within_deadline(cancellation, &mut producer_captures),
        )
        .await
        .map_err(|_| CurrentError::CaptureTimedOut)
        .and_then(std::convert::identity);
        tracing::debug!(
            target: "current_work",
            runtime_epoch = %self.runtime_epoch,
            current_capture_ms = started.elapsed().as_secs_f64() * 1000.0,
            current_capture_producer_requests = producer_captures,
            current_capture_stale_retries = producer_captures.saturating_sub(1),
            success = result.is_ok(),
            "current capture finished"
        );
        result
    }

    async fn capture_current_within_deadline(
        &self,
        cancellation: CancellationToken,
        producer_captures: &mut usize,
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
                result = self.commands.send(crate::thread::Command::Control(MailboxCommand::ReadCurrent { captured: captured.take(), reply })) => {
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
                    *producer_captures += 1;
                    // The owner continues polling prepared.execute while this handle waits. In
                    // particular, mailbox dispatch never blocks the producer that must answer it.
                    let stream = handle
                        .capture(epoch, &attempt_id, cancellation.clone())
                        .await
                        .map_err(Arc::new);
                    captured = Some(CapturedStream {
                        epoch,
                        attempt_id,
                        handle,
                        stream,
                    });
                }
            }
        }
    }
}

impl Owner {
    fn install_current_business_state(
        &mut self,
        current: &ThreadCurrent,
    ) -> Result<(), CurrentError> {
        let mut state = current.state.to_paused_snapshot();
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

    pub(in crate::thread) fn turn_attempt_identity(&self, prefix: &str, step: u32) -> String {
        if self.current_task_start_ordinal.is_none() {
            return format!("{prefix}:{step}");
        }
        Uuid::new_v4().to_string()
    }

    /// Reconcile local facts once, then use the normal Turn and model preparation path.
    pub(in crate::thread) fn prepare_current_resume(
        &mut self,
        epoch: RuntimeEpoch,
        expected_stop_generation: u64,
        mut input: TurnInput,
    ) -> Result<TurnInput, CurrentError> {
        if epoch != self.runtime_epoch || input.turn_id.is_empty() {
            return Err(CurrentError::InvalidIdentity);
        }
        if self.current_saved_lifecycle.is_none() {
            return Err(CurrentError::NotPaused);
        }
        if self.interrupt.is_closing() {
            return Err(CurrentError::Closed);
        }
        if input.cancellation.is_cancelled() || expected_stop_generation != self.interrupt.stops() {
            return Err(CurrentError::Cancelled);
        }
        if self
            .state
            .turns
            .iter()
            .any(|turn| turn.turn_id == input.turn_id)
        {
            return Err(CurrentError::InvalidIdentity);
        }
        let CurrentRead::Complete(mut current) = self.read_current(None)? else {
            return Err(CurrentError::NotPaused);
        };
        current.reconcile_saved_local_state()?;
        self.install_current_business_state(&current)?;
        self.publish_snapshot();
        current.check_model_waits()?;
        let direct = current
            .model_call
            .as_ref()
            .and_then(|call| match &call.phase {
                SavedModelPhase::Preparing {
                    pending_step_input: Some(pending),
                } => Some(pending.content.clone()),
                _ => None,
            });
        input.content = direct.unwrap_or_default();
        if let Some(content) = self.freeze_next_input_batch() {
            input.content.extend(content);
        }
        self.current_saved_execution = None;
        self.current_saved_lifecycle = None;
        Ok(input)
    }

    pub(in crate::thread) fn finish_current_work_if_idle(&mut self) {
        if !self.current_model_running
            && self.pending.is_empty()
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
        // Frozen queue records retain their own content until admission. Only the prefix that is
        // not owned by those records must be saved with the preparing call.
        let queued_content_len: usize = self
            .active_inputs
            .iter()
            .filter_map(|id| {
                self.state
                    .inputs
                    .iter()
                    .find(|record| &record.input.id == id)
            })
            .map(|record| record.input.context.len())
            .sum();
        let direct_len = input.content.len().saturating_sub(queued_content_len);
        let pending_step_input =
            (!input.content[..direct_len].is_empty()).then(|| PendingStepInput {
                content: input.content[..direct_len].to_vec(),
            });
        if self
            .current_call
            .as_ref()
            .is_some_and(|call| call.source_attempt_id == input.attempt_id)
        {
            if pending_step_input.is_some()
                && let Some(call) = &mut self.current_call
                && matches!(call.phase, SavedModelPhase::Preparing { .. })
            {
                call.phase = SavedModelPhase::Preparing { pending_step_input };
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
            phase: SavedModelPhase::Preparing { pending_step_input },
        });
        self.current_capture = None;
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
                    && self
                        .current_capture
                        .as_ref()
                        .is_some_and(|handle| handle.same_endpoint(&captured.handle))
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
        let current = ThreadCurrent {
            schema_version: CURRENT_SCHEMA_VERSION,
            thread_id: self.id.clone(),
            saved_runtime_epoch: self.runtime_epoch,
            snapshot_revision: *self.current_dirty.borrow(),
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

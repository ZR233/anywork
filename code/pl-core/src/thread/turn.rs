//! One Turn's model/tool loop, executed entirely inside the Thread owner.
use super::*;

impl Owner {
    pub(super) async fn run_turn(
        &mut self,
        input: TurnInput,
    ) -> Result<TurnCompletion, ThreadError> {
        let turn_id = input.turn_id.clone();
        let mut admission = None;
        let result = self.execute_turn(input, &mut admission).await;
        // A Turn that ended before it ever created its record (a stop during preparation) still has to
        // settle the batch it froze: a body-less control it never consumed was replaced meanwhile and
        // must not linger as phantom owed work. The normal path settles inside its own terminal commit.
        if !self.state.turns.iter().any(|turn| turn.turn_id == turn_id) {
            if let Err(error) = self.settle_replaced_controls() {
                self.input_driver.fail(Arc::new(error));
                self.pause_inputs();
            }
        }
        // execute_turn has returned after asynchronous cancellation cleanup. Release the execution
        // with the terminal facts in one persisted commit, never in a later snapshot-only update.
        // Keep its admission permit until that commit too: a host draining the gate must not see
        // zero admitted Turns while their terminal facts are still uncommitted. A preparing exit
        // without a Turn takes this same boundary; its accepted continuation remains a logical fact.
        self.finish_execution(&turn_id);
        self.publish();
        drop(admission);
        result
    }

    async fn execute_turn(
        &mut self,
        input: TurnInput,
        admission: &mut Option<admission::TurnAdmissionPermit>,
    ) -> Result<TurnCompletion, ThreadError> {
        if self.state.lifecycle != ThreadLifecycle::Open {
            return Err(ThreadError::Closed);
        }
        if input.turn_id.is_empty()
            || input.attempt_prefix.is_empty()
            || self
                .state
                .turns
                .iter()
                .any(|turn| turn.turn_id == input.turn_id)
        {
            return Err(ThreadError::InvalidIdentity);
        }
        if input.cancellation.is_cancelled() {
            return Err(ThreadError::Cancelled);
        }
        // A direct Turn reaches this point without the queue driver, so the execution identity is
        // allocated here when nobody did it yet. A driver-started Turn keeps the generation the
        // driver already published.
        self.begin_execution()?;
        // The Turn admission gate is the one place new Turns are held back, and it is checked before
        // this Turn owns anything: while the owner waits here no Turn record exists and no input is
        // consumed, so a held Turn leaves the queue exactly as it found it.
        *admission = Some(self.await_turn_admission(&input.cancellation).await?);
        let started = tokio::time::Instant::now();
        let turn_id = input.turn_id.clone();
        let mut turns = self.state.turns.to_vec();
        turns.push(TurnRecord {
            elapsed_ms: None,
            input_id: self.active_inputs.first().cloned(),
            turn_id: turn_id.clone(),
            state: TurnState::Running,
            model_steps: 0,
        });
        self.state.turns = turns.clone().into();
        self.enter_running_execution(&turn_id);
        self.publish();
        // Publish the generation before any asynchronous preparation: input received while a
        // model is being opened must redirect this Turn, not silently queue behind it.
        let mut result = async {
            self.apply_model_update().await?;
            if input.cancellation.is_cancelled() || self.interrupt.is_closing() {
                return Err(ThreadError::Cancelled);
            }
            self.execute_turn_loop(input).await
        }
        .await;
        if matches!(result, Err(ThreadError::Closed)) && self.interrupt.is_closing() {
            result = Err(ThreadError::Cancelled);
        }
        if matches!(result, Err(ThreadError::Cancelled)) {
            let cancelled_calls = self.cancel_pending_calls(Some(&turn_id));
            // A failed context settlement must not skip physical task cleanup or leave this Turn
            // Running. Keep the original typed cleanup failure as the Turn result below.
            if self.interrupted_turn.as_deref() == Some(&turn_id) {
                self.settle_turn_cancellation(&turn_id).await;
            }
            if let Err(error) = cancelled_calls {
                result = Err(error);
            }
        }
        if let Some(turn) = turns.last_mut() {
            // Metadata failures must not replace an execution or cleanup error and its source.
            turn.elapsed_ms = match started.elapsed().as_millis().try_into() {
                Ok(elapsed) => Some(elapsed),
                Err(_) => {
                    if result.is_ok() {
                        result = Err(ThreadError::RevisionExhausted);
                    }
                    None
                }
            };
            match self
                .state
                .attempts
                .iter()
                .filter(|attempt| attempt.turn_id == turn_id)
                .count()
                .try_into()
            {
                Ok(steps) => turn.model_steps = steps,
                Err(_) => {
                    if result.is_ok() {
                        result = Err(ThreadError::RevisionExhausted);
                    }
                }
            }
            turn.state = match &result {
                Ok(completed) => TurnState::Finished(completed.outcome),
                Err(ThreadError::Cancelled) => match self.input_driver.error() {
                    Some(error) => failed_turn(error),
                    None if self.interrupted_turn.as_deref() == Some(&turn_id) => {
                        TurnState::Interrupted
                    }
                    None => TurnState::Cancelled,
                },
                Err(error) => failed_turn(error),
            };
        }
        self.state.turns = turns.into();
        // Only a terminal outcome that really owes work becomes continuable, and it does so in this
        // same commit. Interaction waits, storage faults, cancellations and validation or identity
        // failures all have their own state and are never disguised as "continue".
        if let Some(reason) = self.turn_continuation_reason(&result) {
            self.form_continuation(reason, Some(turn_id.clone()), &format!("turn:{turn_id}"));
        }
        // The batch this Turn froze is settled with the same commit: a body-less control the batch
        // carried but never consumed, and whose authorization this outcome spent or replaced, can
        // never authorize anything again. Keeping it pending would leave phantom owed work that
        // recovery would later report as interrupted.
        if let Err(error) = self.settle_replaced_controls() {
            self.input_driver.fail(Arc::new(error));
            self.pause_inputs();
        }
        result
    }

    /// The continuation a Turn's terminal outcome leaves behind, if it leaves one.
    fn turn_continuation_reason(
        &self,
        result: &Result<TurnCompletion, ThreadError>,
    ) -> Option<ContinuationReason> {
        match result {
            Ok(completion) if completion.outcome == TurnOutcome::StepLimit => {
                Some(ContinuationReason::StepLimit)
            }
            // A close that had to cut live work leaves that same owed work behind, under its own
            // reason, so a restart offers an explicit continuation instead of silently dropping it.
            Err(ThreadError::Cancelled) if self.interrupt.is_closing() => {
                Some(ContinuationReason::HostShutdown)
            }
            // A cancellation that latched a real failure is that failure, exactly like the terminal
            // state records it; the run itself reports cancellation.
            Err(ThreadError::Cancelled) => self
                .input_driver
                .error()
                .filter(|error| recoverable_continuation(error))
                .map(|_| ContinuationReason::ExecutionFailed),
            Err(error) if recoverable_continuation(error) => {
                Some(ContinuationReason::ExecutionFailed)
            }
            Ok(_) | Err(_) => None,
        }
    }

    /// Holds this Turn at the admission gate until the gate is open, and claims its permit.
    ///
    /// Every way a Turn can start reaches this method through [`Self::run_turn`] — a direct
    /// `run_turn`, the queued-input driver, an inbox wake-up and an internal continuation — so this
    /// is the single admission point and no second scheduler (and no per-model-step check) is
    /// needed. While it waits the owner keeps servicing its mailbox, so close, cancellation, flush
    /// and storage recovery still settle; the wait itself consumes no input and creates no Turn
    /// record.
    async fn await_turn_admission(
        &mut self,
        cancellation: &CancellationToken,
    ) -> Result<admission::TurnAdmissionPermit, ThreadError> {
        let Some(gate) = self.turn_admission.clone() else {
            return Ok(admission::TurnAdmissionPermit::ungated());
        };
        // Subscribe before reading the state: a release that lands between the read and the wait
        // must still wake this owner instead of leaving it waiting for an already open gate.
        let mut transitions = gate.subscribe();
        if let Some(permit) = gate.try_admit() {
            return Ok(permit);
        }
        self.turn_admission_waiting = true;
        self.note_execution_phase(ExecutionPhase::AwaitingAdmission);
        self.publish_snapshot();
        let outcome = loop {
            if cancellation.is_cancelled() || self.interrupt.is_closing() {
                break Err(ThreadError::Cancelled);
            }
            if self.state.lifecycle != ThreadLifecycle::Open {
                break Err(ThreadError::Closed);
            }
            let transitioned = self
                .await_with_mailbox(async {
                    tokio::select! {
                        () = cancellation.cancelled() => None,
                        changed = transitions.changed() => Some(changed),
                    }
                })
                .await;
            match transitioned {
                None => break Err(ThreadError::Cancelled),
                // The last gate handle is gone, so nothing can ever open admission for this Turn.
                Some(false) => break Err(ThreadError::Closed),
                Some(true) => {}
            }
            if let Some(permit) = gate.try_admit() {
                break Ok(permit);
            }
        };
        self.turn_admission_waiting = false;
        self.note_execution_phase(self.execution_progress_phase());
        self.publish_snapshot();
        outcome
    }

    pub(super) fn cancel_pending_calls(
        &mut self,
        turn_id: Option<&str>,
    ) -> Result<(), ThreadError> {
        let selected = self
            .pending
            .iter()
            .filter(|(_, call)| turn_id.is_none_or(|turn| call.turn_id == turn))
            .map(|(id, _)| id.clone())
            .collect::<Vec<_>>();
        if selected.is_empty() {
            return Ok(());
        }
        let revision = self
            .state
            .context
            .revision
            .checked_add(1)
            .ok_or(ThreadError::RevisionExhausted)?;
        let mut records = self.state.context.records.to_vec();
        let mut deliveries = self.state.deliveries.to_vec();
        let mut identities = records
            .iter()
            .map(|record| record.id.clone())
            .collect::<std::collections::BTreeSet<_>>();
        for call_id in selected {
            let Some(call) = self.pending.remove(&call_id) else {
                return Err(ThreadError::MissingCall);
            };
            let content = vec![ContextContent::Text {
                text: Arc::from(
                    "Tool call was cancelled before execution. No tool side effects were started.",
                ),
            }];
            let mut suffix = 0_u64;
            let id = loop {
                let id = format!("cancelled:{revision}:{call_id}:{suffix}");
                if identities.insert(id.clone()) {
                    break id;
                }
                suffix += 1;
            };
            records.push(ContextRecord {
                id,
                turn_id: Some(call.turn_id),
                source: ContextSource::ToolResult {
                    call_id: call_id.clone(),
                    tool_id: call.call.tool_id.clone(),
                },
                content: content.clone(),
                tool_calls: Vec::new(),
            });
            deliveries.push(ToolDelivery {
                target: ToolDeliveryTarget::CallResult,
                call_id,
                tool_id: call.call.tool_id,
                output: crate::tool::ToolOutput::new(
                    OpaquePayload::text("cancelled before execution"),
                    content.clone(),
                ),
                delivered_context: content,
                outcome: ToolOutcome::Cancelled,
            });
        }
        self.state.context = ContextSnapshot {
            revision,
            records: records.into(),
        };
        self.state.deliveries = deliveries.into();
        Ok(())
    }

    async fn execute_turn_loop(&mut self, input: TurnInput) -> Result<TurnCompletion, ThreadError> {
        if input.attempt_prefix.is_empty() {
            return Err(ThreadError::InvalidIdentity);
        }
        let mut content = input.content;
        let mut step = 0_u32;
        let mut corrections = 0_u8;
        let mut recovered_capacity = false;
        let mut correction_source = None;
        loop {
            let completed = step.checked_add(1).ok_or(ThreadError::RevisionExhausted)?;
            let step_input = StepInput {
                turn_id: input.turn_id.clone(),
                attempt_id: format!("{}:{step}", input.attempt_prefix),
                content,
                cancellation: input.cancellation.clone(),
            };
            let result = self
                .step_in_turn(
                    step_input,
                    correction_source.take(),
                    &mut recovered_capacity,
                )
                .await;
            let output = match result {
                Err(ThreadError::Model(ref error))
                    if error.kind == crate::model::ModelFailureKind::ContextLimit
                        && !recovered_capacity
                        && !input.max_model_steps.reached(completed)
                        && self.state.attempts.last().is_some_and(|attempt| {
                            attempt.attempt_id == format!("{}:{step}", input.attempt_prefix)
                                && attempt.status == AttemptStatus::Failed
                        }) =>
                {
                    recovered_capacity = true;
                    let next = StepInput {
                        turn_id: input.turn_id.clone(),
                        attempt_id: format!("{}:{completed}", input.attempt_prefix),
                        content: Vec::new(),
                        cancellation: input.cancellation.clone(),
                    };
                    // The failed attempt already admitted its input. Reduce committed history,
                    // then let the next identified attempt proceed without consuming it again.
                    if !self.recover_context(&next).await? {
                        return Err(ThreadError::Model(error.clone()));
                    }
                    content = Vec::new();
                    step = completed;
                    continue;
                }
                Err(ThreadError::ModelOutput(ModelOutputViolation::SoloBatch { ref tool_ids }))
                    if corrections < 2 && !input.max_model_steps.reached(completed) =>
                {
                    if input.cancellation.is_cancelled() || self.interrupt.is_closing() {
                        return Err(ThreadError::Cancelled);
                    }
                    content = vec![ContextContent::Text {
                        text: Arc::from(format!(
                            "No tools in this batch were executed. Tools {tool_ids:?} must each be called alone in a model response. Generate a corrected response using the committed results; do not repeat completed tools."
                        )),
                    }];
                    correction_source = Some(format!("{}:{step}", input.attempt_prefix));
                    corrections += 1;
                    step = step.checked_add(1).ok_or(ThreadError::RevisionExhausted)?;
                    continue;
                }
                other => other?,
            };
            if output.tool_calls.is_empty() {
                return Ok(TurnCompletion {
                    model_steps: completed,
                    outcome: TurnOutcome::Completed,
                    last_output: output,
                });
            }
            for call in &output.tool_calls {
                match self
                    .execute_tool(call.call_id.clone(), input.cancellation.clone())
                    .await
                {
                    Ok(ToolDispatch::Completed(result))
                        if result.control() == crate::tool::ToolControl::EndTurn =>
                    {
                        return Ok(TurnCompletion {
                            model_steps: completed,
                            outcome: TurnOutcome::Completed,
                            last_output: output,
                        });
                    }
                    Ok(ToolDispatch::Completed(result))
                        if result.control() == crate::tool::ToolControl::AwaitInteraction =>
                    {
                        return Ok(TurnCompletion {
                            model_steps: completed,
                            outcome: TurnOutcome::WaitingInteraction,
                            last_output: output,
                        });
                    }
                    Err(ThreadError::Cancelled) if !input.cancellation.is_cancelled() => {}
                    Ok(_) | Err(ThreadError::Tool(_)) => {} // Failed tool facts were committed for model recovery.
                    Err(error) => return Err(error),
                }
            }
            if input.max_model_steps.reached(completed) {
                return Ok(TurnCompletion {
                    model_steps: completed,
                    outcome: TurnOutcome::StepLimit,
                    last_output: output,
                });
            }
            content = Vec::new();
            step = step.checked_add(1).ok_or(ThreadError::RevisionExhausted)?;
        }
    }
}

fn failed_turn(error: &ThreadError) -> TurnState {
    TurnState::Failed {
        description: error.to_string(),
        model_failure: match error {
            ThreadError::Model(error) => Some(Box::new(error.failure_facts())),
            _ => None,
        },
    }
}

/// Whether a Turn failure leaves work a caller can recover by explicitly continuing.
///
/// Only a failure a later explicit request can actually change counts, and a Thread whose model binding
/// itself is unavailable. The model categories are:
///
/// - `Unavailable`: the provider is temporarily unavailable, so a retry or a new binding can succeed.
/// - `ContextLimit`: the context no longer fits. The Turn already had its one automatic compaction, so
///   continuing needs a host decision — a bigger window or a different binding — and without a point the
///   consumed request could never be run again once that decision is made.
/// - `UnsupportedContent`: this binding cannot carry the request content. A binding that can is a host
///   decision too, and the already consumed request is otherwise lost.
///
/// Everything else keeps its own state instead of pretending to be continuable: `InvalidResponse` (the
/// answer could not be used), `ImplementationPanicked` (an adapter defect), `IncompatibleContext` (the
/// request shape has to change, not the authorization), a storage fault (explicit save recovery), a
/// pending tool commit (retry), an interaction (its own resolution entry), a closed owner, a cancellation
/// and every validation or identity violation. Nothing here ever retries by itself: a point only makes an
/// explicit continuation possible.
fn recoverable_continuation(error: &ThreadError) -> bool {
    match error {
        ThreadError::ModelUnavailable => true,
        ThreadError::Model(error) => matches!(
            error.kind,
            crate::model::ModelFailureKind::Unavailable
                | crate::model::ModelFailureKind::ContextLimit
                | crate::model::ModelFailureKind::UnsupportedContent
        ),
        _ => false,
    }
}

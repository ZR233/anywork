//! Frozen model operations and the single synchronous result reducer.
use super::*;

pub(super) struct StepWork {
    pub(super) input: StepInput,
    pub(super) plan: crate::tool::opaque::ToolPlan,
    pub(super) retry_of: Option<String>,
    pub(super) frozen_input: Vec<ContextRecord>,
    pub(super) consumed_messages: u64,
    pub(super) steering_ids: Vec<String>,
    pub(super) context: ContextSnapshot,
    pub(super) base_context_revision: u64,
    pub(super) tool_projection: Option<OpaquePayload>,
    pub(super) preparation_refresh: u8,
    pub(super) admitted_attempt: Option<RequestAttempt>,
    pub(super) recovery_error: Option<Arc<ModelError>>,
    pub(super) compaction_applied: bool,
}

impl StepWork {
    pub(super) fn repair_failure(&self, repair: ThreadError) -> ThreadError {
        with_model_repair(self.recovery_error.clone(), repair)
    }
}

pub(super) fn with_model_repair(
    primary: Option<Arc<ModelError>>,
    repair: ThreadError,
) -> ThreadError {
    match primary {
        Some(primary) if !matches!(repair, ThreadError::Cancelled) => ThreadError::ModelRepair {
            primary,
            repair: Arc::new(repair),
        },
        _ => repair,
    }
}

impl Owner {
    fn output_violation(
        &self,
        attempt_id: &str,
        revision: u64,
        plan: &crate::tool::opaque::ToolPlan,
        output: &ModelStepOutput,
    ) -> Option<ModelOutputViolation> {
        if output.attempt_id != attempt_id {
            return Some(ModelOutputViolation::AttemptIdentity {
                expected: attempt_id.into(),
                actual: output.attempt_id.clone(),
            });
        }
        if output.base_context_revision != revision {
            return Some(ModelOutputViolation::ContextRevision {
                expected: revision,
                actual: output.base_context_revision,
            });
        }
        let mut ids = std::collections::BTreeSet::new();
        for call in &output.tool_calls {
            if call.call_id.is_empty() {
                return Some(ModelOutputViolation::EmptyCallIdentity);
            }
            // Call identity is global to the Thread: a call already admitted by the current context,
            // or by the independent live ledger of the current Turn must never be re-declared. The
            // ledger outlives any compaction of the attempts that declared those calls, so a long
            // Turn keeps its duplicate-call protection after its finished attempts leave the
            // resident set.
            if !ids.insert(&call.call_id)
                || self.state.live_calls.contains_key(&call.call_id)
                || self.state.context.records.iter().any(|record| {
                    record
                        .tool_calls
                        .iter()
                        .any(|old| old.call_id == call.call_id)
                })
            {
                return Some(ModelOutputViolation::DuplicateCallIdentity {
                    call_id: call.call_id.clone(),
                });
            }
        }
        // Execution authority is checked per call at dispatch, not for unused declarations. A
        // diagnostic unknown name is not an execution identity, even if it equals a real stable ID.
        for call in &output.tool_calls {
            if !matches!(
                call.rejection,
                Some(crate::model::ModelToolCallRejection::UnknownTool { .. })
            ) && plan.get(&call.tool_id).is_none()
            {
                return Some(ModelOutputViolation::UnknownTool {
                    tool_id: call.tool_id.clone(),
                    call_id: call.call_id.clone(),
                });
            }
        }
        for call in &output.tool_calls {
            if let Some(rejection) = &call.rejection {
                return Some(ModelOutputViolation::ToolCallRejected {
                    call_id: call.call_id.clone(),
                    rejection: rejection.clone(),
                });
            }
        }
        let solo = output
            .tool_calls
            .iter()
            .filter(|call| {
                plan.get(&call.tool_id)
                    .is_some_and(|tool| tool.requires_solo_call())
            })
            .map(|call| call.tool_id.clone())
            .collect::<Vec<_>>();
        (output.tool_calls.len() > 1 && !solo.is_empty())
            .then_some(ModelOutputViolation::SoloBatch { tool_ids: solo })
    }

    pub(super) fn validate_step_identity(&self, input: &StepInput) -> Result<(), ThreadError> {
        if self.current_saved_lifecycle.is_some() {
            return Err(ThreadError::CurrentPaused);
        }
        if input.turn_id.is_empty()
            || input.attempt_id.is_empty()
            || self.state.context.records.iter().any(|record| {
                record.id == format!("{}:input", input.attempt_id)
                    || record.id == format!("{}:output", input.attempt_id)
            })
            || self.state.attempt_ids.contains_key(&input.attempt_id)
            || self
                .state
                .attempts
                .iter()
                .any(|attempt| attempt.attempt_id == input.attempt_id)
        {
            return Err(ThreadError::InvalidIdentity);
        }
        Ok(())
    }

    /// Publishes the explicit model execution phase at the exact boundary it describes.
    pub(super) fn enter_model_execution(&mut self, phase: ModelExecutionPhase) {
        if self.state.model_execution == Some(phase) {
            return;
        }
        self.state.model_execution = Some(phase);
        self.publish_snapshot();
    }

    pub(super) fn check_model_admission(&mut self) -> Result<(), ThreadError> {
        if self.state.lifecycle != ThreadLifecycle::Open || self.interrupt.is_closing() {
            return Err(ThreadError::Closed);
        }
        if !self
            .model
            .as_ref()
            .is_some_and(DynModelSession::is_available)
        {
            return Err(ThreadError::ModelUnavailable);
        }
        if self
            .state
            .interactions
            .values()
            .any(|r| r.state == interactions::InteractionState::Pending)
        {
            return Err(ThreadError::PendingInteraction);
        }
        if !self.pending.is_empty() {
            return Err(ThreadError::PendingTools);
        }
        Ok(())
    }

    pub(super) fn freeze_step(
        &mut self,
        input: StepInput,
        plan: crate::tool::opaque::ToolPlan,
        retry_of: Option<String>,
    ) -> Result<StepWork, ThreadError> {
        self.validate_step_identity(&input)?;
        self.check_model_admission()?;
        self.begin_current_step(&input, &plan);
        let correcting = retry_of.as_ref().is_some_and(|source| {
            self.state.attempts.last().is_some_and(|previous| {
                previous.attempt_id == *source
                    && matches!(
                        &previous.status,
                        AttemptStatus::Rejected { reason } if reason.is_correctable()
                    )
            })
        });
        // Freeze consumption before any awaited preparation. Mailbox input arriving while the
        // hook runs belongs to the next step and must not change this preview or its watermark.
        let (messages, consumed_messages) = if retry_of.is_none() || correcting {
            self.message_context(&input.turn_id)
        } else {
            (Vec::new(), self.state.consumed_messages)
        };
        let (steering, steering_ids) = if retry_of.is_none() || correcting {
            self.steering_context(&input.turn_id)
        } else {
            (Vec::new(), Vec::new())
        };
        let mut frozen_input = messages;
        if !input.content.is_empty() {
            frozen_input.push(ContextRecord {
                tool_calls: Vec::new(),
                id: format!("{}:input", input.attempt_id),
                turn_id: Some(input.turn_id.clone()),
                source: if correcting {
                    ContextSource::Runtime {
                        source_id: "model-output-correction".into(),
                    }
                } else {
                    ContextSource::User
                },
                content: input.content.clone(),
            });
        }
        frozen_input.extend(steering);

        Ok(StepWork {
            input,
            plan,
            retry_of,
            frozen_input,
            consumed_messages,
            steering_ids,
            context: self.state.context.clone(),
            base_context_revision: self.state.context.revision,
            tool_projection: None,
            preparation_refresh: 0,
            admitted_attempt: None,
            recovery_error: None,
            compaction_applied: false,
        })
    }

    pub(super) fn build_model_request(&mut self, mut step: StepWork) -> Result<(), ThreadError> {
        let StepWork {
            ref input,
            ref plan,
            ref frozen_input,
            ..
        } = step;
        self.enter_model_execution(ModelExecutionPhase::BuildingRequest);
        let mut records = self.state.context.records.to_vec();
        let changed = !frozen_input.is_empty();
        records.extend_from_slice(frozen_input);
        let input_revision = if changed {
            self.state
                .context
                .revision
                .checked_add(1)
                .ok_or(ThreadError::RevisionExhausted)?
        } else {
            self.state.context.revision
        };
        let context = ContextSnapshot {
            revision: input_revision,
            records: records.into(),
        };
        context.validate_complete()?;
        // Reserving the reliable output budget waits for capacity/storage admission, which is a wait
        // on the host, not on the model implementation.
        self.enter_model_execution(ModelExecutionPhase::Admitting);
        // The call may only start once the reliable budget really funds the output it will stream:
        // this is the admission reservation, and it waits at a storage safety point instead of
        // starting a call whose result could not be retained.
        let output_budget = self
            .operation_budgets
            .get(&input.attempt_id)
            .cloned()
            .ok_or(ThreadError::InvalidIdentity)?;
        let (progress, observations) = crate::model::ModelProgressSender::channel(
            self.cold.clone(),
            &self.id,
            &input.turn_id,
            &input.attempt_id,
            output_budget.clone(),
        );
        self.model_progress = Some((input.attempt_id.clone(), observations));
        let (members, member_receiver) =
            crate::model::ModelMemberSender::channel(&input.turn_id, &input.attempt_id);
        let members = members
            .with_output(output_budget.clone())
            .with_context_recovery(
                step.recovery_error
                    .as_ref()
                    .and_then(|error| error.context_recovery.as_deref())
                    .cloned(),
            );
        let members = if self.cold.is_some() || !self.is_current_owner {
            members.with_settlement(self.register_model_settlement(
                Some(input.turn_id.clone()),
                input.attempt_id.clone(),
                output_budget.clone(),
                false,
            )?)
        } else {
            members
        };
        let member_registry = members.registry();
        let tools = plan.declarations();
        let request = ModelRequest {
            tool_call_mode: plan.call_mode(),
            solo_tool_ids: plan.solo_tool_ids(),
            progress: Some(progress),
            members: Some(members),
            thread_id: self.id.clone(),
            turn_id: input.turn_id.clone(),
            attempt_id: input.attempt_id.clone(),
            context: context.clone(),
            tools: tools.clone(),
            committed_private_context: self.state.private_context.clone(),
            resources: self.resources.clone(),
            cancellation: input.cancellation.clone(),
        };
        if let Some(call) = &mut self.current_call {
            call.tools = request.tools.clone();
            call.tool_call_mode = request.tool_call_mode;
            call.solo_tool_ids = request.solo_tool_ids.clone();
        }
        self.model_members = Some(super::model_members::MemberCall::new(
            member_receiver,
            input,
            member_registry,
        ));
        step.base_context_revision = self.state.context.revision;
        step.context = context;
        let mut model = self.model.take().ok_or(ThreadError::ModelUnavailable)?;
        self.enter_model_execution(ModelExecutionPhase::PreparingRequest);
        let available = model.is_available();
        self.primary = Some(super::execution::PrimaryWork::new(available, async move {
            let result = model.prepare(request).await;
            super::execution::PrimaryCompletion::PreparedModel {
                model,
                step,
                result,
            }
        }));
        Ok(())
    }

    pub(super) fn admit_prepared_model(
        &mut self,
        mut step: StepWork,
        prepared: crate::model::PreparedModelCall,
    ) -> Result<(), ThreadError> {
        let StepWork {
            ref input,
            ref plan,
            ref steering_ids,
            ref context,
            consumed_messages,
            ..
        } = step;
        let input_revision = context.revision;
        if input.cancellation.is_cancelled() {
            return Err(ThreadError::Cancelled);
        }
        if self.state.context.revision != step.base_context_revision {
            return Err(ThreadError::ContextConflict {
                expected: step.base_context_revision,
                actual: self.state.context.revision,
            });
        }
        let tools = plan.declarations();
        let input_estimate = prepared.input_estimate();
        let request_metadata = prepared.request_metadata().cloned();
        let usage_binding = prepared.usage_binding().cloned();
        let tool_projection = prepared.tool_projection().cloned();
        if let Some(call) = &mut self.current_call {
            call.tools = plan.declarations();
            call.tool_call_mode = plan.call_mode();
            call.solo_tool_ids = plan.solo_tool_ids();
            call.prepared_parameters = request_metadata.clone();
        }
        self.current_capture = prepared.current_capture().cloned();
        if let Some(capture) = &self.current_capture {
            capture.bind_dirty(self.current_dirty.clone());
        }
        // Capacity and storage admission happen before dispatch; they are waits on the host, not on
        // the model implementation.
        self.enter_model_execution(ModelExecutionPhase::Admitting);
        self.capacity.admit(input_estimate)?;
        self.check_model_admission()?;
        let mut attempts = self.state.attempts.to_vec();
        attempts.push(RequestAttempt {
            turn_id: input.turn_id.clone(),
            attempt_id: input.attempt_id.clone(),
            retry_of: step.retry_of.clone(),
            input_revision,
            status: AttemptStatus::Running,
            usage: None,
            facts: Some(AttemptFacts {
                input_record_count: context.records.len(),
                input_hash: Some(super::context_preparation::input_hash(
                    &context.records,
                    &tools,
                    plan.call_mode(),
                    &plan.solo_tool_ids(),
                )?),
                request_metadata,
                usage_binding,
                tool_projection: tool_projection.clone(),
                tools: plan.declarations(),
                outcome: AttemptOutcome::Running,
                input_estimate,
            }),
        });
        step.admitted_attempt = attempts.last().cloned();
        self.validate_steering(steering_ids)?;
        // Consumption can retire the task/permission that still owns an undelivered result.
        // Keep the entire synchronous admission atomic, including the owner fields outside state:
        // no snapshot may expose it until publish has reserved both resource cuts.
        let previous = self.state.clone();
        let previous_current = self.current_call.clone();
        let previous_retry_plan = self.retry_plan.clone();
        let previous_claim = self.pending_output_claim.clone();
        let admission = (|| {
            self.consume_active_input(&input.turn_id, &input.attempt_id)?;
            self.consume_steering(steering_ids, &input.turn_id, &input.attempt_id)?;
            self.retry_plan = Some((input.attempt_id.clone(), plan.clone()));
            self.state.context = context.clone();
            // Direct input enters confirmed context and loses its temporary ownership in this
            // same synchronous transition. Streaming cannot be published before this point.
            if let Some(call) = &mut self.current_call {
                call.phase = current::SavedModelPhase::Preparing {
                    pending_step_input: None,
                };
            }
            self.current_model_running = true;
            // Whether this admission really executes queued work — a Message input of this batch or of the
            // steering set, or the messages it delivers. That is what serves a point nothing claims any
            // more, and it is measured before the watermark and the inputs move.
            let ran_queued_work = consumed_messages > self.state.consumed_messages
                || self
                    .active_inputs
                    .iter()
                    .chain(steering_ids.iter())
                    .any(|id| {
                        self.state.inputs.iter().any(|record| {
                            record.input.id == *id
                                && record.input.purpose == input::InputPurpose::Message
                        })
                    });
            self.state.consumed_messages = consumed_messages;
            // Actual submitted content supersedes owed work when its frozen batch is admitted.
            // Resume already consumed its one-shot token when reserving this execution.
            if ran_queued_work {
                self.state.continuation = None;
            }
            self.mark_resume_effective();
            self.state.attempts = attempts.clone().into();
            self.state
                .attempt_ids
                .insert(input.attempt_id.clone(), input.turn_id.clone());
            // The attempt is now running the prepared provider call; streaming output is observed
            // through the model progress sender.
            self.state.model_execution = Some(ModelExecutionPhase::Running);
            // The attempt's own "running" row is part of what this call's reliable output ceiling funds.
            self.claim_output(input.attempt_id.clone());
            self.publish()
        })();
        if let Err(error) = admission {
            self.state = previous;
            self.current_call = previous_current;
            self.retry_plan = previous_retry_plan;
            self.pending_output_claim = previous_claim;
            self.current_model_running = false;
            return Err(error);
        }
        drop((previous, previous_retry_plan, previous_claim));
        step.tool_projection = tool_projection;
        let model = self.model.take().ok_or(ThreadError::ModelUnavailable)?;
        let available = model.is_available();
        self.primary = Some(super::execution::PrimaryWork::new(available, async move {
            let exit = prepared.execute_with_current().await;
            super::execution::PrimaryCompletion::Model { model, step, exit }
        }));
        Ok(())
    }

    pub(super) fn reduce_model_result(
        &mut self,
        step: &StepWork,
        exit: crate::model::ModelCallExit,
    ) -> Result<ModelStepOutput, ThreadError> {
        let input = &step.input;
        let plan = &step.plan;
        let input_revision = step.context.revision;
        let output_revision = input_revision
            .checked_add(1)
            .ok_or(ThreadError::RevisionExhausted)?;
        let tool_context = step.context.clone();
        let tool_projection = step.tool_projection.clone();
        self.current_model_running = false;
        self.current_capture = None;
        self.current_snapshot_missing = exit.current.is_none();
        if let Some(stream) = exit.current
            && let Some(call) = &mut self.current_call
        {
            call.phase = current::SavedModelPhase::Streaming { stream };
        }
        let mut attempts = self.state.attempts.to_vec();
        if let Some(admitted) = &step.admitted_attempt {
            if let Some(attempt) = attempts
                .iter_mut()
                .find(|a| a.attempt_id == admitted.attempt_id)
            {
                *attempt = admitted.clone();
            } else {
                attempts.push(admitted.clone());
            }
        }
        let result = exit.result.map_err(Arc::new);
        let member_error = self.finish_model_members();
        if input.cancellation.is_cancelled()
            && self.interrupted_turn.as_deref() == Some(&input.turn_id)
            && let Err(error) = &result
            && error.kind != crate::model::ModelFailureKind::Cancelled
        {
            self.policy
                .fail(Arc::new(ThreadError::Model(error.clone())));
            self.pause_inputs();
        }
        let (outcome, result) = if input.cancellation.is_cancelled() {
            (
                AttemptOutcome::Cancelled { result },
                Err(ThreadError::Cancelled),
            )
        } else {
            let violation = result.as_ref().ok().and_then(|output| {
                self.output_violation(&input.attempt_id, input_revision, plan, output)
            });
            match (result, violation) {
                (Err(error), _) => (
                    AttemptOutcome::Failed(error.clone()),
                    Err(ThreadError::Model(error)),
                ),
                (Ok(output), Some(reason)) => (
                    AttemptOutcome::Rejected {
                        output,
                        reason: reason.clone(),
                    },
                    Err(reason.into()),
                ),
                (Ok(output), None) => {
                    let admitted_call_ids = output
                        .tool_calls
                        .iter()
                        .map(|call| call.call_id.clone())
                        .collect::<Vec<_>>();
                    for call in &output.tool_calls {
                        if let Some(executor) = plan.get(&call.tool_id) {
                            self.pending.insert(
                                call.call_id.clone(),
                                PendingCall {
                                    context: tool_context.clone(),
                                    model_projection: tool_projection.clone(),
                                    turn_id: input.turn_id.clone(),
                                    call: call.clone(),
                                    executor: executor.clone(),
                                    parent_call_id: None,
                                    nested_plan: executor
                                        .may_call_nested()
                                        .then(|| Arc::new(plan.clone())),
                                },
                            );
                        }
                    }
                    let mut records = self.state.context.records.to_vec();
                    records.push(ContextRecord {
                        tool_calls: output.tool_calls.clone(),
                        id: format!("{}:output", input.attempt_id),
                        // 提交记录与 effect/子引用共享同一个稳定 turn id：这里克隆而不是移动，
                        // `input.turn_id` 之后仍要写入 live_calls。
                        turn_id: Some(input.turn_id.clone()),
                        source: ContextSource::Assistant,
                        content: output.content.clone(),
                    });
                    self.state.context = ContextSnapshot {
                        revision: output_revision,
                        records: records.into(),
                    };
                    self.state.private_context = output.private_context.clone();
                    // No await or observer cut separates the complete output, context, private
                    // context and usage terminal reducer below. The pending outcome is discarded.
                    if let Some(call) = &mut self.current_call {
                        call.phase = current::SavedModelPhase::Applied;
                    }
                    self.current_snapshot_missing = false;
                    for call_id in admitted_call_ids {
                        self.state
                            .live_calls
                            .entry(call_id)
                            .or_insert_with(|| input.turn_id.clone());
                    }
                    (AttemptOutcome::Committed(output.clone()), Ok(output))
                }
            }
        };
        if let Some(attempt) = attempts.last_mut() {
            attempt.status = AttemptStatus::from_outcome(&outcome);
            attempt.usage = attempt_outcome_usage(&outcome).cloned();
            if let Some(facts) = &mut attempt.facts {
                facts.outcome = outcome;
            }
        }
        self.state.attempts = attempts.into();
        // The terminal receiver remains available only until its immutable History handoff has
        // captured the exact producer cut. Current snapshots already exclude non-running attempts.
        // Independently admitted members still have live call-local opaque allocations until the
        // terminal handoff below completes. Their resident reservation is not transferable funding
        // for this terminal effect: use ordinary reliable admission for that encoded copy instead.
        // Calls without retained members keep their original output transfer.
        self.pending_output_claim = if self
            .model_members
            .as_ref()
            .is_some_and(super::model_members::MemberCall::retains_members)
        {
            None
        } else {
            Some(input.attempt_id.clone())
        };
        self.current_snapshot_missing = false;
        if let Some((attempt_id, receiver)) = &self.model_progress {
            let progress = receiver.borrow().clone();
            self.progress_tracker.observe(attempt_id, &progress, &self.event_bus);
        }
        self.progress_tracker
            .finish_attempt(&input.attempt_id, &self.event_bus);
        self.model_progress = None;
        let published = self.publish();
        published?;
        // Keep bounded member validation through the final output checks and terminal handoff.
        // Closing ingress above is not permission to release its identity/metadata obligation early.
        self.model_members = None;
        match member_error {
            Some(error) => Err(ThreadError::Model(Arc::new(crate::model::ModelError {
                context_recovery: None,
                kind: crate::model::ModelFailureKind::InvalidResponse,
                source: Some(Box::new(error)),
                details: None,
                usage: Box::default(),
            }))),
            None => result,
        }
    }

    pub(super) fn finish_step(&mut self, attempt_id: &str) {
        self.retire_model_settlement(attempt_id);
        self.settle_operation_output(attempt_id);
        self.progress_tracker
            .finish_attempt(attempt_id, &self.event_bus);
        self.model_progress = None;
        self.model_members = None;
        self.state.model_execution = None;
        self.current_snapshot_missing = false;
        if !self.current_model_running {
            self.current_capture = None;
        }
        self.publish_snapshot();
    }
}

//! Frozen tool execution, control validation and atomic result commit.
use super::*;

#[derive(Clone)]
pub(super) struct ToolExecutionCompletion {
    pub(super) call: PendingCall,
    pub(super) output: Result<crate::tool::ToolOutput, Arc<crate::tool::opaque::ToolError>>,
    pub(super) cancellation: CancellationToken,
}

pub(super) type ToolExecutionFuture = futures::future::BoxFuture<'static, ToolExecutionCompletion>;

/// Pure materialization shared by ordinary commit and current capture of a retained completion.
pub(super) fn observed_completion(
    completion: &ToolExecutionCompletion,
) -> (crate::tool::ToolOutput, ToolOutcome) {
    match &completion.output {
        Ok(output) => {
            let outcome = match completion.call.executor.validate_control(output) {
                Ok(()) => ToolOutcome::Succeeded,
                Err(error) => ToolOutcome::Failed(Arc::new(error)),
            };
            (output.clone(), outcome)
        }
        Err(error) => {
            let output = error.observed_output().cloned().unwrap_or_else(|| {
                let text = error.to_string();
                crate::tool::ToolOutput::new(
                    OpaquePayload::text(text.clone()),
                    vec![ContextContent::Text {
                        text: Arc::from(text),
                    }],
                )
            });
            (output, ToolOutcome::Failed(error.clone()))
        }
    }
}

pub(super) fn annotate_failure_context(
    output: &mut crate::tool::ToolOutput,
    outcome: &ToolOutcome,
) {
    if let ToolOutcome::Failed(error) = outcome {
        let diagnostic = error.to_string();
        if !output.context().iter().any(|content| matches!(content, ContextContent::Text { text } if text.as_ref() == diagnostic)) {
            output.append_framework_context(ContextContent::Text { text: Arc::from(format!("Framework recorded tool failure: {diagnostic}")) });
        }
    }
}

pub(super) fn model_delivery_context(
    output: &crate::tool::ToolOutput,
    outcome: &ToolOutcome,
) -> Vec<ContextContent> {
    if matches!(outcome, ToolOutcome::Cancelled) {
        vec![ContextContent::Text {
            text: Arc::from(
                "Tool execution was cancelled. Any observed result is retained for inspection; its state changes and Turn control were not applied.",
            ),
        }]
    } else {
        output.context().to_vec()
    }
}

/// Reliable output reservation identity of one tool call.
///
/// It is exactly the caller key the tool's task is stored under, so the mailbox progress handler
/// finds the call's quota from the caller identity it already has instead of parsing it back out.
pub(super) fn tool_output_operation(call_id: &str) -> String {
    format!("task:{call_id}")
}

#[derive(Debug, thiserror::Error)]
#[error("tool capacity unavailable; no execution was started")]
pub(super) struct ToolCapacityUnavailable;

/// The same known result is measured before dispatch and accepted if task admission fails.
pub(super) fn capacity_result(
    call: &PendingCall,
    revision: u64,
) -> Result<(ContextRecord, ToolDelivery), ThreadError> {
    let id = &call.call.call_id;
    let body = serde_json::json!({"code":"capacity_unavailable", "notStarted":true, "callId":id, "toolId":call.call.tool_id}).to_string();
    let content = vec![ContextContent::Text {
        text: Arc::from(body.clone()),
    }];
    let output = crate::tool::ToolOutput::new(
        OpaquePayload::new("pl.core.tool-error", 1, body)
            .map_err(|_| ThreadError::InvalidOutput)?,
        content.clone(),
    );
    let record = ContextRecord {
        id: format!("not-started:{revision}:{id}"),
        turn_id: Some(call.turn_id.clone()),
        source: ContextSource::ToolResult {
            call_id: id.clone(),
            tool_id: call.call.tool_id.clone(),
        },
        content: content.clone(),
        tool_calls: Vec::new(),
    };
    let delivery = ToolDelivery {
        target: ToolDeliveryTarget::CallResult,
        call_id: id.clone(),
        tool_id: call.call.tool_id.clone(),
        output,
        delivered_context: content,
        outcome: ToolOutcome::Failed(Arc::new(crate::tool::opaque::ToolError::new(
            ToolCapacityUnavailable,
        ))),
    };
    Ok((record, delivery))
}

impl Owner {
    pub(super) fn begin_tool_execution(
        &mut self,
        id: String,
        cancellation: CancellationToken,
    ) -> Result<ToolExecutionFuture, ThreadError> {
        if self.state.lifecycle != ThreadLifecycle::Open {
            return Err(ThreadError::Closed);
        }
        if cancellation.is_cancelled() || self.interrupt.is_closing() {
            return Err(ThreadError::Cancelled);
        }
        let call = self.pending.get(&id).ok_or(ThreadError::MissingCall)?;
        // Bodies, context and frozen catalogs are shared with the original owner. Charge the new
        // owned identities and task slots, without serializing another PendingCall mirror.
        let metadata_bytes = 1024_u64
            .saturating_add(
                (std::mem::size_of::<PendingCall>() + std::mem::size_of::<task::TaskRecord>())
                    as u64,
            )
            .saturating_add(
                (call.call.call_id.len() * 4
                    + call.call.tool_id.len() * 3
                    + call.turn_id.len()
                    + call.parent_call_id.as_ref().map_or(0, String::len)) as u64,
            );
        let metadata_id = format!("task-metadata:{id}");
        let metadata = crate::model::OutputBudget::reserve(
            self.cold.clone(),
            &self.id,
            &metadata_id,
            metadata_bytes,
            None,
        )
        .map_err(|_| ThreadError::StoragePressure)?;
        if metadata.charge(metadata_bytes).is_err() {
            metadata.release();
            return Err(ThreadError::StoragePressure);
        }
        self.task_metadata.insert(id.clone(), metadata);
        let call = self.pending.remove(&id).ok_or(ThreadError::MissingCall)?;
        if let Err(error) = self.start_task(&call) {
            if let Some(metadata) = self.task_metadata.remove(&id) {
                metadata.release();
            }
            self.pending.insert(id, call);
            return Err(error);
        }
        let cancellation =
            if call.parent_call_id.is_some() || call.executor.requires_foreground_execution() {
                cancellation.child_token()
            } else {
                self.interrupt.background_token()
            };
        let tasks =
            TaskAccess::new(self, &id, &call.executor).with_nested_plan(call.nested_plan.clone());
        if let Some(plan) = &call.nested_plan {
            self.nested_plans.insert(
                format!("task:{id}"),
                super::owner::NestedScope {
                    plan: plan.clone(),
                    context: call.context.clone(),
                    model_projection: call.model_projection.clone(),
                    invocations: tasks.nested_invocations.clone(),
                },
            );
        }
        let authorized = call.executor.remains_authorized(&self.tools);
        let cold = self.cold.clone();
        let cold_error = self.cold_error.clone();
        let context = crate::tool::opaque::CallContext {
            grant: Default::default(),
            context: call.context.clone(),
            history_fence: self.state.commit_sequence,
            model_projection: call.model_projection.clone(),
            tasks: Some(tasks),
            thread_id: self.id.clone(),
            turn_id: call.turn_id.clone(),
            call_id: id,
            cancellation: cancellation.clone(),
            extensions: Arc::new(self.state.extensions.clone()),
            extension_sequence: self.state.extension_sequence,
            catalog: self.tools.catalog(),
        };
        let identity = crate::tool::task::ExecutionIdentity::new(
            call.call.call_id.clone(),
            call.call.tool_id.clone(),
        );
        let failed_call = call.clone();
        let failed_cancellation = cancellation.clone();
        let execution = self
            .executions
            .start(identity, cancellation.clone(), async move {
                let output = if authorized {
                    call.executor
                        .execute(call.call.arguments.clone(), context, cold, cold_error)
                        .await
                        .map_err(Arc::new)
                } else {
                    Err(Arc::new(crate::tool::opaque::ToolError::new(
                        ThreadError::ToolPermissionRevoked,
                    )))
                };
                ToolExecutionCompletion {
                    call,
                    output,
                    cancellation,
                }
            })
            .map_err(|_| ThreadError::Closed)?;
        self.executing_authorities.insert(
            format!("task:{}", failed_call.call.call_id),
            failed_call.executor.authority(),
        );
        Ok(Box::pin(async move {
            match execution.wait().await {
                Ok(completion) => (*completion).clone(),
                Err(error) => ToolExecutionCompletion {
                    call: failed_call,
                    output: Err(Arc::new(crate::tool::opaque::ToolError::new(error))),
                    cancellation: failed_cancellation,
                },
            }
        }))
    }

    pub(super) fn commit_tool_execution(
        &mut self,
        mut completion: ToolExecutionCompletion,
    ) -> Result<crate::tool::ToolOutput, ThreadError> {
        // A retained completion is retried as the fact first observed here. Later stop/close
        // requests must not turn an already completed successful result into a cancelled one.
        let cancellation = CancellationToken::new();
        if completion.cancellation.is_cancelled() {
            cancellation.cancel();
        }
        completion.cancellation = cancellation;
        let id = completion.call.call.call_id.clone();
        if let Some(progress) = self.state.tool_progress.get(&format!("task:{id}")) {
            self.current_retired_previews.insert(
                id.clone(),
                current::SavedToolProgress::capture(self.runtime_epoch, progress),
            );
        }
        let operation = tool_output_operation(&id);
        let result = self.stage_tool_execution(completion);
        let terminal =
            result.is_ok() || matches!(result, Err(ThreadError::Tool(_) | ThreadError::Cancelled));
        if terminal {
            self.pending_output_claim = Some(operation.clone());
            // Known context, effects and usage are accepted once. History owns its pending export;
            // publication failure can never restore pre-completion business state or rerun the tool.
            let published = self.publish();
            self.permission_leases.remove(&format!("permission:{id}"));
            self.executions.forget(&format!("task:{id}"));
            self.executing_authorities.remove(&format!("task:{id}"));
            self.nested_plans.remove(&format!("task:{id}"));
            if published.is_ok() {
                self.settle_operation_output(&operation);
                self.release_retired_task_metadata();
            } else {
                self.publish_snapshot();
            }
            published?;
        }
        result
    }

    pub(super) fn reject_tool_capacity(
        &mut self,
        id: &str,
        receipt_operation: &str,
    ) -> Result<(), ThreadError> {
        let call = self.pending.remove(id).ok_or(ThreadError::MissingCall)?;
        let (record, delivery) = capacity_result(&call, self.state.context.revision)?;
        current::pair_known_call_result(&mut self.state.context, record)
            .map_err(|error| ThreadError::CurrentResume(Arc::new(error)))?;
        let mut deliveries = self.state.deliveries.to_vec();
        deliveries.push(delivery);
        self.state.deliveries = deliveries.into();
        self.claim_output(receipt_operation.to_owned());
        self.publish()
    }

    pub(super) fn release_retired_task_metadata(&mut self) {
        if self.cold.is_some() && !self.pending_effects.is_empty() {
            return;
        }
        let retired: Vec<_> = self
            .task_metadata
            .keys()
            .filter(|id| {
                self.executions.token(&format!("task:{id}")).is_none()
                    && !self
                        .state
                        .tasks
                        .get(&format!("task:{id}"))
                        .is_some_and(|task| task.status == task::TaskStatus::Running)
            })
            .cloned()
            .collect();
        for id in retired {
            if let Some(metadata) = self.task_metadata.remove(&id) {
                metadata.release();
            }
        }
    }

    pub(super) fn retry_history_admission(&mut self) -> Result<(), ThreadError> {
        self.publish()?;
        self.admit_cold();
        self.release_retired_task_metadata();
        self.cold_error
            .as_ref()
            .map_or(Ok(()), |error| Err(ThreadError::Storage(error.clone())))
    }

    /// Accepts one increment of a running tool call's live output under its reliable output quota.
    ///
    /// The increment is charged against the call's reservation *before* it becomes resident: an
    /// increment the quota cannot hold is refused, the call is cancelled with the bytes it already
    /// accepted, and the earlier output is kept instead of being replaced by a larger one. The typed
    /// fault is latched right here, before the call can finish, so a Thread that truncated a tool
    /// never quietly starts more work while the tool is still wrapping up.
    ///
    /// The producer sends only what changed, so this path never re-reads or re-copies the accumulated
    /// output: the owner appends one shared chunk, or takes the producer's bounded window as a whole
    /// replacement, and publishes the newer snapshot by cloning `Arc`s.
    ///
    /// Two distinct ceilings can refuse an increment, and both cancel the call with the bytes already
    /// accepted and latch a typed pressure fault, but they bound different things:
    ///
    /// - The [`crate::model::MAX_TOOL_PROGRESS_BYTES`] live-window ceiling and the
    ///   [`crate::model::MAX_TOOL_PROGRESS_PARTS`] identity ceiling bound the *observed* window this
    ///   session holds. A producer that would exceed them is not rolling its window over as the port
    ///   requires, so it is cancelled rather than allowed to keep producing output the owner would
    ///   silently drop. This never charges or releases the durable reservation.
    /// - The call's reliable output reservation (`OutputBudget`) bounds the bytes the durable queue
    ///   may retain. Its accounting is owned by the writer, not by this path.
    pub(super) fn report_tool_progress(
        &mut self,
        caller: String,
        executor: crate::tool::opaque::ExecutionAuthority,
        update: crate::model::ToolProgressUpdate,
    ) -> Result<(), ThreadError> {
        if self.state.lifecycle != ThreadLifecycle::Open || self.interrupt.is_closing() {
            return Err(ThreadError::Closed);
        }
        if !self
            .state
            .tasks
            .get(&caller)
            .is_some_and(|task| task.status == task::TaskStatus::Running)
        {
            return Err(ThreadError::TaskAccessExpired);
        }
        if !executor.remains_authorized(&self.tools) {
            return Err(ThreadError::ToolPermissionRevoked);
        }
        let accepted = match self.state.tool_progress.get(&caller) {
            Some(current) => current.bytes_after(&update),
            None => crate::model::ToolProgress::default().bytes_after(&update),
        };
        let parts = match self.state.tool_progress.get(&caller) {
            Some(current) => current.parts_after(&update),
            None => 1,
        };
        if accepted > crate::model::MAX_TOOL_PROGRESS_BYTES
            || parts > crate::model::MAX_TOOL_PROGRESS_PARTS
        {
            // The live-output window this session can observe is exhausted: the producer is emitting
            // more than the owner can hold. This is a core semantic ceiling on the *observed* window,
            // distinct from the reliable output budget (a reservation this path never charges or
            // releases, and whose canonical/archive accounting belongs to the writer). A tool that
            // keeps producing output the owner can no longer accept must not be quietly ignored, so
            // cancel the call with the bytes already accepted — they stay resident — and latch the
            // same typed output-pressure fault the reliable-budget refusal uses, so the Thread fails
            // closed and pauses further admission instead of letting a runaway producer run on.
            if let Some(token) = self.executions.token(&caller) {
                token.cancel();
            }
            let limit = if accepted > crate::model::MAX_TOOL_PROGRESS_BYTES {
                crate::model::MAX_TOOL_PROGRESS_BYTES
            } else {
                crate::model::MAX_TOOL_PROGRESS_PARTS as u64
            };
            let resident = self
                .state
                .tool_progress
                .get(&caller)
                .map_or(0, crate::model::ToolProgress::bytes);
            self.latch_output_budget_fault(&caller, resident, limit);
            return Err(ThreadError::InvalidOutput);
        }
        let refused = match self.operation_budgets.get(&caller) {
            Some(budget) => budget.charge(accepted).is_err(),
            // No reservation to charge: this backend has no reliable budget, and the preview is
            // still bounded by the producer's own process-side output cap.
            None => false,
        };
        if refused {
            // Cancel the operation with the bytes it already accepted; the earlier preview stays.
            if let Some(token) = self.executions.token(&caller) {
                token.cancel();
            }
            // Publish the typed fault the moment the preview is refused. A tool that keeps wrapping
            // up after this must not hold the fault — and the admission block that goes with it —
            // invisible until it happens to commit; the owner is the single publisher, so this rides
            // the same latch the release path uses and repeating it there is a no-op.
            let refusal = self
                .operation_budgets
                .get(&caller)
                .and_then(|budget| budget.refusal());
            if let Some((accepted, limit)) = refusal {
                self.latch_output_budget_fault(&caller, accepted, limit);
            }
            return Err(ThreadError::InvalidOutput);
        }
        let next = match self.state.tool_progress.get(&caller) {
            Some(current) => current.applied(&update),
            None => crate::model::ToolProgress::default().applied(&update),
        };
        self.state.tool_progress.insert(caller, next);
        self.publish_snapshot();
        Ok(())
    }

    /// Latches a producer's typed reliable-output failure the moment the tool reports it.
    ///
    /// A capture write or archive that could not be stored is a fact about accepted output, not about
    /// the call's final result: reporting it through the running call's own reliable channel latches
    /// the fault — and blocks other model/tool admission — before the call returns, instead of waiting
    /// for `execute` to unwind. The obligation the fault carries is kept under this generation, so the
    /// pause stays until that same obligation is retried and its bytes really stored. The latch is
    /// idempotent, so a producer that reports the same fault again (or the return path that sees it a
    /// second time) is a no-op.
    pub(super) fn report_tool_output_storage_fault(
        &mut self,
        caller: String,
        executor: crate::tool::opaque::ExecutionAuthority,
        fault: Arc<cold::OutputStorageFault>,
    ) -> Result<(), ThreadError> {
        if self.state.lifecycle != ThreadLifecycle::Open || self.interrupt.is_closing() {
            return Err(ThreadError::Closed);
        }
        if !self
            .state
            .tasks
            .get(&caller)
            .is_some_and(|task| task.status == task::TaskStatus::Running)
        {
            return Err(ThreadError::TaskAccessExpired);
        }
        if !executor.remains_authorized(&self.tools) {
            return Err(ThreadError::ToolPermissionRevoked);
        }
        self.latch_storage_fault(fault.kind, fault.source.clone(), fault.obligation.clone());
        Ok(())
    }

    fn stage_tool_execution(
        &mut self,
        completion: ToolExecutionCompletion,
    ) -> Result<crate::tool::ToolOutput, ThreadError> {
        let (mut output, mut outcome) = observed_completion(&completion);
        let ToolExecutionCompletion {
            call, cancellation, ..
        } = completion;
        let id = call.call.call_id.clone();
        // A producer that could not store the output it was streaming reports its own typed storage
        // failure through the tool boundary. Latch the exact category it named before the failure is
        // delivered, so the Thread pauses further admission instead of continuing as if the capture
        // had succeeded; the accepted output still rides along with the failed result.
        let authorized = call.executor.remains_authorized(&self.tools);
        if authorized
            && let ToolOutcome::Failed(error) = &outcome
            && let Some(fault) = error
                .source
                .downcast_ref::<crate::thread::cold::OutputStorageFault>()
        {
            self.latch_storage_fault(fault.kind, fault.source.clone(), fault.obligation.clone());
        }
        if cancellation.is_cancelled() {
            outcome = ToolOutcome::Cancelled;
        }
        let controls = output.control() != crate::tool::ToolControl::Continue
            || !output.extension_mutations().is_empty()
            || !output.revealed_tools().is_empty();
        if matches!(outcome, ToolOutcome::Succeeded) && controls && !authorized {
            outcome = ToolOutcome::Failed(Arc::new(crate::tool::opaque::ToolError::new(
                ThreadError::ToolPermissionRevoked,
            )));
        }

        if matches!(outcome, ToolOutcome::Succeeded)
            && let Err(error) = self.tools.validate_reveal(output.revealed_tools())
        {
            outcome = ToolOutcome::Failed(Arc::new(crate::tool::opaque::ToolError::new(error)));
        }
        let interaction_id = crate::tool::opaque::tool_interaction_id(&id);
        if matches!(outcome, ToolOutcome::Succeeded)
            && output.interaction().is_some()
            && self.state.interactions.contains_key(&interaction_id)
        {
            outcome = ToolOutcome::Failed(Arc::new(crate::tool::opaque::ToolError::new(
                ThreadError::InvalidIdentity,
            )));
        }
        if matches!(outcome, ToolOutcome::Succeeded) {
            let mut candidate = self.state.clone();
            let admitted = (|| {
                super::extensions::stage_extensions(
                    &mut candidate,
                    output.extension_mutations().to_vec(),
                )?;
                if let Some(payload) = output.interaction() {
                    let now = crate::time::unix_seconds();
                    let record = interactions::InteractionRecord {
                        created_at: now,
                        updated_at: now,
                        continuation_id: None,
                        request: interactions::InteractionRequest {
                            id: interaction_id.clone(),
                            turn_id: call.turn_id.clone(),
                            payload: payload.clone(),
                        },
                        revision: 1,
                        state: interactions::InteractionState::Pending,
                        extension_mutations: Vec::new(),
                    };
                    candidate
                        .interactions
                        .insert(interaction_id, record.clone());
                    let mut changes = candidate.interaction_changes.to_vec();
                    changes.push(record);
                    candidate.interaction_changes = changes.into();
                }
                candidate.interaction_collection_revision_for(
                    &self.published,
                    &candidate.interactions,
                    &candidate.permissions,
                )?;
                Ok::<_, ThreadError>(())
            })();
            match admitted {
                Ok(()) => self.state = candidate,
                Err(error) => {
                    outcome =
                        ToolOutcome::Failed(Arc::new(crate::tool::opaque::ToolError::new(error)))
                }
            }
        }
        annotate_failure_context(&mut output, &outcome);
        let delivered_context = model_delivery_context(&output, &outcome);
        let task = self
            .state
            .tasks
            .get(&format!("task:{id}"))
            .cloned()
            .ok_or(ThreadError::InvalidIdentity)?;
        let (target, delivered_context) = if let Some(parent_call_id) = call.parent_call_id {
            (ToolDeliveryTarget::Nested { parent_call_id }, Vec::new())
        } else if task.acknowledgement.is_some() {
            let context = super::background::result_context(
                &task,
                task::TaskStatus::from_outcome(&outcome),
                delivered_context,
            );
            let message_id = super::background::append_result_message(
                &mut self.state,
                &task,
                &output,
                context.clone(),
            )?;
            (ToolDeliveryTarget::Inbox { message_id }, context)
        } else {
            let record_id = super::background::unique_id(
                &format!("tool-result:{id}"),
                self.state
                    .context
                    .records
                    .iter()
                    .map(|record| record.id.as_str()),
            )?;
            current::pair_known_call_result(
                &mut self.state.context,
                ContextRecord {
                    id: record_id,
                    turn_id: Some(call.turn_id),
                    source: ContextSource::ToolResult {
                        call_id: id.clone(),
                        tool_id: call.call.tool_id.clone(),
                    },
                    content: delivered_context.clone(),
                    tool_calls: Vec::new(),
                },
            )
            .map_err(|error| ThreadError::CurrentResume(Arc::new(error)))?;
            (ToolDeliveryTarget::CallResult, delivered_context)
        };
        let mut deliveries = self.state.deliveries.to_vec();
        deliveries.push(ToolDelivery {
            target,
            call_id: id.clone(),
            tool_id: call.call.tool_id,
            output: output.clone(),
            delivered_context,
            outcome: outcome.clone(),
        });
        self.state.deliveries = deliveries.into();
        self.finish_task(&id, &outcome)?;
        self.settle_execution_permission(&id)?;
        if matches!(outcome, ToolOutcome::Succeeded) && !output.revealed_tools().is_empty() {
            // Discovery changes the manager used by freeze(), not just the snapshot. Reserve every
            // resource cut before applying that control; the remaining synchronous publish sees the
            // same collection and cannot fail its revision preflight after discovery has escaped.
            self.state.interaction_collection_revision_for(
                &self.published,
                &self.state.interactions,
                &self.state.permissions,
            )?;
            self.tools.reveal(output.revealed_tools())?;
            self.state.discovered_tools = self.tools.discovery();
        }

        match outcome {
            ToolOutcome::Succeeded => Ok(output),
            ToolOutcome::Interrupted | ToolOutcome::Cancelled => Err(ThreadError::Cancelled),
            ToolOutcome::Failed(error) => Err(ThreadError::Tool(error)),
        }
    }
}

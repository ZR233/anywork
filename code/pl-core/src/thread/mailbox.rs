//! Bounded owner commands that cannot modify an admitted model input.
use super::*;

#[derive(Debug)]
pub(super) enum OutputRetryReply {
    Finished(Result<(), ThreadError>),
    /// Another original retry still owns the I/O. Re-enter this same bounded mailbox after it
    /// settles, preserving serial retry semantics without retaining a list of reply waiters.
    Waiting(CancellationToken),
}

#[derive(Debug)]
pub(super) enum MailboxCommand {
    ReadCurrent {
        captured: Option<current::CapturedStream>,
        reply: oneshot::Sender<Result<current::CurrentRead, current::CurrentError>>,
    },
    InvokeNested {
        caller: String,
        executor: crate::tool::opaque::ExecutionAuthority,
        tool_id: String,
        arguments: OpaquePayload,
        cancellation: CancellationToken,
        reply: oneshot::Sender<Result<crate::tool::ToolOutput, ThreadError>>,
    },
    ContinueInput(
        input::ThreadInput,
        input::InputDriverOptions,
        oneshot::Sender<Result<input::InputRecord, ThreadError>>,
    ),
    ContinueMessage(
        inbox::ThreadMessage,
        input::InputDriverOptions,
        Option<String>,
        oneshot::Sender<Result<u64, ThreadError>>,
    ),
    Resume(
        ResumeRequest,
        input::InputDriverOptions,
        oneshot::Sender<Result<ContinuationOperation, ThreadError>>,
    ),
    ReadResume(
        ResumeRequest,
        oneshot::Sender<Result<ContinuationRead, ThreadError>>,
    ),
    QueueRuntimeFacts(Vec<RuntimeFact>, oneshot::Sender<Result<(), ThreadError>>),
    /// One accepted increment of a running tool call's live output.
    ///
    /// The command carries only what changed — one chunk, or the whole bounded window after the
    /// producer rolled over — so a progress report never ships the accumulated text back to the
    /// owner.
    ToolProgress {
        caller: String,
        executor: crate::tool::opaque::ExecutionAuthority,
        update: crate::model::ToolProgressUpdate,
        reply: oneshot::Sender<Result<(), ThreadError>>,
    },
    /// A running tool's accepted output could not be stored; latch the typed fault now.
    ///
    /// The producer reports this through the same reliable, bounded channel it already uses for
    /// progress, so a capture write or archive that failed stops other model/tool admission before
    /// the call returns instead of only when `execute` unwinds. The fault keeps its
    /// [`crate::thread::cold::OutputRetryObligation`], so the pause stays until that exact obligation
    /// is retried and its bytes really stored.
    ToolOutputStorageFault {
        caller: String,
        executor: crate::tool::opaque::ExecutionAuthority,
        fault: Arc<cold::OutputStorageFault>,
        reply: oneshot::Sender<Result<(), ThreadError>>,
    },
    InstallRuntimeBundle(
        Box<RuntimeBundle>,
        crate::tool::opaque::RegistrationBatch,
        oneshot::Sender<Result<RuntimeBundleReceipt, ThreadError>>,
    ),
    RuntimeAuthorizationChanged,
    BeginIdleClose(oneshot::Sender<bool>),
    RetryToolCleanup(oneshot::Sender<Result<(), ThreadError>>),
    RetireTools(
        crate::tool::opaque::RegistrationBatch,
        oneshot::Sender<Result<(), ThreadError>>,
    ),
    InterruptTurn {
        expected: Option<String>,
        reply: oneshot::Sender<Result<bool, ThreadError>>,
    },
    /// Stops exactly the named execution, including one that is still preparing.
    InterruptExecution {
        expected: String,
        reply: oneshot::Sender<Result<bool, ThreadError>>,
    },
    CancelRunningTurn {
        expected: String,
        reply: oneshot::Sender<Result<bool, ThreadError>>,
    },
    SubmitInput(
        input::InputSubmission,
        oneshot::Sender<Result<input::InputRecord, ThreadError>>,
    ),
    RequestPermission {
        caller: String,
        authority: crate::tool::opaque::ExecutionAuthority,
        payload: OpaquePayload,
        reply: oneshot::Sender<Result<permissions::PermissionRecord, ThreadError>>,
    },
    ResolvePermission(
        permissions::PermissionResolution,
        oneshot::Sender<Result<permissions::PermissionRecord, ThreadError>>,
    ),
    RecordTaskObservation {
        caller: String,
        payload: OpaquePayload,
        reply: oneshot::Sender<Result<(), ThreadError>>,
    },
    ValidateExecution {
        caller: String,
        executor: crate::tool::opaque::ExecutionAuthority,
        reply: oneshot::Sender<Result<(), ThreadError>>,
    },
    ResumeInputs(
        input::InputDriverOptions,
        oneshot::Sender<Result<(), ThreadError>>,
    ),
    PauseInputs(oneshot::Sender<()>),
    Input(
        input::ThreadInput,
        Option<input::InputDriverOptions>,
        oneshot::Sender<Result<input::InputRecord, ThreadError>>,
    ),
    DiscardInput(
        String,
        oneshot::Sender<Result<input::InputRecord, ThreadError>>,
    ),
    RetryHistoryAdmission(oneshot::Sender<Result<(), ThreadError>>),
    /// Continues new model/tool admission after a hard storage fault was recovered.
    ///
    /// The explicit resume must reach an owner that is already *inside* a running Turn: a paused
    /// Turn waits at a storage safety point (`await_storage_admission`) and only services this
    /// mailbox, so a resume that only travelled the outer command channel could never release the
    /// pause it was sent to release. Routing it here keeps one path for both idle and in-flight
    /// owners instead of two ladders with different reachability.
    ResumeStorage {
        generation: u64,
        reply: oneshot::Sender<Result<(), ThreadError>>,
    },
    /// Re-runs the accepted output the current fault owes and clears the obligation on success.
    ///
    /// Like the resume control, it must reach an owner that is already inside a running or paused
    /// Turn, so it travels this mailbox. It only clears the obligation; the generation, backend
    /// verdict and durability fence are still verified by the explicit resume, so this is an
    /// idempotent retry rather than a release.
    RetryOutputStorage(oneshot::Sender<OutputRetryReply>),
    /// Makes every already-published fact durable, keeping the target fixed at request time.
    ///
    /// An explicit flush must reach an owner that is already *inside* a running or paused Turn, so
    /// it travels this mailbox like the resume control instead of the outer command channel: a
    /// paused Turn only services this mailbox, and a flush waiting on the outer channel there would
    /// wait for a Turn that cannot end on its own. The target is the admitted watermark this owner
    /// has when it handles the request, so a later admission never extends the barrier.
    Flush(oneshot::Sender<Result<(), ThreadError>>),
    ToolCancelTask {
        caller: String,
        authorization: Option<crate::tool::opaque::ToolAuthorization>,
        target: String,
        reply: oneshot::Sender<Result<task::TaskCancellationReceipt, ThreadError>>,
    },
    CancelTask(
        String,
        oneshot::Sender<Result<task::TaskCancellationReceipt, ThreadError>>,
    ),
    Register(
        Option<u64>,
        crate::tool::opaque::RegistrationBatch,
        oneshot::Sender<Result<(), ThreadError>>,
    ),
    Message(
        inbox::ThreadMessage,
        Option<input::InputDriverOptions>,
        oneshot::Sender<Result<u64, ThreadError>>,
    ),
    MessageWithExtensions {
        message: inbox::ThreadMessage,
        mutations: Vec<extensions::ExtensionMutation>,
        reply: oneshot::Sender<Result<u64, ThreadError>>,
    },
    /// Host-owned delivery markers must commit before their message is admitted. An active tool
    /// can be waiting for that message, so routing this through the idle-only command queue deadlocks.
    Extensions(
        Vec<extensions::ExtensionMutation>,
        oneshot::Sender<
            Result<std::collections::BTreeMap<String, extensions::ExtensionRecord>, ThreadError>,
        >,
    ),
    WakeAcceptedMessage {
        id: String,
        sequence: u64,
        options: input::InputDriverOptions,
        reply: oneshot::Sender<Result<bool, ThreadError>>,
    },
}

impl Owner {
    pub(super) fn process_mailbox(&mut self, command: MailboxCommand) {
        match command {
            MailboxCommand::ReadCurrent { captured, reply } => {
                let _ = reply.send(self.read_current(captured));
            }
            MailboxCommand::InvokeNested {
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
            MailboxCommand::ContinueInput(input, options, reply) => {
                let _ = reply.send(self.continue_input(input, options));
            }
            MailboxCommand::ContinueMessage(message, options, receipt, reply) => {
                let _ = reply.send(self.continue_message(message, options, receipt.as_deref()));
            }
            MailboxCommand::Resume(request, options, reply) => {
                let _ = reply.send(self.resume(request, options));
            }
            MailboxCommand::ReadResume(request, reply) => {
                let _ = reply.send(self.read_resume(&request));
            }
            MailboxCommand::InstallRuntimeBundle(update, batch, reply) => {
                // The managed sender closes a batch refused before handoff. During shutdown
                // the existing ToolManager may already be owned by its close future.
                let result = if self.interrupt.is_closing()
                    || self.state.lifecycle != ThreadLifecycle::Open
                {
                    Err(ThreadError::Closed)
                } else {
                    self.queue_runtime_bundle(*update, batch.take().unwrap_or_default())
                };
                let _ = reply.send(result);
            }
            MailboxCommand::RuntimeAuthorizationChanged => {
                if let Err(error) = self.retire_revoked_runtime_tools() {
                    self.fail_owner_work(error);
                }
            }
            MailboxCommand::QueueRuntimeFacts(facts, reply) => {
                let _ = reply.send(self.queue_runtime_facts(facts));
            }
            MailboxCommand::RetryToolCleanup(reply) => {
                self.tools.retry_cleanup();
                self.retry_retired_runtime_models();
                self.publish_snapshot();
                let _ = reply.send(Ok(()));
            }
            MailboxCommand::RetireTools(batch, reply) => {
                let tools = batch.take().unwrap_or_default();
                self.tools.retain_candidates(&tools);
                drop(tools);
                self.publish_snapshot();
                let _ = reply.send(Ok(()));
            }
            MailboxCommand::ToolProgress {
                caller,
                executor,
                update,
                reply,
            } => {
                let result = self.report_tool_progress(caller, executor, update);
                let _ = reply.send(result);
            }
            MailboxCommand::ToolOutputStorageFault {
                caller,
                executor,
                fault,
                reply,
            } => {
                let result = self.report_tool_output_storage_fault(caller, executor, fault);
                let _ = reply.send(result);
            }
            MailboxCommand::BeginIdleClose(reply) => {
                let idle = self.active_inputs.is_empty()
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
                            self.policy.fail(Arc::new(error));
                            false
                        }
                    }
                } else {
                    false
                };
                let _ = reply.send(idle);
            }

            MailboxCommand::CancelRunningTurn { expected, reply } => {
                let running = self
                    .state
                    .turns
                    .iter()
                    .any(|turn| turn.state == TurnState::Running && turn.turn_id == expected);
                let result = if running {
                    self.interrupted_turn = Some(expected.clone());
                    let result = self.cancel_turn_tasks(&expected);
                    // Internal draining preserves the execution policy; a later explicit Stop
                    // still advances the stop generation and wins over this transition.
                    let interrupted = self.active.as_ref().is_some_and(|run| {
                        run.input.cancellation.cancel();
                        true
                    });
                    self.publish_snapshot();
                    result.map(|()| interrupted)
                } else {
                    Ok(false)
                };
                let _ = reply.send(result);
            }
            MailboxCommand::InterruptTurn { expected, reply } => {
                let active = self
                    .state
                    .turns
                    .iter()
                    .rev()
                    .find(|turn| turn.state == TurnState::Running)
                    .map(|turn| turn.turn_id.clone())
                    .or_else(|| self.interrupted_turn.clone());
                let result = match active {
                    Some(turn_id) if expected.as_ref().is_some_and(|id| id != &turn_id) => {
                        Err(ThreadError::InvalidIdentity)
                    }
                    Some(turn_id) => {
                        self.interrupted_turn = Some(turn_id.clone());
                        self.pause_inputs();
                        let result = self.cancel_turn_tasks(&turn_id);
                        let interrupted = self.interrupt.interrupt();
                        self.publish_snapshot();
                        result.map(|()| interrupted)
                    }
                    None => {
                        self.pause_inputs();
                        self.publish_snapshot();
                        Ok(false)
                    }
                };
                let _ = reply.send(result);
            }

            MailboxCommand::InterruptExecution { expected, reply } => {
                // The named execution is compared with the one this owner really owns. A stop for a
                // finished or replaced execution is an outdated identity, never "stop whatever runs
                // now": the caller asked for exactly one generation, and stopping a newer one would
                // cancel work it never named.
                let current = self.state.execution.clone();
                let result = match current {
                    Some(execution) if execution.id == expected => {
                        let turn_id = execution.turn_id.clone();
                        if let Some(execution) = self.state.execution.as_mut() {
                            execution.phase = ExecutionPhase::Stopping;
                        }
                        self.pause_inputs();
                        // The point is formed before cancellation settles so the owed work is a
                        // committed fact even if cleanup has to wait for a running tool.
                        let source = turn_id
                            .as_ref()
                            .map_or_else(|| "execution".to_owned(), |id| format!("turn:{id}"));
                        self.form_continuation(
                            ContinuationReason::UserStop,
                            turn_id.clone(),
                            &source,
                        );
                        let tasks = turn_id.as_ref().map_or(Ok(()), |turn_id| {
                            self.interrupted_turn = Some(turn_id.clone());
                            self.cancel_turn_tasks(turn_id)
                        });
                        let cancelled = self.interrupt.interrupt();
                        self.publish().and(tasks).map(|()| cancelled)
                    }
                    Some(_) | None => Err(ThreadError::InvalidIdentity),
                };
                let _ = reply.send(result);
            }

            MailboxCommand::SubmitInput(submission, reply) => {
                let result = self.accept_input_with_policy(submission.input, submission.policy);
                if result
                    .as_ref()
                    .is_ok_and(|record| record.state == input::InputState::Pending)
                    && let Some(options) = submission.drive
                    && let Err(error) = self.resume_inputs(options)
                {
                    self.policy.fail(Arc::new(error));
                    self.publish_snapshot();
                }
                let _ = reply.send(result);
            }
            MailboxCommand::RequestPermission {
                caller,
                authority,
                payload,
                reply,
            } => {
                let _ = reply.send(self.request_execution_permission(caller, authority, payload));
            }
            MailboxCommand::ResolvePermission(resolution, reply) => {
                let _ = reply.send(self.resolve_execution_permission(resolution));
            }
            MailboxCommand::RecordTaskObservation {
                caller,
                payload,
                reply,
            } => {
                // Cancellation does not erase already incurred observations. The exact task must
                // still be running; this operation never grants permission to execute a tool.
                let result = if !self
                    .state
                    .tasks
                    .get(&caller)
                    .is_some_and(|task| task.status == task::TaskStatus::Running)
                {
                    Err(ThreadError::TaskAccessExpired)
                } else {
                    let id = format!("tool-observation:{}", payload.format());
                    let expected_revision =
                        self.state.extensions.get(&id).map(|record| record.revision);
                    self.mutate_extensions(vec![extensions::ExtensionMutation::Put {
                        id,
                        expected_revision,
                        payload,
                    }])
                    .map(|_| ())
                };
                let _ = reply.send(result);
            }
            MailboxCommand::ValidateExecution {
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
            MailboxCommand::ResumeInputs(options, reply) => {
                let _ = reply.send(self.resume_inputs(options));
            }
            MailboxCommand::PauseInputs(reply) => {
                self.pause_inputs();
                let _ = reply.send(());
            }
            MailboxCommand::Input(input, drive, reply) => {
                let result = self.accept_input(input);
                if result
                    .as_ref()
                    .is_ok_and(|record| record.state == input::InputState::Pending)
                    && let Some(options) = drive
                    && let Err(error) = self.resume_inputs(options)
                {
                    // Admission is already committed: report its receipt even if close raced the drive request.
                    self.policy.fail(Arc::new(error));
                    self.publish_snapshot();
                }
                let _ = reply.send(result);
            }
            MailboxCommand::DiscardInput(id, reply) => {
                let _ = reply.send(self.discard_input(&id));
            }
            MailboxCommand::RetryHistoryAdmission(reply) => {
                let _ = reply.send(self.retry_history_admission());
            }
            MailboxCommand::ResumeStorage { generation, reply } => {
                let result = if self.interrupt.is_closing() {
                    Err(ThreadError::Closed)
                } else {
                    self.resume_storage(generation)
                };
                let _ = reply.send(result);
            }
            MailboxCommand::ToolCancelTask {
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
            MailboxCommand::CancelTask(id, reply) => {
                let _ = reply.send(self.cancel_task(&id));
            }
            MailboxCommand::Register(expected, tools, reply) => {
                let tools = tools.take().unwrap_or_default();
                self.tools.retain_candidates(&tools);
                let result = if self.state.lifecycle == ThreadLifecycle::Open
                    && !self.interrupt.is_closing()
                {
                    if let Some(expected) = expected
                        && expected != self.state.extension_sequence
                    {
                        drop(tools);
                        self.publish_snapshot();
                        let _ = reply.send(Err(ThreadError::ExtensionSequenceConflict {
                            expected,
                            actual: self.state.extension_sequence,
                        }));
                        return;
                    }
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
            MailboxCommand::Message(message, drive, reply) => {
                let result = if self.interrupt.is_closing() {
                    Err(ThreadError::Closed)
                } else {
                    self.receive_message(message, drive, None)
                };
                let _ = reply.send(result);
            }
            MailboxCommand::MessageWithExtensions {
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
            MailboxCommand::Extensions(mutations, reply) => {
                let result = if self.interrupt.is_closing() {
                    Err(ThreadError::Closed)
                } else {
                    self.mutate_extensions(mutations)
                };
                let _ = reply.send(result);
            }
            MailboxCommand::WakeAcceptedMessage {
                id,
                sequence,
                options,
                reply,
            } => {
                let _ = reply.send(self.wake_accepted_message(&id, sequence, options));
            }
            MailboxCommand::Flush(reply) => self.start_flush(reply),
            // Handled by `dispatch_mailbox`, which is the only place that may await the machine.
            MailboxCommand::RetryOutputStorage(reply) => {
                self.start_output_retry(reply);
            }
        }
    }
}

//! Handle operations submit bounded priority commands; only the owner mutates Thread state.
use super::*;

enum InitialState {
    FreshCurrent(Box<current::ThreadCurrent>),
    RestoredCurrent(Box<current::ThreadCurrent>),
}

impl ThreadHandle {
    /// Returns whether both handles address the same physical owner incarnation.
    pub fn same_instance(&self, other: &Self) -> bool {
        self.user_commands.same_channel(&other.user_commands)
    }

    /// Subscribes to the unified CoreEvent broadcast stream (durable commits + live events).
    pub fn subscribe_events(
        &self,
    ) -> tokio::sync::broadcast::Receiver<super::super::events::CoreEvent> {
        self.core_events.subscribe()
    }

    /// Releases immutable exports only after the independent history consumer accepted them.
    /// No current save, dirty notification, execution permission or legacy cold fence is advanced.
    /// The retained window can also be released after the physical owner has closed.
    pub fn release_history_through(&self, through: u64) -> Result<(), ThreadError> {
        self.effect_window.release_export_through(through)
    }

    /// Reads a bounded page of the Current owner's original immutable history exports.
    /// The consumer releases them explicitly after its reliable queue accepts ownership.
    pub fn history_export_page(
        &self,
        after: u64,
        limit: std::num::NonZeroUsize,
    ) -> Result<Vec<Arc<HistoryExport>>, ThreadError> {
        self.effect_window.current_page(after, limit.get())
    }

    /// Continues a restored, paused current using the owner's currently configured services.
    /// Saved model parameters remain diagnostic observations; they do not bind the new request.
    pub async fn resume_current(
        &self,
        turn_id: String,
        max_model_steps: ModelStepLimit,
        cancellation: CancellationToken,
    ) -> Result<TurnCompletion, current::CurrentError> {
        if turn_id.is_empty() {
            return Err(current::CurrentError::InvalidIdentity);
        }
        let input = TurnInput {
            attempt_prefix: turn_id.clone(),
            turn_id,
            content: Vec::new(),
            max_model_steps,
            cancellation,
        };
        let (reply, response) = oneshot::channel();
        self.user_commands
            .send(UserCommand::CurrentResume {
                epoch: self.runtime_epoch,
                expected_stop_generation: self.interrupt.stops(),
                input,
                reply,
            })
            .await
            .map_err(|_| current::CurrentError::Closed)?;
        response.await.map_err(|_| current::CurrentError::Closed)?
    }

    /// Starts one owner with a fresh, exclusively owned model session.
    ///
    /// # Errors
    /// Rejects an empty Thread identity before spawning the owner.
    pub fn start(id: String, model: DynModelSession) -> Result<Self, ThreadError> {
        if id.is_empty() {
            return Err(ThreadError::InvalidIdentity);
        }
        let current = current::ThreadCurrent::new(id.clone(), current::RuntimeEpoch::new());
        Self::spawn_owner(
            id,
            Some(model),
            InitialState::FreshCurrent(Box::new(current)),
            false,
        )
    }

    /// Starts one fresh Current owner under a new runtime epoch. A resource-only owner may
    /// install its model later; absence of a model does not make a new object a paused restore.
    pub fn start_current(
        id: String,
        model: Option<DynModelSession>,
    ) -> Result<Self, current::CurrentError> {
        let current = current::ThreadCurrent::new(id.clone(), current::RuntimeEpoch::new());
        Self::spawn_owner(
            id,
            model,
            InitialState::FreshCurrent(Box::new(current)),
            true,
        )
        .map_err(|error| current::CurrentError::Owner(Arc::new(error)))
    }

    /// Installs only logical current data under a fresh paused owner. No history is read, no old
    /// terminal facts are synthesized, and no model/tool work starts. Pass `None` to open no session.
    pub fn restore_current(
        current: current::ThreadCurrent,
        model: Option<DynModelSession>,
    ) -> Result<Self, current::CurrentError> {
        let id = current.thread_id.clone();
        let current = current.activate_paused(&id)?;
        Self::spawn_owner(
            id,
            model,
            InitialState::RestoredCurrent(Box::new(current)),
            true,
        )
        .map_err(|error| current::CurrentError::Owner(Arc::new(error)))
    }

    fn spawn_owner(
        id: String,
        model: Option<DynModelSession>,
        initial: InitialState,
        is_current_owner: bool,
    ) -> Result<Self, ThreadError> {
        if id.is_empty() {
            return Err(ThreadError::InvalidIdentity);
        }
        let resumed = matches!(&initial, InitialState::RestoredCurrent(_));
        let current_paused = matches!(&initial, InitialState::RestoredCurrent(_));
        let (published, state, restored_current) = match initial {
            InitialState::FreshCurrent(current) | InitialState::RestoredCurrent(current) => {
                let state = current.state.to_paused_snapshot();
                (state.clone(), state, Some(current))
            }
        };
        let (user_commands, user_rx) = mpsc::channel(64);
        let (events, event_rx) = mpsc::channel(128);
        let (event_bus, core_events) = super::super::events::EventBus::new();
        let completed_tasks = Arc::new(std::sync::RwLock::new(
            super::super::task_access::CompletedTaskLedger::default(),
        ));
        let interrupt = cancellation::InterruptHandle::default();
        let (publish, snapshots) = watch::channel(super::super::subscription::OwnerPublication {
            snapshot: published.clone(),
            binding: None,
        });
        let (output_refusals, output_refusal_rx) =
            watch::channel::<Option<crate::model::OutputRefusal>>(None);
        let tools = crate::tool::opaque::ToolManager::with_discovery(&state.discovered_tools);
        let effect_window = Arc::new(EffectWindow::new());
        let runtime_epoch = restored_current
            .as_ref()
            .map_or_else(current::RuntimeEpoch::new, |current| {
                current.saved_runtime_epoch
            });
        let (final_current, final_current_rx) = watch::channel(None);
        let (current_dirty, current_dirty_rx) = watch::channel(0);
        let authorization_dirty = Arc::new(std::sync::atomic::AtomicBool::new(false));
        let mut owner = Owner {
            active: None,
            primary: None,
            closing: None,
            runtime_epoch,
            current_call: None,
            current_capture: None,
            current_dirty,
            current_model_running: false,
            current_snapshot_missing: false,
            is_current_owner,
            current_saved_execution: restored_current
                .as_ref()
                .filter(|_| current_paused)
                .and_then(|current| current.state.execution.clone()),
            current_saved_lifecycle: restored_current
                .as_ref()
                .filter(|_| current_paused)
                .map(|current| current.state.lifecycle),
            current_task_start_ordinal: restored_current
                .as_ref()
                .map_or(0, |current| current.state.task_start_ordinal),
            current_retired_previews: restored_current
                .as_ref()
                .map(|current| current.state.tool_previews.clone())
                .unwrap_or_default(),
            final_current,
            runtime_binding: None,
            pending_bundle: None,
            bundle_generation: 0,
            runtime_model_jobs: 0,
            retired_runtime_models: Vec::new(),
            revoked_runtime_tools: false,
            authorization_dirty: authorization_dirty.clone(),
            executing_authorities: Default::default(),
            pending_runtime_facts: Default::default(),
            context_preparation: None,
            compaction_call: None,
            pending_context_compactions: Vec::new(),
            model_progress: None,
            model_settlement_jobs: 0,
            model_settlements: Default::default(),
            effect_window: effect_window.clone(),
            permission_leases: Default::default(),
            active_inputs: Vec::new(),
            input_batch_through: None,
            frozen_turn: None,
            interrupted_turn: None,
            policy: if resumed {
                input::ExecutionPolicy::Paused(input::PauseReason::User)
            } else {
                input::ExecutionPolicy::Paused(input::PauseReason::Initial)
            },
            interrupt: interrupt.clone(),
            task_commands: events.downgrade(),
            event_bus,
            progress_tracker: Default::default(),
            completed_tasks,
            id,
            model,
            state,
            publish,
            tools,
            pending: Default::default(),
            executions: Default::default(),
            nested_replies: Default::default(),
            nested_sequence: 0,
            nested_plans: Default::default(),
            background: Default::default(),
            capacity: Default::default(),
            pending_effects: Default::default(),
            cold: None,
            cold_error: None,
            fault_fence: None,
            store_fault_generation: None,
            verified_recovery_generation: None,
            local_fault: None,
            output_obligations: Default::default(),
            output_retry_active: None,
            maintenance: Default::default(),
            tool_waiters: Default::default(),
            pressure_watch_closed: false,
            pending_output_repairs: Default::default(),
            satisfied_output_obligations: Default::default(),
            output_backpressure: false,
            threshold_paused: false,
            task_metadata: Default::default(),
            operation_budgets: Default::default(),
            output_refusals,
            output_refusal_rx,
            deferred_output_releases: Default::default(),
            pending_output_claim: None,
            model_members: None,
            pending_model_members: Vec::new(),
            pending_model_sub_attempt_settlements: Vec::new(),
            pending_model_member_starts: Vec::new(),
            pending_model_member_content_available: Vec::new(),
            pending_model_connection_events: Vec::new(),
            resources: None,
            retry_plan: None,
            published,
        };
        owner.current_call = restored_current.and_then(|current| current.model_call);
        owner.publish()?;
        owner.publish_snapshot();
        tokio::spawn(owner.run(user_rx, event_rx));
        Ok(Self {
            runtime_epoch,
            final_current: final_current_rx,
            current_dirty: current_dirty_rx,
            _lifetime: Arc::new(HandleLifetime(interrupt.clone())),
            user_commands,
            events,
            core_events,
            interrupt,
            snapshots,
            authorization_dirty,
            effect_window,
        })
    }

    /// Closes only when the owner atomically observes no active or pending work.
    ///
    /// # Errors
    /// Returns actual resource or persistence failures; a failed close remains retryable.
    pub async fn close_if_idle(&self) -> Result<bool, ThreadError> {
        if self.snapshot().lifecycle == ThreadLifecycle::Closed {
            return Ok(true);
        }
        let (reply, response) = oneshot::channel();
        self.user_commands
            .send(UserCommand::Mailbox(
                super::mailbox::MailboxCommand::BeginIdleClose(reply),
            ))
            .await
            .map_err(|_| ThreadError::Closed)?;
        if !response.await.map_err(|_| ThreadError::Closed)? {
            return Ok(false);
        }
        self.close().await?;
        Ok(true)
    }

    /// Stops the current Turn after atomically checking its expected identity and pauses queued execution.
    /// Passing no identity stops whichever Turn the owner is currently executing.
    ///
    /// # Errors
    /// Returns `InvalidIdentity` when another Turn is active, or `Closed` when the owner has exited.
    pub async fn interrupt_turn(&self, expected: Option<String>) -> Result<bool, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.user_commands
            .send(UserCommand::Mailbox(
                super::mailbox::MailboxCommand::InterruptTurn { expected, reply },
            ))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Stops exactly the named execution, including one that is still preparing.
    ///
    /// The owner compares the identity with the execution it really owns, so a superseded identity
    /// answers [`ThreadError::InvalidIdentity`] instead of stopping whatever runs now. Accepting the
    /// stop pauses the queue and forms the continuation point the settled execution leaves behind;
    /// the receipt only proves the stop was accepted, and a caller that needs completion observes the
    /// execution leaving the snapshot.
    ///
    /// # Errors
    /// Returns `InvalidIdentity` when no execution carries the identity, or `Closed` when the owner
    /// is no longer reachable.
    pub async fn interrupt_execution(
        &self,
        expected_execution_id: String,
    ) -> Result<bool, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.user_commands
            .send(UserCommand::Mailbox(
                super::mailbox::MailboxCommand::InterruptExecution {
                    expected: expected_execution_id,
                    reply,
                },
            ))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Cancels the named executing Turn while preserving the queue's paused/running policy.
    /// A completed identity or an input waiting for admission returns false without cancelling
    /// that pending admission. Hosts can therefore drain a closed Turn gate without losing inputs.
    ///
    /// # Errors
    /// Returns task cleanup errors or `Closed` when the owner is no longer reachable.
    pub async fn cancel_running_turn(&self, expected: String) -> Result<bool, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.user_commands
            .send(UserCommand::Mailbox(
                super::mailbox::MailboxCommand::CancelRunningTurn { expected, reply },
            ))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Cancels only the currently active execution generation without closing the Thread.
    /// Returns false when there is no active model/tool/Turn command.
    pub fn interrupt(&self) -> bool {
        self.interrupt.interrupt()
    }

    /// Signals global shutdown without waiting for commands, storage or resource joins.
    ///
    /// Cancels the active generation and independent background tools. Unlike [`Self::close`], this
    /// does not close the owner or publish a terminal fact: hosts must still call `close` and await
    /// its result. New execution generations inherit the shutdown signal; existing results and
    /// terminal producers remain owned until the normal close path drains them.
    pub fn request_shutdown(&self) {
        self.interrupt.request_shutdown();
    }

    /// Replaces the model of an idle standalone Thread through its package installation.
    pub async fn replace_model(
        &self,
        factory: crate::model::ModelFactory,
    ) -> Result<(), ThreadError> {
        let snapshot = self.snapshot();
        let model = RuntimeModel::new(uuid::Uuid::new_v4().to_string(), factory, None);
        let mut update = RuntimeBundle::model_only(self, &snapshot, model);
        update.require_idle = true;
        self.install_runtime_bundle(update)
            .await?
            .installed()
            .await
            .map(|_| ())
            .map_err(|error| match &*error {
                ThreadError::Model(error) => ThreadError::Model(error.clone()),
                ThreadError::Closed => ThreadError::Closed,
                ThreadError::InputRequiresIdle => ThreadError::InputRequiresIdle,
                ThreadError::StaleRuntimeBundle => ThreadError::StaleRuntimeBundle,
                _ => ThreadError::RuntimeInstallation(error),
            })
    }

    /// Installs a policy before admitting new work; running requests keep their frozen policy.
    /// # Errors
    /// Rejects a closed owner.
    pub async fn set_context_preparation(
        &self,
        preparation: Option<context_preparation::ContextPreparer>,
    ) -> Result<(), ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::ContextPreparation(preparation, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Installs the resource service lease captured by subsequent prepared model calls.
    ///
    /// # Errors
    /// Rejects a closed or closing owner.
    pub async fn set_resources(
        &self,
        resources: crate::context::ResourceAccess,
    ) -> Result<(), ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Resources(resources, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Commits application state and its model-visible facts in one atomic checkpoint.
    ///
    /// # Errors
    /// Rejects version conflicts or invalid facts without applying either half of the update.
    pub async fn update_application(
        &self,
        update: extensions::ApplicationUpdate,
    ) -> Result<ThreadSnapshot, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Application(update, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Atomically mutates producer-owned opaque records without projecting them into model context.
    /// Services an active owner through its mailbox, including while a tool awaits a message whose
    /// delivery first needs this marker. This does not start model or tool execution.
    ///
    /// # Errors
    /// Rejects stale revisions, invalid identities, overflow or a closed Thread without partial writes.
    pub async fn mutate_extensions(
        &self,
        mutations: Vec<extensions::ExtensionMutation>,
    ) -> Result<std::collections::BTreeMap<String, extensions::ExtensionRecord>, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Mailbox(
                super::mailbox::MailboxCommand::Extensions(
                    super::mailbox::ExtensionRequest::Mutate(mutations, reply),
                ),
            ))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Registers a durable auxiliary model call before sending its first request.
    pub async fn begin_auxiliary_model_call(
        &self,
        turn_id: Option<String>,
    ) -> Result<ModelSettlementPort, crate::model::ModelMemberError> {
        use crate::model::ModelMemberError;
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Mailbox(
                super::mailbox::MailboxCommand::OpenAuxiliaryModel {
                    caller: None,
                    turn_id,
                    reply,
                },
            ))
            .await
            .map_err(|_| ModelMemberError::Closed)?;
        response.await.map_err(|_| ModelMemberError::Closed)?
    }

    /// Checks the exact saved original without granting a new call or publishing an effect.
    pub async fn confirm_saved_model_settlement(
        &self,
        settlement: crate::model::ModelSubAttemptSettlement,
    ) -> Result<(), crate::model::ModelMemberError> {
        use crate::model::ModelMemberError;
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Mailbox(
                super::mailbox::MailboxCommand::VerifyModelSettlement { settlement, reply },
            ))
            .await
            .map_err(|_| ModelMemberError::Closed)?;
        super::model_settlement::await_settlement(response).await
    }

    /// Accepts a message idempotently; context is delivered only with a later model admission.
    ///
    /// # Errors
    /// Rejects changed content under an existing ID, invalid identities or a closed owner.
    pub async fn send_message(&self, message: inbox::ThreadMessage) -> Result<u64, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Mailbox(super::mailbox::MailboxCommand::Message(
                message, None, reply,
            )))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Accepts a message and commits its producer-owned records in the same owner publication.
    /// This does not request execution. A host can retain an explicit admission marker until its
    /// independent Current save succeeds, even after the bounded message ledger retires the ID.
    ///
    /// # Errors
    /// Rejects conflicting message identities, stale extension revisions and closed owners before
    /// applying either mutation.
    pub async fn send_message_with_extensions(
        &self,
        message: inbox::ThreadMessage,
        mutations: Vec<extensions::ExtensionMutation>,
    ) -> Result<u64, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Mailbox(
                super::mailbox::MailboxCommand::MessageWithExtensions {
                    message,
                    mutations,
                    reply,
                },
            ))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Delivers a runtime message and durably requests execution if it remains unconsumed.
    /// A message consumed by an already active Turn does not trigger a second invocation.
    ///
    /// # Errors
    /// Rejects conflicting identities or a closed owner before message acceptance.
    pub async fn send_message_and_resume(
        &self,
        message: inbox::ThreadMessage,
        options: input::InputDriverOptions,
    ) -> Result<u64, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Mailbox(super::mailbox::MailboxCommand::Message(
                message,
                Some(options),
                reply,
            )))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Wakes an already accepted, still unconsumed message without admitting another copy.
    /// Returns false if the message has since been consumed. The host must first prove the
    /// identity and sequence against durable history; an unknown pending identity fails closed.
    ///
    /// # Errors
    /// Rejects closed owners and pending identities that do not match the accepted message.
    pub async fn wake_accepted_message(
        &self,
        id: &str,
        sequence: u64,
        options: input::InputDriverOptions,
    ) -> Result<bool, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Mailbox(
                super::mailbox::MailboxCommand::WakeAcceptedMessage {
                    id: id.to_owned(),
                    sequence,
                    options,
                    reply,
                },
            ))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Accepts a parent-authored message, interrupts active work and continues after cleanup.
    /// Duplicate identities return the original receipt without restarting execution.
    ///
    /// # Errors
    /// Rejects conflicting identities, pending interactions and unavailable admission.
    pub async fn send_message_and_continue(
        &self,
        message: inbox::ThreadMessage,
        options: input::InputDriverOptions,
    ) -> Result<u64, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Mailbox(
                super::mailbox::MailboxCommand::ContinueMessage(message, options, None, reply),
            ))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Continues with a message while retaining its exact receipt in a caller-owned extension.
    /// A repeat reads that receipt before checking new admission or interrupting current work.
    /// The caller deletes the record after its original delivery obligation is settled.
    ///
    /// # Errors
    /// Rejects changed receipt identities and the same admission failures as
    /// [`Self::send_message_and_continue`].
    pub async fn send_message_and_continue_with_receipt(
        &self,
        message: inbox::ThreadMessage,
        options: input::InputDriverOptions,
        receipt_extension_id: String,
    ) -> Result<u64, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Mailbox(
                super::mailbox::MailboxCommand::ContinueMessage(
                    message,
                    options,
                    Some(receipt_extension_id),
                    reply,
                ),
            ))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Waits for a committed task result; cancelling this wait does not cancel the task.
    ///
    /// # Errors
    /// Rejects unknown tasks, missing terminal deliveries, cancelled waits or a lost owner.
    pub async fn wait_task(
        &self,
        id: &str,
        cancellation: CancellationToken,
    ) -> Result<ToolDelivery, ThreadError> {
        let mut snapshots = self.snapshots.clone();
        loop {
            if cancellation.is_cancelled() {
                return Err(ThreadError::Cancelled);
            }
            {
                let snapshot = snapshots.borrow_and_update();
                let task = snapshot
                    .tasks
                    .get(id)
                    .or_else(|| {
                        snapshot
                            .terminal_tasks
                            .iter()
                            .find(|record| record.id == id)
                    })
                    .ok_or(ThreadError::InvalidIdentity)?;

                if task.status != task::TaskStatus::Running {
                    // A settled result is committed history: read the resident queue while the result
                    // is still owed to model context, otherwise the exact committed delivery from the
                    // bounded live effect window. Older results are the host's calls reader.
                    let call_id = task.call_id.as_str();
                    if let Some(delivery) = snapshot
                        .deliveries
                        .iter()
                        .find(|delivery| delivery.call_id == call_id)
                    {
                        return Ok(delivery.clone());
                    }
                    return recent_effect_fact(&self.effect_window, |effect| {
                        effect
                            .deliveries
                            .iter()
                            .rev()
                            .find(|delivery| delivery.call_id == call_id)
                            .cloned()
                    })
                    .ok_or(ThreadError::InvalidOutput);
                }
            }
            tokio::select! {
                _ = cancellation.cancelled() => return Err(ThreadError::Cancelled),
                changed = snapshots.changed() => changed.map_err(|_| ThreadError::Closed)?,
            }
        }
    }

    /// Retries only result commits retained after execution, without repeating tool side effects.
    ///
    /// # Errors
    /// Returns the original commit boundary failure if the state still cannot accept the result.
    pub async fn retry_history_admission(&self) -> Result<(), ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Mailbox(
                super::mailbox::MailboxCommand::RetryHistoryAdmission(reply),
            ))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Requests cancellation of this owner's task without waiting for physical completion.
    ///
    /// # Errors
    /// Rejects unknown task identities or an unavailable owner.
    pub async fn cancel_task(
        &self,
        id: String,
    ) -> Result<task::TaskCancellationReceipt, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.user_commands
            .send(UserCommand::Mailbox(
                super::mailbox::MailboxCommand::CancelTask(id, reply),
            ))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Resolves one live execution permission without decoding its prompt payload.
    ///
    /// # Errors
    /// Rejects new decisions for stale revisions, expired tasks and replaced policies.
    /// An identical terminal decision only returns its saved receipt; it never grants a new execution lease.
    pub async fn resolve_execution_permission(
        &self,
        resolution: permissions::PermissionResolution,
    ) -> Result<permissions::PermissionRecord, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.user_commands
            .send(UserCommand::Mailbox(
                mailbox::MailboxCommand::ResolvePermission(resolution, reply),
            ))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Atomically selects queue or current-Turn delivery and records the immutable input.
    ///
    /// # Errors
    /// Rejects incompatible routing policy, duplicate identities with different content and storage pressure.
    pub async fn submit_input_with_policy(
        &self,
        submission: input::InputSubmission,
    ) -> Result<input::InputRecord, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.user_commands
            .send(UserCommand::Mailbox(mailbox::MailboxCommand::SubmitInput(
                submission, reply,
            )))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Records an opaque host interaction idempotently without parsing its contents.
    ///
    /// # Errors
    /// Rejects identity conflicts or a closed owner.
    pub async fn request_interaction(
        &self,
        request: interactions::InteractionRequest,
    ) -> Result<interactions::InteractionRecord, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::RequestInteraction(request, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Resolves an interaction and commits its actual context atomically.
    ///
    /// # Errors
    /// Rejects stale or terminal interactions, invalid context and pending tool batches.
    pub async fn resolve_interaction(
        &self,
        resolution: interactions::InteractionResolution,
    ) -> Result<interactions::InteractionRecord, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.user_commands
            .send(UserCommand::ResolveInteraction(resolution, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Cancels a pending interaction and atomically appends its cancellation context.
    /// Repeating the same successful command returns the original terminal record.
    ///
    /// # Errors
    /// Rejects stale revisions, answered interactions, pending tool batches or a closed owner.
    pub async fn cancel_interaction(
        &self,
        cancellation: interactions::InteractionCancellation,
    ) -> Result<interactions::InteractionRecord, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.user_commands
            .send(UserCommand::CancelInteraction(cancellation, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Sets admission limits for subsequent prepared calls.
    ///
    /// # Errors
    /// Returns an unavailable or closing owner.
    pub async fn set_capacity(&self, capacity: ContextCapacity) -> Result<(), ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Capacity(capacity, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Reveals deferred declarations without changing their frozen content or rebuilding instances.
    ///
    /// # Errors
    /// Rejects unknown IDs atomically or a closed owner.
    pub async fn reveal_tools(&self, ids: Vec<String>) -> Result<(), ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Reveal(ids, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Captures the owner generation and installed revision.
    pub fn runtime_bundle_base(&self, snapshot: &ThreadSnapshot) -> RuntimeBundleBase {
        RuntimeBundleBase {
            epoch: self.runtime_epoch,
            revision: snapshot.runtime_bundle.revision,
            extension_inputs: Default::default(),
        }
    }

    /// Reads the active execution binding from Core's own snapshot publication.
    pub fn runtime_binding(&self) -> RuntimeBindingReader {
        RuntimeBindingReader {
            snapshots: self.snapshots.clone(),
            commands: self.events.downgrade(),
            authorization_dirty: self.authorization_dirty.clone(),
        }
    }

    /// Transfers a candidate and its cleanup obligations to this owner. The receipt resolves
    /// at installation. An admitted request can keep using the currently installed package.
    pub async fn install_runtime_bundle(
        &self,
        mut update: RuntimeBundle,
    ) -> Result<RuntimeBundleReceipt, ThreadError> {
        let registrations = update
            .tools
            .as_mut()
            .map(|tools| std::mem::take(&mut tools.registrations))
            .unwrap_or_default();
        let batch = crate::tool::opaque::RegistrationBatch::new(registrations);
        let (reply, response) = oneshot::channel();
        let result = match self
            .events
            .send(LoopEvent::Mailbox(
                super::mailbox::MailboxCommand::InstallRuntimeBundle(
                    Box::new(update),
                    batch.clone(),
                    reply,
                ),
            ))
            .await
        {
            Ok(()) => response.await.unwrap_or(Err(ThreadError::Closed)),
            Err(_) => Err(ThreadError::Closed),
        };
        finish_tool_transfer(batch, result).await
    }

    /// Replaces this Thread's registry atomically. Pending calls keep their frozen executors.
    ///
    /// # Errors
    /// Rejects duplicate registrations or a closed owner.
    pub async fn register_tools(
        &self,
        tools: Vec<crate::tool::opaque::Registration>,
    ) -> Result<(), ThreadError> {
        let batch = crate::tool::opaque::RegistrationBatch::new(tools);
        let (reply, response) = oneshot::channel();
        let result = match self
            .events
            .send(LoopEvent::Mailbox(
                super::mailbox::MailboxCommand::Register(batch.clone(), reply),
            ))
            .await
        {
            Ok(()) => response.await.unwrap_or(Err(ThreadError::Closed)),
            Err(_) => Err(ThreadError::Closed),
        };
        finish_tool_transfer(batch, result).await
    }

    /// Retries retained tool cleanup failures without replacing the current catalog.
    /// Completion and original errors are observed through `ThreadSnapshot::tool_cleanup`.
    ///
    /// # Errors
    /// Returns `Closed` when the owner no longer accepts operations.
    pub async fn retry_tool_cleanup(&self) -> Result<(), ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Mailbox(
                super::mailbox::MailboxCommand::RetryToolCleanup(reply),
            ))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Transfers unused candidates to this owner for asynchronous cleanup, without installing them.
    ///
    /// # Errors
    /// Returns owner errors; a failed transfer returns retained cleanup through `RejectedTools`.
    pub async fn retire_tools(
        &self,
        tools: Vec<crate::tool::opaque::Registration>,
    ) -> Result<(), ThreadError> {
        let batch = crate::tool::opaque::RegistrationBatch::new(tools);
        let (reply, response) = oneshot::channel();
        let result = match self
            .events
            .send(LoopEvent::Mailbox(
                super::mailbox::MailboxCommand::RetireTools(batch.clone(), reply),
            ))
            .await
        {
            Ok(()) => response.await.unwrap_or(Err(ThreadError::Closed)),
            Err(_) => Err(ThreadError::Closed),
        };
        finish_tool_transfer(batch, result).await
    }

    /// Executes one admitted call, attaching its result to the original call and tool role.
    ///
    /// # Errors
    /// Rejects unknown or completed calls, cancellation, and tool failures.
    pub async fn execute_tool(
        &self,
        call_id: String,
        cancellation: CancellationToken,
    ) -> Result<ToolDispatch, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Execute(call_id, cancellation, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Queues the latest facts per source for the next model preparation boundary.
    /// Acceptance never mutates an already admitted model input or waits for the Turn to end.
    /// Pending facts are ephemeral; the host must resupply them after cold activation.
    ///
    /// # Errors
    /// Rejects empty or duplicate source identities and a closing owner.
    pub async fn queue_runtime_facts(&self, facts: Vec<RuntimeFact>) -> Result<(), ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Mailbox(
                super::mailbox::MailboxCommand::QueueRuntimeFacts(facts, reply),
            ))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Atomically updates only the supplied runtime fact sources, preserving all others.
    /// Empty content clears that source; an empty patch changes no source.
    ///
    /// # Errors
    /// Rejects duplicate or empty sources, pending tool calls, revision overflow and a closed owner.
    pub async fn patch_runtime_facts(
        &self,
        facts: Vec<RuntimeFact>,
    ) -> Result<ContextSnapshot, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::PatchRuntimeFacts(facts, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Supplies the complete current runtime fact set. Unchanged content is not appended again.
    /// Omitted known sources receive an invalidation record with runtime attribution.
    ///
    /// # Errors
    /// Rejects duplicate or empty source identities, revision overflow and a closed owner.
    pub async fn update_facts(
        &self,
        facts: Vec<RuntimeFact>,
    ) -> Result<ContextSnapshot, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::UpdateFacts(facts, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Forces one idle reduction using the installed preparer, preserving input and tool history.
    /// # Errors
    /// Rejects stale context, busy/closed owners, cancellation and unsuccessful compaction.
    pub async fn compact_context(
        &self,
        expected_revision: u64,
        cancellation: CancellationToken,
    ) -> Result<ContextSnapshot, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::CompactContext(
                expected_revision,
                cancellation,
                reply,
            ))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Replaces context after a successful host transformation, retaining both versions.
    /// Tool executors cannot invoke this operation through their restricted CallContext.
    ///
    /// # Errors
    /// Rejects stale revisions, duplicate records, pending tool calls or a closed owner.
    pub async fn replace_context(
        &self,
        replacement: ReplaceContext,
    ) -> Result<ContextSnapshot, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::ReplaceContext(replacement, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Installs the independent History export sink and its existing reliable-output budget.
    /// Current capture is independent of History. Normal close waits for already-incurred model
    /// settlements. The host drains the remaining History exports separately.
    pub async fn attach_history(
        &self,
        store: super::super::history_sink::HistorySinkHandle,
    ) -> Result<(), ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::AttachHistory(store, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Installs a host CoreEventSink to receive every CoreEvent directly on commit/live update.
    pub async fn attach_event_sink(
        &self,
        sink: Arc<dyn super::super::events::CoreEventSink>,
    ) -> Result<(), ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::AttachEventSink(sink, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Continues new model/tool admission after a hard storage fault was recovered.
    pub async fn resume_storage(&self, generation: u64) -> Result<(), ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Mailbox(
                super::mailbox::MailboxCommand::ResumeStorage { generation, reply },
            ))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Re-runs the accepted output the current storage fault owes, without releasing the pause.
    pub async fn retry_output_storage(&self) -> Result<(), ThreadError> {
        loop {
            let (reply, response) = oneshot::channel();
            self.events
                .send(LoopEvent::Mailbox(
                    super::mailbox::MailboxCommand::RetryOutputStorage(reply),
                ))
                .await
                .map_err(|_| ThreadError::Closed)?;
            match response.await.map_err(|_| ThreadError::Closed)? {
                super::mailbox::OutputRetryReply::Finished(result) => return result,
                super::mailbox::OutputRetryReply::Waiting(finished) => finished.cancelled().await,
            }
        }
    }

    /// Checks storage health without blocking live execution on database durability.
    pub async fn flush(&self) -> Result<(), ThreadError> {
        if self.durably_released() {
            return Ok(());
        }
        let (reply, response) = oneshot::channel();
        if self
            .user_commands
            .send(UserCommand::Mailbox(super::mailbox::MailboxCommand::Flush(
                reply,
            )))
            .await
            .is_err()
        {
            return self.settled_flush();
        }
        match response.await {
            Ok(result) => result,
            Err(_) => self.settled_flush(),
        }
    }

    /// Reports whether the owner was released after its physical close settled.
    fn durably_released(&self) -> bool {
        self.snapshot().lifecycle == ThreadLifecycle::Closed
    }

    fn settled_flush(&self) -> Result<(), ThreadError> {
        if self.durably_released() {
            Ok(())
        } else {
            Err(ThreadError::Closed)
        }
    }

    /// Subscribes to immutable live snapshots without granting mutation or lifecycle authority.
    pub fn subscribe(&self) -> ThreadSubscription {
        ThreadSubscription {
            snapshots: self.snapshots.clone(),
            initial: true,
        }
    }

    /// Reads the transient live effect window after a known sequence.
    ///
    /// # Errors
    /// Rejects a future watermark. Closing execution does not revoke read access.
    pub async fn effect_page(
        &self,
        after: u64,
        limit: std::num::NonZeroUsize,
    ) -> Result<Vec<Arc<ThreadEffectBatch>>, ThreadError> {
        if after > self.snapshot().commit_sequence {
            return Err(ThreadError::InvalidContext);
        }
        match self.effect_window.page_after(after, limit.get()) {
            WindowPage::Page(page) => Ok(page),
            WindowPage::Gap => Err(ThreadError::InvalidContext),
        }
    }

    /// Returns every commit still retained by the transient live effect window.
    ///
    /// # Errors
    /// This in-memory read currently cannot fail.
    pub async fn effects(&self) -> Result<Vec<Arc<ThreadEffectBatch>>, ThreadError> {
        Ok(self.effect_window.retained())
    }

    /// Returns the first effect sequence the live window can still serve.
    pub fn effect_window_start(&self) -> Option<u64> {
        self.effect_window.start()
    }

    /// Returns the last atomic commit without waiting for an in-flight model operation.
    pub fn snapshot(&self) -> ThreadSnapshot {
        self.snapshots.borrow().snapshot.clone()
    }

    /// Runs a bounded model/tool loop without interleaving another submitted Turn.
    ///
    /// # Errors
    /// Returns model/admission/cancellation errors; committed tool failures remain available to the next step.
    pub async fn run_turn(&self, input: TurnInput) -> Result<TurnCompletion, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.user_commands
            .send(UserCommand::Turn(input, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Retries the latest failed attempt with the exact admitted context and frozen executors.
    ///
    /// # Errors
    /// Rejects changed context, revoked/changed tool declarations, completed source attempts and reused IDs.
    pub async fn retry_attempt(
        &self,
        source: String,
        attempt: String,
        cancellation: CancellationToken,
    ) -> Result<ModelStepOutput, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Retry {
                source,
                attempt,
                cancellation,
                reply,
            })
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Submits a model step to the serial owner.
    ///
    /// # Errors
    /// Returns admission, model or output-validation failures. Admitted failures remain in history.
    pub async fn step(&self, input: StepInput) -> Result<ModelStepOutput, ThreadError> {
        let (reply, response) = oneshot::channel();
        self.events
            .send(LoopEvent::Step(input, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }

    /// Drains accepted commands and closes the model. A failed close keeps the owner available.
    ///
    /// # Errors
    /// Returns model close failure or an unavailable owner.
    pub async fn close(&self) -> Result<(), ThreadError> {
        self.close_with_purpose(crate::thread::owner::ClosePurpose::Preserve)
            .await
    }

    /// Stops and joins owned work without forming a recovery stop or flushing cold storage.
    ///
    /// The caller must already have sealed writes and retained responsibility for deleting this
    /// Thread's durable content. Failed resource cleanup keeps the owner available for retry.
    ///
    /// # Errors
    /// Returns resource close failure or an unavailable owner.
    pub async fn close_for_deletion(&self) -> Result<(), ThreadError> {
        self.close_with_purpose(crate::thread::owner::ClosePurpose::Delete)
            .await
    }

    /// Seals deletion and cancels running work before the host joins its other producers.
    ///
    /// This only requests shutdown. The caller must still await [`Self::close_for_deletion`] to
    /// release the real model, tool and task owners, including retryable cleanup failures.
    pub fn prepare_close_for_deletion(&self) {
        self.interrupt.begin_delete();
    }

    async fn close_with_purpose(
        &self,
        purpose: crate::thread::owner::ClosePurpose,
    ) -> Result<(), ThreadError> {
        match purpose {
            crate::thread::owner::ClosePurpose::Preserve => self.interrupt.begin_close(),
            crate::thread::owner::ClosePurpose::Delete => self.interrupt.begin_delete(),
        }
        let (reply, response) = oneshot::channel();
        self.user_commands
            .send(UserCommand::Close(purpose, reply))
            .await
            .map_err(|_| ThreadError::Closed)?;
        response.await.map_err(|_| ThreadError::Closed)?
    }
}

async fn finish_tool_transfer<T>(
    batch: crate::tool::opaque::RegistrationBatch,
    result: Result<T, ThreadError>,
) -> Result<T, ThreadError> {
    if let Some(tools) = batch.take() {
        let rejection = result.err().unwrap_or(ThreadError::Closed);
        return match crate::tool::opaque::close_rejected(tools).await {
            Ok(()) => Err(rejection),
            Err(error) => Err(ThreadError::RejectedTools(Box::new(
                error.with_rejection(rejection),
            ))),
        };
    }
    result
}

#[cfg(test)]
mod history_handoff_tests {
    use super::*;

    #[tokio::test]
    async fn history_handoff_can_finish_before_current_snapshot_is_published() {
        let handle = ThreadHandle::start_current("history-publication-race".into(), None)
            .expect("fresh owner");
        let snapshot = handle.snapshot();
        let sequence = snapshot.commit_sequence + 1;
        // Owner::publish exposes the export before publish_snapshot. Hold that
        // exact gap without adding a hook to the production owner or public API.
        let mut published = snapshot.clone();
        published.commit_sequence = sequence;
        let export = Arc::new(HistoryExport {
            effect: Arc::new(ThreadEffectBatch {
                thread_id: "history-publication-race".into(),
                sequence,
                ..Default::default()
            }),
            state: published,
            output_claim: None,
        });
        handle.effect_window.push_current(export.clone());
        assert_eq!(handle.snapshot().commit_sequence, snapshot.commit_sequence);
        let demand = std::num::NonZeroUsize::new(1).unwrap();
        let page = handle
            .history_export_page(snapshot.commit_sequence, demand)
            .expect("published export");
        assert!(Arc::ptr_eq(&page[0], &export));
        handle
            .release_history_through(sequence)
            .expect("accepted history handoff");
        handle
            .release_history_through(sequence)
            .expect("idempotent release");
        assert!(
            handle
                .history_export_page(sequence, demand)
                .expect("released cut")
                .is_empty()
        );
        assert!(handle.release_history_through(sequence + 1).is_err());
        assert!(handle.history_export_page(sequence + 1, demand).is_err());
        handle.close().await.expect("close owner");
    }
}

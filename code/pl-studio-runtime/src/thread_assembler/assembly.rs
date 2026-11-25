//! Paused Native installation: validate, transfer resources, configure, publish or retain cleanup.
use super::*;

impl SessionRuntime {
    /// Validates history, opens a fresh model session, binds tools/services and publishes once.
    /// History recovery does not invoke models or tools or re-render old content.
    ///
    /// # Errors
    /// Rejects duplicate identities and corrupt history; failed cleanup keeps its owner registered.
    pub async fn assemble(
        &self,
        spec: StudioThreadSpec,
    ) -> Result<ThreadHandle, ThreadAssemblyError> {
        let reservation = self.reserve(&spec.id, spec.parent_id.as_deref())?;
        self.assemble_reserved(spec, &reservation).await
    }

    pub(super) fn validate_assembly_spec(
        spec: &StudioThreadSpec,
        reservation: &Reservation,
    ) -> Result<(), ThreadAssemblyError> {
        if spec.id != reservation.id {
            return Err(ThreadAssemblyError::Identity(spec.id.clone()));
        }
        if spec.id.is_empty()
            || spec.parent_id.as_deref() == Some(spec.id.as_str())
            || spec.parent_id.as_ref().is_some_and(String::is_empty)
        {
            return Err(ThreadAssemblyError::Identity(spec.id.clone()));
        }
        if spec.current.is_some() && !spec.initial_context.is_empty() {
            return Err(ThreadAssemblyError::InitialContextOnRecovery);
        }
        pl_core::context::ContextSnapshot {
            revision: 0,
            records: spec.initial_context.clone().into(),
        }
        .validate_complete()
        .map_err(ThreadError::from)?;
        if spec
            .current
            .as_ref()
            .is_some_and(|current| current.thread_id != spec.id)
        {
            return Err(ThreadAssemblyError::Identity(spec.id.clone()));
        }
        Ok(())
    }

    pub(super) fn register_native_entry(
        &self,
        spec: &mut StudioThreadSpec,
        activation: ThreadActivation,
    ) -> Result<(ThreadHandle, Arc<crate::session::NativeResources>), ThreadAssemblyError> {
        // The paused owner receives the entire physical package before its admission or
        // observation becomes visible. Its retirement path also owns failed candidates.
        let thread = match spec.current.take() {
            Some(current) => ThreadHandle::restore_current(current, None)?,
            None => ThreadHandle::start_current(spec.id.clone(), None)?,
        };
        let resources = self
            .0
            .state()
            .activation
            .creating
            .get(&spec.id)
            .expect("reserved preparation")
            .resources
            .require_native()?
            .clone();
        self.0.state().members.insert_entry(
            spec.id.clone(),
            crate::session::AgentInstance {
                identity: activation.agent,
                binding: activation.binding,
                runtime: crate::session::AgentRuntime::Native(Box::new(
                    crate::session::NativeThreadRuntime {
                        resources: resources.clone(),
                        purpose: EntryPurpose::Execution,
                        workspace_usage: spec.workspace_usage.take(),
                        close_storage: None,
                        published_resources_closed: false,
                        workspace_disposition: None,
                        cleanup: Arc::new(child_resources::CleanupGate::default()),
                        execution: spec.execution,
                        incarnation: Arc::new(()),
                        parent_id: spec.parent_id.clone(),
                        ready: false,
                        thread: thread.clone(),
                    },
                )),
            },
        );
        Ok((thread, resources))
    }

    pub(super) async fn install_initial_bundle(
        &self,
        spec: StudioThreadSpec,
        thread: &ThreadHandle,
        resources: &Arc<crate::session::NativeResources>,
        mut preparation_guard: Option<ThreadPreparationGuard>,
    ) -> Result<(), ThreadAssemblyError> {
        let initial_binding = resources.binding();
        let registrations = match &initial_binding {
            Some(binding) => spec
                .tools
                .into_iter()
                .map(|registration| registration.guard_authorization(&binding.authorization))
                .collect(),
            None => spec.tools,
        };
        let storage_setup = async {
            thread.set_resources(spec.resources).await?;
            thread.set_capacity(spec.capacity).await?;
            if let Some(store) = spec.history_sink {
                self.attach_execution_storage(&spec.id, store).await?;
            }
            Ok::<_, ThreadAssemblyError>(())
        }
        .await;
        if let Err(setup) = storage_setup {
            return match thread.retire_tools(registrations).await {
                Ok(()) => Err(setup),
                Err(ThreadError::RejectedTools(tools)) => {
                    resources.candidates.retain(thread.clone(), tools);
                    Err(setup)
                }
                Err(error) => Err(ThreadAssemblyError::Cleanup {
                    id: spec.id.clone(),
                    setup: Box::new(setup),
                    cleanup: Box::new(error.into()),
                }),
            };
        }
        let cancellation = initial_binding
            .as_ref()
            .map(|binding| binding.lifetime.cancellation.clone());
        let runtime_binding = match initial_binding {
            Some(binding) => pl_core::thread::RuntimeBinding::new(binding),
            None => pl_core::thread::RuntimeBinding::new(()),
        };
        let snapshot = thread.snapshot();
        let application = (!spec.initial_extensions.is_empty() || !spec.initial_context.is_empty())
            .then(|| pl_core::thread::RuntimeApplication {
                instruction_binding: None,
                update: pl_core::thread::extensions::ApplicationUpdate {
                    mutations: spec
                        .initial_extensions
                        .into_iter()
                        .map(
                            |(id, payload)| pl_core::thread::extensions::ExtensionMutation::Put {
                                id,
                                expected_revision: None,
                                payload,
                            },
                        )
                        .collect(),
                    facts: Vec::new(),
                },
                context: (!spec.initial_context.is_empty()).then_some(
                    pl_core::thread::ReplaceContext {
                        expected_revision: snapshot.context.revision,
                        reason: pl_core::thread::ContextReplacementReason::Rebuild,
                        records: spec.initial_context,
                    },
                ),
            });
        let update = pl_core::thread::RuntimeBundle {
            base: thread.runtime_bundle_base(&snapshot),
            desired: format!("initial:{}", spec.id).into(),
            model: spec.model,
            require_idle: false,
            model_context_revision: None,
            wait_for_model_before_input: false,
            tools: Some(pl_core::thread::RuntimeTools {
                registrations,
                binding: runtime_binding,
                facts: spec.initial_runtime_facts,
            }),
            application,
            is_current: Arc::new(move || {
                cancellation
                    .as_ref()
                    .is_none_or(|token| !token.is_cancelled())
            }),
        };
        let receipt = match thread.install_runtime_bundle(update).await {
            Ok(receipt) => receipt,
            Err(ThreadError::RejectedTools(tools)) => {
                let diagnostic = tools.to_string();
                resources.candidates.retain(thread.clone(), tools);
                return Err(ThreadAssemblyError::Resource {
                    operation: "register initial Native resources",
                    source: Box::new(std::io::Error::other(diagnostic)),
                });
            }
            Err(error) => return Err(error.into()),
        };
        receipt
            .installed()
            .await
            .map_err(|source| ThreadAssemblyError::Resource {
                operation: "install initial Native resources",
                source: Box::new(source),
            })?;
        if resources.binding().is_some() {
            resources.observe_binding(thread.runtime_binding());
            if let Some(services) = self.0.state().agent_services.as_ref() {
                services.factory.notify_lsp_binding_changed();
            }
        }
        // Freeze the observer's recovery baseline before exposing this owner to execution.
        // Observers may query the registry, so invoke them without its lock held.
        self.publish_observation(&spec.id, &thread);
        if let Some(guard) = preparation_guard.take() {
            guard.disarm();
        }
        let mut state = self.0.state();
        if state.close.closing {
            return Err(ThreadAssemblyError::Thread(ThreadError::Closed));
        }
        let ready = !state.activation.unpublished_children.contains_key(&spec.id);
        let entry = state
            .members
            .entries
            .get_mut(&spec.id)
            .ok_or(ThreadError::Closed)?;
        entry.native_mut()?.ready = ready;
        Ok::<_, ThreadAssemblyError>(())
    }

    pub(super) async fn assemble_reserved(
        &self,
        mut spec: StudioThreadSpec,
        reservation: &Reservation,
    ) -> Result<ThreadHandle, ThreadAssemblyError> {
        tracing::debug!(
            target: "conversation_work",
            thread_id = %spec.id,
            tool_or_ssh_initialization = 1,
            "execution resources requested"
        );
        Self::validate_assembly_spec(&spec, reservation)?;
        let activation = self.consume_activation(&spec.id)?;
        if activation.parent_id() != spec.parent_id.as_deref() {
            return Err(ThreadAssemblyError::Identity(spec.id));
        }
        let is_root = activation.agent.parent_agent_id.is_none();
        if !is_root && !spec.agent_controls.is_empty() {
            return Err(ThreadAssemblyError::ChildDepth);
        }
        spec.tools.append(&mut spec.agent_controls);
        let (thread, resources) = self.register_native_entry(&mut spec, activation)?;
        let id = spec.id.clone();
        let preparation_guard = spec.preparation_guard.take();
        let setup = self
            .install_initial_bundle(spec, &thread, &resources, preparation_guard)
            .await;
        if let Err(setup) = setup {
            if let Err(cleanup) = self.prepare_close(&id, &thread).await {
                return Err(ThreadAssemblyError::Cleanup {
                    id,
                    setup: Box::new(setup),
                    cleanup: Box::new(cleanup),
                });
            }
            match thread.close().await {
                Ok(()) => {
                    let settled = async {
                        self.drain_observation(&id).await?;
                        self.join_close_storage(&id).await?;
                        self.confirm_preparation_close(&id, is_root).await?;
                        Ok::<(), ThreadAssemblyError>(())
                    }
                    .await;
                    if let Err(cleanup) = settled {
                        return Err(ThreadAssemblyError::Cleanup {
                            id,
                            setup: Box::new(setup),
                            cleanup: Box::new(cleanup),
                        });
                    }
                    let removed = { self.0.state().members.remove_entry(&id) };
                    drop(removed);
                }
                Err(cleanup) => {
                    return Err(ThreadAssemblyError::Cleanup {
                        id,
                        setup: Box::new(setup),
                        cleanup: Box::new(cleanup.into()),
                    });
                }
            }
            return Err(setup);
        }
        if is_root {
            let services = { self.0.state().agent_services.clone() };
            if let Some(services) = services
                && services
                    .store
                    .thread_preparation(&id)
                    .await
                    .map_err(|source| ThreadAssemblyError::Resource {
                        operation: "read root preparation publication",
                        source: source.into_boxed_dyn_error(),
                    })?
                    .is_some()
            {
                services
                    .store
                    .publish_preparation(&id)
                    .await
                    .map_err(|source| ThreadAssemblyError::Resource {
                        operation: "confirm root preparation publication",
                        source: source.into_boxed_dyn_error(),
                    })?;
            }
        }
        Ok(thread)
    }

    /// Creates a child with an independent context from its frozen Profile and initial facts.
    /// Model sessions, task state, mutable extensions and executors are created independently.
    ///
    /// # Errors
    /// Rejects mismatched parent identities or recovery history.
    pub async fn assemble_child(
        &self,
        spec: StudioThreadSpec,
        caller: &pl_tool::collaboration::control::AgentCallContext,
    ) -> Result<ThreadHandle, ThreadAssemblyError> {
        let caller_thread = self
            .0
            .state()
            .members
            .by_agent
            .get(&caller.caller)
            .cloned()
            .ok_or(ThreadAssemblyError::Closed)?;
        if spec.parent_id.as_deref() != Some(caller_thread.as_str()) || spec.current.is_some() {
            return Err(ThreadAssemblyError::Identity(spec.id));
        }
        self.assemble(spec).await
    }

    pub(super) fn reserve(
        &self,
        id: &str,
        parent: Option<&str>,
    ) -> Result<Reservation, ThreadAssemblyError> {
        self.reserve_resources(id, parent, None)
    }

    pub(super) fn reserve_resources(
        &self,
        id: &str,
        parent: Option<&str>,
        resources: Option<crate::session::PreparedResources>,
    ) -> Result<Reservation, ThreadAssemblyError> {
        if id.is_empty() || parent.is_some_and(|parent| parent.is_empty() || parent == id) {
            return Err(ThreadAssemblyError::Identity(id.into()));
        }
        let mut state = self.0.state();
        if state.close.closing
            || state.close.sealed_agents.contains_key(id)
            || parent.is_some_and(|parent| state.close.sealed_agents.contains_key(parent))
        {
            return Err(ThreadAssemblyError::Closed);
        }
        if state.activation.failed_preparations.contains_key(id) {
            return Err(ThreadAssemblyError::Unpublished(id.into()));
        }
        if state.activation.creating.contains_key(id) || state.members.entries.contains_key(id) {
            return Err(ThreadAssemblyError::Identity(id.to_owned()));
        }
        if let Some(parent) = parent {
            let admitted = match state.members.entries.get(parent) {
                Some(entry) => match &entry.runtime {
                    crate::session::AgentRuntime::Native(native) => {
                        native.ready && native.thread.snapshot().lifecycle == ThreadLifecycle::Open
                    }
                    crate::session::AgentRuntime::Acp(acp) => !acp.cancellation.is_cancelled(),
                },
                None => state
                    .members
                    .by_agent
                    .values()
                    .any(|thread| thread == parent),
            };
            if !admitted {
                return Err(ThreadAssemblyError::Identity(parent.to_owned()));
            }
        }
        let mut cursor = parent;
        let mut visited = BTreeSet::new();
        while let Some(parent) = cursor {
            if parent == id || !visited.insert(parent) {
                return Err(ThreadAssemblyError::Identity(id.to_owned()));
            }
            cursor = state
                .members
                .entries
                .get(parent)
                .and_then(|entry| EntryRegistry::membership_parent(&state.members.by_agent, entry))
                .or_else(|| {
                    state
                        .activation
                        .creating
                        .get(parent)
                        .and_then(|preparation| preparation.parent_id.as_deref())
                });
        }
        let resources = resources.unwrap_or_else(|| {
            crate::session::PreparedResources::Native(
                state
                    .activation
                    .unpublished_children
                    .get(id)
                    .map(|child| child.workspace.native_resources())
                    .unwrap_or_default(),
            )
        });
        let cancellation = match &resources {
            crate::session::PreparedResources::Native(_) => Default::default(),
            crate::session::PreparedResources::Acp(acp) => acp.cancellation.clone(),
        };
        state.activation.creating.insert(
            id.to_owned(),
            Preparation {
                resources,
                identity: None,
                settlement: None,
                parent_id: parent.map(str::to_owned),
                cancellation,
                result: None,
            },
        );
        Ok(Reservation {
            registry: self.0.clone(),
            id: id.to_owned(),
        })
    }
}

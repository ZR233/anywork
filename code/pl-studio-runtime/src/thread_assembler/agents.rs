//! Product-owned relationship checks and descendant shutdown over generic Thread handles.
use super::observation::DeliveryDisposition;
use super::{Registry, SessionRuntime, State, ThreadAssemblyError};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    thread::{ThreadLifecycle, input::InputState, task::TaskStatus},
    tool::opaque::Registration,
};
use pl_tool::collaboration::control::{
    AgentCallContext, AgentCloseOutcome, AgentInterruptResult, AgentSendResult, AgentSpawnResult,
    ControlError, SpawnReceipt,
};
use pl_tool::collaboration::thread::{
    AgentControlHost, AgentControlKind, AgentMessage, AgentSpawn, AgentSpawnProfile,
    ThreadAgentControl,
};
use std::sync::{Arc, Weak};

#[derive(Debug, Clone)]
pub(crate) struct AgentHost {
    registry: Weak<Registry>,
    pub(super) identity: pl_protocol::AgentThreadIdentity,
    resources: AgentHostResources,
    pub(super) catalog: crate::config::AgentProfileCatalog,
    selection: pl_protocol::DelegationSettings,
}

#[derive(Debug, Clone)]
enum AgentHostResources {
    Native(Weak<crate::session::NativeResources>),
    Acp(Weak<crate::studio::runtime::acp_business::AcpResources>),
}

impl AgentHost {
    pub(crate) fn delegation(&self) -> pl_protocol::DelegationSettings {
        self.selection
    }

    pub(crate) fn spawn_profiles(&self) -> Vec<AgentSpawnProfile> {
        if self.identity.parent_agent_id.is_some() {
            return Vec::new();
        }
        self.catalog
            .profiles
            .iter()
            .map(|profile| AgentSpawnProfile {
                profile_id: profile.definition.definition_id.clone(),
                backend: profile.binding.backend(),
                workspace_mode: profile.workspace_mode,
            })
            .collect()
    }

    pub(super) fn validate_instance(&self) -> Result<(), ControlError> {
        let owner = self.owner()?;
        let state = owner.0.state();
        let id = self.identity.thread_id.as_str();
        let entry = state
            .entries
            .get(id)
            .ok_or_else(|| ControlError::Missing(id.into()))?;
        if state.closing || state.sealed_agents.contains_key(id) || entry.identity != self.identity
        {
            return Err(ControlError::Closed);
        }
        match (&self.resources, &entry.runtime) {
            (
                AgentHostResources::Native(resources),
                crate::session::AgentRuntime::Native(native),
            ) if resources.ptr_eq(&Arc::downgrade(&native.resources))
                && native.ready
                && native.purpose == super::EntryPurpose::Execution
                && native.workspace_disposition.is_none()
                && native.thread.snapshot().lifecycle == ThreadLifecycle::Open =>
            {
                if crate::studio::agent_close::is_explicitly_closed(&native.thread.snapshot())
                    .map_err(|source| {
                        ControlError::service(super::agent_services::ServiceError(source))
                    })?
                {
                    return Err(ControlError::Closed);
                }
            }
            (AgentHostResources::Acp(resources), crate::session::AgentRuntime::Acp(acp))
                if resources.ptr_eq(&Arc::downgrade(acp)) && !acp.cancellation.is_cancelled() => {}
            _ => return Err(ControlError::Closed),
        }
        Ok(())
    }

    pub(super) fn caller(&self, context: &AgentCallContext) -> Result<String, ControlError> {
        self.validate_instance()?;
        if context.caller != self.identity.agent_id || context.cancellation.is_cancelled() {
            return Err(ControlError::Closed);
        }
        Ok(self.identity.thread_id.to_string())
    }

    pub(super) fn target_identity(
        &self,
        target: &str,
    ) -> Result<pl_protocol::AgentThreadIdentity, ControlError> {
        let owner = self.owner()?;
        let state = owner.0.state();
        let agent = pl_protocol::AgentId::new(target).map_err(ControlError::service)?;
        if let Some(id) = state.by_agent.get(&agent)
            && let Some(entry) = state.entries.get(id)
            && entry.identity.session_id == self.identity.session_id
        {
            return Ok(entry.identity.clone());
        }
        if let Some(services) = &state.agent_services
            && let Some(identity) = services
                .events
                .member_identity(&self.identity.session_id, &agent)
        {
            return Ok(identity);
        }
        Err(ControlError::Missing(target.into()))
    }

    fn target_thread(&self, target: &str) -> Result<String, ControlError> {
        Ok(self.target_identity(target)?.thread_id.to_string())
    }

    fn target_agent(
        &self,
        owner: &SessionRuntime,
        thread: &str,
    ) -> Result<pl_protocol::AgentId, ControlError> {
        owner
            .0
            .state()
            .entries
            .get(thread)
            .map(|entry| entry.identity.agent_id.clone())
            .ok_or_else(|| ControlError::Missing(thread.into()))
    }

    pub(super) fn owner(&self) -> Result<SessionRuntime, ControlError> {
        self.registry
            .upgrade()
            .map(SessionRuntime)
            .ok_or(ControlError::Closed)
    }
}

fn ancestry(state: &State, id: &str) -> Result<Vec<String>, ControlError> {
    let mut path = Vec::new();
    let mut cursor = Some(id.to_owned());
    let mut session = None;
    while let Some(id) = cursor {
        if path.contains(&id) {
            return Err(ControlError::Ancestry);
        }
        let identity = state
            .entries
            .get(&id)
            .map(|entry| entry.identity.clone())
            .or_else(|| {
                state
                    .agent_services
                    .as_ref()?
                    .events
                    .agent_execution_identity(&id)
                    .map(|(identity, _, _)| identity)
            })
            .ok_or_else(|| ControlError::Missing(id.clone()))?;
        if session
            .as_ref()
            .is_some_and(|session| session != &identity.session_id)
        {
            return Err(ControlError::Ancestry);
        }
        session = Some(identity.session_id.clone());
        path.push(id);
        cursor = match identity.parent_agent_id {
            Some(parent) => Some(
                state
                    .by_agent
                    .get(&parent)
                    .cloned()
                    .or_else(|| {
                        state
                            .agent_services
                            .as_ref()?
                            .events
                            .member_identity(&identity.session_id, &parent)
                            .map(|parent| parent.thread_id.to_string())
                    })
                    .ok_or(ControlError::Ancestry)?,
            ),
            None => None,
        };
    }
    Ok(path)
}

fn descendant(state: &State, caller: &str, target: &str) -> Result<(), ControlError> {
    if !state.entries.get(caller).is_some_and(member_open) {
        return Err(ControlError::Missing(caller.into()));
    }
    ancestry(state, caller)?;
    if caller == target
        || !ancestry(state, target)?
            .iter()
            .skip(1)
            .any(|id| id == caller)
    {
        return Err(ControlError::Relationship {
            caller: caller.into(),
            target: target.into(),
        });
    }
    Ok(())
}

pub(super) fn member_open(entry: &crate::session::AgentInstance) -> bool {
    match &entry.runtime {
        crate::session::AgentRuntime::Native(native) => {
            native.ready && native.thread.snapshot().lifecycle == ThreadLifecycle::Open
        }
        crate::session::AgentRuntime::Acp(acp) => !acp.cancellation.is_cancelled(),
    }
}

/// Lists one in-flight tree member that holds capacity but has no published Thread snapshot.
/// The row carries identity plus the explicit preparing lifecycle; no model or run-state facts
/// are invented. Members whose parent is outside the tree are skipped.
fn push_preparing_row(
    state: &State,
    root: &str,
    rows: &mut std::collections::BTreeMap<String, serde_json::Value>,
    id: &str,
    parent: Option<&str>,
) -> Result<(), ControlError> {
    let Some(parent) = parent else {
        return Ok(());
    };
    if ancestry(state, parent)?.last().is_some_and(|id| id == root) {
        let identity = state
            .entries
            .get(id)
            .map(|entry| entry.identity.clone())
            .or_else(|| {
                state
                    .pending_activation
                    .get(id)
                    .map(|activation| activation.agent.clone())
            })
            .or_else(|| {
                state.agent_services.as_ref().and_then(|services| {
                    services
                        .events
                        .agent_execution_identity(id)
                        .map(|(identity, _, _)| identity)
                })
            });
        // New Native spawns explicitly allocate their member identity together with this
        // reservation. Cold members instead retain the committed directory identity above.
        let member = identity
            .as_ref()
            .map_or(id, |identity| identity.agent_id.as_str());
        let parent = state
            .entries
            .get(parent)
            .ok_or_else(|| ControlError::Missing(parent.into()))?
            .identity
            .agent_id
            .as_str();
        rows.insert(
            id.to_owned(),
            serde_json::json!({"id":member, "parentId":parent, "lifecycle":{"kind":"preparing"}}),
        );
    }
    Ok(())
}

pub(super) fn agent_row(
    id: &str,
    parent: Option<&str>,
    snapshot: &pl_core::thread::ThreadSnapshot,
) -> anyhow::Result<serde_json::Value> {
    let model = crate::studio::model_route::saved_profile(snapshot)?
        .map(|(profile, _)| crate::studio::delegation::profile_model(&profile));
    let delegation = crate::studio::delegation::saved(snapshot)?;
    Ok(
        serde_json::json!({ "id":id, "parentId":parent, "lifecycle":snapshot.lifecycle,
        "frozenModel":model, "delegationMode":delegation.map(|value| value.mode), "delegationPreference":delegation.map(|value| value.preference),
        "lastTurn":snapshot.turns.last(), "pendingInputs":snapshot.inputs.iter().filter(|input| input.state == InputState::Pending).count(),
        "runningTasks":snapshot.tasks.values().filter(|task| task.status == TaskStatus::Running).count() }),
    )
}

fn assigned_workspace(
    snapshot: &pl_core::thread::ThreadSnapshot,
) -> Result<Option<pl_protocol::AgentWorkspaceAssignmentSnapshot>, ThreadAssemblyError> {
    crate::studio::workspace_receipt::from_snapshot(snapshot).map_err(|source| {
        ThreadAssemblyError::Resource {
            operation: "decode assigned child workspace",
            source: Box::<dyn std::error::Error + Send + Sync>::from(source),
        }
    })
}

#[derive(Debug, thiserror::Error)]
#[error("child {id} preparation failed ({operation}); resource cleanup failed ({cleanup})")]
struct SpawnCleanupError {
    id: String,
    #[source]
    operation: ThreadAssemblyError,
    cleanup: ThreadAssemblyError,
}

async fn cleanup_spawn_failure(
    owner: &SessionRuntime,
    id: &str,
    operation: ThreadAssemblyError,
) -> ControlError {
    match owner.discard_child_resources(id).await {
        Ok(()) => ControlError::service(operation),
        Err(cleanup) => ControlError::service(SpawnCleanupError {
            id: id.into(),
            operation,
            cleanup,
        }),
    }
}

impl AgentHost {
    async fn spawn_acp_owned(
        &self,
        owner: SessionRuntime,
        context: AgentCallContext,
        request: AgentSpawn,
    ) -> Result<AgentSpawnResult, ControlError> {
        if request.model_selection.is_some()
            || request.writable_paths.is_some()
            || request.review_target_agent_id.is_some()
            || request.review_feedback.is_some()
        {
            return Err(ControlError::service(std::io::Error::other(
                "ACP target forbids modelSelection, writablePaths and structured review",
            )));
        }
        let caller = self.caller(&context)?;
        let services = owner
            .0
            .state()
            .agent_services
            .clone()
            .ok_or(ControlError::Closed)?;
        let (profile, definition) = services
            .config
            .resolve_acp_child_profile(&request.profile_id)
            .map_err(ControlError::service)?;
        if profile.workspace_mode == pl_protocol::AgentWorkspaceMode::Review {
            return Err(ControlError::service(std::io::Error::other(
                "ACP target supports ordinary tasks only",
            )));
        }
        let business = services.acp_business.clone().ok_or(ControlError::Closed)?;
        let (_, reservation) = owner
            .reserve_child(&context)
            .map_err(ControlError::service)?;
        services
            .factory
            .begin_child_preparation(&caller, &reservation.id)
            .await
            .map_err(ControlError::service)?;
        let workspace_owner = owner.0.state().unpublished_children[&reservation.id]
            .workspace
            .clone();
        let child_request = super::ChildThreadRequest {
            workspace_owner,
            id: reservation.id.clone(),
            cancellation: reservation.cancellation.clone(),
            caller,
            call_id: context.call_id.clone(),
            profile_id: request.profile_id.clone(),
            model_selection: None,
            delegation: self.selection,
            task_summary: request.task_summary,
            writable_paths: None,
            review_target_agent_id: None,
            review_feedback: None,
            review_target: None,
            review_workspace: None,
            metadata: OpaquePayload::new(
                "pl.studio.agent-metadata",
                1,
                serde_json::to_string(&request.metadata).map_err(ControlError::service)?,
            )
            .map_err(ControlError::service)?,
        };
        let preparation = business.open_child(&owner, &child_request, &profile, definition);
        tokio::pin!(preparation);
        let result = tokio::select! {
            result = &mut preparation => result,
            () = context.cancellation.cancelled() => {
                reservation.cancellation.cancel();
                preparation.await
            }
        };
        let (resources, workspace) = match result {
            Ok(prepared) => prepared,
            Err(error) => {
                return Err(cleanup_spawn_failure(
                    &owner,
                    &reservation.id,
                    ThreadAssemblyError::Resource {
                        operation: "prepare ACP child",
                        source: error.into_boxed_dyn_error(),
                    },
                )
                .await);
            }
        };
        let agent = self.target_agent(&owner, &reservation.id)?;
        let mut receipt = SpawnReceipt {
            agent_id: agent.to_string(),
            profile_id: request.profile_id,
            model: None,
            delegation: self.selection,
            workspace: Some(workspace),
            message_accepted: false,
            message_sequence: None,
        };
        if let Err(error) = services.store.publish_preparation(&reservation.id).await {
            return Ok(AgentSpawnResult {
                receipt,
                message_error: Some(ControlError::service(super::agent_services::ServiceError(
                    error,
                ))),
            });
        }
        let delivery = async {
            if context.cancellation.is_cancelled() {
                return Err(ControlError::Closed);
            }
            let _operation = owner.agent_operation(&reservation.id).await;
            owner
                .ensure_agent_admission_open(&reservation.id)
                .map_err(ControlError::service)?;
            resources
                .session()
                .map_err(|error| ControlError::service(super::agent_services::ServiceError(error)))?
                .submit(vec![pl_protocol::studio::ContentBlock::Text(
                    pl_acp::session::schema::TextContent::new(request.message),
                )])
                .await
                .map_err(ControlError::service)?;
            Ok::<_, ControlError>(())
        }
        .await;
        receipt.message_accepted = delivery.is_ok();
        Ok(AgentSpawnResult {
            receipt,
            message_error: delivery.err(),
        })
    }

    async fn ensure_archive_execution_admission(
        owner: &SessionRuntime,
        id: &str,
    ) -> Result<(), ControlError> {
        let services = { owner.0.state().agent_services.clone() };
        if let Some(services) = services {
            services
                .factory
                .ensure_member_execution_allowed(id)
                .await
                .map_err(|error| {
                    ControlError::service(super::agent_services::ServiceError(error))
                })?;
        }
        Ok(())
    }

    async fn spawn_owned(
        &self,
        owner: SessionRuntime,
        context: AgentCallContext,
        request: AgentSpawn,
        _parent_operation: tokio::sync::OwnedMutexGuard<()>,
    ) -> Result<AgentSpawnResult, ControlError> {
        let caller = self.caller(&context)?;
        owner
            .ensure_agent_admission_open(&caller)
            .map_err(ControlError::service)?;
        Self::ensure_archive_execution_admission(&owner, &caller).await?;
        let delegation = self.selection;
        let factory = owner
            .child_factory(&context)
            .map_err(ControlError::service)?;
        let declared = self
            .catalog
            .profiles
            .iter()
            .find(|profile| profile.definition.definition_id == request.profile_id);
        if matches!(self.resources, AgentHostResources::Acp(_))
            && (request.review_target_agent_id.is_some()
                || request.review_feedback.is_some()
                || declared.is_some_and(|profile| {
                    profile.workspace_mode == pl_protocol::AgentWorkspaceMode::Review
                }))
        {
            return Err(ControlError::service(
                ThreadAssemblyError::UnsupportedBackend {
                    backend: pl_protocol::AgentBackendKind::Acp,
                },
            ));
        }
        if declared
            .is_some_and(|profile| matches!(profile.binding, pl_protocol::AgentBinding::Acp(_)))
        {
            return self.spawn_acp_owned(owner, context, request).await;
        }
        let admission = factory
            .admit(
                &request.profile_id,
                delegation,
                request.model_selection.clone(),
            )
            .await
            .map_err(ControlError::service)?;
        // The model names a member; the existing Native review preparation consumes its
        // default Thread binding, just like the Native send and close implementations.
        let review_target_thread = request
            .review_target_agent_id
            .as_deref()
            .map(|target| self.target_thread(target))
            .transpose()?;
        if review_target_thread.as_deref() == Some(caller.as_str()) {
            return Err(ControlError::service(
                ThreadAssemblyError::ReviewTargetInvalid(caller.clone()),
            ));
        }
        let (_, reservation) = owner
            .reserve_child(&context)
            .map_err(ControlError::service)?;
        if let Some(services) = { owner.0.state().agent_services.clone() } {
            services
                .factory
                .begin_child_preparation(&caller, &reservation.id)
                .await
                .map_err(ControlError::service)?;
        }
        let _review_operation = match review_target_thread.as_deref() {
            Some(target) => Some(owner.agent_operation(target).await),
            None => None,
        };
        let review_target = match review_target_thread.as_deref() {
            Some(target) => Some(
                owner
                    .freeze_review_target(&caller, target, request.review_feedback)
                    .await
                    .map_err(|error| {
                        ControlError::service(super::agent_services::ServiceError(error))
                    })?,
            ),
            None => None,
        };
        let (review_target, review_workspace, review_check) = match review_target {
            Some((target, workspace, check)) => (Some(target), Some(workspace), Some(check)),
            None => (None, None, None),
        };
        let workspace_owner = {
            owner
                .0
                .state()
                .unpublished_children
                .get(&reservation.id)
                .ok_or_else(|| ControlError::Missing(reservation.id.clone()))?
                .workspace
                .clone()
        };
        let preparation = admission(super::ChildThreadRequest {
            workspace_owner,
            id: reservation.id.clone(),
            cancellation: reservation.cancellation.clone(),
            caller: caller.clone(),
            call_id: context.call_id.clone(),
            profile_id: request.profile_id.clone(),
            model_selection: request.model_selection,
            delegation,
            task_summary: request.task_summary,
            writable_paths: request.writable_paths,
            review_target_agent_id: review_target_thread,
            review_feedback: request.review_feedback,
            review_target,
            review_workspace,
            metadata: OpaquePayload::new(
                "pl.studio.agent-metadata",
                1,
                serde_json::to_string(&request.metadata).map_err(ControlError::service)?,
            )
            .map_err(ControlError::service)?,
        });
        tokio::pin!(preparation);
        let spec = tokio::select! {
            result = &mut preparation => result,
            () = context.cancellation.cancelled() => {
                reservation.cancellation.cancel();
                // Keep the original factory future and its resource owner until it settles.
                preparation.await
            }
        };
        let spec = match spec {
            Ok(spec) => spec,
            Err(error) => {
                return Err(cleanup_spawn_failure(&owner, &reservation.id, error).await);
            }
        };
        if reservation.cancellation.is_cancelled() {
            drop(spec);
            return Err(cleanup_spawn_failure(
                &owner,
                &reservation.id,
                pl_core::thread::ThreadError::Cancelled.into(),
            )
            .await);
        }
        if spec.id != reservation.id {
            let invalid = spec.id.clone();
            drop(spec);
            return Err(cleanup_spawn_failure(
                &owner,
                &reservation.id,
                ThreadAssemblyError::Identity(invalid),
            )
            .await);
        }
        let id = spec.id.clone();
        if let Some(check) = &review_check
            && let Err(error) = check.confirm().await
        {
            return Err(cleanup_spawn_failure(
                &owner,
                &id,
                ThreadAssemblyError::Resource {
                    operation: "recheck reviewed workspace before publication",
                    source: Box::new(error),
                },
            )
            .await);
        }
        let options = spec.execution;
        let assembly = owner.assemble_child(spec, &context);
        tokio::pin!(assembly);
        let child = tokio::select! {
            result = &mut assembly => result,
            () = context.cancellation.cancelled() => {
                reservation.cancellation.cancel();
                assembly.await
            }
        };
        let child = match child {
            Ok(child) => child,
            Err(error) => {
                return Err(cleanup_spawn_failure(&owner, &reservation.id, error).await);
            }
        };
        if reservation.cancellation.is_cancelled() {
            return Err(cleanup_spawn_failure(
                &owner,
                &id,
                pl_core::thread::ThreadError::Cancelled.into(),
            )
            .await);
        }
        let workspace = match assigned_workspace(&child.snapshot()) {
            Ok(workspace) => workspace,
            Err(error) => return Err(cleanup_spawn_failure(&owner, &id, error).await),
        };
        let profile = match crate::studio::model_route::saved_profile(&child.snapshot()) {
            Ok(Some((profile, _))) => profile,
            Ok(None) => {
                return Err(cleanup_spawn_failure(
                    &owner,
                    &id,
                    ThreadAssemblyError::Identity("child has no frozen Profile".into()),
                )
                .await);
            }
            Err(source) => {
                return Err(cleanup_spawn_failure(
                    &owner,
                    &id,
                    ThreadAssemblyError::Resource {
                        operation: "decode frozen child Profile",
                        source: source.into(),
                    },
                )
                .await);
            }
        };
        let model = crate::studio::delegation::profile_model(&profile);
        let agent_id = match self.target_agent(&owner, &id) {
            Ok(agent) => agent.to_string(),
            Err(source) => {
                return Err(cleanup_spawn_failure(
                    &owner,
                    &id,
                    ThreadAssemblyError::Resource {
                        operation: "resolve prepared child identity",
                        source: Box::new(source),
                    },
                )
                .await);
            }
        };
        // Freeze every creation fact before publication. Nothing after the handoff may
        // turn a real published member into an error without its creation receipt.
        let mut receipt = SpawnReceipt {
            agent_id,
            profile_id: request.profile_id,
            model: Some(model),
            delegation,
            workspace,
            message_accepted: false,
            message_sequence: None,
        };
        if let Some(check) = &review_check
            && let Err(error) = check.confirm().await
        {
            return Err(cleanup_spawn_failure(
                &owner,
                &id,
                ThreadAssemblyError::Resource {
                    operation: "confirm reviewed workspace before publication",
                    source: Box::new(error),
                },
            )
            .await);
        }
        if reservation.cancellation.is_cancelled() || context.cancellation.is_cancelled() {
            return Err(cleanup_spawn_failure(
                &owner,
                &id,
                pl_core::thread::ThreadError::Cancelled.into(),
            )
            .await);
        }
        let operation = owner.agent_operation(&id).await;
        if context.cancellation.is_cancelled() {
            reservation.cancellation.cancel();
            drop(operation);
            return Err(cleanup_spawn_failure(
                &owner,
                &id,
                pl_core::thread::ThreadError::Cancelled.into(),
            )
            .await);
        }
        if let Err(error) = owner.publish_child_resources(&id) {
            // Retained disposal acquires this same identity's permit. Never join it while
            // holding the publication permit (the caller also owns the root spawn permit).
            drop(operation);
            return Err(cleanup_spawn_failure(&owner, &id, error).await);
        }
        let _operation = operation;
        if let Some(services) = { owner.0.state().agent_services.clone() }
            && let Err(error) = services.store.publish_preparation(&id).await
        {
            return Ok(AgentSpawnResult {
                receipt,
                message_error: Some(ControlError::service(super::agent_services::ServiceError(
                    error,
                ))),
            });
        }
        let message = pl_core::thread::inbox::ThreadMessage {
            kind: pl_core::context::AgentMessageKind::Task,
            id: format!("initial:{}:{}", caller.len(), context.call_id),
            source_id: format!("agent:{}", caller),
            payload: OpaquePayload::text(request.message.clone()),
            context: vec![ContextContent::Text {
                text: Arc::from(request.message),
            }],
        };
        // The child's initial delivery is adjudicated against the child's durable identity index
        // first: a repeated spawn command must answer with the original receipt instead of queueing
        // the same initial message as new work, and an unverifiable or conflicting identity is
        // rejected rather than delivered again.
        let delivery = match owner.adjudicate_message(&id, &message).await {
            Ok(DeliveryDisposition::Receipt(sequence)) => Ok(sequence),
            Ok(DeliveryDisposition::New) => {
                match owner.prepare_input_admission(&id, &child).await {
                    Ok(()) => child
                        .send_message_and_continue(message, options)
                        .await
                        .map_err(ThreadAssemblyError::from),
                    Err(error) => Err(error),
                }
            }
            Ok(DeliveryDisposition::Conflict) => {
                Err(ThreadAssemblyError::MessageConflict(message.id.clone()))
            }
            Ok(DeliveryDisposition::Unverifiable) => {
                Err(ThreadAssemblyError::MessageUnverifiable(message.id.clone()))
            }
            Err(error) => Err(error),
        };
        let (sequence, message_error) = match delivery {
            Ok(sequence) => (Some(sequence), None),
            Err(source) => (None, Some(ControlError::service(source))),
        };
        receipt.message_accepted = sequence.is_some();
        receipt.message_sequence = sequence;
        Ok(AgentSpawnResult {
            receipt,
            message_error,
        })
    }
}

impl AgentControlHost for AgentHost {
    async fn spawn(
        &self,
        context: AgentCallContext,
        request: AgentSpawn,
    ) -> Result<AgentSpawnResult, ControlError> {
        let owner = self.owner()?;
        let caller = self.caller(&context)?;
        let parent_operation = owner.agent_operation(&caller).await;
        self.validate_instance()?;
        let services = owner.0.state().agent_services.clone();
        if let Some(services) = services {
            let admission = owner.clone();
            let caller = caller.clone();
            let admitted_caller = caller.clone();
            let host = self.clone();
            services
                .operations
                .run(
                    caller,
                    format!("spawn:{}", context.call_id),
                    move || {
                        admission.ensure_agent_admission_open(&admitted_caller)?;
                        Ok(())
                    },
                    async move {
                        // Keep preparation/cleanup state on the heap before the existing
                        // operation owner moves this worker through JoinSet/Tokio admission.
                        Ok(
                            Box::pin(host.spawn_owned(owner, context, request, parent_operation))
                                .await,
                        )
                    },
                )
                .await
                .map_err(|error| {
                    ControlError::service(super::agent_services::ServiceError(error))
                })?
        } else {
            Box::pin(self.spawn_owned(owner, context, request, parent_operation)).await
        }
    }

    async fn send(
        &self,
        context: AgentCallContext,
        mut message: AgentMessage,
    ) -> Result<AgentSendResult, ControlError> {
        let caller_id = self.caller(&context)?;
        let caller = caller_id.as_str();
        let target_agent = message.target.clone();
        let identity = self.target_identity(&message.target)?;
        if identity.parent_agent_id.as_ref() != Some(&self.identity.agent_id) {
            return Err(ControlError::Relationship {
                caller: context.caller.to_string(),
                target: target_agent,
            });
        }
        message.target = identity.thread_id.to_string();
        let owner = self.owner()?;
        if caller == message.target {
            return Err(ControlError::Relationship {
                caller: caller.into(),
                target: target_agent,
            });
        }
        // Preserve caller qualification across cold activation and target admission.
        let _caller_operation = owner.agent_operation(caller).await;
        self.validate_instance()?;
        Self::ensure_archive_execution_admission(&owner, caller).await?;
        Self::ensure_archive_execution_admission(&owner, &message.target).await?;
        let services = owner.0.state().agent_services.clone();
        if let Some(services) = &services {
            services
                .authorize(caller, &message.target)
                .await
                .map_err(|error| {
                    ControlError::service(super::agent_services::ServiceError(error))
                })?;
            services
                .store
                .ensure_agent_execution_allowed(&message.target)
                .await
                .map_err(|error| {
                    ControlError::service(super::agent_services::ServiceError(error))
                })?;
        }
        let acp_target = services.as_ref().is_some_and(|services| {
            services
                .events
                .agent_execution_identity(&message.target)
                .is_some_and(|(_, binding, _)| matches!(binding, pl_protocol::AgentBinding::Acp(_)))
        }) || owner
            .0
            .state()
            .entries
            .get(&message.target)
            .is_some_and(|entry| matches!(entry.runtime, crate::session::AgentRuntime::Acp(_)));
        if acp_target {
            let _operation = owner.agent_operation(&message.target).await;
            let services = services.as_ref().ok_or(ControlError::Closed)?;
            let business = services.acp_business.as_ref().ok_or(ControlError::Closed)?;
            let resources = business
                .activate_child(&owner, caller, &message.target)
                .await
                .map_err(|error| {
                    ControlError::service(super::agent_services::ServiceError(error))
                })?;
            self.validate_instance()?;
            owner
                .ensure_agent_admission_open(&message.target)
                .map_err(ControlError::service)?;
            let session = resources.session().map_err(|error| {
                ControlError::service(super::agent_services::ServiceError(error))
            })?;
            let current = session.snapshot().await.map_err(ControlError::service)?;
            let content = vec![pl_protocol::studio::ContentBlock::Text(
                pl_acp::session::schema::TextContent::new(message.message),
            )];
            match current.active_run {
                Some(run) => session.replace(run, content).await,
                None => session.submit(content).await,
            }
            .map_err(ControlError::service)?;
            return Ok(AgentSendResult {
                target: target_agent,
                message_id: message.id,
                sequence: None,
            });
        }
        if owner.thread(&message.target).is_none() {
            let services = owner.0.state().agent_services.clone();
            if let Some(services) = services {
                services
                    .activate_child(&owner, caller, &message.target)
                    .await
                    .map_err(|error| {
                        ControlError::service(super::agent_services::ServiceError(error))
                    })?;
            }
        }
        let _operation = owner.agent_operation(&message.target).await;
        owner
            .ensure_agent_admission_open(&message.target)
            .map_err(ControlError::service)?;
        let (target, options) = {
            let state = owner.0.state();
            if state.closing {
                return Err(ControlError::Closed);
            }
            descendant(&state, caller, &message.target)?;
            let entry = state
                .entries
                .get(&message.target)
                .filter(|entry| {
                    entry.native().is_ok_and(|native| {
                        native.ready
                            && State::membership_parent(&state.by_agent, entry) == Some(caller)
                    })
                })
                .ok_or_else(|| ControlError::Relationship {
                    caller: caller.into(),
                    target: message.target.clone(),
                })?;
            (
                entry
                    .native()
                    .map_err(|_| ControlError::Closed)?
                    .thread
                    .clone(),
                entry.native().map_err(|_| ControlError::Closed)?.execution,
            )
        };
        let delivery = pl_core::thread::inbox::ThreadMessage {
            kind: pl_core::context::AgentMessageKind::Report,
            id: message.id.clone(),
            source_id: format!("agent:{caller}"),
            payload: OpaquePayload::text(message.message.clone()),
            context: vec![ContextContent::Text {
                text: Arc::from(message.message),
            }],
        };
        // The target's durable identity index adjudicates the delivery before it can become new work:
        // an identical repeat answers with its original receipt instead of a second delivery, while a
        // conflicting or unverifiable identity is rejected and a failed lookup never admits a
        // possible duplicate.
        let sequence = match owner
            .adjudicate_message(&message.target, &delivery)
            .await
            .map_err(ControlError::service)?
        {
            DeliveryDisposition::Receipt(sequence) => sequence,
            DeliveryDisposition::New => {
                owner
                    .prepare_input_admission(&message.target, &target)
                    .await
                    .map_err(ControlError::service)?;
                target
                    .send_message_and_continue(delivery, options)
                    .await
                    .map_err(ControlError::service)?
            }
            DeliveryDisposition::Conflict => {
                return Err(ControlError::service(ThreadAssemblyError::MessageConflict(
                    message.id.clone(),
                )));
            }
            DeliveryDisposition::Unverifiable => {
                return Err(ControlError::service(
                    ThreadAssemblyError::MessageUnverifiable(message.id.clone()),
                ));
            }
        };
        Ok(AgentSendResult {
            target: target_agent,
            message_id: message.id,
            sequence: Some(sequence),
        })
    }

    async fn list(
        &self,
        context: AgentCallContext,
    ) -> Result<Vec<serde_json::Value>, ControlError> {
        let caller_id = self.caller(&context)?;
        let caller = caller_id.as_str();
        let owner = self.owner()?;
        let mut acp_members = Vec::new();
        let mut rows = {
            let state = owner.0.state();
            if state.closing {
                return Err(ControlError::Closed);
            }
            if !state.entries.get(caller).is_some_and(member_open) {
                return Err(ControlError::Missing(caller.into()));
            }
            let path = ancestry(&state, caller)?;
            let root = path.last().ok_or(ControlError::Ancestry)?;
            // A complete listing also covers in-flight members: reserved spawns and cold
            // activations that already hold tree capacity but are not published yet. They carry
            // no Thread snapshot, so only identity and the explicit preparing fact are projected.
            let mut rows = std::collections::BTreeMap::new();
            for (id, child) in &state.unpublished_children {
                push_preparing_row(&state, root, &mut rows, id, Some(child.parent.as_str()))?;
            }
            for (id, preparation) in &state.creating {
                push_preparing_row(
                    &state,
                    root,
                    &mut rows,
                    id,
                    preparation.parent_id.as_deref(),
                )?;
            }
            for (id, entry) in &state.entries {
                if ancestry(&state, id)?.last() != Some(root) {
                    continue;
                }
                let native = match &entry.runtime {
                    crate::session::AgentRuntime::Native(native) => native,
                    crate::session::AgentRuntime::Acp(acp) => {
                        acp_members.push((entry.identity.clone(), acp.clone()));
                        continue;
                    }
                };
                let snapshot = native.thread.snapshot();
                if !native.ready && snapshot.lifecycle == ThreadLifecycle::Open {
                    if !rows.contains_key(id) {
                        push_preparing_row(
                            &state,
                            root,
                            &mut rows,
                            id,
                            State::membership_parent(&state.by_agent, entry),
                        )?;
                    }
                    continue;
                }
                rows.insert(
                    id.clone(),
                    agent_row(
                        entry.identity.agent_id.as_str(),
                        entry
                            .identity
                            .parent_agent_id
                            .as_ref()
                            .map(pl_protocol::AgentId::as_str),
                        &snapshot,
                    )
                    .map_err(|error| {
                        ControlError::service(super::agent_services::ServiceError(error))
                    })?,
                );
            }
            rows.into_values().collect::<Vec<_>>()
        };
        for (identity, resources) in acp_members {
            let mut row = serde_json::json!({
                "id": identity.agent_id, "parentId": identity.parent_agent_id,
                "backend": "acp", "deliveryError": resources.delivery_error(),
                "hostMcp": resources.host_mcp_status().await,
            });
            match resources.session() {
                Ok(session) => match session.snapshot().await {
                    Ok(snapshot) => {
                        row["lifecycle"] = serde_json::json!({"kind": if snapshot.closing {"closing"} else {"open"}});
                        row["activeRun"] = snapshot.active_run.map(|run|
                            serde_json::json!({"instance":run.instance,"sequence":run.sequence})
                        ).unwrap_or(serde_json::Value::Null);
                        row["lastCompleted"] = snapshot.last_completed.map(|completed| {
                            let result = match completed.result {
                                Ok(response) => serde_json::json!({"ok": response}),
                                Err(error) => serde_json::json!({"error": error}),
                            };
                            serde_json::json!({
                                "run":{"instance":completed.run.instance,"sequence":completed.run.sequence},
                                "completionSequence":completed.completion_sequence,
                                "result":result,"summary":completed.summary,"truncated":completed.truncated,
                            })
                        }).unwrap_or(serde_json::Value::Null);
                    }
                    Err(error) => row["snapshotError"] = error.to_string().into(),
                },
                Err(error) => row["snapshotError"] = error.to_string().into(),
            }
            rows.push(row);
        }
        let services = owner.0.state().agent_services.clone();
        if let Some(services) = services {
            let loaded = rows
                .iter()
                .filter_map(|row| row["id"].as_str().map(str::to_owned))
                .collect();
            rows.extend(
                services
                    .saved_agents(caller, &loaded)
                    .await
                    .map_err(|error| {
                        ControlError::service(super::agent_services::ServiceError(error))
                    })?,
            );
        }
        Ok(rows)
    }

    async fn interrupt(
        &self,
        context: AgentCallContext,
        target: &str,
    ) -> Result<AgentInterruptResult, ControlError> {
        let caller_id = self.caller(&context)?;
        let caller = caller_id.as_str();
        let target_agent = target.to_owned();
        let target_id = self.target_thread(target)?;
        let target = target_id.as_str();
        let owner = self.owner()?;
        let _caller_operation = owner.agent_operation(caller).await;
        self.validate_instance()?;
        owner
            .ensure_agent_admission_open(target)
            .map_err(ControlError::service)?;
        let acp = {
            let state = owner.0.state();
            descendant(&state, caller, target)?;
            state
                .entries
                .get(target)
                .and_then(|entry| match &entry.runtime {
                    crate::session::AgentRuntime::Acp(acp) => Some(acp.clone()),
                    _ => None,
                })
        };
        if let Some(acp) = acp {
            let session = acp.session().map_err(|error| {
                ControlError::service(super::agent_services::ServiceError(error))
            })?;
            let run = session
                .snapshot()
                .await
                .map_err(ControlError::service)?
                .active_run
                .ok_or_else(|| ControlError::StaleExecution(target.into()))?;
            session
                .interrupt(run)
                .await
                .map_err(ControlError::service)?;
            return Ok(AgentInterruptResult {
                target: target_agent,
                execution_id: format!("{}:{}", run.instance, run.sequence),
                interrupted: true,
            });
        }
        // The parent stops exactly the execution it observed, through the same precise stop the user
        // interfaces use. A superseded identity fails instead of cancelling whatever runs now.
        let (thread, execution) = {
            let state = owner.0.state();
            if state.closing {
                return Err(ControlError::Closed);
            }
            descendant(&state, caller, target)?;
            let entry = state
                .entries
                .get(target)
                .ok_or_else(|| ControlError::Missing(target.into()))?;
            (
                entry
                    .native()
                    .map_err(|_| ControlError::Closed)?
                    .thread
                    .clone(),
                entry
                    .native()
                    .map_err(|_| ControlError::Closed)?
                    .thread
                    .snapshot()
                    .execution,
            )
        };
        let Some(execution) = execution else {
            return Err(ControlError::StaleExecution(target.into()));
        };
        let interrupted = thread
            .interrupt_execution(execution.id.clone())
            .await
            .map_err(ControlError::service)?;
        Ok(AgentInterruptResult {
            target: target_agent,
            execution_id: execution.id,
            interrupted,
        })
    }

    async fn close(
        &self,
        context: AgentCallContext,
        target: &str,
        options: pl_tool::collaboration::thread::AgentCloseOptions,
    ) -> Result<AgentCloseOutcome, ControlError> {
        let caller_id = self.caller(&context)?;
        let caller = caller_id.as_str();
        let target_id = self.target_thread(target)?;
        let target = target_id.as_str();
        let owner = self.owner()?;
        let root_operation = owner.agent_operation(caller).await;
        self.validate_instance()?;
        let services = owner.0.state().agent_services.clone();
        if let Some(services) = services {
            let admission = owner.clone();
            let root = caller.to_owned();
            let caller = caller.to_owned();
            let target_id = target.to_owned();
            let outcome = services
                .operations
                .clone()
                .run(
                    caller.clone(),
                    format!("close:{}:{target}:{}", target.len(), options.force),
                    move || {
                        admission.ensure_agent_admission_open(&root)?;
                        anyhow::ensure!(
                            admission
                                .0
                                .state()
                                .entries
                                .get(&root)
                                .is_some_and(|entry| entry.identity.parent_agent_id.is_none()),
                            "only a root may close child agents"
                        );
                        Ok(())
                    },
                    Box::pin(async move {
                        services
                            .close_child_tree(owner, caller, target_id, options, root_operation)
                            .await
                    }),
                )
                .await
                .map_err(|error| {
                    ControlError::service(super::agent_services::ServiceError(error))
                })?;
            return Ok(outcome);
        }
        Err(ControlError::service(super::agent_services::ServiceError(
            anyhow::anyhow!("final child retirement requires the Studio durable resource owner"),
        )))
    }
}

impl SessionRuntime {
    fn agent_host(
        &self,
        caller: &pl_protocol::AgentThreadIdentity,
        resources: AgentHostResources,
        profiles: &crate::config::AgentProfilesSnapshot,
        selection: pl_protocol::DelegationSettings,
    ) -> Result<AgentHost, ThreadAssemblyError> {
        let mut catalog = profiles
            .catalog
            .executable(selection.mode)
            .map_err(|source| ThreadAssemblyError::Resource {
                operation: "read executable Agent Profile catalog",
                source: Box::new(source),
            })?;
        catalog.profiles.retain(|profile| {
            profile.definition.definition_id != crate::config::ROOT_AGENT_ROUTE_KEY
                && !crate::agent::definition::is_root_definition_id(
                    &profile.definition.definition_id,
                )
                && (!matches!(resources, AgentHostResources::Acp(_))
                    || profile.workspace_mode != pl_protocol::AgentWorkspaceMode::Review)
        });
        Ok(AgentHost {
            registry: Arc::downgrade(&self.0),
            identity: caller.clone(),
            resources,
            catalog,
            selection,
        })
    }

    pub(crate) fn acp_agent_host(
        &self,
        caller: &pl_protocol::AgentThreadIdentity,
        resources: &Arc<crate::studio::runtime::acp_business::AcpResources>,
        profiles: &crate::config::AgentProfilesSnapshot,
        selection: pl_protocol::DelegationSettings,
    ) -> Result<AgentHost, ThreadAssemblyError> {
        self.agent_host(
            caller,
            AgentHostResources::Acp(Arc::downgrade(resources)),
            profiles,
            selection,
        )
    }

    pub(crate) fn native_agent_host(
        &self,
        caller: &pl_protocol::AgentThreadIdentity,
        resources: &Arc<crate::session::NativeResources>,
        profiles: &crate::config::AgentProfilesSnapshot,
        selection: pl_protocol::DelegationSettings,
    ) -> Result<AgentHost, ThreadAssemblyError> {
        self.agent_host(
            caller,
            AgentHostResources::Native(Arc::downgrade(resources)),
            profiles,
            selection,
        )
    }

    pub(crate) fn agent_control_tools_for_thread(
        &self,
        id: &str,
        thread: &pl_core::thread::ThreadHandle,
        profiles: &crate::config::AgentProfilesSnapshot,
        selection: pl_protocol::DelegationSettings,
    ) -> Result<Vec<Registration>, ThreadAssemblyError> {
        let (identity, resources) = {
            let state = self.0.state();
            let entry = state
                .entries
                .get(id)
                .filter(|entry| {
                    entry
                        .native()
                        .is_ok_and(|native| native.thread.same_instance(thread))
                })
                .ok_or(ThreadAssemblyError::Closed)?;
            (entry.identity.clone(), entry.native()?.resources.clone())
        };
        self.agent_control_tools(&identity, &resources, profiles, selection)
    }

    /// Creates control frontends and a query view from one published Profile generation.
    /// Tools hold a weak coordinator reference and cannot keep their registry alive.
    ///
    /// # Errors
    /// Returns catalog, schema construction, model declaration encoding or registration errors.
    pub(crate) fn agent_control_tools(
        &self,
        caller: &pl_protocol::AgentThreadIdentity,
        resources: &Arc<crate::session::NativeResources>,
        profiles: &crate::config::AgentProfilesSnapshot,
        selection: pl_protocol::DelegationSettings,
    ) -> Result<Vec<Registration>, ThreadAssemblyError> {
        let host = Arc::new(self.native_agent_host(caller, resources, profiles, selection)?);
        let profiles = host.spawn_profiles();
        let mut kinds = vec![
            AgentControlKind::Send,
            AgentControlKind::List,
            AgentControlKind::Interrupt,
            AgentControlKind::Close,
        ];
        if self.0.state().child_factory.is_some() {
            kinds.push(AgentControlKind::Spawn);
        }
        let mut tools = Vec::new();
        for kind in kinds {
            let spec = kind
                .declaration(&profiles, selection.mode)
                .map_err(|source| ThreadAssemblyError::Resource {
                    operation: "build Agent control schema",
                    source: Box::new(source),
                })?;
            if let Some(spec) = spec {
                let prepared = pl_tool::binding::prepare_registration(
                    spec.name(),
                    &spec,
                    pl_model::completion::ToolCallPolicy::DirectOnly,
                )?;
                tools.push(
                    ThreadAgentControl::new(host.clone(), kind, spec, caller.clone(), {
                        let host = host.clone();
                        move || host.validate_instance()
                    })
                    .registration(prepared),
                );
            }
        }
        tools.extend(self.agent_query_tools(host, selection)?);
        Ok(tools)
    }
}

#[cfg(test)]
pub(crate) mod archive_tests {
    //! Real spawn/assembly/retained-disposal interleavings; only the physical factory is a fixture.
    use super::*;
    use pl_core::tool::{ToolOutput, opaque::ToolError};

    fn host(owner: &SessionRuntime, id: &str) -> AgentHost {
        let state = owner.0.state();
        let entry = &state.entries[id];
        AgentHost {
            registry: Arc::downgrade(&owner.0),
            identity: entry.identity.clone(),
            resources: AgentHostResources::Native(Arc::downgrade(
                &entry.native().unwrap().resources,
            )),
            catalog: Default::default(),
            selection: crate::studio::delegation::saved(&entry.native().unwrap().thread.snapshot())
                .unwrap()
                .unwrap_or_default(),
        }
    }

    use crate::thread_assembler::{ChildThreadRequest, StudioChildFactory, StudioThreadSpec};
    use pl_core::thread::extensions::ExtensionMutation;
    use std::{
        collections::BTreeMap,
        future::Future,
        sync::{
            Mutex,
            atomic::{AtomicBool, Ordering},
        },
        task::Poll,
    };

    pub(crate) fn spec(
        id: String,
        parent_id: Option<String>,
        root: &std::path::Path,
    ) -> StudioThreadSpec {
        let info = pl_model::model::ModelInfo::compatible("archive-fixture");
        let route = pl_model::config::ResolvedModelRoute {
            pricing_mode: Default::default(),
            role: crate::config::root_agent_route_id(),
            account_id: pl_model::config::AccountId::new("archive-fixture").unwrap(),
            endpoint: pl_model::protocol::ProtocolEndpoint::compatible(
                "archive fixture",
                "http://127.0.0.1:0",
            ),
            context: info.resolve_context(None),
            model: info,
            effort: None,
        };
        let profile = pl_protocol::AgentProfileSnapshot {
            profile_id: "fixture".into(),
            display_name: "fixture".into(),
            description: String::new(),
            when_to_use: String::new(),
            system_instructions: String::new(),
            account_id: "archive-fixture".into(),
            model_id: "archive-fixture".into(),
            effort: None,
            source: "fixture".into(),
            revision: "1".into(),
            content_hash: "fixture".into(),
            system: false,
            enabled: true,
            workspace_mode: pl_protocol::AgentWorkspaceMode::Directory,
        };
        StudioThreadSpec {
            workspace_usage: None,
            preparation_guard: None,
            context_preparation: None,
            agent_controls: Vec::new(),
            execution: pl_core::thread::input::InputDriverOptions {
                max_model_steps: pl_core::thread::ModelStepLimit::Unlimited,
            },
            id,
            parent_id,
            model: pl_model::runtime::ThreadModel::new(
                pl_model::runtime::ModelRuntime::from_route(&route).unwrap(),
                None,
            ),
            route,
            model_available: false,
            checkpoint: None,
            initial_context: Vec::new(),
            initial_runtime_facts: Vec::new(),
            initial_extensions: BTreeMap::from([(
                crate::studio::model_route::AGENT_PROFILE_EXTENSION.into(),
                crate::studio::model_route::encode_profile(&profile).unwrap(),
            )]),
            tools: Vec::new(),
            resources: pl_core::context::ResourceAccess::new(
                crate::resource_store::FileResourceStore::new(root.join("resources")),
            ),
            capacity: Default::default(),
            cold_store: None,
        }
    }

    #[derive(Debug)]
    struct SpawnFactory {
        id: Arc<Mutex<Option<String>>>,
        release: Arc<tokio::sync::Semaphore>,
        dispositions: Arc<Mutex<Vec<pl_tool::collaboration::thread::WorkspaceRelease>>>,
        root: std::path::PathBuf,
    }
    impl StudioChildFactory for SpawnFactory {
        type Admission = ();

        async fn admit(
            &self,
            _: &str,
            _: pl_protocol::DelegationSettings,
            _: Option<pl_protocol::studio::NewThreadModelRoute>,
        ) -> Result<(), ThreadAssemblyError> {
            Ok(())
        }

        async fn prepare(
            &self,
            request: ChildThreadRequest,
            _: (),
        ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
            *self.id.lock().unwrap() = Some(request.id.clone());
            self.release.acquire().await.unwrap().forget();
            Ok(spec(request.id, Some(request.caller), &self.root))
        }

        async fn discard_unpublished(
            &self,
            _: &str,
            _: Option<&crate::studio::WorkspaceUsageLease>,
            disposition: pl_tool::collaboration::thread::WorkspaceRelease,
        ) -> Result<(), ThreadAssemblyError> {
            self.dispositions.lock().unwrap().push(disposition);
            Ok(())
        }
    }

    #[derive(Debug)]
    struct UnsupportedAdmission;

    impl StudioChildFactory for UnsupportedAdmission {
        type Admission = ();

        async fn admit(
            &self,
            _: &str,
            _: pl_protocol::DelegationSettings,
            _: Option<pl_protocol::studio::NewThreadModelRoute>,
        ) -> Result<(), ThreadAssemblyError> {
            Err(ThreadAssemblyError::UnsupportedBackend {
                backend: pl_protocol::AgentBackendKind::Acp,
            })
        }

        async fn prepare(
            &self,
            _: ChildThreadRequest,
            _: (),
        ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
            panic!("unsupported admission must not enter preparation")
        }

        async fn discard_unpublished(
            &self,
            _: &str,
            _: Option<&crate::studio::WorkspaceUsageLease>,
            _: pl_tool::collaboration::thread::WorkspaceRelease,
        ) -> Result<(), ThreadAssemblyError> {
            panic!("unsupported admission must not own unpublished resources")
        }
    }

    /// Product environment replacement only; reservation, spawn ownership and failed disposal remain real.
    pub(crate) async fn spawn_failed_archive_fixture(
        owner: SessionRuntime,
        root: String,
        factory: impl StudioChildFactory,
    ) -> Result<AgentSpawnResult, ControlError> {
        owner.0.state().child_factory = Some(crate::thread_assembler::children::ChildFactory::new(
            factory,
        ));
        let context = AgentCallContext {
            caller: pl_protocol::AgentId::new(root.clone()).unwrap(),
            call_id: "archive-first-write".into(),
            cancellation: Default::default(),
        };
        let request = AgentSpawn {
            profile_id: "fixture".into(),
            model_selection: None,
            task_summary: "archive first write".to_owned().try_into().unwrap(),
            message: "never delivered".into(),
            writable_paths: None,
            review_target_agent_id: None,
            review_feedback: None,
            metadata: serde_json::Value::Null,
        };
        let permit = owner.agent_operation(&root).await;
        host(&owner, &root)
            .spawn_owned(owner, context, request, permit)
            .await
    }

    #[tokio::test]
    async fn unsupported_profile_fails_outer_spawn_before_reservation_or_review_workspace() {
        let root = tempfile::tempdir().unwrap();
        let owner = SessionRuntime::default();
        owner.set_child_factory(UnsupportedAdmission).unwrap();
        owner.install_explicit_activation(crate::thread_assembler::ThreadActivation::native_test(
            "root", None,
        ));
        let parent = owner
            .assemble(spec("root".into(), None, root.path()))
            .await
            .unwrap();
        parent
            .mutate_extensions(vec![ExtensionMutation::Put {
                id: crate::studio::delegation::EXTENSION.into(),
                expected_revision: None,
                payload: crate::studio::delegation::encode(Default::default()).unwrap(),
            }])
            .await
            .unwrap();
        let context = AgentCallContext {
            caller: pl_protocol::AgentId::new("root").unwrap(),
            call_id: "unsupported-spawn".into(),
            cancellation: Default::default(),
        };
        let request = AgentSpawn {
            profile_id: "acp-profile".into(),
            model_selection: None,
            task_summary: "must reject before review".to_owned().try_into().unwrap(),
            message: "must never be delivered".into(),
            writable_paths: None,
            review_target_agent_id: Some("root".into()),
            review_feedback: None,
            metadata: serde_json::Value::Null,
        };
        let permit = owner.agent_operation("root").await;
        let error = host(&owner, "root")
            .spawn_owned(owner.clone(), context, request, permit)
            .await
            .unwrap_err();
        assert!(matches!(
            match &error {
                ControlError::Service(source) => source.downcast_ref::<ThreadAssemblyError>(),
                _ => None,
            },
            Some(ThreadAssemblyError::UnsupportedBackend {
                backend: pl_protocol::AgentBackendKind::Acp
            })
        ));
        let state = owner.0.state();
        assert!(state.preparing_children.is_empty());
        assert!(state.unpublished_children.is_empty());
        assert_eq!(state.entries.len(), 1);
    }

    #[tokio::test]
    async fn archive_spawn_publication_failure_releases_child_permit_and_joins_root_spawn() {
        let root = tempfile::tempdir().unwrap();
        let owner = SessionRuntime::default();
        let id = Arc::new(Mutex::new(None));
        let release = Arc::new(tokio::sync::Semaphore::new(0));
        let dispositions = Arc::new(Mutex::new(Vec::new()));
        owner
            .set_child_factory(SpawnFactory {
                id: id.clone(),
                release: release.clone(),
                dispositions: dispositions.clone(),
                root: root.path().into(),
            })
            .unwrap();
        let observed = Arc::new(AtomicBool::new(false));
        let observed_child = observed.clone();
        owner
            .observe_assembly(
                move |id, _, _| {
                    if id != "root" {
                        observed_child.store(true, Ordering::SeqCst);
                    }
                },
                |_, _| Box::pin(async { Ok(()) }),
                None,
                |_, _, _| Box::pin(async { Ok(()) }),
                |_| Box::pin(async { Ok(()) }),
            )
            .unwrap();
        owner.install_explicit_activation(crate::thread_assembler::ThreadActivation::native_test(
            "root", None,
        ));
        let parent = owner
            .assemble(spec("root".into(), None, root.path()))
            .await
            .unwrap();
        parent
            .mutate_extensions(vec![ExtensionMutation::Put {
                id: crate::studio::delegation::EXTENSION.into(),
                expected_revision: None,
                payload: crate::studio::delegation::encode(Default::default()).unwrap(),
            }])
            .await
            .unwrap();
        let context = AgentCallContext {
            caller: pl_protocol::AgentId::new("root").unwrap(),
            call_id: "spawn".into(),
            cancellation: Default::default(),
        };
        let request = AgentSpawn {
            profile_id: "fixture".into(),
            model_selection: None,
            task_summary: "archive publication race".to_owned().try_into().unwrap(),
            message: "must never be delivered".into(),
            writable_paths: None,
            review_target_agent_id: None,
            review_feedback: None,
            metadata: serde_json::Value::Null,
        };
        let host = host(&owner, "root");
        let parent_operation = owner.agent_operation("root").await;
        let spawn = host.spawn_owned(owner.clone(), context, request, parent_operation);
        tokio::pin!(spawn);
        assert!(futures::poll!(&mut spawn).is_pending());
        let child_id = id.lock().unwrap().clone().unwrap();
        // The spawn is parked inside the factory's release gate, before child assembly; give the
        // child the same explicit typed identity the standalone roots use.
        owner.install_explicit_activation(crate::thread_assembler::ThreadActivation::native_test(
            &child_id,
            Some("root"),
        ));
        let child_operation = owner.agent_operation(&child_id).await;
        release.add_permits(1);
        // The observer runs at the end of real assembly. With no review target or services there
        // is no await from that callback until spawn_owned queues on the held publication permit.
        futures::future::poll_fn(|cx| {
            assert!(spawn.as_mut().poll(cx).is_pending());
            if observed.load(Ordering::SeqCst) {
                Poll::Ready(())
            } else {
                Poll::Pending
            }
        })
        .await;
        let child = owner.observed_thread(&child_id).unwrap();
        assert!(child.snapshot().inputs.is_empty());
        let scope = owner.seal_archive_scope(&["root".into()]).unwrap();
        drop(child_operation);
        let result = tokio::time::timeout(std::time::Duration::from_secs(2), &mut spawn)
            .await
            .expect("publish rejection must not deadlock its own retained-disposal permit");
        assert!(result.is_err());
        tokio::time::timeout(
            std::time::Duration::from_secs(2),
            owner.drain_archive_preparations(&scope),
        )
        .await
        .expect("the failed spawn must also release the root permit")
        .unwrap();
        assert_eq!(
            *dispositions.lock().unwrap(),
            vec![pl_tool::collaboration::thread::WorkspaceRelease::Preserve]
        );
        assert!(owner.observed_thread(&child_id).is_none());
        assert!(child.snapshot().inputs.is_empty());
        drop(scope);
        owner.close("root").await.unwrap();
    }

    #[derive(Debug)]
    struct FailClosedFlush {
        sink: crate::studio::storage_fault_test_support::ThreadStorageSink,
        fail: Arc<AtomicBool>,
    }

    #[derive(Debug, Default, Clone)]
    struct RejectFirstDeletionResourceClose(Arc<std::sync::atomic::AtomicUsize>);

    impl pl_agent_tool::Tool for RejectFirstDeletionResourceClose {
        type Input = OpaquePayload;
        type Context = pl_core::tool::opaque::CallContext;
        type Output = ToolOutput;
        type Error = ToolError;

        fn definition(&self) -> &pl_agent_tool::ToolDefinition {
            static DEFINITION: std::sync::LazyLock<pl_agent_tool::ToolDefinition> =
                std::sync::LazyLock::new(|| {
                    pl_agent_tool::ToolDefinition::text(
                        "close-probe",
                        "Deletion resource close probe",
                    )
                    .expect("valid definition")
                });
            &DEFINITION
        }

        async fn execute(
            &self,
            _: OpaquePayload,
            _: pl_core::tool::opaque::CallContext,
        ) -> Result<ToolOutput, ToolError> {
            Err(ToolError::new(std::io::Error::other("unused fixture tool")))
        }

        async fn close(&self) -> Result<(), ToolError> {
            if self.0.fetch_add(1, Ordering::SeqCst) == 0 {
                return Err(ToolError::new(std::io::Error::other(
                    "retained deletion resource close failed once",
                )));
            }
            Ok(())
        }
    }

    #[tokio::test]
    async fn deletion_joins_original_binding_after_queued_attachment_is_sealed_closed()
    -> anyhow::Result<()> {
        use crate::{
            studio::{
                StudioStore,
                storage_fault_test_support::{ThreadStorageSink, register_test_thread},
                store::thread_preparation::PreparationIdentity,
            },
            thread_assembler::CloseStorage,
        };
        use futures::FutureExt;
        use pl_core::thread::ThreadError;

        for execution in [true, false] {
            let temp = tempfile::tempdir()?;
            let store = StudioStore::open(temp.path().join("home/data/studio.sqlite")).await?;
            let mut protocol = pl_protocol::Thread::placeholder("sealed-attachment");
            protocol.workspace_id = "workspace".into();
            protocol.root_thread_id = protocol.id.clone();
            register_test_thread(&store, &protocol).await?;
            let owner = SessionRuntime::default();
            let registration =
                Registration::prepare("close-probe".into(), OpaquePayload::text("probe"))?;
            let resource = RejectFirstDeletionResourceClose::default();
            let mut prepared = spec(protocol.id.clone(), None, temp.path());
            prepared
                .tools
                .push(registration.attach(pl_agent_tool::ToolHandle::new(resource.clone())));
            owner.install_explicit_activation(
                crate::thread_assembler::ThreadActivation::native_test(
                    &protocol.id,
                    protocol.parent_thread_id.as_deref(),
                ),
            );
            let thread = owner.assemble(prepared).await?;
            let sink = ThreadStorageSink::new(store.clone(), protocol.clone(), None).await?;
            let binding = Arc::new(sink.binding());
            drop(sink);
            let completing_thread = thread.clone();
            let storage = binding.storage.clone();
            let completion = async move {
                completing_thread
                    .attach_storage(storage)
                    .await
                    .map_err(Arc::new)
            }
            .boxed()
            .shared();
            owner
                .0
                .state()
                .entries
                .get_mut(&protocol.id)
                .unwrap()
                .native_mut()
                .unwrap()
                .close_storage = Some(if execution {
                CloseStorage::Execution {
                    completion: completion.clone(),
                    binding: Some(binding.clone()),
                    preparation_storage: None,
                    observation_installed: false,
                    joined: false,
                }
            } else {
                CloseStorage::Attaching {
                    binding: binding.clone(),
                    completion: completion.clone(),
                }
            });
            // This current-thread test enqueues AttachCold without yielding to the serial core.
            // The retained completion therefore exists before deletion seals admission.
            let mut queued = completion.clone();
            assert!(futures::poll!(&mut queued).is_pending());
            owner.prepare_deletion(std::slice::from_ref(&protocol.id));
            assert!(
                matches!(queued.await, Err(error) if matches!(error.as_ref(), ThreadError::Closed))
            );
            assert!(!thread.snapshot().persistence.attached);
            assert!(
                owner.attach_close_storage(&protocol.id).await.is_err(),
                "preserving close must still require successful attachment"
            );
            let members = [PreparationIdentity {
                thread_id: protocol.id.clone(),
                workspace_id: protocol.workspace_id.clone(),
                parent_id: None,
                root_id: protocol.id.clone(),
            }];
            let failure = owner
                .close_tree_for_deletion(&protocol.id, &members)
                .await
                .expect_err("a true resource close failure must retain the owner");
            // The delete dependency graph propagates branch failures as SubtreeClose; the
            // original resource-close failure stays the sole first cause with no siblings.
            assert!(
                matches!(
                    &failure,
                    ThreadAssemblyError::SubtreeClose {
                        first,
                        ..
                    } if matches!(first.as_ref(), ThreadAssemblyError::Thread(ThreadError::Tool(_)))
                ),
                "{failure:?}"
            );
            assert_eq!(resource.0.load(Ordering::SeqCst), 1);
            assert!(owner.observed_thread(&protocol.id).is_some());
            assert!(
                !binding.channel.deletion_joined(),
                "resource failure cannot count as a writer join"
            );
            assert!(
                matches!(completion.peek(), Some(Err(error)) if matches!(error.as_ref(), ThreadError::Closed))
            );
            if !execution {
                assert!(
                    matches!(
                        owner.0.state().entries[&protocol.id]
                            .native()
                            .unwrap()
                            .close_storage,
                        Some(CloseStorage::Attaching { .. })
                    ),
                    "a rejected attachment must not become Attached"
                );
            }
            owner
                .close_tree_for_deletion(&protocol.id, &members)
                .await?;
            assert!(
                binding.channel.deletion_joined(),
                "the original writer must actually join"
            );
            assert!(owner.observed_thread(&protocol.id).is_none());
            assert_eq!(thread.snapshot().lifecycle, ThreadLifecycle::Closed);
            assert_eq!(resource.0.load(Ordering::SeqCst), 2);
            assert!(!thread.snapshot().persistence.attached);
            owner
                .close_tree_for_deletion(&protocol.id, &members)
                .await?;
            store.close().await?;
        }
        Ok(())
    }
    impl pl_core::thread::cold::ColdStore for FailClosedFlush {
        fn pressure(&self, thread_id: &str) -> pl_core::thread::cold::StoragePressure {
            self.sink.pressure(thread_id)
        }

        fn admit(
            &self,
            thread_id: &str,
            write: pl_core::thread::cold::ThreadWrite,
        ) -> Result<(), pl_core::thread::cold::ColdStoreError> {
            if write.checkpoint.state.lifecycle == ThreadLifecycle::Closed {
                self.fail.store(true, Ordering::SeqCst);
            }
            self.sink.admit(thread_id, write)
        }

        async fn flush(
            &self,
            thread_id: &str,
            sequence: u64,
        ) -> Result<(), pl_core::thread::cold::ColdStoreError> {
            // The real writer may have committed Closed even though its caller never received a
            // successful flush ACK. Preserve its real pressure; never invent a durable watermark.
            self.sink.flush(thread_id, sequence).await?;
            if self.fail.load(Ordering::SeqCst) {
                return Err(pl_core::thread::cold::ColdStoreError {
                    source: Box::new(std::io::Error::other(
                        "injected closed checkpoint flush failure",
                    )),
                });
            }
            Ok(())
        }
    }

    #[tokio::test]
    async fn archive_setup_failure_before_observer_retains_original_storage_until_real_flush_ack()
    -> anyhow::Result<()> {
        use crate::studio::{
            StudioStore,
            storage_fault_test_support::{
                ThreadStorageSink, close_factory, register_test_thread,
                spawn_live_projection_for_thread,
            },
            store::thread_preparation::{PreparationIdentity, PreparationSave},
        };
        use anyhow::Context;
        use pl_core::thread::cold::ColdStoreHandle;
        let temp = tempfile::tempdir()?;
        let database = temp.path().join("home/data/studio.sqlite");
        let store = StudioStore::open(&database).await.with_context(|| {
            format!(
                "open current storage-ACK fixture product database {}",
                database.display()
            )
        })?;
        let factory = close_factory(&store)?;
        let owner = SessionRuntime::default();
        factory.install(&owner)?;
        let mut protocol = pl_protocol::Thread::placeholder("private-setup");
        protocol.workspace_id = "workspace".into();
        protocol.root_thread_id = protocol.id.clone();
        register_test_thread(&store, &protocol).await?;
        let host_temp = store.registered_session_paths(&protocol.id)?.temp_dir();
        let pending_file = host_temp.join("pending-private-setup");
        tokio::fs::write(
            &pending_file,
            b"not disposable before the original save ACK",
        )
        .await?;
        store
            .begin_thread_preparation(PreparationIdentity {
                thread_id: protocol.id.clone(),
                workspace_id: protocol.workspace_id.clone(),
                parent_id: None,
                root_id: protocol.id.clone(),
            })
            .await?;
        let sink = ThreadStorageSink::new(store.clone(), protocol.clone(), None).await?;
        let projection = spawn_live_projection_for_thread(store.clone(), &protocol.id);
        let failure = Arc::new(AtomicBool::new(false));
        let mut prepared = spec(protocol.id.clone(), None, temp.path());
        prepared.cold_store = Some(ColdStoreHandle::new(FailClosedFlush {
            sink,
            fail: failure.clone(),
        }));
        // Invalid extension initialization occurs after AttachCold but before publish_observation.
        prepared.initial_extensions.insert(
            String::new(),
            OpaquePayload::text("invalid extension identity"),
        );
        owner.install_explicit_activation(crate::thread_assembler::ThreadActivation::native_test(
            &protocol.id,
            None,
        ));
        let result = owner.assemble(prepared).await;
        assert!(matches!(result, Err(ThreadAssemblyError::Cleanup { .. })));
        assert!(
            failure.load(Ordering::SeqCst),
            "real close reached the failing flush"
        );
        let retained = owner
            .observed_thread(&protocol.id)
            .expect("original storage owner");
        assert!(retained.flush().await.is_err());
        assert_eq!(retained.snapshot().lifecycle, ThreadLifecycle::Closed);
        {
            let state = owner.0.state();
            assert!(matches!(
                state.entries[&protocol.id].native().unwrap().close_storage,
                Some(crate::thread_assembler::CloseStorage::Execution {
                    observation_installed: false,
                    joined: false,
                    binding: Some(_),
                    ..
                })
            ));
        }
        assert_eq!(
            store.thread_preparation(&protocol.id).await?.unwrap().save,
            PreparationSave::Required
        );
        assert!(
            owner.close(&protocol.id).await.is_err(),
            "Closed is not an ACK"
        );
        assert!(owner.observed_thread(&protocol.id).is_some());
        assert_eq!(
            tokio::fs::read(&pending_file).await?,
            b"not disposable before the original save ACK"
        );
        failure.store(false, Ordering::SeqCst);
        owner.close(&protocol.id).await?;
        assert!(owner.observed_thread(&protocol.id).is_none());
        let acknowledged = store.thread_preparation(&protocol.id).await?.unwrap();
        assert_eq!(acknowledged.save, PreparationSave::Confirmed);
        assert!(acknowledged.stopped && acknowledged.retired);
        let checkpoint = store
            .history(&protocol.id)
            .await?
            .checkpoint()
            .await?
            .unwrap();
        assert_eq!(checkpoint.state.lifecycle, ThreadLifecycle::Closed);
        projection.await?;
        factory.shutdown().await?;
        Ok(())
    }
}

#[cfg(test)]
mod control_tests {
    //! Real Native owners and tool bindings; only physical preparation is replaced.
    use super::*;
    use crate::thread_assembler::{
        ChildThreadRequest, StudioChildFactory, StudioThreadSpec, ThreadActivation,
    };
    use pl_agent_tool::Tool;
    use pl_core::tool::opaque::CallContext;

    fn call(agent: &str) -> AgentCallContext {
        AgentCallContext {
            caller: pl_protocol::AgentId::new(agent).unwrap(),
            call_id: "trusted-call".into(),
            cancellation: Default::default(),
        }
    }

    fn native_call(thread: &str) -> CallContext {
        CallContext {
            thread_id: thread.into(),
            turn_id: "turn".into(),
            call_id: "trusted-call".into(),
            grant: Default::default(),
            context: Default::default(),
            history_fence: 0,
            model_projection: None,
            tasks: None,
            cancellation: Default::default(),
            extensions: Arc::new(Default::default()),
            catalog: Arc::from([]),
            extension_sequence: 0,
        }
    }

    fn host(owner: &SessionRuntime, thread: &str) -> Arc<AgentHost> {
        let state = owner.0.state();
        let entry = &state.entries[thread];
        Arc::new(AgentHost {
            registry: Arc::downgrade(&owner.0),
            identity: entry.identity.clone(),
            resources: AgentHostResources::Native(Arc::downgrade(
                &entry.native().unwrap().resources,
            )),
            catalog: Default::default(),
            selection: crate::studio::delegation::saved(&entry.native().unwrap().thread.snapshot())
                .unwrap()
                .unwrap_or_default(),
        })
    }

    fn frontend(host: Arc<AgentHost>, kind: AgentControlKind) -> ThreadAgentControl<AgentHost> {
        ThreadAgentControl::new(
            host.clone(),
            kind,
            kind.declaration(
                &[AgentSpawnProfile {
                    profile_id: "fixture".into(),
                    backend: pl_protocol::AgentBackendKind::Native,
                    workspace_mode: pl_protocol::AgentWorkspaceMode::Directory,
                }],
                pl_protocol::DelegationMode::default(),
            )
            .unwrap()
            .unwrap(),
            host.identity.clone(),
            move || host.validate_instance(),
        )
    }

    async fn member(
        owner: &SessionRuntime,
        root: &std::path::Path,
        thread: &str,
        agent: &str,
        parent: Option<(&str, &str)>,
    ) -> pl_core::thread::ThreadHandle {
        let mut identity = ThreadActivation::native_test(thread, parent.map(|(thread, _)| thread));
        identity.agent.session_id = owner.id().clone();
        identity.agent.agent_id = pl_protocol::AgentId::new(agent).unwrap();
        identity.agent.parent_agent_id =
            parent.map(|(_, agent)| pl_protocol::AgentId::new(agent).unwrap());
        owner.install_explicit_activation(identity);
        owner
            .assemble(archive_tests::spec(
                thread.into(),
                parent.map(|(thread, _)| thread.into()),
                root,
            ))
            .await
            .unwrap()
    }

    #[tokio::test]
    async fn product_tree_controls_native_members_with_distinct_typed_ids() {
        let dir = tempfile::tempdir().unwrap();
        let owner = SessionRuntime::default();
        member(&owner, dir.path(), "native-root", "root-member", None).await;
        member(
            &owner,
            dir.path(),
            "native-child",
            "child-member",
            Some(("native-root", "root-member")),
        )
        .await;
        {
            let mut state = owner.0.state();
            // Native binding metadata cannot redefine the product member tree.
            state
                .entries
                .get_mut("native-root")
                .unwrap()
                .native_mut()
                .unwrap()
                .parent_id = Some("irrelevant".into());
            state
                .entries
                .get_mut("native-child")
                .unwrap()
                .native_mut()
                .unwrap()
                .parent_id = None;
        }
        let root = host(&owner, "native-root");
        let mut foreign = ThreadActivation::native_test("foreign-native", None);
        foreign.agent.session_id = pl_protocol::SessionId::new("other-session").unwrap();
        owner.install_explicit_activation(foreign);
        let rejected = owner
            .assemble(archive_tests::spec(
                "foreign-native".into(),
                None,
                dir.path(),
            ))
            .await
            .unwrap_err();
        assert!(matches!(rejected, ThreadAssemblyError::Identity(_)));
        assert!(matches!(
            root.interrupt(call("root-member"), "foreign-native").await,
            Err(ControlError::Missing(_))
        ));
        let rows = root.list(call("root-member")).await.unwrap();
        assert_eq!(rows.len(), 2);
        let child = rows.iter().find(|row| row["id"] == "child-member").unwrap();
        assert_eq!(child["parentId"], "root-member");
        assert!(matches!(
            root.interrupt(call("root-member"), "child-member").await,
            Err(ControlError::StaleExecution(_))
        ));
        assert!(matches!(
            root.interrupt(call("root-member"), "root-member").await,
            Err(ControlError::Relationship { .. })
        ));
        let child = host(&owner, "native-child");
        assert!(matches!(
            child.interrupt(call("child-member"), "root-member").await,
            Err(ControlError::Relationship { .. })
        ));
        assert!(
            root.list(call("child-member")).await.is_err(),
            "trusted caller still must match the frozen binding"
        );
        assert!(owner.close_session().await.is_empty());
    }

    #[tokio::test]
    async fn old_native_tools_cannot_rebind_a_reactivated_member() {
        let dir = tempfile::tempdir().unwrap();
        let owner = SessionRuntime::default();
        member(&owner, dir.path(), "native-root", "root-member", None).await;
        let old_host = host(&owner, "native-root");
        let old = frontend(old_host.clone(), AgentControlKind::List);
        let json = || OpaquePayload::new("application/json", 1, "{}").unwrap();
        assert!(
            old.execute(json(), native_call("other-native"))
                .await
                .is_err()
        );
        assert!(
            old.execute(json(), native_call("native-root"))
                .await
                .is_ok()
        );
        owner.close("native-root").await.unwrap();
        member(&owner, dir.path(), "native-root", "root-member", None).await;
        assert!(
            old.execute(json(), native_call("native-root"))
                .await
                .is_err()
        );
        assert!(old_host.list(call("root-member")).await.is_err());
        let current = host(&owner, "native-root");
        assert_eq!(current.list(call("root-member")).await.unwrap().len(), 1);
        owner
            .0
            .state()
            .sealed_agents
            .insert("native-root".into(), 1);
        assert!(current.list(call("root-member")).await.is_err());
        owner.0.state().sealed_agents.remove("native-root");
        crate::studio::agent_close::commit(&owner.thread("native-root").unwrap())
            .await
            .unwrap();
        assert!(current.list(call("root-member")).await.is_err());
        assert!(owner.close_session().await.is_empty());
    }

    #[tokio::test]
    async fn native_send_replays_the_original_receipt_and_rejects_changed_body() {
        let dir = tempfile::tempdir().unwrap();
        let owner = SessionRuntime::default();
        member(&owner, dir.path(), "native-root", "root-member", None).await;
        let child = member(
            &owner,
            dir.path(),
            "native-child",
            "child-member",
            Some(("native-root", "root-member")),
        )
        .await;
        let sequence = child
            .send_message(pl_core::thread::inbox::ThreadMessage {
                kind: pl_core::context::AgentMessageKind::Report,
                id: format!(
                    "agent-message:{}:native-root:trusted-call",
                    "native-root".len()
                ),
                source_id: "agent:native-root".into(),
                payload: OpaquePayload::text("same"),
                context: vec![ContextContent::Text {
                    text: Arc::from("same"),
                }],
            })
            .await
            .unwrap();
        let tool = frontend(host(&owner, "native-root"), AgentControlKind::Send);
        let input = |body: &str| {
            OpaquePayload::new(
                "application/json",
                1,
                serde_json::json!({"target":"child-member", "message":body}).to_string(),
            )
            .unwrap()
        };
        let receipt = tool
            .execute(input("same"), native_call("native-root"))
            .await
            .unwrap();
        let receipt: serde_json::Value = serde_json::from_str(receipt.payload().content()).unwrap();
        assert_eq!(receipt["sequence"], sequence);
        assert_eq!(receipt["target"], "child-member");
        assert!(
            tool.execute(input("changed"), native_call("native-root"))
                .await
                .is_err()
        );
        assert_eq!(child.snapshot().inbox_sequence, sequence);
        assert!(
            child.snapshot().execution.is_none(),
            "a duplicate must not start or stop execution"
        );
        assert!(child.snapshot().inputs.is_empty());
        assert!(owner.close_session().await.is_empty());
    }

    #[derive(Debug)]
    struct PhysicalFactory {
        owner: Weak<Registry>,
        path: std::path::PathBuf,
        wait_for_cancel: bool,
    }

    impl StudioChildFactory for PhysicalFactory {
        type Admission = ();
        async fn admit(
            &self,
            _: &str,
            _: pl_protocol::DelegationSettings,
            _: Option<pl_protocol::studio::NewThreadModelRoute>,
        ) -> Result<(), ThreadAssemblyError> {
            Ok(())
        }

        async fn prepare(
            &self,
            request: ChildThreadRequest,
            _: (),
        ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
            if self.wait_for_cancel {
                request.cancellation.cancelled().await;
                return Err(ThreadAssemblyError::Closed);
            }
            let mut activation = ThreadActivation::native_test(&request.id, Some(&request.caller));
            let owner = SessionRuntime(self.owner.upgrade().unwrap());
            activation.agent.session_id = owner.id().clone();
            activation.agent.parent_agent_id = Some(
                owner.0.state().entries[&request.caller]
                    .identity
                    .agent_id
                    .clone(),
            );
            owner.install_explicit_activation(activation);
            let mut spec = archive_tests::spec(request.id, Some(request.caller), &self.path);
            let assignment = pl_protocol::AgentWorkspaceAssignmentSnapshot {
                mode: pl_protocol::AgentWorkspaceMode::Directory,
                project_root: self.path.to_string_lossy().into_owned(),
                root: self.path.to_string_lossy().into_owned(),
                writable_paths: Some(Vec::new()),
                worktree: None,
                review_target: None,
            };
            spec.initial_extensions.insert(
                crate::studio::workspace_receipt::EXTENSION.into(),
                crate::studio::workspace_receipt::to_payload(&assignment).unwrap(),
            );
            Ok(spec)
        }

        async fn discard_unpublished(
            &self,
            _: &str,
            _: Option<&crate::studio::WorkspaceUsageLease>,
            _: pl_tool::collaboration::thread::WorkspaceRelease,
        ) -> Result<(), ThreadAssemblyError> {
            Ok(())
        }
    }

    async fn spawning_owner(
        path: &std::path::Path,
        fail_initial: bool,
        wait_for_cancel: bool,
    ) -> SessionRuntime {
        let owner = SessionRuntime::default();
        owner
            .observe_assembly(
                |_, _, _| {},
                |_, _| Box::pin(async { Ok(()) }),
                Some(Arc::new(move |_, message| {
                    Box::pin(async move {
                        if fail_initial && message.starts_with("initial:") {
                            Err(ThreadAssemblyError::Resource {
                                operation: "lookup initial message identity",
                                source: Box::new(std::io::Error::other(
                                    "fixture message index unavailable",
                                )),
                            })
                        } else {
                            Ok(None)
                        }
                    })
                })),
                |_, _, _| Box::pin(async { Ok(()) }),
                |_| Box::pin(async { Ok(()) }),
            )
            .unwrap();
        owner
            .set_child_factory(PhysicalFactory {
                owner: Arc::downgrade(&owner.0),
                path: path.into(),
                wait_for_cancel,
            })
            .unwrap();
        let root = member(&owner, path, "native-root", "root-member", None).await;
        root.mutate_extensions(vec![pl_core::thread::extensions::ExtensionMutation::Put {
            id: crate::studio::delegation::EXTENSION.into(),
            expected_revision: None,
            payload: crate::studio::delegation::encode(Default::default()).unwrap(),
        }])
        .await
        .unwrap();
        owner
    }

    #[tokio::test]
    async fn published_spawn_input_failure_keeps_child_identity_and_source() {
        let dir = tempfile::tempdir().unwrap();
        let owner = spawning_owner(dir.path(), true, false).await;
        let request: AgentSpawn = pl_agent_tool::typed::decode_json(
            r#"{"profileId":"fixture","taskSummary":"test","message":"first input"}"#,
        )
        .unwrap();
        let result = host(&owner, "native-root")
            .spawn(call("root-member"), request)
            .await
            .unwrap();
        assert!(!result.receipt.message_accepted);
        assert!(result.receipt.message_sequence.is_none());
        assert!(owner.thread(&result.receipt.agent_id).is_some());
        assert_eq!(
            result.receipt.workspace.as_ref().unwrap().root,
            dir.path().to_string_lossy()
        );
        let control = result.message_error.unwrap();
        assert!(
            std::error::Error::source(&control)
                .unwrap()
                .is::<ThreadAssemblyError>()
        );
        assert_eq!(
            std::error::Error::source(std::error::Error::source(&control).unwrap())
                .unwrap()
                .to_string(),
            "fixture message index unavailable"
        );
        assert!(owner.close_session().await.is_empty());
    }

    #[tokio::test]
    async fn preparing_capacity_and_root_policy_use_product_membership() {
        let dir = tempfile::tempdir().unwrap();
        let owner = spawning_owner(dir.path(), false, false).await;
        let request: AgentSpawn = pl_agent_tool::typed::decode_json(
        r#"{"profileId":"fixture","taskSummary":"invalid review","message":"test","reviewTargetAgentId":"root-member"}"#,
    ).unwrap();
        let error = host(&owner, "native-root")
            .spawn(call("root-member"), request)
            .await
            .unwrap_err();
        assert!(matches!(
            error,
            ControlError::Service(source) if matches!(source.downcast_ref::<ThreadAssemblyError>(), Some(ThreadAssemblyError::ReviewTargetInvalid(_)))
        ));
        assert!(owner.0.state().unpublished_children.is_empty());
        member(
            &owner,
            dir.path(),
            "native-child",
            "child-member",
            Some(("native-root", "root-member")),
        )
        .await;
        {
            let mut state = owner.0.state();
            state
                .entries
                .get_mut("native-root")
                .unwrap()
                .native_mut()
                .unwrap()
                .parent_id = Some("irrelevant".into());
            state
                .entries
                .get_mut("native-child")
                .unwrap()
                .native_mut()
                .unwrap()
                .parent_id = None;
        }
        assert!(matches!(
            owner.reserve_child(&call("child-member")),
            Err(ThreadAssemblyError::ChildDepth)
        ));
        let mut reservations = Vec::new();
        let context = call("root-member");
        for _ in 0..14 {
            reservations.push(owner.reserve_child(&context).unwrap().1);
        }
        assert!(matches!(
            owner.reserve_child(&call("root-member")),
            Err(ThreadAssemblyError::ChildCapacity(16))
        ));
        assert_eq!(
            host(&owner, "native-root")
                .list(call("root-member"))
                .await
                .unwrap()
                .len(),
            16
        );
        context.cancellation.cancel();
        assert!(
            !reservations[0].cancellation.is_cancelled(),
            "call cancellation is not child lifetime"
        );
        drop(reservations);
        assert!(owner.close_session().await.is_empty());
    }

    #[tokio::test]
    async fn call_cancellation_settles_the_original_unpublished_preparation() {
        let dir = tempfile::tempdir().unwrap();
        let owner = spawning_owner(dir.path(), false, true).await;
        let context = call("root-member");
        let cancellation = context.cancellation.clone();
        let request = pl_agent_tool::typed::decode_json(
            r#"{"profileId":"fixture","taskSummary":"cancel preparation","message":"test"}"#,
        )
        .unwrap();
        let host = host(&owner, "native-root");
        let spawn = host.spawn(context, request);
        tokio::pin!(spawn);
        assert!(futures::poll!(&mut spawn).is_pending());
        assert_eq!(owner.0.state().unpublished_children.len(), 1);
        cancellation.cancel();
        assert!(
            tokio::time::timeout(std::time::Duration::from_secs(2), spawn)
                .await
                .unwrap()
                .is_err()
        );
        assert!(owner.0.state().unpublished_children.is_empty());
        assert!(owner.0.state().preparing_children.is_empty());
        assert!(owner.close_session().await.is_empty());
    }

    mod publication_commit {
        use super::*;
        use crate::studio::{
            ProductEventBus, StudioStore, storage_fault_test_support::close_factory,
        };
        use pl_core::model::{
            DynModelSession, Model, ModelError, ModelFactory, ModelRequest, ModelSession,
            ModelStepOutput, ModelToolCall, PreparedModelCall,
        };
        use sea_orm::ConnectionTrait;

        struct PersistentFactory {
            physical: PhysicalFactory,
            events: ProductEventBus,
        }

        impl std::fmt::Debug for PersistentFactory {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.write_str("PersistentFactory")
            }
        }

        impl StudioChildFactory for PersistentFactory {
            type Admission = ();

            async fn admit(
                &self,
                _: &str,
                _: pl_protocol::DelegationSettings,
                _: Option<pl_protocol::studio::NewThreadModelRoute>,
            ) -> Result<(), ThreadAssemblyError> {
                Ok(())
            }

            async fn prepare(
                &self,
                request: ChildThreadRequest,
                _: (),
            ) -> Result<StudioThreadSpec, ThreadAssemblyError> {
                let mut record = pl_protocol::Thread::placeholder(&request.id);
                record.workspace_id = "publication-project".into();
                record.root_thread_id = SessionRuntime(self.physical.owner.upgrade().unwrap())
                    .id()
                    .to_string();
                record.parent_thread_id = Some(request.caller.clone());
                record.workspace_path = self.physical.path.to_string_lossy().into_owned();
                self.events
                    .commit_test_thread(&record)
                    .await
                    .map_err(|source| ThreadAssemblyError::Resource {
                        operation: "commit fixture child directory",
                        source: source.into(),
                    })?;
                self.physical.prepare(request, ()).await
            }

            async fn discard_unpublished(
                &self,
                _: &str,
                _: Option<&crate::studio::WorkspaceUsageLease>,
                _: pl_tool::collaboration::thread::WorkspaceRelease,
            ) -> Result<(), ThreadAssemblyError> {
                Ok(())
            }
        }

        struct SpawnModel;
        struct SpawnSession(bool);
        impl Model for SpawnModel {
            async fn open_session(&self) -> Result<DynModelSession, ModelError> {
                Ok(DynModelSession::new(SpawnSession(false)))
            }
        }
        impl ModelSession for SpawnSession {
            async fn prepare(
                &mut self,
                request: ModelRequest,
            ) -> Result<PreparedModelCall, ModelError> {
                let calls = if std::mem::replace(&mut self.0, true) {
                    Vec::new()
                } else {
                    vec![ModelToolCall {
                    call_id: "publish-commit".into(),
                    tool_id: "spawn_agent".into(),
                    arguments: OpaquePayload::new("application/json", 1,
                        r#"{"profileId":"fixture","taskSummary":"publication failure","message":"must not be admitted"}"#).unwrap(),
                    rejection: None,
                    presentation_contract: request.tools[0].presentation_contract.clone(),
                }]
                };
                Ok(PreparedModelCall::new(async move {
                    Ok(ModelStepOutput {
                        turn_action: Default::default(),
                        attempt_id: request.attempt_id,
                        base_context_revision: request.context.revision,
                        content: vec![ContextContent::Text {
                            text: Arc::from("fixture step"),
                        }],
                        tool_calls: calls,
                        private_context: None,
                        usage: Default::default(),
                    })
                }))
            }
            async fn close(&mut self) -> Result<(), ModelError> {
                Ok(())
            }
        }

        #[tokio::test]
        async fn sqlite_publication_failure_retains_native_receipt_and_closeable_child()
        -> anyhow::Result<()> {
            let dir = tempfile::tempdir()?;
            let store = StudioStore::open(dir.path().join("data/studio.sqlite")).await?;
            let services = close_factory(&store)?;
            let owner = SessionRuntime::open(pl_protocol::SessionId::new("native-root")?);
            owner.set_child_factory(PersistentFactory {
                physical: PhysicalFactory {
                    owner: Arc::downgrade(&owner.0),
                    path: dir.path().into(),
                    wait_for_cancel: false,
                },
                events: services.events.clone(),
            })?;
            services.install(&owner)?;
            let mut record = pl_protocol::Thread::placeholder("native-root");
            record.workspace_id = "publication-project".into();
            record.root_thread_id = "native-root".into();
            record.workspace_path = dir.path().to_string_lossy().into_owned();
            services.events.commit_test_thread(&record).await?;
            let root = member(&owner, dir.path(), "native-root", "native-root", None).await;
            root.mutate_extensions(vec![pl_core::thread::extensions::ExtensionMutation::Put {
                id: crate::studio::delegation::EXTENSION.into(),
                expected_revision: None,
                payload: crate::studio::delegation::encode(Default::default())?,
            }])
            .await?;
            let tool = frontend(host(&owner, "native-root"), AgentControlKind::Spawn);
            let prepared = pl_tool::binding::prepare_registration(
                "spawn_agent",
                tool.definition(),
                pl_model::completion::ToolCallPolicy::DirectOnly,
            )?;
            root.register_tools(vec![tool.registration(prepared)])
                .await?;
            root.replace_model(ModelFactory::new(SpawnModel)).await?;
            // Reject only the real false -> true publication write, not preparation/assembly writes.
            store
                .database()
                .execute_unprepared(
                    "CREATE TRIGGER reject_spawn_publication BEFORE UPDATE ON studio_objects
             WHEN NEW.object_kind='threadPreparation'
               AND json_extract(OLD.payload_json,'$.published')=0
               AND json_extract(NEW.payload_json,'$.published')=1
             BEGIN SELECT RAISE(ABORT,'controlled spawn publication rejection'); END",
                )
                .await?;
            tokio::time::timeout(
                std::time::Duration::from_secs(10),
                root.run_turn(pl_core::thread::TurnInput {
                    turn_id: "publish".into(),
                    attempt_prefix: "attempt-publish".into(),
                    content: vec![ContextContent::Text {
                        text: Arc::from("spawn"),
                    }],
                    max_model_steps: pl_core::thread::ModelStepLimit::Limited(3.try_into()?),
                    cancellation: Default::default(),
                }),
            )
            .await??;
            let deliveries = root
                .effects()
                .await?
                .iter()
                .flat_map(|effect| effect.deliveries.to_vec())
                .collect::<Vec<_>>();
            assert_eq!(deliveries.len(), 1);
            let delivery = &deliveries[0];
            let pl_core::thread::ToolOutcome::Failed(error) = &delivery.outcome else {
                panic!("publication rejection must remain a failed Native tool call: {delivery:?}");
            };
            assert!(error.source.is::<ControlError>(), "{error:?}");
            let mut source: Option<&(dyn std::error::Error + 'static)> = Some(error.as_ref());
            let mut database_error = false;
            while let Some(cause) = source {
                database_error |= cause.downcast_ref::<sea_orm::DbErr>().is_some();
                source = cause.source();
            }
            assert!(
                database_error,
                "the original typed SQLite error must survive Native delivery: {error:?}"
            );
            assert!(
                format!("{error}").contains("controlled spawn publication rejection"),
                "{error:?}"
            );
            assert_eq!(
                owner.0.state().entries.len(),
                2,
                "the child was already published"
            );
            assert!(owner.0.state().unpublished_children.is_empty());
            assert_eq!(
                delivery.output.payload().format(),
                "pl.studio.agent-control"
            );
            let receipt: serde_json::Value =
                serde_json::from_str(delivery.output.payload().content())?;
            assert_eq!(receipt["messageAccepted"], false);
            assert!(receipt.get("messageSequence").is_none());
            assert_eq!(
                receipt["workspace"]["root"],
                dir.path().to_string_lossy().as_ref()
            );
            let id = receipt["agentId"]
                .as_str()
                .expect("published member identity");
            let child = owner.thread(id).expect("memory publication remains ready");
            assert!(!owner.0.state().unpublished_children.contains_key(id));
            assert!(!store.thread_preparation(id).await?.unwrap().published);
            assert!(child.snapshot().inbox.is_empty());
            assert!(child.snapshot().inputs.is_empty());
            assert!(child.snapshot().execution.is_none());
            store
                .database()
                .execute_unprepared("DROP TRIGGER reject_spawn_publication")
                .await?;
            let close = host(&owner, "native-root")
                .close(call("native-root"), id, Default::default())
                .await?;
            assert_eq!(close.target, id);
            assert!(
                close
                    .agents
                    .iter()
                    .any(|agent| agent.agent_id == id && agent.execution_closed)
            );
            assert!(owner.close_session().await.is_empty());
            services.shutdown().await?;
            store.close().await?;
            Ok(())
        }
    }
}

#[cfg(test)]
mod future_sizes {
    use super::*;

    fn bounded<Input, F: std::future::Future + Send>(name: &str, _: impl FnOnce(Input) -> F) {
        let bytes = std::mem::size_of::<F>();
        eprintln!("{name}: {bytes} bytes");
        assert!(bytes <= 16 * 1024, "{name} inlines {bytes} bytes");
    }

    #[test]
    fn spawn_handoff_future_remains_bounded() {
        // Inspect the real trait future, including its managed-operation handoff.
        // The closure is never called: no fixture resources or leaked host are needed.
        bounded(
            "AgentHost spawn handoff",
            |(host, context, request): (&'static AgentHost, AgentCallContext, AgentSpawn)| {
                host.spawn(context, request)
            },
        );
    }
}

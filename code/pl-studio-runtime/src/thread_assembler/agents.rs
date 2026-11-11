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
struct AgentHost {
    registry: Weak<Registry>,
    identity: pl_protocol::AgentThreadIdentity,
    resources: Weak<crate::session::NativeResources>,
}

#[cfg(test)]
#[path = "agents_archive_tests.rs"]
pub(crate) mod archive_tests;
#[cfg(test)]
#[path = "agents_control_tests.rs"]
mod control_tests;

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

impl AgentHost {
    fn validate_instance(&self) -> Result<(), ControlError> {
        let owner = self.owner()?;
        let state = owner.0.state();
        let id = self.identity.thread_id.as_str();
        let entry = state
            .entries
            .get(id)
            .ok_or_else(|| ControlError::Missing(id.into()))?;
        let native = entry.native().map_err(|_| ControlError::Closed)?;
        if state.closing
            || state.sealed_agents.contains_key(id)
            || entry.identity != self.identity
            || !self.resources.ptr_eq(&Arc::downgrade(&native.resources))
            || !native.ready
            || native.purpose != super::EntryPurpose::Execution
            || native.workspace_disposition.is_some()
            || native.thread.snapshot().lifecycle != ThreadLifecycle::Open
        {
            return Err(ControlError::Closed);
        }
        if crate::studio::agent_close::is_explicitly_closed(&native.thread.snapshot())
            .map_err(|source| ControlError::service(super::agent_services::ServiceError(source)))?
        {
            return Err(ControlError::Closed);
        }
        Ok(())
    }

    fn caller(&self, context: &AgentCallContext) -> Result<String, ControlError> {
        self.validate_instance()?;
        if context.caller != self.identity.agent_id || context.cancellation.is_cancelled() {
            return Err(ControlError::Closed);
        }
        Ok(self.identity.thread_id.to_string())
    }

    fn target_identity(
        &self,
        target: &str,
    ) -> Result<pl_protocol::AgentThreadIdentity, ControlError> {
        let owner = self.owner()?;
        let state = owner.0.state();
        let agent = pl_protocol::AgentId::new(target).map_err(ControlError::service)?;
        if let Some(id) = state.by_agent.get(&agent) {
            let entry = &state.entries[id];
            if entry.identity.session_id == self.identity.session_id {
                return Ok(entry.identity.clone());
            }
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

    fn owner(&self) -> Result<SessionRuntime, ControlError> {
        self.registry
            .upgrade()
            .map(SessionRuntime)
            .ok_or(ControlError::Closed)
    }
}

fn ancestry(state: &State, id: &str) -> Result<Vec<String>, ControlError> {
    let mut path = Vec::new();
    let mut cursor = Some(id);
    let session = state
        .entries
        .get(id)
        .map(|entry| &entry.identity.session_id);
    while let Some(id) = cursor {
        if path.iter().any(|previous| previous == id) {
            return Err(ControlError::Ancestry);
        }
        let entry = state
            .entries
            .get(id)
            .ok_or_else(|| ControlError::Missing(id.into()))?;
        if Some(&entry.identity.session_id) != session {
            return Err(ControlError::Ancestry);
        }
        path.push(id.to_owned());
        cursor = State::membership_parent(&state.by_agent, entry);
        if entry.identity.parent_agent_id.is_some() && cursor.is_none() {
            return Err(ControlError::Ancestry);
        }
    }
    Ok(path)
}

fn descendant(state: &State, caller: &str, target: &str) -> Result<(), ControlError> {
    if !state.entries.get(caller).is_some_and(|entry| {
        entry.native().is_ok_and(|native| {
            native.ready && native.thread.snapshot().lifecycle == ThreadLifecycle::Open
        })
    }) {
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
    async fn ensure_archive_execution_admission(
        owner: &SessionRuntime,
        id: &str,
    ) -> Result<(), ControlError> {
        let services = { owner.0.state().agent_services.clone() };
        if let Some(services) = services {
            let record = services
                .store
                .read_thread(id)
                .await
                .map_err(|error| ControlError::service(super::agent_services::ServiceError(error)))?
                .ok_or_else(|| ControlError::Missing(id.to_owned()))?;
            services
                .store
                .ensure_archive_execution_allowed(&record.workspace_id, Some(id))
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
        let delegation = {
            let state = owner.0.state();
            let caller = state
                .entries
                .get(&caller)
                .ok_or_else(|| ControlError::Missing(caller.clone()))?;
            crate::studio::delegation::saved(
                &caller
                    .native()
                    .map_err(|_| ControlError::Closed)?
                    .thread
                    .snapshot(),
            )
            .map_err(|error| ControlError::service(super::agent_services::ServiceError(error)))?
            .ok_or_else(|| ControlError::Missing("saved delegation selection".into()))?
        };
        let factory = owner
            .child_factory(&context)
            .map_err(ControlError::service)?;
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
            let parent = services.record(&caller).await.map_err(|error| {
                ControlError::service(super::agent_services::ServiceError(error))
            })?;
            services
                .store
                .begin_thread_preparation(
                    crate::studio::store::thread_preparation::PreparationIdentity {
                        thread_id: reservation.id.clone(),
                        workspace_id: parent.workspace_id,
                        parent_id: Some(caller.clone()),
                        root_id: parent.root_thread_id,
                    },
                )
                .await
                .map_err(|error| {
                    ControlError::service(super::agent_services::ServiceError(error))
                })?;
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
            model,
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
            sequence,
        })
    }

    async fn list(
        &self,
        context: AgentCallContext,
    ) -> Result<Vec<serde_json::Value>, ControlError> {
        let caller_id = self.caller(&context)?;
        let caller = caller_id.as_str();
        let owner = self.owner()?;
        let mut rows = {
            let state = owner.0.state();
            if state.closing {
                return Err(ControlError::Closed);
            }
            if !state
                .entries
                .get(caller)
                .is_some_and(|entry| entry.native().is_ok_and(|native| native.ready))
            {
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
                let snapshot = entry
                    .native()
                    .map_err(|_| ControlError::Closed)?
                    .thread
                    .snapshot();
                if ancestry(&state, id)?.last() != Some(root) {
                    continue;
                }
                if !entry.native().map_err(|_| ControlError::Closed)?.ready
                    && snapshot.lifecycle == ThreadLifecycle::Open
                {
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
                    async move {
                        services
                            .close_child_tree(owner, caller, target_id, options, root_operation)
                            .await
                    },
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
        });
        let profiles = catalog
            .profiles
            .iter()
            .map(|profile| AgentSpawnProfile {
                profile_id: profile.definition.definition_id.clone(),
                workspace_mode: profile.workspace_mode,
            })
            .collect::<Vec<_>>();
        let host = Arc::new(AgentHost {
            registry: Arc::downgrade(&self.0),
            identity: caller.clone(),
            resources: Arc::downgrade(resources),
        });
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
        tools.extend(self.agent_query_tools(catalog, selection)?);
        Ok(tools)
    }
}

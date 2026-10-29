//! Product-owned relationship checks and descendant shutdown over generic Thread handles.
use super::observation::DeliveryDisposition;
use super::{Registry, State, StudioThreadAssembler, ThreadAssemblyError};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    thread::{ThreadLifecycle, input::InputState, task::TaskStatus},
    tool::{
        ToolOutput,
        opaque::{Registration, ToolError},
    },
};
use pl_tool::collaboration::thread::{
    AgentControlHost, AgentControlKind, AgentMessage, AgentSpawn, AgentSpawnProfile,
    ThreadAgentControl,
};
use std::sync::{Arc, Weak};

#[derive(Debug)]
struct AgentHost(Weak<Registry>);

#[derive(Debug, thiserror::Error)]
enum ControlError {
    #[error("agent coordinator is closed")]
    Closed,
    #[error("agent is missing or not published: {0}")]
    Missing(String),
    #[error("target {target} is not a descendant of caller {caller}")]
    Relationship { caller: String, target: String },
    #[error("invalid agent ancestry")]
    Ancestry,
    #[error("agent {0} has no current execution to stop")]
    StaleExecution(String),
}

impl AgentHost {
    fn owner(&self) -> Result<StudioThreadAssembler, ToolError> {
        self.0
            .upgrade()
            .map(StudioThreadAssembler)
            .ok_or_else(|| ToolError::new(ControlError::Closed))
    }
}

fn ancestry(state: &State, id: &str) -> Result<Vec<String>, ToolError> {
    let mut path = Vec::new();
    let mut cursor = Some(id);
    while let Some(id) = cursor {
        if path.iter().any(|previous| previous == id) {
            return Err(ToolError::new(ControlError::Ancestry));
        }
        let entry = state
            .entries
            .get(id)
            .ok_or_else(|| ToolError::new(ControlError::Missing(id.into())))?;
        path.push(id.to_owned());
        cursor = entry.parent_id.as_deref();
    }
    Ok(path)
}

fn descendant(state: &State, caller: &str, target: &str) -> Result<(), ToolError> {
    if !state.entries.get(caller).is_some_and(|entry| {
        entry.ready && entry.thread.snapshot().lifecycle == ThreadLifecycle::Open
    }) {
        return Err(ToolError::new(ControlError::Missing(caller.into())));
    }
    ancestry(state, caller)?;
    if caller == target
        || !ancestry(state, target)?
            .iter()
            .skip(1)
            .any(|id| id == caller)
    {
        return Err(ToolError::new(ControlError::Relationship {
            caller: caller.into(),
            target: target.into(),
        }));
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
) -> Result<(), ToolError> {
    let Some(parent) = parent else {
        return Ok(());
    };
    if ancestry(state, parent)?.last().is_some_and(|id| id == root) {
        rows.insert(
            id.to_owned(),
            serde_json::json!({"id":id, "parentId":parent, "lifecycle":{"kind":"preparing"}}),
        );
    }
    Ok(())
}

fn output(value: impl serde::Serialize) -> Result<ToolOutput, ToolError> {
    let encoded = serde_json::to_string(&value).map_err(ToolError::new)?;
    Ok(ToolOutput::new(
        OpaquePayload::new("pl.studio.agent-control", 1, encoded.clone())
            .map_err(ToolError::new)?,
        vec![ContextContent::Text {
            text: Arc::from(encoded),
        }],
    ))
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

#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct SpawnReceipt {
    agent_id: String,
    profile_id: String,
    model: pl_protocol::studio::NewThreadModelRoute,
    delegation: pl_protocol::DelegationSettings,
    #[serde(skip_serializing_if = "Option::is_none")]
    workspace: Option<pl_protocol::AgentWorkspaceAssignmentSnapshot>,
    message_accepted: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    message_sequence: Option<u64>,
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
    owner: &StudioThreadAssembler,
    id: &str,
    operation: ThreadAssemblyError,
) -> ToolError {
    match owner.discard_child_resources(id).await {
        Ok(()) => ToolError::new(operation),
        Err(cleanup) => ToolError::new(SpawnCleanupError {
            id: id.into(),
            operation,
            cleanup,
        }),
    }
}

impl AgentHost {
    async fn spawn_owned(
        &self,
        owner: StudioThreadAssembler,
        context: pl_core::tool::opaque::CallContext,
        request: AgentSpawn,
        _parent_operation: tokio::sync::OwnedMutexGuard<()>,
    ) -> Result<ToolOutput, ToolError> {
        owner
            .ensure_agent_admission_open(&context.thread_id)
            .map_err(ToolError::new)?;
        let (factory, reservation) = owner.reserve_child(&context).map_err(ToolError::new)?;
        let delegation = {
            let state = owner.0.state();
            let caller = state
                .entries
                .get(&context.thread_id)
                .ok_or_else(|| ToolError::new(ControlError::Missing(context.thread_id.clone())))?;
            crate::studio::delegation::saved(&caller.thread.snapshot())
                .map_err(|error| ToolError::new(super::agent_services::ServiceError(error)))?
                .ok_or_else(|| {
                    ToolError::new(ControlError::Missing("saved delegation selection".into()))
                })?
        };
        let workspace_owner = {
            owner
                .0
                .state()
                .unpublished_children
                .get(&reservation.id)
                .ok_or_else(|| ToolError::new(ControlError::Missing(reservation.id.clone())))?
                .workspace
                .clone()
        };
        let spec = factory
            .prepare(super::ChildThreadRequest {
                workspace_owner,
                id: reservation.id.clone(),
                cancellation: reservation.cancellation.clone(),
                caller: context.thread_id.clone(),
                call_id: context.call_id.clone(),
                profile_id: request.profile_id.clone(),
                model_selection: request.model_selection,
                delegation,
                task_summary: request.task_summary,
                writable_paths: request.writable_paths,
                review_target_agent_id: request.review_target_agent_id,
                metadata: OpaquePayload::new(
                    "pl.studio.agent-metadata",
                    1,
                    serde_json::to_string(&request.metadata).map_err(ToolError::new)?,
                )
                .map_err(ToolError::new)?,
            })
            .await;
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
        let options = spec.execution;
        let child = owner.assemble_child(spec, &context).await;
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
        let _operation = owner.agent_operation(&id).await;
        if let Err(error) = owner.publish_child_resources(&id) {
            return Err(cleanup_spawn_failure(&owner, &id, error).await);
        }
        let message = pl_core::thread::inbox::ThreadMessage {
            kind: pl_core::context::AgentMessageKind::Task,
            id: format!("initial:{}:{}", context.thread_id.len(), context.call_id),
            source_id: format!("agent:{}", context.thread_id),
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
        match delivery {
            Ok(sequence) => output(SpawnReceipt {
                agent_id: id,
                profile_id: request.profile_id,
                model,
                delegation,
                workspace,
                message_accepted: true,
                message_sequence: Some(sequence),
            }),
            Err(source) => Err(ToolError::new(source).with_output(output(SpawnReceipt {
                agent_id: id,
                profile_id: request.profile_id,
                model,
                delegation,
                workspace,
                message_accepted: false,
                message_sequence: None,
            })?)),
        }
    }
}

impl AgentControlHost for AgentHost {
    async fn spawn(
        &self,
        context: pl_core::tool::opaque::CallContext,
        request: AgentSpawn,
    ) -> Result<ToolOutput, ToolError> {
        let owner = self.owner()?;
        let parent_operation = owner.agent_operation(&context.thread_id).await;
        let services = owner.0.state().agent_services.clone();
        if let Some(services) = services {
            let admission = owner.clone();
            let caller = context.thread_id.clone();
            let admitted_caller = caller.clone();
            let host = AgentHost(self.0.clone());
            services
                .operations
                .run(
                    caller,
                    move || {
                        admission.ensure_agent_admission_open(&admitted_caller)?;
                        Ok(())
                    },
                    async move {
                        Ok(host
                            .spawn_owned(owner, context, request, parent_operation)
                            .await)
                    },
                )
                .await
                .map_err(|error| ToolError::new(super::agent_services::ServiceError(error)))?
        } else {
            self.spawn_owned(owner, context, request, parent_operation)
                .await
        }
    }

    async fn send(&self, caller: &str, message: AgentMessage) -> Result<ToolOutput, ToolError> {
        let owner = self.owner()?;
        let services = owner.0.state().agent_services.clone();
        if let Some(services) = &services {
            services
                .authorize(caller, &message.target)
                .await
                .map_err(|error| ToolError::new(super::agent_services::ServiceError(error)))?;
            services
                .store
                .ensure_agent_execution_allowed(&message.target)
                .await
                .map_err(|error| ToolError::new(super::agent_services::ServiceError(error)))?;
        }
        if owner.thread(&message.target).is_none() {
            let services = owner.0.state().agent_services.clone();
            if let Some(services) = services {
                services
                    .activate_child(&owner, caller, &message.target)
                    .await
                    .map_err(|error| ToolError::new(super::agent_services::ServiceError(error)))?;
            }
        }
        let _operation = owner.agent_operation(&message.target).await;
        owner
            .ensure_agent_admission_open(&message.target)
            .map_err(ToolError::new)?;
        let (target, options) = {
            let state = owner.0.state();
            if state.closing {
                return Err(ToolError::new(ControlError::Closed));
            }
            descendant(&state, caller, &message.target)?;
            let entry = state
                .entries
                .get(&message.target)
                .filter(|entry| entry.ready && entry.parent_id.as_deref() == Some(caller))
                .ok_or_else(|| {
                    ToolError::new(ControlError::Relationship {
                        caller: caller.into(),
                        target: message.target.clone(),
                    })
                })?;
            (entry.thread.clone(), entry.execution)
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
            .map_err(ToolError::new)?
        {
            DeliveryDisposition::Receipt(sequence) => sequence,
            DeliveryDisposition::New => {
                owner
                    .prepare_input_admission(&message.target, &target)
                    .await
                    .map_err(ToolError::new)?;
                target
                    .send_message_and_continue(delivery, options)
                    .await
                    .map_err(ToolError::new)?
            }
            DeliveryDisposition::Conflict => {
                return Err(ToolError::new(ThreadAssemblyError::MessageConflict(
                    message.id.clone(),
                )));
            }
            DeliveryDisposition::Unverifiable => {
                return Err(ToolError::new(ThreadAssemblyError::MessageUnverifiable(
                    message.id.clone(),
                )));
            }
        };
        output(
            serde_json::json!({"target":message.target, "messageId":message.id, "sequence":sequence}),
        )
    }

    async fn list(&self, caller: &str) -> Result<ToolOutput, ToolError> {
        let owner = self.owner()?;
        let mut rows = {
            let state = owner.0.state();
            if state.closing {
                return Err(ToolError::new(ControlError::Closed));
            }
            if !state.entries.get(caller).is_some_and(|entry| entry.ready) {
                return Err(ToolError::new(ControlError::Missing(caller.into())));
            }
            let path = ancestry(&state, caller)?;
            let root = path
                .last()
                .ok_or_else(|| ToolError::new(ControlError::Ancestry))?;
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
                let snapshot = entry.thread.snapshot();
                if ancestry(&state, id)?.last() != Some(root) {
                    continue;
                }
                if !entry.ready && snapshot.lifecycle == ThreadLifecycle::Open {
                    if !rows.contains_key(id) {
                        push_preparing_row(
                            &state,
                            root,
                            &mut rows,
                            id,
                            entry.parent_id.as_deref(),
                        )?;
                    }
                    continue;
                }
                rows.insert(
                    id.clone(),
                    agent_row(id, entry.parent_id.as_deref(), &snapshot).map_err(|error| {
                        ToolError::new(super::agent_services::ServiceError(error))
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
                    .map_err(|error| ToolError::new(super::agent_services::ServiceError(error)))?,
            );
        }
        output(rows)
    }

    async fn interrupt(&self, caller: &str, target: &str) -> Result<ToolOutput, ToolError> {
        let owner = self.owner()?;
        // The parent stops exactly the execution it observed, through the same precise stop the user
        // interfaces use. A superseded identity fails instead of cancelling whatever runs now.
        let (thread, execution) = {
            let state = owner.0.state();
            if state.closing {
                return Err(ToolError::new(ControlError::Closed));
            }
            descendant(&state, caller, target)?;
            let entry = state
                .entries
                .get(target)
                .ok_or_else(|| ToolError::new(ControlError::Missing(target.into())))?;
            (entry.thread.clone(), entry.thread.snapshot().execution)
        };
        let Some(execution) = execution else {
            return Err(ToolError::new(ControlError::StaleExecution(target.into())));
        };
        let interrupted = thread
            .interrupt_execution(execution.id.clone())
            .await
            .map_err(ToolError::new)?;
        output(serde_json::json!({
            "target":target,
            "executionId":execution.id,
            "interrupted":interrupted,
        }))
    }

    async fn close(
        &self,
        caller: &str,
        target: &str,
        options: pl_tool::collaboration::thread::AgentCloseOptions,
    ) -> Result<ToolOutput, ToolError> {
        let owner = self.owner()?;
        let root_operation = owner.agent_operation(caller).await;
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
                    move || {
                        admission.ensure_agent_admission_open(&root)?;
                        anyhow::ensure!(
                            admission
                                .0
                                .state()
                                .entries
                                .get(&root)
                                .is_some_and(|entry| entry.parent_id.is_none()),
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
                .map_err(|error| ToolError::new(super::agent_services::ServiceError(error)))?;
            let receipt = output(&outcome)?;
            return match outcome.error {
                Some(error) => Err(ToolError::new(super::agent_services::ServiceError(
                    anyhow::anyhow!(error.message),
                ))
                .with_output(receipt)),
                None => Ok(receipt),
            };
        }
        Err(ToolError::new(super::agent_services::ServiceError(
            anyhow::anyhow!("final child retirement requires the Studio durable resource owner"),
        )))
    }
}

impl StudioThreadAssembler {
    /// Creates control frontends and a query view from one published Profile generation.
    /// Tools hold a weak coordinator reference and cannot keep their registry alive.
    ///
    /// # Errors
    /// Returns catalog, schema construction, model declaration encoding or registration errors.
    pub fn agent_control_tools(
        &self,
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
            profile.profile_id != crate::config::ROOT_AGENT_ROUTE_KEY
                && !crate::agent::definition::is_root_definition_id(&profile.profile_id)
        });
        let profiles = catalog
            .profiles
            .iter()
            .map(|profile| AgentSpawnProfile {
                profile_id: profile.profile_id.clone(),
                workspace_mode: profile.workspace_mode,
            })
            .collect::<Vec<_>>();
        let host = Arc::new(AgentHost(Arc::downgrade(&self.0)));
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
                let declaration = pl_model::runtime::thread_tool_declaration(&spec)?;
                tools.push(ThreadAgentControl::new(host.clone(), kind).registration(declaration)?);
            }
        }
        tools.extend(self.agent_query_tools(catalog, selection)?);
        Ok(tools)
    }
}

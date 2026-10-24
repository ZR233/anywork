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

impl AgentControlHost for AgentHost {
    async fn spawn(
        &self,
        context: pl_core::tool::opaque::CallContext,
        request: AgentSpawn,
    ) -> Result<ToolOutput, ToolError> {
        let owner = self.owner()?;
        // Root preparation and directory enumeration share the root→child lock order. A tree
        // archive cannot miss a child whose workspace was still being prepared at enumeration.
        let _parent_operation = owner.agent_operation(&context.thread_id).await;
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
        let spec = factory
            .prepare(super::ChildThreadRequest {
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
            return Err(cleanup_spawn_failure(
                &owner,
                &reservation.id,
                pl_core::thread::ThreadError::Cancelled.into(),
            )
            .await);
        }
        if spec.id != reservation.id {
            return Err(cleanup_spawn_failure(
                &owner,
                &reservation.id,
                ThreadAssemblyError::Identity(spec.id),
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

    async fn send(&self, caller: &str, message: AgentMessage) -> Result<ToolOutput, ToolError> {
        let owner = self.owner()?;
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
            let mut rows = Vec::new();
            for (id, entry) in &state.entries {
                let snapshot = entry.thread.snapshot();
                if (!entry.ready && snapshot.lifecycle == ThreadLifecycle::Open)
                    || ancestry(&state, id)?.last() != Some(root)
                {
                    continue;
                }
                rows.push(
                    agent_row(id, entry.parent_id.as_deref(), &snapshot).map_err(|error| {
                        ToolError::new(super::agent_services::ServiceError(error))
                    })?,
                );
            }
            rows
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
        let thread = {
            let state = owner.0.state();
            if state.closing {
                return Err(ToolError::new(ControlError::Closed));
            }
            descendant(&state, caller, target)?;
            state
                .entries
                .get(target)
                .ok_or_else(|| ToolError::new(ControlError::Missing(target.into())))?
                .thread
                .clone()
        };
        let interrupted = thread.interrupt_turn(None).await.map_err(ToolError::new)?;
        output(serde_json::json!({"target":target,"interrupted":interrupted}))
    }

    async fn close(
        &self,
        caller: &str,
        target: &str,
        disposition: pl_tool::collaboration::thread::AgentWorkspaceDisposition,
    ) -> Result<ToolOutput, ToolError> {
        let owner = self.owner()?;
        let root_operation = owner.agent_operation(caller).await;
        let services = owner.0.state().agent_services.clone();
        if let Some(services) = services {
            let admission = owner.clone();
            let root = caller.to_owned();
            let caller = caller.to_owned();
            let target_id = target.to_owned();
            services
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
                            .close_child_tree(owner, caller, target_id, disposition, root_operation)
                            .await
                    },
                )
                .await
                .map_err(|error| ToolError::new(super::agent_services::ServiceError(error)))?;
            return output(
                serde_json::json!({"target":target,"lifecycle":ThreadLifecycle::Closed,"workspaceDisposition":disposition}),
            );
        }
        let mut targets = {
            let state = owner.0.state();
            if state.closing {
                return Err(ToolError::new(ControlError::Closed));
            }
            descendant(&state, caller, target)?;
            let mut targets = Vec::new();
            for id in state.entries.keys() {
                let path = ancestry(&state, id)?;
                if path.iter().any(|ancestor| ancestor == target) {
                    targets.push((path.len(), id.clone()));
                }
            }
            targets
        };
        targets.sort_by(|left, right| right.0.cmp(&left.0).then_with(|| left.1.cmp(&right.1)));
        let _seals = owner
            .seal_agent_close(&targets, disposition)
            .await
            .map_err(ToolError::new)?;
        drop(root_operation);
        for (_, id) in targets {
            owner.close(&id).await.map_err(ToolError::new)?;
        }
        output(
            serde_json::json!({"target":target,"lifecycle":ThreadLifecycle::Closed,"workspaceDisposition":disposition}),
        )
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

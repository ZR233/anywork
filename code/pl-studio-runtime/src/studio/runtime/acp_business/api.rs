use std::sync::Arc;

use crate::acp_schema::ContentBlock;
use crate::protocol::*;
use crate::{AcpSessionReference, AgentBackend};
use anyhow::{Context, Result, ensure};
use futures::FutureExt;
use pl_acp::session as sdk;

use super::{AcpResources, AcpSessionCompletion, AcpSessionObservation, projection};
use crate::studio::records::{
    AcpDirectoryTitle, AcpTitleLabel, AgentDirectoryRecord, SessionDirectoryRecord,
};
use crate::studio::runtime::StudioRuntime;
use crate::studio::runtime::thread_title::provisional_title;

/// An accepted product member and its original SDK observation. A resident
/// member returns the same target and no second observation/connection.
pub struct AcpSessionOpen {
    pub target: AcpSessionTarget,
    pub observation: Option<AcpSessionObservation>,
    pub completion: AcpSessionCompletion,
    pub info_snapshot: Option<AcpSessionInfoSnapshot>,
    pub workflow_state: Option<AcpWorkflowStateSnapshot>,
}

/// Immutable leases of existing service owners; never holds a StudioRuntime or SessionTable.
#[derive(Clone)]
pub(crate) struct AcpBusinessOwner {
    factory: crate::studio::StudioThreadFactory,
    config: crate::config::ConfigRuntime,
    store: crate::studio::StudioStore,
    events: crate::studio::ProductEventBus,
    connections: crate::studio::runtime::acp_accounts::AcpAccountRuntime,
    thread_modes: crate::mode::ThreadModeManager,
}

struct MemberOpen {
    owner: crate::thread_assembler::SessionRuntime,
    identity: crate::AgentThreadIdentity,
    project: crate::studio::WorkspaceRecord,
    definition: crate::config::AcpServiceDefinition,
    session_record: SessionDirectoryRecord,
    previous: Option<AgentDirectoryRecord>,
    intent: AcpOpenIntent,
    cwd: Option<String>,
    business_root: String,
    role: String,
    title: Option<String>,
    usage: Option<crate::studio::WorkspaceUsageLease>,
    cancellation: Option<tokio_util::sync::CancellationToken>,
}

struct PendingOpen {
    target: AcpSessionTarget,
    resources: std::sync::Arc<AcpResources>,
    opening: tokio::sync::oneshot::Receiver<Result<sdk::Observer, AcpBusinessFailure>>,
}

impl PendingOpen {
    async fn observe(self) -> Result<AcpSessionOpen> {
        let observer = self
            .opening
            .await
            .context("ACP preparation stopped before observation")??;
        let workflow_state = self.resources.workflow_snapshot();
        let workflow_updates = self.resources.subscribe_workflow();
        Ok(AcpSessionOpen {
            target: self.target,
            observation: Some(AcpSessionObservation::new(
                observer,
                self.resources.completion.clone(),
                workflow_updates,
            )),
            completion: self.resources.completion.clone(),
            info_snapshot: None,
            workflow_state,
        })
    }
}

impl AcpBusinessOwner {
    pub(crate) async fn activate_child(
        &self,
        owner: &crate::thread_assembler::SessionRuntime,
        caller: &str,
        target: &str,
    ) -> Result<Arc<AcpResources>> {
        if let Some(resources) = owner.resident_acp(target)? {
            resources.completion.wait().await?;
            return Ok(resources);
        }
        let member = self.factory.directory_member(target)?;
        let parent = self.factory.directory_member(caller)?;
        ensure!(
            member.agent.parent_agent_id.as_deref() == Some(parent.agent.agent_id.as_str())
                && member.session.session_id == parent.session.session_id,
            "ACP activation requires a direct child"
        );
        self.factory.ensure_member_execution_allowed(target).await?;
        let AgentBackend::Acp { reference } = &member.agent.backend else {
            anyhow::bail!("ACP activation requires an ACP member");
        };
        let definitions = self.config.read_acp_definitions();
        let entry = definitions
            .definitions
            .get(&reference.account_id)
            .context("ACP account is missing")?;
        let definition = self
            .config
            .resolve_acp_definition(&reference.account_id, entry.connection_revision)?;
        let project = self
            .store
            .read_project(&member.session.workspace_id)
            .await?
            .context("ACP workspace is missing")?;
        let cwd = reference.cwd.clone();
        let business_root = self.factory.acp_business_root(target, &member.session);
        let usage = self.factory.reserve_workspace_use(target, &project).await?;
        self.factory
            .verify_acp_workspace(target, &project, &business_root)
            .await?;
        let identity = self
            .events
            .agent_execution_identity(target)
            .context("ACP member identity is missing")?
            .0;
        let pending = self.begin_open(MemberOpen {
            owner: owner.clone(),
            identity,
            project,
            definition,
            session_record: member.session,
            previous: Some(member.agent.clone()),
            intent: AcpOpenIntent::Load {
                session_id: reference.acp_session_id.clone(),
            },
            cwd: Some(cwd),
            business_root,
            role: member.agent.role,
            title: member.agent.title,
            usage: Some(usage),
            cancellation: None,
        })?;
        let resources = pending.resources.clone();
        let observer = pending
            .opening
            .await
            .context("ACP child observation stopped")??;
        resources.retain_observer(observer).await?;
        resources.completion.wait().await?;
        Ok(resources)
    }

    pub(crate) async fn open_child(
        &self,
        owner: &crate::thread_assembler::SessionRuntime,
        request: &crate::thread_assembler::ChildThreadRequest,
        profile: &crate::AgentProfile,
        definition: crate::config::AcpServiceDefinition,
    ) -> Result<(Arc<AcpResources>, crate::AgentWorkspaceAssignmentSnapshot)> {
        ensure!(
            profile.workspace_mode != crate::AgentWorkspaceMode::Review
                && request.model_selection.is_none()
                && request.writable_paths.is_none()
                && request.review_target_agent_id.is_none()
                && request.review_feedback.is_none(),
            "ACP target supports ordinary tasks only"
        );
        let prepared = self
            .factory
            .prepare_acp_child_workspace(request, profile.workspace_mode)
            .await?;
        let pending = self.begin_open(MemberOpen {
            owner: owner.clone(),
            identity: prepared.child_identity,
            project: prepared.project,
            definition,
            session_record: prepared.parent.session,
            previous: None,
            intent: AcpOpenIntent::New,
            cwd: None,
            business_root: prepared.assignment.root.clone(),
            role: profile.definition.definition_id.clone(),
            title: Some(request.task_summary.as_str().to_owned()),
            usage: Some(prepared.workspace_usage),
            cancellation: Some(request.cancellation.clone()),
        })?;
        let resources = pending.resources.clone();
        let observer = pending
            .opening
            .await
            .context("ACP child observation stopped")??;
        resources.retain_observer(observer).await?;
        let completion = resources.completion.wait();
        tokio::pin!(completion);
        tokio::select! {
            result = &mut completion => result?,
            () = request.cancellation.cancelled() => {
                resources.cancel();
                completion.await?;
            }
        }
        Ok((resources.clone(), prepared.assignment))
    }

    pub(in crate::studio::runtime) fn new(
        factory: crate::studio::StudioThreadFactory,
        config: crate::config::ConfigRuntime,
        store: crate::studio::StudioStore,
        events: crate::studio::ProductEventBus,
        connections: crate::studio::runtime::acp_accounts::AcpAccountRuntime,
        thread_modes: crate::mode::ThreadModeManager,
    ) -> Self {
        Self {
            factory,
            config,
            store,
            events,
            connections,
            thread_modes,
        }
    }

    fn begin_open(&self, request: MemberOpen) -> Result<PendingOpen> {
        let MemberOpen {
            owner,
            identity,
            project,
            definition,
            mut session_record,
            previous,
            intent,
            cwd,
            mut business_root,
            role,
            title,
            usage,
            cancellation,
        } = request;
        let agent_id = identity.agent_id.to_string();
        let thread_id = identity.thread_id.to_string();
        let now = crate::studio::ids::unix_seconds();
        let (publication, published) = tokio::sync::watch::channel(None);
        let completion = AcpSessionCompletion {
            publication: published,
        };
        let draft = matches!(&intent, AcpOpenIntent::Draft { .. });
        let requested_mode = match &intent {
            AcpOpenIntent::Draft { mode, .. } => mode.clone(),
            _ => None,
        };
        let is_root = identity.parent_agent_id.is_none();
        let resources = AcpResources::new(project.id.clone(), completion.clone(), draft);
        if identity.parent_agent_id.is_some() && previous.is_none() {
            resources.begin_initial_configuration();
        }
        let preparation =
            owner.prepare_acp(identity.clone(), definition.id.clone(), resources.clone())?;
        let accepted = AcpSessionTarget {
            session_id: session_record.session_id.clone(),
            agent_id: agent_id.clone(),
            thread_id: thread_id.clone(),
            instance: resources.instance,
        };
        let factory = self.factory.clone();
        let events = self.events.clone();
        let connections = self.connections.clone();
        let config = self.config.clone();
        let store = self.store.clone();
        let thread_modes = self.thread_modes.clone();
        let calls = self.store.calls().clone();
        let sample_thread_id = thread_id.clone();
        let sample_generation = resources.generation.clone();
        let sample_account_id = definition.id.clone();
        let sample_account_name = definition.display_name.clone();
        let resources_for_result = resources.clone();
        let baseline = previous
            .as_ref()
            .map(|agent| (session_record.clone(), agent.clone()));
        let (started, opening) = tokio::sync::oneshot::channel();
        tokio::spawn(async move {
            let mut started = Some(started);
            let operation = {
                let operation = std::panic::AssertUnwindSafe(async {
                    let account = connections.acquire_for_business(&definition).map_err(|_| {
                        projection::preparation("ACP account connection is closing or stale")
                    })?;
                    let workspace_cancel = resources.cancellation.child_token();
                    let ready_cancel = resources.cancellation.child_token();
                    let workspace_task = async {
                        let draft_worktree = if draft
                            && session_record.workspace_mode == crate::ThreadWorkspaceMode::Worktree
                        {
                            resources
                                .retain_draft_worktree(factory.clone(), thread_id.clone())
                                .await;
                            let lease = factory
                                .prepare_acp_root_worktree(&thread_id, &project)
                                .await
                                .map_err(|error| projection::preparation(&error.to_string()))?;
                            business_root = lease.path.clone();
                            session_record.workspace_path = business_root.clone();
                            Some(lease)
                        } else {
                            None
                        };
                        let usage = match usage {
                            Some(usage) => usage,
                            None => factory
                                .reserve_workspace_use(&thread_id, &project)
                                .await
                                .map_err(|_| {
                                    projection::preparation("ACP workspace admission failed")
                                })?,
                        };
                        let cwd = factory
                            .prepare_acp_protocol_cwd(
                                &thread_id,
                                &project,
                                &business_root,
                                cwd.as_deref(),
                            )
                            .await
                            .map_err(|error| projection::preparation(&error.to_string()))?;
                        {
                            let workspace_config = config
                                .read()
                                .map_err(|error| projection::preparation(&error.to_string()))?
                                .config;
                            let binding = factory
                                .prepare_acp_workspace(
                                    crate::studio::thread_factory::AcpWorkspaceRequest {
                                        id: &thread_id,
                                        project: &project,
                                        business_root: &business_root,
                                        usage: &usage,
                                        session_mode: session_record.workspace_mode,
                                        config: &workspace_config,
                                        cancellation: &workspace_cancel,
                                    },
                                )
                                .await
                                .map_err(|error| projection::preparation(&error.to_string()))?;
                            let tools = super::super::acp_workspace_tools::WorkspaceTools::new(
                                thread_id.clone(),
                                binding,
                                &workspace_config,
                            );
                            resources
                                .retain_workspace_tools(tools, usage.clone())
                                .await
                                .map_err(|error| projection::preparation(&error.to_string()))?;
                        }
                        if workspace_cancel.is_cancelled() {
                            return Err(projection::preparation("ACP preparation cancelled"));
                        }
                        if let Some(lease) = &draft_worktree {
                            factory
                                .confirm_acp_worktree(lease, &usage, &preparation)
                                .await
                                .map_err(|error| projection::preparation(&error.to_string()))?;
                        }
                        Ok::<_, AcpBusinessFailure>((usage, cwd))
                    };
                    let ready_task = async {
                        tokio::select! {
                            biased;
                            () = ready_cancel.cancelled() => {
                                Err(projection::preparation("ACP preparation cancelled"))
                            }
                            result = account.ready_business() => result,
                        }
                    };
                    let (workspace_result, prepared_result) = tokio::join!(
                        async {
                            let result = workspace_task.await;
                            if result.is_err() && !workspace_cancel.is_cancelled() {
                                ready_cancel.cancel();
                            }
                            result
                        },
                        async {
                            let result = ready_task.await;
                            if result.is_err() && !ready_cancel.is_cancelled() {
                                workspace_cancel.cancel();
                            }
                            result
                        }
                    );
                    let (usage, cwd, prepared) = match (workspace_result, prepared_result) {
                        (Ok((usage, cwd)), Ok(prepared)) => (usage, cwd, prepared),
                        (Ok(_), Err(error)) => return Err(error),
                        (Err(error), Ok(_)) => return Err(error),
                        (Err(workspace_error), Err(prepared_error)) => {
                            if !ready_cancel.is_cancelled() {
                                return Err(prepared_error);
                            }
                            return Err(workspace_error);
                        }
                    };
                    let res_dir = store
                        .session_resources_dir_for(&project.id, &thread_id)
                        .map_err(|error| projection::preparation(&error.to_string()))?;
                    let wp_owner = super::AcpWorkflowPlanOwner::load_or_init(
                        thread_id.clone(),
                        is_root,
                        res_dir,
                        thread_modes,
                        requested_mode,
                    )
                    .await
                    .map_err(|error| projection::preparation(&error.to_string()))?;
                    resources
                        .retain_workflow_plan(wp_owner)
                        .map_err(|error| projection::preparation(&error.to_string()))?;
                    let intent = match intent {
                        AcpOpenIntent::New | AcpOpenIntent::Draft { .. } => sdk::Open::New,
                        AcpOpenIntent::Load { session_id: id } => sdk::Open::Load(id.into()),
                        AcpOpenIntent::Resume { session_id: id } => sdk::Open::Resume(id.into()),
                    };
                    let observer = resources
                        .observe(sdk::OpenRequest {
                            cwd: cwd.clone(),
                            intent,
                            prepare: Some(
                                crate::studio::runtime::acp_host_mcp::prepare_open(
                                    &owner,
                                    &identity,
                                    &resources,
                                    &config,
                                    &cwd,
                                    crate::DelegationSettings {
                                        mode: session_record.delegation_mode,
                                        preference: session_record.delegation_preference,
                                    },
                                )
                                .await
                                .map_err(|error| projection::preparation(&error.to_string()))?,
                            ),
                            expected_server_version: prepared.expected_version,
                            on_text_performance: Some(Arc::new(
                                move |run, evidence, model, effort| {
                                    calls.record_acp_performance(
                                        crate::studio::storage::calls::AcpPerformanceObservation {
                                            thread_id: sample_thread_id.clone(),
                                            call_id: format!(
                                                "acp:{sample_generation}:{}",
                                                run.sequence
                                            ),
                                            account_id: sample_account_id.clone(),
                                            account_name: sample_account_name.clone(),
                                            model,
                                            effort,
                                            performance: projection::text_performance(evidence),
                                        },
                                    );
                                },
                            )),
                            cleanup: pl_acp::auth::CleanupBudget::new(
                                std::time::Duration::from_secs(5),
                            ),
                        })
                        .await
                        .map_err(|_| {
                            projection::preparation("ACP observation could not be installed")
                        })?;
                    // The original SDK window is handed out before any protocol IO starts.
                    let _ = started
                        .take()
                        .expect("single observation")
                        .send(Ok(observer));
                    resources
                        .start(account, prepared.protocol, usage)
                        .await
                        .map_err(|_| projection::preparation("ACP business launch failed"))?;
                    let session = resources
                        .session()
                        .map_err(|_| projection::preparation("ACP is not initialized"))?;
                    let remote_id = tokio::select! {
                        biased;
                        result = session.opened() => result.map_err(projection::failure)?,
                        () = resources.cancellation.cancelled() => {
                            let _ = resources.close().await;
                            session.opened().await.map_err(projection::failure)?
                        },
                    };
                    let reference = AcpSessionReference {
                        account_id: definition.id,
                        acp_session_id: remote_id.to_string(),
                        cwd: cwd.clone(),
                    };
                    let backend = AgentBackend::Acp {
                        reference: reference.clone(),
                    };
                    let mut agent = previous.unwrap_or_else(|| AgentDirectoryRecord {
                        agent_id,
                        thread_id,
                        session_id: session_record.session_id.clone(),
                        parent_agent_id: identity.parent_agent_id.as_ref().map(ToString::to_string),
                        role,
                        title,
                        backend: backend.clone(),
                        explicitly_closed: false,
                        created_at: now,
                        updated_at: now,
                    });
                    agent.backend = backend;
                    agent.updated_at = crate::studio::ids::unix_seconds();
                    if identity.parent_agent_id.is_none() {
                        session_record.updated_at = agent.updated_at;
                    }
                    // Preserve a successful peer identity even if final publication loses to close.
                    resources
                        .retain_association(session_record, agent, baseline)
                        .await;
                    resources
                        .settle_association(&events)
                        .await
                        .map_err(|error| {
                            let mut failure = projection::preparation(&error.to_string());
                            failure.kind = AcpBusinessFailureKind::Publication;
                            failure
                        })?;
                    preparation
                        .publish()
                        .map_err(|_| projection::preparation("ACP publication was closed"))?;
                    if identity.parent_agent_id.is_some() {
                        owner
                            .publish_acp_child_resources(identity.thread_id.as_str())
                            .map_err(|error| projection::preparation(&error.to_string()))?;
                    } else {
                        resources
                            .start_title_projection(
                                events.clone(),
                                identity.thread_id.to_string(),
                                reference,
                                session.title_changes(),
                            )
                            .await;
                    }
                    owner
                        .bind_acp_result_delivery(&identity, &resources)
                        .await
                        .map_err(|error| projection::preparation(&error.to_string()))?;
                    Ok::<_, AcpBusinessFailure>(())
                })
                .catch_unwind();
                tokio::pin!(operation);
                tokio::select! {
                    result = &mut operation => result,
                    () = async {
                        match cancellation {
                            Some(cancellation) => cancellation.cancelled_owned().await,
                            None => std::future::pending::<()>().await,
                        }
                    } => {
                        resources.cancel();
                        operation.await
                    }
                }
            };
            let mut result = operation
                .unwrap_or_else(|_| Err(projection::preparation("ACP preparation panicked")));
            if result.is_err() {
                let outcome = resources.close().await;
                if let (Err(error), Some(exit)) = (&mut result, outcome.exit) {
                    error.auth_methods = projection::methods(exit.auth_methods);
                }
            }
            if let Some(started) = started {
                let error =
                    result.as_ref().err().cloned().unwrap_or_else(|| {
                        projection::preparation("ACP observation was not prepared")
                    });
                let _ = started.send(Err(error));
            }
            // Reservation remains in the original Session until every cleanup await above ends.
            publication.send_replace(Some(result));
            drop(preparation);
        });
        Ok(PendingOpen {
            target: accepted,
            resources: resources_for_result,
            opening,
        })
    }
}

impl StudioRuntime {
    pub async fn open_acp_session(&self, request: OpenAcpSessionRequest) -> Result<AcpSessionOpen> {
        let lifecycle = self.thread_lifecycle_admission().await?;
        let project = self
            .store
            .read_project(&request.workspace_id)
            .await?
            .context("ACP workspace is missing")?;
        self.ensure_project_thread_admission_open(&project.id)?;
        let now = crate::studio::ids::unix_seconds();
        let mut _admission = None;
        let existing = request
            .thread_id
            .as_deref()
            .map(|id| {
                self.agent_facility
                    .product_events
                    .directory_facts(id)
                    .context("ACP product member is missing")
            })
            .transpose()?;
        let (mut session_record, previous, agent_id, thread_id) = if let Some((session, agent)) =
            existing
        {
            ensure!(
                session.workspace_id == request.workspace_id
                    && !session.archived
                    && !agent.explicitly_closed
                    && (agent.parent_agent_id.is_some() || session.root_agent_id == agent.agent_id),
                "ACP product membership is not executable"
            );
            let AgentBackend::Acp { reference } = &agent.backend else {
                return Err(projection::failure(sdk::Error::Unsupported).into());
            };
            ensure!(
                reference.account_id == request.account_id,
                "ACP account binding differs"
            );
            let owner = self
                .sessions
                .materialize(&crate::SessionId::new(session.session_id.clone())?)?;
            // The existing per-member admission permit serializes cold preparation
            // registration, not protocol open or product publication.
            _admission = Some(owner.agent_operation(&agent.thread_id).await);
            if let Some(acp) = owner.resident_acp(&agent.thread_id)? {
                let info_snapshot = match acp.session() {
                    Ok(session) => session
                        .snapshot()
                        .await
                        .ok()
                        .and_then(|snapshot| projection::info_snapshot(&snapshot)),
                    Err(_) => None,
                };
                let workflow_state = acp.workflow_snapshot();
                let workflow_updates = acp.subscribe_workflow();
                return Ok(AcpSessionOpen {
                    target: target(&session, &agent, &acp),
                    observation: acp.take_observation().await.map(|observer| {
                        AcpSessionObservation::new(
                            observer,
                            acp.completion.clone(),
                            workflow_updates,
                        )
                    }),
                    completion: acp.completion.clone(),
                    info_snapshot,
                    workflow_state,
                });
            }
            let id = match &request.intent {
                AcpOpenIntent::Load { session_id: id }
                | AcpOpenIntent::Resume { session_id: id } => id,
                AcpOpenIntent::New | AcpOpenIntent::Draft { .. } => {
                    anyhow::bail!("existing ACP association requires Load or Resume")
                }
            };
            ensure!(
                id == &reference.acp_session_id
                    && (project.ssh_alias.is_some()
                        || agent.parent_agent_id.is_some()
                        || reference.cwd == session.workspace_path),
                "ACP remote session reference differs"
            );
            let business_root = self
                .thread_factory
                .acp_business_root(&agent.thread_id, &session);
            self.thread_factory
                .verify_acp_workspace(&agent.thread_id, &project, &business_root)
                .await?;
            let agent_id = agent.agent_id.clone();
            let thread_id = agent.thread_id.clone();
            (session, Some(agent), agent_id, thread_id)
        } else {
            let session_id = crate::studio::ids::new_id("session");
            let agent_id = crate::studio::ids::new_id("agent");
            let thread_id = crate::studio::ids::new_id("acp");
            let delegation = self.config_runtime.read()?.config.delegation;
            let (workspace_mode, delegation_mode, delegation_preference) = match &request.intent {
                AcpOpenIntent::Draft {
                    workspace_mode,
                    delegation_mode,
                    delegation_preference,
                    mode: _,
                } => (
                    *workspace_mode,
                    delegation_mode.unwrap_or(delegation.mode),
                    delegation_preference.unwrap_or(delegation.preference),
                ),
                _ => (
                    crate::ThreadWorkspaceMode::Local,
                    delegation.mode,
                    delegation.preference,
                ),
            };
            (
                SessionDirectoryRecord {
                    session_id: session_id.clone(),
                    root_agent_id: agent_id.clone(),
                    workspace_id: request.workspace_id.clone(),
                    title: request.account_id.clone(),
                    acp_title: Some(AcpDirectoryTitle {
                        label: match &request.intent {
                            AcpOpenIntent::New | AcpOpenIntent::Draft { .. } => {
                                AcpTitleLabel::AwaitingInput
                            }
                            AcpOpenIntent::Load { .. } | AcpOpenIntent::Resume { .. } => {
                                AcpTitleLabel::Fallback
                            }
                        },
                        peer: None,
                    }),
                    native_mode: None,
                    workspace_mode,
                    delegation_mode,
                    delegation_preference,
                    workspace_path: project.path.clone(),
                    created_at: now,
                    updated_at: now,
                    last_user_message_at: None,
                    archived: false,
                },
                None,
                agent_id,
                thread_id,
            )
        };
        // Freeze exactly once. No asynchronous stage rereads or changes the definition.
        let definition = self
            .config_runtime
            .resolve_acp_definition(&request.account_id, request.expected_connection_revision)?;
        if previous.is_none() {
            session_record.title = match &request.intent {
                AcpOpenIntent::New | AcpOpenIntent::Draft { .. } => provisional_title(""),
                AcpOpenIntent::Load { .. } | AcpOpenIntent::Resume { .. } => {
                    definition.display_name.clone()
                }
            };
        }
        let identity = crate::AgentThreadIdentity {
            session_id: crate::SessionId::new(session_record.session_id.clone())?,
            agent_id: crate::AgentId::new(agent_id.clone())?,
            parent_agent_id: previous
                .as_ref()
                .and_then(|agent| agent.parent_agent_id.as_ref())
                .map(|id| crate::AgentId::new(id.clone()))
                .transpose()?,
            thread_id: crate::ThreadId::new(thread_id.clone())?,
        };
        let owner = self.sessions.materialize(&identity.session_id)?;
        let business = AcpBusinessOwner::new(
            self.thread_factory.clone(),
            self.config_runtime.clone(),
            self.store.clone(),
            self.agent_facility.product_events.clone(),
            self.acp_accounts.clone(),
            self.thread_modes.clone(),
        );
        let cwd = match &previous {
            Some(agent) => match &agent.backend {
                AgentBackend::Acp { reference } => Some(reference.cwd.clone()),
                _ => unreachable!("ACP association checked"),
            },
            None => None,
        };
        let business_root = self
            .thread_factory
            .acp_business_root(&thread_id, &session_record);
        let role = previous.as_ref().map_or_else(
            || crate::config::ROOT_AGENT_ROUTE_KEY.into(),
            |agent| agent.role.clone(),
        );
        let title = previous.as_ref().and_then(|agent| agent.title.clone());
        let pending = business.begin_open(MemberOpen {
            owner,
            identity,
            project,
            definition,
            session_record,
            previous,
            intent: request.intent,
            cwd,
            business_root,
            role,
            title,
            usage: None,
            cancellation: None,
        })?;
        // The original Session already owns preparation before either admission lock is released.
        drop(_admission);
        drop(lifecycle);
        pending.observe().await
    }

    fn business_resources(
        &self,
        target: &AcpSessionTarget,
    ) -> Result<Arc<AcpResources>, AcpBusinessFailure> {
        let id = crate::SessionId::new(target.session_id.clone())
            .map_err(|_| projection::failure(sdk::Error::Stale))?;
        let owner = self
            .sessions
            .get(&id)
            .ok_or_else(|| projection::failure(sdk::Error::Closed))?;
        owner
            .acp_resources(&target.thread_id, &target.agent_id, target.instance)
            .map_err(|error| {
                projection::failure(match error {
                    crate::thread_assembler::ThreadAssemblyError::Preparing(_) => {
                        sdk::Error::NotReady
                    }
                    crate::thread_assembler::ThreadAssemblyError::Closed => sdk::Error::Closed,
                    crate::thread_assembler::ThreadAssemblyError::UnsupportedBackend { .. } => {
                        sdk::Error::Unsupported
                    }
                    _ => sdk::Error::Stale,
                })
            })
    }

    /// Publishes the prepared association with a provisional title from the frozen user text.
    pub async fn commit_acp_draft(
        &self,
        target: AcpSessionTarget,
        first_prompt_text: &str,
    ) -> Result<(), AcpBusinessFailure> {
        let resources = self.business_resources(&target)?;
        resources.completion.wait().await?;
        resources
            .commit_draft(&self.agent_facility.product_events, first_prompt_text)
            .await
            .map_err(|error| projection::preparation(&error.to_string()))
    }

    pub async fn prompt_acp_session(
        &self,
        target: AcpSessionTarget,
        content: Vec<ContentBlock>,
    ) -> Result<AcpRunId, AcpBusinessFailure> {
        let resources = self.business_resources(&target)?;
        resources
            .ensure_input_ready()
            .map_err(projection::failure)?;
        if !resources.association_published().await {
            return Err(projection::failure(sdk::Error::NotReady));
        }
        let events = &self.agent_facility.product_events;
        let first = events
            .directory_facts(&target.thread_id)
            .and_then(|(session, agent)| {
                if !agent.is_root_agent()
                    || session.acp_title?.label != AcpTitleLabel::AwaitingInput
                {
                    return None;
                }
                let AgentBackend::Acp { reference } = agent.backend else {
                    return None;
                };
                Some(reference)
            });
        let Some(reference) = first else {
            return submit_acp_prompt(&resources, content)
                .await
                .map(projection::run);
        };

        // The lifecycle worker owns first-input admission and its fallback label
        // even if the caller stops waiting; it never waits for the remote run.
        let events = events.clone();
        self.run_thread_lifecycle_operation(async move {
            let title_prompt = content
                .iter()
                .filter_map(|block| match block {
                    ContentBlock::Text(text) => Some(text.text.as_str()),
                    _ => None,
                })
                .collect::<Vec<_>>()
                .join("\n");
            let result = submit_acp_prompt(&resources, content).await;
            if result.is_ok()
                && let Some(_gate) = resources.title_update_admission().await
            {
                events
                    .record_acp_first_input_title(
                        &target.thread_id,
                        &reference,
                        provisional_title(&title_prompt),
                    )
                    .await;
            }
            Ok(result.map(projection::run))
        })
        .await
        .map_err(|error| {
            if self.shutdown_committed() {
                projection::failure(sdk::Error::Closed)
            } else {
                projection::preparation(&error.to_string())
            }
        })?
    }

    pub async fn replace_acp_session(
        &self,
        target: AcpSessionTarget,
        run: AcpRunId,
        mut content: Vec<ContentBlock>,
    ) -> Result<AcpRunId, AcpBusinessFailure> {
        let resources = self.business_resources(&target)?;
        resources
            .ensure_input_ready()
            .map_err(projection::failure)?;
        if let Some(wp) = resources.workflow_plan.get()
            && let Some(host_state) = wp
                .reconcile_run_for_turn()
                .await
                .map_err(|error| projection::preparation(&error.to_string()))?
        {
            content.insert(
                0,
                ContentBlock::Text(sdk::schema::TextContent::new(host_state).annotations(
                    sdk::schema::Annotations::new().audience(vec![sdk::schema::Role::Assistant]),
                )),
            );
        }
        resources
            .session()
            .map_err(|_| projection::failure(sdk::Error::NotReady))?
            .replace(
                sdk::RunId {
                    instance: run.instance,
                    sequence: run.sequence,
                },
                content,
            )
            .await
            .map(projection::run)
            .map_err(projection::failure)
    }
    pub async fn interrupt_acp_session(
        &self,
        target: AcpSessionTarget,
        run: AcpRunId,
    ) -> Result<(), AcpBusinessFailure> {
        let resources = self.business_resources(&target)?;
        resources
            .session()
            .map_err(|_| projection::failure(sdk::Error::NotReady))?
            .interrupt(sdk::RunId {
                instance: run.instance,
                sequence: run.sequence,
            })
            .await
            .map_err(projection::failure)
    }
    pub async fn configure_acp_session(
        &self,
        target: AcpSessionTarget,
        id: SessionConfigId,
        value: SessionConfigOptionValue,
    ) -> Result<(), AcpBusinessFailure> {
        let resources = self.business_resources(&target)?;
        resources
            .ensure_input_ready()
            .map_err(projection::failure)?;
        resources
            .session()
            .map_err(|_| projection::failure(sdk::Error::NotReady))?
            .set_config(id, value)
            .await
            .map_err(projection::failure)
    }
    pub async fn set_acp_session_mode(
        &self,
        target: AcpSessionTarget,
        mode: SessionModeId,
    ) -> Result<(), AcpBusinessFailure> {
        let resources = self.business_resources(&target)?;
        resources
            .ensure_input_ready()
            .map_err(projection::failure)?;
        resources
            .session()
            .map_err(|_| projection::failure(sdk::Error::NotReady))?
            .set_mode(mode)
            .await
            .map_err(projection::failure)
    }
    pub async fn set_acp_thread_mode(
        &self,
        target: AcpSessionTarget,
        mode_id: crate::mode::ThreadModeId,
    ) -> Result<AcpWorkflowStateSnapshot, AcpBusinessFailure> {
        let resources = self.business_resources(&target)?;
        resources
            .ensure_input_ready()
            .map_err(projection::failure)?;
        let snapshot = resources
            .session()
            .map_err(|_| projection::failure(sdk::Error::NotReady))?
            .snapshot()
            .await
            .map_err(projection::failure)?;
        if snapshot.closing || !snapshot.ready || snapshot.active_run.is_some() {
            return Err(projection::failure(sdk::Error::Busy));
        }
        let wp = resources
            .workflow_plan
            .get()
            .ok_or_else(|| projection::preparation("ACP workflow owner is unavailable"))?;
        let normalized = mode_id.legacy_builtin_replacement().unwrap_or(mode_id);
        let catalog = self.thread_modes.snapshot();
        let registered = catalog
            .mode(&normalized)
            .ok_or_else(|| projection::failure(sdk::Error::InvalidOption))?;
        wp.set_mode(normalized, &registered)
            .await
            .map_err(|error| projection::preparation(&error.to_string()))
    }
    pub async fn answer_acp_permission(
        &self,
        target: AcpSessionTarget,
        id: AcpPermissionId,
        option: Option<PermissionOptionId>,
    ) -> Result<(), AcpBusinessFailure> {
        let resources = self.business_resources(&target)?;
        resources
            .session()
            .map_err(|_| projection::failure(sdk::Error::NotReady))?
            .answer_permission(
                sdk::PermissionId {
                    instance: id.instance,
                    sequence: id.sequence,
                },
                option,
            )
            .await
            .map_err(projection::failure)
    }
    pub async fn list_acp_sessions(
        &self,
        target: AcpSessionTarget,
        request: ListSessionsRequest,
    ) -> Result<ListSessionsResponse, AcpBusinessFailure> {
        let resources = self.business_resources(&target)?;
        let events = &self.agent_facility.product_events;
        let source = events
            .directory_facts(&target.thread_id)
            .and_then(|(_, agent)| {
                let AgentBackend::Acp { reference } = agent.backend else {
                    return None;
                };
                request
                    .cwd
                    .as_deref()
                    .is_none_or(|cwd| cwd.to_str() == Some(reference.cwd.as_str()))
                    .then_some(reference)
            });
        let response = resources
            .session()
            .map_err(|_| projection::failure(sdk::Error::NotReady))?
            .list(request)
            .await
            .map_err(projection::failure)?;
        if let Some(source) = source
            && let Some(_gate) = resources.title_update_admission().await
        {
            events
                .record_acp_list_titles(&target.thread_id, &source, &response.sessions)
                .await;
        }
        Ok(response)
    }
    pub async fn acp_session_snapshot(
        &self,
        target: AcpSessionTarget,
    ) -> Result<AcpBusinessSnapshot, AcpBusinessFailure> {
        let resources = self.business_resources(&target)?;
        let workflow_state = resources.workflow_snapshot();
        resources
            .session()
            .map_err(|_| projection::failure(sdk::Error::NotReady))?
            .snapshot()
            .await
            .map(|snapshot| projection::snapshot(target, snapshot, workflow_state))
            .map_err(projection::failure)
    }
    pub(in crate::studio::runtime) async fn acp_prompt_capabilities_for_thread(
        &self,
        thread_id: &str,
    ) -> Result<sdk::schema::PromptCapabilities> {
        let (session, agent) = self
            .agent_facility
            .product_events
            .directory_facts(thread_id)
            .context("ACP product member is missing")?;
        ensure!(
            !session.archived
                && !agent.explicitly_closed
                && (agent.parent_agent_id.is_some() || session.root_agent_id == agent.agent_id)
                && matches!(&agent.backend, AgentBackend::Acp { .. }),
            "ACP product membership is not executable"
        );
        let id = crate::SessionId::new(session.session_id.clone())?;
        let owner = self
            .sessions
            .get(&id)
            .context("ACP session is not resident")?;
        let acp = owner
            .resident_acp(thread_id)?
            .context("ACP member is not resident")?;
        let target = target(&session, &agent, &acp);
        let resources = self.business_resources(&target)?;
        let snapshot = resources.session()?.snapshot().await?;
        ensure!(
            snapshot.ready && !snapshot.closing,
            "ACP session is not ready for prompt"
        );
        Ok(snapshot.capabilities.prompt_capabilities)
    }
    pub async fn close_acp_session(&self, target: AcpSessionTarget) -> Result<AcpBusinessClose> {
        let id = crate::SessionId::new(target.session_id)?;
        let owner = self
            .sessions
            .get(&id)
            .context("ACP Session owner is missing")?;
        ensure!(
            owner
                .acp_identity(&target.thread_id)
                .is_some_and(|identity| {
                    identity.agent_id.as_str() == target.agent_id && identity.session_id == id
                }),
            "ACP product identity is stale"
        );
        let resources = owner
            .resident_acp(&target.thread_id)?
            .context("ACP member is missing")?;
        ensure!(
            resources.instance == target.instance,
            "ACP runtime generation is stale"
        );
        let is_root = owner
            .acp_identity(&target.thread_id)
            .is_some_and(|identity| identity.parent_agent_id.is_none());
        let report = if is_root {
            owner.close_session().await
        } else {
            Arc::new(
                owner
                    .close(&target.thread_id)
                    .await
                    .err()
                    .map(|error| vec![(target.thread_id.clone(), Arc::new(error))])
                    .unwrap_or_default(),
            )
        };
        if let Some(lease) = self.agent_facility.worktrees.get(&target.thread_id)
            && lease.state
                == crate::studio::agent_host::worktree_lease::WorktreeLeaseState::Preserved
        {
            self.publish_worktree_recovery(Some("unused ACP draft worktree retained"), &lease)
                .await;
        }
        let mut result = projection::close(resources.outcome().await);
        result.owner_failures = report
            .iter()
            .map(|(thread_id, error)| AcpMemberCloseFailure {
                thread_id: thread_id.clone(),
                message: error.to_string(),
            })
            .collect();
        Ok(result)
    }
}

async fn submit_acp_prompt(
    resources: &AcpResources,
    mut content: Vec<ContentBlock>,
) -> Result<sdk::RunId, AcpBusinessFailure> {
    resources
        .ensure_input_ready()
        .map_err(projection::failure)?;
    if !resources.association_published().await {
        return Err(projection::failure(sdk::Error::NotReady));
    }
    if let Some(wp) = resources.workflow_plan.get()
        && let Some(host_state) = wp
            .reconcile_run_for_turn()
            .await
            .map_err(|error| projection::preparation(&error.to_string()))?
    {
        content.insert(
            0,
            ContentBlock::Text(sdk::schema::TextContent::new(host_state).annotations(
                sdk::schema::Annotations::new().audience(vec![sdk::schema::Role::Assistant]),
            )),
        );
    }
    resources
        .session()
        .map_err(|_| projection::failure(sdk::Error::NotReady))?
        .submit(content)
        .await
        .map_err(projection::failure)
}

fn target(
    session: &SessionDirectoryRecord,
    agent: &AgentDirectoryRecord,
    resource: &AcpResources,
) -> AcpSessionTarget {
    AcpSessionTarget {
        session_id: session.session_id.clone(),
        agent_id: agent.agent_id.clone(),
        thread_id: agent.thread_id.clone(),
        instance: resource.instance,
    }
}

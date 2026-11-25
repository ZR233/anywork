//! Reserve, prepare, and publish the original ACP session member.

use std::sync::Arc;

use anyhow::{Context, Result, ensure};
use futures::FutureExt;
use pl_acp::session as sdk;
use tokio_util::sync::CancellationToken;

use super::{
    AcpBusinessOwner, AcpResources, AcpSessionCompletion, AcpSessionObservation, AcpSessionOpen,
    AgentDirectoryRecord, SessionDirectoryRecord, projection,
};
use crate::studio::runtime::acp_accounts::{AccountConnection, PreparedConnection};
use crate::studio::{StudioThreadFactory, WorkspaceRecord, WorkspaceUsageLease};
use crate::{
    AcpBusinessFailure, AcpBusinessFailureKind, AcpOpenIntent, AcpSessionReference,
    AcpSessionTarget, AgentBackend,
};

pub(super) struct MemberOpen {
    pub(super) owner: crate::thread_assembler::SessionRuntime,
    pub(super) identity: crate::AgentThreadIdentity,
    pub(super) project: crate::studio::WorkspaceRecord,
    pub(super) definition: crate::config::AcpServiceDefinition,
    pub(super) session_record: SessionDirectoryRecord,
    pub(super) previous: Option<AgentDirectoryRecord>,
    pub(super) intent: AcpOpenIntent,
    pub(super) cwd: Option<String>,
    pub(super) business_root: String,
    pub(super) role: String,
    pub(super) title: Option<String>,
    pub(super) usage: Option<crate::studio::WorkspaceUsageLease>,
    pub(super) cancellation: Option<tokio_util::sync::CancellationToken>,
}

pub(super) struct PendingOpen {
    target: AcpSessionTarget,
    resources: std::sync::Arc<AcpResources>,
    opening: tokio::sync::oneshot::Receiver<Result<sdk::Observer, AcpBusinessFailure>>,
}

struct MemberProtocol<'a> {
    owner: &'a crate::thread_assembler::SessionRuntime,
    identity: &'a crate::AgentThreadIdentity,
    resources: &'a Arc<AcpResources>,
    delegation: crate::DelegationSettings,
    cwd: &'a str,
    intent: AcpOpenIntent,
    requested_mode: Option<crate::mode::ThreadModeId>,
    expected_server_version: Option<String>,
    on_text_performance: sdk::OnTextPerformance,
}

impl PendingOpen {
    pub(super) async fn observe(self) -> Result<AcpSessionOpen> {
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

    pub(super) fn begin_open(&self, request: MemberOpen) -> Result<PendingOpen> {
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
        let business = self.clone();
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
            let events = &business.events;
            let mut started = Some(started);
            let operation = {
                let operation = std::panic::AssertUnwindSafe(async {
                    let account = business
                        .connections
                        .acquire_for_business(&definition)
                        .map_err(|_| {
                            projection::preparation("ACP account connection is closing or stale")
                        })?;
                    let workspace_cancel = resources.cancellation.child_token();
                    let ready_cancel = resources.cancellation.child_token();
                    let workspace_task = MemberWorkspace {
                        project: &project,
                        thread_id: &thread_id,
                        session: &mut session_record,
                        business_root: &mut business_root,
                        cwd: cwd.as_deref(),
                        usage,
                        config: &business.config,
                    }
                    .prepare(
                        &business.factory,
                        &resources,
                        &preparation,
                        draft,
                        &workspace_cancel,
                    );
                    let (usage, cwd, prepared) = prepare_business_connection(
                        &account,
                        workspace_task,
                        &workspace_cancel,
                        &ready_cancel,
                    )
                    .await?;
                    let observer = business
                        .observe_member(MemberProtocol {
                            owner: &owner,
                            identity: &identity,
                            resources: &resources,
                            delegation: crate::DelegationSettings {
                                mode: session_record.delegation_mode,
                                preference: session_record.delegation_preference,
                            },
                            cwd: &cwd,
                            intent,
                            requested_mode,
                            expected_server_version: prepared.expected_version,
                            on_text_performance: Arc::new(move |run, evidence, model, effort| {
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
                            }),
                        })
                        .await?;
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
                        .settle_association(events)
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

    async fn observe_member(
        &self,
        member: MemberProtocol<'_>,
    ) -> Result<sdk::Observer, AcpBusinessFailure> {
        let MemberProtocol {
            owner,
            identity,
            resources,
            delegation,
            cwd,
            intent,
            requested_mode,
            expected_server_version,
            on_text_performance,
        } = member;
        let res_dir = self
            .store
            .session_resources_dir_for(&resources.workspace_id, identity.thread_id.as_str())
            .map_err(|error| projection::preparation(&error.to_string()))?;
        let wp_owner = super::super::AcpWorkflowPlanOwner::load_or_init(
            identity.thread_id.to_string(),
            identity.parent_agent_id.is_none(),
            res_dir,
            self.thread_modes.clone(),
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
        resources
            .observe(sdk::OpenRequest {
                cwd: cwd.to_owned(),
                intent,
                prepare: Some(
                    crate::studio::runtime::acp_host_mcp::prepare_open(
                        owner,
                        identity,
                        resources,
                        &self.config,
                        cwd,
                        delegation,
                    )
                    .await
                    .map_err(|error| projection::preparation(&error.to_string()))?,
                ),
                expected_server_version,
                on_text_performance: Some(on_text_performance),
                cleanup: pl_acp::auth::CleanupBudget::new(std::time::Duration::from_secs(5)),
            })
            .await
            .map_err(|_| projection::preparation("ACP observation could not be installed"))
    }
}

struct MemberWorkspace<'a> {
    project: &'a WorkspaceRecord,
    thread_id: &'a str,
    session: &'a mut SessionDirectoryRecord,
    business_root: &'a mut String,
    cwd: Option<&'a str>,
    usage: Option<WorkspaceUsageLease>,
    config: &'a crate::config::ConfigRuntime,
}

impl MemberWorkspace<'_> {
    async fn prepare(
        self,
        factory: &StudioThreadFactory,
        resources: &AcpResources,
        preparation: &impl crate::thread_assembler::WorkspaceBindingAdmission,
        draft: bool,
        cancellation: &CancellationToken,
    ) -> Result<(WorkspaceUsageLease, String), AcpBusinessFailure> {
        let draft_worktree =
            if draft && self.session.workspace_mode == crate::ThreadWorkspaceMode::Worktree {
                resources
                    .retain_draft_worktree(factory.clone(), self.thread_id.to_owned())
                    .await;
                let lease = factory
                    .prepare_acp_root_worktree(self.thread_id, self.project)
                    .await
                    .map_err(|error| projection::preparation(&error.to_string()))?;
                *self.business_root = lease.path.clone();
                self.session.workspace_path = self.business_root.clone();
                Some(lease)
            } else {
                None
            };
        let usage = match self.usage {
            Some(usage) => usage,
            None => factory
                .reserve_workspace_use(self.thread_id, self.project)
                .await
                .map_err(|_| projection::preparation("ACP workspace admission failed"))?,
        };
        let cwd = factory
            .prepare_acp_protocol_cwd(self.thread_id, self.project, self.business_root, self.cwd)
            .await
            .map_err(|error| projection::preparation(&error.to_string()))?;
        {
            let workspace_config = self
                .config
                .read()
                .map_err(|error| projection::preparation(&error.to_string()))?
                .config;
            let binding = factory
                .prepare_acp_workspace(crate::studio::thread_factory::AcpWorkspaceRequest {
                    id: self.thread_id,
                    project: self.project,
                    business_root: self.business_root,
                    usage: &usage,
                    session_mode: self.session.workspace_mode,
                    config: &workspace_config,
                    cancellation: cancellation,
                })
                .await
                .map_err(|error| projection::preparation(&error.to_string()))?;
            let tools = crate::studio::runtime::acp_workspace_tools::WorkspaceTools::new(
                self.thread_id.to_owned(),
                binding,
                &workspace_config,
            );
            resources
                .retain_workspace_tools(tools, usage.clone())
                .await
                .map_err(|error| projection::preparation(&error.to_string()))?;
        }
        if cancellation.is_cancelled() {
            return Err(projection::preparation("ACP preparation cancelled"));
        }
        if let Some(lease) = &draft_worktree {
            factory
                .confirm_acp_worktree(lease, &usage, preparation)
                .await
                .map_err(|error| projection::preparation(&error.to_string()))?;
        }
        Ok::<_, AcpBusinessFailure>((usage, cwd))
    }
}

async fn prepare_business_connection(
    account: &AccountConnection,
    workspace: impl Future<Output = Result<(WorkspaceUsageLease, String), AcpBusinessFailure>>,
    workspace_cancel: &CancellationToken,
    ready_cancel: &CancellationToken,
) -> Result<(WorkspaceUsageLease, String, PreparedConnection), AcpBusinessFailure> {
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
            let result = workspace.await;
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
    match (workspace_result, prepared_result) {
        (Ok((usage, cwd)), Ok(prepared)) => Ok((usage, cwd, prepared)),
        (Ok(_), Err(error)) | (Err(error), Ok(_)) => Err(error),
        (Err(workspace_error), Err(prepared_error)) => {
            if !ready_cancel.is_cancelled() {
                Err(prepared_error)
            } else {
                Err(workspace_error)
            }
        }
    }
}

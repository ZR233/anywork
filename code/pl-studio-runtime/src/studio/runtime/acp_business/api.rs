use std::sync::Arc;

use anyhow::{Context, Result, ensure};
use futures::FutureExt;
use pl_acp::session as sdk;
use pl_protocol::session::{AcpSessionReference, AgentBackend};
use pl_protocol::studio::*;

use super::{AcpResources, AcpSessionCompletion, AcpSessionObservation, projection};
use crate::studio::records::{AgentDirectoryRecord, SessionDirectoryRecord};
use crate::studio::runtime::{StudioRuntime, acp_launch, acp_worker::AcpSpawnRequest};

/// An accepted product member and its original SDK observation. A resident
/// member returns the same target and no second observation/connection.
pub struct AcpSessionOpen {
    pub target: AcpSessionTarget,
    pub observation: Option<AcpSessionObservation>,
    pub completion: AcpSessionCompletion,
}

/// Immutable leases of existing service owners; never holds a StudioRuntime or SessionTable.
#[derive(Clone)]
pub(crate) struct AcpBusinessOwner {
    factory: crate::studio::StudioThreadFactory,
    config: crate::config::ConfigRuntime,
    store: crate::studio::StudioStore,
    events: crate::studio::ProductEventBus,
    workers: std::sync::Arc<super::super::acp_worker::WorkerSource>,
    mcp_source: crate::host_mcp_assets::HostMcpSource,
}

struct MemberOpen {
    owner: crate::thread_assembler::SessionRuntime,
    identity: pl_protocol::AgentThreadIdentity,
    project: crate::studio::WorkspaceRecord,
    definition: crate::config::AcpServiceDefinition,
    session_record: SessionDirectoryRecord,
    previous: Option<AgentDirectoryRecord>,
    intent: AcpOpenIntent,
    cwd: String,
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
        Ok(AcpSessionOpen {
            target: self.target,
            observation: Some(AcpSessionObservation::new(
                observer,
                self.resources.completion.clone(),
            )),
            completion: self.resources.completion.clone(),
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
        let usage = self.factory.reserve_workspace_use(target, &project).await?;
        self.factory
            .verify_acp_workspace(target, &project, &cwd)
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
            intent: AcpOpenIntent::Load(reference.acp_session_id.clone()),
            cwd,
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
        profile: &pl_protocol::AgentProfile,
        definition: crate::config::AcpServiceDefinition,
    ) -> Result<(
        Arc<AcpResources>,
        pl_protocol::AgentWorkspaceAssignmentSnapshot,
    )> {
        ensure!(
            profile.workspace_mode != pl_protocol::AgentWorkspaceMode::Review
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
        ensure!(
            prepared.project.ssh_alias.is_none(),
            "ACP child requires a local workspace"
        );
        let pending = self.begin_open(MemberOpen {
            owner: owner.clone(),
            identity: prepared.child_identity,
            project: prepared.project,
            definition,
            session_record: prepared.parent.session,
            previous: None,
            intent: AcpOpenIntent::New,
            cwd: prepared.assignment.root.clone(),
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
        workers: std::sync::Arc<super::super::acp_worker::WorkerSource>,
        mcp_source: crate::host_mcp_assets::HostMcpSource,
    ) -> Self {
        Self {
            factory,
            config,
            store,
            events,
            workers,
            mcp_source,
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
        let resources = AcpResources::new(project.id.clone(), completion.clone());
        let preparation =
            owner.prepare_acp(identity.clone(), definition.id.clone(), resources.clone())?;
        let accepted = AcpSessionTarget {
            session_id: session_record.session_id.clone(),
            agent_id: agent_id.clone(),
            thread_id: thread_id.clone(),
            instance: resources.instance,
        };
        let factory = self.factory.clone();
        let store = self.store.clone();
        let events = self.events.clone();
        let workers = self.workers.clone();
        let config = self.config.clone();
        let mcp_source = self.mcp_source.clone();
        let resources_for_result = resources.clone();
        let baseline = previous
            .as_ref()
            .map(|agent| (session_record.clone(), agent.clone()));
        let (started, opening) = tokio::sync::oneshot::channel();
        tokio::spawn(async move {
            let mut started = Some(started);
            let operation = {
                let operation = std::panic::AssertUnwindSafe(async {
                    let cwd_path = std::path::PathBuf::from(&cwd);
                    let launch = acp_launch::resolve_launch(
                        &store,
                        &definition,
                        &cwd_path,
                        &resources.cancellation,
                    )
                    .await
                    .map_err(projection::launch_failure)?;
                    let usage = match usage {
                        Some(usage) => usage,
                        None => factory
                            .reserve_workspace_use(&thread_id, &project)
                            .await
                            .map_err(|_| {
                                projection::preparation("ACP workspace admission failed")
                            })?,
                    };
                    factory
                        .assign_workspace_use(&usage, &project, &cwd_path)
                        .await
                        .map_err(|_| {
                            projection::preparation("ACP workspace identity is unavailable")
                        })?;
                    let intent = match intent {
                        AcpOpenIntent::New => sdk::Open::New,
                        AcpOpenIntent::Load(id) => sdk::Open::Load(id.into()),
                        AcpOpenIntent::Resume(id) => sdk::Open::Resume(id.into()),
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
                                    pl_protocol::DelegationSettings {
                                        mode: session_record.delegation_mode,
                                        preference: session_record.delegation_preference,
                                    },
                                    mcp_source,
                                )
                                .map_err(|error| projection::preparation(&error.to_string()))?,
                            ),
                            expected_server_version: launch.expected_server_version,
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
                        .start(
                            AcpSpawnRequest {
                                program: launch.program,
                                args: launch.args,
                                cwd: cwd_path,
                                env: launch.env,
                            },
                            &workers,
                            usage,
                        )
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
                    let backend = AgentBackend::Acp {
                        reference: AcpSessionReference {
                            account_id: definition.id,
                            acp_session_id: remote_id.to_string(),
                            cwd: cwd.clone(),
                        },
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
        if project.ssh_alias.is_some() {
            return Err(projection::failure(sdk::Error::Unsupported).into());
        }
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
                .materialize(&pl_protocol::SessionId::new(session.session_id.clone())?)?;
            // The existing per-member admission permit serializes cold preparation
            // registration, not protocol open or product publication.
            _admission = Some(owner.agent_operation(&agent.thread_id).await);
            if let Some(acp) = owner.resident_acp(&agent.thread_id)? {
                return Ok(AcpSessionOpen {
                    target: target(&session, &agent, &acp),
                    observation: acp.take_observation().await.map(|observer| {
                        AcpSessionObservation::new(observer, acp.completion.clone())
                    }),
                    completion: acp.completion.clone(),
                });
            }
            let id = match &request.intent {
                AcpOpenIntent::Load(id) | AcpOpenIntent::Resume(id) => id,
                AcpOpenIntent::New => {
                    anyhow::bail!("existing ACP association requires Load or Resume")
                }
            };
            ensure!(
                id == &reference.acp_session_id
                    && (agent.parent_agent_id.is_some() || reference.cwd == session.workspace_path),
                "ACP remote session reference differs"
            );
            if agent.parent_agent_id.is_some() {
                self.thread_factory
                    .verify_acp_workspace(&agent.thread_id, &project, &reference.cwd)
                    .await?;
            }
            let agent_id = agent.agent_id.clone();
            let thread_id = agent.thread_id.clone();
            (session, Some(agent), agent_id, thread_id)
        } else {
            let session_id = crate::studio::ids::new_id("session");
            let agent_id = crate::studio::ids::new_id("agent");
            let thread_id = crate::studio::ids::new_id("acp");
            let delegation = self.config_runtime.read()?.config.delegation;
            (
                SessionDirectoryRecord {
                    session_id: session_id.clone(),
                    root_agent_id: agent_id.clone(),
                    workspace_id: request.workspace_id.clone(),
                    title: request.account_id.clone(),
                    native_mode: None,
                    workspace_mode: pl_protocol::ThreadWorkspaceMode::Local,
                    delegation_mode: delegation.mode,
                    delegation_preference: delegation.preference,
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
            session_record.title = definition.display_name.clone();
        }
        self.store
            .ensure_archive_execution_allowed(&project.id, Some(&thread_id))
            .await?;
        self.store
            .ensure_agent_execution_allowed(&thread_id)
            .await?;
        let identity = pl_protocol::AgentThreadIdentity {
            session_id: pl_protocol::SessionId::new(session_record.session_id.clone())?,
            agent_id: pl_protocol::AgentId::new(agent_id.clone())?,
            parent_agent_id: previous
                .as_ref()
                .and_then(|agent| agent.parent_agent_id.as_ref())
                .map(|id| pl_protocol::AgentId::new(id.clone()))
                .transpose()?,
            thread_id: pl_protocol::ThreadId::new(thread_id.clone())?,
        };
        let owner = self.sessions.materialize(&identity.session_id)?;
        let business = AcpBusinessOwner::new(
            self.thread_factory.clone(),
            self.config_runtime.clone(),
            self.store.clone(),
            self.agent_facility.product_events.clone(),
            self.acp_workers.clone(),
            self.host_mcp_source.clone(),
        );
        let cwd = match &previous {
            Some(agent) => match &agent.backend {
                AgentBackend::Acp { reference } => reference.cwd.clone(),
                _ => unreachable!("ACP association checked"),
            },
            None => session_record.workspace_path.clone(),
        };
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
        let id = pl_protocol::SessionId::new(target.session_id.clone())
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

    pub async fn prompt_acp_session(
        &self,
        target: AcpSessionTarget,
        content: Vec<ContentBlock>,
    ) -> Result<AcpRunId, AcpBusinessFailure> {
        let resources = self.business_resources(&target)?;
        resources
            .session()
            .map_err(|_| projection::failure(sdk::Error::NotReady))?
            .submit(content)
            .await
            .map(projection::run)
            .map_err(projection::failure)
    }
    pub async fn replace_acp_session(
        &self,
        target: AcpSessionTarget,
        run: AcpRunId,
        content: Vec<ContentBlock>,
    ) -> Result<AcpRunId, AcpBusinessFailure> {
        let resources = self.business_resources(&target)?;
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
            .session()
            .map_err(|_| projection::failure(sdk::Error::NotReady))?
            .set_mode(mode)
            .await
            .map_err(projection::failure)
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
        resources
            .session()
            .map_err(|_| projection::failure(sdk::Error::NotReady))?
            .list(request)
            .await
            .map_err(projection::failure)
    }
    pub async fn acp_session_snapshot(
        &self,
        target: AcpSessionTarget,
    ) -> Result<AcpBusinessSnapshot, AcpBusinessFailure> {
        let resources = self.business_resources(&target)?;
        resources
            .session()
            .map_err(|_| projection::failure(sdk::Error::NotReady))?
            .snapshot()
            .await
            .map(|snapshot| projection::snapshot(target, snapshot))
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
        let id = pl_protocol::SessionId::new(session.session_id.clone())?;
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
        let id = pl_protocol::SessionId::new(target.session_id)?;
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

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
        let (mut session_record, previous, agent_id, thread_id) =
            if let Some((session, agent)) = existing {
                ensure!(
                    session.workspace_id == request.workspace_id
                        && !session.archived
                        && !agent.explicitly_closed
                        && agent.is_root_agent()
                        && session.root_agent_id == agent.agent_id,
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
                        observation: None,
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
                    id == &reference.acp_session_id && reference.cwd == session.workspace_path,
                    "ACP remote session reference differs"
                );
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
        self.store.ensure_agent_execution_allowed(&agent_id).await?;
        let identity = pl_protocol::AgentThreadIdentity {
            session_id: pl_protocol::SessionId::new(session_record.session_id.clone())?,
            agent_id: pl_protocol::AgentId::new(agent_id.clone())?,
            parent_agent_id: None,
            thread_id: pl_protocol::ThreadId::new(thread_id.clone())?,
        };
        let owner = self.sessions.materialize(&identity.session_id)?;
        let (publication, published) = tokio::sync::watch::channel(None);
        let completion = AcpSessionCompletion {
            publication: published,
        };
        let resources = AcpResources::new(project.id.clone(), completion.clone());
        let preparation = owner.prepare_acp(identity, request.account_id, resources.clone())?;
        drop(_admission);
        // Project archive can now capture this real branch from the original Session table.
        // Never retain the lifecycle lock while awaiting a protocol open or its observation.
        drop(lifecycle);
        let accepted = AcpSessionTarget {
            session_id: session_record.session_id.clone(),
            agent_id: agent_id.clone(),
            thread_id: thread_id.clone(),
            instance: resources.instance,
        };
        let factory = self.thread_factory.clone();
        let store = self.store.clone();
        let events = self.agent_facility.product_events.clone();
        let workers = self.acp_workers.clone();
        let baseline = previous
            .as_ref()
            .map(|agent| (session_record.clone(), agent.clone()));
        let (started, opening) = tokio::sync::oneshot::channel();
        tokio::spawn(async move {
            let mut started = Some(started);
            let operation = std::panic::AssertUnwindSafe(async {
                let cwd = std::path::PathBuf::from(&session_record.workspace_path);
                let launch =
                    acp_launch::resolve_launch(&store, &definition, &cwd, &resources.cancellation)
                        .await
                        .map_err(projection::launch_failure)?;
                let usage = factory
                    .reserve_workspace_use(&thread_id, &project)
                    .await
                    .map_err(|_| projection::preparation("ACP workspace admission failed"))?;
                factory
                    .assign_workspace_use(&usage, &project, &cwd)
                    .await
                    .map_err(|_| {
                        projection::preparation("ACP workspace identity is unavailable")
                    })?;
                let intent = match request.intent {
                    AcpOpenIntent::New => sdk::Open::New,
                    AcpOpenIntent::Load(id) => sdk::Open::Load(id.into()),
                    AcpOpenIntent::Resume(id) => sdk::Open::Resume(id.into()),
                };
                let observer = resources
                    .observe(sdk::OpenRequest {
                        cwd: session_record.workspace_path.clone(),
                        intent,
                        expected_server_version: launch.expected_server_version,
                        cleanup: pl_acp::auth::CleanupBudget::new(std::time::Duration::from_secs(
                            5,
                        )),
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
                            cwd,
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
                        cwd: session_record.workspace_path.clone(),
                    },
                };
                let mut agent = previous.unwrap_or_else(|| AgentDirectoryRecord {
                    agent_id,
                    thread_id,
                    session_id: session_record.session_id.clone(),
                    parent_agent_id: None,
                    role: crate::config::ROOT_AGENT_ROUTE_KEY.into(),
                    title: None,
                    backend: backend.clone(),
                    explicitly_closed: false,
                    created_at: now,
                    updated_at: now,
                });
                agent.backend = backend;
                agent.updated_at = crate::studio::ids::unix_seconds();
                session_record.updated_at = agent.updated_at;
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
                Ok::<_, AcpBusinessFailure>(())
            })
            .catch_unwind()
            .await;
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
        let observer = opening
            .await
            .context("ACP preparation stopped before observation")??;
        Ok(AcpSessionOpen {
            target: accepted,
            observation: Some(AcpSessionObservation::new(observer, completion.clone())),
            completion,
        })
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
        let report = owner.close_session().await;
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

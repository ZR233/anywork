use std::sync::Arc;

use crate::acp_schema::ContentBlock;
use crate::protocol::*;
use crate::{AcpSessionReference, AgentBackend};
use anyhow::{Context, Result, ensure};
use pl_acp::session as sdk;

mod open;

use open::MemberOpen;

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

impl StudioRuntime {
    pub async fn open_acp_session(&self, request: OpenAcpSessionRequest) -> Result<AcpSessionOpen> {
        let lifecycle = self.thread_lifecycle_admission().await?;
        let project = self
            .store
            .read_project(&request.workspace_id)
            .await?
            .context("ACP workspace is missing")?;
        self.ensure_project_thread_admission_open(&project.id)?;
        let mut member_admission = None;
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
                let reference = validate_existing_member(&request, &session, &agent)?;
                let owner = self
                    .sessions
                    .materialize(&crate::SessionId::new(session.session_id.clone())?)?;
                // The existing per-member admission permit serializes cold preparation
                // registration, not protocol open or product publication.
                member_admission = Some(owner.agent_operation(&agent.thread_id).await);
                if let Some(acp) = owner.resident_acp(&agent.thread_id)? {
                    return Ok(observe_resident(&session, &agent, &acp).await);
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
                let (session, agent_id, thread_id) = self.new_acp_root(&request, &project)?;
                (session, None, agent_id, thread_id)
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
        drop(member_admission);
        drop(lifecycle);
        pending.observe().await
    }

    fn new_acp_root(
        &self,
        request: &OpenAcpSessionRequest,
        project: &crate::studio::WorkspaceRecord,
    ) -> Result<(SessionDirectoryRecord, String, String)> {
        let now = crate::studio::ids::unix_seconds();
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
        Ok((
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
            agent_id,
            thread_id,
        ))
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
        inject_workflow_prompt(&resources, &mut content).await?;
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
            && lease.state == crate::studio::worktree::worktree_lease::WorktreeLeaseState::Preserved
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

fn validate_existing_member<'a>(
    request: &OpenAcpSessionRequest,
    session: &SessionDirectoryRecord,
    agent: &'a AgentDirectoryRecord,
) -> Result<&'a AcpSessionReference> {
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
    Ok(reference)
}

async fn observe_resident(
    session: &SessionDirectoryRecord,
    agent: &AgentDirectoryRecord,
    acp: &AcpResources,
) -> AcpSessionOpen {
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
    AcpSessionOpen {
        target: target(session, agent, acp),
        observation: acp.take_observation().await.map(|observer| {
            AcpSessionObservation::new(observer, acp.completion.clone(), workflow_updates)
        }),
        completion: acp.completion.clone(),
        info_snapshot,
        workflow_state,
    }
}

async fn inject_workflow_prompt(
    resources: &AcpResources,
    content: &mut Vec<ContentBlock>,
) -> Result<(), AcpBusinessFailure> {
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
    Ok(())
}

async fn submit_acp_prompt(
    resources: &AcpResources,
    mut content: Vec<ContentBlock>,
) -> Result<sdk::RunId, AcpBusinessFailure> {
    inject_workflow_prompt(resources, &mut content).await?;
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

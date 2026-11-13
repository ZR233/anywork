//! ACP materialization uses the original membership reservation and close owner.
use std::sync::Arc;

use crate::session::{AgentInstance, AgentRuntime, PreparedResources};
use crate::studio::runtime::acp_business::AcpResources;

use super::{Reservation, SessionRuntime, ThreadAssemblyError};

pub(crate) struct AcpPreparation {
    owner: SessionRuntime,
    _reservation: Reservation,
    identity: pl_protocol::AgentThreadIdentity,
    binding: pl_protocol::AgentBinding,
    pub(crate) resources: Arc<AcpResources>,
}

impl AcpPreparation {
    /// Publication returns product membership, never a fabricated Native handle.
    pub(crate) fn publish(&self) -> Result<pl_protocol::AgentThreadIdentity, ThreadAssemblyError> {
        let mut state = self.owner.0.state();
        let id = self.identity.thread_id.as_str();
        if state.closing
            || state.sealed_agents.contains_key(id)
            || self.resources.cancellation.is_cancelled()
        {
            return Err(ThreadAssemblyError::Closed);
        }
        let original = state
            .creating
            .get(id)
            .and_then(|preparation| match &preparation.resources {
                PreparedResources::Acp(acp) => Some(acp),
                PreparedResources::Native(_) => None,
            })
            .is_some_and(|current| Arc::ptr_eq(current, &self.resources));
        if !original {
            return Err(ThreadAssemblyError::Identity(id.into()));
        }
        state.insert_entry(
            id.into(),
            AgentInstance {
                identity: self.identity.clone(),
                binding: self.binding.clone(),
                runtime: AgentRuntime::Acp(self.resources.clone()),
            },
        );
        Ok(self.identity.clone())
    }
}

impl SessionRuntime {
    pub(crate) fn acp_roots_for_workspace(&self, workspace_id: &str) -> Vec<String> {
        let state = self.0.state();
        state
            .entries
            .values()
            .filter_map(|entry| match &entry.runtime {
                AgentRuntime::Acp(acp) if acp.workspace_id == workspace_id => {
                    Some(entry.identity.thread_id.to_string())
                }
                _ => None,
            })
            .chain(state.creating.iter().filter_map(
                |(id, preparation)| match &preparation.resources {
                    PreparedResources::Acp(acp) if acp.workspace_id == workspace_id => {
                        Some(id.clone())
                    }
                    _ => None,
                },
            ))
            .chain(state.failed_preparations.iter().filter_map(|(id, failed)| {
                match &failed.resources {
                    PreparedResources::Acp(acp) if acp.workspace_id == workspace_id => {
                        Some(id.clone())
                    }
                    _ => None,
                }
            }))
            .collect()
    }

    pub(crate) fn acp_identity(&self, thread_id: &str) -> Option<pl_protocol::AgentThreadIdentity> {
        let state = self.0.state();
        state
            .entries
            .get(thread_id)
            .map(|entry| entry.identity.clone())
            .or_else(|| {
                state
                    .creating
                    .get(thread_id)
                    .and_then(|preparation| preparation.identity.clone())
            })
            .or_else(|| {
                state
                    .failed_preparations
                    .get(thread_id)
                    .and_then(|failed| failed.identity.clone())
            })
    }
    pub(crate) fn resident_acp(
        &self,
        thread_id: &str,
    ) -> Result<Option<Arc<AcpResources>>, ThreadAssemblyError> {
        let state = self.0.state();
        if let Some(entry) = state.entries.get(thread_id) {
            return match &entry.runtime {
                AgentRuntime::Acp(acp) => Ok(Some(acp.clone())),
                AgentRuntime::Native(_) => Err(ThreadAssemblyError::UnsupportedBackend {
                    backend: pl_protocol::AgentBackendKind::Native,
                }),
            };
        }
        let resources = state
            .creating
            .get(thread_id)
            .map(|preparation| &preparation.resources)
            .or_else(|| {
                state
                    .failed_preparations
                    .get(thread_id)
                    .map(|failed| &failed.resources)
            });
        match resources {
            Some(PreparedResources::Acp(acp)) => Ok(Some(acp.clone())),
            Some(PreparedResources::Native(_)) => Err(ThreadAssemblyError::UnsupportedBackend {
                backend: pl_protocol::AgentBackendKind::Native,
            }),
            None => Ok(None),
        }
    }
    pub(crate) fn prepare_acp(
        &self,
        identity: pl_protocol::AgentThreadIdentity,
        account_id: String,
        resources: Arc<AcpResources>,
    ) -> Result<AcpPreparation, ThreadAssemblyError> {
        if &identity.session_id != self.id() {
            return Err(ThreadAssemblyError::Identity(
                identity.thread_id.to_string(),
            ));
        }
        let parent = if let Some(parent_agent) = &identity.parent_agent_id {
            let parent = {
                let state = self.0.state();
                state
                    .by_agent
                    .get(parent_agent)
                    .and_then(|thread| {
                        state
                            .entries
                            .get(thread)
                            .map(|entry| entry.identity.clone())
                    })
                    .or_else(|| {
                        state
                            .agent_services
                            .as_ref()?
                            .events
                            .member_identity(&identity.session_id, parent_agent)
                    })
                    .ok_or_else(|| ThreadAssemblyError::Identity(identity.thread_id.to_string()))?
            };
            self.retain_directory_identity(&parent)?;
            Some(parent.thread_id.to_string())
        } else {
            None
        };
        let reservation = self.reserve_resources(
            identity.thread_id.as_str(),
            parent.as_deref(),
            Some(PreparedResources::Acp(resources.clone())),
        )?;
        self.0
            .state()
            .creating
            .get_mut(identity.thread_id.as_str())
            .expect("registered ACP preparation")
            .identity = Some(identity.clone());
        Ok(AcpPreparation {
            owner: self.clone(),
            _reservation: reservation,
            identity,
            binding: pl_protocol::AgentBinding::Acp(pl_protocol::AcpAgentConfig { account_id }),
            resources,
        })
    }

    pub(crate) fn publish_acp_child_resources(&self, id: &str) -> Result<(), ThreadAssemblyError> {
        let mut state = self.0.state();
        if state.closing
            || state.sealed_agents.contains_key(id)
            || state
                .preparing_children
                .get(id)
                .is_some_and(|child| child.cancellation.is_cancelled())
        {
            return Err(ThreadAssemblyError::Closed);
        }
        if !state.entries.get(id).is_some_and(|entry| {
            matches!(&entry.runtime, AgentRuntime::Acp(acp) if !acp.cancellation.is_cancelled())
        }) {
            return Err(ThreadAssemblyError::Identity(id.into()));
        }
        // A cold ACP member has no new-child reservation.
        let unpublished = state.unpublished_children.remove(id);
        drop(state);
        drop(unpublished);
        Ok(())
    }

    pub(crate) async fn bind_acp_result_delivery(
        &self,
        identity: &pl_protocol::AgentThreadIdentity,
        resources: &Arc<AcpResources>,
    ) -> anyhow::Result<()> {
        let Some(parent_agent) = &identity.parent_agent_id else {
            return Ok(());
        };
        let parent = {
            let state = self.0.state();
            let services = state
                .agent_services
                .as_ref()
                .ok_or(ThreadAssemblyError::Closed)?;
            let parent = services
                .events
                .member_identity(&identity.session_id, parent_agent)
                .ok_or(ThreadAssemblyError::Closed)?;
            let (_, binding, _) = services
                .events
                .agent_execution_identity(parent.thread_id.as_str())
                .ok_or(ThreadAssemblyError::Closed)?;
            if !matches!(binding, pl_protocol::AgentBinding::Native(_)) {
                return Ok(());
            }
            parent
        };
        let registry = Arc::downgrade(&self.0);
        let child = identity.clone();
        let generation = resources.generation.clone();
        resources.start_result_delivery(Arc::new(move |completed| {
            let registry = registry.clone();
            let parent = parent.clone();
            let child = child.clone();
            let generation = generation.clone();
            Box::pin(async move {
                let owner = SessionRuntime(registry.upgrade().ok_or(ThreadAssemblyError::Closed)?);
                let services = owner.0.state().agent_services.clone().ok_or(ThreadAssemblyError::Closed)?;
                let result = match &completed.result {
                    Ok(response) => serde_json::to_value(response)?,
                    Err(error) => serde_json::json!({"error": error}),
                };
                let text = serde_json::to_string(&serde_json::json!({
                    "agentId": child.agent_id, "backend": "acp", "generation": generation,
                    "run": {"instance": completed.run.instance, "sequence": completed.run.sequence},
                    "completionSequence": completed.completion_sequence,
                    "result": result, "summary": completed.summary, "truncated": completed.truncated,
                }))?;
                let message = pl_core::thread::inbox::ThreadMessage {
                    kind: pl_core::context::AgentMessageKind::Report,
                    id: format!("studio.acp.{}:{}:{generation}:{}", child.agent_id.as_str().len(),
                        child.agent_id, completed.completion_sequence),
                    source_id: format!("agent:{}", child.thread_id),
                    payload: pl_core::context::OpaquePayload::text(text.clone()),
                    context: vec![pl_core::context::ContextContent::Text { text: text.into() }],
                };
                services.redeliver_parent_report(&owner, parent.thread_id.as_str(), message).await
            })
        })).await
    }

    /// Every control resolves the original runtime generation, not just AgentId.
    pub(crate) fn acp_resources(
        &self,
        thread_id: &str,
        agent_id: &str,
        instance: u64,
    ) -> Result<Arc<AcpResources>, ThreadAssemblyError> {
        let state = self.0.state();
        if state.closing || state.sealed_agents.contains_key(thread_id) {
            return Err(ThreadAssemblyError::Closed);
        }
        let entry = state.entries.get(thread_id).ok_or_else(|| {
            if state.creating.contains_key(thread_id) {
                ThreadAssemblyError::Preparing(thread_id.into())
            } else {
                ThreadAssemblyError::Closed
            }
        })?;
        if entry.identity.agent_id.as_str() != agent_id {
            return Err(ThreadAssemblyError::Identity(thread_id.into()));
        }
        match &entry.runtime {
            AgentRuntime::Acp(acp)
                if acp.instance == instance && !acp.cancellation.is_cancelled() =>
            {
                Ok(acp.clone())
            }
            AgentRuntime::Acp(_) => Err(ThreadAssemblyError::Identity(thread_id.into())),
            AgentRuntime::Native(_) => Err(ThreadAssemblyError::UnsupportedBackend {
                backend: pl_protocol::AgentBackendKind::Native,
            }),
        }
    }
}

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
        if &identity.session_id != self.id() || identity.parent_agent_id.is_some() {
            return Err(ThreadAssemblyError::Identity(
                identity.thread_id.to_string(),
            ));
        }
        let reservation = self.reserve_resources(
            identity.thread_id.as_str(),
            None,
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

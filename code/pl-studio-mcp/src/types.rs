use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use tokio_util::sync::CancellationToken;

/// The existing host operations; neither a caller identity nor an authority grant.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum HostOperation {
    SpawnAgent,
    SendMessage,
    ListAgents,
    WaitAgent,
    InterruptAgent,
    CloseAgent,
    ListAgentProfiles,
    ListDelegationModels,
    GetDelegationModel,
}

impl HostOperation {
    pub const fn tool_name(self) -> &'static str {
        match self {
            Self::SpawnAgent => "anywork_spawn_agent",
            Self::SendMessage => "anywork_send_message",
            Self::ListAgents => "anywork_list_agents",
            Self::WaitAgent => "anywork_wait_agent",
            Self::InterruptAgent => "anywork_interrupt_agent",
            Self::CloseAgent => "anywork_close_agent",
            Self::ListAgentProfiles => "anywork_list_agent_profiles",
            Self::ListDelegationModels => "anywork_list_delegation_models",
            Self::GetDelegationModel => "anywork_get_delegation_model",
        }
    }

    pub fn from_tool_name(name: &str) -> Option<Self> {
        match name {
            "anywork_spawn_agent" => Some(Self::SpawnAgent),
            "anywork_send_message" => Some(Self::SendMessage),
            "anywork_list_agents" => Some(Self::ListAgents),
            "anywork_wait_agent" => Some(Self::WaitAgent),
            "anywork_interrupt_agent" => Some(Self::InterruptAgent),
            "anywork_close_agent" => Some(Self::CloseAgent),
            "anywork_list_agent_profiles" => Some(Self::ListAgentProfiles),
            "anywork_list_delegation_models" => Some(Self::ListDelegationModels),
            "anywork_get_delegation_model" => Some(Self::GetDelegationModel),
            _ => None,
        }
    }
}

/// Consumer projection of the runtime's author-owned tool declaration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HostTool {
    pub operation: HostOperation,
    pub description: String,
    pub input_schema: Map<String, Value>,
}

pub type HostCatalog = Vec<HostTool>;

/// A domain invocation. Trusted identity and call IDs are assigned inside the runtime.
#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HostInvocation {
    pub operation: HostOperation,
    pub arguments: Map<String, Value>,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HostResult {
    pub value: Value,
    pub is_error: bool,
}

/// Safe adapter diagnostics. Business failures are returned as `HostResult`.
#[derive(Debug, Clone, thiserror::Error)]
pub enum HostError {
    #[error("host service is closed")]
    Closed,
    #[error("host IPC connection failed")]
    Transport,
    #[error("host IPC authentication failed")]
    Unauthorized,
    #[error("invalid host request")]
    InvalidRequest,
    #[error("host message exceeds the size limit")]
    TooLarge,
}

/// Transport-independent access to the original runtime; implementations never select a caller
/// from request arguments. Cancellation ends this observation, not already-owned business work.
pub trait HostTools: Clone + Send + Sync + 'static {
    fn catalog(&self) -> impl Future<Output = Result<HostCatalog, HostError>> + Send;

    fn invoke(
        &self,
        request: HostInvocation,
        cancellation: CancellationToken,
    ) -> impl Future<Output = Result<HostResult, HostError>> + Send;
}

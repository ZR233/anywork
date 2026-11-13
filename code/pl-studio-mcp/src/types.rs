use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};
use tokio_util::sync::CancellationToken;

/// Consumer projection of the runtime's author-owned tool declaration.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HostTool {
    /// Exact identity from this instance's prepared catalog, not a permission grant.
    pub tool_id: String,
    pub description: String,
    pub input_schema: Map<String, Value>,
}

pub type HostCatalog = Vec<HostTool>;

/// A domain invocation. Trusted identity and call IDs are assigned inside the runtime.
#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HostInvocation {
    pub tool_id: String,
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

use std::fmt;

use pl_agent_tool::ToolResult;
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
    /// Published only when the backend actually returns the author's final result contract.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub output_schema: Option<Map<String, Value>>,
}

pub type HostCatalog = Vec<HostTool>;

/// A domain invocation. Trusted identity and call IDs are assigned inside the runtime.
#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HostInvocation {
    pub tool_id: String,
    pub arguments: Map<String, Value>,
}

/// One explicitly authored MCP content block.
#[derive(Serialize, Deserialize)]
#[serde(rename_all = "snake_case", deny_unknown_fields)]
pub enum HostContent {
    Text(String),
    Image {
        /// Base64-encoded image data.
        data: String,
        mime_type: String,
    },
}

impl fmt::Debug for HostContent {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Text(_) => f.write_str("Text(..)"),
            Self::Image { .. } => f.write_str("Image { .. }"),
        }
    }
}

#[derive(Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HostResult {
    pub result: ToolResult<HostContent>,
    pub is_error: bool,
}

impl HostResult {
    /// Authors a JSON result with its default model-readable representation.
    pub fn json(value: Value, is_error: bool) -> Self {
        let content = vec![HostContent::Text(value.to_string())];
        Self {
            result: ToolResult::from_data(value, content),
            is_error,
        }
    }
}

impl fmt::Debug for HostResult {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("HostResult")
            .field("is_error", &self.is_error)
            .field("content", &self.result.content())
            .finish_non_exhaustive()
    }
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

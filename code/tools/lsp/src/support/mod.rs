//! Narrow language-service capabilities. No server registry, path policy or
//! helper-process type crosses this boundary.
use serde::{Deserialize, Serialize};
use std::{error::Error, future::Future, path::PathBuf};
pub use tokio_util::sync::CancellationToken;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase")]
pub enum Operation {
    GoToDefinition,
    FindReferences,
    Hover,
    DocumentSymbol,
    WorkspaceSymbol,
    GoToImplementation,
    PrepareCallHierarchy,
    IncomingCalls,
    OutgoingCalls,
    Diagnostics,
}

impl Operation {
    pub fn requires_position(self) -> bool {
        matches!(
            self,
            Self::GoToDefinition
                | Self::FindReferences
                | Self::Hover
                | Self::GoToImplementation
                | Self::PrepareCallHierarchy
                | Self::IncomingCalls
                | Self::OutgoingCalls
        )
    }

    pub fn requires_file(self) -> bool {
        self.requires_position() || matches!(self, Self::DocumentSymbol)
    }
}

#[derive(Debug)]
pub struct QueryRequest {
    pub language_id: String,
    pub operation: Operation,
    pub file_path: Option<PathBuf>,
    pub line: Option<u32>,
    pub character: Option<u32>,
    pub query: Option<String>,
    pub max_results: Option<usize>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct QueryResult {
    pub success: bool,
    pub operation: Operation,
    pub server_id: Option<String>,
    pub result: String,
    pub result_count: Option<usize>,
    pub file_count: Option<usize>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Capabilities {
    pub servers: Vec<ServerCapabilities>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ServerCapabilities {
    pub id: String,
    pub display_name: String,
    pub language_ids: Vec<String>,
    pub operations: Vec<String>,
    pub availability: String,
    pub ready: bool,
}

/// Reads the existing service owner; never starts or closes a second registry.
pub trait CapabilityReader: Send + Sync + 'static {
    type Error: Error + Send + Sync + 'static;
    fn capabilities(&self) -> impl Future<Output = Result<Capabilities, Self::Error>> + Send;
}

pub trait QueryService: Send + Sync + 'static {
    type Error: Error + Send + Sync + 'static;

    /// Host resolves and authorizes the path using its invocation grant. This
    /// capability does not let input choose or replace the workspace.
    fn resolve_path(
        &self,
        path: PathBuf,
        operation: Operation,
    ) -> impl Future<Output = Result<PathBuf, Self::Error>> + Send;

    fn query(
        &self,
        request: QueryRequest,
    ) -> impl Future<Output = Result<QueryResult, Self::Error>> + Send;
}

pub struct LspContext<S> {
    pub service: S,
    pub cancellation: CancellationToken,
}

/// The domain value is retained in full; the host chooses its history envelope.
#[derive(Debug)]
pub struct LspResult<T> {
    pub value: T,
}

impl<T: Serialize> LspResult<T> {
    pub fn encode(&self) -> Result<(String, String), serde_json::Error> {
        let encoded = serde_json::to_string(&self.value)?;
        let preview = pl_output::bounded_text(&encoded, 12 * 1024, 0);
        let text = if preview.truncated {
            format!(
                "{}\n[LSP preview omitted {} bytes; full result retained in history.]",
                preview.text, preview.bytes_omitted
            )
        } else {
            preview.text
        };
        Ok((encoded, text))
    }
}

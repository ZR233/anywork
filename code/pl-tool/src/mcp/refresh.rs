//! Results of explicit discovery over the runtime's existing MCP connections.

/// Discovery outcome, independent of transport availability and catalog installation.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub enum McpToolRefreshStatus {
    Updated,
    Unchanged,
    Failed,
    Skipped,
}

/// One server's discovery result. Diagnostics must already be redacted by its owner.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct McpServerToolRefresh {
    pub server_id: String,
    pub status: McpToolRefreshStatus,
    pub tool_count: Option<usize>,
    pub message: Option<String>,
}

/// Completed discovery results; this is not a Thread tool-catalog installation receipt.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct McpToolRefreshReport {
    pub generation: u64,
    pub servers: Vec<McpServerToolRefresh>,
}

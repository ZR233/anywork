//! Frozen MCP transport capabilities and shared MCP content projection.
use std::{error::Error, fmt, future::Future, sync::Mutex};

use pl_agent_tool::ToolDefinition;
use pl_tool_media_support::{CancellationToken, ImageOutputLimits};
use rmcp::model::CallToolResult;
use serde_json::Value;

mod projection;
pub use projection::{bound_text, project_content, project_resource};

/// The complete remote declaration and routing identity, frozen by one transport lease.
#[derive(Debug, Clone)]
pub struct FrozenTool {
    pub server_id: String,
    pub raw_name: String,
    pub exposed_name: String,
    pub description: String,
    pub input_schema: Value,
    pub output_schema: Option<Value>,
}

impl FrozenTool {
    pub fn definition(&self) -> Result<ToolDefinition, pl_agent_tool::DefinitionError> {
        let definition = ToolDefinition::json(
            &self.exposed_name,
            &self.description,
            self.input_schema.clone(),
        )?;
        match &self.output_schema {
            Some(schema) => definition.with_output_schema(schema.clone()),
            None => Ok(definition),
        }
    }
}

#[derive(Debug, Clone)]
pub enum ResourceOperation {
    ListResources { cursor: Option<String> },
    ListResourceTemplates { cursor: Option<String> },
    ReadResource { uri: String },
}

/// A host-owned frozen transport generation, not a runtime owner or authorization object.
pub trait FrozenMcpLease: Clone + Send + Sync + 'static {
    type Error: Error + Send + Sync + 'static;

    fn generation(&self) -> u64;
    fn tool(&self, exposed_name: &str) -> Option<FrozenTool>;
    fn resource_server_ids(&self) -> &[String];
    fn call_tool(
        &self,
        server_id: String,
        raw_name: String,
        arguments: Value,
    ) -> impl Future<Output = Result<CallToolResult, Self::Error>> + Send;
    fn resource_query(
        &self,
        server_id: Option<String>,
        operation: ResourceOperation,
    ) -> impl Future<Output = Result<Value, Self::Error>> + Send;
}

/// Each tool owns its slot; cloning for a call keeps only that call's transport alive.
pub struct LeaseSlot<L>(Mutex<Option<L>>);

impl<L: Clone> LeaseSlot<L> {
    pub fn new(lease: L) -> Self {
        Self(Mutex::new(Some(lease)))
    }

    pub fn acquire<P: fmt::Debug>(&self) -> Result<L, McpError<P>> {
        self.0
            .lock()
            .map_err(|_| McpError::invalid("MCP lease lock poisoned"))?
            .clone()
            .ok_or_else(|| McpError::invalid("MCP tool is closed"))
    }

    pub fn release<P: fmt::Debug>(&self) -> Result<(), McpError<P>> {
        let lease = self
            .0
            .lock()
            .map_err(|_| McpError::invalid("MCP lease lock poisoned"))?
            .take();
        drop(lease);
        Ok(())
    }
}

#[derive(Debug, Clone, Default)]
pub struct McpContext {
    pub image_limits: Option<ImageOutputLimits>,
    pub cancellation: CancellationToken,
}

/// MCP owns text projection; opaque media delivery remains entirely host-owned.
#[derive(Debug)]
pub enum Content<P> {
    Text(String),
    Media(P),
}

#[derive(Debug, Clone, Copy)]
pub enum ResultKind {
    Tool,
    Resources,
}

#[derive(Debug)]
pub struct McpOutput<P> {
    pub protocol: Value,
    pub content: Vec<Content<P>>,
    pub kind: ResultKind,
}

#[derive(Debug)]
pub enum Observed<P> {
    Projected(McpOutput<P>),
    Unarchived { protocol: Value, kind: ResultKind },
}

/// Side effects are never repeated to repair local projection or storage failures.
#[derive(Debug)]
pub struct McpError<P: fmt::Debug> {
    pub source: Box<dyn Error + Send + Sync>,
    pub observed: Option<Observed<P>>,
}

impl<P: fmt::Debug> fmt::Display for McpError<P> {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        self.source.fmt(formatter)
    }
}

impl<P: fmt::Debug + 'static> Error for McpError<P> {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        Some(self.source.as_ref())
    }
}

impl<P: fmt::Debug> McpError<P> {
    pub fn new(source: impl Error + Send + Sync + 'static) -> Self {
        Self {
            source: Box::new(source),
            observed: None,
        }
    }

    pub fn invalid(message: impl Into<String>) -> Self {
        Self::new(std::io::Error::other(message.into()))
    }

    pub fn with_unarchived(mut self, protocol: Value, kind: ResultKind) -> Self {
        self.observed = Some(Observed::Unarchived { protocol, kind });
        self
    }
}

pub fn validate_resource_server<L: FrozenMcpLease, P: fmt::Debug>(
    lease: &L,
    server: Option<&str>,
) -> Result<(), McpError<P>> {
    if lease.resource_server_ids().is_empty()
        || server.is_some_and(|server| !lease.resource_server_ids().iter().any(|id| id == server))
    {
        return Err(McpError::invalid(
            "server has no resource capability in this lease",
        ));
    }
    Ok(())
}

pub fn list_output<P>(protocol: Value) -> Result<McpOutput<P>, McpError<P>>
where
    P: fmt::Debug,
{
    let mut content = vec![Content::Text(
        serde_json::to_string(&protocol).map_err(McpError::new)?,
    )];
    bound_text(&mut content);
    Ok(McpOutput {
        protocol,
        content,
        kind: ResultKind::Resources,
    })
}

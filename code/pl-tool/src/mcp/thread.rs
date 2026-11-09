//! Anywork binding for the independent dynamic MCP executor.
use super::{McpRuntimeToolDescriptor, McpTurnLease};
use crate::media::{DomainMediaHost, ToolMediaHost, domain_error, image_limits};
use pl_agent_tool::Tool;
use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, ToolError},
    },
};
use pl_tool_mcp_support::{
    Content, FrozenTool, McpContext, McpError, McpOutput, Observed, ResultKind,
};
use std::sync::Arc;

pub struct ThreadMcpTool<H> {
    authorization: pl_core::tool::opaque::ToolAuthorization,
    inner: pl_tool_mcp::McpTool<McpTurnLease, DomainMediaHost<H>>,
}

impl<H: ToolMediaHost> ThreadMcpTool<H> {
    pub fn new(lease: McpTurnLease, tool_id: &str, media: Arc<H>) -> Result<Self, ToolError> {
        let authorization = lease.authorization();
        let inner = pl_tool_mcp::McpTool::new(lease, tool_id, Arc::new(DomainMediaHost(media)))
            .map_err(|error| map_error(error, |content| content))?;
        Ok(Self {
            authorization,
            inner,
        })
    }

    pub fn registration(
        self,
        prepared: pl_core::tool::opaque::PreparedRegistration,
    ) -> Registration {
        let authorization = self.authorization.clone();
        prepared
            .attach(pl_agent_tool::ToolHandle::new(self))
            .deferred()
            .with_authorization(authorization)
    }
}

impl McpRuntimeToolDescriptor {
    /// Preserves the complete frozen remote schema, without normalizing or rediscovering it.
    pub fn definition(
        &self,
    ) -> Result<pl_agent_tool::ToolDefinition, pl_agent_tool::DefinitionError> {
        FrozenTool::from(self).definition()
    }
}

impl<H: ToolMediaHost> Tool for ThreadMcpTool<H> {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        self.inner.definition()
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let input = json_text(&input)?;
        let context = mcp_context(&context)?;
        self.inner
            .execute(input, context)
            .await
            .map_err(|error| map_error(error, |content| content))
            .and_then(|output| map_output(output, |content| content))
    }

    async fn close(&self) -> Result<(), ToolError> {
        self.inner
            .close()
            .await
            .map_err(|error| map_error(error, |content| content))
    }
}

pub(super) fn json_text(input: &OpaquePayload) -> Result<String, ToolError> {
    if input.format() != "application/json" || input.version() != 1 {
        return Err(ToolError::new(
            pl_agent_tool::typed::ArgumentError::UnsupportedPayload {
                format: input.format().to_owned(),
                version: input.version(),
            },
        ));
    }
    Ok(input.content().to_owned())
}

pub(super) fn mcp_context(context: &CallContext) -> Result<McpContext, ToolError> {
    Ok(McpContext {
        image_limits: image_limits(context.model_projection.as_ref())?,
        cancellation: context.cancellation.clone(),
    })
}

pub(super) fn map_output<P>(
    output: McpOutput<P>,
    media: impl Fn(P) -> Vec<ContextContent>,
) -> Result<ToolOutput, ToolError> {
    let format = match output.kind {
        ResultKind::Tool => "pl.tool.mcp-result",
        ResultKind::Resources => "pl.tool.mcp-resources",
    };
    let content = output
        .content
        .into_iter()
        .flat_map(|content| match content {
            Content::Text(text) => vec![ContextContent::Text { text: text.into() }],
            Content::Media(projection) => media(projection),
        })
        .collect();
    Ok(ToolOutput::new(
        OpaquePayload::new(
            format,
            1,
            serde_json::to_string(&output.protocol).map_err(ToolError::new)?,
        )
        .map_err(ToolError::new)?,
        content,
    ))
}

pub(super) fn map_error<P: std::fmt::Debug>(
    error: McpError<P>,
    media: impl Fn(P) -> Vec<ContextContent>,
) -> ToolError {
    let message = error.to_string();
    let source = domain_error(error.source);
    let observed = match error.observed {
        Some(Observed::Projected(output)) => map_output(output, media)
            .expect("MCP projected values and fixed history format are valid"),
        Some(Observed::Unarchived { protocol, kind }) => {
            let (format, note) = match kind {
                ResultKind::Tool => (
                    "pl.tool.mcp-unarchived",
                    "MCP result was received, but its resources could not be prepared",
                ),
                ResultKind::Resources => (
                    "pl.tool.mcp-resources-unarchived",
                    "MCP resource was received but could not be prepared",
                ),
            };
            ToolOutput::new(
                OpaquePayload::new(format, 1, protocol.to_string())
                    .expect("fixed MCP observation format"),
                vec![ContextContent::Text {
                    text: format!("{note}: {message}").into(),
                }],
            )
        }
        None => return source,
    };
    source.with_output(observed)
}

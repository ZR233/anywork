//! Anywork registrations for the three independent MCP resource tools.
use super::{
    McpTurnLease,
    thread::{json_text, map_error, map_output, mcp_context},
};
use crate::media::{DomainMediaHost, ToolMediaHost};
use pl_agent_tool::typed::TypedTool;
use pl_core::{
    context::OpaquePayload,
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, ToolError},
    },
};
use std::sync::Arc;

type List = pl_tool_mcp::list_resources::ListMcpResources<McpTurnLease>;
type Templates = pl_tool_mcp::list_resource_templates::ListMcpResourceTemplates<McpTurnLease>;
type Read<H> = pl_tool_mcp::read_resource::ReadMcpResource<McpTurnLease, DomainMediaHost<H>>;

#[derive(Debug, Clone, Copy)]
pub enum McpResourceToolKind {
    ListResources,
    ListResourceTemplates,
    ReadResource,
}

impl McpResourceToolKind {
    pub fn all() -> &'static [Self] {
        &[
            Self::ListResources,
            Self::ListResourceTemplates,
            Self::ReadResource,
        ]
    }

    pub fn name(self) -> &'static str {
        match self {
            Self::ListResources => List::NAME,
            Self::ListResourceTemplates => Templates::NAME,
            Self::ReadResource => pl_tool_mcp::read_resource::NAME,
        }
    }

    pub fn definition(self) -> pl_agent_tool::ToolDefinition {
        let (description, schema) = match self {
            Self::ListResources => (
                List::DESCRIPTION,
                pl_agent_tool::typed::input_schema_for::<pl_tool_mcp::list_resources::Input>(),
            ),
            Self::ListResourceTemplates => (
                Templates::DESCRIPTION,
                pl_agent_tool::typed::input_schema_for::<pl_tool_mcp::list_resource_templates::Input>(
                ),
            ),
            Self::ReadResource => (
                pl_tool_mcp::read_resource::DESCRIPTION,
                pl_agent_tool::typed::input_schema_for::<pl_tool_mcp::read_resource::Input>(),
            ),
        };
        pl_agent_tool::ToolDefinition::json(self.name(), description, schema)
            .expect("static MCP resource definition")
            .with_output_schema(match self {
                Self::ListResources => resource_list_schema::<rmcp::model::ListResourcesResult>(),
                Self::ListResourceTemplates => {
                    resource_list_schema::<rmcp::model::ListResourceTemplatesResult>()
                }
                Self::ReadResource => read_resource_schema(),
            })
            .expect("static MCP resource output schema")
    }
}

fn resource_list_schema<T: schemars::JsonSchema>() -> serde_json::Value {
    use serde_json::{Value, json};
    let mut page = crate::binding::program_schema::<T>();
    let object = page
        .as_object_mut()
        .expect("resource list schema is an object");
    let draft = object.remove("$schema");
    let definitions = object.remove("$defs");
    // The frozen host returns one protocol page or pages keyed by server ID.
    let mut result = json!({"anyOf": [page, {"type":"object", "additionalProperties": page}]});
    if let Some(Value::String(draft)) = draft {
        result["$schema"] = draft.into();
    }
    if let Some(definitions) = definitions {
        result["$defs"] = definitions;
    }
    result
}

fn read_resource_schema() -> serde_json::Value {
    use serde_json::json;
    let mut schema = crate::binding::program_schema::<rmcp::model::ReadResourceResult>();
    // The media owner consumes the transport's blob and retains its exact bytes.
    schema["properties"]["contents"]["items"] = json!({
        "type":"object", "properties": {
            "uri":{"type":"string"},"mimeType":{"type":"string"},"_meta":{"type":"object"},
            "text":{"type":"string"},
            "retainedResource":crate::media::resource_reference_schema()
        }, "required":["uri"], "oneOf":[{"required":["text"]},{"required":["retainedResource"]}],
        "additionalProperties":false
    });
    schema
}

enum ResourceTool<H> {
    List(List),
    Templates(Templates),
    Read(Read<H>),
}

pub struct ThreadMcpResourceTool<H> {
    definition: pl_agent_tool::ToolDefinition,
    authorization: pl_core::tool::opaque::ToolAuthorization,
    inner: ResourceTool<H>,
}

impl<H: ToolMediaHost> ThreadMcpResourceTool<H> {
    pub fn new(
        lease: McpTurnLease,
        kind: McpResourceToolKind,
        media: Arc<H>,
        definition: pl_agent_tool::ToolDefinition,
    ) -> Self {
        let authorization = lease.authorization();
        let inner = match kind {
            McpResourceToolKind::ListResources => ResourceTool::List(List::new(lease)),
            McpResourceToolKind::ListResourceTemplates => {
                ResourceTool::Templates(Templates::new(lease))
            }
            McpResourceToolKind::ReadResource => {
                ResourceTool::Read(Read::new(lease, Arc::new(DomainMediaHost(media))))
            }
        };
        Self {
            definition,
            authorization,
            inner,
        }
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

impl<H: ToolMediaHost> pl_agent_tool::Tool for ThreadMcpResourceTool<H> {
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let text = json_text(&input)?;
        let context = mcp_context(&context)?;
        match &self.inner {
            ResourceTool::List(tool) => {
                let input = pl_agent_tool::typed::decode_json(&text).map_err(ToolError::new)?;
                tool.execute(input, context)
                    .await
                    .map_err(|error| map_error(error, |()| Vec::new()))
                    .map(|output| map_output(output, |()| Vec::new()))
            }
            ResourceTool::Templates(tool) => {
                let input = pl_agent_tool::typed::decode_json(&text).map_err(ToolError::new)?;
                tool.execute(input, context)
                    .await
                    .map_err(|error| map_error(error, |()| Vec::new()))
                    .map(|output| map_output(output, |()| Vec::new()))
            }
            ResourceTool::Read(tool) => {
                let input = pl_agent_tool::typed::decode_json(&text).map_err(ToolError::new)?;
                tool.execute(input, context)
                    .await
                    .map_err(|error| map_error(error, |content| content))
                    .map(|output| map_output(output, |content| content))
            }
        }
    }

    async fn close(&self) -> Result<(), ToolError> {
        match &self.inner {
            ResourceTool::List(tool) => tool
                .close()
                .await
                .map_err(|error| map_error(error, |()| Vec::new())),
            ResourceTool::Templates(tool) => tool
                .close()
                .await
                .map_err(|error| map_error(error, |()| Vec::new())),
            ResourceTool::Read(tool) => tool
                .close()
                .await
                .map_err(|error| map_error(error, |content| content)),
        }
    }
}

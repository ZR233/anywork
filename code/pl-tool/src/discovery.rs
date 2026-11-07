//! Model-callable discovery over the Thread's read-only opaque tool directory.
use pl_core::context::{ContextContent, OpaquePayload};
use pl_core::tool::{
    ToolOutput,
    opaque::{CallContext, ToolError},
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;

/// Matches stable tool identities without parsing provider declaration formats.
#[derive(Debug)]
pub struct DiscoverTools;

#[derive(Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct SearchInput {
    query: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SearchResult {
    tool_ids: Vec<String>,
}

impl pl_agent_tool::typed::TypedTool for DiscoverTools {
    const NAME: &'static str = DISCOVER_TOOLS_NAME;
    const DESCRIPTION: &'static str = DISCOVER_TOOLS_DESCRIPTION;
    type Args = SearchInput;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    async fn execute(
        &self,
        request: Self::Args,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let query = request.query.trim().to_lowercase();
        let ids = context
            .catalog
            .iter()
            .filter(|tool| {
                tool.tool_id != "discover_tools" && tool.tool_id.to_lowercase().contains(&query)
            })
            .take(20)
            .map(|tool| tool.tool_id.clone())
            .collect::<Vec<_>>();
        let result = serde_json::to_string(&SearchResult {
            tool_ids: ids.clone(),
        })
        .map_err(ToolError::new)?;
        Ok(ToolOutput::new(
            OpaquePayload::text(result.clone()),
            vec![ContextContent::Text {
                text: Arc::from(result),
            }],
        )
        .with_revealed_tools(ids))
    }
}

pub fn discover_tools_definition() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::ToolDefinition::json(
        DISCOVER_TOOLS_NAME,
        DISCOVER_TOOLS_DESCRIPTION,
        pl_agent_tool::typed::input_schema_for::<SearchInput>(),
    )
    .expect("static tool definition")
}

const DISCOVER_TOOLS_NAME: &str = "discover_tools";
const DISCOVER_TOOLS_DESCRIPTION: &str = "Reveal up to 20 tool IDs matching query as one case-insensitive literal ID substring (surrounding whitespace is trimmed). Use an exact ID or a fragment such as 'delegation'; not a natural-language request, description search, or space-separated list. An empty query returns only the first 20 matches, not the full catalog. No match means this substring did not match the current Thread catalog, not that a capability is globally unavailable.";

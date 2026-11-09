//! Language-service capability discovery, independent of the product host.
use pl_agent_tool::{Tool, ToolDefinition};
use pl_tool_lsp_support::{Capabilities, CapabilityReader, LspContext, LspResult};
use std::marker::PhantomData;

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct LspCapabilitiesInput {}

pub fn lsp_capabilities_definition() -> ToolDefinition {
    ToolDefinition::json(
        "lsp_capabilities",
        "List language IDs, query operations and readiness for this workspace.",
        pl_agent_tool::typed::input_schema_for::<LspCapabilitiesInput>(),
    )
    .expect("static tool definition")
}

#[derive(Debug, thiserror::Error)]
pub enum CapabilitiesError<E: std::error::Error + 'static> {
    #[error(transparent)]
    Input(#[from] pl_agent_tool::typed::ArgumentError),
    #[error("language-service discovery cancelled")]
    Cancelled,
    #[error(transparent)]
    Service(E),
}

#[derive(Debug)]
pub struct LspCapabilitiesTool<S> {
    definition: ToolDefinition,
    service: PhantomData<fn() -> S>,
}

impl<S> LspCapabilitiesTool<S> {
    pub fn new(definition: ToolDefinition) -> Self {
        Self {
            definition,
            service: PhantomData,
        }
    }
}

impl<S: CapabilityReader> Tool for LspCapabilitiesTool<S> {
    type Input = String;
    type Context = LspContext<S>;
    type Output = LspResult<Capabilities>;
    type Error = CapabilitiesError<S::Error>;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: String,
        context: LspContext<S>,
    ) -> Result<Self::Output, Self::Error> {
        let _: LspCapabilitiesInput = pl_agent_tool::typed::decode_json(&input)?;
        if context.cancellation.is_cancelled() {
            return Err(CapabilitiesError::Cancelled);
        }
        let value = context
            .service
            .capabilities()
            .await
            .map_err(CapabilitiesError::Service)?;
        Ok(LspResult { value })
    }
}

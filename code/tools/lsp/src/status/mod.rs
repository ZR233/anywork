//! Read-only lifecycle visibility, including when semantic tools are unavailable.
use crate::support::{LspContext, LspResult, StatusReader, WorkspaceStatus};
use pl_agent_tool::{Tool, ToolDefinition};
use std::marker::PhantomData;

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub struct LspStatusInput {}

pub fn lsp_status_definition() -> ToolDefinition {
    ToolDefinition::json(
        "lsp_status",
        "Read current workspace language-server configuration sources, initialization phases, progress and failures. Available even when no server is ready. This only reads published state; it never starts, reloads or waits for a server. Configure one server per .anywork/lsp/<server-id>.toml; consult studio-config for instructions.",
        pl_agent_tool::typed::input_schema_for::<LspStatusInput>(),
    )
    .expect("static tool definition")
}

#[derive(Debug, thiserror::Error)]
pub enum StatusError<E: std::error::Error + 'static> {
    #[error(transparent)]
    Input(#[from] pl_agent_tool::typed::ArgumentError),
    #[error("language-service status read cancelled")]
    Cancelled,
    #[error(transparent)]
    Service(E),
}

#[derive(Debug)]
pub struct LspStatusTool<S> {
    definition: ToolDefinition,
    service: PhantomData<fn() -> S>,
}

impl<S> LspStatusTool<S> {
    pub fn new(definition: ToolDefinition) -> Self {
        Self {
            definition,
            service: PhantomData,
        }
    }
}

impl<S: StatusReader> Tool for LspStatusTool<S> {
    type Input = String;
    type Context = LspContext<S>;
    type Output = LspResult<WorkspaceStatus>;
    type Error = StatusError<S::Error>;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: String,
        context: LspContext<S>,
    ) -> Result<Self::Output, Self::Error> {
        let _: LspStatusInput = pl_agent_tool::typed::decode_json(&input)?;
        if context.cancellation.is_cancelled() {
            return Err(StatusError::Cancelled);
        }
        let value = context
            .service
            .status()
            .await
            .map_err(StatusError::Service)?;
        Ok(LspResult { value })
    }
}

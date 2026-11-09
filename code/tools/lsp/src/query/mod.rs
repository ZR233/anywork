//! Validates and orchestrates language-service queries through restricted ports.
use crate::support::{LspContext, LspResult, Operation, QueryRequest, QueryResult, QueryService};
use pl_agent_tool::{Tool, ToolDefinition};
use std::{marker::PhantomData, path::PathBuf};

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LspQueryInput {
    /// 目标语言 ID；运行期按 catalog 路由到对应 server。
    pub language_id: String,
    pub operation: Operation,
    /// Workspace-relative or absolute path to the source file.
    pub file_path: Option<PathBuf>,
    /// 1-based line number for position operations.
    #[schemars(range(min = 1))]
    pub line: Option<u32>,
    /// 1-based UTF-16 character offset for position operations.
    #[schemars(range(min = 1))]
    pub character: Option<u32>,
    /// Workspace symbol query string.
    pub query: Option<String>,
    /// Maximum results to return.
    #[schemars(range(min = 1))]
    pub max_results: Option<usize>,
}

pub fn lsp_query_definition() -> ToolDefinition {
    ToolDefinition::json(
        "lsp_query",
        "Query workspace language services for definitions, references, hover, symbols, call hierarchy or diagnostics. Discover supported languages with lsp_capabilities.",
        pl_agent_tool::typed::input_schema_for::<LspQueryInput>(),
    ).expect("static tool definition")
}

#[derive(Debug, thiserror::Error)]
pub enum QueryError<E: std::error::Error + 'static> {
    #[error(transparent)]
    Input(#[from] pl_agent_tool::typed::ArgumentError),
    #[error("invalid LSP query: {0}")]
    Invalid(&'static str),
    #[error("LSP query cancelled")]
    Cancelled,
    #[error("LSP path authorization failed: {0}")]
    Path(#[source] E),
    #[error(
        "LSP query for languageId `{language}` failed: {source}; lsp_capabilities lists current service readiness"
    )]
    Service {
        language: String,
        #[source]
        source: E,
    },
}

#[derive(Debug)]
pub struct LspQueryTool<S> {
    definition: ToolDefinition,
    service: PhantomData<fn() -> S>,
}

impl<S> LspQueryTool<S> {
    pub fn new(definition: ToolDefinition) -> Self {
        Self {
            definition,
            service: PhantomData,
        }
    }
}

impl<S: QueryService> Tool for LspQueryTool<S> {
    type Input = String;
    type Context = LspContext<S>;
    type Output = LspResult<QueryResult>;
    type Error = QueryError<S::Error>;

    fn definition(&self) -> &ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        raw: String,
        context: LspContext<S>,
    ) -> Result<Self::Output, Self::Error> {
        let input: LspQueryInput = pl_agent_tool::typed::decode_json(&raw)?;
        if input.language_id.trim().is_empty() {
            return Err(QueryError::Invalid("languageId must not be blank"));
        }
        if input.operation.requires_file() && input.file_path.is_none() {
            return Err(QueryError::Invalid("operation requires filePath"));
        }
        if input.line == Some(0) || input.character == Some(0) || input.max_results == Some(0) {
            return Err(QueryError::Invalid(
                "line, character and maxResults must be positive",
            ));
        }
        if input.operation.requires_position()
            && (input.line.is_none() || input.character.is_none())
        {
            return Err(QueryError::Invalid("operation requires line and character"));
        }
        if context.cancellation.is_cancelled() {
            return Err(QueryError::Cancelled);
        }
        let file_path = match input.file_path {
            Some(path) => Some(
                context
                    .service
                    .resolve_path(path, input.operation)
                    .await
                    .map_err(QueryError::Path)?,
            ),
            None => None,
        };
        if context.cancellation.is_cancelled() {
            return Err(QueryError::Cancelled);
        }
        let language = input.language_id.clone();
        let value = context
            .service
            .query(QueryRequest {
                language_id: input.language_id,
                operation: input.operation,
                file_path,
                line: input.line,
                character: input.character,
                query: input.query,
                max_results: input.max_results,
            })
            .await
            .map_err(|source| QueryError::Service { language, source })?;
        Ok(LspResult { value })
    }
}

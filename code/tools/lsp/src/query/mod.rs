//! Validates and orchestrates language-service queries through restricted ports.
use crate::support::{LspContext, LspResult, Operation, QueryRequest, QueryResult, QueryService};
use pl_agent_tool::{Tool, ToolDefinition};
use std::{marker::PhantomData, path::PathBuf};

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LspQueryInput {
    /// Language ID from lsp_capabilities, not a file extension or project name.
    pub language_id: String,
    /// Server ID from lsp_capabilities; select explicitly when the language is ambiguous.
    pub server_id: Option<String>,
    /// Semantic operation. Cursor-based operations require filePath, line and
    /// character; documentSymbol locates declarations without a cursor.
    pub operation: Operation,
    /// Source file path, relative to this Thread's execution workspace or absolute;
    /// not relative to the language package or a previous shell command's cwd.
    pub file_path: Option<PathBuf>,
    /// 1-based line in filePath itself, not a line in concatenated command output.
    /// Required only for position operations; locate the symbol before querying.
    #[schemars(range(min = 1))]
    pub line: Option<u32>,
    /// 1-based UTF-16 code-unit offset within that source line, inside the target
    /// identifier. Do not count line-number prefixes or UTF-8 bytes.
    #[schemars(range(min = 1))]
    pub character: Option<u32>,
    /// Symbol name/text filter for workspaceSymbol; not a file path or tool ID.
    pub query: Option<String>,
    /// Maximum results to return.
    #[schemars(range(min = 1))]
    pub max_results: Option<usize>,
}

pub fn lsp_query_definition() -> ToolDefinition {
    ToolDefinition::json(
        "lsp_query",
        "Resolve definitions, types, references, symbols, call relationships or diagnostics with workspace language services. Use lsp_capabilities for languages and server IDs. Read the target file or use documentSymbol/workspaceSymbol to locate a symbol before cursor queries; check that results describe the intended declaration, not just an import.",
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
        let request = context.service.query(QueryRequest {
            language_id: input.language_id,
            server_id: input.server_id,
            operation: input.operation,
            file_path,
            line: input.line,
            character: input.character,
            query: input.query,
            max_results: input.max_results,
        });
        let value = context
            .cancellation
            .run_until_cancelled(request)
            .await
            .ok_or(QueryError::Cancelled)?
            .map_err(|source| QueryError::Service { language, source })?;
        Ok(LspResult { value })
    }
}

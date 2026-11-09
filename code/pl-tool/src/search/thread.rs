//! Host bindings for independent search tools; routing and core context stay here.
use super::WebSearchClient;
use pl_agent_tool::typed::TypedTool;
use pl_core::{
    context::{ContextContent, ContextSnapshot, ContextSource, OpaquePayload},
    tool::{
        ToolOutput,
        opaque::{CallContext, ToolError},
    },
};
use pl_model::protocol::deepseek::tools::{self, Observed, ToolsClient, ToolsError};
use pl_protocol::search::SearchSettings;
use pl_tool_search::support::{
    FetchResponse, FetchService, SearchResponse, SearchService, SearchSource, ServiceFailure,
};
use serde_json::Value;
use tokio_util::sync::CancellationToken;
const ASSISTANT_CONTEXT_CHAR_LIMIT: usize = 4_000;

#[derive(Debug)]
pub struct ThreadSearchOptions {
    pub model: String,
    pub settings: SearchSettings,
    pub max_output_tokens: Option<u64>,
}

#[derive(Debug)]
pub struct StandaloneSearchService {
    client: WebSearchClient,
    options: ThreadSearchOptions,
}
impl pl_tool_search::tools::web_search::SearchService for StandaloneSearchService {
    type Error = super::WebSearchError;
    async fn search(
        &self,
        request: pl_tool_search::tools::web_search::Request,
    ) -> Result<pl_tool_search::tools::web_search::Response, Self::Error> {
        let request = pl_protocol::search::SearchRequest {
            id: request.id,
            model: self.options.model.clone(),
            input: request.input,
            commands: serde_json::from_value(serde_json::to_value(request.commands)?)?,
            settings: self.options.settings.clone(),
            max_output_tokens: self.options.max_output_tokens,
        };
        let response = self.client.search(&request).await?;
        Ok(pl_tool_search::tools::web_search::Response {
            encrypted_output: response.encrypted_output,
            output: response.output,
            results: response.results,
        })
    }
}

#[derive(Debug)]
pub struct ThreadWebSearchTool {
    tool: pl_tool_search::tools::web_search::WebSearch<StandaloneSearchService>,
}
impl ThreadWebSearchTool {
    pub fn new(client: WebSearchClient, options: ThreadSearchOptions) -> Self {
        Self {
            tool: pl_tool_search::tools::web_search::WebSearch::new(StandaloneSearchService {
                client,
                options,
            }),
        }
    }
    pub fn declaration() -> pl_agent_tool::ToolDefinition {
        pl_agent_tool::typed::prepare_json::<
            pl_tool_search::tools::web_search::WebSearch<StandaloneSearchService>,
        >()
        .expect("static search definition")
        .definition()
        .clone()
    }
}
impl TypedTool for ThreadWebSearchTool {
    const NAME: &'static str =
        <pl_tool_search::tools::web_search::WebSearch<StandaloneSearchService> as TypedTool>::NAME;
    const DESCRIPTION: &'static str = pl_tool_search::tools::web_search::DESCRIPTION;
    type Args = pl_tool_search::tools::web_search::SearchCommands;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;
    async fn execute(
        &self,
        commands: Self::Args,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        let output = self
            .tool
            .execute(
                commands,
                pl_tool_search::tools::web_search::Context {
                    request_id: format!("{}:{}", context.turn_id, context.call_id),
                    input: recent_context(&context.context),
                    cancellation: context.cancellation,
                },
            )
            .await
            .map_err(ToolError::new)?;
        text_output("pl.tool.web-search", &output.response, output.preview)
    }
}

#[derive(Debug)]
pub struct DeepSeekService {
    client: ToolsClient,
}
impl SearchService for DeepSeekService {
    type Error = ToolsError;
    fn source_limit(&self) -> usize {
        usize::from(tools::ToolsOptions::default().count)
    }
    async fn search(
        &self,
        query: String,
        cancellation: CancellationToken,
    ) -> Result<SearchResponse, ServiceFailure<ToolsError, SearchResponse>> {
        self.client
            .search(&tools::SearchRequest { query }, cancellation)
            .await
            .map(search_response)
            .map_err(|source| {
                let observed = match source.observed_response() {
                    Some(Observed::Search(response)) => Some(search_response((**response).clone())),
                    _ => None,
                };
                let cancelled = matches!(source, ToolsError::Cancelled { .. });
                ServiceFailure {
                    source,
                    observed,
                    cancelled,
                }
            })
    }
}
impl FetchService for DeepSeekService {
    type Error = ToolsError;
    async fn fetch(
        &self,
        url: String,
        cancellation: CancellationToken,
    ) -> Result<FetchResponse, ServiceFailure<ToolsError, FetchResponse>> {
        self.client
            .fetch(&tools::FetchRequest { url }, cancellation)
            .await
            .map(fetch_response)
            .map_err(|source| {
                let observed = match source.observed_response() {
                    Some(Observed::Fetch(response)) => Some(fetch_response((**response).clone())),
                    _ => None,
                };
                let cancelled = matches!(source, ToolsError::Cancelled { .. });
                ServiceFailure {
                    source,
                    observed,
                    cancelled,
                }
            })
    }
}
fn search_response(response: tools::SearchResponse) -> SearchResponse {
    SearchResponse {
        sources: response
            .sources
            .into_iter()
            .map(|source| SearchSource {
                url: source.url,
                title: source.title,
                snippet: source.snippet,
                published_at: source.published_at,
            })
            .collect(),
        raw_response: response.raw_response,
    }
}
fn fetch_response(response: tools::FetchResponse) -> FetchResponse {
    FetchResponse {
        status: response.status,
        title: response.title,
        content: response.content,
        raw_response: response.raw_response,
    }
}

#[derive(Debug)]
pub struct ThreadDeepSeekWebSearchTool {
    tool: pl_tool_search::tools::deepseek_web_search::DeepSeekWebSearch<DeepSeekService>,
}
impl ThreadDeepSeekWebSearchTool {
    pub fn new(client: ToolsClient) -> Self {
        Self {
            tool: pl_tool_search::tools::deepseek_web_search::DeepSeekWebSearch::new(
                DeepSeekService { client },
            ),
        }
    }
    pub fn declaration() -> pl_agent_tool::ToolDefinition {
        pl_agent_tool::typed::prepare_json::<
            pl_tool_search::tools::deepseek_web_search::DeepSeekWebSearch<DeepSeekService>,
        >()
        .expect("static search definition")
        .definition()
        .clone()
    }
}
impl TypedTool for ThreadDeepSeekWebSearchTool {
    const NAME: &'static str = "deepseek_web_search";
    const DESCRIPTION: &'static str = pl_tool_search::tools::deepseek_web_search::DESCRIPTION;
    type Args = pl_tool_search::tools::deepseek_web_search::Args;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;
    async fn execute(
        &self,
        args: Self::Args,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        match self.tool.execute(args, context.cancellation).await {
            Ok(output) => text_output(
                "pl.tool.deepseek-web-search",
                &output.results,
                output.preview,
            ),
            Err(pl_tool_search::tools::deepseek_web_search::SearchError::Service {
                source,
                output,
            }) => {
                let mut error = ToolError::new(source);
                if let Some(output) = output {
                    error = error.with_output(text_output(
                        "pl.tool.deepseek-web-search",
                        &output.results,
                        output.preview,
                    )?);
                }
                Err(error)
            }
            Err(error) => Err(ToolError::new(error)),
        }
    }
}
#[derive(Debug)]
pub struct ThreadDeepSeekWebFetchTool {
    tool: pl_tool_search::tools::deepseek_web_fetch::DeepSeekWebFetch<DeepSeekService>,
}
impl ThreadDeepSeekWebFetchTool {
    pub fn new(client: ToolsClient) -> Self {
        Self {
            tool: pl_tool_search::tools::deepseek_web_fetch::DeepSeekWebFetch::new(
                DeepSeekService { client },
            ),
        }
    }
    pub fn declaration() -> pl_agent_tool::ToolDefinition {
        pl_agent_tool::typed::prepare_json::<
            pl_tool_search::tools::deepseek_web_fetch::DeepSeekWebFetch<DeepSeekService>,
        >()
        .expect("static fetch definition")
        .definition()
        .clone()
    }
}
impl TypedTool for ThreadDeepSeekWebFetchTool {
    const NAME: &'static str = "deepseek_web_fetch";
    const DESCRIPTION: &'static str = pl_tool_search::tools::deepseek_web_fetch::DESCRIPTION;
    type Args = pl_tool_search::tools::deepseek_web_fetch::Args;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;
    async fn execute(
        &self,
        args: Self::Args,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        match self.tool.execute(args, context.cancellation).await {
            Ok(output) => text_output(
                "pl.tool.deepseek-web-fetch",
                &output.response,
                output.preview,
            ),
            Err(pl_tool_search::tools::deepseek_web_fetch::FetchError::Service {
                source,
                output,
            }) => {
                let mut error = ToolError::new(source);
                if let Some(output) = output {
                    error = error.with_output(text_output(
                        "pl.tool.deepseek-web-fetch",
                        &output.response,
                        output.preview,
                    )?);
                }
                Err(error)
            }
            Err(error) => Err(ToolError::new(error)),
        }
    }
}
fn text_output(
    format: &str,
    response: &impl serde::Serialize,
    text: String,
) -> Result<ToolOutput, ToolError> {
    Ok(ToolOutput::new(
        OpaquePayload::new(
            format,
            1,
            serde_json::to_string(response).map_err(ToolError::new)?,
        )
        .map_err(ToolError::new)?,
        vec![ContextContent::Text { text: text.into() }],
    ))
}

fn recent_context(context: &ContextSnapshot) -> Option<Vec<Value>> {
    let start = context
        .records
        .iter()
        .enumerate()
        .rev()
        .filter(|(_, record)| record.source == ContextSource::User)
        .take(2)
        .last()?
        .0;
    let mut remaining = ASSISTANT_CONTEXT_CHAR_LIMIT;
    let messages = context.records[start..]
        .iter()
        .filter_map(|record| {
            let role = match record.source {
                ContextSource::User => "user",
                ContextSource::Assistant if record.tool_calls.is_empty() => "assistant",
                ContextSource::Assistant
                | ContextSource::InstructionSnapshot { .. }
                | ContextSource::Instruction
                | ContextSource::Runtime { .. }
                | ContextSource::RuntimeFact { .. }
                | ContextSource::AgentMessage { .. }
                | ContextSource::ToolResult { .. } => return None,
            };
            let mut text = record
                .content
                .iter()
                .filter_map(|part| match part {
                    ContextContent::Text { text } => Some(text.as_ref()),
                    ContextContent::Resource { .. } | ContextContent::Opaque { .. } => None,
                })
                .collect::<Vec<_>>()
                .join("\n");
            if role == "assistant" {
                text = text.chars().take(remaining).collect();
                remaining = remaining.saturating_sub(text.chars().count());
            }
            if text.is_empty() {
                None
            } else {
                Some(serde_json::json!({"role":role,"content":text}))
            }
        })
        .collect::<Vec<_>>();
    (!messages.is_empty()).then_some(messages)
}

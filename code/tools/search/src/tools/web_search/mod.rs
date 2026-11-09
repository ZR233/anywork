//! Standalone search orchestration over a host-selected search service.
mod commands;
pub use commands::*;
use pl_agent_tool::typed::TypedTool;
use serde::{Deserialize, Serialize};
use std::{error::Error, future::Future};
use tokio_util::sync::CancellationToken;

pub const DESCRIPTION: &str = "Search or open web pages, find text in pages, capture PDF pages, and query finance, weather, sports, or time data. Pass commands as arrays of objects, for example {\"search_query\":[{\"q\":\"latest Flutter release\"}]} or {\"open\":[{\"ref_id\":\"turn0search0\"}]}. Multiple commands may be combined in one call.";

#[derive(Debug)]
pub struct Context {
    pub request_id: String,
    /// Only the user/assistant text selected by the host is supplied here.
    pub input: Option<Vec<serde_json::Value>>,
    pub cancellation: CancellationToken,
}

#[derive(Debug)]
pub struct Request {
    pub id: String,
    pub input: Option<Vec<serde_json::Value>>,
    pub commands: SearchCommands,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
pub struct Response {
    #[serde(default)]
    pub encrypted_output: Option<String>,
    pub output: String,
    #[serde(default)]
    pub results: Option<Vec<serde_json::Value>>,
}

#[derive(Debug)]
pub struct Output {
    pub response: Response,
    pub preview: String,
}

pub trait SearchService: Send + Sync + 'static {
    type Error: Error + Send + Sync + 'static;
    fn search(
        &self,
        request: Request,
    ) -> impl Future<Output = Result<Response, Self::Error>> + Send;
}

#[derive(Debug, thiserror::Error)]
pub enum SearchError<E: Error + 'static> {
    #[error("search cancelled")]
    Cancelled,
    #[error("search service failed: {0}")]
    Service(#[source] E),
}

#[derive(Debug)]
pub struct WebSearch<S> {
    service: S,
}

impl<S: SearchService> WebSearch<S> {
    pub fn new(service: S) -> Self {
        Self { service }
    }
}

impl<S: SearchService> TypedTool for WebSearch<S> {
    const NAME: &'static str = "web_search";
    const DESCRIPTION: &'static str = DESCRIPTION;
    type Args = SearchCommands;
    type Context = Context;
    type Output = Output;
    type Error = SearchError<S::Error>;

    async fn execute(
        &self,
        commands: SearchCommands,
        context: Context,
    ) -> Result<Output, Self::Error> {
        if context.cancellation.is_cancelled() {
            return Err(SearchError::Cancelled);
        }
        let response = self
            .service
            .search(Request {
                id: context.request_id,
                input: context.input,
                commands,
            })
            .await
            .map_err(SearchError::Service)?;
        let bounded = pl_output::bounded_text(&response.output, 12 * 1024, 0);
        let preview = if bounded.truncated {
            format!(
                "{}\n[Search preview omitted {} bytes; full result retained in history.]",
                bounded.text, bounded.bytes_omitted
            )
        } else {
            bounded.text
        };
        Ok(Output { response, preview })
    }
}

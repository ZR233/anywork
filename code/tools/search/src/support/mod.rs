//! Search response observations shared by standalone search and fetch tools.
use serde::{Deserialize, Serialize};
use std::{error::Error, future::Future};
use tokio_util::sync::CancellationToken;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchSource {
    pub url: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub snippet: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub published_at: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchResponse {
    pub sources: Vec<SearchSource>,
    pub raw_response: serde_json::Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FetchResponse {
    pub status: u16,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    pub content: String,
    pub raw_response: serde_json::Value,
}

/// A provider failure keeps its original source and any fully observed response.
#[derive(Debug, thiserror::Error)]
#[error("{source}")]
pub struct ServiceFailure<E: Error + 'static, R: std::fmt::Debug> {
    #[source]
    pub source: E,
    pub observed: Option<R>,
    pub cancelled: bool,
}

pub trait SearchService: Send + Sync + 'static {
    type Error: Error + Send + Sync + 'static;
    /// The frozen service's result count, used for the merged projection.
    fn source_limit(&self) -> usize;
    fn search(
        &self,
        query: String,
        cancellation: CancellationToken,
    ) -> impl Future<Output = Result<SearchResponse, ServiceFailure<Self::Error, SearchResponse>>> + Send;
}

pub trait FetchService: Send + Sync + 'static {
    type Error: Error + Send + Sync + 'static;
    fn fetch(
        &self,
        url: String,
        cancellation: CancellationToken,
    ) -> impl Future<Output = Result<FetchResponse, ServiceFailure<Self::Error, FetchResponse>>> + Send;
}

pub fn bounded_preview(text: &str, kind: &str) -> String {
    let bounded = pl_output::bounded_text(text, 12_000, 0);
    if !bounded.truncated {
        return bounded.text;
    }
    let note = if kind == "fetch" {
        "\n(Content truncated. Fetch a more specific URL or section for the full text.)"
    } else {
        ""
    };
    format!(
        "{}{note}\n[DeepSeek {kind} preview omitted {} bytes; full result retained in history.]",
        bounded.text, bounded.bytes_omitted
    )
}

//! Host-owned `/alpha/search` request and configuration adaptation.

use pl_protocol::search::{WebSearchConfig, WebSearchMode};
use pl_protocol::{WebSearchContextSize, WebSearchFilters, WebSearchUserLocation};
use pl_tool_search::tools::web_search::SearchCommands;
use serde::{Deserialize, Serialize};

/// 独立 `/alpha/search` 请求。
#[derive(Debug, Clone, Serialize, PartialEq)]
pub(super) struct SearchRequest {
    pub(super) id: String,
    pub(super) model: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) input: Option<Vec<serde_json::Value>>,
    pub(super) commands: SearchCommands,
    pub(super) settings: SearchSettings,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub(super) max_output_tokens: Option<u64>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SearchSettings {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    user_location: Option<WebSearchUserLocation>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    search_context_size: Option<WebSearchContextSize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    filters: Option<WebSearchFilters>,
    allowed_callers: Vec<SearchAllowedCaller>,
    external_web_access: ExternalWebAccess,
}

impl SearchSettings {
    pub fn from_config(config: &WebSearchConfig) -> Self {
        Self {
            user_location: config
                .location
                .as_ref()
                .filter(|location| !location.is_empty())
                .map(Into::into),
            search_context_size: config.context_size,
            filters: (!config.allowed_domains.is_empty()).then(|| WebSearchFilters {
                allowed_domains: config.allowed_domains.clone(),
            }),
            allowed_callers: vec![SearchAllowedCaller::Direct],
            external_web_access: ExternalWebAccess::from(config.mode),
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
enum SearchAllowedCaller {
    Direct,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(untagged)]
enum ExternalWebAccess {
    Boolean(bool),
    Mode(ExternalWebAccessMode),
}

impl From<WebSearchMode> for ExternalWebAccess {
    fn from(mode: WebSearchMode) -> Self {
        match mode {
            WebSearchMode::Disabled | WebSearchMode::Cached => Self::Boolean(false),
            WebSearchMode::Indexed => Self::Mode(ExternalWebAccessMode::Indexed),
            WebSearchMode::Live => Self::Boolean(true),
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
enum ExternalWebAccessMode {
    Indexed,
}

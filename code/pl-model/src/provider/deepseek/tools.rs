//! Native DeepSeek access：官方 Search & Fetch 工具接口。
//!
//! 该模块是 `pl-model` 暴露给上层的公开工具域：调用方只消费 [`ToolsClient`]、
//! [`ToolsOptions`]、[`SearchRequest`]、[`SearchSource`]、[`SearchResponse`]、
//! [`FetchRequest`]、[`FetchResponse`]、[`Observed`] 与 [`ToolsError`]。请求与响应都是
//! DeepSeek provider 私有的 wire 细节，不进入会话 transport，也不携带任何会话历史。
//!
//! 契约要点：
//! - 端点由 `provider.base_url` 自身地址组装：去掉尾部 `/`、去掉一个尾部 `/v1`，保留
//!   自定义 reverse-proxy 的 path 前缀，再分别追加 `/v1/tools/search` 与 `/v1/tools/fetch`。
//!   已指向 `/anthropic` 或 `/anthropic/v1` 的地址明确失败，不静默改写。
//! - 鉴权只使用所选 provider 的 `Authorization: Bearer`（附带 JSON headers）；显式禁用
//!   重定向与 reqwest 默认 protocol 重试。
//! - 超时覆盖整个请求（等待 headers 与读取 body）；取消同样覆盖这两段读取。
//! - search 只发送 `query` / `count` / `need_content = false`；fetch 只发送 `url`。空
//!   query、超长 query、非法 URL 与非法 `count` 在发出前拒绝。
//! - search 严格消费 `results[]` 的 `url` / `title` / `snippet` / `date`；fetch 要求
//!   `content` 为字符串。已完整取得的响应正文通过 [`ToolsError::observed_response`] 保留：
//!   合法 JSON 保留解析值，非 JSON（含畸形 JSON 与非 UTF-8 字节）按 base64 约定无损保留
//!   原始字节。错误信息与 `Debug` 输出都不包含凭据。

use std::collections::HashSet;
use std::time::Duration;

use base64::{Engine, engine::general_purpose::STANDARD};
use reqwest::header::{ACCEPT, AUTHORIZATION, CONTENT_TYPE, HeaderMap, HeaderName, HeaderValue};
use serde::{Deserialize, Serialize};

use crate::provider::ProviderEndpoint;

/// 与运行时共享的精确取消类型重导出。
pub use tokio_util::sync::CancellationToken;

const DEFAULT_COUNT: u8 = 10;
const DEFAULT_TIMEOUT: Duration = Duration::from_secs(60);
const MAX_QUERY_CHARS: usize = 128;
const MAX_FETCH_URL_CHARS: usize = 8192;
const MAX_COUNT: u8 = 50;
const MAX_ERROR_MESSAGE_CHARS: usize = 512;
const RAW_BODY_ENCODING: &str = "base64";
const SEARCH_PATH: &str = "/v1/tools/search";
const FETCH_PATH: &str = "/v1/tools/fetch";
const RESERVED_HEADERS: [&str; 4] = ["authorization", "content-type", "accept", "host"];

/// 官方 Search & Fetch 工具接口的请求参数。
///
/// `count` 默认 10（与官方默认一致），整体超时默认 60 秒；这是本模块冻结进客户端的部署值。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ToolsOptions {
    /// search 结果上限，必须在 `1..=50`。
    pub count: u8,
    /// 覆盖整个请求的超时，必须为正。
    pub timeout: Duration,
}

impl Default for ToolsOptions {
    fn default() -> Self {
        Self {
            count: DEFAULT_COUNT,
            timeout: DEFAULT_TIMEOUT,
        }
    }
}

/// 一次独立搜索的输入；只有 `query` 会进入请求。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchRequest {
    /// 用户查询文本。
    pub query: String,
}

/// 归一化后的搜索来源。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchSource {
    /// 结果页 URL；同一 URL 只保留首次出现。
    pub url: String,
    /// 结果标题，缺省为未知。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    /// 结果摘要片段。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub snippet: Option<String>,
    /// 页面发布时间（`date`），缺省为未知。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub published_at: Option<String>,
}

/// 归一化的独立搜索结果；同时保留原始响应事实。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchResponse {
    /// 按 URL 首现去重后的来源。
    pub sources: Vec<SearchSource>,
    /// 供应商原生响应正文。合法 JSON 原样保留；正文已完整收到但不是合法 JSON（非 2xx 文本、
    /// 畸形 JSON、非 UTF-8 字节）时改为 `{"encoding":"base64","data":...}`，逐字节无损保留原始
    /// 正文。
    pub raw_response: serde_json::Value,
}

/// 一次独立抓取的输入；只有 `url` 会进入请求。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FetchRequest {
    /// 要抓取的页面 URL。
    pub url: String,
}

/// 归一化的独立抓取结果；同时保留原始响应事实。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FetchResponse {
    /// 成功响应的真实 HTTP 状态码。
    pub status: u16,
    /// 页面标题，空串或缺失为未知。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    /// 页面正文；必须是字符串。
    pub content: String,
    /// 供应商原生响应正文，留存规则与 [`SearchResponse::raw_response`] 相同。
    pub raw_response: serde_json::Value,
}

/// 已完整收到的 search 或 fetch 响应事实。
#[derive(Debug, Clone, PartialEq)]
pub enum Observed {
    Search(Box<SearchResponse>),
    Fetch(Box<FetchResponse>),
}

/// 独立 Search & Fetch 的类型化错误；已观察到的响应通过 [`ToolsError::observed_response`] 保留。
#[derive(Debug, thiserror::Error)]
pub enum ToolsError {
    /// 所选 provider 没有可用凭据。
    #[error("deepseek tools require a non-empty provider credential")]
    MissingCredential,
    /// 空 query 在发出前被拒绝。
    #[error("deepseek tools require a non-empty query")]
    EmptyQuery,
    /// query 超长，在发出前被拒绝。
    #[error("invalid deepseek tools query: {message}")]
    InvalidQuery { message: String },
    /// fetch URL 非法，在发出前被拒绝。
    #[error("invalid deepseek tools url: {message}")]
    InvalidUrl { message: String },
    /// 配置或参数在发出前被拒绝。
    #[error("invalid deepseek tools configuration: {message}")]
    Config { message: String },
    /// 构建 HTTP 客户端失败。
    #[error("failed to build deepseek tools client: {source}")]
    Client {
        #[source]
        source: reqwest::Error,
    },
    /// 请求在传输阶段失败。
    #[error("deepseek tools request failed: {source}")]
    Transport {
        #[source]
        source: reqwest::Error,
        observed: Option<Box<Observed>>,
    },
    /// 请求整体超时。
    #[error("deepseek tools timed out after {seconds} seconds")]
    Timeout {
        seconds: u64,
        #[source]
        source: reqwest::Error,
        observed: Option<Box<Observed>>,
    },
    /// 请求被调用方取消。
    #[error("deepseek tools request was cancelled")]
    Cancelled { observed: Option<Box<Observed>> },
    /// HTTP 状态非 2xx；`message` 优先取 `error.message`（按 `chars()` 截断到 512），
    /// 否则回退标准原因短语；完整正文经 `observed` 保留。
    #[error("deepseek tools returned HTTP {status}: {message}")]
    HttpStatus {
        status: u16,
        message: String,
        observed: Option<Box<Observed>>,
    },
    /// 2xx 响应体不是合法 JSON；完整正文经 `observed` 无损保留。
    #[error("deepseek tools returned an unreadable response: {source}")]
    InvalidResponse {
        #[source]
        source: serde_json::Error,
        observed: Option<Box<Observed>>,
    },
    /// search 响应不是包含 `results` 数组的对象，或结果项形状非法。
    #[error("deepseek tools search results are malformed")]
    MalformedResults { observed: Box<Observed> },
    /// fetch 响应缺少字符串 `content`。
    #[error("deepseek tools fetch response is missing content")]
    MissingContent { observed: Box<Observed> },
}

impl ToolsError {
    /// 返回本次调用已取得的原始响应，未取得时为 `None`。
    ///
    /// 完整收到响应正文时一定返回 `Some`：合法 JSON 保留解析后的 `raw_response`，非 JSON 正文
    /// （畸形 JSON、非 UTF-8 字节、非 2xx 文本）以 base64 约定无损保留原始字节。超时或取消等
    /// 尚未取到完整正文的路径返回 `None`。
    pub fn observed_response(&self) -> Option<&Observed> {
        match self {
            Self::Transport { observed, .. }
            | Self::Timeout { observed, .. }
            | Self::Cancelled { observed }
            | Self::HttpStatus { observed, .. }
            | Self::InvalidResponse { observed, .. } => observed.as_deref(),
            Self::MalformedResults { observed } | Self::MissingContent { observed } => {
                Some(observed.as_ref())
            }
            Self::MissingCredential
            | Self::EmptyQuery
            | Self::InvalidQuery { .. }
            | Self::InvalidUrl { .. }
            | Self::Config { .. }
            | Self::Client { .. } => None,
        }
    }
}

/// 只负责 DeepSeek 官方 Search & Fetch 工具接口的 HTTP 客户端。
///
/// 客户端冻结一次解析出的端点、参数与凭据；凭据只作为 sensitive header 保存在内部，
/// 不进入 `Debug` 或错误信息。
#[derive(Clone)]
pub struct ToolsClient {
    client: reqwest::Client,
    search_endpoint: String,
    fetch_endpoint: String,
    options: ToolsOptions,
}

impl std::fmt::Debug for ToolsClient {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ToolsClient")
            .field("search_endpoint", &self.search_endpoint)
            .field("fetch_endpoint", &self.fetch_endpoint)
            .field("options", &self.options)
            .finish_non_exhaustive()
    }
}

impl ToolsClient {
    /// 从所选 provider endpoint 与参数构造官方工具客户端。
    ///
    /// # Errors
    /// 缺少非空凭据返回 [`ToolsError::MissingCredential`]；非法端点、`count` 或超时返回
    /// [`ToolsError::Config`]；构建 HTTP 客户端失败返回 [`ToolsError::Client`]。这些失败都
    /// 发生在发出任何请求之前。
    pub fn new(endpoint: &ProviderEndpoint, options: ToolsOptions) -> Result<Self, ToolsError> {
        let credential = endpoint
            .bearer_token
            .as_deref()
            .map(str::trim)
            .filter(|token| !token.is_empty())
            .ok_or(ToolsError::MissingCredential)?;
        if !(1..=MAX_COUNT).contains(&options.count) {
            return Err(ToolsError::Config {
                message: "count must be between 1 and 50".to_string(),
            });
        }
        if options.timeout.is_zero() {
            return Err(ToolsError::Config {
                message: "timeout must be positive".to_string(),
            });
        }

        let (search_endpoint, fetch_endpoint) = tools_endpoints(&endpoint.base_url)?;
        let headers = request_headers(endpoint, credential)?;
        let client = reqwest::Client::builder()
            .timeout(options.timeout)
            .redirect(reqwest::redirect::Policy::none())
            .retry(reqwest::retry::never())
            .default_headers(headers)
            .build()
            .map_err(|source| ToolsError::Client { source })?;

        Ok(Self {
            client,
            search_endpoint,
            fetch_endpoint,
            options,
        })
    }

    /// 返回本次 search 实际使用的端点，便于上层无凭据地诊断。
    pub fn search_endpoint(&self) -> &str {
        &self.search_endpoint
    }

    /// 返回本次 fetch 实际使用的端点，便于上层无凭据地诊断。
    pub fn fetch_endpoint(&self) -> &str {
        &self.fetch_endpoint
    }

    /// 执行一次官方 search。
    ///
    /// # Errors
    /// 空 query 返回 [`ToolsError::EmptyQuery`]；超长 query 返回 [`ToolsError::InvalidQuery`]；
    /// 其余失败返回类型化的 [`ToolsError`]，并在取得响应时保留已观察事实。
    pub async fn search(
        &self,
        request: &SearchRequest,
        cancellation: CancellationToken,
    ) -> Result<SearchResponse, ToolsError> {
        let query = validate_query(&request.query)?;
        let body = serde_json::json!({
            "query": query,
            "count": self.options.count,
            "need_content": false,
        });
        let (_, value) = self
            .dispatch(&self.search_endpoint, &body, CallKind::Search, cancellation)
            .await?;
        normalize_search(value)
    }

    /// 执行一次官方 fetch。
    ///
    /// # Errors
    /// 非法 URL 返回 [`ToolsError::InvalidUrl`]；其余失败返回类型化的 [`ToolsError`]，
    /// 并在取得响应时保留已观察事实。
    pub async fn fetch(
        &self,
        request: &FetchRequest,
        cancellation: CancellationToken,
    ) -> Result<FetchResponse, ToolsError> {
        let url = validate_fetch_url(&request.url)?;
        let body = serde_json::json!({ "url": url });
        let (status, value) = self
            .dispatch(&self.fetch_endpoint, &body, CallKind::Fetch, cancellation)
            .await?;
        normalize_fetch(status, value)
    }

    async fn dispatch(
        &self,
        url: &str,
        body: &serde_json::Value,
        kind: CallKind,
        cancellation: CancellationToken,
    ) -> Result<(u16, serde_json::Value), ToolsError> {
        let sending = self.client.post(url).json(body).send();
        let response = tokio::select! {
            biased;
            () = cancellation.cancelled() => {
                return Err(ToolsError::Cancelled { observed: None });
            }
            result = sending => {
                result.map_err(|source| transport_error(source, self.options.timeout))?
            }
        };

        let status = response.status();
        let reading = response.bytes();
        let bytes = tokio::select! {
            biased;
            () = cancellation.cancelled() => {
                return Err(ToolsError::Cancelled { observed: None });
            }
            result = reading => {
                result.map_err(|source| transport_error(source, self.options.timeout))?
            }
        };

        let status_code = status.as_u16();
        match serde_json::from_slice::<serde_json::Value>(&bytes) {
            Ok(value) if status.is_success() => Ok((status_code, value)),
            Ok(value) => Err(ToolsError::HttpStatus {
                status: status_code,
                message: http_error_message(status_code, Some(&value)),
                observed: Some(Box::new(observed_payload(
                    kind,
                    status_code,
                    Some(value),
                    &bytes,
                ))),
            }),
            Err(source) if status.is_success() => Err(ToolsError::InvalidResponse {
                source,
                observed: Some(Box::new(observed_payload(kind, status_code, None, &bytes))),
            }),
            Err(_) => Err(ToolsError::HttpStatus {
                status: status_code,
                message: http_error_message(status_code, None),
                observed: Some(Box::new(observed_payload(kind, status_code, None, &bytes))),
            }),
        }
    }
}

#[derive(Clone, Copy)]
enum CallKind {
    Search,
    Fetch,
}

fn validate_query(query: &str) -> Result<&str, ToolsError> {
    let query = query.trim();
    if query.is_empty() {
        return Err(ToolsError::EmptyQuery);
    }
    if query.chars().count() > MAX_QUERY_CHARS {
        return Err(ToolsError::InvalidQuery {
            message: "query 超过 128 字符".to_string(),
        });
    }
    Ok(query)
}

fn validate_fetch_url(url: &str) -> Result<&str, ToolsError> {
    let url = url.trim();
    if url.is_empty() {
        return Err(ToolsError::InvalidUrl {
            message: "fetch url must not be empty".to_string(),
        });
    }
    if url.chars().count() > MAX_FETCH_URL_CHARS {
        return Err(ToolsError::InvalidUrl {
            message: "fetch url exceeds 8192 characters".to_string(),
        });
    }
    let parsed = reqwest::Url::parse(url).map_err(|error| ToolsError::InvalidUrl {
        // ParseError 只描述失败类别，不含输入原文，因此不会回显 userinfo。
        message: format!("invalid fetch url: {error}"),
    })?;
    // 先拒绝 userinfo，避免后续回显 URL 的分支把凭据写进 Display。
    if !parsed.username().is_empty() || parsed.password().is_some() {
        return Err(ToolsError::InvalidUrl {
            message: "fetch url must not contain credentials".to_string(),
        });
    }
    if !matches!(parsed.scheme(), "http" | "https") {
        return Err(ToolsError::InvalidUrl {
            message: format!("fetch url must use http or https: {url}"),
        });
    }
    if parsed.host_str().is_none() {
        return Err(ToolsError::InvalidUrl {
            message: "fetch url must contain a host".to_string(),
        });
    }
    Ok(url)
}

fn transport_error(source: reqwest::Error, timeout: Duration) -> ToolsError {
    if source.is_timeout() {
        ToolsError::Timeout {
            seconds: timeout.as_secs(),
            source,
            observed: None,
        }
    } else {
        ToolsError::Transport {
            source,
            observed: None,
        }
    }
}

/// 用 provider 的 base_url 自身地址组装官方工具端点。
///
/// 去掉尾部 `/` 与一个尾部 `/v1`，保留自定义 reverse-proxy 的 path 前缀，再分别追加
/// `/v1/tools/search` 与 `/v1/tools/fetch`。已指向 `/anthropic` 或 `/anthropic/v1` 的地址
/// 明确失败。只接受无 userinfo / query / fragment 的 http(s) 地址，不替换 host，也不回退到
/// 官方域名。
fn tools_endpoints(base_url: &str) -> Result<(String, String), ToolsError> {
    let trimmed = base_url.trim();
    if trimmed.is_empty() {
        return Err(ToolsError::Config {
            message: "deepseek tools base url must not be empty".to_string(),
        });
    }
    let mut url = reqwest::Url::parse(trimmed).map_err(|error| ToolsError::Config {
        // ParseError 只描述失败类别，不含输入原文，因此不会回显 userinfo。
        message: format!("invalid deepseek tools base url: {error}"),
    })?;
    // 先拒绝 userinfo，避免后续回显 base url 的分支把凭据写进 Display。
    if !url.username().is_empty() || url.password().is_some() {
        return Err(ToolsError::Config {
            message: "deepseek tools base url must not contain credentials".to_string(),
        });
    }
    if !matches!(url.scheme(), "http" | "https") {
        return Err(ToolsError::Config {
            message: format!("deepseek tools base url must use http or https: {trimmed}"),
        });
    }
    if url.query().is_some() || url.fragment().is_some() {
        return Err(ToolsError::Config {
            message: "deepseek tools base url must not contain a query or fragment".to_string(),
        });
    }
    if url.host_str().is_none() {
        return Err(ToolsError::Config {
            message: "deepseek tools base url must contain a host".to_string(),
        });
    }

    let path = url.path().trim_end_matches('/');
    if path.ends_with("/anthropic") || path.ends_with("/anthropic/v1") {
        return Err(ToolsError::Config {
            message: "deepseek Anthropic-compatible endpoint does not host the official tools API; point base_url at the API root (for example https://api.deepseek.com)".to_string(),
        });
    }
    let root = path.strip_suffix("/v1").unwrap_or(path);
    let mut search = url.clone();
    search.set_path(&format!("{root}{SEARCH_PATH}"));
    url.set_path(&format!("{root}{FETCH_PATH}"));
    Ok((search.to_string(), url.to_string()))
}

fn request_headers(endpoint: &ProviderEndpoint, credential: &str) -> Result<HeaderMap, ToolsError> {
    let mut headers = HeaderMap::new();
    for (name, value) in endpoint.http_headers.iter().flatten() {
        if RESERVED_HEADERS
            .iter()
            .any(|reserved| name.eq_ignore_ascii_case(reserved))
        {
            continue;
        }
        let header_name =
            HeaderName::from_bytes(name.as_bytes()).map_err(|error| ToolsError::Config {
                message: format!("invalid provider header name `{name}`: {error}"),
            })?;
        let header_value = HeaderValue::from_str(value).map_err(|error| ToolsError::Config {
            message: format!("invalid provider header value for `{name}`: {error}"),
        })?;
        headers.insert(header_name, header_value);
    }

    let mut authorization =
        HeaderValue::from_str(&format!("Bearer {credential}")).map_err(|_| ToolsError::Config {
            message: "deepseek tools credential is not a valid header value".to_string(),
        })?;
    authorization.set_sensitive(true);
    headers.insert(AUTHORIZATION, authorization);
    headers.insert(CONTENT_TYPE, HeaderValue::from_static("application/json"));
    headers.insert(ACCEPT, HeaderValue::from_static("application/json"));
    Ok(headers)
}

fn normalize_search(value: serde_json::Value) -> Result<SearchResponse, ToolsError> {
    let sources = match parse_sources(&value) {
        Ok(sources) => sources,
        Err(()) => {
            return Err(ToolsError::MalformedResults {
                observed: Box::new(search_observed(value, Vec::new())),
            });
        }
    };
    Ok(SearchResponse {
        sources,
        raw_response: value,
    })
}

fn parse_sources(value: &serde_json::Value) -> Result<Vec<SearchSource>, ()> {
    let object = value.as_object().ok_or(())?;
    let results = object
        .get("results")
        .and_then(serde_json::Value::as_array)
        .ok_or(())?;
    let mut sources = Vec::new();
    let mut seen = HashSet::new();
    for item in results {
        let object = item.as_object().ok_or(())?;
        let url = match object.get("url") {
            Some(serde_json::Value::String(url)) if !url.is_empty() => url.clone(),
            _ => return Err(()),
        };
        let title = optional_string(object.get("title"))?;
        let snippet = optional_string(object.get("snippet"))?;
        let published_at = optional_date(object.get("date"))?;
        if seen.insert(url.clone()) {
            sources.push(SearchSource {
                url,
                title,
                snippet,
                published_at,
            });
        }
    }
    Ok(sources)
}

fn optional_string(value: Option<&serde_json::Value>) -> Result<Option<String>, ()> {
    match value {
        None => Ok(None),
        Some(serde_json::Value::String(text)) if text.is_empty() => Ok(None),
        Some(serde_json::Value::String(text)) => Ok(Some(text.clone())),
        Some(_) => Err(()),
    }
}

fn optional_date(value: Option<&serde_json::Value>) -> Result<Option<String>, ()> {
    match value {
        None | Some(serde_json::Value::Null) => Ok(None),
        Some(serde_json::Value::String(text)) if text.is_empty() => Ok(None),
        Some(serde_json::Value::String(text)) => Ok(Some(text.clone())),
        Some(_) => Err(()),
    }
}

fn normalize_fetch(status: u16, value: serde_json::Value) -> Result<FetchResponse, ToolsError> {
    let Some(serde_json::Value::String(content)) = value.get("content") else {
        return Err(ToolsError::MissingContent {
            observed: Box::new(fetch_observed(status, value, None, String::new())),
        });
    };
    let content = content.clone();
    let title = match value.get("title") {
        Some(serde_json::Value::String(title)) if !title.is_empty() => Some(title.clone()),
        _ => None,
    };
    Ok(FetchResponse {
        status,
        title,
        content,
        raw_response: value,
    })
}

fn observed_payload(
    kind: CallKind,
    status: u16,
    parsed: Option<serde_json::Value>,
    bytes: &[u8],
) -> Observed {
    let raw_response = parsed.unwrap_or_else(|| raw_body_value(bytes));
    match kind {
        CallKind::Search => search_observed(raw_response, Vec::new()),
        CallKind::Fetch => fetch_observed(status, raw_response, None, String::new()),
    }
}

fn search_observed(raw_response: serde_json::Value, sources: Vec<SearchSource>) -> Observed {
    Observed::Search(Box::new(SearchResponse {
        sources,
        raw_response,
    }))
}

fn fetch_observed(
    status: u16,
    raw_response: serde_json::Value,
    title: Option<String>,
    content: String,
) -> Observed {
    Observed::Fetch(Box::new(FetchResponse {
        status,
        title,
        content,
        raw_response,
    }))
}

fn raw_body_value(bytes: &[u8]) -> serde_json::Value {
    serde_json::json!({
        "encoding": RAW_BODY_ENCODING,
        "data": STANDARD.encode(bytes),
    })
}

fn http_error_message(status: u16, parsed: Option<&serde_json::Value>) -> String {
    if let Some(message) = parsed
        .and_then(|value| value.get("error"))
        .and_then(|error| error.get("message"))
        .and_then(serde_json::Value::as_str)
    {
        return message.chars().take(MAX_ERROR_MESSAGE_CHARS).collect();
    }
    match status {
        301 => "Moved Permanently",
        302 => "Found",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        429 => "Too Many Requests",
        500 => "Internal Server Error",
        _ => "",
    }
    .to_string()
}

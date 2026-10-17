mod binding;
mod client;
mod hosted_options;
mod plan;
mod thread;

pub use binding::{SearchBindingError, ThreadSearchBinding};
pub use client::{SearchEndpoint, WebSearchClient};
pub use plan::{
    WebSearchAvailability, WebSearchBackend, WebSearchDeepSeekOptions, WebSearchPath,
    WebSearchPlan, WebSearchPlans, WebSearchResolution, WebSearchService, WebSearchServices,
    plan_deepseek_web_search, plan_openai_web_search, plan_web_search_services, plan_web_searches,
};
pub use thread::{
    ThreadDeepSeekWebFetchTool, ThreadDeepSeekWebSearchTool, ThreadSearchOptions,
    ThreadWebSearchTool,
};

pub const TOOL_WEB_SEARCH: &str = "web_search";
pub const TOOL_DEEPSEEK_WEB_SEARCH: &str = "deepseek_web_search";
pub const TOOL_DEEPSEEK_WEB_FETCH: &str = "deepseek_web_fetch";
pub const DEEPSEEK_SEARCH_MAX_QUERIES: usize = 4;
const ASSISTANT_CONTEXT_CHAR_LIMIT: usize = 4_000;
const DEEPSEEK_SEARCH_CONTEXT_BYTE_LIMIT: usize = 12_000;
const WEB_SEARCH_DESCRIPTION: &str = "Search or open web pages, find text in pages, capture PDF pages, and query finance, weather, sports, or time data. Pass commands as arrays of objects, for example {\"search_query\":[{\"q\":\"latest Flutter release\"}]} or {\"open\":[{\"ref_id\":\"turn0search0\"}]}. Multiple commands may be combined in one call.";
const DEEPSEEK_WEB_SEARCH_DESCRIPTION: &str = "Search the web with one to four merged queries and return ranked sources, executed by the DeepSeek search service; every request is billed. Prefer other configured web search tools and use this only when other web search is not configured, is unavailable, or has actually failed. Call discover_tools first to discover available MCP tools before choosing this fallback.";
const DEEPSEEK_WEB_FETCH_DESCRIPTION: &str = "Fetch the content of a specific HTTP(S) URL as Markdown, executed by the DeepSeek Fetch service; every call is billed. Prefer other fetch or page-extraction tools and use this only when none is available or it has failed.";

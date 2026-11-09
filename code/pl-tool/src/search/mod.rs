mod binding;
mod client;
mod hosted_options;
mod plan;
mod thread;

pub use binding::{SearchBindingError, ThreadSearchBinding};
pub use client::{SearchEndpoint, WebSearchClient, WebSearchError};
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
pub const DEEPSEEK_SEARCH_MAX_QUERIES: usize =
    pl_tool_search::tools::deepseek_web_search::MAX_QUERIES;

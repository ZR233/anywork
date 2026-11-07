//! Web Search 计划投影为独立的工具执行器与模型持有的 hosted 能力。
//!
//! 装配过程中只消费规划结果与共享配置快照；hosted 条目永不在本层获取 core 执行器。
//! OpenAI 与 DeepSeek 两条规划彼此独立，任一可用都只追加自己的工具，不排斥其他工具。

use crate::binding::{ToolCallPolicy, prepare_native_tool, prepare_registration};
use pl_core::tool::opaque::Registration;
use pl_model::protocol::StandaloneWebSearchDialect;
use pl_model::protocol::deepseek::tools::{ToolsClient, ToolsError, ToolsOptions};
use pl_model::runtime::HostedTool;
use pl_protocol::HostedWebSearchDialect;
use pl_protocol::search::WebSearchConfig;

use super::client::{SearchEndpoint, WebSearchClient};
use super::hosted_options;
use super::plan::{WebSearchPath, WebSearchPlans};
use super::thread::{
    ThreadDeepSeekWebFetchTool, ThreadDeepSeekWebSearchTool, ThreadSearchOptions,
    ThreadWebSearchTool,
};

/// 公共搜索装配错误；产品调用方负责映射到自身错误域。
///
/// 该类型刻意不引用任何 Studio 专属错误，以便 Studio 与 mai-team 等调用方共用。
#[derive(Debug, thiserror::Error)]
pub enum SearchBindingError {
    #[error("standalone search is missing its resolved backend")]
    MissingBackend,
    #[error(transparent)]
    Config(#[from] pl_protocol::PureError),
    #[error(transparent)]
    Binding(#[from] crate::binding::BindingError),
    #[error(transparent)]
    Tools(#[from] ToolsError),
}

/// Frozen search assembly; hosted entries never acquire core executors.
#[derive(Debug)]
pub struct ThreadSearchBinding {
    pub tools: Vec<Registration>,
    pub hosted: Vec<HostedTool>,
}

impl WebSearchPlans {
    /// Returns only provider-executed declarations without constructing local tool resources.
    pub fn hosted_tools(&self, config: &WebSearchConfig) -> pl_protocol::Result<Vec<HostedTool>> {
        let mut hosted = Vec::new();
        for plan in self.plans() {
            if plan.resolution.path != Some(WebSearchPath::Hosted) {
                continue;
            }
            match plan.hosted_dialect {
                Some(HostedWebSearchDialect::OpenAiResponses) => {
                    let options = hosted_options::openai_options(config).ok_or_else(|| {
                        pl_protocol::PureError::ConfigError(
                            "hosted search requires an enabled effective mode".into(),
                        )
                    })?;
                    hosted.push(HostedTool::WebSearch(options));
                }
                // Only OpenAI Responses hosted is planned; DeepSeek search is native standalone.
                // Any other dialect on a hosted path is an assembly bug, not a silent skip.
                Some(HostedWebSearchDialect::DeepSeekResponses) | None => {
                    return Err(pl_protocol::PureError::ConfigError(
                        "planned hosted web search has an unsupported dialect".into(),
                    ));
                }
            }
        }
        Ok(hosted)
    }

    /// Projects every available provider capability using the same configuration snapshot as the route.
    ///
    /// # Errors
    /// Returns missing backend, disabled hosted options, declaration or registration errors.
    pub fn build_thread(
        &self,
        config: &WebSearchConfig,
    ) -> std::result::Result<ThreadSearchBinding, SearchBindingError> {
        let mut binding = ThreadSearchBinding {
            tools: Vec::new(),
            hosted: self.hosted_tools(config)?,
        };
        for plan in self.plans() {
            if plan.resolution.path == Some(WebSearchPath::Standalone) {
                let backend = plan
                    .backend
                    .as_ref()
                    .ok_or(SearchBindingError::MissingBackend)?;
                match backend.dialect {
                    StandaloneWebSearchDialect::OpenAiSearchApi => {
                        let native = prepare_native_tool::<ThreadWebSearchTool>()
                            .map_err(crate::binding::BindingError::from)?;
                        let prepared = prepare_registration(
                            super::TOOL_WEB_SEARCH,
                            native.definition(),
                            ToolCallPolicy::DirectOnly,
                        )?;
                        let client = WebSearchClient::new(&SearchEndpoint {
                            base_url: backend.endpoint.base_url.clone(),
                            bearer_token: backend.endpoint.bearer_token.clone(),
                            http_headers: backend.endpoint.http_headers.clone(),
                        })?;
                        let model = backend.model.clone().ok_or_else(|| {
                            pl_protocol::PureError::ConfigError(
                                "openai standalone web search requires a resolved service model"
                                    .into(),
                            )
                        })?;
                        let tool = ThreadWebSearchTool::new(
                            client,
                            ThreadSearchOptions {
                                model,
                                settings: pl_protocol::search::SearchSettings::from_config(config),
                                max_output_tokens: backend.max_output_tokens,
                            },
                        );
                        binding.tools.push(
                            prepared
                                .attach(pl_agent_tool::ToolHandle::new(native.attach(tool)))
                                .with_presentation_contract(
                                    pl_core::model::ToolPresentationContract::new(
                                        "builtin.web_search@1",
                                    ),
                                ),
                        );
                    }
                    StandaloneWebSearchDialect::DeepSeekToolsApi => {
                        let search = self
                            .deepseek_options
                            .enabled
                            .then(|| {
                                let native = prepare_native_tool::<ThreadDeepSeekWebSearchTool>()?;
                                let prepared = prepare_registration(
                                    super::TOOL_DEEPSEEK_WEB_SEARCH,
                                    native.definition(),
                                    ToolCallPolicy::DirectOnly,
                                )?;
                                Ok::<_, crate::binding::BindingError>((native, prepared))
                            })
                            .transpose()?;
                        let fetch = self
                            .deepseek_options
                            .fetch_enabled
                            .then(|| {
                                let native = prepare_native_tool::<ThreadDeepSeekWebFetchTool>()?;
                                let prepared = prepare_registration(
                                    super::TOOL_DEEPSEEK_WEB_FETCH,
                                    native.definition(),
                                    ToolCallPolicy::DirectOnly,
                                )?;
                                Ok::<_, crate::binding::BindingError>((native, prepared))
                            })
                            .transpose()?;
                        let client = ToolsClient::new(&backend.endpoint, ToolsOptions::default())?;
                        if let Some((native, prepared)) = search {
                            let tool = ThreadDeepSeekWebSearchTool::new(client.clone());
                            binding.tools.push(
                                prepared
                                    .attach(pl_agent_tool::ToolHandle::new(native.attach(tool)))
                                    .with_presentation_contract(
                                        pl_core::model::ToolPresentationContract::new(
                                            "builtin.deepseek_web_search@1",
                                        ),
                                    ),
                            );
                        }
                        if let Some((native, prepared)) = fetch {
                            let tool = ThreadDeepSeekWebFetchTool::new(client);
                            binding.tools.push(
                                prepared
                                    .attach(pl_agent_tool::ToolHandle::new(native.attach(tool)))
                                    .with_presentation_contract(
                                        pl_core::model::ToolPresentationContract::new(
                                            "builtin.deepseek_web_fetch@1",
                                        ),
                                    ),
                            );
                        }
                    }
                }
            }
        }
        Ok(binding)
    }
}

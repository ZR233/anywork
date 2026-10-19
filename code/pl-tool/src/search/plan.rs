//! Account/model capability 驱动的 Web Search 规划。
//!
//! 规划分两层。`plan_web_search_services` 只按 account 服务能力与凭据解析两条互相
//! 独立的搜索服务（account、服务模型、可用性），完全与会话模型无关，Studio 的
//! settings 投影直接消费它。`plan_web_searches` 在服务结果上叠加当前模型能力检查
//! （function calling 与 Responses hosted），并把当前 account 作为 DeepSeek 候选
//! 优先项，供 Thread 消费。任一路可用都只增加自己的工具，既不排斥其他普通工具，
//! 也不排斥 MCP 目录或另一路搜索。HTTP 客户端与工具执行见 [`super::client`] 与
//! [`super::thread`]，装配见 [`super::binding`]。

use pl_model::config::{AccountConfig, AccountId, AgentModelConfig, ResolvedModelRoute};
use pl_model::protocol::{ProtocolEndpoint, StandaloneWebSearchDialect, WireApi};
use pl_protocol::HostedWebSearchDialect;
use pl_protocol::search::{WebSearchConfig, WebSearchMode};
use pl_protocol::{PureError, Result, WebSearchResolutionDescriptor};

/// 本仓库 OpenAI 独立搜索默认使用的服务模型。
const OPENAI_SEARCH_MODEL: &str = "gpt-6-sol";

/// 当前 turn 实际使用的 Web Search 路径。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WebSearchPath {
    Standalone,
    Hosted,
}

/// Web Search 规划结果的可用性。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WebSearchAvailability {
    Available,
    Disabled,
    MissingCredential,
    AccountUnsupported,
    ModelUnsupported,
}

/// 已解析且可直接创建 standalone 客户端的 backend。
#[derive(Debug, Clone)]
pub struct WebSearchBackend {
    pub account_id: AccountId,
    pub endpoint: ProtocolEndpoint,
    pub model: Option<String>,
    pub max_output_tokens: Option<u64>,
    pub dialect: StandaloneWebSearchDialect,
}

/// 产品和设置页共用的单条 Web Search 解析结果。
#[derive(Debug, Clone)]
pub struct WebSearchResolution {
    pub configured_mode: WebSearchMode,
    pub effective_mode: WebSearchMode,
    pub availability: WebSearchAvailability,
    pub path: Option<WebSearchPath>,
    pub account_id: Option<AccountId>,
    pub model_id: Option<String>,
}

impl WebSearchResolution {
    /// 生成不包含凭证的公共协议投影。
    pub fn descriptor(&self) -> WebSearchResolutionDescriptor {
        WebSearchResolutionDescriptor {
            configured_mode: mode_label(self.configured_mode).to_string(),
            effective_mode: mode_label(self.effective_mode).to_string(),
            availability: availability_label(self.availability).to_string(),
            path: self.path.map(path_label).map(str::to_string),
            account_id: self.account_id.as_ref().map(ToString::to_string),
            model_id: self.model_id.clone(),
        }
    }
}

/// 与会话模型无关的单条搜索服务解析。
#[derive(Debug, Clone)]
pub struct WebSearchService {
    pub resolution: WebSearchResolution,
    pub(super) backend: Option<WebSearchBackend>,
}

/// OpenAI 与 DeepSeek 两条独立搜索服务的解析结果。
#[derive(Debug, Clone)]
pub struct WebSearchServices {
    pub openai: WebSearchService,
    pub deepseek: WebSearchService,
}

/// 一条搜索路径叠加当前模型能力后的规划结果。
#[derive(Debug, Clone)]
pub struct WebSearchPlan {
    pub resolution: WebSearchResolution,
    pub(super) backend: Option<WebSearchBackend>,
    pub(super) hosted_dialect: Option<HostedWebSearchDialect>,
}

/// OpenAI 与 DeepSeek 两条独立搜索路径的规划结果。
#[derive(Debug, Clone)]
pub struct WebSearchPlans {
    pub openai: WebSearchPlan,
    pub deepseek: WebSearchPlan,
    pub deepseek_options: WebSearchDeepSeekOptions,
}

impl WebSearchPlans {
    pub(super) fn plans(&self) -> [&WebSearchPlan; 2] {
        [&self.openai, &self.deepseek]
    }
}

/// DeepSeek 联网能力的两个独立开关。
#[derive(Debug, Clone, Copy)]
pub struct WebSearchDeepSeekOptions {
    pub enabled: bool,
    pub fetch_enabled: bool,
}

impl Default for WebSearchDeepSeekOptions {
    fn default() -> Self {
        Self {
            enabled: true,
            fetch_enabled: true,
        }
    }
}

impl WebSearchDeepSeekOptions {
    pub fn any_enabled(&self) -> bool {
        self.enabled || self.fetch_enabled
    }
}

/// 独立解析两条搜索服务路径，与会话模型无关。
///
/// 候选 account 按 account id 稳定排序，搜索服务模型来自该 account 自己的目录；
/// 因此跨会话更换同一 account 的对话模型不会改变搜索服务模型。
pub fn plan_web_search_services(
    models: &AgentModelConfig,
    openai_config: &WebSearchConfig,
    deepseek: &WebSearchDeepSeekOptions,
) -> Result<WebSearchServices> {
    Ok(WebSearchServices {
        openai: plan_openai_service(models, openai_config)?,
        deepseek: plan_deepseek_service(models, deepseek, None)?,
    })
}

/// 分别独立规划 OpenAI 与 DeepSeek 两条搜索路径，并叠加当前模型能力检查。
pub fn plan_web_searches(
    models: &AgentModelConfig,
    current: &ResolvedModelRoute,
    openai_config: &WebSearchConfig,
    deepseek: &WebSearchDeepSeekOptions,
) -> Result<WebSearchPlans> {
    Ok(WebSearchPlans {
        openai: plan_openai_web_search(models, current, openai_config)?,
        deepseek: plan_deepseek_web_search(models, current, deepseek)?,
        deepseek_options: *deepseek,
    })
}

/// 根据 account 服务能力和当前模型能力确定性规划 OpenAI Web Search。
///
/// standalone `/alpha/search` 与 Responses hosted search 语义保持不变，只是不再让
/// hosted 路径独占本轮工具。
pub fn plan_openai_web_search(
    models: &AgentModelConfig,
    current: &ResolvedModelRoute,
    config: &WebSearchConfig,
) -> Result<WebSearchPlan> {
    let service = plan_openai_service(models, config)?;
    let configured_mode = service.resolution.configured_mode;
    if service.resolution.availability == WebSearchAvailability::Disabled {
        return Ok(unavailable_plan(
            configured_mode,
            WebSearchAvailability::Disabled,
        ));
    }
    if service.resolution.availability == WebSearchAvailability::Available
        && current.model.capabilities.supports_function_calling()
        && let Some(backend) = service.backend
    {
        return Ok(standalone_plan(configured_mode, backend));
    }

    let current_has_credential = current.endpoint.bearer_token.is_some();
    let hosted_capabilities = &current.endpoint.service_capabilities.web_search;
    let hosted_declared = hosted_capabilities.hosted_responses
        && hosted_capabilities.hosted_dialect == HostedWebSearchDialect::OpenAiResponses;
    let hosted_supported = hosted_declared
        && current.model.binding.transport.protocol == WireApi::Responses
        && current.model.capabilities.supports_web_search()
        && current_has_credential;
    if hosted_supported {
        return Ok(hosted_plan(
            configured_mode,
            current.account_id.clone(),
            Some(current.model.model_id.clone()),
            HostedWebSearchDialect::OpenAiResponses,
        ));
    }

    let availability = if service.resolution.availability != WebSearchAvailability::Available {
        service.resolution.availability
    } else if hosted_declared && !current_has_credential {
        WebSearchAvailability::MissingCredential
    } else {
        WebSearchAvailability::ModelUnsupported
    };
    Ok(unavailable_plan(configured_mode, availability))
}

/// 规划 DeepSeek 独立搜索路径，消费者模型只要求 function calling。
///
/// 当前 account 仅在自己声明 DeepSeek native 方言且有 key 时作为候选优先；否则按
/// account id 稳定顺序。DeepSeek standalone 不解析也不借用会话模型。
pub fn plan_deepseek_web_search(
    models: &AgentModelConfig,
    current: &ResolvedModelRoute,
    deepseek: &WebSearchDeepSeekOptions,
) -> Result<WebSearchPlan> {
    let service = plan_deepseek_service(models, deepseek, Some(&current.account_id))?;
    let configured_mode = service.resolution.configured_mode;
    if service.resolution.availability == WebSearchAvailability::Disabled {
        return Ok(unavailable_plan(
            configured_mode,
            WebSearchAvailability::Disabled,
        ));
    }
    if service.resolution.availability == WebSearchAvailability::Available
        && current.model.capabilities.supports_function_calling()
        && let Some(backend) = service.backend
    {
        return Ok(standalone_plan(configured_mode, backend));
    }
    let availability = if service.resolution.availability == WebSearchAvailability::Available {
        WebSearchAvailability::ModelUnsupported
    } else {
        service.resolution.availability
    };
    Ok(unavailable_plan(configured_mode, availability))
}

fn plan_openai_service(
    models: &AgentModelConfig,
    config: &WebSearchConfig,
) -> Result<WebSearchService> {
    let configured_mode = config.mode;
    if configured_mode.is_disabled() {
        return Ok(unavailable_service(
            configured_mode,
            WebSearchAvailability::Disabled,
        ));
    }
    let selection = standalone_backend(models, StandaloneWebSearchDialect::OpenAiSearchApi, None)?;
    if let Some(backend) = selection.backend {
        return Ok(available_service(
            configured_mode,
            WebSearchPath::Standalone,
            backend,
        ));
    }
    let availability = if selection.any_declared {
        WebSearchAvailability::MissingCredential
    } else {
        WebSearchAvailability::AccountUnsupported
    };
    Ok(unavailable_service(configured_mode, availability))
}

fn plan_deepseek_service(
    models: &AgentModelConfig,
    deepseek: &WebSearchDeepSeekOptions,
    preferred: Option<&AccountId>,
) -> Result<WebSearchService> {
    let configured_mode = if deepseek.any_enabled() {
        WebSearchMode::Live
    } else {
        WebSearchMode::Disabled
    };
    if !deepseek.any_enabled() {
        return Ok(unavailable_service(
            configured_mode,
            WebSearchAvailability::Disabled,
        ));
    }
    let selection = standalone_backend(
        models,
        StandaloneWebSearchDialect::DeepSeekToolsApi,
        preferred,
    )?;
    if let Some(backend) = selection.backend {
        return Ok(available_service(
            configured_mode,
            WebSearchPath::Standalone,
            backend,
        ));
    }
    let availability = if selection.any_declared {
        WebSearchAvailability::MissingCredential
    } else {
        WebSearchAvailability::AccountUnsupported
    };
    Ok(unavailable_service(configured_mode, availability))
}

#[derive(Debug, Default)]
struct StandaloneSelection {
    backend: Option<WebSearchBackend>,
    any_declared: bool,
}

/// 选择首个声明该方言且有非空 key 的 account。
///
/// `preferred` 仅在它自己声明该方言且有 key 时优先；否则回退到按 account id 的稳定顺序。
/// OpenAI 路径传 `None`，DeepSeek 线程规划传当前 account，settings 服务投影同样传 `None`。
fn standalone_backend(
    models: &AgentModelConfig,
    dialect: StandaloneWebSearchDialect,
    preferred: Option<&AccountId>,
) -> Result<StandaloneSelection> {
    let mut selection = StandaloneSelection::default();
    for (account_id, account) in candidate_order(models, preferred) {
        let capabilities = account.service_capabilities()?;
        if capabilities.web_search.standalone != Some(dialect) {
            continue;
        }
        selection.any_declared = true;
        if account.resolved_bearer_token().is_none() {
            continue;
        }
        let (model, max_output_tokens) = search_service_model(account_id, account, dialect)?;
        selection.backend = Some(WebSearchBackend {
            account_id: account_id.clone(),
            endpoint: account.to_endpoint()?,
            model,
            max_output_tokens,
            dialect,
        });
        return Ok(selection);
    }
    Ok(selection)
}

/// preferred account（若存在）在前的稳定候选顺序，其余按 account id 排序。
fn candidate_order<'a>(
    models: &'a AgentModelConfig,
    preferred: Option<&AccountId>,
) -> Vec<(&'a AccountId, &'a AccountConfig)> {
    let mut ordered = Vec::with_capacity(models.accounts.len());
    if let Some(preferred) = preferred
        && let Some((account_id, account)) = models.accounts.get_key_value(preferred)
    {
        ordered.push((account_id, account));
    }
    for (account_id, account) in &models.accounts {
        if Some(account_id) == preferred {
            continue;
        }
        ordered.push((account_id, account));
    }
    ordered
}

/// 从 account 自身目录选择确定性、与会话模型无关的搜索服务模型。
fn search_service_model(
    account_id: &AccountId,
    account: &AccountConfig,
    dialect: StandaloneWebSearchDialect,
) -> Result<(Option<String>, Option<u64>)> {
    match dialect {
        StandaloneWebSearchDialect::OpenAiSearchApi => {
            let models = account.effective_models(None)?;
            let model = models
                .iter()
                .find(|model| model.model_id == OPENAI_SEARCH_MODEL)
                .or_else(|| models.first())
                .ok_or_else(|| {
                    PureError::ConfigError(format!(
                        "account {account_id} has no models for standalone web search"
                    ))
                })?;
            Ok((Some(model.model_id.clone()), model.max_output_tokens))
        }
        StandaloneWebSearchDialect::DeepSeekToolsApi => Ok((None, None)),
    }
}

fn available_service(
    mode: WebSearchMode,
    path: WebSearchPath,
    backend: WebSearchBackend,
) -> WebSearchService {
    WebSearchService {
        resolution: available_resolution(
            mode,
            path,
            backend.account_id.clone(),
            backend.model.clone(),
        ),
        backend: Some(backend),
    }
}

fn unavailable_service(
    mode: WebSearchMode,
    availability: WebSearchAvailability,
) -> WebSearchService {
    WebSearchService {
        resolution: WebSearchResolution {
            configured_mode: mode,
            effective_mode: WebSearchMode::Disabled,
            availability,
            path: None,
            account_id: None,
            model_id: None,
        },
        backend: None,
    }
}

fn standalone_plan(mode: WebSearchMode, backend: WebSearchBackend) -> WebSearchPlan {
    WebSearchPlan {
        resolution: available_resolution(
            mode,
            WebSearchPath::Standalone,
            backend.account_id.clone(),
            backend.model.clone(),
        ),
        backend: Some(backend),
        hosted_dialect: None,
    }
}

fn hosted_plan(
    mode: WebSearchMode,
    account_id: AccountId,
    model_id: Option<String>,
    dialect: HostedWebSearchDialect,
) -> WebSearchPlan {
    WebSearchPlan {
        resolution: available_resolution(mode, WebSearchPath::Hosted, account_id, model_id),
        backend: None,
        hosted_dialect: Some(dialect),
    }
}

fn available_resolution(
    mode: WebSearchMode,
    path: WebSearchPath,
    account_id: AccountId,
    model_id: Option<String>,
) -> WebSearchResolution {
    WebSearchResolution {
        configured_mode: mode,
        effective_mode: mode,
        availability: WebSearchAvailability::Available,
        path: Some(path),
        account_id: Some(account_id),
        model_id,
    }
}

fn unavailable_plan(
    configured_mode: WebSearchMode,
    availability: WebSearchAvailability,
) -> WebSearchPlan {
    WebSearchPlan {
        resolution: WebSearchResolution {
            configured_mode,
            effective_mode: WebSearchMode::Disabled,
            availability,
            path: None,
            account_id: None,
            model_id: None,
        },
        backend: None,
        hosted_dialect: None,
    }
}

fn mode_label(mode: WebSearchMode) -> &'static str {
    match mode {
        WebSearchMode::Disabled => "disabled",
        WebSearchMode::Cached => "cached",
        WebSearchMode::Indexed => "indexed",
        WebSearchMode::Live => "live",
    }
}

fn availability_label(availability: WebSearchAvailability) -> &'static str {
    match availability {
        WebSearchAvailability::Available => "available",
        WebSearchAvailability::Disabled => "disabled",
        WebSearchAvailability::MissingCredential => "missing_credential",
        WebSearchAvailability::AccountUnsupported => "account_unsupported",
        WebSearchAvailability::ModelUnsupported => "model_unsupported",
    }
}

fn path_label(path: WebSearchPath) -> &'static str {
    match path {
        WebSearchPath::Standalone => "standalone",
        WebSearchPath::Hosted => "hosted",
    }
}

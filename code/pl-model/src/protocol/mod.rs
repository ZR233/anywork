//! Endpoint configuration, concrete native clients and independently supported services.
mod adapters;
mod clients;
pub mod compatible;
pub mod deepseek;
pub mod discovery;
pub(crate) mod files;
pub mod images;
pub mod mimo;
pub mod openai;
pub mod xai;
pub mod zhipu;
pub(crate) use adapters::{ProtocolAdaptation, ProtocolAdapter};
pub use clients::ProtocolClient;

use std::collections::HashMap;
use std::hash::{DefaultHasher, Hash, Hasher};

use serde::Deserialize;
use serde::Serialize;

use crate::runtime::transport_policy::RESPONSES_WEBSOCKET_PROFILE_REVISION;

// 公共能力类型字段（如 `WebSearchServiceCapabilities::hosted_dialect`）使用的
// pl-protocol 类型在此精确重导出，消费方只需依赖 pl-model。
pub use pl_protocol::HostedWebSearchDialect;

pub const ZHIPU_CODING_PLAN_BASE_URL: &str = "https://open.bigmodel.cn/api/v1";
pub(crate) const RESPONSES_WEBSOCKET_DIALECT: &str = "responses_websockets=2026-02-06";

/// 协议 endpoint 可提供的独立 Web Search 协议。
///
/// 该类型描述服务能力，不代表 provider 身份；任何兼容 endpoint 都可显式声明。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StandaloneWebSearchDialect {
    /// OpenAI 兼容的独立 `/alpha/search` 搜索 API。
    OpenAiSearchApi,
    /// DeepSeek 原生独立搜索：官方 Search & Fetch 工具接口。
    DeepSeekToolsApi,
}

impl StandaloneWebSearchDialect {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::OpenAiSearchApi => "open_ai_search_api",
            Self::DeepSeekToolsApi => "deep_seek_tools_api",
        }
    }
}

impl std::str::FromStr for StandaloneWebSearchDialect {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "open_ai_search_api" => Ok(Self::OpenAiSearchApi),
            "deep_seek_tools_api" => Ok(Self::DeepSeekToolsApi),
            value => Err(format!(
                "unsupported standalone web search dialect: {value}"
            )),
        }
    }
}

/// 厂商协议 endpoint 可提供的 Web Search 服务能力。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct WebSearchServiceCapabilities {
    #[serde(default)]
    pub hosted_responses: bool,
    #[serde(default)]
    pub hosted_dialect: HostedWebSearchDialect,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub standalone: Option<StandaloneWebSearchDialect>,
}

/// 协议 endpoint 可提供的图像生成协议方言。
///
/// 该类型描述服务能力，不代表 endpoint 身份；任何兼容 endpoint 都可显式声明。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ImageGenerationDialect {
    /// OpenAI 兼容的 `/images/generations` 内联图像接口。
    OpenAiImages,
}

impl ImageGenerationDialect {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::OpenAiImages => "open_ai_images",
        }
    }

    /// 方言声明的请求路径，直接追加到 endpoint `base_url` 之后。
    ///
    /// 路径不包含版本前缀：版本前缀只来自用户配置的 `base_url`。
    pub const fn path(self) -> &'static str {
        match self {
            Self::OpenAiImages => "/images/generations",
        }
    }
}

impl std::str::FromStr for ImageGenerationDialect {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "open_ai_images" => Ok(Self::OpenAiImages),
            value => Err(format!("unsupported image generation dialect: {value}")),
        }
    }
}

/// 协议 endpoint 可提供的图像生成服务能力。
///
/// 生图模型不是对话模型：`model_prefixes` 是生图库存的唯一声明来源，
/// `preferred_models` 只决定同一 endpoint 内的确定性选择顺序。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ImageGenerationCapabilities {
    pub dialect: ImageGenerationDialect,
    /// 生图模型 slug 前缀，大小写敏感。
    pub model_prefixes: Vec<String>,
    /// 有序首选生图模型 slug；留空交给版本择优。
    pub preferred_models: Vec<String>,
}

impl ImageGenerationCapabilities {
    /// OpenAI 官方 Images 能力的 canonical 声明。
    ///
    /// 首选序有意留空：选择交给候选名单的版本择优，避免把某个旧 slug 固化为默认。
    pub fn openai_images() -> Self {
        Self {
            dialect: ImageGenerationDialect::OpenAiImages,
            model_prefixes: vec!["gpt-image-".to_string()],
            preferred_models: Vec::new(),
        }
    }
}

/// 与具体产品无关的 endpoint 外部服务能力。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProtocolServiceCapabilities {
    #[serde(default)]
    pub files: FileUploadCapability,
    #[serde(default)]
    pub remote_compaction: bool,
    #[serde(default)]
    pub web_search: WebSearchServiceCapabilities,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub image_generation: Option<ImageGenerationCapabilities>,
    #[serde(default)]
    pub prompt_cache: PromptCacheServiceCapabilities,
    #[serde(default)]
    pub responses_tools: ResponsesHostedToolCapabilities,
    #[serde(default, rename = "historyInstructionRole")]
    pub history_instruction_role: HistoryInstructionRole,
}

/// Accepted authority for full instruction snapshots inside model history.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum HistoryInstructionRole {
    #[default]
    None,
    System,
    Developer,
}

impl HistoryInstructionRole {
    /// Whether this declared history role actually accepts the wire role the
    /// concrete protocol sends. `None` is never a supported update authority.
    pub(crate) fn accepts(self, role: InstructionWireRole) -> bool {
        matches!(
            (self, role),
            (Self::System, InstructionWireRole::System)
                | (Self::Developer, InstructionWireRole::Developer)
        )
    }
}

/// The wire role a concrete protocol + wire API uses for trusted instruction messages.
///
/// Chat Completions only has `system`; Responses defaults to `developer` except DeepSeek,
/// whose official Responses surface treats `developer` as `user` and therefore must send
/// trusted instructions as `system`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum InstructionWireRole {
    System,
    Developer,
}

/// Effective behavior requires both endpoint syntax and model override semantics.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstructionUpdateStrategy {
    ReplacePrefix,
    AppendFullSnapshot,
}

/// Explicit upload dialect; custom endpoints must opt in.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum FileUploadCapability {
    #[default]
    None,
    DeepSeek,
}

/// Endpoint 对 Responses hosted tool 类型的支持。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ResponsesHostedToolCapabilities {
    #[serde(default)]
    pub programmatic_tool_calling: bool,
}

/// 协议 endpoint 的提示词缓存 dialect。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum PromptCacheDialect {
    #[default]
    None,
    ImplicitPrefix,
    OpenAiPromptCacheKey,
}

impl PromptCacheDialect {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::None => "none",
            Self::ImplicitPrefix => "implicit_prefix",
            Self::OpenAiPromptCacheKey => "open_ai_prompt_cache_key",
        }
    }
}

impl std::str::FromStr for PromptCacheDialect {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "none" => Ok(Self::None),
            "implicit_prefix" => Ok(Self::ImplicitPrefix),
            "open_ai_prompt_cache_key" => Ok(Self::OpenAiPromptCacheKey),
            value => Err(format!("unsupported prompt cache dialect: {value}")),
        }
    }
}

/// 协议 endpoint 可提供的提示词缓存能力。
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct PromptCacheServiceCapabilities {
    #[serde(default)]
    pub dialect: PromptCacheDialect,
}

/// 当前协议、wire API 与 model 合成后的缓存策略。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum EffectivePromptCachePolicy {
    #[default]
    None,
    ImplicitPrefix,
    OpenAiPromptCacheKey,
}

impl EffectivePromptCachePolicy {
    pub const fn label(self) -> &'static str {
        match self {
            Self::None => "none",
            Self::ImplicitPrefix => "implicitPrefix",
            Self::OpenAiPromptCacheKey => "openAiPromptCacheKey",
        }
    }

    pub const fn uses_prompt_cache_key(self) -> bool {
        matches!(self, Self::OpenAiPromptCacheKey)
    }
}

impl ProtocolServiceCapabilities {
    /// 返回同时支持 Responses hosted 与 OpenAI Search API 的能力集合。
    pub fn openai_web_search() -> Self {
        Self {
            history_instruction_role: HistoryInstructionRole::None,
            remote_compaction: true,
            files: FileUploadCapability::None,
            web_search: WebSearchServiceCapabilities {
                hosted_responses: true,
                hosted_dialect: HostedWebSearchDialect::OpenAiResponses,
                standalone: Some(StandaloneWebSearchDialect::OpenAiSearchApi),
            },
            image_generation: None,
            prompt_cache: PromptCacheServiceCapabilities {
                dialect: PromptCacheDialect::OpenAiPromptCacheKey,
            },
            responses_tools: ResponsesHostedToolCapabilities {
                programmatic_tool_calling: true,
            },
        }
    }
}

/// 明确的厂商协议选择。
///
/// 自定义 endpoint 不会从 URL 获得厂商身份；协议适配、wire API 与连接方式是三个独立
/// 维度。字符串值保留既有 wire 事实（如 `deep_seek`）。
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ProtocolKind {
    OpenAi,
    DeepSeek,
    Zhipu,
    MiMo,
    Xai,
    #[default]
    OpenAiCompatible,
}

impl ProtocolKind {
    /// 与 serde 相同的 wire 值；描述投影和解析共用这一处事实。
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::OpenAi => "open_ai",
            Self::DeepSeek => "deep_seek",
            Self::Zhipu => "zhipu",
            Self::MiMo => "mi_mo",
            Self::Xai => "xai",
            Self::OpenAiCompatible => "open_ai_compatible",
        }
    }

    /// The wire role this protocol uses for trusted instruction messages.
    ///
    /// This is the single dispatch fact: Chat Completions always uses `system`, Responses
    /// uses `developer` except DeepSeek whose Responses contract sends `system`. Neither the
    /// model name nor the endpoint URL participates.
    pub(crate) const fn instruction_wire_role(self, api: WireApi) -> InstructionWireRole {
        match (self, api) {
            (Self::DeepSeek, WireApi::Responses) => InstructionWireRole::System,
            (_, WireApi::Responses) => InstructionWireRole::Developer,
            (_, WireApi::ChatCompletions) => InstructionWireRole::System,
        }
    }
}

impl std::str::FromStr for ProtocolKind {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "open_ai" => Ok(Self::OpenAi),
            "deep_seek" => Ok(Self::DeepSeek),
            "zhipu" => Ok(Self::Zhipu),
            "mi_mo" => Ok(Self::MiMo),
            "xai" => Ok(Self::Xai),
            "open_ai_compatible" => Ok(Self::OpenAiCompatible),
            value => Err(format!("unsupported protocol kind: {value}")),
        }
    }
}

#[derive(Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ProtocolEndpoint {
    #[serde(default)]
    pub protocol: ProtocolKind,
    pub name: String,
    pub base_url: String,
    pub bearer_token: Option<String>,
    pub http_headers: Option<HashMap<String, String>>,
    #[serde(default)]
    pub tool_wire_policy: ToolWirePolicy,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub apply_patch_tool_type: Option<ApplyPatchToolType>,
    #[serde(default)]
    pub service_capabilities: ProtocolServiceCapabilities,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum WireApi {
    Responses,
    #[default]
    ChatCompletions,
}

/// 流式完成请求使用的连接方式。
///
/// 连接方式与 wire API 正交：OpenAI 的两个模式都使用 Responses，HTTP
/// 模式通过 SSE 返回事件，WebSocket 模式通过 `response.create` 帧返回事件。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConnectionMode {
    WebSocket,
    #[default]
    Http,
}

/// 返回 transport 实现的确定性版本标识，供上层 catalog revision 纳入缓存失效。
///
/// 标识不进入配置或产品 DTO；Responses WebSocket 的值与实际握手 dialect
/// 常量同源，协议适配发生变化时 catalog ETag 会随二进制一起变化。
pub fn wire_transport_profile_revision(protocol: WireApi, mode: ConnectionMode) -> &'static str {
    match (protocol, mode) {
        (WireApi::Responses, ConnectionMode::WebSocket) => RESPONSES_WEBSOCKET_PROFILE_REVISION,
        (WireApi::Responses, ConnectionMode::Http) => "responses-http-v1",
        (WireApi::ChatCompletions, ConnectionMode::Http) => "chat-completions-http-v1",
        (WireApi::ChatCompletions, ConnectionMode::WebSocket) => {
            "unsupported-chat-completions-websocket"
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ToolWirePolicy {
    NativeCustomTools,
    #[default]
    FunctionFallback,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ApplyPatchToolType {
    Freeform,
}

impl std::fmt::Debug for ProtocolEndpoint {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("ProtocolEndpoint")
            .field("name", &self.name)
            .field("protocol", &self.protocol)
            .field("has_credential", &self.bearer_token.is_some())
            .finish_non_exhaustive()
    }
}

impl ProtocolEndpoint {
    /// Selects a concrete protocol explicitly, without changing endpoint credentials.
    pub fn with_protocol(mut self, protocol: ProtocolKind) -> Self {
        self.protocol = protocol;
        self
    }

    pub fn effective_prompt_cache_policy(
        &self,
        model: &crate::model::ModelInfo,
    ) -> EffectivePromptCachePolicy {
        match (
            model.binding.transport.protocol,
            self.service_capabilities.prompt_cache.dialect,
        ) {
            (_, PromptCacheDialect::ImplicitPrefix) => EffectivePromptCachePolicy::ImplicitPrefix,
            (WireApi::Responses, PromptCacheDialect::OpenAiPromptCacheKey) => {
                EffectivePromptCachePolicy::OpenAiPromptCacheKey
            }
            _ => EffectivePromptCachePolicy::None,
        }
    }

    pub fn instruction_update_strategy(
        &self,
        model: &crate::model::ModelInfo,
    ) -> InstructionUpdateStrategy {
        let role = self
            .protocol
            .instruction_wire_role(model.binding.transport.protocol);
        let accepts = self
            .service_capabilities
            .history_instruction_role
            .accepts(role);
        if accepts && model.capabilities.instruction_snapshot_overrides {
            InstructionUpdateStrategy::AppendFullSnapshot
        } else {
            InstructionUpdateStrategy::ReplacePrefix
        }
    }

    pub fn openai(base_url: Option<String>) -> Self {
        let custom_endpoint = base_url.is_some();
        let mut service_capabilities = ProtocolServiceCapabilities::openai_web_search();
        // 覆盖 base_url 保留图像生成能力：Images 路径追加在该前缀之后，与
        // standalone Web Search 的继承语义一致。
        service_capabilities.image_generation = Some(ImageGenerationCapabilities::openai_images());
        if custom_endpoint {
            service_capabilities.remote_compaction = false;
            service_capabilities.responses_tools = ResponsesHostedToolCapabilities::default();
        }
        Self {
            protocol: ProtocolKind::OpenAi,
            name: "OpenAI".into(),
            base_url: base_url.unwrap_or_else(|| "https://api.openai.com/v1".into()),
            bearer_token: None,
            http_headers: None,
            tool_wire_policy: ToolWirePolicy::NativeCustomTools,
            apply_patch_tool_type: Some(ApplyPatchToolType::Freeform),
            service_capabilities,
        }
    }

    /// Canonical xAI Responses endpoint. A custom URL drops prompt-cache inheritance.
    pub fn xai(base_url: Option<String>) -> Self {
        let canonical = base_url
            .as_deref()
            .is_none_or(|url| url.trim_end_matches('/') == "https://api.x.ai/v1");
        Self {
            protocol: ProtocolKind::Xai,
            name: "xAI".into(),
            base_url: base_url.unwrap_or_else(|| "https://api.x.ai/v1".into()),
            bearer_token: None,
            http_headers: None,
            tool_wire_policy: ToolWirePolicy::FunctionFallback,
            apply_patch_tool_type: None,
            service_capabilities: ProtocolServiceCapabilities {
                prompt_cache: PromptCacheServiceCapabilities {
                    dialect: if canonical {
                        PromptCacheDialect::OpenAiPromptCacheKey
                    } else {
                        PromptCacheDialect::None
                    },
                },
                ..ProtocolServiceCapabilities::default()
            },
        }
    }

    pub fn deepseek(base_url: Option<String>) -> Self {
        let canonical = base_url
            .as_deref()
            .is_none_or(|url| url.trim_end_matches('/') == "https://api.deepseek.com");
        Self {
            protocol: ProtocolKind::DeepSeek,
            name: "DeepSeek".into(),
            base_url: base_url.unwrap_or_else(|| "https://api.deepseek.com".into()),
            bearer_token: None,
            http_headers: None,
            tool_wire_policy: ToolWirePolicy::FunctionFallback,
            apply_patch_tool_type: None,
            service_capabilities: ProtocolServiceCapabilities {
                // DeepSeek 的 in-history/leading-only 更新能力只在 Messages API 下声明，
                // Responses 不可证明；这里不声明历史指令覆盖能力，安全走 ReplacePrefix。
                history_instruction_role: HistoryInstructionRole::None,
                files: if canonical {
                    FileUploadCapability::DeepSeek
                } else {
                    FileUploadCapability::None
                },
                web_search: WebSearchServiceCapabilities {
                    standalone: canonical.then_some(StandaloneWebSearchDialect::DeepSeekToolsApi),
                    ..WebSearchServiceCapabilities::default()
                },
                prompt_cache: PromptCacheServiceCapabilities {
                    dialect: PromptCacheDialect::ImplicitPrefix,
                },
                ..ProtocolServiceCapabilities::default()
            },
        }
    }

    pub fn zhipu(base_url: Option<String>) -> Self {
        Self::compatible(
            "Zhipu",
            base_url.unwrap_or_else(|| "https://open.bigmodel.cn/api/paas/v4".into()),
        )
        .with_protocol(ProtocolKind::Zhipu)
    }

    pub fn zhipu_coding_plan(base_url: Option<String>) -> Self {
        Self::compatible(
            "Zhipu Coding Plan",
            base_url.unwrap_or_else(|| ZHIPU_CODING_PLAN_BASE_URL.into()),
        )
        .with_protocol(ProtocolKind::Zhipu)
    }

    /// 构造通用 OpenAI-compatible provider。
    ///
    /// 协议与连接模式属于绑定模型的 transport profile；endpoint 只采用最保守
    /// 的 function tool wire，不因兼容服务名称继承官方 OpenAI 能力。
    pub fn compatible(name: impl Into<String>, base_url: impl Into<String>) -> Self {
        Self {
            protocol: ProtocolKind::OpenAiCompatible,
            name: name.into(),
            base_url: base_url.into(),
            bearer_token: None,
            http_headers: None,
            tool_wire_policy: ToolWirePolicy::FunctionFallback,
            apply_patch_tool_type: None,
            service_capabilities: ProtocolServiceCapabilities::default(),
        }
    }

    pub fn uses_native_custom_tools(&self) -> bool {
        matches!(self.tool_wire_policy, ToolWirePolicy::NativeCustomTools)
    }

    /// 返回只用于进程内连接复用判定的 provider 指纹。
    ///
    /// 指纹覆盖 endpoint、凭证和 headers，但不会暴露这些原始值。配置发生
    /// 变化时，已有模型会话 会断开旧 WebSocket 并建立新连接。
    pub fn connection_fingerprint(&self) -> u64 {
        let mut hasher = DefaultHasher::new();
        self.base_url.trim_end_matches('/').hash(&mut hasher);
        self.bearer_token.hash(&mut hasher);
        if let Some(headers) = &self.http_headers {
            let mut headers = headers.iter().collect::<Vec<_>>();
            headers.sort_by(|left, right| left.0.cmp(right.0));
            for (name, value) in headers {
                name.hash(&mut hasher);
                value.hash(&mut hasher);
            }
        }
        let fingerprint = hasher.finish();
        if fingerprint == 0 { 1 } else { fingerprint }
    }
}

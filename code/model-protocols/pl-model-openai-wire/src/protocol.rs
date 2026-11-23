//! Endpoint configuration, wire dialects and independently supported services.
pub use crate::authorization::EndpointAuthorization;

use std::collections::HashMap;
use std::hash::{DefaultHasher, Hash, Hasher};

use serde::Deserialize;
use serde::Serialize;

/// Identifier of the hosted search dialect offered by an endpoint.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct HostedWebSearchDialect(ProtocolId);

impl HostedWebSearchDialect {
    pub const RESPONSES: Self = Self::from_static("open_ai_responses");

    pub const fn from_static(id: &'static str) -> Self {
        Self(ProtocolId::from_static(id))
    }

    pub fn as_str(&self) -> &str {
        self.0.as_str()
    }
}

impl Default for HostedWebSearchDialect {
    fn default() -> Self {
        Self::RESPONSES
    }
}

impl std::str::FromStr for HostedWebSearchDialect {
    type Err = pl_model_types::InvalidProtocolId;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        value.parse().map(Self)
    }
}

pub const RESPONSES_WEBSOCKET_DIALECT: &str = "responses_websockets=2026-02-06";

/// Identifier of a registered standalone search service.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct StandaloneWebSearchDialect(ProtocolId);

impl StandaloneWebSearchDialect {
    pub const fn from_static(id: &'static str) -> Self {
        Self(ProtocolId::from_static(id))
    }

    pub fn as_str(&self) -> &str {
        self.0.as_str()
    }
}

impl std::str::FromStr for StandaloneWebSearchDialect {
    type Err = pl_model_types::InvalidProtocolId;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        value.parse().map(Self)
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
    pub fn accepts(self, role: InstructionWireRole) -> bool {
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
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum InstructionWireRole {
    System,
    #[default]
    Developer,
}

/// Effective behavior requires both endpoint syntax and model override semantics.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InstructionUpdateStrategy {
    ReplacePrefix,
    AppendFullSnapshot,
}

/// Explicit upload dialect; custom endpoints must opt in.
/// Stable ID of the selected file upload service. The existing "none" value
/// is reserved for endpoints without an upload service.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(transparent)]
pub struct FileUploadCapability(ProtocolId);

impl FileUploadCapability {
    pub const NONE: Self = Self(ProtocolId::from_static("none"));

    pub const fn from_static(id: &'static str) -> Self {
        Self(ProtocolId::from_static(id))
    }

    pub fn as_str(&self) -> &str {
        self.0.as_str()
    }
}

impl Default for FileUploadCapability {
    fn default() -> Self {
        Self::NONE
    }
}

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
    #[serde(rename = "open_ai_prompt_cache_key")]
    ExplicitKey,
}

impl PromptCacheDialect {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::None => "none",
            Self::ImplicitPrefix => "implicit_prefix",
            Self::ExplicitKey => "open_ai_prompt_cache_key",
        }
    }
}

impl std::str::FromStr for PromptCacheDialect {
    type Err = String;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "none" => Ok(Self::None),
            "implicit_prefix" => Ok(Self::ImplicitPrefix),
            "open_ai_prompt_cache_key" => Ok(Self::ExplicitKey),
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
    #[serde(rename = "openAiPromptCacheKey")]
    ExplicitKey,
}

impl EffectivePromptCachePolicy {
    pub const fn label(self) -> &'static str {
        match self {
            Self::None => "none",
            Self::ImplicitPrefix => "implicitPrefix",
            Self::ExplicitKey => "openAiPromptCacheKey",
        }
    }

    pub const fn uses_prompt_cache_key(self) -> bool {
        matches!(self, Self::ExplicitKey)
    }
}

impl ProtocolServiceCapabilities {
    /// 返回同时支持 Responses hosted 与 OpenAI Search API 的能力集合。
    pub fn openai_web_search() -> Self {
        Self {
            history_instruction_role: HistoryInstructionRole::None,
            remote_compaction: true,
            files: FileUploadCapability::NONE,
            web_search: WebSearchServiceCapabilities {
                hosted_responses: true,
                hosted_dialect: HostedWebSearchDialect::RESPONSES,
                standalone: None,
            },
            image_generation: None,
            prompt_cache: PromptCacheServiceCapabilities {
                dialect: PromptCacheDialect::ExplicitKey,
            },
            responses_tools: ResponsesHostedToolCapabilities {
                programmatic_tool_calling: true,
            },
        }
    }
}

pub use pl_model_types::ProtocolId;

#[derive(Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ProtocolEndpoint {
    #[serde(skip)]
    pub authorization: Option<EndpointAuthorization>,
    pub protocol: ProtocolId,
    #[serde(skip)]
    pub responses_instruction_role: InstructionWireRole,
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

pub use pl_model_types::transport::ConnectionMode;

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
            .field("has_authorization", &self.authorization.is_some())
            .finish_non_exhaustive()
    }
}

impl ProtocolEndpoint {
    pub fn request_headers(
        &self,
        token: Option<&str>,
        model_headers: &HashMap<String, String>,
    ) -> crate::Result<reqwest::header::HeaderMap> {
        let mut headers = crate::headers(token, self.http_headers.as_ref(), model_headers)?;
        if let Some(session) = &self.authorization {
            // Legacy/custom header layers must not replace the selected OAuth owner's token.
            let canonical = crate::headers(
                Some(token.ok_or_else(|| {
                    crate::PureError::ConfigError("ChatGPT access token is missing".into())
                })?),
                None,
                &HashMap::new(),
            )?;
            headers.extend(canonical);
            if let Some(workspace_id) = session.workspace_id() {
                let mut account =
                    reqwest::header::HeaderValue::from_str(workspace_id).map_err(|_| {
                        crate::PureError::ConfigError("Invalid ChatGPT account identity".into())
                    })?;
                account.set_sensitive(true);
                headers.insert("chatgpt-account-id", account);
                headers.insert(
                    "originator",
                    reqwest::header::HeaderValue::from_static("anywork"),
                );
            }
        }
        Ok(headers)
    }
    /// Resolve a live token immediately before a supported request, not at route freeze time.
    pub async fn resolve_bearer_token(&self) -> crate::Result<Option<String>> {
        if let Some(session) = &self.authorization {
            return session.token(&self.base_url).await.map(Some);
        }
        Ok(self.bearer_token.clone())
    }
    pub const fn instruction_wire_role(&self, api: WireApi) -> InstructionWireRole {
        match api {
            WireApi::Responses => self.responses_instruction_role,
            WireApi::ChatCompletions => InstructionWireRole::System,
        }
    }

    pub fn effective_prompt_cache_policy(
        &self,
        model: &crate::model::ModelDefinition,
    ) -> EffectivePromptCachePolicy {
        match (
            model.extra.binding.transport.protocol,
            self.service_capabilities.prompt_cache.dialect,
        ) {
            (_, PromptCacheDialect::ImplicitPrefix) => EffectivePromptCachePolicy::ImplicitPrefix,
            (WireApi::Responses, PromptCacheDialect::ExplicitKey) => {
                EffectivePromptCachePolicy::ExplicitKey
            }
            _ => EffectivePromptCachePolicy::None,
        }
    }

    pub fn instruction_update_strategy(
        &self,
        model: &crate::model::ModelDefinition,
    ) -> InstructionUpdateStrategy {
        let role = self.instruction_wire_role(model.extra.binding.transport.protocol);
        let accepts = self
            .service_capabilities
            .history_instruction_role
            .accepts(role);
        if accepts && model.extra.capabilities.instruction_snapshot_overrides {
            InstructionUpdateStrategy::AppendFullSnapshot
        } else {
            InstructionUpdateStrategy::ReplacePrefix
        }
    }

    pub fn new(protocol: ProtocolId, name: impl Into<String>, base_url: impl Into<String>) -> Self {
        Self {
            protocol,
            responses_instruction_role: InstructionWireRole::Developer,
            authorization: None,
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
        self.authorization
            .as_ref()
            .map(|session| session.registration_id())
            .hash(&mut hasher);
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

const RESPONSES_WEBSOCKET_PROFILE_REVISION: &str = "responses_websockets=2026-02-06;pl-ws-v2;happy-eyeballs=250ms;connect=15s;send=15s;idle=300s;ws-retries=1;total-retries=5;replay-budget=shared;fallback=http-session";

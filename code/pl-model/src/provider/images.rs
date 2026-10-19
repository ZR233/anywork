//! 独立 Images 方言的图像生成客户端。
//!
//! 该模块属于 provider 协议边界：请求与响应都是 Images 方言的 wire 细节，不进入会话
//! transport，也不携带会话历史。调用方只消费 [`ImagesClient`]、[`ImageGenerationRequest`]、
//! [`ImageGenerationBackground`]、[`GeneratedImage`] 与 [`ImagesError`]。
//!
//! 契约要点：
//! - 端点由方言声明的路径追加到 `base_url` 之后：去掉尾部 `/`，保留用户配置的 path
//!   前缀（含版本前缀），不插入或猜测 `/v1`，也不按 URL 猜测适配器。
//! - 鉴权与配置 header 复用 endpoint 的既有应用逻辑（显式 bearer 与 `http_headers`），
//!   不新建第二套规则；凭据只作为 sensitive header 保存在内部，不进入 `Debug` 或错误信息。
//! - 请求只携带 `model`、`prompt` 与可选 `background`；尺寸、质量、数量与响应格式交给
//!   供应商默认，不为兼容网关发送未声明字段。
//! - 总超时 180 秒覆盖等待 headers 与读取 body；显式禁用重定向与自动重试；响应体上限
//!   32 MiB。取消由 future drop 传播，不创建无主任务。
//! - 响应只接受内联 base64 图像；媒体类型按字节判定，失败保留类型化原因，不回显
//!   header、凭据或原始正文。

use std::collections::HashMap;
use std::time::Duration;

use base64::{Engine, engine::general_purpose::STANDARD};
use futures::StreamExt;
use reqwest::Url;
use serde::Deserialize;

use super::{ImageGenerationDialect, ProviderEndpoint};

pub use pl_protocol::ProviderFailureKind;

/// 响应体上限：32 MiB。
const BODY_LIMIT: usize = 32 * 1024 * 1024;
/// 覆盖整个请求（等待 headers 与读取 body）的总超时。
const REQUEST_TIMEOUT: Duration = Duration::from_secs(180);
const TRANSPARENT_BACKGROUND: &str = "transparent";

/// 背景模式；只有显式透明才发送 `background` 字段。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ImageGenerationBackground {
    Opaque,
    Transparent,
}

/// 一次图像生成的输入。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ImageGenerationRequest {
    /// 生图模型 slug，由 provider 目录的在线观察派生。
    pub model: String,
    /// 提示词原文。
    pub prompt: String,
    /// 背景模式；缺省为不透明，即不发送 `background`。
    pub background: ImageGenerationBackground,
}

/// 已解码的内联图像。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GeneratedImage {
    /// 图像字节；不写入工作区文件，由上层媒体归档消费。
    pub bytes: Vec<u8>,
    /// 按字节判定的媒体类型，例如 `image/png`。
    pub media_type: &'static str,
    /// 供应商可选返回的改写后提示词。
    pub revised_prompt: Option<String>,
}

/// 图像生成的类型化错误；不包含 header、凭据或原始正文。
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum ImagesError {
    #[error("image generation endpoint or headers are invalid")]
    Configuration,
    #[error("image generation timed out")]
    Timeout,
    #[error("image generation transport failed ({kind:?})")]
    Transport { kind: ProviderFailureKind },
    #[error("image generation returned HTTP {status}")]
    Http { status: u16 },
    #[error("image generation response exceeded 32 MiB")]
    TooLarge,
    #[error("image generation returned an invalid response")]
    Protocol,
}

/// 只负责 Images 方言的 HTTP 客户端。
///
/// 客户端冻结一次解析出的端点、方言语义与凭据 header。
pub struct ImagesClient {
    client: reqwest::Client,
    endpoint: Url,
    dialect: ImageGenerationDialect,
}

impl std::fmt::Debug for ImagesClient {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        // URL 在构造时已拒绝 userinfo 与 fragment，凭据只存在于 sensitive header。
        formatter
            .debug_struct("ImagesClient")
            .field("endpoint", &self.endpoint.as_str())
            .field("dialect", &self.dialect)
            .finish_non_exhaustive()
    }
}

impl ImagesClient {
    /// 从声明了图像生成能力的 endpoint 构造客户端。
    ///
    /// # Errors
    /// 未声明能力、非法 endpoint/header 或构建 HTTP 客户端失败返回
    /// [`ImagesError::Configuration`]；这些失败都不发出任何请求。
    pub fn new(endpoint: ProviderEndpoint) -> Result<Self, ImagesError> {
        let dialect = endpoint
            .service_capabilities
            .image_generation
            .as_ref()
            .map(|capabilities| capabilities.dialect)
            .ok_or(ImagesError::Configuration)?;
        let url = endpoint_url(&endpoint.base_url, dialect)?;
        let headers = crate::runtime::transport::headers(
            endpoint.bearer_token.as_deref(),
            endpoint.http_headers.as_ref(),
            &HashMap::new(),
        )
        .map_err(|_| ImagesError::Configuration)?;
        let client = reqwest::Client::builder()
            .timeout(REQUEST_TIMEOUT)
            .redirect(reqwest::redirect::Policy::none())
            .retry(reqwest::retry::never())
            .default_headers(headers)
            .build()
            .map_err(|_| ImagesError::Configuration)?;
        Ok(Self {
            client,
            endpoint: url,
            dialect,
        })
    }

    /// 执行一次图像生成。
    ///
    /// # Errors
    /// 传输、超时、HTTP 状态、响应超限与协议失败分别返回对应的 [`ImagesError`]；
    /// 非 2xx 只报告状态码，不读取正文进错误。
    pub async fn generate(
        &self,
        request: ImageGenerationRequest,
    ) -> Result<GeneratedImage, ImagesError> {
        let body = RequestBody {
            model: &request.model,
            prompt: &request.prompt,
            background: match request.background {
                ImageGenerationBackground::Opaque => None,
                ImageGenerationBackground::Transparent => Some(TRANSPARENT_BACKGROUND),
            },
        };
        let response = self
            .client
            .post(self.endpoint.clone())
            .json(&body)
            .send()
            .await
            .map_err(classify_transport_error)?;
        let status = response.status();
        if !status.is_success() {
            // 状态码是完整失败事实；正文可能含供应商内部细节，不进入错误。
            return Err(ImagesError::Http {
                status: status.as_u16(),
            });
        }
        if response
            .content_length()
            .is_some_and(|length| length > BODY_LIMIT as u64)
        {
            return Err(ImagesError::TooLarge);
        }
        let mut bytes = Vec::new();
        let mut stream = response.bytes_stream();
        while let Some(chunk) = stream.next().await {
            let chunk = chunk.map_err(classify_transport_error)?;
            if chunk.len() > BODY_LIMIT - bytes.len() {
                return Err(ImagesError::TooLarge);
            }
            bytes.extend_from_slice(&chunk);
        }
        decode(&bytes)
    }
}

#[derive(serde::Serialize)]
struct RequestBody<'a> {
    model: &'a str,
    prompt: &'a str,
    #[serde(skip_serializing_if = "Option::is_none")]
    background: Option<&'static str>,
}

/// 未知字段一律忽略：不同网关会在 `data[]` 上追加各自的展示字段。
#[derive(Deserialize)]
struct Envelope {
    data: Option<Vec<ImageRecord>>,
}

#[derive(Deserialize)]
struct ImageRecord {
    b64_json: Option<String>,
    revised_prompt: Option<String>,
}

fn decode(bytes: &[u8]) -> Result<GeneratedImage, ImagesError> {
    let envelope: Envelope = serde_json::from_slice(bytes).map_err(|_| ImagesError::Protocol)?;
    let mut data = envelope.data.ok_or(ImagesError::Protocol)?;
    if data.is_empty() {
        return Err(ImagesError::Protocol);
    }
    let record = data.swap_remove(0);
    let encoded = record.b64_json.ok_or(ImagesError::Protocol)?;
    let bytes = STANDARD
        .decode(encoded.as_bytes())
        .map_err(|_| ImagesError::Protocol)?;
    let media_type = media_type(&bytes).ok_or(ImagesError::Protocol)?;
    Ok(GeneratedImage {
        bytes,
        media_type,
        revised_prompt: record.revised_prompt.filter(|prompt| !prompt.is_empty()),
    })
}

/// 只按字节判定媒体类型；未知格式明确失败，不回退到响应 header 猜测。
fn media_type(bytes: &[u8]) -> Option<&'static str> {
    if bytes.starts_with(b"\x89PNG\r\n\x1a\n") {
        return Some("image/png");
    }
    if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        return Some("image/jpeg");
    }
    if bytes.len() >= 12 && bytes.starts_with(b"RIFF") && &bytes[8..12] == b"WEBP" {
        return Some("image/webp");
    }
    None
}

/// 把方言路径追加到配置的 `base_url` 之后。
///
/// 只接受无 userinfo、无 fragment 的 http(s) 地址；query 保留，路径不猜测版本前缀。
fn endpoint_url(base_url: &str, dialect: ImageGenerationDialect) -> Result<Url, ImagesError> {
    let mut url = Url::parse(base_url.trim()).map_err(|_| ImagesError::Configuration)?;
    if !matches!(url.scheme(), "http" | "https")
        || !url.username().is_empty()
        || url.password().is_some()
        || url.fragment().is_some()
        || url.host_str().is_none()
    {
        return Err(ImagesError::Configuration);
    }
    let declared = dialect.path().trim_start_matches('/');
    let segments = declared.split('/').filter(|segment| !segment.is_empty());
    url.path_segments_mut()
        .map_err(|_| ImagesError::Configuration)?
        .pop_if_empty()
        .extend(segments);
    Ok(url)
}

fn classify_transport_error(error: reqwest::Error) -> ImagesError {
    if error.is_timeout() {
        return ImagesError::Timeout;
    }
    // 复用推理传输的错误分类与脱敏，但不对外暴露其诊断文本。
    match crate::runtime::transport::reqwest_error_to_pure(error) {
        pl_protocol::PureError::Provider(failure) => ImagesError::Transport { kind: failure.kind },
        _ => ImagesError::Configuration,
    }
}

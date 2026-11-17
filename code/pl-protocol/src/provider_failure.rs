use serde::{Deserialize, Serialize};

/// Provider 失败的稳定语义类别；控制流不得从 message 或 provider code 反向推断。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ProviderFailureKind {
    Authentication,
    Authorization,
    Capacity,
    Configuration,
    Transport,
    Protocol,
    Unknown,
}

/// 宿主调度器应如何处理一次模型调用失败。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", tag = "kind")]
pub enum RetryDisposition {
    Retryable {
        #[serde(default, skip_serializing_if = "Option::is_none")]
        retry_after_ms: Option<u64>,
    },
    Permanent,
}

impl RetryDisposition {
    /// 返回失败是否允许由宿主在新的 turn 中继续执行。
    pub fn is_retryable(&self) -> bool {
        matches!(self, Self::Retryable { .. })
    }

    /// 返回 provider 建议的最短等待时间。
    pub fn retry_after_ms(&self) -> Option<u64> {
        match self {
            Self::Retryable { retry_after_ms } => *retry_after_ms,
            Self::Permanent => None,
        }
    }
}

/// Provider adapter 跨 crate 返回的结构化失败阶段。
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ProviderFailureStage {
    #[default]
    Unknown,
    Request,
    Handshake,
    Stream,
    Attachment,
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ProviderRecovery {
    #[default]
    None,
    HttpFallback,
    RefreshAttachments,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProviderFailureContext {
    pub stage: ProviderFailureStage,
    pub request_id: Option<String>,
    pub recovery: ProviderRecovery,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ProviderFailure {
    #[serde(default)]
    pub context: ProviderFailureContext,
    pub kind: ProviderFailureKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub http_status: Option<u16>,
    pub message: String,
    pub retry: RetryDisposition,
}

impl std::fmt::Display for ProviderFailure {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.message)
    }
}

use serde::{Deserialize, Serialize};

use crate::{ProviderFailureKind, RetryDisposition};

/// Turn 失败所属的稳定领域类别。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum TurnFailureCategory {
    Provider,
    ProviderCapacity,
    Tool,
    Validation,
    Protocol,
    Internal,
}

/// 跨 runtime 与宿主边界保存的结构化 turn 失败。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct TurnFailure {
    pub category: TurnFailureCategory,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub provider_kind: Option<ProviderFailureKind>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub http_status: Option<u16>,
    pub message: String,
    pub retry: RetryDisposition,
}

impl TurnFailure {
    /// 构造一个不应由宿主自动重试的失败。
    pub fn permanent(category: TurnFailureCategory, message: impl Into<String>) -> Self {
        Self {
            category,
            provider_kind: None,
            code: None,
            http_status: None,
            message: message.into(),
            retry: RetryDisposition::Permanent,
        }
    }
}

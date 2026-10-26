//! Studio API 的稳定错误分类与脱敏错误体。

use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use utoipa::ToSchema;

static NEXT_CORRELATION_ID: AtomicU64 = AtomicU64::new(1);

/// Stable Studio API error categories shared by FRB and HTTP.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum StudioErrorCode {
    NotInitialized,
    RuntimeStopped,
    InstanceBusy,
    InvalidArgument,
    NotFound,
    Busy,
    Conflict,
    StaleRevision,
    PermissionDenied,
    Cancelled,
    CancellationTooLate,
    Overloaded,
    Unavailable,
    Protocol,
    Storage,
    Update,
    Internal,
}

impl StudioErrorCode {
    /// Stable camelCase label shared by logs, diagnostics and shutdown reports.
    pub const fn label(self) -> &'static str {
        match self {
            Self::NotInitialized => "notInitialized",
            Self::RuntimeStopped => "runtimeStopped",
            Self::InstanceBusy => "instanceBusy",
            Self::InvalidArgument => "invalidArgument",
            Self::NotFound => "notFound",
            Self::Busy => "busy",
            Self::Conflict => "conflict",
            Self::StaleRevision => "staleRevision",
            Self::PermissionDenied => "permissionDenied",
            Self::Cancelled => "cancelled",
            Self::CancellationTooLate => "cancellationTooLate",
            Self::Overloaded => "overloaded",
            Self::Unavailable => "unavailable",
            Self::Protocol => "protocol",
            Self::Storage => "storage",
            Self::Update => "update",
            Self::Internal => "internal",
        }
    }
}

/// 结构化错误详情里的稳定原因标签。
///
/// 错误类别说明「哪一类失败」，原因标签进一步说明同类别下的具体产品含义，使调用方不必解析
/// 提示文本即可区分「子会话由主智能体调度」「继续点已不再可用」等情况。标签与
/// [`StudioError::details`] 的 `reason` 字段一一对应。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum StudioErrorReason {
    AccountModelDiscoveryUnsupported,
    /// 用户不能对子会话发送、继续或提交；子会话的执行由主智能体调度。
    ChildThreadRequiresParentScheduling,
    /// 目标会话当前没有可认领的继续点。
    ContinuationUnavailable,
    /// 目标继续点已被另一次受理认领。
    ContinuationClaimed,
    /// 调用方冻结的继续点已经不是当前继续点。
    StaleContinuation,
    /// 调用方冻结的执行编号不是当前执行。
    StaleExecution,
    /// 该会话仍有当前执行或正在清理，不能开始新的轮次。
    ExecutionInProgress,
    /// 交互不允许由主会话转交处理。
    InteractionNotHosted,
    /// 交互版本已经不是调用方观察到的那个。
    StaleInteraction,
    /// 目标会话已归档：只读，不能执行、停止或决议其中的工作。
    ThreadArchived,
}

impl StudioErrorReason {
    /// 稳定 camelCase 标签，与序列化结果一致。
    pub const fn label(self) -> &'static str {
        match self {
            Self::AccountModelDiscoveryUnsupported => "accountModelDiscoveryUnsupported",
            Self::ChildThreadRequiresParentScheduling => "childThreadRequiresParentScheduling",
            Self::ContinuationUnavailable => "continuationUnavailable",
            Self::ContinuationClaimed => "continuationClaimed",
            Self::StaleContinuation => "staleContinuation",
            Self::StaleExecution => "staleExecution",
            Self::ExecutionInProgress => "executionInProgress",
            Self::InteractionNotHosted => "interactionNotHosted",
            Self::StaleInteraction => "staleInteraction",
            Self::ThreadArchived => "threadArchived",
        }
    }
}

/// A redacted API error. Internal diagnostics are correlated through `correlation_id` only.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, thiserror::Error, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
#[error("{message} (correlation id: {correlation_id})")]
pub struct StudioError {
    pub code: StudioErrorCode,
    pub message: String,
    pub retryable: bool,
    pub correlation_id: String,
    /// 动态详情；装箱后错误返回值保持窄小，JSON 形状不变（见 design/18 §18.2）。
    #[schema(value_type = Object)]
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub details: Option<Box<Value>>,
}

impl StudioError {
    pub fn new(code: StudioErrorCode, message: impl Into<String>, retryable: bool) -> Self {
        Self {
            code,
            message: message.into(),
            retryable,
            correlation_id: next_correlation_id(),
            details: None,
        }
    }

    pub fn with_details(mut self, details: Value) -> Self {
        self.details = Some(Box::new(details));
        self
    }

    /// Attaches the stable reason label and any extra structured facts.
    ///
    /// Only identities and reasons are carried: never prompt text, tool arguments or model output.
    pub fn with_reason(mut self, reason: StudioErrorReason, extra: Value) -> Self {
        let mut details = match extra {
            Value::Object(details) => details,
            _ => serde_json::Map::new(),
        };
        details.insert(
            "reason".to_owned(),
            Value::String(reason.label().to_owned()),
        );
        self.details = Some(Box::new(Value::Object(details)));
        self
    }

    /// The stable reason label this error carries, when it has one.
    pub fn reason(&self) -> Option<&str> {
        self.details
            .as_ref()
            .and_then(|details| details.get("reason"))
            .and_then(Value::as_str)
    }

    pub fn invalid_argument(message: impl Into<String>) -> Self {
        Self::new(StudioErrorCode::InvalidArgument, message, false)
    }

    pub fn not_found(resource: &'static str) -> Self {
        Self::new(
            StudioErrorCode::NotFound,
            format!("The requested Studio {resource} was not found"),
            false,
        )
    }

    pub fn instance_busy() -> Self {
        Self::new(
            StudioErrorCode::InstanceBusy,
            "Another Studio runtime already owns this home",
            true,
        )
    }

    pub fn internal() -> Self {
        Self::new(
            StudioErrorCode::Internal,
            "Studio could not complete the operation",
            false,
        )
    }

    pub fn storage() -> Self {
        Self::new(
            StudioErrorCode::Storage,
            "Studio storage is unavailable",
            true,
        )
    }
}

fn next_correlation_id() -> String {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |duration| duration.as_secs());
    let sequence = NEXT_CORRELATION_ID.fetch_add(1, Ordering::Relaxed);
    format!("studio-{timestamp:x}-{sequence:x}")
}

pub type StudioResult<T> = Result<T, StudioError>;

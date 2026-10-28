//! Studio API 的稳定错误分类与脱敏错误体。

use std::sync::atomic::{AtomicU64, Ordering};
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
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
    Superseded,
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
            Self::Superseded => "superseded",
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
    /// 用户不能对子会话发送、继续或提交；子会话的执行由主智能体调度。
    ChildThreadRequiresParentScheduling,
    /// 目标会话当前没有可认领的继续点。
    ContinuationUnavailable,
    /// 原继续操作已受理，但其回执当前尚不可读。
    ContinuationAccepted,
    /// 目标继续点已被另一次受理认领。
    ContinuationClaimed,
    /// 调用方冻结的继续点已经不是当前继续点。
    StaleContinuation,
    /// 调用方冻结的执行编号不是当前执行。
    StaleExecution,
    /// 执行所有者裁决时已无当前执行。
    NoExecution,
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
            Self::ChildThreadRequiresParentScheduling => "childThreadRequiresParentScheduling",
            Self::ContinuationUnavailable => "continuationUnavailable",
            Self::ContinuationAccepted => "continuationAccepted",
            Self::ContinuationClaimed => "continuationClaimed",
            Self::StaleContinuation => "staleContinuation",
            Self::StaleExecution => "staleExecution",
            Self::NoExecution => "noExecution",
            Self::ExecutionInProgress => "executionInProgress",
            Self::InteractionNotHosted => "interactionNotHosted",
            Self::StaleInteraction => "staleInteraction",
            Self::ThreadArchived => "threadArchived",
        }
    }
}

/// Exact, non-sensitive facts carried by stop/continue/hosted-interaction rejections.
/// The discriminator preserves the difference between rejection and accepted-but-not-durable.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum ControlFailureFacts {
    Unspecified,
    ChildThreadAction {
        thread_id: String,
        action: String,
        parent_thread_id: Option<String>,
    },
    ThreadAction {
        thread_id: String,
        action: String,
    },
    ExpectedExecution {
        thread_id: String,
        expected_execution_id: String,
    },
    Executing {
        thread_id: String,
        execution_id: String,
        phase: String,
    },
    ExpectedContinuation {
        thread_id: String,
        expected_continuation_id: String,
    },
    ContinuationAccepted {
        thread_id: String,
        operation_id: String,
        accepted: bool,
    },
    ContinuationOperation {
        thread_id: String,
        operation_id: String,
    },
    ContinuationPointConflict {
        thread_id: String,
        operation_id: String,
        expected_continuation_id: String,
        accepted_continuation_id: String,
    },
    ContinuationRouteConflict {
        thread_id: String,
        operation_id: String,
        expected_model_route_revision: u64,
        accepted_model_route_revision: u64,
    },
    StaleContinuation {
        thread_id: String,
        expected_continuation_id: String,
        current_continuation_id: String,
    },
    ClaimedContinuation {
        thread_id: String,
        continuation_id: String,
    },
    ChildInteraction {
        interaction_id: String,
        interaction_thread_id: String,
    },
    InteractionRevision {
        interaction_id: String,
        expected_revision: u64,
        current_revision: u64,
    },
    InteractionTerminal {
        interaction_id: String,
        current_revision: u64,
    },
    InteractionOperation {
        operation_id: String,
        interaction_id: String,
    },
    ChildHost {
        host_thread_id: String,
        host_is_child: bool,
    },
    InteractionHost {
        host_thread_id: String,
        interaction_thread_id: String,
    },
    DecisionDurability {
        interaction_id: String,
        decision_saved: bool,
    },
    UnreadableDecision {
        thread_id: String,
        interaction_id: String,
    },
    DecisionIdentity {
        interaction_id: String,
        current_revision: u64,
        operation_identity_recorded: bool,
    },
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
    /// 装箱避免错误类型本身过大（`clippy::result_large_err`）；`serde` 表示不变。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub details: Option<Box<StudioErrorDetails>>,
}

/// Stable diagnostic fields. Arbitrary JSON is not part of the error contract.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum StudioErrorDetails {
    Startup {
        step: String,
        kind: StartupFailureKind,
    },
    Revision {
        expected: u64,
        actual: u64,
    },
    SshAuthentication {
        password_offered: Option<bool>,
    },
    Reason {
        reason: String,
    },
    Control {
        reason: String,
        facts: ControlFailureFacts,
    },
    Identity {
        identity: String,
    },
    TimelineRevision {
        item_id: String,
        field: String,
        revision: u64,
    },
    Validation {
        issues: Vec<crate::ThreadModeValidationIssue>,
    },
    Thread {
        thread_id: String,
    },
    ResourceLimit {
        resource: String,
        capacity: u64,
    },
    /// Bot provider diagnostic: only stable published fields, never arbitrary JSON.
    Bot {
        code: String,
        platform_code: Option<String>,
        guidance: Option<String>,
    },
    /// A stale delegation/statistics cursor bound to the catalog revision it was issued for.
    CatalogRevision {
        revision: u64,
    },
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum StartupFailureKind {
    ModeDefinitions,
    Migration,
    PersistentData,
    Environment,
    Cancelled,
    Internal,
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

    pub fn with_details(mut self, details: StudioErrorDetails) -> Self {
        self.details = Some(Box::new(details));
        self
    }

    /// Attaches non-sensitive, typed facts without changing admission or execution state.
    pub fn with_reason(self, reason: StudioErrorReason, facts: ControlFailureFacts) -> Self {
        self.with_details(StudioErrorDetails::Control {
            reason: reason.label().to_owned(),
            facts,
        })
    }

    pub fn reason(&self) -> Option<&str> {
        match self.details.as_deref() {
            Some(
                StudioErrorDetails::Reason { reason } | StudioErrorDetails::Control { reason, .. },
            ) => Some(reason),
            _ => None,
        }
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

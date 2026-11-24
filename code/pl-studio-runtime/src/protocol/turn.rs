//! Turn aggregate and its canonical lifecycle state machine.

use serde::{Deserialize, Serialize};

use crate::{BudgetLimitSnapshot, TurnFailure};

/// Thread 中一次由明确输入启动的执行。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Turn {
    /// Accepted input associated with this execution attempt, when started from a queue.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub input_id: Option<String>,
    pub id: String,
    pub thread_id: String,
    pub revision: u64,
    pub state: TurnState,
    pub updated_at: i64,
}

impl Turn {
    /// 创建排队中的 Turn。
    pub fn queued(id: impl Into<String>, thread_id: impl Into<String>, queued_at: i64) -> Self {
        Self {
            input_id: None,
            id: id.into(),
            thread_id: thread_id.into(),
            revision: 0,
            state: TurnState::Queued(QueuedTurnState::new(queued_at)),
            updated_at: queued_at,
        }
    }

    /// 返回 Turn 开始执行的时间；排队期间可能为空。
    pub fn started_at(&self) -> Option<i64> {
        self.state.started_at()
    }

    /// 返回终态完成时间。
    pub fn completed_at(&self) -> Option<i64> {
        self.state.completed_at()
    }

    /// 返回运行阶段。
    pub fn phase(&self) -> Option<TurnPhase> {
        self.state.phase()
    }
}

/// Turn 执行期间的可展示活动阶段。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum TurnPhase {
    Preparing,
    Thinking,
    Responding,
    Planning,
    RunningTool,
    Persisting,
}

/// Turn 正常完成的业务边界。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum TurnCompletion {
    Normal,
    InteractionRequested,
}

/// Turn 被取消的强类型原因。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum TurnCancellationCause {
    /// Cancellation was recorded without a product-specific initiating cause.
    Unspecified,
    UserRequested,
    RuntimeShutdown,
    AgentClosed,
    Interrupted,
    Recovery,
    Coalesced {
        target_turn_id: String,
    },
}

/// 预算终态后的上下文压缩结果。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum TurnRolloverOutcome {
    NotAttempted,
    Succeeded,
    Failed { error: String },
}

pl_protocol::impl_labeled_enum!(
    TurnPhase,
    "TurnPhase",
    [
        TurnPhase::Preparing => "preparing",
        TurnPhase::Thinking => "thinking",
        TurnPhase::Responding => "responding",
        TurnPhase::Planning => "planning",
        TurnPhase::RunningTool => "runningTool",
        TurnPhase::Persisting => "persisting",
    ]
);

/// turn id 的非空透明字符串标识。
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct TurnId(String);

impl TurnId {
    /// 校验并创建标识。
    pub fn new(value: impl Into<String>) -> crate::Result<Self> {
        let value = value.into();
        if value.trim().is_empty() {
            return Err(crate::PureError::ConfigError(
                "turn id cannot be empty".into(),
            ));
        }
        Ok(Self(value))
    }

    /// 返回标识文本。
    pub fn as_str(&self) -> &str {
        &self.0
    }

    /// 消费标识并返回字符串。
    pub fn into_string(self) -> String {
        self.0
    }
}

impl std::fmt::Display for TurnId {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.0)
    }
}

impl std::str::FromStr for TurnId {
    type Err = crate::PureError;

    fn from_str(value: &str) -> crate::Result<Self> {
        Self::new(value)
    }
}

impl serde::Serialize for TurnId {
    fn serialize<S>(&self, serializer: S) -> std::result::Result<S::Ok, S::Error>
    where
        S: serde::Serializer,
    {
        serializer.serialize_str(&self.0)
    }
}

impl<'de> serde::Deserialize<'de> for TurnId {
    fn deserialize<D>(deserializer: D) -> std::result::Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let value = <String as serde::Deserialize>::deserialize(deserializer)?;
        Self::new(value).map_err(serde::de::Error::custom)
    }
}

// Turn lifecycle state payloads.

/// Turn 的唯一 canonical 生命周期状态。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum TurnState {
    Queued(QueuedTurnState),
    Running(RunningTurnState),
    Completed(CompletedTurnState),
    Cancelled(CancelledTurnState),
    Failed(FailedTurnState),
    BudgetLimited(BudgetLimitedTurnState),
}

impl TurnState {
    pub fn started_at(&self) -> Option<i64> {
        match self {
            Self::Queued(_) => None,
            Self::Running(state) => Some(state.started_at()),
            Self::Completed(state) => state.started_at(),
            Self::Cancelled(state) => state.started_at(),
            Self::Failed(state) => state.started_at(),
            Self::BudgetLimited(state) => state.started_at(),
        }
    }

    pub fn completed_at(&self) -> Option<i64> {
        match self {
            Self::Queued(_) | Self::Running(_) => None,
            Self::Completed(state) => Some(state.completed_at()),
            Self::Cancelled(state) => Some(state.completed_at()),
            Self::Failed(state) => Some(state.completed_at()),
            Self::BudgetLimited(state) => Some(state.completed_at()),
        }
    }

    pub fn phase(&self) -> Option<TurnPhase> {
        match self {
            Self::Running(state) => Some(state.phase()),
            Self::Queued(_)
            | Self::Completed(_)
            | Self::Cancelled(_)
            | Self::Failed(_)
            | Self::BudgetLimited(_) => None,
        }
    }

    pub fn is_terminal(&self) -> bool {
        match self {
            Self::Queued(_) | Self::Running(_) => false,
            Self::Completed(_) | Self::Cancelled(_) | Self::Failed(_) | Self::BudgetLimited(_) => {
                true
            }
        }
    }
}

/// 排队等待执行的 Turn。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct QueuedTurnState {
    queued_at: i64,
}

impl QueuedTurnState {
    pub fn new(queued_at: i64) -> Self {
        Self { queued_at }
    }

    pub fn queued_at(&self) -> i64 {
        self.queued_at
    }
}

/// 正在执行的 Turn。
/// 正在执行的 Turn。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct RunningTurnState {
    started_at: i64,
    phase: TurnPhase,
}

impl RunningTurnState {
    pub fn new(started_at: i64, phase: TurnPhase) -> Self {
        Self { started_at, phase }
    }

    pub fn started_at(&self) -> i64 {
        self.started_at
    }

    pub fn phase(&self) -> TurnPhase {
        self.phase
    }
}

/// 正常结束的 Turn。
/// 正常结束的 Turn。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct CompletedTurnState {
    started_at: Option<i64>,
    completed_at: i64,
    completion: TurnCompletion,
}

impl CompletedTurnState {
    pub fn new(started_at: Option<i64>, completed_at: i64, completion: TurnCompletion) -> Self {
        Self {
            started_at,
            completed_at,
            completion,
        }
    }

    pub fn started_at(&self) -> Option<i64> {
        self.started_at
    }

    pub fn completed_at(&self) -> i64 {
        self.completed_at
    }

    pub fn completion(&self) -> TurnCompletion {
        self.completion
    }
}

/// 被显式取消的 Turn。
/// 被显式取消的 Turn。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct CancelledTurnState {
    started_at: Option<i64>,
    requested_at: i64,
    completed_at: i64,
    cause: TurnCancellationCause,
}

impl CancelledTurnState {
    pub fn new(
        started_at: Option<i64>,
        requested_at: i64,
        completed_at: i64,
        cause: TurnCancellationCause,
    ) -> Self {
        Self {
            started_at,
            requested_at,
            completed_at,
            cause,
        }
    }

    pub fn started_at(&self) -> Option<i64> {
        self.started_at
    }

    pub fn requested_at(&self) -> i64 {
        self.requested_at
    }

    pub fn completed_at(&self) -> i64 {
        self.completed_at
    }

    pub fn cause(&self) -> &TurnCancellationCause {
        &self.cause
    }
}

/// 失败结束的 Turn。
/// 失败结束的 Turn。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct FailedTurnState {
    started_at: Option<i64>,
    completed_at: i64,
    failure: TurnFailure,
}

impl FailedTurnState {
    pub fn new(started_at: Option<i64>, completed_at: i64, failure: TurnFailure) -> Self {
        Self {
            started_at,
            completed_at,
            failure,
        }
    }

    pub fn started_at(&self) -> Option<i64> {
        self.started_at
    }

    pub fn completed_at(&self) -> i64 {
        self.completed_at
    }

    pub fn failure(&self) -> &TurnFailure {
        &self.failure
    }
}

/// 达到预算上限后结束的 Turn。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct BudgetLimitedTurnState {
    started_at: Option<i64>,
    completed_at: i64,
    limit: BudgetLimitSnapshot,
    rollover: TurnRolloverOutcome,
}

impl BudgetLimitedTurnState {
    pub fn new(
        started_at: Option<i64>,
        completed_at: i64,
        limit: BudgetLimitSnapshot,
        rollover: TurnRolloverOutcome,
    ) -> Self {
        Self {
            started_at,
            completed_at,
            limit,
            rollover,
        }
    }

    pub fn started_at(&self) -> Option<i64> {
        self.started_at
    }

    pub fn completed_at(&self) -> i64 {
        self.completed_at
    }

    pub fn limit(&self) -> &BudgetLimitSnapshot {
        &self.limit
    }

    pub fn rollover(&self) -> &TurnRolloverOutcome {
        &self.rollover
    }
}

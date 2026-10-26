//! 当前执行身份与停止资格：目录级轻状态只描述「这一行现在能停止什么」。
//!
//! 执行身份由 core 在选定工作、等待保存或准备模型之前分配，进入实际轮次后不变。它不是
//! `activeTurn` 的可空投影：准备期、等待准入期与清理期同样可寻址，因此产品停止命令携带
//! 这里的 `id`，而不是当前轮次编号。

use serde::{Deserialize, Serialize};

/// 一个会话当前拥有的执行；同一执行进入实际轮次后编号不变。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AgentExecution {
    id: String,
    phase: AgentExecutionPhase,
    /// 已真正进入轮次时才有值；准备期为空，编号本身不变。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    turn_id: Option<String>,
}

impl AgentExecution {
    pub fn new(id: impl Into<String>, phase: AgentExecutionPhase, turn_id: Option<String>) -> Self {
        Self {
            id: id.into(),
            phase,
            turn_id,
        }
    }

    pub fn id(&self) -> &str {
        &self.id
    }

    pub fn phase(&self) -> AgentExecutionPhase {
        self.phase
    }

    pub fn turn_id(&self) -> Option<&str> {
        self.turn_id.as_deref()
    }
}

/// 执行当前所处阶段；准备与清理阶段和运行中的轮次一样可以被停止。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum AgentExecutionPhase {
    /// 已经选定工作，还没有建立轮次或等待保存。
    Preparing,
    /// 等待已认领的事实达到保存水位。
    AwaitingStorage,
    /// 等待轮次准入。
    AwaitingAdmission,
    /// 轮次正在 owner 内执行。
    Running,
    /// 停止已受理，该执行正在收束。
    Stopping,
}

/// 该会话当前仍然欠着的继续点；`None` 表示没有可继续的工作。
///
/// 它是执行事实的投影，不是客户端或本地可推导的资格：第一次点击「继续」所需的
/// `id` 只能来自这里，不能被猜出或本地生成。`claimed` 说明这个点是否已被某个操作认领，
/// 客户端据此区分「可以继续」与「继续已受理、正在准备」。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContinuationView {
    /// 稳定且不复用的继续点编号，用于拒绝过时点击。
    id: String,
    /// 被中断的轮次；尚未建立轮次就停止时为空。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    source_turn_id: Option<String>,
    /// 打断原因；核心没有确立原因时为空，不伪造。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    reason: Option<ContinuationReason>,
    created_at: i64,
    /// 是否已有输入或消息认领了该点；认领不等于已生效。
    claimed: bool,
}

impl ContinuationView {
    pub fn new(
        id: impl Into<String>,
        source_turn_id: Option<String>,
        reason: Option<ContinuationReason>,
        created_at: i64,
        claimed: bool,
    ) -> Self {
        Self {
            id: id.into(),
            source_turn_id,
            reason,
            created_at,
            claimed,
        }
    }

    pub fn id(&self) -> &str {
        &self.id
    }

    pub fn source_turn_id(&self) -> Option<&str> {
        self.source_turn_id.as_deref()
    }

    pub fn reason(&self) -> Option<ContinuationReason> {
        self.reason
    }

    pub fn created_at(&self) -> i64 {
        self.created_at
    }

    pub fn claimed(&self) -> bool {
        self.claimed
    }
}

/// 为什么这个会话还欠着工作；只记录打断本身确立过的原因。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, utoipa::ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum ContinuationReason {
    /// 用户停止了该执行。
    UserStop,
    /// 宿主在仍有工作欠着时关闭了会话。
    HostShutdown,
    /// 恢复发现执行被一个已消失的进程中断。
    ProcessInterrupted,
    /// 执行在模型步数预算处停止。
    StepLimit,
    /// 执行以类型化错误失败。
    ExecutionFailed,
}

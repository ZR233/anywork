//! Agent 可观察生命周期的唯一协议 union。

use serde::{Deserialize, Serialize};

use crate::TurnId;

/// Agent 的唯一 canonical 生命周期状态。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum AgentState {
    Idle(IdleAgentState),
    Running(RunningAgentState),
    WaitingInteraction(WaitingInteractionAgentState),
    Closing(ClosingAgentState),
    Closed(ClosedAgentState),
}

impl AgentState {
    /// 创建 idle Agent 状态。
    pub fn idle() -> Self {
        Self::Idle(IdleAgentState::new())
    }

    /// 返回当前 active 或等待交互的 Turn。
    pub fn turn_id(&self) -> Option<&TurnId> {
        match self {
            Self::Running(state) => Some(state.turn_id()),
            Self::WaitingInteraction(state) => Some(state.turn_id()),
            Self::Idle(_) | Self::Closing(_) | Self::Closed(_) => None,
        }
    }

    /// 返回 Agent 是否已停止执行并可供等待方收束。
    pub fn is_settled(&self) -> bool {
        matches!(self, Self::Idle(_) | Self::Closed(_))
    }
}

/// 没有 active Turn 的 Agent。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct IdleAgentState {}

impl IdleAgentState {
    pub fn new() -> Self {
        Self {}
    }
}

/// 正在执行模型或本地编排的 Agent。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RunningAgentState {
    turn_id: TurnId,
}

impl RunningAgentState {
    pub fn new(turn_id: TurnId) -> Self {
        Self { turn_id }
    }

    pub fn turn_id(&self) -> &TurnId {
        &self.turn_id
    }
}

/// 等待指定用户 Interaction 的 Agent。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct WaitingInteractionAgentState {
    turn_id: TurnId,
    interaction_id: String,
}

impl WaitingInteractionAgentState {
    pub fn new(turn_id: TurnId, interaction_id: String) -> Self {
        Self {
            turn_id,
            interaction_id,
        }
    }

    pub fn turn_id(&self) -> &TurnId {
        &self.turn_id
    }

    pub fn interaction_id(&self) -> &str {
        &self.interaction_id
    }
}

/// 已拒绝新工作、正在释放资源的 Agent。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct ClosingAgentState;

impl ClosingAgentState {
    pub fn new() -> Self {
        Self
    }
}

/// 已完成资源释放的 Agent 终态。
#[derive(Debug, Clone, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct ClosedAgentState;

impl ClosedAgentState {
    pub fn new() -> Self {
        Self
    }
}

//! Runtime health projections shared by the Studio bridge.
//!
//! Workflow state is intentionally not duplicated here: it is projected from the
//! canonical `AgentWorkingState` into `pl_protocol::ThreadRuntimeSnapshot`.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct StudioAgentDirectoryEntry {
    pub id: String,
    pub thread_id: String,
    pub root_thread_id: String,
    pub path: String,
    pub parent_path: Option<String>,
    pub role: String,
    pub delegation_mode: pl_protocol::DelegationMode,
    pub delegation_preference: pl_protocol::DelegationPreference,
    pub frozen_model: Option<pl_protocol::studio::NewThreadModelRoute>,
    pub task: String,
    pub summary: Option<String>,
    pub depth: u32,
    pub state: pl_protocol::AgentState,
    /// 该成员当前拥有的执行；未装载、无当前执行时为 `None`。
    ///
    /// 它来自会话执行事实，不是 `activeTurn` 的可空投影：准备、等待准入与清理期同样有身份，
    /// 所以列表可以在没有轮次编号时仍给出正确的停止目标。
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub execution: Option<pl_protocol::AgentExecution>,
    /// 用户是否可以对这一行发起精确停止。
    ///
    /// 由当前执行、生命周期与显式关闭意图派生；`state` 仍是业务状态，两者不互相推断。
    pub can_stop: bool,
    /// 该成员存在继续点且尚未被任何操作认领：用户已停止/执行被中断，等待主智能体调度。
    ///
    /// 只表达这一个执行事实，`false` 同时覆盖「从未运行」「正常完成」和「继续已受理」。它是
    /// 目录级轻状态，完整继续点视图仍只在该会话自己的运行时快照里发布。
    pub awaiting_scheduling: bool,
    pub updated_at: i64,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StudioMcpHealth {
    pub mcp_servers: Vec<StudioMcpServer>,
    pub active_mcp_servers: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StudioLspHealth {
    pub lsp_servers: Vec<StudioLspServer>,
    pub active_lsp_servers: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StudioMcpServer {
    pub id: String,
    pub transport: String,
    pub endpoint: String,
    pub source_kind: String,
    pub mutation_policy: String,
    pub state: crate::StudioMcpServerState,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct StudioLspServer {
    pub id: String,
    pub display_name: String,
    #[serde(default)]
    pub extensions: Vec<String>,
    #[serde(default)]
    pub language_ids: Vec<String>,
    pub state: crate::StudioLspServerState,
}

/// Observable startup milestones before the normal product stream is available.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum StudioStartupStage {
    Preparing,
    WaitingForSteps,
    ClosingResources,
    BackingUp,
    Resetting,
    StartingServices,
    OpeningStorage,
    LoadingConfiguration,
    ReadingProjects,
    PreparingResources,
    Ready,
    Failed,
}

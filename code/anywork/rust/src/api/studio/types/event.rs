use serde::{Deserialize, Serialize};

use super::{
    BridgeAgentDirectoryState, BridgeBotsStateSnapshot, BridgeLspStateSnapshot,
    BridgeMcpCatalogSnapshot, BridgeModelCatalogStateSnapshot, BridgePersistenceStateSnapshot,
    BridgeProjectDirectoryState, BridgeRecoveryStateSnapshot, BridgeSettingsConfigStateSnapshot,
    BridgeSkillsStateSnapshot, BridgeThreadLspStateSnapshot, BridgeThreadMcpStateSnapshot,
    BridgeThreadModeCatalogSnapshot, BridgeUpdaterStateSnapshot,
};

/// Flutter Bridge 的 Studio 产品事件信封。
///
/// `sequence` 只检测 transport lag；payload 中完整 snapshot 的领域 revision 决定替换顺序。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct BridgeProductEventEnvelope {
    pub event_id: String,
    pub sequence: u64,
    pub created_at: i64,
    pub payload: BridgeProductEventPayload,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub enum BridgeProductEventPayload {
    ProjectDirectoryChanged(BridgeProjectDirectoryState),
    AgentDirectoryChanged(BridgeAgentDirectoryState),
    SettingsConfigStateChanged(Box<BridgeSettingsConfigStateSnapshot>),
    ModelCatalogStateChanged(Box<BridgeModelCatalogStateSnapshot>),
    RecoveryStateChanged(BridgeRecoveryStateSnapshot),
    McpCatalogChanged(BridgeMcpCatalogSnapshot),
    ThreadMcpStateChanged(BridgeThreadMcpStateSnapshot),
    ThreadLspStateChanged(BridgeThreadLspStateSnapshot),
    LspStateChanged(BridgeLspStateSnapshot),
    SkillsStateChanged(BridgeSkillsStateSnapshot),
    ThreadModeCatalogChanged(BridgeThreadModeCatalogSnapshot),
    SessionCostsChanged(Box<super::response::BridgeSessionCostsState>),
    ChildInteractionsChanged(Box<super::product_topic::BridgeChildInteractionsState>),
    UpdaterStateChanged(BridgeUpdaterStateSnapshot),
    PersistenceStateChanged(BridgePersistenceStateSnapshot),
    PersistenceQueueStateChanged(Box<super::response::BridgePersistenceQueueStateSnapshot>),
    AgentProfilesStateChanged(Box<super::response::BridgeAgentProfilesStateSnapshot>),
    BotsStateChanged(Box<BridgeBotsStateSnapshot>),
}

/// 一次关机进度的精确阶段状态；只有持久化刷新阶段携带 pending commit 数。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum BridgeShutdownProgress {
    StoppingSubscriptions,
    CancellingTurns,
    FlushingPersistence { pending_commits: u64 },
    StoppingAgents,
    StoppingMcp,
    StoppingLsp,
    Stopped,
}

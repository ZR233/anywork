//! Studio 关机进度的精确阶段状态。

use serde::{Deserialize, Serialize};

/// Studio 关机的固定阶段序列；只有刷新持久化阶段携带 pending commit 数。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum StudioShutdownProgress {
    StoppingSubscriptions(StoppingSubscriptionsProgress),
    CancellingTurns(CancellingTurnsProgress),
    FlushingPersistence(FlushingPersistenceProgress),
    StoppingAgents(StoppingAgentsProgress),
    StoppingMcp(StoppingMcpProgress),
    StoppingLsp(StoppingLspProgress),
    Stopped(StoppedProgress),
}

impl StudioShutdownProgress {
    pub fn is_stopped(self) -> bool {
        matches!(self, Self::Stopped(_))
    }
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct CancellingTurnsProgress;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FlushingPersistenceProgress {
    pending_commits: u64,
}

impl FlushingPersistenceProgress {
    pub fn new(pending_commits: u64) -> Self {
        Self { pending_commits }
    }

    pub fn pending_commits(self) -> u64 {
        self.pending_commits
    }
}

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct StoppedProgress;

/// 正在停止协作 Agent。
#[derive(Debug, Clone, Copy, Default, serde::Serialize, serde::Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct StoppingAgentsProgress;

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct StoppingLspProgress;

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct StoppingMcpProgress;

#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(deny_unknown_fields)]
pub struct StoppingSubscriptionsProgress;

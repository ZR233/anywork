//! Narrow startup result and immutable startup details.
use super::super::source::SourceStateErrorRead;
use crate::studio::ReadText;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub enum StartupStage {
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
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub enum StartupCloseReason {
    Requested,
    AttemptReplaced,
    Completed,
    RuntimeStopped,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum StartupProgressFrame {
    Data {
        delivery_sequence: u64,
        stage: StartupStage,
    },
    Failure {
        error: crate::studio::StudioError,
    },
    Closed {
        reason: StartupCloseReason,
    },
}
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RuntimeStartupReadRef {
    pub entry: u64,
    pub revision: u64,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RuntimeReady {
    pub revision: u64,
    pub ready_at: i64,
    pub details: RuntimeStartupReadRef,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RuntimeStartupScopeIdentity {
    pub scope_id: String,
    pub owner_epoch: String,
    pub attempt_id: u64,
    pub revision: u64,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    content = "data",
    rename_all = "camelCase",
    rename_all_fields = "camelCase",
    deny_unknown_fields
)]
pub enum RuntimeStateRead {
    Uninitialized {
        at: i64,
    },
    Initializing {
        at: i64,
    },
    Ready {
        at: i64,
    },
    ShuttingDown {
        at: i64,
    },
    Stopped {
        at: i64,
    },
    Failed {
        failed_at: i64,
        error: SourceStateErrorRead,
    },
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StartupRecoveryRead {
    pub backup_path: ReadText,
    pub reason: ReadText,
    pub created_at: i64,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StartupActiveTurnRead {
    pub thread_id: ReadText,
    pub turn_id: ReadText,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RuntimeStartupReadHeader {
    pub scope: RuntimeStartupScopeIdentity,
    pub reference: RuntimeStartupReadRef,
    pub revision: u64,
    pub state: RuntimeStateRead,
    pub startup_recovery: Option<StartupRecoveryRead>,
    pub active_turn_count: u64,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StartupActiveTurnReadPage {
    pub offset: u64,
    pub total: u64,
    pub items: Vec<StartupActiveTurnRead>,
    pub next_offset: Option<u64>,
}

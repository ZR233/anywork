//! Studio runtime 自身生命周期；状态修改只能通过领域命令。

use std::sync::{Arc, Mutex};

use crate::StateError;
use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::studio::ids::unix_seconds;

/// Studio runtime 当前活动 turn。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioActiveTurn {
    pub thread_id: String,
    pub turn_id: String,
}

/// Studio runtime 的 canonical 生命周期状态。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum StudioRuntimeLifecycleState {
    Uninitialized(UninitializedStudioRuntime),
    Initializing(InitializingStudioRuntime),
    Ready(ReadyStudioRuntime),
    ShuttingDown(ShuttingDownStudioRuntime),
    Stopped(StoppedStudioRuntime),
    Failed(FailedStudioRuntime),
}

/// Studio runtime 状态种类的只读投影。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StudioRuntimeStateKind {
    Uninitialized,
    Initializing,
    Ready,
    ShuttingDown,
    Stopped,
    Failed,
}

impl StudioRuntimeLifecycleState {
    pub fn kind(&self) -> StudioRuntimeStateKind {
        match self {
            Self::Uninitialized(_) => StudioRuntimeStateKind::Uninitialized,
            Self::Initializing(_) => StudioRuntimeStateKind::Initializing,
            Self::Ready(_) => StudioRuntimeStateKind::Ready,
            Self::ShuttingDown(_) => StudioRuntimeStateKind::ShuttingDown,
            Self::Stopped(_) => StudioRuntimeStateKind::Stopped,
            Self::Failed(_) => StudioRuntimeStateKind::Failed,
        }
    }

    pub fn updated_at(&self) -> i64 {
        match self {
            Self::Uninitialized(state) => state.created_at(),
            Self::Initializing(state) => state.started_at(),
            Self::Ready(state) => state.ready_at(),
            Self::ShuttingDown(state) => state.started_at(),
            Self::Stopped(state) => state.stopped_at(),
            Self::Failed(state) => state.failed_at(),
        }
    }

    pub fn is_ready(&self) -> bool {
        matches!(self, Self::Ready(_))
    }

    pub fn is_stopped(&self) -> bool {
        matches!(self, Self::Stopped(_))
    }
}

/// 可以改变 runtime 生命周期的命令。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StudioRuntimeCommand {
    BeginInitialize {
        expected_revision: u64,
        at: i64,
    },
    FinishInitialize {
        expected_revision: u64,
        at: i64,
    },
    BeginShutdown {
        expected_revision: u64,
        at: i64,
    },
    FinishShutdown {
        expected_revision: u64,
        at: i64,
    },
    FailShutdown {
        expected_revision: u64,
        at: i64,
        error: StateError,
    },
}

impl StudioRuntimeCommand {
    fn expected_revision(&self) -> u64 {
        match self {
            Self::BeginInitialize {
                expected_revision, ..
            }
            | Self::FinishInitialize {
                expected_revision, ..
            }
            | Self::BeginShutdown {
                expected_revision, ..
            }
            | Self::FinishShutdown {
                expected_revision, ..
            }
            | Self::FailShutdown {
                expected_revision, ..
            } => *expected_revision,
        }
    }
}

/// runtime 生命周期的纯转换结果。
#[derive(Debug, Clone, PartialEq, Eq)]
struct StudioRuntimeTransitionDecision {
    pub next_state: StudioRuntimeLifecycleState,
    pub changed: bool,
}

/// runtime 生命周期转换错误。
#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub(in crate::studio) enum StudioRuntimeTransitionError {
    #[error("Studio runtime revision is stale: expected {expected}, actual {actual}")]
    StaleRevision {
        expected: u64,
        actual: u64,
        command: StudioRuntimeCommand,
    },
    #[error("Studio runtime in {current:?} rejects command {command:?}")]
    IllegalTransition {
        current: StudioRuntimeStateKind,
        command: StudioRuntimeCommand,
    },
}

/// UI 与 adapter 读取的完整 runtime 聚合快照。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StudioRuntimeSnapshot {
    pub revision: u64,
    pub state: StudioRuntimeLifecycleState,
    pub active_turns: Vec<StudioActiveTurn>,
    pub startup_recovery: Option<crate::StudioStartupRecovery>,
}

impl StudioRuntimeSnapshot {
    fn decide(
        &self,
        command: StudioRuntimeCommand,
    ) -> Result<StudioRuntimeTransitionDecision, StudioRuntimeTransitionError> {
        if command.expected_revision() != self.revision {
            return Err(StudioRuntimeTransitionError::StaleRevision {
                expected: command.expected_revision(),
                actual: self.revision,
                command,
            });
        }
        let next_state = match (&self.state, &command) {
            (
                StudioRuntimeLifecycleState::Uninitialized(_)
                | StudioRuntimeLifecycleState::Stopped(_)
                | StudioRuntimeLifecycleState::Failed(_),
                StudioRuntimeCommand::BeginInitialize { at, .. },
            ) => StudioRuntimeLifecycleState::Initializing(InitializingStudioRuntime::new(*at)),
            (
                StudioRuntimeLifecycleState::Initializing(_),
                StudioRuntimeCommand::FinishInitialize { at, .. },
            ) => StudioRuntimeLifecycleState::Ready(ReadyStudioRuntime::new(*at)),
            (
                StudioRuntimeLifecycleState::Ready(_) | StudioRuntimeLifecycleState::Failed(_),
                StudioRuntimeCommand::BeginShutdown { at, .. },
            ) => StudioRuntimeLifecycleState::ShuttingDown(ShuttingDownStudioRuntime::new(*at)),
            (
                StudioRuntimeLifecycleState::ShuttingDown(_),
                StudioRuntimeCommand::FinishShutdown { at, .. },
            ) => StudioRuntimeLifecycleState::Stopped(StoppedStudioRuntime::new(*at)),
            (
                StudioRuntimeLifecycleState::ShuttingDown(_),
                StudioRuntimeCommand::FailShutdown { at, error, .. },
            ) => StudioRuntimeLifecycleState::Failed(FailedStudioRuntime::new(*at, error.clone())),
            _ => {
                return Err(StudioRuntimeTransitionError::IllegalTransition {
                    current: self.state.kind(),
                    command,
                });
            }
        };
        Ok(StudioRuntimeTransitionDecision {
            changed: next_state != self.state,
            next_state,
        })
    }
}

/// 进程内 runtime 状态 owner。
#[derive(Debug, Clone)]
pub struct StudioRuntimeState {
    inner: Arc<Mutex<StudioRuntimeSnapshot>>,
}

impl StudioRuntimeState {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(Mutex::new(StudioRuntimeSnapshot {
                revision: 0,
                state: StudioRuntimeLifecycleState::Uninitialized(UninitializedStudioRuntime::new(
                    unix_seconds(),
                )),
                active_turns: Vec::new(),
                startup_recovery: None,
            })),
        }
    }

    pub fn snapshot(&self) -> StudioRuntimeSnapshot {
        self.inner
            .lock()
            .expect("runtime state mutex poisoned")
            .clone()
    }

    pub(in crate::studio) fn apply(
        &self,
        command: StudioRuntimeCommand,
    ) -> Result<StudioRuntimeSnapshot, StudioRuntimeTransitionError> {
        let mut current = self.inner.lock().expect("runtime state mutex poisoned");
        let decision = current.decide(command)?;
        if decision.changed {
            current.revision = current.revision.saturating_add(1);
            current.state = decision.next_state;
        }
        Ok(current.clone())
    }
}

impl Default for StudioRuntimeState {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FailedStudioRuntime {
    failed_at: i64,
    error: StateError,
}

impl FailedStudioRuntime {
    pub(super) fn new(failed_at: i64, error: StateError) -> Self {
        Self { failed_at, error }
    }

    pub fn failed_at(&self) -> i64 {
        self.failed_at
    }

    pub fn error(&self) -> &StateError {
        &self.error
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct InitializingStudioRuntime {
    started_at: i64,
}

impl InitializingStudioRuntime {
    pub(super) fn new(started_at: i64) -> Self {
        Self { started_at }
    }

    pub fn started_at(&self) -> i64 {
        self.started_at
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReadyStudioRuntime {
    ready_at: i64,
}

impl ReadyStudioRuntime {
    pub(super) fn new(ready_at: i64) -> Self {
        Self { ready_at }
    }

    pub fn ready_at(&self) -> i64 {
        self.ready_at
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ShuttingDownStudioRuntime {
    started_at: i64,
}

impl ShuttingDownStudioRuntime {
    pub(super) fn new(started_at: i64) -> Self {
        Self { started_at }
    }

    pub fn started_at(&self) -> i64 {
        self.started_at
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StoppedStudioRuntime {
    stopped_at: i64,
}

impl StoppedStudioRuntime {
    pub(super) fn new(stopped_at: i64) -> Self {
        Self { stopped_at }
    }

    pub fn stopped_at(&self) -> i64 {
        self.stopped_at
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UninitializedStudioRuntime {
    created_at: i64,
}

impl UninitializedStudioRuntime {
    pub(super) fn new(created_at: i64) -> Self {
        Self { created_at }
    }

    pub fn created_at(&self) -> i64 {
        self.created_at
    }
}

//! 外部资源观察状态；每个 variant 只持有当前阶段合法的字段。

use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::StateError;

/// 一个可刷新外部资源的 canonical 生命周期。
///
/// 无可用值的阶段与保留 last-known value 的阶段在类型层分离。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub enum ObservedResource<T> {
    Uninitialized(UninitializedResource),
    Loading(LoadingResource),
    Ready(ReadyResource<T>),
    Refreshing(RefreshingResource<T>),
    Stale(StaleResource<T>),
    Degraded(DegradedResource<T>),
    Failed(FailedResource),
    Stopped(StoppedResource),
}

/// 外部资源的穷尽状态种类。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ObservedResourceKind {
    Uninitialized,
    Loading,
    Ready,
    Refreshing,
    Stale,
    Degraded,
    Failed,
    Stopped,
}

/// 可以改变外部资源生命周期的领域命令。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ObservedResourceCommand<T> {
    Begin {
        expected_revision: u64,
        operation: StateOperation,
        operation_id: String,
        started_at: i64,
    },
    Succeed {
        expected_revision: u64,
        updated_at: i64,
        last_checked_at: Option<i64>,
        value: T,
    },
    Observe {
        expected_revision: u64,
        observed_at: i64,
        last_checked_at: Option<i64>,
        value: T,
    },
    MarkStale {
        expected_revision: u64,
        stale_at: i64,
        value: T,
    },
    Fail {
        expected_revision: u64,
        failed_at: i64,
        error: StateError,
    },
    Stop {
        expected_revision: u64,
        stopped_at: i64,
    },
}

impl<T> ObservedResourceCommand<T> {
    fn expected_revision(&self) -> u64 {
        match self {
            Self::Begin {
                expected_revision, ..
            }
            | Self::Succeed {
                expected_revision, ..
            }
            | Self::Observe {
                expected_revision, ..
            }
            | Self::MarkStale {
                expected_revision, ..
            }
            | Self::Fail {
                expected_revision, ..
            }
            | Self::Stop {
                expected_revision, ..
            } => *expected_revision,
        }
    }
}

/// 外部资源状态机的纯转换结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ObservedResourceTransitionDecision<T> {
    pub next_state: ObservedResource<T>,
    pub changed: bool,
}

/// 非法外部资源状态转换。
#[derive(Debug, Clone, PartialEq, Eq, Error)]
pub enum ObservedResourceTransitionError<T: std::fmt::Debug> {
    #[error("observed resource revision is stale: expected {expected}, actual {actual}")]
    StaleRevision {
        expected: u64,
        actual: u64,
        command: ObservedResourceCommand<T>,
    },
    #[error("observed resource in {current:?} rejects command {command:?}")]
    IllegalTransition {
        current: ObservedResourceKind,
        command: ObservedResourceCommand<T>,
    },
}

impl<T> ObservedResource<T> {
    /// 创建尚未加载且没有可用值的资源。
    pub fn uninitialized(updated_at: i64) -> Self {
        Self::Uninitialized(UninitializedResource::new(updated_at))
    }

    /// 创建已就绪的资源。
    pub fn ready(revision: u64, updated_at: i64, value: T) -> Self {
        Self::Ready(ReadyResource::new(revision, updated_at, value))
    }

    /// 返回领域 revision。
    pub fn revision(&self) -> u64 {
        match self {
            Self::Uninitialized(state) => state.revision(),
            Self::Loading(state) => state.revision(),
            Self::Ready(state) => state.revision(),
            Self::Refreshing(state) => state.revision(),
            Self::Stale(state) => state.revision(),
            Self::Degraded(state) => state.revision(),
            Self::Failed(state) => state.revision(),
            Self::Stopped(state) => state.revision(),
        }
    }

    /// 返回当前穷尽状态种类。
    pub fn kind(&self) -> ObservedResourceKind {
        match self {
            Self::Uninitialized(_) => ObservedResourceKind::Uninitialized,
            Self::Loading(_) => ObservedResourceKind::Loading,
            Self::Ready(_) => ObservedResourceKind::Ready,
            Self::Refreshing(_) => ObservedResourceKind::Refreshing,
            Self::Stale(_) => ObservedResourceKind::Stale,
            Self::Degraded(_) => ObservedResourceKind::Degraded,
            Self::Failed(_) => ObservedResourceKind::Failed,
            Self::Stopped(_) => ObservedResourceKind::Stopped,
        }
    }

    /// 返回最近一次状态变化时间。
    pub fn updated_at(&self) -> i64 {
        match self {
            Self::Uninitialized(state) => state.updated_at(),
            Self::Loading(state) => state.started_at(),
            Self::Ready(state) => state.updated_at(),
            Self::Refreshing(state) => state.started_at(),
            Self::Stale(state) => state.stale_at(),
            Self::Degraded(state) => state.failed_at(),
            Self::Failed(state) => state.failed_at(),
            Self::Stopped(state) => state.stopped_at(),
        }
    }

    /// 返回适用状态中最近一次完成观察的时间。
    pub fn last_checked_at(&self) -> Option<i64> {
        match self {
            Self::Ready(state) => state.last_checked_at(),
            Self::Refreshing(state) => state.last_checked_at(),
            Self::Stale(state) => state.last_checked_at(),
            Self::Degraded(state) => state.last_checked_at(),
            Self::Uninitialized(_) | Self::Loading(_) | Self::Failed(_) | Self::Stopped(_) => None,
        }
    }

    /// 返回当前仍可展示的 canonical 或 last-known value。
    pub fn value(&self) -> Option<&T> {
        match self {
            Self::Ready(state) => Some(state.value()),
            Self::Refreshing(state) => Some(state.value()),
            Self::Stale(state) => Some(state.value()),
            Self::Degraded(state) => Some(state.value()),
            Self::Uninitialized(_) | Self::Loading(_) | Self::Failed(_) | Self::Stopped(_) => None,
        }
    }

    /// 消费资源并返回当前仍可用的值。
    pub fn into_value(self) -> Option<T> {
        match self {
            Self::Ready(state) => Some(state.into_value()),
            Self::Refreshing(state) => Some(state.into_value()),
            Self::Stale(state) => Some(state.into_value()),
            Self::Degraded(state) => Some(state.into_value()),
            Self::Uninitialized(_) | Self::Loading(_) | Self::Failed(_) | Self::Stopped(_) => None,
        }
    }

    /// 在不改变生命周期元数据的前提下转换资源值。
    pub fn map<U>(self, map_value: impl FnOnce(T) -> U) -> ObservedResource<U> {
        match self {
            Self::Uninitialized(state) => {
                ObservedResource::Uninitialized(UninitializedResource::new(state.updated_at()))
            }
            Self::Loading(state) => ObservedResource::Loading(LoadingResource::new(
                state.revision(),
                state.operation(),
                state.operation_id().to_string(),
                state.started_at(),
            )),
            Self::Ready(state) => {
                let revision = state.revision();
                let updated_at = state.updated_at();
                let last_checked_at = state.last_checked_at();
                ObservedResource::Ready(ReadyResource::new_observed(
                    revision,
                    updated_at,
                    last_checked_at,
                    map_value(state.into_value()),
                ))
            }
            Self::Refreshing(state) => {
                let revision = state.revision();
                let operation = state.operation();
                let operation_id = state.operation_id().to_string();
                let started_at = state.started_at();
                let last_checked_at = state.last_checked_at();
                ObservedResource::Refreshing(RefreshingResource::new(
                    revision,
                    operation,
                    operation_id,
                    started_at,
                    last_checked_at,
                    map_value(state.into_value()),
                ))
            }
            Self::Stale(state) => {
                let revision = state.revision();
                let stale_at = state.stale_at();
                let last_checked_at = state.last_checked_at();
                ObservedResource::Stale(StaleResource::new(
                    revision,
                    stale_at,
                    last_checked_at,
                    map_value(state.into_value()),
                ))
            }
            Self::Degraded(state) => {
                let revision = state.revision();
                let failed_at = state.failed_at();
                let last_checked_at = state.last_checked_at();
                let operation = state.operation();
                let error = state.error().clone();
                ObservedResource::Degraded(DegradedResource::new(
                    revision,
                    failed_at,
                    last_checked_at,
                    operation,
                    error,
                    map_value(state.into_value()),
                ))
            }
            Self::Failed(state) => ObservedResource::Failed(FailedResource::new(
                state.revision(),
                state.failed_at(),
                state.operation(),
                state.error().clone(),
            )),
            Self::Stopped(state) => ObservedResource::Stopped(StoppedResource::new(
                state.revision(),
                state.stopped_at(),
            )),
        }
    }
}

fn cached_observation<T: Clone>(state: &ObservedResource<T>) -> Option<(i64, T)> {
    match state {
        ObservedResource::Ready(current) => {
            Some((current.last_checked_at(), current.value().clone()))
        }
        ObservedResource::Stale(current) => {
            Some((current.last_checked_at(), current.value().clone()))
        }
        ObservedResource::Degraded(current) => {
            Some((current.last_checked_at(), current.value().clone()))
        }
        _ => None,
    }
}

impl<T> ObservedResource<T>
where
    T: Clone + PartialEq + std::fmt::Debug,
{
    /// 纯计算一个命令的下一状态，不执行 IO。
    ///
    /// # Errors
    ///
    /// revision 过期或当前状态不接受命令时返回具体转换错误。
    pub fn decide(
        &self,
        command: ObservedResourceCommand<T>,
    ) -> Result<ObservedResourceTransitionDecision<T>, ObservedResourceTransitionError<T>> {
        if command.expected_revision() != self.revision() {
            return Err(ObservedResourceTransitionError::StaleRevision {
                expected: command.expected_revision(),
                actual: self.revision(),
                command,
            });
        }
        let revision = self.revision().saturating_add(1);
        if let ObservedResourceCommand::Begin {
            operation,
            operation_id,
            started_at,
            ..
        } = &command
        {
            if let Some((last_checked_at, value)) = cached_observation(self) {
                let next_state = Self::Refreshing(RefreshingResource::new(
                    revision,
                    *operation,
                    operation_id.clone(),
                    *started_at,
                    last_checked_at,
                    value,
                ));
                return Ok(ObservedResourceTransitionDecision {
                    changed: next_state != *self,
                    next_state,
                });
            }
        }
        let next_state = match (self, &command) {
            (
                Self::Uninitialized(_) | Self::Failed(_),
                ObservedResourceCommand::Begin {
                    operation,
                    operation_id,
                    started_at,
                    ..
                },
            ) => Self::Loading(LoadingResource::new(
                revision,
                *operation,
                operation_id.clone(),
                *started_at,
            )),
            (
                Self::Loading(_) | Self::Refreshing(_),
                ObservedResourceCommand::Succeed {
                    updated_at,
                    last_checked_at,
                    value,
                    ..
                },
            ) => Self::Ready(ReadyResource::new_observed(
                revision,
                *updated_at,
                *last_checked_at,
                value.clone(),
            )),
            (
                Self::Ready(_) | Self::Stale(_) | Self::Degraded(_),
                ObservedResourceCommand::Observe {
                    observed_at,
                    last_checked_at,
                    value,
                    ..
                },
            ) => Self::Ready(ReadyResource::new_observed(
                revision,
                *observed_at,
                *last_checked_at,
                value.clone(),
            )),
            (
                Self::Ready(_) | Self::Stale(_) | Self::Degraded(_),
                ObservedResourceCommand::MarkStale {
                    stale_at, value, ..
                },
            ) => Self::Stale(StaleResource::new(
                revision,
                *stale_at,
                self.last_checked_at(),
                value.clone(),
            )),
            (
                Self::Loading(current),
                ObservedResourceCommand::Fail {
                    failed_at, error, ..
                },
            ) => Self::Failed(FailedResource::new(
                revision,
                *failed_at,
                current.operation(),
                error.clone(),
            )),
            (
                Self::Refreshing(current),
                ObservedResourceCommand::Fail {
                    failed_at, error, ..
                },
            ) => Self::Degraded(DegradedResource::new(
                revision,
                *failed_at,
                current.last_checked_at(),
                current.operation(),
                error.clone(),
                current.value().clone(),
            )),
            (
                Self::Uninitialized(_)
                | Self::Loading(_)
                | Self::Ready(_)
                | Self::Refreshing(_)
                | Self::Stale(_)
                | Self::Degraded(_)
                | Self::Failed(_),
                ObservedResourceCommand::Stop { stopped_at, .. },
            ) => Self::Stopped(StoppedResource::new(revision, *stopped_at)),
            _ => {
                return Err(ObservedResourceTransitionError::IllegalTransition {
                    current: self.kind(),
                    command,
                });
            }
        };
        Ok(ObservedResourceTransitionDecision {
            changed: next_state != *self,
            next_state,
        })
    }
}

/// 可以改变或重新观察领域状态的明确命令。
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum StateOperation {
    Initialize,
    Activate,
    Reload,
    Reconcile,
    Discover,
    Check,
    Probe,
    Repair,
    Reset,
    Shutdown,
}

/// 刷新失败但仍保留可展示 last-known value 的资源。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct DegradedResource<T> {
    revision: u64,
    failed_at: i64,
    last_checked_at: Option<i64>,
    operation: StateOperation,
    error: StateError,
    value: T,
}

impl<T> DegradedResource<T> {
    pub(super) fn new(
        revision: u64,
        failed_at: i64,
        last_checked_at: Option<i64>,
        operation: StateOperation,
        error: StateError,
        value: T,
    ) -> Self {
        Self {
            revision,
            failed_at,
            last_checked_at,
            operation,
            error,
            value,
        }
    }

    pub fn revision(&self) -> u64 {
        self.revision
    }

    pub fn failed_at(&self) -> i64 {
        self.failed_at
    }

    pub fn last_checked_at(&self) -> Option<i64> {
        self.last_checked_at
    }

    pub fn operation(&self) -> StateOperation {
        self.operation
    }

    pub fn error(&self) -> &StateError {
        &self.error
    }

    pub fn value(&self) -> &T {
        &self.value
    }

    pub(super) fn into_value(self) -> T {
        self.value
    }
}

/// 加载失败且没有可用值的资源。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct FailedResource {
    revision: u64,
    failed_at: i64,
    operation: StateOperation,
    error: StateError,
}

impl FailedResource {
    pub(super) fn new(
        revision: u64,
        failed_at: i64,
        operation: StateOperation,
        error: StateError,
    ) -> Self {
        Self {
            revision,
            failed_at,
            operation,
            error,
        }
    }

    pub fn revision(&self) -> u64 {
        self.revision
    }

    pub fn failed_at(&self) -> i64 {
        self.failed_at
    }

    pub fn operation(&self) -> StateOperation {
        self.operation
    }

    pub fn error(&self) -> &StateError {
        &self.error
    }
}

/// 首次加载中；此阶段没有可展示的旧值。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct LoadingResource {
    revision: u64,
    operation: StateOperation,
    operation_id: String,
    started_at: i64,
}

impl LoadingResource {
    pub(super) fn new(
        revision: u64,
        operation: StateOperation,
        operation_id: String,
        started_at: i64,
    ) -> Self {
        Self {
            revision,
            operation,
            operation_id,
            started_at,
        }
    }

    pub fn revision(&self) -> u64 {
        self.revision
    }

    pub fn operation(&self) -> StateOperation {
        self.operation
    }

    pub fn operation_id(&self) -> &str {
        &self.operation_id
    }

    pub fn started_at(&self) -> i64 {
        self.started_at
    }
}

/// 已就绪且与 desired state 一致的资源。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReadyResource<T> {
    revision: u64,
    updated_at: i64,
    last_checked_at: Option<i64>,
    value: T,
}

impl<T> ReadyResource<T> {
    pub(super) fn new(revision: u64, updated_at: i64, value: T) -> Self {
        Self::new_observed(revision, updated_at, None, value)
    }

    pub(super) fn new_observed(
        revision: u64,
        updated_at: i64,
        last_checked_at: Option<i64>,
        value: T,
    ) -> Self {
        Self {
            revision,
            updated_at,
            last_checked_at,
            value,
        }
    }

    pub fn revision(&self) -> u64 {
        self.revision
    }

    pub fn updated_at(&self) -> i64 {
        self.updated_at
    }

    pub fn last_checked_at(&self) -> Option<i64> {
        self.last_checked_at
    }

    pub fn value(&self) -> &T {
        &self.value
    }

    pub(super) fn into_value(self) -> T {
        self.value
    }
}

/// 刷新中，并保留可展示的 last-known value。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RefreshingResource<T> {
    revision: u64,
    operation: StateOperation,
    operation_id: String,
    started_at: i64,
    last_checked_at: Option<i64>,
    value: T,
}

impl<T> RefreshingResource<T> {
    pub(super) fn new(
        revision: u64,
        operation: StateOperation,
        operation_id: String,
        started_at: i64,
        last_checked_at: Option<i64>,
        value: T,
    ) -> Self {
        Self {
            revision,
            operation,
            operation_id,
            started_at,
            last_checked_at,
            value,
        }
    }

    pub fn revision(&self) -> u64 {
        self.revision
    }

    pub fn operation(&self) -> StateOperation {
        self.operation
    }

    pub fn operation_id(&self) -> &str {
        &self.operation_id
    }

    pub fn started_at(&self) -> i64 {
        self.started_at
    }

    pub fn last_checked_at(&self) -> Option<i64> {
        self.last_checked_at
    }

    pub fn value(&self) -> &T {
        &self.value
    }

    pub(super) fn into_value(self) -> T {
        self.value
    }
}

/// 已明确失效但仍可展示 last-known value 的资源。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StaleResource<T> {
    revision: u64,
    stale_at: i64,
    last_checked_at: Option<i64>,
    value: T,
}

impl<T> StaleResource<T> {
    pub(super) fn new(
        revision: u64,
        stale_at: i64,
        last_checked_at: Option<i64>,
        value: T,
    ) -> Self {
        Self {
            revision,
            stale_at,
            last_checked_at,
            value,
        }
    }

    pub fn revision(&self) -> u64 {
        self.revision
    }

    pub fn stale_at(&self) -> i64 {
        self.stale_at
    }

    pub fn last_checked_at(&self) -> Option<i64> {
        self.last_checked_at
    }

    pub fn value(&self) -> &T {
        &self.value
    }

    pub(super) fn into_value(self) -> T {
        self.value
    }
}

/// 已停止且不再暴露旧值的资源。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct StoppedResource {
    revision: u64,
    stopped_at: i64,
}

impl StoppedResource {
    pub(super) fn new(revision: u64, stopped_at: i64) -> Self {
        Self {
            revision,
            stopped_at,
        }
    }

    pub fn revision(&self) -> u64 {
        self.revision
    }

    pub fn stopped_at(&self) -> i64 {
        self.stopped_at
    }
}

/// 尚未加载、没有可用值的资源。
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UninitializedResource {
    revision: u64,
    updated_at: i64,
}

impl UninitializedResource {
    pub(super) fn new(updated_at: i64) -> Self {
        Self {
            revision: 0,
            updated_at,
        }
    }

    pub fn revision(&self) -> u64 {
        self.revision
    }

    pub fn updated_at(&self) -> i64 {
        self.updated_at
    }
}

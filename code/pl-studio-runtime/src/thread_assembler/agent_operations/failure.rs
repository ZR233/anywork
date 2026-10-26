//! Actual collaboration join evidence, separate from operation business outcomes.
use std::sync::Arc;

use tokio::task::{Id, JoinError};

#[derive(Debug, Clone)]
#[allow(dead_code)] // 保留：关闭/停机诊断事实，报告投影的读取方尚未接回；删除会丢失去噪证据。
pub(crate) struct AgentOperationJoinIssue {
    pub(crate) task_id: Id,
    // None records missing original metadata, never an invented caller/root identity.
    pub(crate) caller: Option<String>,
    pub(crate) error: Arc<JoinError>,
}

#[derive(Debug, Clone)]
#[allow(dead_code)] // 保留：关闭/停机诊断事实，报告投影的读取方尚未接回；删除会丢失去噪证据。
pub(crate) struct AgentOperationPending {
    pub(crate) task_id: Id,
    pub(crate) caller: String,
}

/// Immutable view of all currently unresolved real joins in the original Jobs owner.
#[derive(Debug, Clone, thiserror::Error)]
#[error("collaboration shutdown retained failed original joins")]
pub(crate) struct AgentOperationsJoinFailure {
    pub(crate) jobs: Vec<AgentOperationJoinIssue>,
    pub(crate) driver: Option<Arc<JoinError>>,
    pub(crate) driver_id: Option<Id>,
    pub(crate) pending: Vec<AgentOperationPending>,
    #[source]
    pub(crate) cause: Arc<JoinError>,
}

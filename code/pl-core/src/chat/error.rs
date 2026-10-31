//! Timeline 内容源的类型化失败。
//!
//! 分类只由类型决定，调用方不解析错误文本：非法参数与游标、不存在的 item／内容、序号耗尽、
//! 代际失配、预算耗尽与存储故障彼此独立，损坏、迁移失败、空库和取消不会被压成同一种“到头”。

use crate::chat::TimelineEpoch;

#[derive(Debug, thiserror::Error)]
pub enum ChatError {
    /// One identity or one completion sequence was published with a different payload.
    ///
    /// A sealed record is immutable: the same identity with the same payload is idempotent, and any
    /// other combination — a different body at the same identity, or two identities at one sequence —
    /// is a contract error, never an overwrite.
    #[error("chat completion has a conflicting identity or payload: {0}")]
    Conflict(String),
    /// The completion sequence would exceed the signed 64-bit range the store keeps.
    ///
    /// The whole batch fails without partial publication; the caller reports the resource limit
    /// instead of wrapping or reusing sequences.
    #[error("chat completion sequence exceeds the persistent store's range")]
    SeqExhausted,
    /// A request carried an unsupported identity, cursor, ceiling or content offset.
    ///
    /// The rejected input is reported instead of being silently clamped, so a caller never believes
    /// it read a wider page or a larger block than it asked for.
    #[error("invalid chat request: {0}")]
    InvalidArgument(String),
    #[error("invalid chat read demand: {0}")]
    InvalidDemand(String),
    #[error("chat content generation is stale")]
    StaleContent,
    /// The addressed item or explicitly declared content does not exist in this session.
    #[error("chat content not found: {0}")]
    NotFound(String),
    /// A cursor or request belongs to a completion epoch this session no longer runs.
    ///
    /// The session was rebuilt and the completion collection restarted under a new epoch; the caller
    /// re-baselines from a fresh page instead of reinterpreting stale positions.
    #[error("chat cursor epoch {cursor:?} does not match the running epoch {session:?}")]
    EpochMismatch {
        cursor: TimelineEpoch,
        session: TimelineEpoch,
    },
    /// A history port returned more items or encoded bytes than its reserved demand allowed.
    #[error("chat history exceeds the reserved read budget: {0}")]
    Overloaded(String),
    /// The observation was closed; the caller must not treat it as a normal end of content.
    #[error("chat content observation is closed")]
    Cancelled,
    #[error("chat history failed: {0}")]
    History(#[source] Box<dyn std::error::Error + Send + Sync>),
}

//! Timeline 内容源的类型化失败。
//!
//! 分类只由类型决定，调用方不解析错误文本：非法参数与游标、不存在的 item／field、过期
//! revision、预算耗尽与存储故障彼此独立，损坏、迁移失败、空库和取消不会被压成同一种“到头”。

use crate::chat::ChatField;

#[derive(Debug, thiserror::Error)]
pub enum ChatError {
    #[error("chat item has a conflicting identity, order or revision: {0}")]
    Conflict(String),
    #[error("chat item order exceeds the persistent store's range")]
    OrderExhausted,
    #[error("chat order allocator was not initialized before synchronous publication")]
    OrderNotInitialized,
    /// A request carried an unsupported value (page limit, detail block size, continuation offset).
    ///
    /// The rejected input is reported instead of being silently clamped, so a caller never believes
    /// it read a wider page or a larger block than it asked for.
    #[error("invalid chat request: {0}")]
    InvalidArgument(String),
    /// The addressed item or field does not exist in this session.
    #[error("chat content not found: {0}")]
    NotFound(String),
    /// The requested item revision is no longer the current one; reload the item before reading.
    #[error("chat content of {item_id} changed; field {field} at revision {revision} is stale")]
    StaleRevision {
        item_id: String,
        field: ChatField,
        revision: u64,
    },
    /// The bounded preview of one item cannot be represented within the caller's budget.
    ///
    /// A structure that cannot shrink any further is reported instead of falling back to the whole
    /// payload.
    #[error("chat content exceeds the preview budget: {0}")]
    Overloaded(String),
    /// The content changed while a read was assembled, and the bounded publication log can no longer
    /// prove what happened in that window.
    ///
    /// A read captures bounded candidate references and a source version, reads storage outside every
    /// lock and commits afterwards; a withdrawal released meanwhile must not come back through the
    /// captured reference. When that window is no longer covered by the bounded continuity metadata,
    /// the read is retried instead of guessing a deletion, a resurrection or an empty page.
    #[error("chat content changed while the read was being assembled; retry the read")]
    ReadInvalidated,
    /// The observation was closed; the caller must not treat it as a normal end of content.
    #[error("chat content observation is closed")]
    Cancelled,
    #[error("chat history failed: {0}")]
    History(#[source] Box<dyn std::error::Error + Send + Sync>),
}

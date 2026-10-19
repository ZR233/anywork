//! 无状态页请求、严格 keyset 边界与页结果。
//!
//! 页不是窗口：请求只表达“最新”或“某条更旧边界之前”，结果只表达“这一页有什么、下一条边界在哪、
//! 是否真的还有更旧内容”。没有 offset 分页、没有 against 方向、没有跨页拼接状态。

use crate::chat::{ChatError, ChatItem};

/// 每页默认条目数。
pub const DEFAULT_PAGE_ITEMS: usize = 32;
/// 单页最多接纳的条目数；显式请求超出该范围即被拒绝，不做静默放宽。
pub const MAX_PAGE_ITEMS: usize = 100;
/// 单页预览字节预算；预算提前截页仍返回真实的下一边界。
pub const PAGE_PREVIEW_BYTES: usize = 2 * 1024 * 1024;

/// 严格 `(order, item_id)` keyset 边界。
///
/// 比较键就是会话内固定的 `(ordinal, identity)`，因此同一身份的位置不会因页游标而漂移，两个
/// ordinal 相同的条目也由身份唯一区分。边界可以指向尚未落盘的权威条目：游标只表达顺序事实，
/// 不要求该条目已经存在于 durable history，也不把数据库 applied-write 水位当作内容版本。
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord)]
pub struct ChatCursor {
    pub order: u64,
    pub item_id: String,
}

impl ChatCursor {
    /// 由顺序与稳定身份构造边界。
    pub fn new(order: u64, item_id: impl Into<String>) -> Self {
        Self {
            order,
            item_id: item_id.into(),
        }
    }

    /// 一条条目的自身边界。
    pub fn of(item: &ChatItem) -> Self {
        Self::new(item.order, item.item_id.clone())
    }
}

/// 一页请求：只有 `latest`（`before` 为 `None`）或“某条边界之前”。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ChatPageRequest {
    pub before: Option<ChatCursor>,
    pub limit: Option<usize>,
}

impl ChatPageRequest {
    /// 最新一页（默认条目数）。
    pub fn latest() -> Self {
        Self::default()
    }

    /// 严格位于 `before` 之前的一页。
    pub fn before(before: ChatCursor) -> Self {
        Self {
            before: Some(before),
            limit: None,
        }
    }

    /// 指定本页最多返回的条目数。
    pub fn with_limit(mut self, limit: usize) -> Self {
        self.limit = Some(limit);
        self
    }

    /// 校验后的条目数：缺省 32，显式值必须在 `1..=100`。
    ///
    /// # Errors
    /// 显式 `limit` 为 0 或超过 [`MAX_PAGE_ITEMS`] 时返回 [`ChatError::InvalidArgument`]，不静默
    /// 截断成允许范围内的值。
    pub fn limit(&self) -> Result<usize, ChatError> {
        match self.limit {
            None => Ok(DEFAULT_PAGE_ITEMS),
            Some(limit) if (1..=MAX_PAGE_ITEMS).contains(&limit) => Ok(limit),
            Some(limit) => Err(ChatError::InvalidArgument(format!(
                "page limit {limit} is outside 1..={MAX_PAGE_ITEMS}"
            ))),
        }
    }
}

/// 一页升序条目、下一条更旧边界与是否真的还有更旧内容。
///
/// `before` 只在 `has_older` 为真时给出，并取自本页实际第一条（最旧）条目，因此后续页严格接续、
/// 不重复也不跳过。`has_older` 由真实存在性证明（多出一条候选或存储侧存在性检查），短页本身不
/// 等于到头。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatPage {
    pub items: Vec<ChatItem>,
    pub before: Option<ChatCursor>,
    pub has_older: bool,
}

/// 存储侧一页结果：只回答“读到哪些条目”与“是否真的还有更旧行”。
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ChatHistoryPage {
    pub items: Vec<ChatItem>,
    pub has_older: bool,
}

//! 按记录、字段与字节偏移分块读取完整正文。
//!
//! 详情不是“整条全文入口”：请求给出条目身份、字段身份与可选 continuation，结果是一段落在
//! UTF-8 边界上的有界正文块、字段完整字节数和下一块游标。读取只取所需区间，不先物化整个前缀或
//! 剩余全文。完成记录不可变，因此没有内容版本：continuation 绑定记录身份、字段身份与偏移，读取
//! 时逐项校验，从一个字段取得的 continuation 不能被带到另一个字段或另一条记录上，也不会被当成
//! “附近某个位置”的猜测。不存在字段与空字段是两种不同的事实。

use crate::chat::{ChatError, ChatField};

/// 详情块默认字节数。
pub const DEFAULT_DETAIL_BYTES: usize = 64 * 1024;
/// 详情块最多接纳的字节数。
pub const MAX_DETAIL_BYTES: usize = 256 * 1024;
/// 详情块最少接纳的字节数：4 个 UTF-8 字节，即一个标量的最大编码长度。
///
/// 取 4 字节而不是更大的缓冲是为了让边界行为真实可测：一个非空块一定能推进至少一个标量，同时调用
/// 方不会被强制读取远超所需的字节。
pub const MIN_DETAIL_BYTES: usize = 4;

/// 字段内的一段位置游标：绑定记录身份、字段身份与字节偏移的 continuation。
///
/// 它不是 Dart 字符下标，也不是可跨字段复用的偏移：`item_id` 与 `field` 一起构成它的语义，读取时
/// 逐项校验。偏移本身始终落在已交付正文的 UTF-8 边界上。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatDetailCursor {
    item_id: String,
    field: ChatField,
    offset: u64,
}

impl ChatDetailCursor {
    /// 由绑定事实与字段内字节偏移构造 continuation。
    pub fn new(item_id: impl Into<String>, field: ChatField, offset: u64) -> Self {
        Self {
            item_id: item_id.into(),
            field,
            offset,
        }
    }

    /// 该 continuation 所属的条目身份。
    pub fn item_id(&self) -> &str {
        &self.item_id
    }

    /// 该 continuation 所属的字段身份。
    pub fn field(&self) -> &ChatField {
        &self.field
    }

    /// 字段内字节偏移。
    pub fn offset(&self) -> u64 {
        self.offset
    }

    /// 校验 continuation 属于这次读取请求，否则返回类型化拒绝。
    pub(crate) fn validate(&self, request: &ChatDetailRequest) -> Result<(), ChatError> {
        if self.item_id != request.item_id {
            return Err(ChatError::InvalidArgument(format!(
                "detail continuation belongs to item {} instead of {}",
                self.item_id, request.item_id
            )));
        }
        if self.field != request.field {
            return Err(ChatError::InvalidArgument(format!(
                "detail continuation belongs to field {} instead of {}",
                self.field, request.field
            )));
        }
        Ok(())
    }
}

/// 一次详情读取请求。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatDetailRequest {
    pub item_id: String,
    pub field: ChatField,
    pub continuation: Option<ChatDetailCursor>,
    pub max_bytes: Option<usize>,
}

impl ChatDetailRequest {
    /// 从字段开头读取一块。
    pub fn new(item_id: impl Into<String>, field: ChatField) -> Self {
        Self {
            item_id: item_id.into(),
            field,
            continuation: None,
            max_bytes: None,
        }
    }

    /// 从给定 continuation 继续读取。
    pub fn with_continuation(mut self, continuation: ChatDetailCursor) -> Self {
        self.continuation = Some(continuation);
        self
    }

    /// 指定本块最多字节数。
    pub fn with_max_bytes(mut self, max_bytes: usize) -> Self {
        self.max_bytes = Some(max_bytes);
        self
    }

    /// 校验后的块大小：缺省 64 KiB，显式值必须在 4..=256 KiB。
    ///
    /// # Errors
    /// 显式块大小低于 [`MIN_DETAIL_BYTES`] 或高于 [`MAX_DETAIL_BYTES`] 时返回
    /// [`ChatError::InvalidArgument`]。
    pub fn block_bytes(&self) -> Result<usize, ChatError> {
        match self.max_bytes {
            None => Ok(DEFAULT_DETAIL_BYTES),
            Some(bytes) if (MIN_DETAIL_BYTES..=MAX_DETAIL_BYTES).contains(&bytes) => Ok(bytes),
            Some(bytes) => Err(ChatError::InvalidArgument(format!(
                "detail block {bytes} is outside {MIN_DETAIL_BYTES}..={MAX_DETAIL_BYTES}"
            ))),
        }
    }
}

/// 一段完整正文块。
///
/// `total_bytes` 是该字段完整正文的 UTF-8 字节数，`continuation` 只在仍有后续字节时给出。空字段
/// 返回空正文且没有下一块：空字段与不存在的字段是两种不同的事实。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatDetailChunk {
    pub item_id: String,
    pub field: ChatField,
    pub text: String,
    pub total_bytes: u64,
    pub continuation: Option<ChatDetailCursor>,
}

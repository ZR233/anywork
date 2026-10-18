//! 宿主持久化边界：keyset 页、按身份读取与有界预览。
//!
//! 存储是更旧行文的唯一来源，普通页只做 keyset 读取，不按 offset 扫描整段历史。取消读取不向展示
//! 发布任何部分结果，底层只读工作仍由宿主自己的连接池管理。

use std::{fmt, future::Future};

use futures::future::BoxFuture;

use crate::{
    chat::{ChatCursor, ChatError, ChatHistoryPage, ChatItem},
    model::ContentBlock,
};

/// 单条条目的预览字节预算。
///
/// 超出预算的正文以同身份、同顺序的预览返回，完整正文按身份与字段通过
/// [`Session::read_detail`](crate::chat::Session::read_detail) 分块读取；静态身份与判别字段不因
/// 预算被改写。
pub const CHAT_ITEM_PREVIEW_BYTES: usize = 256 * 1024;

/// Host persistence is the only source of older rows.
///
/// Implementations use keyset queries only: a short page is not evidence that the beginning of the
/// history has been reached, so `has_older` must come from a real existence check.
pub trait ChatHistory: Send + Sync + fmt::Debug + 'static {
    /// Project a bounded visible copy without changing the canonical item.
    ///
    /// The default bounds every content field so the **whole** preview — the non-shrinkable structure
    /// plus the body UTF-8 — fits [`CHAT_ITEM_PREVIEW_BYTES`], reusing the shared block prefix instead
    /// of re-materializing the text. Structure is charged first, so an item with many empty or short
    /// fields, long host keys or a large static `meta` cannot buy itself free body bytes. Each field
    /// keeps its complete byte length, so a truncated preview never rewrites the original size. A
    /// codec-aware host overrides this when its own encoding has per-field limits or a smaller product
    /// budget; [`ErasedChatHistory::bounded`] then checks the result against the same limit.
    fn bounded(&self, item: &ChatItem) -> Result<ChatItem, ChatError> {
        let structure = item.preview_structure_bytes();
        if structure > CHAT_ITEM_PREVIEW_BYTES {
            return Err(ChatError::Overloaded(format!(
                "preview structure of {} exceeds {CHAT_ITEM_PREVIEW_BYTES} bytes",
                item.item_id
            )));
        }
        let body_budget = CHAT_ITEM_PREVIEW_BYTES - structure;
        if item.content_bytes() <= body_budget {
            return Ok(item.clone());
        }
        let mut preview = item.clone();
        let mut remaining = body_budget;
        for field in preview.fields.values_mut() {
            let (bounded, kept) = ContentBlock::prefix_at(&field.block, remaining);
            field.block = bounded;
            remaining = remaining.saturating_sub(kept);
        }
        Ok(preview)
    }

    /// Highest committed or already allocated order. A cold session reads this once before
    /// admitting a new identity; subsequent allocations do not perform storage IO.
    fn latest_allocated_order(&self) -> impl Future<Output = Result<u64, ChatError>> + Send;

    /// Up to `limit` rows strictly older than `before`, ascending, plus a proven `has_older`.
    fn page(
        &self,
        before: Option<&ChatCursor>,
        limit: usize,
    ) -> impl Future<Output = Result<ChatHistoryPage, ChatError>> + Send;

    /// The complete canonical item, never a bounded preview.
    fn item(
        &self,
        item_id: &str,
    ) -> impl Future<Output = Result<Option<ChatItem>, ChatError>> + Send;
}

pub(crate) trait ErasedChatHistory: Send + Sync + fmt::Debug {
    fn bounded(&self, item: &ChatItem) -> Result<ChatItem, ChatError>;
    fn latest_allocated_order(&self) -> BoxFuture<'_, Result<u64, ChatError>>;
    fn page<'a>(
        &'a self,
        before: Option<&'a ChatCursor>,
        limit: usize,
    ) -> BoxFuture<'a, Result<ChatHistoryPage, ChatError>>;
    fn item<'a>(&'a self, id: &'a str) -> BoxFuture<'a, Result<Option<ChatItem>, ChatError>>;
}

impl<T: ChatHistory> ErasedChatHistory for T {
    fn bounded(&self, item: &ChatItem) -> Result<ChatItem, ChatError> {
        let preview = ChatHistory::bounded(self, item)?;
        // A host override may use its own per-field limits, so the shared single-item limit is checked
        // once more on the result: no override can hand the session a preview larger than the contract.
        // An over-budget result is reported as a resource limit instead of being silently trimmed a
        // second time — the host's own product fields stay exactly as it produced them.
        if preview.resident_bytes() > CHAT_ITEM_PREVIEW_BYTES {
            return Err(ChatError::Overloaded(format!(
                "bounded preview of {} exceeds {CHAT_ITEM_PREVIEW_BYTES} bytes",
                preview.item_id
            )));
        }
        Ok(preview)
    }

    fn latest_allocated_order(&self) -> BoxFuture<'_, Result<u64, ChatError>> {
        Box::pin(ChatHistory::latest_allocated_order(self))
    }

    fn page<'a>(
        &'a self,
        before: Option<&'a ChatCursor>,
        limit: usize,
    ) -> BoxFuture<'a, Result<ChatHistoryPage, ChatError>> {
        Box::pin(ChatHistory::page(self, before, limit))
    }

    fn item<'a>(&'a self, id: &'a str) -> BoxFuture<'a, Result<Option<ChatItem>, ChatError>> {
        Box::pin(ChatHistory::item(self, id))
    }
}

//! 宿主持久化边界：完成页、按身份读取与有界预览。
//!
//! 存储是更旧行文的唯一来源。普通页只做 keyset 读取，内部补发只做 after-range 读取，都不按
//! offset 扫描整段历史。每次调用在端口上都是一次新的短读事务：读取方在锁外调用，不复用捕获之前
//! 建立的旧快照。取消读取不向展示发布任何部分结果，底层连接池归宿主管理。
//!
//! 接口保持产品无关：实现只知道完成序号、稳定身份与完整不可变记录，不知道展示分组或协议标签。

use std::{fmt, future::Future};

use futures::future::BoxFuture;

use crate::{
    chat::{ChatCursor, ChatError, ChatHistoryPage, ChatItem},
    model::ContentBlock,
};

/// 单条记录的预览字节预算。
///
/// 超出预算的正文以同身份、同顺序的预览返回，完整正文按身份与字段通过
/// [`Session::read_detail`](crate::chat::Session::read_detail) 分块读取；静态身份与判别字段不因
/// 预算被改写。
pub const CHAT_ITEM_PREVIEW_BYTES: usize = 256 * 1024;

/// Host persistence is the only source of committed rows.
///
/// Implementations use keyset queries only: a short page is not evidence that the beginning of the
/// history has been reached, so `has_more` must come from a real existence check. Every call opens a
/// fresh short read transaction; callers invoke these methods outside the session's timeline lock.
pub trait ChatHistory: Send + Sync + fmt::Debug + 'static {
    /// Project a bounded visible copy without changing the canonical record.
    ///
    /// The default bounds every content field so the **whole** preview — the non-shrinkable structure
    /// plus the body UTF-8 — fits [`CHAT_ITEM_PREVIEW_BYTES`], reusing the shared block prefix instead
    /// of re-materializing the text. Structure is charged first, so a record with many empty or short
    /// fields, long host keys or a large static `meta` cannot buy itself free body bytes. Each field
    /// keeps its complete byte length, so a truncated preview never rewrites the original size. A
    /// codec-aware host overrides this when its own encoding has per-field limits or a smaller
    /// product budget; [`ErasedChatHistory::bounded`] then checks the result against the same limit.
    fn bounded(&self, record: &ChatItem) -> Result<ChatItem, ChatError> {
        let structure = record.preview_structure_bytes();
        if structure > CHAT_ITEM_PREVIEW_BYTES {
            return Err(ChatError::Overloaded(format!(
                "preview structure of {} exceeds {CHAT_ITEM_PREVIEW_BYTES} bytes",
                record.item_id
            )));
        }
        let body_budget = CHAT_ITEM_PREVIEW_BYTES - structure;
        if record.content_bytes() <= body_budget {
            return Ok(record.clone());
        }
        let mut preview = record.clone();
        let mut remaining = body_budget;
        for field in preview.fields.values_mut() {
            let (bounded, kept) = ContentBlock::prefix_at(&field.block, remaining);
            field.block = bounded;
            remaining = remaining.saturating_sub(kept);
        }
        Ok(preview)
    }

    /// Highest completion sequence the store has persisted. A cold session reads this once before
    /// publishing; it seeds both the visible head and the durable prefix. This does not create a
    /// history database and does not start the model.
    fn latest_append_seq(&self) -> impl Future<Output = Result<u64, ChatError>> + Send;

    /// Up to `limit` committed rows strictly older than `before` and at or below `ceiling`,
    /// ascending, plus a proven `has_more`.
    ///
    /// `ceiling` is the completion head the caller captured under its timeline lock; a row above it
    /// is not yet visible to that read even if a writer committed meanwhile.
    fn page(
        &self,
        before: Option<&ChatCursor>,
        ceiling: u64,
        limit: usize,
    ) -> impl Future<Output = Result<ChatHistoryPage, ChatError>> + Send;

    /// Up to `limit` committed rows strictly newer than `after` and at or below `ceiling`,
    /// ascending, plus a proven `has_more`.
    ///
    /// This is the bounded internal catch-up read behind a tail, independent of the public
    /// Latest/Before paging; it exists so a lagging consumer can be refilled from the completion
    /// collection without skipping to the head.
    fn page_after(
        &self,
        after: u64,
        ceiling: u64,
        limit: usize,
    ) -> impl Future<Output = Result<ChatHistoryPage, ChatError>> + Send;

    /// The complete canonical record, never a bounded preview.
    fn item(
        &self,
        item_id: &str,
    ) -> impl Future<Output = Result<Option<ChatItem>, ChatError>> + Send;
}

pub(crate) trait ErasedChatHistory: Send + Sync + fmt::Debug {
    fn bounded(&self, record: &ChatItem) -> Result<ChatItem, ChatError>;
    fn latest_append_seq(&self) -> BoxFuture<'_, Result<u64, ChatError>>;
    fn page<'a>(
        &'a self,
        before: Option<&'a ChatCursor>,
        ceiling: u64,
        limit: usize,
    ) -> BoxFuture<'a, Result<ChatHistoryPage, ChatError>>;
    fn page_after<'a>(
        &'a self,
        after: u64,
        ceiling: u64,
        limit: usize,
    ) -> BoxFuture<'a, Result<ChatHistoryPage, ChatError>>;
    fn item<'a>(&'a self, id: &'a str) -> BoxFuture<'a, Result<Option<ChatItem>, ChatError>>;
}

impl<T: ChatHistory> ErasedChatHistory for T {
    fn bounded(&self, record: &ChatItem) -> Result<ChatItem, ChatError> {
        let preview = ChatHistory::bounded(self, record)?;
        // A host override may use its own per-field limits, so the shared single-record limit is
        // checked once more on the result: no override can hand the session a preview larger than
        // the contract. An over-budget result is reported as a resource limit instead of being
        // silently trimmed a second time — the host's own product fields stay exactly as it
        // produced them.
        if preview.resident_bytes() > CHAT_ITEM_PREVIEW_BYTES {
            return Err(ChatError::Overloaded(format!(
                "bounded preview of {} exceeds {CHAT_ITEM_PREVIEW_BYTES} bytes",
                preview.item_id
            )));
        }
        Ok(preview)
    }

    fn latest_append_seq(&self) -> BoxFuture<'_, Result<u64, ChatError>> {
        Box::pin(ChatHistory::latest_append_seq(self))
    }

    fn page<'a>(
        &'a self,
        before: Option<&'a ChatCursor>,
        ceiling: u64,
        limit: usize,
    ) -> BoxFuture<'a, Result<ChatHistoryPage, ChatError>> {
        Box::pin(ChatHistory::page(self, before, ceiling, limit))
    }

    fn page_after<'a>(
        &'a self,
        after: u64,
        ceiling: u64,
        limit: usize,
    ) -> BoxFuture<'a, Result<ChatHistoryPage, ChatError>> {
        Box::pin(ChatHistory::page_after(self, after, ceiling, limit))
    }

    fn item<'a>(&'a self, id: &'a str) -> BoxFuture<'a, Result<Option<ChatItem>, ChatError>> {
        Box::pin(ChatHistory::item(self, id))
    }
}

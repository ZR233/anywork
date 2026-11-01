//! Host persistence port. Every asynchronous read opens a NEW short snapshot after invocation.
//! No query flushes/starts execution or loads checkpoints. Page implementations select indexed
//! headers and length(payload) first, use select_payload, and fetch only Inline bodies. exhausted
//! comes from natural keyset exhaustion, not COUNT/existence; cancellation publishes no partial page.

use crate::chat::{
    ChatBudget, ChatContent, ChatError, ChatHistoryPage, ChatHistoryRequest, ChatItem,
    ContentManifestPage, ContentManifestRequest, ContentReadRequest, ContentWindow,
};
use futures::future::BoxFuture;
use std::{fmt, future::Future};

pub trait ChatHistory: Send + Sync + fmt::Debug + 'static {
    fn latest_append_seq(&self) -> impl Future<Output = Result<u64, ChatError>> + Send;
    /// Descending selection, ascending result. Demand has already reserved all non-item costs.
    fn page(
        &self,
        request: &ChatHistoryRequest,
        budget: &dyn ChatBudget,
    ) -> impl Future<Output = Result<ChatHistoryPage, ChatError>> + Send;
    /// Ascending selection and result, for bounded internal replay only.
    fn page_after(
        &self,
        request: &ChatHistoryRequest,
        budget: &dyn ChatBudget,
    ) -> impl Future<Output = Result<ChatHistoryPage, ChatError>> + Send;
    /// Complete frozen record for publication idempotency only, never used by normal pages/content.
    fn item(
        &self,
        item_id: &str,
    ) -> impl Future<Output = Result<Option<ChatItem>, ChatError>> + Send;
    /// Publication-only validation of an immutable content key against a fresh durable snapshot.
    ///
    /// An absent key or a sealed key with the same descriptor and exact bytes succeeds. The host
    /// may also own an unsealed active prefix: a same-generation append/seal with an exact existing
    /// byte prefix can succeed under that owner's rules. Core never interprets active state.
    /// Descriptor/byte conflicts return [`ChatError::Conflict`]; storage/content failures remain
    /// their real errors. Implementations compare existing bodies through bounded ranges, without
    /// allocating the complete body. Session revalidates its captured durable prefix before
    /// publication; pending and newly published records are always sealed and strictly immutable.
    fn validate_content(
        &self,
        content: &ChatContent,
    ) -> impl Future<Output = Result<(), ChatError>> + Send;
    /// Producer-declared manifest, bounded by demand. No payload reference inference.
    fn list_contents(
        &self,
        request: &ContentManifestRequest,
        budget: &dyn ChatBudget,
    ) -> impl Future<Output = Result<ContentManifestPage, ChatError>> + Send;
    /// A real BLOB/chunk range read, NOT item()/read-full-then-slice. Missing/IO/stale is an error.
    fn read_content(
        &self,
        request: &ContentReadRequest,
    ) -> impl Future<Output = Result<ContentWindow, ChatError>> + Send;
}

pub(crate) trait ErasedChatHistory: Send + Sync + fmt::Debug {
    fn latest_append_seq(&self) -> BoxFuture<'_, Result<u64, ChatError>>;
    fn page<'a>(
        &'a self,
        request: &'a ChatHistoryRequest,
        budget: &'a dyn ChatBudget,
    ) -> BoxFuture<'a, Result<ChatHistoryPage, ChatError>>;
    fn page_after<'a>(
        &'a self,
        request: &'a ChatHistoryRequest,
        budget: &'a dyn ChatBudget,
    ) -> BoxFuture<'a, Result<ChatHistoryPage, ChatError>>;
    fn item<'a>(&'a self, id: &'a str) -> BoxFuture<'a, Result<Option<ChatItem>, ChatError>>;
    fn validate_content<'a>(
        &'a self,
        content: &'a ChatContent,
    ) -> BoxFuture<'a, Result<(), ChatError>>;
    fn list_contents<'a>(
        &'a self,
        request: &'a ContentManifestRequest,
        budget: &'a dyn ChatBudget,
    ) -> BoxFuture<'a, Result<ContentManifestPage, ChatError>>;
    fn read_content<'a>(
        &'a self,
        request: &'a ContentReadRequest,
    ) -> BoxFuture<'a, Result<ContentWindow, ChatError>>;
}

impl<T: ChatHistory> ErasedChatHistory for T {
    fn latest_append_seq(&self) -> BoxFuture<'_, Result<u64, ChatError>> {
        Box::pin(ChatHistory::latest_append_seq(self))
    }
    fn page<'a>(
        &'a self,
        request: &'a ChatHistoryRequest,
        budget: &'a dyn ChatBudget,
    ) -> BoxFuture<'a, Result<ChatHistoryPage, ChatError>> {
        Box::pin(ChatHistory::page(self, request, budget))
    }
    fn page_after<'a>(
        &'a self,
        request: &'a ChatHistoryRequest,
        budget: &'a dyn ChatBudget,
    ) -> BoxFuture<'a, Result<ChatHistoryPage, ChatError>> {
        Box::pin(ChatHistory::page_after(self, request, budget))
    }
    fn item<'a>(&'a self, id: &'a str) -> BoxFuture<'a, Result<Option<ChatItem>, ChatError>> {
        Box::pin(ChatHistory::item(self, id))
    }
    fn validate_content<'a>(
        &'a self,
        content: &'a ChatContent,
    ) -> BoxFuture<'a, Result<(), ChatError>> {
        Box::pin(ChatHistory::validate_content(self, content))
    }
    fn list_contents<'a>(
        &'a self,
        request: &'a ContentManifestRequest,
        budget: &'a dyn ChatBudget,
    ) -> BoxFuture<'a, Result<ContentManifestPage, ChatError>> {
        Box::pin(ChatHistory::list_contents(self, request, budget))
    }
    fn read_content<'a>(
        &'a self,
        request: &'a ContentReadRequest,
    ) -> BoxFuture<'a, Result<ContentWindow, ChatError>> {
        Box::pin(ChatHistory::read_content(self, request))
    }
}

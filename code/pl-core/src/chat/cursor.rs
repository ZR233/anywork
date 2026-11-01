//! Explicit read demand, source-bound exclusive continuations and generic payload delivery.

use crate::chat::{ChatError, ChatItemHeader, ChatQuery};
use std::sync::Arc;

pub const MAX_READ_ITEMS: usize = 4096;
pub const MAX_READ_BYTES: usize = 8 * 1024 * 1024;

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct TimelineEpoch(String);
impl TimelineEpoch {
    pub fn new(epoch: impl Into<String>) -> Result<Self, ChatError> {
        let epoch = epoch.into();
        if epoch.is_empty() {
            return Err(ChatError::InvalidArgument("empty timeline epoch".into()));
        }
        Ok(Self(epoch))
    }
    pub fn as_str(&self) -> &str {
        &self.0
    }
}

/// Internal catch-up position, not a product cursor.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatCompletionCursor {
    pub epoch: TimelineEpoch,
    pub append_seq: u64,
}
impl ChatCompletionCursor {
    pub fn new(epoch: TimelineEpoch, append_seq: u64) -> Self {
        Self { epoch, append_seq }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ReadDemand {
    pub max_items: usize,
    pub max_bytes: usize,
}
impl ReadDemand {
    pub fn new(max_items: usize, max_bytes: usize) -> Self {
        Self {
            max_items,
            max_bytes,
        }
    }
    pub fn validate(&self) -> Result<(), ChatError> {
        if !(1..=MAX_READ_ITEMS).contains(&self.max_items)
            || !(1..=MAX_READ_BYTES).contains(&self.max_bytes)
        {
            return Err(ChatError::InvalidDemand(
                "unsupported item or byte demand".into(),
            ));
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PayloadMode {
    Inline,
    Deferred,
}

/// Host encoding contract. Costs are conservative upper bounds on actual encoded bytes, not RAM
/// sizes. `fixed_bytes` reserves the batch/header/current/cursor; `item_bytes` includes identity,
/// envelope, length and all encoding expansion. It must inspect headers only, remain synchronous,
/// and never call Session or perform IO. There is deliberately no default codec or preview limit.
pub trait ChatBudget: Send + Sync {
    fn fixed_bytes(&self) -> usize;
    fn item_bytes(&self, header: &ChatItemHeader, mode: PayloadMode) -> usize;
    fn manifest_bytes(&self, descriptor: &super::ContentDescriptor) -> usize;
}

/// Select before reading payload bytes. None means stop at this item, never skip it for older rows.
pub fn select_payload(
    header: &ChatItemHeader,
    remaining: usize,
    budget: &dyn ChatBudget,
) -> Option<PayloadMode> {
    if budget.item_bytes(header, PayloadMode::Inline) <= remaining {
        Some(PayloadMode::Inline)
    } else if budget.item_bytes(header, PayloadMode::Deferred) <= remaining {
        Some(PayloadMode::Deferred)
    } else {
        None
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PayloadData {
    Inline(Arc<[u8]>),
    Deferred { item_id: String, byte_length: u64 },
}
impl PayloadData {
    pub fn mode(&self) -> PayloadMode {
        match self {
            Self::Inline(_) => PayloadMode::Inline,
            Self::Deferred { .. } => PayloadMode::Deferred,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatPageItem {
    pub header: ChatItemHeader,
    pub payload: PayloadData,
}

/// Bound to both source epoch and query membership; ceiling stays fixed across old pages.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatCursor {
    pub epoch: TimelineEpoch,
    pub query: ChatQuery,
    pub ceiling: u64,
    pub append_seq: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatPageRequest {
    pub query: ChatQuery,
    pub demand: ReadDemand,
    pub before: Option<ChatCursor>,
    pub ceiling: Option<u64>,
}
impl ChatPageRequest {
    pub fn latest(query: ChatQuery, demand: ReadDemand) -> Self {
        Self {
            query,
            demand,
            before: None,
            ceiling: None,
        }
    }
    pub fn before(cursor: ChatCursor, demand: ReadDemand) -> Self {
        Self {
            query: cursor.query.clone(),
            ceiling: Some(cursor.ceiling),
            before: Some(cursor),
            demand,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatPage {
    pub epoch: TimelineEpoch,
    /// Captured H0, including out-of-scope completions. Tail delivery starts here.
    pub ceiling: u64,
    pub items: Vec<ChatPageItem>,
    /// A continuation is permission to ask again, not an exact hasOlder assertion.
    pub before: Option<ChatCursor>,
}

/// Port request: demand already excludes fixed overhead and any items taken from pending.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatHistoryRequest {
    pub query: Option<ChatQuery>,
    pub after: u64,
    pub before: Option<u64>,
    pub ceiling: u64,
    pub demand: ReadDemand,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct ChatHistoryPage {
    pub items: Vec<ChatPageItem>,
    /// Only true when natural iteration exhausted the requested interval. No existence query needed.
    pub exhausted: bool,
}

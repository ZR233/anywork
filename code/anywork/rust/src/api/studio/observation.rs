//! Transport values common to typed read scopes; no business payload or mutable state lives here.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeReadText {
    Inline { text: String },
    Deferred { field_id: u64, utf8_bytes: u64 },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTextChunk {
    pub field_id: u64,
    pub offset: u64,
    pub text: String,
    pub next_offset: Option<u64>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct BridgeTypedListRef { pub list_id: u64, pub total: u64 }

impl From<pl_protocol::studio::ReadText> for BridgeReadText {
    fn from(value: pl_protocol::studio::ReadText) -> Self {
        match value {
            pl_protocol::studio::ReadText::Inline { text } => Self::Inline { text },
            pl_protocol::studio::ReadText::Deferred { field_id, utf8_bytes } => Self::Deferred { field_id, utf8_bytes },
        }
    }
}

impl From<pl_protocol::studio::TextChunk> for BridgeTextChunk {
    fn from(value: pl_protocol::studio::TextChunk) -> Self {
        Self { field_id: value.field_id, offset: value.offset, text: value.text, next_offset: value.next_offset }
    }
}

impl From<pl_protocol::studio::TypedListRef> for BridgeTypedListRef {
    fn from(value: pl_protocol::studio::TypedListRef) -> Self {
        Self { list_id: value.list_id, total: value.total }
    }
}

impl From<pl_protocol::studio::StudioShutdownIssue> for super::types::BridgeShutdownIssue {
    fn from(value: pl_protocol::studio::StudioShutdownIssue) -> Self {
        Self { stage: value.stage, code: value.code, message: value.message,
            retryable: value.retryable, correlation_id: value.correlation_id }
    }
}

impl From<pl_protocol::studio::FeedCloseIssue> for super::types::BridgeFeedCloseIssue {
    fn from(value: pl_protocol::studio::FeedCloseIssue) -> Self {
        use pl_protocol::studio::CleanupRecovery;
        use super::types::BridgeCleanupRecovery;
        Self { diagnostic: value.diagnostic.into(), recovery: match value.recovery {
            CleanupRecovery::AwaitCompletion => BridgeCleanupRecovery::AwaitCompletion,
            CleanupRecovery::RetryClose => BridgeCleanupRecovery::RetryClose,
            CleanupRecovery::Terminal => BridgeCleanupRecovery::Terminal,
        } }
    }
}

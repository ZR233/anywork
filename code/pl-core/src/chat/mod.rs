//! Product-independent completion owner, scoped demand reads and immutable content ranges.
//! Business payloads and public protocol mapping belong to the producer/host, not Core.

mod cursor;
mod detail;
mod error;
mod history;
mod item;
mod read;
#[cfg(test)]
mod run_tests;
mod session;
mod tail;

pub use cursor::{
    CHAT_CURSOR_VERSION, CHAT_INDEX_VERSION, ChatBudget, ChatCompletionCursor, ChatCursor,
    ChatHistoryItemRequest, ChatHistoryPage, ChatHistoryRequest, ChatItemRequest, ChatPage,
    ChatPageItem, ChatPageRequest, MAX_READ_BYTES, MAX_READ_ITEMS, PayloadData, PayloadMode,
    ReadDemand, TimelineEpoch, select_payload,
};
pub use detail::{
    ChatContent, ChatContentKey, ContentBytes, ContentData, ContentDescriptor, ContentManifestPage,
    ContentManifestRequest, ContentReadRequest, ContentRef, ContentWindow, IndexedText,
};
pub use error::ChatError;
pub use history::ChatHistory;
pub use item::{
    ChatContents, ChatDraft, ChatItem, ChatItemHeader, ChatKey, ChatPublicationSeed, ChatQuery,
    ChatReadHint, ChatRunPosition, ChatRunSeed, ChatSelection, PresentationPart,
    presentation_item_id, presentation_prefix,
};
pub use session::{Session, WeakSession};
pub use tail::{ChatCompletedBatch, ChatTail, ChatTailBaseline, ChatTailUpdate};

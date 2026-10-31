//! Product-independent completion owner, scoped demand reads and immutable content ranges.
//! Business payloads and public protocol mapping belong to the producer/host, not Core.

mod cursor;
mod detail;
mod error;
mod history;
mod item;
mod read;
mod session;
mod tail;

pub use cursor::{
    ChatBudget, ChatCompletionCursor, ChatCursor, ChatHistoryPage, ChatHistoryRequest, ChatPage,
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
    ChatContents, ChatDraft, ChatItem, ChatItemHeader, ChatKey, ChatQuery, PresentationPart,
    presentation_item_id, presentation_prefix,
};
pub use session::{Session, WeakSession};
pub use tail::{ChatCompletedBatch, ChatTail, ChatTailBaseline, ChatTailUpdate};

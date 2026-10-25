//! Timeline 内容源：无状态 keyset 页、有界尾部订阅与按身份详情。
//!
//! 会话只拥有事实与有界预览，不拥有可见行、阅读位置或视口几何。因此这里没有窗口、焦点、双向
//! 翻页或“展开整条”的操作回执：
//!
//! - [`Session::page`] 读一页最新或更旧的 keyset 页，返回升序轻量条目、下一条边界与 `has_older`；
//! - [`Session::subscribe_tail`] 建立一条有界尾部订阅，先给出一致基线，再交付连续补丁或显式重同步；
//! - [`Session::read_detail`] 按 item／field／revision 分块读取完整正文，不物化整段历史。
//! - [`Session::read_metadata`] 按给定身份读取当前元数据，不保留或返回正文。
//!
//! 生产者仍在这里准入事实：发布、保存确认、终态标记与顺序分配都是同一份会话状态，可靠待保存事实
//! 在被确认前保持完整正文。预览缓存退出不是事实删除，也不产生尾部 `Remove`。

mod cursor;
mod detail;
mod error;
mod history;
mod item;
mod metadata;
mod read;
pub(crate) mod session;
mod tail;

pub use cursor::{
    ChatCursor, ChatHistoryPage, ChatPage, ChatPageRequest, DEFAULT_PAGE_ITEMS, MAX_PAGE_ITEMS,
    PAGE_PREVIEW_BYTES,
};
pub use detail::{
    ChatDetailChunk, ChatDetailCursor, ChatDetailRequest, DEFAULT_DETAIL_BYTES, MAX_DETAIL_BYTES,
    MIN_DETAIL_BYTES,
};
pub use error::ChatError;
pub use history::{CHAT_ITEM_PREVIEW_BYTES, ChatHistory};
pub use item::{
    CHAT_BODY_FIELD, ChatField, ChatFieldPreview, ChatItem, ChatItemParts, ChatLifecycle,
    PresentationPart, presentation_item_id, presentation_prefix,
};
pub use metadata::{ChatItemMetadata, ChatItemMetadataRead};
pub use session::{Session, WeakSession};
pub use tail::{
    ChatResyncReason, ChatTail, ChatTailBaseline, ChatTailPatch, ChatTailUpdate,
    ChatUpdatePriority, FieldChange, FieldUpdate, TailChange,
};

//! Timeline 内容源：完成集合准入、无状态完成页、完成批次订阅与按身份详情。
//!
//! 会话只拥有完成事实与有界预览，不拥有可见行、阅读位置或视口几何。因此这里没有窗口、焦点、双向
//! 翻页或“展开整条”的操作回执：
//!
//! - [`Session::publish_batch`] 准入一批完整不可变的完成草稿，原子分配完成序号并返回同一份冻结
//!   记录供 writer 提交；[`Session::confirm_durable`] 在真实提交连续前缀后回收 pending；
//! - [`Session::page`] 读一页最新或更旧的 keyset 完成页，返回升序记录、下一条边界、`has_older`
//!   与完成代际；
//! - [`Session::subscribe_tail`] 建立一条有界完成批次订阅：先登记唤醒再捕获一致基线，之后从消费
//!   位置连续补发，不丢完成项、不因落后跳到 head；
//! - [`Session::read_detail`] 按记录／字段／字节偏移分块读取完整正文，不物化整段历史。
//!
//! 运行正文、参数生成、工具进度与待决交互属于实时领域，不进入完成集合；本模块保持产品无关。

mod cursor;
mod detail;
mod error;
mod history;
mod item;
mod read;
pub(crate) mod session;
mod tail;

pub use cursor::{
    ChatCompletionCursor, ChatCursor, ChatHistoryPage, ChatPage, ChatPageRequest,
    DEFAULT_PAGE_ITEMS, MAX_PAGE_ITEMS, PAGE_PREVIEW_BYTES, TimelineEpoch,
};
pub use detail::{
    ChatDetailChunk, ChatDetailCursor, ChatDetailRequest, DEFAULT_DETAIL_BYTES, MAX_DETAIL_BYTES,
    MIN_DETAIL_BYTES,
};
pub use error::ChatError;
pub use history::{CHAT_ITEM_PREVIEW_BYTES, ChatHistory};
pub use item::{
    CHAT_BODY_FIELD, ChatDraft, ChatField, ChatFieldPreview, ChatItem, ChatItemParts,
    PresentationPart, presentation_item_id, presentation_prefix,
};
pub use session::{Session, WeakSession};
pub use tail::{ChatCompletedBatch, ChatTail, ChatTailBaseline, ChatTailUpdate};

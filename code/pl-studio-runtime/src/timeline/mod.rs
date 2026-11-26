//! Unified Native timeline, live status state machine, and MetaEventBus data layer.

pub mod conversation_feed;
pub mod decoder;
pub mod live_status_layer;
pub mod meta_bus;
pub mod models;
mod session_detail;
pub mod timeline_layer;

#[cfg(test)]
mod tests;

pub use conversation_feed::{ConversationFeed, FeedCloseHandle, SessionMetaLayer};
pub use decoder::{
    boundary_item_id, decode_boundary_item, fold_work_group_members, summarize_work_group,
    work_group_item_id,
};
pub use live_status_layer::{LiveStatusDataLayer, STREAMING_TEXT_COALESCE_INTERVAL};
pub use meta_bus::{BusEventSink, MetaEventBus, ThreadMetaEvent};
pub use models::*;
pub use session_detail::{SessionDetailKind, SessionDetailWindow};
pub use timeline_layer::{BODY_CHUNK_READ_BYTES, DEFAULT_TIMELINE_PAGE_ROWS, TimelineDataLayer};

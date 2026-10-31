//! 完成历史和活动事件的 FRB 外观；只进行类型映射，不保存第二份历史。

pub(crate) mod descriptor;
pub use descriptor::*;

use super::{BridgeError, BridgeThreadSubscriptionUpdate};

#[derive(Debug, Clone)]
pub struct BridgeConversationFrame {
    pub thread_id: String,
    pub subscription_id: String,
    pub delivery_sequence: u64,
    pub event: BridgeConversationEvent,
}

#[derive(Debug, Clone)]
pub enum BridgeConversationEvent {
    ActivityContent {
        frame: super::BridgeActivityContentFrame,
        completed: Option<Box<BridgeTimelineUpdate>>,
    },
    State {
        update: Box<BridgeThreadSubscriptionUpdate>,
    },
    ContentBaseline {
        baseline: BridgeTimelineBaseline,
    },
    ContentUpdate {
        update: BridgeTimelineUpdate,
    },
    Failure {
        error: BridgeError,
    },
    Closed,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeContentField {
    Text,
    ThinkingSummary {
        chunk_index: u32,
    },
    ThinkingContent {
        chunk_index: u32,
    },
    ToolArguments,
    ToolResult,
    ToolOutputArtifacts,
    ToolUserInput {
        question_index: u32,
        part: BridgeThreadUserInputFieldPart,
    },
    RawPayload {
        payload_index: u32,
    },
    PlanDocument,
    PlanFeedback,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeThreadUserInputFieldPart {
    Header,
    Question,
    Answer { answer_index: u32 },
    OptionLabel { option_index: u32 },
    OptionDescription { option_index: u32 },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineFieldPreview {
    pub field: BridgeContentField,
    pub text: String,
    pub total_bytes: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeTimelineItem {
    pub header: BridgeTimelineItemHeader,
    pub descriptor: BridgeTimelineDescriptor,
    pub source: BridgeTimelineItemSource,
    pub fields: Vec<BridgeTimelineFieldPreview>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BridgeTimelineItemSource {
    Content,
    ModelRecovery {
        attempt_id: String,
        notice: BridgeTimelineRecoveryNotice,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeTimelineRecoveryNotice {
    Retry,
    Result,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineCompletionCursor {
    pub timeline_epoch: String,
    pub append_seq: u64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeTimelinePage {
    pub timeline_epoch: String,
    pub items: Vec<BridgeTimelineItem>,
    pub before: Option<String>,
    pub has_older: bool,
}

#[derive(Debug, Clone, PartialEq)]
pub struct BridgeTimelineBaseline {
    pub subscription_id: String,
    pub timeline_epoch: String,
    pub items: Vec<BridgeTimelineItem>,
    pub before: Option<String>,
    pub has_older: bool,
    pub completed_cursor: BridgeTimelineCompletionCursor,
}

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeTimelineUpdate {
    Batch {
        subscription_id: String,
        timeline_epoch: String,
        from_seq: u64,
        through_seq: u64,
        items: Vec<BridgeTimelineItem>,
    },
    Reset {
        baseline: BridgeTimelineBaseline,
    },
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineDetailQuery {
    pub timeline_epoch: String,
    pub field: BridgeContentField,
    pub continuation: Option<String>,
    pub max_bytes: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BridgeTimelineDetailChunk {
    pub timeline_epoch: String,
    pub item_id: String,
    pub field: BridgeContentField,
    pub text: String,
    pub total_bytes: u64,
    pub continuation: Option<String>,
}

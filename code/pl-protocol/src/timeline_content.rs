//! 完成历史的 wire 契约：不可变原子、连续完成批次与独立的有界读取。
//!
//! 运行预览、保存水位和 Flutter 展示组不属于完成历史；同一身份发布后不能修订或删除。

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

mod descriptor;
pub use descriptor::*;

pub const TIMELINE_PAGE_ITEMS: usize = 32;
pub const TIMELINE_PAGE_MAX_ITEMS: usize = 100;
pub const TIMELINE_CURSOR_VERSION: u32 = 2;
const PAGE_CURSOR_PREFIX: &str = "tlp2.";
const DETAIL_CURSOR_PREFIX: &str = "tld2.";

/// 正文区域的稳定身份；消费者不解析字段正文来猜测区域。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum ThreadContentField {
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
        part: ThreadUserInputFieldPart,
    },
    RawPayload {
        payload_index: u32,
    },
    /// 历史 Plan 自己的完整文档，不引用当前 Plan。
    PlanDocument,
    PlanFeedback,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum ThreadUserInputFieldPart {
    Header,
    Question,
    Answer { answer_index: u32 },
    OptionLabel { option_index: u32 },
    OptionDescription { option_index: u32 },
}

impl ThreadContentField {
    pub fn token_label(&self) -> String {
        match self {
            Self::Text => "text".to_owned(),
            Self::ThinkingSummary { chunk_index } => format!("thinkingSummary:{chunk_index}"),
            Self::ThinkingContent { chunk_index } => format!("thinkingContent:{chunk_index}"),
            Self::ToolArguments => "toolArguments".to_owned(),
            Self::ToolResult => "toolResult".to_owned(),
            Self::ToolOutputArtifacts => "toolOutputArtifacts".to_owned(),
            Self::ToolUserInput {
                question_index,
                part,
            } => {
                let part = match part {
                    ThreadUserInputFieldPart::Header => "header".to_owned(),
                    ThreadUserInputFieldPart::Question => "question".to_owned(),
                    ThreadUserInputFieldPart::Answer { answer_index } => {
                        format!("answer:{answer_index}")
                    }
                    ThreadUserInputFieldPart::OptionLabel { option_index } => {
                        format!("optionLabel:{option_index}")
                    }
                    ThreadUserInputFieldPart::OptionDescription { option_index } => {
                        format!("optionDescription:{option_index}")
                    }
                };
                format!("toolUserInput:{question_index}:{part}")
            }
            Self::RawPayload { payload_index } => format!("rawPayload:{payload_index}"),
            Self::PlanDocument => "planDocument".to_owned(),
            Self::PlanFeedback => "planFeedback".to_owned(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct TimelineDetailRef {
    pub field: ThreadContentField,
    pub total_bytes: u64,
    pub preview_bytes: u64,
}

/// 一条不可变完成事实。正文仅在预览边界裁剪，身份、完成顺序与完整字节长度保持不变。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineItem {
    pub header: TimelineItemHeader,
    pub descriptor: TimelineDescriptor,
    pub source: TimelineItemSource,
    pub fields: Vec<TimelineFieldPreview>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineFieldPreview {
    pub field: ThreadContentField,
    pub text: String,
    pub total_bytes: u64,
}

impl TimelineFieldPreview {
    pub fn preview_bytes(&self) -> u64 {
        self.text.len() as u64
    }
}

impl TimelineItem {
    pub fn details(&self) -> impl Iterator<Item = TimelineDetailRef> + '_ {
        self.fields.iter().map(|field| TimelineDetailRef {
            field: field.field,
            total_bytes: field.total_bytes,
            preview_bytes: field.preview_bytes(),
        })
    }

    pub fn omitted_bytes(&self) -> u64 {
        self.fields.iter().fold(0_u64, |total, field| {
            total.saturating_add(field.total_bytes.saturating_sub(field.preview_bytes()))
        })
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum TimelineItemSource {
    Content,
    ModelRecovery {
        attempt_id: String,
        notice: TimelineRecoveryNotice,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum TimelineRecoveryNotice {
    Retry,
    Result,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelinePageQuery {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub before: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub limit: Option<u32>,
}

impl TimelinePageQuery {
    pub fn limit(&self) -> Option<usize> {
        self.limit.map(|limit| limit as usize)
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TimelinePage {
    pub thread_id: String,
    pub timeline_epoch: String,
    pub items: Vec<TimelineItem>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub before: Option<String>,
    pub has_older: bool,
}

/// 呈现端实际连续接纳的完成位置；与 deliverySequence、活动 revision 及数据库水位独立。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineCompletionCursor {
    pub timeline_epoch: String,
    pub append_seq: u64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct TimelineTailBaseline {
    pub subscription_id: String,
    pub timeline_epoch: String,
    pub items: Vec<TimelineItem>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub before: Option<String>,
    pub has_older: bool,
    pub completed_cursor: TimelineCompletionCursor,
}

/// 完成项只能追加；落后时从接纳位置补发，只有 epoch 变化可以 reset 完成窗口。
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum TimelineTailUpdate {
    Batch {
        subscription_id: String,
        timeline_epoch: String,
        from_seq: u64,
        through_seq: u64,
        items: Vec<TimelineItem>,
    },
    Reset {
        baseline: TimelineTailBaseline,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineDetailQuery {
    pub timeline_epoch: String,
    pub field: ThreadContentField,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub continuation: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub max_bytes: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub struct TimelineDetailChunk {
    pub thread_id: String,
    pub timeline_epoch: String,
    pub item_id: String,
    pub field: ThreadContentField,
    pub text: String,
    pub total_bytes: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub continuation: Option<String>,
}

/// 严格完成顺序边界，不依赖该条目已经保存。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelinePageCursor {
    pub thread_id: String,
    pub timeline_epoch: String,
    pub append_seq: u64,
    pub item_id: String,
}

impl TimelinePageCursor {
    pub fn encode(&self) -> String {
        format!(
            "{PAGE_CURSOR_PREFIX}{}",
            serde_json::to_string(self).expect("cursor contains serializable primitives")
        )
    }

    pub fn decode(token: &str) -> Option<Self> {
        let cursor: Self = serde_json::from_str(token.strip_prefix(PAGE_CURSOR_PREFIX)?).ok()?;
        (!cursor.thread_id.is_empty()
            && !cursor.timeline_epoch.is_empty()
            && cursor.append_seq > 0
            && cursor.append_seq <= i64::MAX as u64
            && !cursor.item_id.is_empty())
        .then_some(cursor)
    }
}

/// 不可变详情 continuation 绑定 Thread、epoch、item、字段和 UTF-8 字节偏移。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct TimelineDetailCursor {
    pub thread_id: String,
    pub timeline_epoch: String,
    pub item_id: String,
    pub field: String,
    pub offset: u64,
}

impl TimelineDetailCursor {
    pub fn encode(&self) -> String {
        format!(
            "{DETAIL_CURSOR_PREFIX}{}",
            serde_json::to_string(self).expect("cursor contains serializable primitives")
        )
    }

    pub fn decode(token: &str) -> Option<Self> {
        let cursor: Self = serde_json::from_str(token.strip_prefix(DETAIL_CURSOR_PREFIX)?).ok()?;
        (!cursor.thread_id.is_empty()
            && !cursor.timeline_epoch.is_empty()
            && !cursor.item_id.is_empty()
            && !cursor.field.is_empty())
        .then_some(cursor)
    }
}

//! 不可变完成原件及其读取模型。完成级消费者按真实业务条件读取；
//! GUI 的整组交接使用独立 presentation 协议，真实业务当前态仍由 State 维护。

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

mod atom;
mod completed;
pub use atom::*;
pub use completed::*;

use crate::{
    AgentSessionPlanPhase, ThreadActivityKind, ThreadActivityToolState, ThreadStatus, TurnPhase,
    studio::{StudioError, StudioErrorCode, StudioErrorReason},
};

/// 资源准入上限，不是 UI 默认页大小。
pub const CHAT_READ_MAX_ITEMS: u32 = 4096;
pub const CHAT_BATCH_MAX_BYTES: u32 = 256 * 1024;
pub const CONTENT_WINDOW_MAX_BYTES: u32 = 256 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReadDemand {
    pub max_items: u32,
    pub max_bytes: u32,
}

impl ReadDemand {
    /// `minimum_bytes` 是该作用域实际轻量信封的编码大小，包含身份和引用。
    pub fn validate(self, minimum_bytes: usize) -> Result<Self, StudioError> {
        if self.max_items == 0
            || self.max_items > CHAT_READ_MAX_ITEMS
            || self.max_bytes == 0
            || self.max_bytes > CHAT_BATCH_MAX_BYTES
            || (self.max_bytes as usize) < minimum_bytes
        {
            return Err(StudioError::new(
                StudioErrorCode::InvalidArgument,
                "Read demand cannot fit a bounded chat envelope",
                false,
            )
            .with_reason(StudioErrorReason::InvalidDemand, serde_json::Value::Null));
        }
        Ok(self)
    }
}

/// 原件过滤必填，All 必须显式请求；读取权限始终由原租约核验。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(tag = "kind", rename_all = "camelCase", deny_unknown_fields)]
pub enum ChatClassFilter {
    Class { value: String },
    All {},
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChatScope {
    pub query_class: ChatClassFilter,
    pub parent_id: Option<String>,
}

impl ChatScope {
    /// 常规会话原件；parent 必须是真实业务 ChatKey，而非展示组身份。
    pub fn conversation(parent_id: Option<String>) -> Self {
        Self {
            query_class: ChatClassFilter::Class {
                value: "conversation".into(),
            },
            parent_id,
        }
    }

    pub fn query_class(&self) -> Option<&str> {
        match &self.query_class {
            ChatClassFilter::Class { value } => Some(value),
            ChatClassFilter::All {} => None,
        }
    }

    pub fn parent_id(&self) -> Option<&str> {
        self.parent_id.as_deref()
    }

    pub fn is_valid(&self) -> bool {
        self.query_class().is_none_or(|value| !value.is_empty())
            && self
                .parent_id
                .as_ref()
                .is_none_or(|value| !value.is_empty())
    }
}

/// 稳定引用存储身份，而非某个页面的当前选择；读取权限由原 read lease 核验。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContentRef {
    pub database_id: String,
    pub target: ContentTarget,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum ContentTarget {
    ItemPayload { item_id: String },
    Body { owner: ContentOwner, key: String },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum ContentOwner {
    Item {
        item_id: String,
    },
    Current {
        domain: String,
        id: String,
        revision: u64,
    },
    DisplayObservation {
        block_id: String,
        member_key: String,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum PayloadData {
    Inline {
        bytes: Vec<u8>,
    },
    Deferred {
        reference: ContentRef,
        byte_length: u64,
    },
}

/// 小 current 与完成切点一起发布，不包含完整 ThreadSnapshot/上下文或增长集合。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentProjection {
    pub source_effect_seq: u64,
    pub logical_status: ThreadStatus,
    /// 是否存在当前执行来源；持久化 running 不能单独证明这一事实。
    pub execution_present: bool,
    pub active: Option<CurrentActivityHead>,
    pub active_turn: Option<CurrentTurnHead>,
    /// Actual execution source states. These are not presentation boundaries.
    pub sources: Vec<ChatSourceState>,
    /// Actual activity atoms; not completed history or a work-group index.
    pub atoms: Vec<ChatAtom>,
    pub plan: Option<CurrentPlanHead>,
    pub interactions: Option<CurrentCollectionRef>,
    pub previews: Vec<CurrentContentPreview>,
    pub collections: Vec<CurrentCollectionRef>,
}

/// 与 ThreadActivity 的完整活动工具集合分离；增长成员只由 collections 按需交付。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentActivityHead {
    pub id: String,
    pub kind: ThreadActivityKind,
    pub summary: String,
    pub thinking_summary: Option<String>,
    pub thinking_seconds: Option<u64>,
    pub tool_count: u32,
    pub background_tool_count: u32,
    pub latest_tool: Option<CurrentToolHead>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentToolHead {
    pub call_id: String,
    pub name: String,
    pub state: ThreadActivityToolState,
}

impl CurrentProjection {
    pub fn empty(source_effect_seq: u64, logical_status: ThreadStatus) -> Self {
        Self {
            source_effect_seq,
            logical_status,
            execution_present: false,
            active: None,
            active_turn: None,
            sources: Vec::new(),
            atoms: Vec::new(),
            plan: None,
            interactions: None,
            previews: Vec::new(),
            collections: Vec::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentTurnHead {
    pub id: String,
    pub phase: TurnPhase,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentPlanHead {
    pub revision: u64,
    pub phase: AgentSessionPlanPhase,
    pub document: Option<ContentRef>,
}

/// Read-only resource heads from the same accepted Plan/interaction state.
/// These are not a second mutable business model or a persistent history row.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ThreadBusinessRefs {
    pub plan: Option<CurrentPlanHead>,
    pub interactions: Option<CurrentCollectionRef>,
}

impl ThreadBusinessRefs {
    /// Only for a genuinely new state with no established business resources.
    pub fn empty() -> Self {
        Self {
            plan: None,
            interactions: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentCollectionRef {
    pub database_id: String,
    pub collection: String,
    pub revision: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum CurrentContentRole {
    Reasoning,
    Response,
    ToolArguments,
    ToolOutput,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentContentPreview {
    pub id: String,
    pub role: CurrentContentRole,
    /// Original canonical text channel; display role alone never grants outbound eligibility.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text_channel: Option<crate::ThreadTextChannel>,
    pub text: String,
    pub reference: ContentRef,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContentRange {
    pub offset: u64,
    pub max_bytes: u32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContentWindow {
    pub offset: u64,
    pub bytes: Vec<u8>,
    pub generation: String,
    pub available_through: u64,
    pub sealed: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContentManifestEntry {
    pub key: String,
    /// Producer 明确提交的通用目录描述，不是工具字段枚举。
    pub payload: Vec<u8>,
    pub reference: ContentRef,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ContentManifestPage {
    pub entries: Vec<ContentManifestEntry>,
    pub continuation: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentCollectionEntry {
    pub id: String,
    pub position: i64,
    pub payload: PayloadData,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct CurrentCollectionPage {
    pub revision: u64,
    pub entries: Vec<CurrentCollectionEntry>,
    pub continuation: Option<String>,
}

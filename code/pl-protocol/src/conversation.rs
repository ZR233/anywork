//! 按需聊天交付的唯一产品模型。完成顺序和源资格由 Rust owner 持有。

use serde::{Deserialize, Serialize};
use utoipa::ToSchema;

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

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum ChatScope {
    Main,
    Children { parent_id: String },
}

impl ChatScope {
    pub fn query_class(&self) -> &'static str {
        match self {
            Self::Main => "conversation",
            Self::Children { .. } => "activity",
        }
    }

    pub fn parent_id(&self) -> Option<&str> {
        match self {
            Self::Main => None,
            Self::Children { parent_id } => Some(parent_id),
        }
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
}

/// SQL/pending 完成记录不是这条对外消息；不在此复制 seq、class 或 parent。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChatMessage {
    pub id: String,
    pub payload: PayloadData,
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

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase")]
pub enum ChatPlacement {
    Set,
    Prepend,
    Append,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ChatBatch {
    pub placement: ChatPlacement,
    pub messages: Vec<ChatMessage>,
    pub before: Option<String>,
    /// None 保持不变；具体快照内 active=None 才明确退役活动。
    pub current: Option<CurrentProjection>,
}

impl ChatBatch {
    /// 在 Rust 构造/发送边界核验组合，不向 SDK 下放业务切点验证。
    pub fn validate_for(&self, scope: &ChatScope) -> Result<(), StudioError> {
        let valid = match (self.placement, scope) {
            (ChatPlacement::Set, ChatScope::Main) => self.current.is_some(),
            (ChatPlacement::Set | ChatPlacement::Prepend, ChatScope::Children { .. })
            | (ChatPlacement::Prepend, ChatScope::Main) => self.current.is_none(),
            (ChatPlacement::Append, ChatScope::Main) => {
                self.before.is_none() && (!self.messages.is_empty() || self.current.is_some())
            }
            (ChatPlacement::Append, ChatScope::Children { .. }) => {
                self.before.is_none() && self.current.is_none() && !self.messages.is_empty()
            }
        };
        if !valid {
            return Err(StudioError::new(
                StudioErrorCode::Internal,
                "Invalid chat placement, continuation or current projection",
                false,
            ));
        }
        Ok(())
    }

    /// HTTP 的规范编码计量；FRB 外层继续核验自己的 Frame 编码上限。
    pub fn encoded_len(&self) -> Result<usize, serde_json::Error> {
        serde_json::to_vec(self).map(|bytes| bytes.len())
    }
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

#[cfg(test)]
mod tests {
    use super::*;

    fn batch(placement: ChatPlacement) -> ChatBatch {
        ChatBatch {
            placement,
            messages: Vec::new(),
            before: None,
            current: None,
        }
    }

    #[test]
    fn placement_preserves_the_current_and_continuation_boundaries() {
        let children = ChatScope::Children {
            parent_id: "turn:one".into(),
        };
        let mut initial = batch(ChatPlacement::Set);
        assert!(initial.validate_for(&ChatScope::Main).is_err());
        assert!(initial.validate_for(&children).is_ok());
        initial.current = Some(CurrentProjection::empty(7, ThreadStatus::Idle));
        assert!(initial.validate_for(&ChatScope::Main).is_ok());
        assert!(initial.validate_for(&children).is_err());

        let mut append = batch(ChatPlacement::Append);
        assert!(append.validate_for(&ChatScope::Main).is_err());
        append.current = initial.current;
        assert!(append.validate_for(&ChatScope::Main).is_ok());
        append.before = Some("opaque".into());
        assert!(append.validate_for(&ChatScope::Main).is_err());

        let eof = batch(ChatPlacement::Prepend);
        assert!(eof.validate_for(&ChatScope::Main).is_ok());
        assert!(eof.validate_for(&children).is_ok());
    }

    #[test]
    fn demand_and_encoding_count_the_actual_envelope_not_only_payload() {
        let minimum = batch(ChatPlacement::Prepend).encoded_len().unwrap();
        assert!(
            ReadDemand {
                max_items: 1,
                max_bytes: minimum as u32 - 1,
            }
            .validate(minimum)
            .is_err()
        );
        let mut value = batch(ChatPlacement::Prepend);
        value.messages.push(ChatMessage {
            id: "one".into(),
            payload: PayloadData::Inline {
                bytes: "中文🦀".as_bytes().to_vec(),
            },
        });
        assert!(value.encoded_len().unwrap() > minimum + "中文🦀".len());
        let round_trip: ChatBatch =
            serde_json::from_slice(&serde_json::to_vec(&value).unwrap()).unwrap();
        assert_eq!(value, round_trip);
    }
}

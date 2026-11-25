//! 仅用于执行投影的局部类型；旧持久 JSON 仅由 schema 的冻结解码器读取。
use crate::protocol::*;
use serde::{Deserialize, Serialize};

/// Runtime 内部有界执行投影。正文只在转换期间物化，不作为持久化或 wire 记录。
#[derive(Debug, Clone, Serialize, PartialEq)]
#[cfg_attr(test, derive(Deserialize))]
#[serde(rename_all = "camelCase")]
pub(crate) struct ExecutionItem {
    pub id: String,
    pub thread_id: String,
    pub turn_id: String,
    pub ordinal: u64,
    pub revision: u64,
    pub created_at: i64,
    pub updated_at: i64,
    state: ExecutionShape,
}

/// Identity, order and timestamps shared by one projected execution item.
///
/// Text may be borrowed until [`ExecutionItem::new`] copies it into the owned item.
#[derive(Debug, Clone)]
pub(crate) struct ItemStamp<'a> {
    pub(crate) thread_id: std::borrow::Cow<'a, str>,
    pub(crate) turn_id: std::borrow::Cow<'a, str>,
    pub(crate) ordinal: u64,
    pub(crate) revision: u64,
    pub(crate) created_at: i64,
    pub(crate) updated_at: i64,
}

impl ExecutionItem {
    pub fn new(id: String, stamp: ItemStamp<'_>, state: ExecutionShape) -> Self {
        Self {
            id,
            thread_id: stamp.thread_id.into_owned(),
            turn_id: stamp.turn_id.into_owned(),
            ordinal: stamp.ordinal,
            revision: stamp.revision,
            created_at: stamp.created_at,
            updated_at: stamp.updated_at,
            state,
        }
    }

    pub fn state(&self) -> &ExecutionShape {
        &self.state
    }

    /// Rebuilds the item with the given state, keeping identity, ordinal, revision and timestamps.
    ///
    /// The projection uses this at a materialization boundary to inject the
    /// streamed text back into a canonical item whose static structure was stored once, so the text
    /// never has to be re-encoded into the durable payload on the hot path.
    pub fn with_state(mut self, state: ExecutionShape) -> Self {
        self.state = state;
        self
    }

    pub fn is_terminal(&self) -> bool {
        self.state.is_terminal()
    }

    pub fn text(&self) -> Option<&ThreadTextItem> {
        match &self.state {
            ExecutionShape::Text(value) => Some(value),
            ExecutionShape::Thinking(_)
            | ExecutionShape::Tool(_)
            | ExecutionShape::Agent(_)
            | ExecutionShape::Turn(_)
            | ExecutionShape::Inference(_)
            | ExecutionShape::Skill(_)
            | ExecutionShape::File(_)
            | ExecutionShape::Raw(_)
            | ExecutionShape::ContextCompaction(_) => None,
        }
    }

    pub fn tool(&self) -> Option<&ThreadToolItem> {
        match &self.state {
            ExecutionShape::Tool(value) => Some(value),
            ExecutionShape::Text(_)
            | ExecutionShape::Thinking(_)
            | ExecutionShape::Agent(_)
            | ExecutionShape::Turn(_)
            | ExecutionShape::Inference(_)
            | ExecutionShape::Skill(_)
            | ExecutionShape::File(_)
            | ExecutionShape::Raw(_)
            | ExecutionShape::ContextCompaction(_) => None,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(tag = "kind", content = "data", rename_all = "camelCase")]
pub(crate) enum ExecutionShape {
    Raw(ThreadRawItem),
    Text(ThreadTextItem),
    Thinking(ThreadThinkingItem),
    Tool(ThreadToolItem),
    Agent(ThreadAgentItem),
    Turn(ThreadTurnItem),
    Inference(ThreadInferenceItem),
    Skill(ThreadSkillItem),
    File(ThreadFileItem),
    ContextCompaction(ThreadContextCompactionItem),
}

impl ExecutionShape {
    pub fn is_terminal(&self) -> bool {
        match self {
            Self::Text(value) => value.lifecycle().is_terminal(),
            Self::Thinking(value) => value.lifecycle().is_terminal(),
            Self::Tool(value) => value.state().is_terminal(),
            Self::Agent(value) => value.state().is_terminal(),
            Self::Turn(value) => value.state().is_terminal(),
            Self::Inference(value) => value.state().is_terminal(),
            Self::Raw(_) | Self::Skill(_) | Self::File(_) | Self::ContextCompaction(_) => true,
        }
    }

    pub fn terminal_at(&self) -> Option<i64> {
        match self {
            Self::Text(value) => value.lifecycle().terminal_at(),
            Self::Thinking(value) => value.lifecycle().terminal_at(),
            Self::Tool(value) => value.state().terminal_at(),
            Self::Agent(value) => value.state().terminal_at(),
            Self::Turn(value) => value.state().completed_at(),
            Self::Inference(value) => value.state().terminal_at(),
            Self::Skill(value) => Some(value.activation().activated_at),
            Self::File(value) => Some(value.completed_at()),
            Self::Raw(value) => Some(value.recorded_at),
            Self::ContextCompaction(value) => Some(value.compacted_at()),
        }
    }
}

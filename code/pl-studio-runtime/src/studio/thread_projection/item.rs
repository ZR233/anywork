//! 仅用于执行投影的局部类型；旧持久 JSON 仅由 schema 的冻结解码器读取。
use pl_protocol::*;
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

impl ExecutionItem {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        id: String,
        thread_id: String,
        turn_id: String,
        ordinal: u64,
        revision: u64,
        created_at: i64,
        updated_at: i64,
        state: ExecutionShape,
    ) -> Self {
        Self {
            id,
            thread_id,
            turn_id,
            ordinal,
            revision,
            created_at,
            updated_at,
            state,
        }
    }

    #[cfg(test)]
    pub fn completed_user_message(
        id: String,
        thread_id: String,
        turn_id: String,
        text: String,
        attachments: Vec<ThreadAttachment>,
        completed_at: i64,
    ) -> Self {
        Self::completed_input_message(
            id,
            thread_id,
            turn_id,
            ThreadTextChannel::User,
            text,
            attachments,
            completed_at,
        )
    }

    /// 创建一条来自当前 Thread 直接父代理的终态文本 Item。
    pub fn completed_parent_agent_message(
        id: String,
        thread_id: String,
        turn_id: String,
        text: String,
        attachments: Vec<ThreadAttachment>,
        completed_at: i64,
    ) -> Self {
        Self::completed_input_message(
            id,
            thread_id,
            turn_id,
            ThreadTextChannel::ParentAgent,
            text,
            attachments,
            completed_at,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn completed_input_message(
        id: String,
        thread_id: String,
        turn_id: String,
        channel: ThreadTextChannel,
        text: String,
        attachments: Vec<ThreadAttachment>,
        completed_at: i64,
    ) -> Self {
        Self::new(
            id,
            thread_id,
            turn_id,
            0,
            0,
            completed_at,
            completed_at,
            ExecutionShape::Text(ThreadTextItem::new(
                channel,
                text,
                attachments,
                ThreadContentLifecycle::completed(completed_at),
            )),
        )
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

    pub fn kind(&self) -> ExecutionKind {
        self.state.kind()
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
    pub fn kind(&self) -> ExecutionKind {
        match self {
            Self::Raw(_) => ExecutionKind::Raw,
            Self::Text(_) => ExecutionKind::Text,
            Self::Thinking(_) => ExecutionKind::Thinking,
            Self::Tool(_) => ExecutionKind::Tool,
            Self::Agent(_) => ExecutionKind::Agent,
            Self::Turn(_) => ExecutionKind::Turn,
            Self::Inference(_) => ExecutionKind::Inference,
            Self::Skill(_) => ExecutionKind::Skill,
            Self::File(_) => ExecutionKind::File,
            Self::ContextCompaction(_) => ExecutionKind::ContextCompaction,
        }
    }

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

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub(crate) enum ExecutionKind {
    Raw,
    Text,
    Thinking,
    Tool,
    Agent,
    Turn,
    Inference,
    Skill,
    File,
    ContextCompaction,
}

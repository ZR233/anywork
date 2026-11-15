//! 领域文本、工具、附件与执行状态事实；不导出可变历史条目协议。

mod agent;
mod content;
mod inference;
mod skill;
mod tool;
mod wait;

use serde::{Deserialize, Serialize};

use crate::TurnState;

pub use agent::*;
pub use content::*;
pub use inference::*;
pub use skill::*;
pub use tool::*;
pub use wait::*;

/// Original producer data shown when a historical codec is absent or unsupported.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadRawPayload {
    pub format: String,
    pub version: u32,
    pub content: String,
}

/// Raw history is a product view; it never changes the saved model context or authorizes execution.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadRawItem {
    #[serde(default, skip_serializing_if = "ThreadRawItemOrigin::is_stored")]
    pub origin: ThreadRawItemOrigin,
    pub payloads: Vec<ThreadRawPayload>,
    pub notice: String,
    pub recorded_at: i64,
}

impl ThreadRawItem {
    /// Producer data this host could not decode into a typed item.
    pub fn stored(
        payloads: Vec<ThreadRawPayload>,
        notice: impl Into<String>,
        recorded_at: i64,
    ) -> Self {
        Self {
            origin: ThreadRawItemOrigin::Stored,
            payloads,
            notice: notice.into(),
            recorded_at,
        }
    }

    /// The runtime sentence a body-less framework control input stands for.
    ///
    /// It carries no payload by definition: the control never held user content, so there is nothing
    /// a reader could expand. Consumers must not infer this shape from an empty payload list,
    /// because a live-window placeholder is also payload-less.
    pub fn runtime_control(notice: impl Into<String>, recorded_at: i64) -> Self {
        Self {
            origin: ThreadRawItemOrigin::RuntimeControl,
            payloads: Vec::new(),
            notice: notice.into(),
            recorded_at,
        }
    }
}

/// Why one raw record exists.
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub enum ThreadRawItemOrigin {
    /// Producer payloads kept verbatim because no typed item could be built from them.
    #[default]
    Stored,
    /// A runtime sentence that replaced a framework control input with no body of its own.
    RuntimeControl,
}

impl ThreadRawItemOrigin {
    fn is_stored(&self) -> bool {
        matches!(self, Self::Stored)
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadTurnItem {
    state: TurnState,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    input_id: Option<String>,
}

impl ThreadTurnItem {
    pub fn new(state: TurnState) -> Self {
        Self {
            state,
            input_id: None,
        }
    }

    /// Preserves the actual input association for history and disconnected subscribers.
    pub fn with_input_id(mut self, input_id: Option<String>) -> Self {
        self.input_id = input_id;
        self
    }

    pub fn input_id(&self) -> Option<&str> {
        self.input_id.as_deref()
    }

    pub fn state(&self) -> &TurnState {
        &self.state
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct ThreadAttachment {
    pub id: String,
    pub modality: crate::AttachmentModality,
    pub media_type: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub filename: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub width: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub height: Option<u32>,
    pub byte_size: u64,
}

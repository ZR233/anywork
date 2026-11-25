use serde::{Deserialize, Serialize};

use super::{Message, ThreadAttachment};

/// 工具结果的紧凑、可持久化收据。
///
/// 完整工具输出不进入 canonical history；history 只保存有界模型视图、内容
/// 哈希和 artifact 引用，以便压缩后仍能确认已经读取过哪些证据。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolResultReceipt {
    pub call_id: String,
    pub tool_name: String,
    pub arguments_hash: String,
    pub result_hash: String,
    pub total_bytes: u64,
    pub visible_bytes: u64,
    pub truncated: bool,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub artifacts: Vec<serde_json::Value>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub continuation: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub reused_from_call_id: Option<String>,
}

/// 必须在 `store: false` Responses 请求中按原顺序回放的 provider 原生 item 类别。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ResponsesContextItemKind {
    Reasoning,
    WebSearchCall,
    Program,
    ProgramOutput,
    Unknown,
}

/// 有界为已知类别、但保留完整 wire 字段的 Responses 上下文项。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ResponsesContextItem {
    pub kind: ResponsesContextItemKind,
    pub value: serde_json::Value,
}

/// 一次工具调用提交给后续模型请求的 durable 媒体引用。
///
/// `attachment` 只包含 Thread 授权的稳定 metadata；bytes 由宿主在请求期
/// materialize。`label` 是模型可见的安全路径标签，不得包含未经授权的宿主路径。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ToolMediaContext {
    pub call_id: String,
    pub label: String,
    pub attachment: ThreadAttachment,
}

impl ResponsesContextItem {
    const NATIVE_FORMAT: &str = "pl.model.openai.responses-context-item";

    pub fn to_payload(&self) -> pl_core::context::OpaquePayload {
        pl_core::context::OpaquePayload::new(
            Self::NATIVE_FORMAT,
            1,
            serde_json::to_string(self).expect("Responses context item is JSON"),
        )
        .expect("valid Responses context envelope")
    }

    pub fn from_payload(payload: &pl_core::context::OpaquePayload) -> pl_protocol::Result<Self> {
        if payload.format() != Self::NATIVE_FORMAT || payload.version() != 1 {
            return Err(crate::provider_error::invalid_request(
                "unrecognized Responses context payload",
            )
            .into());
        }
        serde_json::from_str(payload.content()).map_err(|error| {
            crate::provider_error::invalid_request("malformed Responses context payload")
                .with_source(error)
                .into()
        })
    }

    pub fn from_wire(value: serde_json::Value) -> Option<Self> {
        let kind = match value.get("type").and_then(serde_json::Value::as_str)? {
            "reasoning" => ResponsesContextItemKind::Reasoning,
            "web_search_call" => ResponsesContextItemKind::WebSearchCall,
            "program" => ResponsesContextItemKind::Program,
            "program_output" => ResponsesContextItemKind::ProgramOutput,
            "message"
            | "function_call"
            | "custom_tool_call"
            | "function_call_output"
            | "custom_tool_call_output"
            | "file_search_call"
            | "computer_call"
            | "computer_call_output"
            | "mcp_call"
            | "code_interpreter_call" => return None,
            _ => ResponsesContextItemKind::Unknown,
        };
        Some(Self { kind, value })
    }
}

/// Provider 无关的模型上下文项。
///
/// 普通对话通过 [`ModelContextItem::Message`] 表达；provider 返回的不可读
/// checkpoint 通过 [`ModelContextItem::Compaction`] 表达。调用方不得把加密
/// checkpoint 当作普通 system/user 文本发送给不支持它的 provider。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "camelCase")]
pub enum ModelContextItem {
    Message {
        message: Message,
    },
    ToolResult {
        /// 可直接投影到 provider wire 的 tool message；其正文即有界 model view。
        message: Message,
        receipt: ToolResultReceipt,
    },
    ToolMedia {
        items: Vec<ToolMediaContext>,
    },
    Compaction {
        #[serde(rename = "encryptedContent")]
        encrypted_content: String,
    },
    #[serde(rename = "responses")]
    Native {
        // The stored OpenAI binding keeps the existing Responses history shape.
        #[serde(rename = "item", with = "responses_context_serde")]
        payload: pl_core::context::OpaquePayload,
    },
}

impl From<ResponsesContextItem> for ModelContextItem {
    fn from(item: ResponsesContextItem) -> Self {
        Self::Native {
            payload: item.to_payload(),
        }
    }
}

mod responses_context_serde {
    use super::*;
    use pl_core::context::OpaquePayload;
    use serde::{Deserializer, Serializer};

    pub(super) fn serialize<S: Serializer>(
        payload: &OpaquePayload,
        serializer: S,
    ) -> Result<S::Ok, S::Error> {
        ResponsesContextItem::from_payload(payload)
            .map_err(serde::ser::Error::custom)?
            .serialize(serializer)
    }

    pub(super) fn deserialize<'de, D: Deserializer<'de>>(
        deserializer: D,
    ) -> Result<OpaquePayload, D::Error> {
        ResponsesContextItem::deserialize(deserializer).map(|item| item.to_payload())
    }
}

impl ModelContextItem {
    pub fn as_message(&self) -> Option<&Message> {
        match self {
            Self::Message { message } => Some(message),
            Self::ToolResult { message, .. } => Some(message),
            Self::ToolMedia { .. } | Self::Compaction { .. } | Self::Native { .. } => None,
        }
    }

    pub fn into_message(self) -> Option<Message> {
        match self {
            Self::Message { message } => Some(message),
            Self::ToolResult { message, .. } => Some(message),
            Self::ToolMedia { .. } | Self::Compaction { .. } | Self::Native { .. } => None,
        }
    }

    pub fn is_compaction(&self) -> bool {
        matches!(self, Self::Compaction { .. })
    }

    pub fn as_tool_result_receipt(&self) -> Option<&ToolResultReceipt> {
        match self {
            Self::ToolResult { receipt, .. } => Some(receipt),
            Self::Message { .. }
            | Self::ToolMedia { .. }
            | Self::Compaction { .. }
            | Self::Native { .. } => None,
        }
    }
}

impl From<Message> for ModelContextItem {
    fn from(message: Message) -> Self {
        Self::Message { message }
    }
}

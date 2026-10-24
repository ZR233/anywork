//! 机器人会话工具前端。注册、凭据与授权管理不开放给模型。
use pl_core::{
    context::OpaquePayload,
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, RegistryError, Tool, ToolError},
    },
};
use schemars::JsonSchema;
use serde::Deserialize;
use std::sync::Arc;

use crate::input::{deserialize_tool_input, typed_tool_input_schema};

#[derive(Debug, Clone, Copy)]
pub enum BotToolKind {
    ListBots,
    ListConversations,
    ReadMessages,
    SendMessage,
}

pub trait BotSessionHost: Send + Sync + std::fmt::Debug + 'static {
    fn list_bots(
        &self,
        project_id: &str,
    ) -> impl std::future::Future<Output = Result<ToolOutput, ToolError>> + Send;
    fn list_conversations(
        &self,
        project_id: &str,
        bot_id: String,
        cursor: Option<String>,
        limit: Option<u32>,
    ) -> impl std::future::Future<Output = Result<ToolOutput, ToolError>> + Send;
    fn read_messages(
        &self,
        project_id: &str,
        request: ReadMessagesInput,
    ) -> impl std::future::Future<Output = Result<ToolOutput, ToolError>> + Send;
    fn send_message(
        &self,
        project_id: &str,
        operation_id: String,
        bot_id: String,
        chat_id: String,
        text: String,
    ) -> impl std::future::Future<Output = Result<ToolOutput, ToolError>> + Send;
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Empty {}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ListConversationsInput {
    bot_id: String,
    #[serde(default)]
    cursor: Option<String>,
    #[serde(default)]
    limit: Option<u32>,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ReadMessagesInput {
    pub bot_id: String,
    pub chat_id: String,
    #[serde(default)]
    pub start_time: Option<i64>,
    #[serde(default)]
    pub end_time: Option<i64>,
    #[serde(default)]
    pub cursor: Option<String>,
    #[serde(default)]
    pub limit: Option<u32>,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SendMessageInput {
    bot_id: String,
    chat_id: String,
    text: String,
}

#[derive(Debug)]
pub struct ThreadBotTool<H> {
    host: Arc<H>,
    kind: BotToolKind,
    project_id: String,
}

impl<H: BotSessionHost> ThreadBotTool<H> {
    pub fn new(host: Arc<H>, kind: BotToolKind, project_id: String) -> Self {
        Self {
            host,
            kind,
            project_id,
        }
    }

    pub fn registration(self, declaration: OpaquePayload) -> Result<Registration, RegistryError> {
        let name = self.kind.name();
        let kind = self.kind;
        let registration = Registration::new(name.into(), declaration, self)?;
        Ok(match kind {
            BotToolKind::SendMessage => registration.foreground(),
            BotToolKind::ListBots | BotToolKind::ListConversations | BotToolKind::ReadMessages => {
                registration
            }
        })
    }
}

impl BotToolKind {
    pub fn name(self) -> &'static str {
        match self {
            Self::ListBots => "list_bots",
            Self::ListConversations => "list_bot_conversations",
            Self::ReadMessages => "read_bot_messages",
            Self::SendMessage => "send_bot_message",
        }
    }

    pub fn declaration(self) -> pl_protocol::ToolSpec {
        match self {
            Self::ListBots => pl_protocol::ToolSpec::function(
                self.name(),
                "List bots authorized for the current project. Returns ids, names, connection state and capabilities without credentials.",
                typed_tool_input_schema::<Empty>(),
            ),
            Self::ListConversations => pl_protocol::ToolSpec::function(
                self.name(),
                "List group chats the bot belongs to and locally observed direct chats. Pagination cursor is bound to the bot.",
                typed_tool_input_schema::<ListConversationsInput>(),
            ),
            Self::ReadMessages => pl_protocol::ToolSpec::function(
                self.name(),
                "Read typed bot messages for one chat. Unsupported media is reported explicitly and is not treated as an attachment.",
                typed_tool_input_schema::<ReadMessagesInput>(),
            ),
            Self::SendMessage => pl_protocol::ToolSpec::function(
                self.name(),
                "Send Markdown through a project-authorized bot. Oversized content is delivered as a complete Markdown file with a short notice. This is an external write and is not a readonly or programmatic tool.",
                typed_tool_input_schema::<SendMessageInput>(),
            ),
        }
    }
}

impl<H: BotSessionHost> Tool for ThreadBotTool<H> {
    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        if input.format() != "application/json" || input.version() != 1 {
            return Err(ToolError::new(std::io::Error::other(
                "unsupported bot tool encoding",
            )));
        }
        if context.cancellation.is_cancelled() {
            return Err(ToolError::new(pl_core::thread::ThreadError::Cancelled));
        }
        let value: serde_json::Value =
            serde_json::from_str(input.content()).map_err(ToolError::new)?;
        match self.kind {
            BotToolKind::ListBots => {
                deserialize_tool_input::<Empty>(self.kind.name(), value).map_err(ToolError::new)?;
                self.host.list_bots(&self.project_id).await
            }
            BotToolKind::ListConversations => {
                let input =
                    deserialize_tool_input::<ListConversationsInput>(self.kind.name(), value)
                        .map_err(ToolError::new)?;
                self.host
                    .list_conversations(&self.project_id, input.bot_id, input.cursor, input.limit)
                    .await
            }
            BotToolKind::ReadMessages => {
                let input = deserialize_tool_input::<ReadMessagesInput>(self.kind.name(), value)
                    .map_err(ToolError::new)?;
                self.host.read_messages(&self.project_id, input).await
            }
            BotToolKind::SendMessage => {
                let input = deserialize_tool_input::<SendMessageInput>(self.kind.name(), value)
                    .map_err(ToolError::new)?;
                self.host
                    .send_message(
                        &self.project_id,
                        context.call_id.clone(),
                        input.bot_id,
                        input.chat_id,
                        input.text,
                    )
                    .await
            }
        }
    }
}

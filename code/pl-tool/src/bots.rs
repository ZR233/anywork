//! 机器人会话工具前端。注册、凭据与授权管理不开放给模型。
use pl_core::{
    context::OpaquePayload,
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, ToolError},
    },
};
use schemars::JsonSchema;
use serde::Deserialize;
use std::sync::Arc;

use pl_agent_tool::typed::{decode_json, input_schema_for};

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
        workspace_id: &str,
    ) -> impl std::future::Future<Output = Result<ToolOutput, ToolError>> + Send;
    fn list_conversations(
        &self,
        workspace_id: &str,
        bot_id: String,
        cursor: Option<String>,
        limit: Option<u32>,
    ) -> impl std::future::Future<Output = Result<ToolOutput, ToolError>> + Send;
    fn read_messages(
        &self,
        workspace_id: &str,
        request: ReadMessagesInput,
    ) -> impl std::future::Future<Output = Result<ToolOutput, ToolError>> + Send;
    fn send_message(
        &self,
        workspace_id: &str,
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
    definition: pl_agent_tool::ToolDefinition,
    host: Arc<H>,
    kind: BotToolKind,
    workspace_id: String,
}

impl<H: BotSessionHost> ThreadBotTool<H> {
    pub fn new(
        host: Arc<H>,
        kind: BotToolKind,
        workspace_id: String,
        definition: pl_agent_tool::ToolDefinition,
    ) -> Self {
        Self {
            definition,
            host,
            kind,
            workspace_id,
        }
    }

    pub fn registration(
        self,
        prepared: pl_core::tool::opaque::PreparedRegistration,
    ) -> Registration {
        let kind = self.kind;
        let registration = prepared.attach(pl_agent_tool::ToolHandle::new(self));
        match kind {
            BotToolKind::SendMessage => registration.foreground(),
            BotToolKind::ListBots | BotToolKind::ListConversations | BotToolKind::ReadMessages => {
                registration
            }
        }
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

    pub fn declaration(self) -> pl_agent_tool::ToolDefinition {
        match self {
            Self::ListBots => pl_agent_tool::ToolDefinition::json(
                self.name(),
                "List bots authorized for the current project. Returns ids, names, connection state and capabilities without credentials.",
                input_schema_for::<Empty>(),
            ).expect("valid tool definition"),
            Self::ListConversations => pl_agent_tool::ToolDefinition::json(
                self.name(),
                "List group chats the bot belongs to and locally observed direct chats. Pagination cursor is bound to the bot.",
                input_schema_for::<ListConversationsInput>(),
            ).expect("valid tool definition"),
            Self::ReadMessages => pl_agent_tool::ToolDefinition::json(
                self.name(),
                "Read typed bot messages for one chat. Unsupported media is reported explicitly and is not treated as an attachment.",
                input_schema_for::<ReadMessagesInput>(),
            ).expect("valid tool definition"),
            Self::SendMessage => pl_agent_tool::ToolDefinition::json(
                self.name(),
                "Send a text message through a project-authorized bot. This is an external write and is not a readonly or programmatic tool.",
                input_schema_for::<SendMessageInput>(),
            ).expect("valid tool definition"),
        }
    }
}

impl<H: BotSessionHost> pl_agent_tool::Tool for ThreadBotTool<H> {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        &self.definition
    }

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
        let value = input.content();
        match self.kind {
            BotToolKind::ListBots => {
                decode_json::<Empty>(value).map_err(ToolError::new)?;
                self.host.list_bots(&self.workspace_id).await
            }
            BotToolKind::ListConversations => {
                let input = decode_json::<ListConversationsInput>(value).map_err(ToolError::new)?;
                self.host
                    .list_conversations(&self.workspace_id, input.bot_id, input.cursor, input.limit)
                    .await
            }
            BotToolKind::ReadMessages => {
                let input = decode_json::<ReadMessagesInput>(value).map_err(ToolError::new)?;
                self.host.read_messages(&self.workspace_id, input).await
            }
            BotToolKind::SendMessage => {
                let input = decode_json::<SendMessageInput>(value).map_err(ToolError::new)?;
                self.host
                    .send_message(
                        &self.workspace_id,
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

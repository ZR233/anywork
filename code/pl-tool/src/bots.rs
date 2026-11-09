//! Core registration and payload mapping for the independent bot tools.
use pl_agent_tool::typed::{TypedTool, decode_json};
use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, ToolError},
    },
};
pub use pl_tool_bot_support::{Bot, BotSessionHost, Page, ReadMessages, SendStatus, Sent};
use std::sync::Arc;

#[derive(Debug, Clone, Copy)]
pub enum BotToolKind {
    ListBots,
    ListConversations,
    ReadMessages,
    SendMessage,
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
            Self::ListBots => pl_tool_list_bots::declaration(),
            Self::ListConversations => pl_tool_list_bot_conversations::declaration(),
            Self::ReadMessages => pl_tool_read_bot_messages::declaration(),
            Self::SendMessage => pl_tool_send_bot_message::declaration(),
        }
    }
}
#[derive(Debug)]
pub struct ThreadBotTool<H> {
    definition: pl_agent_tool::ToolDefinition,
    host: Arc<H>,
    kind: BotToolKind,
    workspace_id: String,
}
impl<H: BotSessionHost> ThreadBotTool<H>
where
    H::Connection: serde::Serialize,
    H::Conversation: serde::Serialize,
    H::Message: serde::Serialize,
    H::Segment: serde::Serialize,
    H::Receipt: serde::Serialize,
{
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
            _ => registration,
        }
    }
}
impl<H: BotSessionHost> pl_agent_tool::Tool for ThreadBotTool<H>
where
    H::Connection: serde::Serialize,
    H::Conversation: serde::Serialize,
    H::Message: serde::Serialize,
    H::Segment: serde::Serialize,
    H::Receipt: serde::Serialize,
{
    type Input = OpaquePayload;
    type Context = CallContext;
    type Output = ToolOutput;
    type Error = ToolError;
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
        let host = self.host.clone();
        let scope = self.workspace_id.clone();
        match self.kind {
            BotToolKind::ListBots => output(
                &pl_tool_list_bots::ListBots::new(host, scope)
                    .execute(decode_json(input.content()).map_err(ToolError::new)?, ())
                    .await
                    .map_err(ToolError::new)?,
            ),
            BotToolKind::ListConversations => output(
                &pl_tool_list_bot_conversations::ListBotConversations::new(host, scope)
                    .execute(decode_json(input.content()).map_err(ToolError::new)?, ())
                    .await
                    .map_err(ToolError::new)?,
            ),
            BotToolKind::ReadMessages => output(
                &pl_tool_read_bot_messages::ReadBotMessages::new(host, scope)
                    .execute(decode_json(input.content()).map_err(ToolError::new)?, ())
                    .await
                    .map_err(ToolError::new)?,
            ),
            BotToolKind::SendMessage => output(
                &pl_tool_send_bot_message::SendBotMessage::new(host, scope)
                    .execute(
                        decode_json(input.content()).map_err(ToolError::new)?,
                        context.call_id,
                    )
                    .await
                    .map_err(ToolError::new)?,
            ),
        }
    }
}
fn output(value: &impl serde::Serialize) -> Result<ToolOutput, ToolError> {
    let encoded = serde_json::to_string(value).map_err(ToolError::new)?;
    Ok(ToolOutput::new(
        OpaquePayload::new("pl.studio.bot-tool", 1, encoded.clone()).map_err(ToolError::new)?,
        vec![ContextContent::Text {
            text: encoded.into(),
        }],
    ))
}

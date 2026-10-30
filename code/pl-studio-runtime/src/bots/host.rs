use super::SendAuthority;
use super::owner::BotRuntime;
use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{ToolOutput, opaque::ToolError},
};
use pl_tool::bots::BotSessionHost;
use std::sync::Arc;

#[derive(Clone)]
pub struct StudioBotSessionHost {
    pub runtime: BotRuntime,
}

impl std::fmt::Debug for StudioBotSessionHost {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("StudioBotSessionHost")
    }
}

impl BotSessionHost for StudioBotSessionHost {
    async fn list_bots(&self, workspace_id: &str) -> Result<ToolOutput, ToolError> {
        let bots = self
            .runtime
            .authorized_bots(workspace_id)
            .await
            .into_iter()
            .map(|bot| {
                serde_json::json!({
                    "id": bot.id,
                    "name": bot.name,
                    "connection": bot.connection,
                    "toolsEnabled": bot.tools_enabled,
                })
            })
            .collect::<Vec<_>>();
        output(&bots)
    }

    async fn list_conversations(
        &self,
        workspace_id: &str,
        bot_id: String,
        cursor: Option<String>,
        limit: Option<u32>,
    ) -> Result<ToolOutput, ToolError> {
        self.ensure_tools_enabled(workspace_id, &bot_id).await?;
        let page = self
            .runtime
            .list_conversations(&bot_id, cursor.as_deref(), limit)
            .await
            .map_err(ToolError::new)?;
        output(&page)
    }

    async fn read_messages(
        &self,
        workspace_id: &str,
        request: pl_tool::bots::ReadMessagesInput,
    ) -> Result<ToolOutput, ToolError> {
        self.ensure_tools_enabled(workspace_id, &request.bot_id)
            .await?;
        let page = self
            .runtime
            .read_messages(
                &request.bot_id,
                &request.chat_id,
                request.start_time,
                request.end_time,
                request.cursor.as_deref(),
                request.limit,
            )
            .await
            .map_err(ToolError::new)?;
        output(&page)
    }

    async fn send_message(
        &self,
        workspace_id: &str,
        operation_id: String,
        bot_id: String,
        chat_id: String,
        text: String,
    ) -> Result<ToolOutput, ToolError> {
        self.ensure_tools_enabled(workspace_id, &bot_id).await?;
        let result = self
            .runtime
            .send_message_as(
                operation_id,
                bot_id,
                chat_id,
                text,
                "tool",
                SendAuthority::Tool {
                    workspace_id: workspace_id.to_string(),
                },
            )
            .await
            .map_err(ToolError::new)?;
        output(&result)
    }
}

impl StudioBotSessionHost {
    async fn ensure_tools_enabled(&self, workspace_id: &str, bot_id: &str) -> Result<(), ToolError> {
        let allowed = self
            .runtime
            .authorized_bots(workspace_id)
            .await
            .into_iter()
            .any(|bot| bot.id == bot_id);
        if allowed {
            Ok(())
        } else {
            Err(ToolError::new(std::io::Error::other(
                "bot is not authorized for this project",
            )))
        }
    }
}

fn output(value: &impl serde::Serialize) -> Result<ToolOutput, ToolError> {
    let encoded = serde_json::to_string(value).map_err(ToolError::new)?;
    Ok(ToolOutput::new(
        OpaquePayload::new("pl.studio.bot-tool", 1, encoded.clone()).map_err(ToolError::new)?,
        vec![ContextContent::Text {
            text: Arc::from(encoded),
        }],
    ))
}

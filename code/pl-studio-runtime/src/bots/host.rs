use super::SendAuthority;
use super::owner::BotRuntime;
use super::protocol::error::{FeishuError, FeishuErrorKind};
use pl_protocol::studio::{
    BotConnectionState, BotConversation, BotMessage, BotSendSegment, BotSendStatus,
    StudioCommandReceipt,
};
use pl_tool::bots::{Bot, BotSessionHost, Page, ReadMessages, SendStatus, Sent};

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
    type Error = FeishuError;
    type Connection = BotConnectionState;
    type Conversation = BotConversation;
    type Message = BotMessage;
    type Segment = BotSendSegment;
    type Receipt = StudioCommandReceipt;
    async fn list_bots(
        &self,
        workspace_id: &str,
    ) -> Result<Vec<Bot<BotConnectionState>>, FeishuError> {
        let bots = self
            .runtime
            .authorized_bots(workspace_id)
            .await
            .into_iter()
            .map(|bot| Bot {
                id: bot.id,
                name: bot.name,
                connection: bot.connection,
                tools_enabled: bot.tools_enabled,
            })
            .collect::<Vec<_>>();
        Ok(bots)
    }

    async fn list_conversations(
        &self,
        workspace_id: &str,
        bot_id: String,
        cursor: Option<String>,
        limit: Option<u32>,
    ) -> Result<Page<BotConversation>, FeishuError> {
        self.ensure_tools_enabled(workspace_id, &bot_id).await?;
        let page = self
            .runtime
            .list_conversations(&bot_id, cursor.as_deref(), limit)
            .await?;
        Ok(Page {
            items: page.conversations,
            next_cursor: page.next_cursor,
        })
    }

    async fn read_messages(
        &self,
        workspace_id: &str,
        request: ReadMessages,
    ) -> Result<Page<BotMessage>, FeishuError> {
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
            .await?;
        Ok(Page {
            items: page.messages,
            next_cursor: page.next_cursor,
        })
    }

    async fn send_message(
        &self,
        workspace_id: &str,
        operation_id: String,
        bot_id: String,
        chat_id: String,
        text: String,
    ) -> Result<Sent<BotSendSegment, StudioCommandReceipt>, FeishuError> {
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
            .await?;
        Ok(Sent {
            status: match result.status {
                BotSendStatus::Succeeded => SendStatus::Succeeded,
                BotSendStatus::Partial => SendStatus::Partial,
                BotSendStatus::Rejected => SendStatus::Rejected,
                BotSendStatus::Unknown => SendStatus::Unknown,
            },
            segments: result.segments,
            receipt: result.receipt,
        })
    }
}

impl StudioBotSessionHost {
    async fn ensure_tools_enabled(
        &self,
        workspace_id: &str,
        bot_id: &str,
    ) -> Result<(), FeishuError> {
        let allowed = self
            .runtime
            .authorized_bots(workspace_id)
            .await
            .into_iter()
            .any(|bot| bot.id == bot_id);
        if allowed {
            Ok(())
        } else {
            Err(FeishuError::new(
                FeishuErrorKind::Permission,
                "bot is not authorized for this project",
                false,
                None,
            ))
        }
    }
}

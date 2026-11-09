use super::SendAuthority;
use super::owner::BotRuntime;
use super::protocol::error::{FeishuError, FeishuErrorKind};
use pl_protocol::studio::{
    BotConnectionState, BotConversation, BotMessage, BotSendSegment, BotSendStatus,
    StudioCommandReceipt,
};
use pl_tool::bots::{Bot, BotSessionHost, Page, ReadMessages, SendStatus, Sent};

/// Public bot-tool diagnostics with explicit access to the trusted backend error.
#[derive(Clone)]
pub struct BotToolError {
    original: FeishuError,
}

impl BotToolError {
    /// Returns the original typed error for trusted runtime diagnostics.
    ///
    /// Its source chain may contain private backend details and must not be
    /// serialized or included in public tool/history/debug projections.
    pub fn original(&self) -> &FeishuError {
        &self.original
    }
}

impl From<FeishuError> for BotToolError {
    fn from(original: FeishuError) -> Self {
        Self { original }
    }
}

impl std::fmt::Display for BotToolError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        std::fmt::Display::fmt(self.original(), formatter)
    }
}

impl std::fmt::Debug for BotToolError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("BotToolError")
            .field("diagnostic", &self.original().diagnostic())
            .finish()
    }
}

// Standard error traversal is public: the original source is available only
// through the explicit trusted accessor above.
impl std::error::Error for BotToolError {}

#[cfg(test)]
tokio::task_local! {
    static SERVICE_FAILURE: FeishuError;
}

/// Injects a service failure after project authorization and before external access.
#[cfg(test)]
pub(in crate::bots) async fn with_service_failure<T>(
    error: FeishuError,
    operation: impl Future<Output = T>,
) -> T {
    SERVICE_FAILURE.scope(error, operation).await
}

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
    type Error = BotToolError;
    type Connection = BotConnectionState;
    type Conversation = BotConversation;
    type Message = BotMessage;
    type Segment = BotSendSegment;
    type Receipt = StudioCommandReceipt;
    async fn list_bots(
        &self,
        workspace_id: &str,
    ) -> Result<Vec<Bot<BotConnectionState>>, BotToolError> {
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
    ) -> Result<Page<BotConversation>, BotToolError> {
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
    ) -> Result<Page<BotMessage>, BotToolError> {
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
    ) -> Result<Sent<BotSendSegment, StudioCommandReceipt>, BotToolError> {
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
            #[cfg(test)]
            if let Ok(error) = SERVICE_FAILURE.try_with(Clone::clone) {
                return Err(error);
            }
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

use anyhow::Result;
use pl_protocol::studio::{
    BotConversationPage, BotMessagePage, BotSendResult, BotsCommandReply, BotsStateSnapshot,
    CancelBotRegistrationRequest, ListBotConversationsRequest, ReadBotMessagesRequest,
    RetryBotConnectionRequest, SaveBotRequest, SendBotMessageRequest, SetBotEnabledRequest,
    SetBotTrustedChatRequest, SetBotTrustedUserRequest, StartBotRegistrationRequest,
};

use super::StudioRuntime;

fn bot_err(error: crate::bots::FeishuError) -> anyhow::Error {
    anyhow::Error::from(error.studio_error())
}

impl StudioRuntime {
    pub async fn read_bots(&self) -> Result<BotsStateSnapshot> {
        Ok(self.bots.snapshot().await)
    }

    pub async fn save_bot(&self, request: SaveBotRequest) -> Result<BotsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        self.bots
            .save_bot(request, &self.owner_epoch)
            .await
            .map_err(bot_err)
    }

    pub async fn start_bot_registration(
        &self,
        request: StartBotRegistrationRequest,
    ) -> Result<BotsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        self.bots
            .start_registration(
                request.operation_id,
                request.name,
                request.project_id,
                &self.owner_epoch,
            )
            .await
            .map_err(bot_err)
    }

    pub async fn cancel_bot_registration(
        &self,
        request: CancelBotRegistrationRequest,
    ) -> Result<BotsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        self.bots
            .cancel_registration(request.operation_id, request.attempt_id, &self.owner_epoch)
            .await
            .map_err(bot_err)
    }

    pub async fn set_bot_enabled(&self, request: SetBotEnabledRequest) -> Result<BotsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        self.bots
            .set_enabled(
                request.operation_id,
                request.bot_id,
                request.expected_config_revision,
                request.enabled,
                &self.owner_epoch,
            )
            .await
            .map_err(bot_err)
    }

    pub async fn retry_bot_connection(
        &self,
        request: RetryBotConnectionRequest,
    ) -> Result<BotsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        self.bots
            .retry_connection(request.operation_id, request.bot_id, &self.owner_epoch)
            .await
            .map_err(bot_err)
    }

    pub async fn set_bot_trusted_user(
        &self,
        request: SetBotTrustedUserRequest,
    ) -> Result<BotsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        self.bots
            .set_trusted_user(
                request.operation_id,
                request.bot_id,
                request.expected_config_revision,
                request.open_id,
                request.trusted,
                &self.owner_epoch,
            )
            .await
            .map_err(bot_err)
    }

    pub async fn set_bot_trusted_chat(
        &self,
        request: SetBotTrustedChatRequest,
    ) -> Result<BotsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        self.bots
            .set_trusted_chat(
                request.operation_id,
                request.bot_id,
                request.expected_config_revision,
                request.chat_id,
                request.trusted,
                &self.owner_epoch,
            )
            .await
            .map_err(bot_err)
    }

    pub async fn list_bot_conversations(
        &self,
        request: ListBotConversationsRequest,
    ) -> Result<BotConversationPage> {
        self.bots
            .list_conversations(&request.bot_id, request.cursor.as_deref(), request.limit)
            .await
            .map_err(bot_err)
    }

    pub async fn read_bot_messages(
        &self,
        request: ReadBotMessagesRequest,
    ) -> Result<BotMessagePage> {
        self.bots
            .read_messages(
                &request.bot_id,
                &request.chat_id,
                request.start_time,
                request.end_time,
                request.cursor.as_deref(),
                request.limit,
            )
            .await
            .map_err(bot_err)
    }

    pub async fn send_bot_message(&self, request: SendBotMessageRequest) -> Result<BotSendResult> {
        Self::validate_operation_id(&request.operation_id)?;
        self.bots
            .send_message(
                request.operation_id,
                request.bot_id,
                request.chat_id,
                request.text,
                &self.owner_epoch,
            )
            .await
            .map_err(bot_err)
    }

    pub async fn create_bot_conversation_thread(
        &self,
        request: pl_protocol::studio::CreateBotConversationThreadRequest,
    ) -> Result<pl_protocol::studio::BotConversationThreadReply> {
        Self::validate_operation_id(&request.operation_id)?;
        self.bots
            .create_conversation_thread(request, &self.owner_epoch)
            .await
            .map_err(bot_err)
    }
}

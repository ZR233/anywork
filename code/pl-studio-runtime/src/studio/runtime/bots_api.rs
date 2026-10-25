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
    pub(crate) async fn prepare_bot_attachment_drafts(
        &self,
        thread_id: &str,
        sources: Vec<pl_protocol::studio::StudioAttachmentDraftSource>,
    ) -> Result<pl_protocol::studio::AdmitAttachmentDraftsResponse> {
        let _guard = self.lifecycle_lock.lock().await;
        let thread = self.ensure_thread_owner(thread_id).await?;
        self.reconcile_bot_model(thread_id, &thread).await?;
        let job = self.begin_attachment_admission(
            crate::studio::new_id("bot-attachment-admission"),
            pl_protocol::studio::AdmitAttachmentDraftsRequest {
                context: pl_protocol::studio::StudioAttachmentAdmissionContext::ExistingThread {
                    thread_id: thread_id.into(),
                },
                sources,
            },
        )?;
        let outcome = job.result().await;
        let closed = job.close().await;
        match outcome {
            // Cleanup is a separate native-owner responsibility; it cannot erase known drafts.
            pl_protocol::studio::AttachmentAdmissionOutcome::Returned { value } => Ok(value),
            pl_protocol::studio::AttachmentAdmissionOutcome::Rejected { error }
            | pl_protocol::studio::AttachmentAdmissionOutcome::UnknownOutcome { error } => {
                match closed.outcome {
                    pl_protocol::studio::FeedCloseOutcome::Clean => Err(error.into()),
                    pl_protocol::studio::FeedCloseOutcome::Unresolved { issues } => {
                        Err(super::draft_commands::DraftCommandsCloseFailure {
                            issues,
                            source: Some(error.into()),
                        }
                        .into())
                    }
                }
            }
        }
    }

    /// Called under the existing lifecycle admission lock before a new user input is accepted.
    pub(super) async fn reconcile_bot_model(
        &self,
        id: &str,
        thread: &pl_core::thread::ThreadHandle,
    ) -> Result<()> {
        let Some(bot) = self.bots.config_for_thread(id).await.map_err(bot_err)? else {
            return Ok(());
        };
        let selector = self.bots.model_selector(&bot).map_err(bot_err)?;
        let state = thread.snapshot();
        let (previous, saved) = crate::studio::model_route::route_record(&state, false)?
            .ok_or_else(|| anyhow::anyhow!("bot session has no model route"))?;
        if saved == selector
            && state
                .extensions
                .contains_key(crate::studio::model_route::BOT_OWNER_EXTENSION)
        {
            return Ok(());
        }
        let settings = self.config_runtime.read()?;
        let route = settings
            .config
            .models
            .resolve_route(crate::config::StudioRole::Planner.id(), &selector)?;
        Self::validate_model_media(&state, &route.model, &[])?;
        let mut mutations = vec![pl_core::thread::extensions::ExtensionMutation::Put {
            id: crate::studio::model_route::MODEL_ROUTE_EXTENSION.into(),
            expected_revision: Some(previous.revision),
            payload: crate::studio::model_route::encode(&selector)?,
        }];
        if !state
            .extensions
            .contains_key(crate::studio::model_route::BOT_OWNER_EXTENSION)
        {
            mutations.push(pl_core::thread::extensions::ExtensionMutation::Put {
                id: crate::studio::model_route::BOT_OWNER_EXTENSION.into(),
                expected_revision: None,
                payload: crate::studio::model_route::encode_bot_owner(&bot.id)?,
            });
        }
        thread
            .queue_deferred_model_update_if_current(
                self.deferred_model_update(&route, &settings.config)?,
                pl_core::thread::DeferredModelUpdatePrecondition::extension(
                    crate::studio::model_route::MODEL_ROUTE_EXTENSION,
                    Some(previous.revision),
                ),
                mutations,
            )
            .await?;
        self.tool_catalog_updates.notify_one();
        Ok(())
    }

    pub async fn read_bots(&self) -> Result<BotsStateSnapshot> {
        Ok(self.bots.snapshot().await)
    }

    pub async fn save_bot(&self, request: SaveBotRequest) -> Result<BotsCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        if let Some(route) = &request.model_route {
            super::settings_api::validated_route(
                &self.config_runtime.read()?.config,
                "bot",
                &route.account_id,
                &route.model_id,
                route.effort.as_deref(),
            )?;
        }
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

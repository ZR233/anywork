use crate::api::studio::bridge_runtime::active_bridge;
use crate::api::studio::convert::bot_audience;
use crate::api::studio::convert::runtime::{
    bridge_bots_command_reply, bridge_bots_state, bridge_conversation_page,
    bridge_conversation_thread_reply, bridge_message_page, bridge_send_result,
    protocol_cancel_registration, protocol_create_thread, protocol_list_conversations,
    protocol_read_messages, protocol_retry_connection, protocol_save_bot, protocol_send_message,
    protocol_set_enabled, protocol_set_trusted_chat, protocol_set_trusted_user,
    protocol_start_registration,
};
use crate::api::studio::types::{
    BridgeBotConversationPage, BridgeBotConversationThreadReply, BridgeBotMessagePage,
    BridgeBotSendResult, BridgeBotsCommandReply, BridgeBotsStateSnapshot,
    BridgeCancelBotRegistrationRequest, BridgeChangeBotThreadSyncReply,
    BridgeChangeBotThreadSyncRequest, BridgeCreateBotConversationThreadRequest, BridgeError,
    BridgeListBotConversationsRequest, BridgeReadBotMessagesRequest,
    BridgeReadThreadAudienceItemsReply, BridgeReadThreadAudienceItemsRequest,
    BridgeReadThreadClosedAuthorizationsReply, BridgeReadThreadClosedAuthorizationsRequest,
    BridgeRetryBotConnectionRequest, BridgeSaveBotRequest, BridgeSendBotMessageRequest,
    BridgeSetBotEnabledRequest, BridgeSetBotTrustedChatRequest, BridgeSetBotTrustedUserRequest,
    BridgeStartBotRegistrationRequest,
};

pub async fn read_bots() -> Result<BridgeBotsStateSnapshot, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_bots_state(bridge.studio.read_bots().await?))
}

pub async fn save_bot(
    request: BridgeSaveBotRequest,
) -> Result<BridgeBotsCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_bots_command_reply(
        bridge.studio.save_bot(protocol_save_bot(request)).await?,
    ))
}

pub async fn start_bot_registration(
    request: BridgeStartBotRegistrationRequest,
) -> Result<BridgeBotsCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_bots_command_reply(
        bridge
            .studio
            .start_bot_registration(protocol_start_registration(request))
            .await?,
    ))
}

pub async fn cancel_bot_registration(
    request: BridgeCancelBotRegistrationRequest,
) -> Result<BridgeBotsCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_bots_command_reply(
        bridge
            .studio
            .cancel_bot_registration(protocol_cancel_registration(request))
            .await?,
    ))
}

pub async fn set_bot_enabled(
    request: BridgeSetBotEnabledRequest,
) -> Result<BridgeBotsCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_bots_command_reply(
        bridge
            .studio
            .set_bot_enabled(protocol_set_enabled(request))
            .await?,
    ))
}

pub async fn retry_bot_connection(
    request: BridgeRetryBotConnectionRequest,
) -> Result<BridgeBotsCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_bots_command_reply(
        bridge
            .studio
            .retry_bot_connection(protocol_retry_connection(request))
            .await?,
    ))
}

pub async fn set_bot_trusted_user(
    request: BridgeSetBotTrustedUserRequest,
) -> Result<BridgeBotsCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_bots_command_reply(
        bridge
            .studio
            .set_bot_trusted_user(protocol_set_trusted_user(request))
            .await?,
    ))
}

pub async fn set_bot_trusted_chat(
    request: BridgeSetBotTrustedChatRequest,
) -> Result<BridgeBotsCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_bots_command_reply(
        bridge
            .studio
            .set_bot_trusted_chat(protocol_set_trusted_chat(request))
            .await?,
    ))
}

pub async fn list_bot_conversations(
    request: BridgeListBotConversationsRequest,
) -> Result<BridgeBotConversationPage, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_conversation_page(
        bridge
            .studio
            .list_bot_conversations(protocol_list_conversations(request))
            .await?,
    ))
}

pub async fn read_bot_messages(
    request: BridgeReadBotMessagesRequest,
) -> Result<BridgeBotMessagePage, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_message_page(
        bridge
            .studio
            .read_bot_messages(protocol_read_messages(request))
            .await?,
    ))
}

pub async fn send_bot_message(
    request: BridgeSendBotMessageRequest,
) -> Result<BridgeBotSendResult, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_send_result(
        bridge
            .studio
            .send_bot_message(protocol_send_message(request))
            .await?,
    ))
}

pub async fn create_bot_conversation_thread(
    request: BridgeCreateBotConversationThreadRequest,
) -> Result<BridgeBotConversationThreadReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_conversation_thread_reply(
        bridge
            .studio
            .create_bot_conversation_thread(protocol_create_thread(request))
            .await?,
    ))
}

pub async fn read_thread_closed_authorizations(
    request: BridgeReadThreadClosedAuthorizationsRequest,
) -> Result<BridgeReadThreadClosedAuthorizationsReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bot_audience::closed_reply(
        bridge
            .studio
            .read_thread_closed_authorizations(bot_audience::read_closed_request(request))
            .await?,
    ))
}

pub async fn read_thread_audience_items(
    request: BridgeReadThreadAudienceItemsRequest,
) -> Result<BridgeReadThreadAudienceItemsReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bot_audience::items_reply(
        bridge
            .studio
            .read_thread_audience_items(bot_audience::items_request(request))
            .await?,
    ))
}

pub async fn change_bot_thread_sync(
    request: BridgeChangeBotThreadSyncRequest,
) -> Result<BridgeChangeBotThreadSyncReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bot_audience::sync_reply(
        bridge
            .studio
            .change_bot_thread_sync(bot_audience::sync_request(request))
            .await?,
    ))
}

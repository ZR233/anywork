use crate::api::studio::{
    bridge_runtime::active_bridge,
    convert::chatgpt_auth::bridge_chatgpt_login_reply,
    types::{BridgeChatGptLoginCommandReply, BridgeError},
};
use pl_protocol::studio::{CancelChatGptLoginRequest, StartChatGptLoginRequest};

/// Starts an editor-bound authorization without creating or changing an account.
pub async fn start_chatgpt_login(
    login_id: String,
    editor_id: String,
    account_id: String,
) -> Result<BridgeChatGptLoginCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_chatgpt_login_reply(
        bridge
            .studio
            .start_chatgpt_login(StartChatGptLoginRequest {
                login_id,
                editor_id,
                account_id,
            })
            .await?,
    ))
}

/// Cancels and joins this attempt, including a completed but unsaved grant.
pub async fn cancel_chatgpt_login(
    login_id: String,
    editor_id: String,
    account_id: String,
) -> Result<BridgeChatGptLoginCommandReply, BridgeError> {
    let bridge = active_bridge().await?;
    Ok(bridge_chatgpt_login_reply(
        bridge
            .studio
            .cancel_chatgpt_login(CancelChatGptLoginRequest {
                login_id,
                editor_id,
                account_id,
            })
            .await?,
    ))
}

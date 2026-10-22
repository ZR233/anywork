use axum::Json;
use axum::extract::State;
use axum::response::IntoResponse;
use pl_protocol::studio::{
    CancelBotRegistrationRequest, ListBotConversationsRequest, ReadBotMessagesRequest,
    RetryBotConnectionRequest, SaveBotRequest, SendBotMessageRequest, SetBotEnabledRequest,
    SetBotTrustedChatRequest, SetBotTrustedUserRequest, StartBotRegistrationRequest,
};
use utoipa_axum::routes;

use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiJson, StudioApiErrors};

pub(crate) fn bot_routes() -> utoipa_axum::router::OpenApiRouter<AppState> {
    utoipa_axum::router::OpenApiRouter::new()
        .routes(routes!(read_bots))
        .routes(routes!(save_bot))
        .routes(routes!(start_bot_registration))
        .routes(routes!(cancel_bot_registration))
        .routes(routes!(set_bot_enabled))
        .routes(routes!(retry_bot_connection))
        .routes(routes!(set_bot_trusted_user))
        .routes(routes!(set_bot_trusted_chat))
        .routes(routes!(list_bot_conversations))
        .routes(routes!(read_bot_messages))
        .routes(routes!(send_bot_message))
        .routes(routes!(create_bot_conversation_thread))
}

#[utoipa::path(get, path = "/api/v1/bots", operation_id = "bots.read", responses(StudioApiErrors, (status = 200)))]
async fn read_bots(State(state): State<AppState>) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state.runtime.read_bots().await.map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/bots", operation_id = "bots.save", request_body = SaveBotRequest, responses(StudioApiErrors, (status = 200)))]
async fn save_bot(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<SaveBotRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .save_bot(request)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/bots/registration", operation_id = "bots.startRegistration", request_body = StartBotRegistrationRequest, responses(StudioApiErrors, (status = 200)))]
async fn start_bot_registration(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<StartBotRegistrationRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .start_bot_registration(request)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/bots/registration/cancel", operation_id = "bots.cancelRegistration", request_body = CancelBotRegistrationRequest, responses(StudioApiErrors, (status = 200)))]
async fn cancel_bot_registration(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<CancelBotRegistrationRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .cancel_bot_registration(request)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/bots/enabled", operation_id = "bots.setEnabled", request_body = SetBotEnabledRequest, responses(StudioApiErrors, (status = 200)))]
async fn set_bot_enabled(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<SetBotEnabledRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .set_bot_enabled(request)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/bots/retry", operation_id = "bots.retryConnection", request_body = RetryBotConnectionRequest, responses(StudioApiErrors, (status = 200)))]
async fn retry_bot_connection(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<RetryBotConnectionRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .retry_bot_connection(request)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/bots/trusted-users", operation_id = "bots.setTrustedUser", request_body = SetBotTrustedUserRequest, responses(StudioApiErrors, (status = 200)))]
async fn set_bot_trusted_user(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<SetBotTrustedUserRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .set_bot_trusted_user(request)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/bots/trusted-chats", operation_id = "bots.setTrustedChat", request_body = SetBotTrustedChatRequest, responses(StudioApiErrors, (status = 200)))]
async fn set_bot_trusted_chat(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<SetBotTrustedChatRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .set_bot_trusted_chat(request)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/bots/conversations", operation_id = "bots.listConversations", request_body = ListBotConversationsRequest, responses(StudioApiErrors, (status = 200)))]
async fn list_bot_conversations(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<ListBotConversationsRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .list_bot_conversations(request)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/bots/messages", operation_id = "bots.readMessages", request_body = ReadBotMessagesRequest, responses(StudioApiErrors, (status = 200)))]
async fn read_bot_messages(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<ReadBotMessagesRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .read_bot_messages(request)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/bots/messages/send", operation_id = "bots.sendMessage", request_body = SendBotMessageRequest, responses(StudioApiErrors, (status = 200)))]
async fn send_bot_message(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<SendBotMessageRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .send_bot_message(request)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/bots/conversations/thread", operation_id = "bots.createConversationThread", request_body = pl_protocol::studio::CreateBotConversationThreadRequest, responses(StudioApiErrors, (status = 200)))]
async fn create_bot_conversation_thread(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<pl_protocol::studio::CreateBotConversationThreadRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .create_bot_conversation_thread(request)
            .await
            .map_err(ApiError::from)?,
    ))
}

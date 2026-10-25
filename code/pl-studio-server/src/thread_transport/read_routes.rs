use super::types::*;
use super::*;
use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiJson, ApiPath, ApiQuery, StudioApiErrors};
use axum::Json;
use axum::extract::State as App;
use pl_protocol::studio::TextChunk;
use pl_protocol::thread_facets::read::{execution::*, interaction::*};

async fn opened(state: AppState, request: Open) -> Result<Json<ReadReply>, ApiError> {
    state.thread_transports.reap();
    let mut opening = state
        .thread_transports
        .open(state.runtime.clone(), request, None)?;
    let Identity::Read(identity) = opening.ready().await? else {
        return Err(StudioError::internal().into());
    };
    opening.adopt()?;
    Ok(Json(ReadReply { identity }))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/reads/turn", operation_id = "thread.read.openTurn", params(("thread_id" = String, Path)), request_body = TurnOpen, responses(StudioApiErrors, (status = 200, body = ReadReply)))]
pub(super) async fn turn_open(
    App(state): App<AppState>,
    ApiPath(thread_id): ApiPath<String>,
    ApiJson(body): ApiJson<TurnOpen>,
) -> Result<Json<ReadReply>, ApiError> {
    opened(
        state,
        Open::Turn {
            thread_id,
            reference: body.reference,
            origin: body.origin,
        },
    )
    .await
}
#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/reads/interaction-index", operation_id = "thread.read.openInteractionIndex", params(("thread_id" = String, Path)), request_body = IndexOpen, responses(StudioApiErrors, (status = 200, body = ReadReply)))]
pub(super) async fn index_open(
    App(state): App<AppState>,
    ApiPath(thread_id): ApiPath<String>,
    ApiJson(body): ApiJson<IndexOpen>,
) -> Result<Json<ReadReply>, ApiError> {
    opened(
        state,
        Open::Index {
            thread_id,
            reference: body.reference,
            origin: body.origin,
        },
    )
    .await
}
#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/reads/interaction", operation_id = "thread.read.openInteraction", params(("thread_id" = String, Path)), request_body = InteractionOpen, responses(StudioApiErrors, (status = 200, body = ReadReply)))]
pub(super) async fn interaction_open(
    App(state): App<AppState>,
    ApiPath(thread_id): ApiPath<String>,
    ApiJson(body): ApiJson<InteractionOpen>,
) -> Result<Json<ReadReply>, ApiError> {
    opened(
        state,
        Open::Interaction {
            thread_id,
            reference: body.reference,
            origin: body.origin,
        },
    )
    .await
}
#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/reads/activity", operation_id = "thread.read.openActivity", params(("thread_id" = String, Path)), request_body = ActivityOpen, responses(StudioApiErrors, (status = 200, body = ReadReply)))]
pub(super) async fn activity_open(
    App(state): App<AppState>,
    ApiPath(thread_id): ApiPath<String>,
    ApiJson(body): ApiJson<ActivityOpen>,
) -> Result<Json<ReadReply>, ApiError> {
    opened(
        state,
        Open::Activity {
            thread_id,
            reference: body.reference,
            origin: body.origin,
        },
    )
    .await
}
#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/reads/storage", operation_id = "thread.read.openStorage", params(("thread_id" = String, Path)), request_body = StorageOpen, responses(StudioApiErrors, (status = 200, body = ReadReply)))]
pub(super) async fn storage_open(
    App(state): App<AppState>,
    ApiPath(thread_id): ApiPath<String>,
    ApiJson(body): ApiJson<StorageOpen>,
) -> Result<Json<ReadReply>, ApiError> {
    opened(
        state,
        Open::Storage {
            thread_id,
            reference: body.reference,
            origin: body.origin,
        },
    )
    .await
}
#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/reads/interaction-reference", operation_id = "thread.read.resolveInteraction", params(("thread_id" = String, Path)), request_body = ResolveInteraction, responses(StudioApiErrors, (status = 200, body = InteractionReadRef)))]
pub(super) async fn resolve_interaction(
    App(state): App<AppState>,
    ApiPath(thread_id): ApiPath<String>,
    ApiJson(body): ApiJson<ResolveInteraction>,
) -> Result<Json<InteractionReadRef>, ApiError> {
    Ok(Json(
        state
            .runtime
            .resolve_interaction_read_ref(
                thread_id,
                body.interaction_id,
                body.revision,
                body.origin,
            )
            .await?,
    ))
}

#[utoipa::path(get, path = "/api/v1/thread-reads/{scope_id}/header/turn", operation_id = "thread.read.turnHeader", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = TurnReadHeader)))]
pub(super) async fn turn_header(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<TurnReadHeader>, ApiError> {
    let Native::Turn(read) = state.thread_transports.get(&id)?.native()? else {
        return Err(wrong().into());
    };
    Ok(Json(read.header().await?))
}
#[utoipa::path(get, path = "/api/v1/thread-reads/{scope_id}/header/interaction-index", operation_id = "thread.read.interactionIndexHeader", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = InteractionIndexReadHeader)))]
pub(super) async fn index_header(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<InteractionIndexReadHeader>, ApiError> {
    let Native::Index(read) = state.thread_transports.get(&id)?.native()? else {
        return Err(wrong().into());
    };
    Ok(Json(read.header().await?))
}
#[utoipa::path(get, path = "/api/v1/thread-reads/{scope_id}/header/interaction", operation_id = "thread.read.interactionHeader", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = InteractionReadHeader)))]
pub(super) async fn interaction_header(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<InteractionReadHeader>, ApiError> {
    let Native::Interaction(read) = state.thread_transports.get(&id)?.native()? else {
        return Err(wrong().into());
    };
    Ok(Json(read.header().await?))
}
#[utoipa::path(get, path = "/api/v1/thread-reads/{scope_id}/header/activity", operation_id = "thread.read.activityHeader", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = ActivityReadHeader)))]
pub(super) async fn activity_header(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<ActivityReadHeader>, ApiError> {
    let Native::Activity(read) = state.thread_transports.get(&id)?.native()? else {
        return Err(wrong().into());
    };
    Ok(Json(read.header().await?))
}
#[utoipa::path(get, path = "/api/v1/thread-reads/{scope_id}/header/storage", operation_id = "thread.read.storageHeader", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = StorageReadHeader)))]
pub(super) async fn storage_header(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<StorageReadHeader>, ApiError> {
    let Native::Storage(read) = state.thread_transports.get(&id)?.native()? else {
        return Err(wrong().into());
    };
    Ok(Json(read.header().await?))
}
#[utoipa::path(get, path = "/api/v1/thread-reads/{scope_id}/entries", operation_id = "thread.read.interactionIndexEntries", params(("scope_id" = String, Path), PageQuery), responses(StudioApiErrors, (status = 200, body = InteractionBriefPage)))]
pub(super) async fn index_entries(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiQuery(query): ApiQuery<PageQuery>,
) -> Result<Json<InteractionBriefPage>, ApiError> {
    let Native::Index(read) = state.thread_transports.get(&id)?.native()? else {
        return Err(wrong().into());
    };
    Ok(Json(read.entries(query.offset(), query.limit()).await?))
}
#[utoipa::path(get, path = "/api/v1/thread-reads/{scope_id}/questions", operation_id = "thread.read.questions", params(("scope_id" = String, Path), PageQuery), responses(StudioApiErrors, (status = 200, body = QuestionPage)))]
pub(super) async fn questions(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiQuery(query): ApiQuery<PageQuery>,
) -> Result<Json<QuestionPage>, ApiError> {
    let Native::Interaction(read) = state.thread_transports.get(&id)?.native()? else {
        return Err(wrong().into());
    };
    Ok(Json(read.questions(query.offset(), query.limit()).await?))
}
#[utoipa::path(get, path = "/api/v1/thread-reads/{scope_id}/questions/{question_index}/options", operation_id = "thread.read.options", params(("scope_id" = String, Path), ("question_index" = u64, Path), PageQuery), responses(StudioApiErrors, (status = 200, body = OptionPage)))]
pub(super) async fn options(
    App(state): App<AppState>,
    ApiPath((id, index)): ApiPath<(String, u64)>,
    ApiQuery(query): ApiQuery<PageQuery>,
) -> Result<Json<OptionPage>, ApiError> {
    let Native::Interaction(read) = state.thread_transports.get(&id)?.native()? else {
        return Err(wrong().into());
    };
    Ok(Json(
        read.options(index, query.offset(), query.limit()).await?,
    ))
}
#[utoipa::path(get, path = "/api/v1/thread-reads/{scope_id}/answer-entries", operation_id = "thread.read.answerEntries", params(("scope_id" = String, Path), PageQuery), responses(StudioApiErrors, (status = 200, body = AnswerEntryPage)))]
pub(super) async fn answer_entries(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiQuery(query): ApiQuery<PageQuery>,
) -> Result<Json<AnswerEntryPage>, ApiError> {
    let Native::Interaction(read) = state.thread_transports.get(&id)?.native()? else {
        return Err(wrong().into());
    };
    Ok(Json(
        read.answer_entries(query.offset(), query.limit()).await?,
    ))
}
#[utoipa::path(get, path = "/api/v1/thread-reads/{scope_id}/answers/{entry_index}/values", operation_id = "thread.read.answerValues", params(("scope_id" = String, Path), ("entry_index" = u64, Path), PageQuery), responses(StudioApiErrors, (status = 200, body = AnswerValuePage)))]
pub(super) async fn answer_values(
    App(state): App<AppState>,
    ApiPath((id, index)): ApiPath<(String, u64)>,
    ApiQuery(query): ApiQuery<PageQuery>,
) -> Result<Json<AnswerValuePage>, ApiError> {
    let Native::Interaction(read) = state.thread_transports.get(&id)?.native()? else {
        return Err(wrong().into());
    };
    Ok(Json(
        read.answer_values(index, query.offset(), query.limit())
            .await?,
    ))
}
#[utoipa::path(get, path = "/api/v1/thread-reads/{scope_id}/tools", operation_id = "thread.read.tools", params(("scope_id" = String, Path), PageQuery), responses(StudioApiErrors, (status = 200, body = ActivityToolPage)))]
pub(super) async fn tools(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiQuery(query): ApiQuery<PageQuery>,
) -> Result<Json<ActivityToolPage>, ApiError> {
    let Native::Activity(read) = state.thread_transports.get(&id)?.native()? else {
        return Err(wrong().into());
    };
    Ok(Json(read.tools(query.offset(), query.limit()).await?))
}
#[utoipa::path(get, path = "/api/v1/thread-reads/{scope_id}/tools/{tool_index}/wait-targets", operation_id = "thread.read.waitTargets", params(("scope_id" = String, Path), ("tool_index" = u64, Path), PageQuery), responses(StudioApiErrors, (status = 200, body = WaitTargetPage)))]
pub(super) async fn wait_targets(
    App(state): App<AppState>,
    ApiPath((id, index)): ApiPath<(String, u64)>,
    ApiQuery(query): ApiQuery<PageQuery>,
) -> Result<Json<WaitTargetPage>, ApiError> {
    let Native::Activity(read) = state.thread_transports.get(&id)?.native()? else {
        return Err(wrong().into());
    };
    Ok(Json(
        read.wait_targets(index, query.offset(), query.limit())
            .await?,
    ))
}
#[utoipa::path(get, path = "/api/v1/thread-reads/{scope_id}/latest-wait-targets", operation_id = "thread.read.latestWaitTargets", params(("scope_id" = String, Path), PageQuery), responses(StudioApiErrors, (status = 200, body = WaitTargetPage)))]
pub(super) async fn latest_wait_targets(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiQuery(query): ApiQuery<PageQuery>,
) -> Result<Json<WaitTargetPage>, ApiError> {
    let Native::Activity(read) = state.thread_transports.get(&id)?.native()? else {
        return Err(wrong().into());
    };
    Ok(Json(
        read.latest_wait_targets(query.offset(), query.limit())
            .await?,
    ))
}
#[utoipa::path(get, path = "/api/v1/thread-reads/{scope_id}/text", operation_id = "thread.read.text", params(("scope_id" = String, Path), TextQuery), responses(StudioApiErrors, (status = 200, body = TextChunk)))]
pub(super) async fn text(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiQuery(query): ApiQuery<TextQuery>,
) -> Result<Json<TextChunk>, ApiError> {
    let offset = query.offset.unwrap_or(0);
    let maximum = query.max_bytes.unwrap_or(65536);
    let chunk = match state.thread_transports.get(&id)?.native()? {
        Native::Turn(read) => read.text(query.field_id, offset, maximum).await?,
        Native::Interaction(read) => read.text(query.field_id, offset, maximum).await?,
        Native::Activity(read) => read.text(query.field_id, offset, maximum).await?,
        Native::Storage(read) => read.text(query.field_id, offset, maximum).await?,
        Native::Index(read) => read.text(query.field_id, offset, maximum).await?,
        Native::Execution(_)
        | Native::Authoring(_)
        | Native::Todo(_)
        | Native::Workflow(_)
        | Native::PlanDocument(_) => return Err(wrong().into()),
    };
    Ok(Json(chunk))
}

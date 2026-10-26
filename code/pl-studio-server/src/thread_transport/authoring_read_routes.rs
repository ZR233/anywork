use super::types::*;
use super::*;
use crate::AppState;
use crate::error::ApiError;
use crate::routes::{ApiJson, ApiPath, ApiQuery, StudioApiErrors};
use axum::Json;
use axum::extract::State as App;
use pl_protocol::studio::TextChunk;
use pl_protocol::thread_facets::read::values::{
    PlanDocumentReadHeader, PlanDocumentValue, TodoItemPage, TodoReadHeader, WorkflowReadHeader,
};

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
#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/reads/todo", operation_id = "thread.read.openTodo", params(("thread_id" = String, Path)), request_body = TodoOpen, responses(StudioApiErrors, (status = 200, body = ReadReply)))]
pub(super) async fn todo_open(
    App(state): App<AppState>,
    ApiPath(thread_id): ApiPath<String>,
    ApiJson(body): ApiJson<TodoOpen>,
) -> Result<Json<ReadReply>, ApiError> {
    opened(
        state,
        Open::Todo {
            thread_id,
            reference: body.reference,
            origin: body.origin,
        },
    )
    .await
}
#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/reads/workflow", operation_id = "thread.read.openWorkflow", params(("thread_id" = String, Path)), request_body = WorkflowOpen, responses(StudioApiErrors, (status = 200, body = ReadReply)))]
pub(super) async fn workflow_open(
    App(state): App<AppState>,
    ApiPath(thread_id): ApiPath<String>,
    ApiJson(body): ApiJson<WorkflowOpen>,
) -> Result<Json<ReadReply>, ApiError> {
    opened(
        state,
        Open::Workflow {
            thread_id,
            reference: body.reference,
            origin: body.origin,
        },
    )
    .await
}
#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/reads/plan-document", operation_id = "thread.read.openPlanDocument", params(("thread_id" = String, Path)), request_body = PlanDocumentOpen, responses(StudioApiErrors, (status = 200, body = ReadReply)))]
pub(super) async fn plan_document_open(
    App(state): App<AppState>,
    ApiPath(thread_id): ApiPath<String>,
    ApiJson(body): ApiJson<PlanDocumentOpen>,
) -> Result<Json<ReadReply>, ApiError> {
    opened(
        state,
        Open::PlanDocument {
            thread_id,
            reference: body.reference,
            origin: body.origin,
        },
    )
    .await
}

#[utoipa::path(get, path = "/api/v1/authoring-reads/{scope_id}/header/todo", operation_id = "thread.read.todoHeader", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = TodoReadHeader)))]
pub(super) async fn todo_header(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<TodoReadHeader>, ApiError> {
    let Native::Todo(read) = state.thread_transports.get_authoring_read(&id)?.native()? else {
        return Err(wrong().into());
    };
    Ok(Json(read.header().await?))
}
#[utoipa::path(get, path = "/api/v1/authoring-reads/{scope_id}/items", operation_id = "thread.read.todoItems", params(("scope_id" = String, Path), PageQuery), responses(StudioApiErrors, (status = 200, body = TodoItemPage)))]
pub(super) async fn todo_items(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiQuery(query): ApiQuery<PageQuery>,
) -> Result<Json<TodoItemPage>, ApiError> {
    let Native::Todo(read) = state.thread_transports.get_authoring_read(&id)?.native()? else {
        return Err(wrong().into());
    };
    Ok(Json(read.items(query.offset(), query.limit()).await?))
}
#[utoipa::path(get, path = "/api/v1/authoring-reads/{scope_id}/header/workflow", operation_id = "thread.read.workflowHeader", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = WorkflowReadHeader)))]
pub(super) async fn workflow_header(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<WorkflowReadHeader>, ApiError> {
    let Native::Workflow(read) = state.thread_transports.get_authoring_read(&id)?.native()? else {
        return Err(wrong().into());
    };
    Ok(Json(read.header().await?))
}
#[utoipa::path(get, path = "/api/v1/authoring-reads/{scope_id}/header/plan-document", operation_id = "thread.read.planDocumentHeader", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = PlanDocumentReadHeader)))]
pub(super) async fn plan_document_header(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<PlanDocumentReadHeader>, ApiError> {
    let Native::PlanDocument(read) = state.thread_transports.get_authoring_read(&id)?.native()?
    else {
        return Err(wrong().into());
    };
    Ok(Json(read.header().await?))
}
#[utoipa::path(get, path = "/api/v1/authoring-reads/{scope_id}/document", operation_id = "thread.read.planDocument", params(("scope_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = PlanDocumentValue)))]
pub(super) async fn plan_document(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
) -> Result<Json<PlanDocumentValue>, ApiError> {
    let Native::PlanDocument(read) = state.thread_transports.get_authoring_read(&id)?.native()?
    else {
        return Err(wrong().into());
    };
    Ok(Json(read.document().await?))
}
#[utoipa::path(get, path = "/api/v1/authoring-reads/{scope_id}/text", operation_id = "thread.read.authoringText", params(("scope_id" = String, Path), TextQuery), responses(StudioApiErrors, (status = 200, body = TextChunk)))]
pub(super) async fn text(
    App(state): App<AppState>,
    ApiPath(id): ApiPath<String>,
    ApiQuery(query): ApiQuery<TextQuery>,
) -> Result<Json<TextChunk>, ApiError> {
    let offset = query.offset.unwrap_or(0);
    let maximum = query.max_bytes.unwrap_or(65536);
    let chunk = match state.thread_transports.get_authoring_read(&id)?.native()? {
        Native::Todo(read) => read.text(query.field_id, offset, maximum).await?,
        Native::Workflow(read) => read.text(query.field_id, offset, maximum).await?,
        Native::PlanDocument(_)
        | Native::Authoring(_)
        | Native::Execution(_)
        | Native::Turn(_)
        | Native::Index(_)
        | Native::Interaction(_)
        | Native::Activity(_)
        | Native::Storage(_) => return Err(wrong().into()),
    };
    Ok(Json(chunk))
}

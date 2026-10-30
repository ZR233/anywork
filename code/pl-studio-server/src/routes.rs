use axum::Json;
use axum::body::Bytes;
use axum::extract::DefaultBodyLimit;
use axum::extract::rejection::JsonRejection;
use axum::extract::rejection::QueryRejection;
use axum::extract::{FromRequest, FromRequestParts, Multipart, Path, Query, Request, State};
use axum::http::request::Parts;
use axum::http::{StatusCode, header};
use axum::response::IntoResponse;
use pl_protocol::studio::{
    AccountDomainFrame, AccountObservationTarget, AcpAccountCatalog, AcpAuthCommandReply,
    AcpAuthSnapshot, AcpInstallCommandReply, AcpInstallSnapshot, AdmitAttachmentDraftsRequest,
    AdmitAttachmentDraftsResponse, CancelAcpAuthRequest, CancelAcpInstallRequest,
    ContinuationOperationView, ContinueThreadRequest, ContinueThreadResponse, CreateAccountRequest,
    CreateThreadRequest, ExpectedRevisionRequest, HealthResponse, LspResetRequest, McpResetRequest,
    OpenProjectRequest, PatchAccountRequest, RemoveAccountModelRequest, RemoveAccountRequest,
    RemoveAcpAccountRequest, RenameThreadRequest, ResolveInteractionRequest, SearchSkillsRequest,
    SetAccountBillingKindRequest, SetAccountModelAutoCompactRequest,
    SetAccountModelConnectionRequest, SetAccountModelEnabledRequest, SetDefaultAccountRequest,
    SetThreadModeRequest, SetThreadModelRouteRequest, SettingsCommandReply, SettingsStateResponse,
    StartAcpAuthRequest, StartAcpInstallRequest, StopThreadRequest, StopThreadResponse,
    StudioAttachmentAdmissionContext, StudioAttachmentDraftSource, StudioCommandRequest,
    StudioError, SubmitPromptRequest, SyncAccountModelsReply, SyncAccountModelsRequest,
    ThreadModelRouteCommandReply, ThreadPageQuery, UpdateAcpAccountRequest,
    UpdatePermissionSettingsRequest, UpdateSettingsFieldRequest,
};
use pl_protocol::{
    DelegationModelDetail, DelegationModelList, GetDelegationModelRequest,
    ListDelegationModelsRequest,
};
use pl_protocol::{ThreadModeDocument, ThreadModeId, WorkflowPreviewRequest};
use pl_protocol::{TimelineDetailQuery, TimelinePageQuery};
use tokio::io::AsyncWriteExt;
use utoipa::{IntoResponses, OpenApi};
use utoipa_axum::{router::OpenApiRouter, routes};

use crate::AppState;
use crate::error::ApiError;
use crate::sse;

#[derive(OpenApi)]
#[openapi(
    info(
        title = "anywork Runtime API",
        version = "0.1.0",
        description = "Loopback adapter over the canonical StudioRuntime"
    ),
    components(schemas(StudioError))
)]
struct StudioApi;

const MAX_MULTIPART_BODY_BYTES: usize = 200 * 1024 * 1024;
const MAX_MULTIPART_FILE_BYTES: usize = 50 * 1024 * 1024;
const MAX_MULTIPART_FILES: usize = 16;

#[derive(Debug, serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct SaveThreadModeDefinitionRequest {
    operation_id: String,
    expected_revision: u64,
    #[schema(value_type = Object)]
    document: ThreadModeDocument,
}

#[derive(Debug, serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ModeDefinitionCommandRequest {
    operation_id: String,
    expected_revision: u64,
}

#[derive(Debug, serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ValidateThreadModeDefinitionRequest {
    json: String,
}

#[allow(dead_code)]
#[derive(IntoResponses)]
pub(crate) enum StudioApiErrors {
    #[response(status = 400, description = "Invalid request or protocol data")]
    BadRequest(StudioError),
    #[response(status = 403, description = "Permission denied")]
    Forbidden(StudioError),
    #[response(status = 404, description = "Resource not found")]
    NotFound(StudioError),
    #[response(status = 409, description = "Busy, conflict, stale, or cancelled")]
    Conflict(StudioError),
    #[response(status = 429, description = "Concurrency limit exceeded")]
    Overloaded(StudioError),
    #[response(
        status = 503,
        description = "Runtime, storage, update, or dependency unavailable"
    )]
    Unavailable(StudioError),
    #[response(status = 500, description = "Internal failure")]
    Internal(StudioError),
}

pub(crate) struct ApiJson<T>(pub T);

impl<S, T> FromRequest<S> for ApiJson<T>
where
    S: Send + Sync,
    T: serde::de::DeserializeOwned,
{
    type Rejection = ApiError;

    async fn from_request(request: Request, state: &S) -> Result<Self, Self::Rejection> {
        Json::<T>::from_request(request, state)
            .await
            .map(|Json(value)| Self(value))
            .map_err(json_rejection)
    }
}

fn json_rejection(rejection: JsonRejection) -> ApiError {
    tracing::debug!(error = %rejection, "rejected Studio HTTP JSON body");
    ApiError(StudioError::invalid_argument("invalid JSON request body"))
}

pub(crate) struct ApiQuery<T>(pub(crate) T);

impl<S, T> FromRequestParts<S> for ApiQuery<T>
where
    S: Send + Sync,
    T: serde::de::DeserializeOwned,
{
    type Rejection = ApiError;

    async fn from_request_parts(parts: &mut Parts, state: &S) -> Result<Self, Self::Rejection> {
        Query::<T>::from_request_parts(parts, state)
            .await
            .map(|Query(value)| Self(value))
            .map_err(query_rejection)
    }
}

fn query_rejection(rejection: QueryRejection) -> ApiError {
    tracing::debug!(error = %rejection, "rejected Studio HTTP query");
    ApiError(StudioError::invalid_argument("invalid query parameters"))
}

/// typed 产品 topic 的查询参数；`projectId`/`rootThreadId` 只服务带作用域 topic。
///
/// 字段按 camelCase 反序列化并与 OpenAPI 文档一致；未知查询参数直接 400，
/// 不允许以 snake_case 或多余身份静默扩大输入。
#[derive(Debug, serde::Deserialize, utoipa::IntoParams)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct ProductTopicQuery {
    pub(crate) topic: String,
    pub(crate) project_id: Option<String>,
    pub(crate) root_thread_id: Option<String>,
}

/// 把 HTTP 查询参数解析为 typed 产品 topic。
///
/// 未知 topic、缺失/多余的作用域身份都是 400 协议错误，不静默落到全局订阅。
pub(crate) fn parse_product_topic(
    query: &ProductTopicQuery,
) -> Result<pl_studio_runtime::StudioProductTopic, ApiError> {
    use pl_studio_runtime::StudioProductTopic;
    let invalid =
        |message: &str| ApiError(pl_protocol::studio::StudioError::invalid_argument(message));
    let topic = match query.topic.trim() {
        "projectDirectory" => StudioProductTopic::ProjectDirectory,
        "threadDirectory" => StudioProductTopic::ThreadDirectory,
        "agentDirectory" => StudioProductTopic::AgentDirectory,
        "settingsConfig" => StudioProductTopic::SettingsConfig,
        "modelCatalog" => StudioProductTopic::ModelCatalog,
        "recovery" => StudioProductTopic::Recovery,
        "mcp" => StudioProductTopic::Mcp,
        "lsp" => StudioProductTopic::Lsp,
        "skills" => StudioProductTopic::Skills {
            // scope 身份原样保留（不 trim），与 runtime / FRB 保持同一身份；`validate()` 只用
            // trim 判定 blank，不做归一化，也不扩大允许的输入。
            project_id: query.project_id.clone().unwrap_or_default(),
        },
        "threadModeCatalog" => StudioProductTopic::ThreadModeCatalog,
        "accountUsage" => StudioProductTopic::AccountUsage,
        "acpAuth" => StudioProductTopic::AcpAuth,
        "acpInstall" => StudioProductTopic::AcpInstall,
        "modelPerformance" => StudioProductTopic::ModelPerformance,
        "sessionCosts" => StudioProductTopic::SessionCosts {
            root_thread_id: query.root_thread_id.clone().unwrap_or_default(),
        },
        "updater" => StudioProductTopic::Updater,
        "persistence" => StudioProductTopic::Persistence,
        "persistenceQueue" => StudioProductTopic::PersistenceQueue,
        "agentProfiles" => StudioProductTopic::AgentProfiles,
        "bots" => StudioProductTopic::Bots,
        other => {
            return Err(invalid(&format!("unknown product topic: {other}")));
        }
    };
    match (
        &topic,
        query.project_id.is_some(),
        query.root_thread_id.is_some(),
    ) {
        (StudioProductTopic::Skills { .. }, true, false) => {}
        (StudioProductTopic::SessionCosts { .. }, false, true) => {}
        (StudioProductTopic::Skills { .. } | StudioProductTopic::SessionCosts { .. }, _, _) => {
            return Err(invalid(
                "scoped product topic requires exactly one scope parameter",
            ));
        }
        (_, false, false) => {}
        _ => {
            return Err(invalid(
                "global product topics do not accept scope parameters",
            ));
        }
    }
    if topic.validate().is_err() {
        return Err(invalid("product topic scope must be a non-empty identity"));
    }
    Ok(topic)
}

pub(crate) fn api_router() -> OpenApiRouter<AppState> {
    let attachment_upload = OpenApiRouter::new()
        .routes(routes!(upload_attachment_drafts))
        .layer(DefaultBodyLimit::max(MAX_MULTIPART_BODY_BYTES));
    OpenApiRouter::with_openapi(StudioApi::openapi())
        .routes(routes!(health))
        .routes(routes!(read_state))
        .routes(routes!(read_product_baseline))
        .routes(routes!(open_project))
        .routes(routes!(prepare_standalone_workspace))
        .routes(routes!(activate_project))
        .routes(routes!(archive_project))
        .routes(routes!(rename_project))
        .routes(routes!(list_threads))
        .routes(routes!(create_thread))
        .routes(routes!(read_thread))
        .routes(routes!(archive_thread))
        .routes(routes!(query_threads))
        .routes(routes!(restore_thread))
        .routes(routes!(rename_thread))
        .routes(routes!(set_thread_mode))
        .routes(routes!(read_thread_mode_definition))
        .routes(routes!(save_thread_mode_definition))
        .routes(routes!(delete_thread_mode_definition))
        .routes(routes!(reload_thread_mode_definitions))
        .routes(routes!(validate_thread_mode_definition))
        .routes(routes!(thread_mode_definition_schema))
        .routes(routes!(preview_thread_mode_workflow))
        .routes(routes!(set_thread_model_route))
        .routes(routes!(list_thread_turns))
        .routes(routes!(list_thread_timeline))
        .routes(routes!(read_thread_timeline_detail))
        .routes(routes!(submit_prompt))
        .routes(routes!(admit_attachment_drafts))
        .routes(routes!(remove_attachment_draft))
        .routes(routes!(read_attachment_draft))
        .routes(routes!(read_thread_attachment))
        .routes(routes!(resolve_interaction))
        .routes(routes!(continue_thread))
        .routes(routes!(stop_thread))
        .routes(routes!(read_continuation_operation))
        .routes(routes!(account_catalog))
        .routes(routes!(list_delegation_models))
        .routes(routes!(get_delegation_model))
        .routes(routes!(read_settings))
        .routes(routes!(reload_settings))
        .routes(routes!(remove_account_model))
        .routes(routes!(set_account_model_enabled))
        .routes(routes!(set_account_billing_kind))
        .routes(routes!(save_permission_settings))
        .routes(routes!(create_account))
        .routes(routes!(patch_account))
        .routes(routes!(set_account_model_auto_compact))
        .routes(routes!(set_account_model_connection))
        .routes(routes!(sync_account_models))
        .routes(routes!(read_account_domain))
        .routes(routes!(set_default_account))
        .routes(routes!(remove_account))
        .routes(routes!(apply_settings_field))
        .routes(routes!(acp_account_catalog))
        .routes(routes!(save_acp_account))
        .routes(routes!(remove_acp_account))
        .routes(routes!(read_account_usage))
        .routes(routes!(check_account_usage))
        .routes(routes!(read_acp_auth))
        .routes(routes!(start_acp_auth))
        .routes(routes!(cancel_acp_auth))
        .routes(routes!(read_acp_install))
        .routes(routes!(start_acp_install))
        .routes(routes!(cancel_acp_install))
        .routes(routes!(read_recovery, retry_recovery))
        .routes(routes!(retry_persistence))
        .routes(routes!(retry_thread_history))
        .routes(routes!(resume_thread_history))
        .routes(routes!(read_persistence_queue))
        .routes(routes!(read_skills))
        .routes(routes!(discover_skills))
        .routes(routes!(search_skills))
        .routes(routes!(read_mcp))
        .routes(routes!(reset_mcp))
        .routes(routes!(read_lsp))
        .routes(routes!(probe_lsp))
        .routes(routes!(repair_lsp))
        .routes(routes!(reset_lsp))
        .routes(routes!(read_update))
        .routes(routes!(check_update))
        .routes(routes!(sse::product_events))
        .routes(routes!(sse::thread_events))
        .routes(routes!(sse::thread_timeline_events))
        .merge(crate::bots::bot_routes())
        .merge(attachment_upload)
}

#[utoipa::path(get, path = "/health", operation_id = "health", responses(StudioApiErrors, (status = 200, body = HealthResponse)))]
async fn health(State(_state): State<AppState>) -> Result<Json<HealthResponse>, ApiError> {
    Ok(Json(HealthResponse {
        status: "ok".to_string(),
    }))
}

#[utoipa::path(get, path = "/api/v1/state", operation_id = "studio.readState", responses(StudioApiErrors, (status = 200, description = "Canonical Studio state")))]
async fn read_state(State(state): State<AppState>) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state.runtime.read_state().await.map_err(ApiError::from)?,
    ))
}

/// 读取一个 typed 产品 topic 的当前 canonical 基线；纯查询，无生命周期副作用。
#[utoipa::path(
    get,
    path = "/api/v1/state/product",
    operation_id = "studio.readProductBaseline",
    params(
        ("topic" = String, Query, description = "typed 产品 topic（camelCase 标签）"),
        ("projectId" = Option<String>, Query, description = "Skills topic 的项目作用域"),
        ("rootThreadId" = Option<String>, Query, description = "SessionCosts topic 的根会话作用域")
    ),
    responses(StudioApiErrors, (status = 200, description = "Canonical topic baseline"))
)]
async fn read_product_baseline(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<ProductTopicQuery>,
) -> Result<impl IntoResponse, ApiError> {
    let topic = parse_product_topic(&query)?;
    Ok(Json(
        state
            .runtime
            .read_product_baseline(&topic)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/projects", operation_id = "project.open", request_body = OpenProjectRequest, responses(StudioApiErrors, (status = 200, description = "Opened Project")))]
async fn open_project(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<OpenProjectRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .open_project(request.path)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/standalone-workspace", operation_id = "workspace.prepareStandalone", responses(StudioApiErrors, (status = 200, description = "Prepared standalone workspace")))]
async fn prepare_standalone_workspace(
    State(state): State<AppState>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .prepare_standalone_workspace()
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/projects/{project_id}/activation", operation_id = "project.activate", params(("project_id" = String, Path)), responses(StudioApiErrors, (status = 204)))]
async fn activate_project(
    State(state): State<AppState>,
    Path(project_id): Path<String>,
) -> Result<StatusCode, ApiError> {
    state
        .runtime
        .activate_project(&project_id)
        .await
        .map_err(ApiError::from)?;
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(delete, path = "/api/v1/projects/{project_id}", operation_id = "project.archive", params(("project_id" = String, Path)), responses(StudioApiErrors, (status = 200)))]
async fn archive_project(
    State(state): State<AppState>,
    Path(project_id): Path<String>,
) -> Result<impl IntoResponse, ApiError> {
    let project = state
        .runtime
        .archive_project(&project_id)
        .await
        .map_err(ApiError::from)?
        .ok_or_else(|| ApiError(StudioError::not_found("Project")))?;
    Ok(Json(project))
}

#[utoipa::path(put, path = "/api/v1/projects/{project_id}/name", operation_id = "project.rename", params(("project_id" = String, Path)), request_body = pl_protocol::studio::RenameProjectRequest, responses(StudioApiErrors, (status = 200)))]
async fn rename_project(
    State(state): State<AppState>,
    Path(project_id): Path<String>,
    ApiJson(request): ApiJson<pl_protocol::studio::RenameProjectRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .rename_project(&project_id, &request.name)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(get, path = "/api/v1/threads", operation_id = "thread.listPage", params(("cursor" = Option<String>, Query), ("limit" = Option<u32>, Query)), responses(StudioApiErrors, (status = 200)))]
async fn list_threads(
    State(state): State<AppState>,
    ApiQuery(query): ApiQuery<ThreadPageQuery>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .list_threads_page(query.cursor.as_deref(), query.limit())
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/query", operation_id = "thread.query", params(("cursor" = Option<String>, Query), ("limit" = Option<u32>, Query)), request_body = pl_protocol::studio::ThreadDirectoryQuery, responses(StudioApiErrors, (status = 200)))]
async fn query_threads(
    State(state): State<AppState>,
    ApiQuery(page): ApiQuery<ThreadPageQuery>,
    ApiJson(query): ApiJson<pl_protocol::studio::ThreadDirectoryQuery>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .query_threads(&query, page.cursor.as_deref(), page.limit())
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/restore", operation_id = "thread.restore", params(("thread_id" = String, Path)), responses(StudioApiErrors, (status = 200)))]
async fn restore_thread(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .restore_thread(thread_id)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/projects/{project_id}/threads", operation_id = "thread.create", params(("project_id" = String, Path)), request_body = CreateThreadRequest, responses(StudioApiErrors, (status = 200)))]
async fn create_thread(
    State(state): State<AppState>,
    Path(project_id): Path<String>,
    ApiJson(request): ApiJson<CreateThreadRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .create_thread_command(project_id, request, None)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(get, path = "/api/v1/threads/{thread_id}", operation_id = "thread.read", params(("thread_id" = String, Path)), responses(StudioApiErrors, (status = 200)))]
async fn read_thread(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .thread_snapshot(&thread_id)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(delete, path = "/api/v1/threads/{thread_id}", operation_id = "thread.archive", params(("thread_id" = String, Path)), request_body = StudioCommandRequest, responses(StudioApiErrors, (status = 200)))]
async fn archive_thread(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    ApiJson(request): ApiJson<StudioCommandRequest>,
) -> Result<impl IntoResponse, ApiError> {
    let result = state
        .runtime
        .archive_thread(request.operation_id, thread_id)
        .await
        .map_err(ApiError::from)?
        .ok_or_else(|| ApiError(StudioError::not_found("Thread")))?;
    Ok(Json(result))
}

#[utoipa::path(put, path = "/api/v1/threads/{thread_id}/title", operation_id = "thread.rename", params(("thread_id" = String, Path)), request_body = RenameThreadRequest, responses(StudioApiErrors, (status = 200)))]
async fn rename_thread(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    ApiJson(request): ApiJson<RenameThreadRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .rename_thread(request.operation_id, thread_id, request.title)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(put, path = "/api/v1/threads/{thread_id}/mode", operation_id = "thread.setMode", params(("thread_id" = String, Path)), request_body = SetThreadModeRequest, responses(StudioApiErrors, (status = 200, body = pl_protocol::studio::ThreadModeCommandReply)))]
async fn set_thread_mode(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    ApiJson(request): ApiJson<SetThreadModeRequest>,
) -> Result<impl IntoResponse, ApiError> {
    let reply = state
        .runtime
        .set_thread_mode(request.operation_id, &thread_id, parse_mode(&request.mode)?)
        .await
        .map_err(ApiError::from)?;
    Ok(Json(reply))
}

#[utoipa::path(get, path = "/api/v1/thread-modes/{mode_id}", operation_id = "threadMode.readDefinition", params(("mode_id" = String, Path)), responses(StudioApiErrors, (status = 200)))]
async fn read_thread_mode_definition(
    State(state): State<AppState>,
    Path(mode_id): Path<String>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .read_thread_mode_definition(&parse_mode(&mode_id)?)
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(put, path = "/api/v1/thread-modes/{mode_id}", operation_id = "threadMode.saveDefinition", params(("mode_id" = String, Path)), request_body = SaveThreadModeDefinitionRequest, responses(StudioApiErrors, (status = 200)))]
async fn save_thread_mode_definition(
    State(state): State<AppState>,
    Path(mode_id): Path<String>,
    ApiJson(request): ApiJson<SaveThreadModeDefinitionRequest>,
) -> Result<impl IntoResponse, ApiError> {
    let mode_id = parse_mode(&mode_id)?;
    if request.document.definition.id != mode_id {
        return Err(ApiError(StudioError::invalid_argument(
            "Thread Mode path ID must match document.id",
        )));
    }
    Ok(Json(
        state
            .runtime
            .save_thread_mode_definition(
                &request.operation_id,
                request.expected_revision,
                request.document,
            )
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(delete, path = "/api/v1/thread-modes/{mode_id}", operation_id = "threadMode.deleteDefinition", params(("mode_id" = String, Path)), request_body = ModeDefinitionCommandRequest, responses(StudioApiErrors, (status = 200)))]
async fn delete_thread_mode_definition(
    State(state): State<AppState>,
    Path(mode_id): Path<String>,
    ApiJson(request): ApiJson<ModeDefinitionCommandRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .delete_thread_mode_definition(
                &request.operation_id,
                request.expected_revision,
                &parse_mode(&mode_id)?,
            )
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/thread-modes/reload", operation_id = "threadMode.reloadDefinitions", request_body = ModeDefinitionCommandRequest, responses(StudioApiErrors, (status = 200)))]
async fn reload_thread_mode_definitions(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<ModeDefinitionCommandRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .reload_thread_mode_definitions(&request.operation_id, request.expected_revision)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/thread-modes/validate", operation_id = "threadMode.validateDefinition", request_body = ValidateThreadModeDefinitionRequest, responses(StudioApiErrors, (status = 200)))]
async fn validate_thread_mode_definition(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<ValidateThreadModeDefinitionRequest>,
) -> Result<Json<pl_protocol::ThreadModeValidationResult>, ApiError> {
    Ok(Json(
        state.runtime.validate_thread_mode_definition(&request.json),
    ))
}

#[utoipa::path(get, path = "/api/v1/thread-modes/schema", operation_id = "threadMode.definitionSchema", responses(StudioApiErrors, (status = 200)))]
async fn thread_mode_definition_schema(
    State(state): State<AppState>,
) -> Result<Json<serde_json::Value>, ApiError> {
    let schema = serde_json::from_str(&state.runtime.thread_mode_definition_schema())
        .map_err(|_| ApiError(StudioError::internal()))?;
    Ok(Json(schema))
}

#[utoipa::path(post, path = "/api/v1/thread-modes/preview", operation_id = "threadMode.previewWorkflow", responses(StudioApiErrors, (status = 200)))]
async fn preview_thread_mode_workflow(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<WorkflowPreviewRequest>,
) -> Result<Json<pl_protocol::WorkflowPreviewSnapshot>, ApiError> {
    Ok(Json(
        state
            .runtime
            .preview_thread_mode_workflow(request)
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(get, path = "/api/v1/threads/{thread_id}/turns", operation_id = "thread.listTurns", params(("thread_id" = String, Path), ("cursor" = Option<String>, Query), ("limit" = Option<u32>, Query)), responses(StudioApiErrors, (status = 200)))]
async fn list_thread_turns(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    ApiQuery(query): ApiQuery<ThreadPageQuery>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .list_thread_turns(&thread_id, query.cursor.as_deref(), query.limit())
            .await
            .map_err(ApiError::from)?,
    ))
}

/// 一页 Timeline 内容：升序轻量预览、真实更旧边界与 `hasOlder`。
///
/// 读取的是共享会话的同一内容源（已落盘行 + 尚未落盘的已成立事实），因此实时与冷历史没有两套入口。
/// `before` 必须是上一页返回的不透明 token；旧 `kind`/`itemId`/`anchor`/`cursor` 参数一律拒绝。
#[utoipa::path(get, path = "/api/v1/threads/{thread_id}/timeline", operation_id = "thread.listTimeline", params(("thread_id" = String, Path), ("before" = Option<String>, Query), ("limit" = Option<u32>, Query)), responses(StudioApiErrors, (status = 200)))]
async fn list_thread_timeline(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    ApiQuery(query): ApiQuery<TimelinePageQuery>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .timeline_page(&thread_id, &query)
            .await
            .map_err(ApiError::from)?,
    ))
}

/// 按 `item`／`field`／`timelineEpoch` 分块读取不可变完整正文。
///
/// typed 查询绑定完成窗口的 epoch、字段身份、不透明 continuation 与块大小；
/// 不把执行 revision 当正文版本，跨 epoch 拒绝拼接，也不读取运行中的活动正文。
#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/timeline/items/{item_id}/detail", operation_id = "thread.readTimelineDetail", params(("thread_id" = String, Path), ("item_id" = String, Path)), request_body = TimelineDetailQuery, responses(StudioApiErrors, (status = 200)))]
async fn read_thread_timeline_detail(
    State(state): State<AppState>,
    Path((thread_id, item_id)): Path<(String, String)>,
    Json(query): Json<TimelineDetailQuery>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .read_timeline_detail(&thread_id, &item_id, &query)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/prompts", operation_id = "prompt.submit", params(("thread_id" = String, Path)), request_body = SubmitPromptRequest, responses(StudioApiErrors, (status = 200)))]
async fn submit_prompt(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    ApiJson(request): ApiJson<SubmitPromptRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .submit_prompt_command(thread_id, request)
            .await
            .map_err(ApiError::from)?,
    ))
}

/// 用户无内容继续主会话。子会话目标由后端拒绝，不依赖客户端隐藏入口。
#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/continue", operation_id = "thread.continue", params(("thread_id" = String, Path)), request_body = ContinueThreadRequest, responses(StudioApiErrors, (status = 200, body = ContinueThreadResponse)))]
async fn continue_thread(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    ApiJson(request): ApiJson<ContinueThreadRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .continue_thread(thread_id, request)
            .await
            .map_err(ApiError::from)?,
    ))
}

/// 精确停止：目标执行由调用方观察并显式命名，用户可停止主会话或指定子成员。
#[utoipa::path(post, path = "/api/v1/threads/{thread_id}/stop", operation_id = "thread.stop", params(("thread_id" = String, Path)), request_body = StopThreadRequest, responses(StudioApiErrors, (status = 200, body = StopThreadResponse)))]
async fn stop_thread(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    ApiJson(request): ApiJson<StopThreadRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .stop_thread(thread_id, request)
            .await
            .map_err(ApiError::from)?,
    ))
}

/// 只读回查一次继续操作；查询不激活执行，也不解除后来发生的停止。
#[utoipa::path(get, path = "/api/v1/threads/{thread_id}/continuations/{operation_id}", operation_id = "thread.readContinuation", params(("thread_id" = String, Path), ("operation_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = ContinuationOperationView)))]
async fn read_continuation_operation(
    State(state): State<AppState>,
    Path((thread_id, operation_id)): Path<(String, String)>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .read_continuation_operation(thread_id, operation_id)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/attachments/drafts", operation_id = "attachment.admit", request_body = AdmitAttachmentDraftsRequest, responses(StudioApiErrors, (status = 200, body = AdmitAttachmentDraftsResponse)))]
async fn admit_attachment_drafts(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<AdmitAttachmentDraftsRequest>,
) -> Result<impl IntoResponse, ApiError> {
    if request
        .sources
        .iter()
        .any(|source| !matches!(source, StudioAttachmentDraftSource::RemoteUrl { .. }))
    {
        return Err(ApiError(StudioError::invalid_argument(
            "JSON attachment admission accepts only remoteUrl sources; local files use multipart upload",
        )));
    }
    Ok(Json(
        state
            .runtime
            .admit_attachment_drafts(request)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/attachments/drafts/upload", operation_id = "attachment.upload", responses(StudioApiErrors, (status = 200, body = AdmitAttachmentDraftsResponse)))]
async fn upload_attachment_drafts(
    State(state): State<AppState>,
    mut multipart: Multipart,
) -> Result<impl IntoResponse, ApiError> {
    let upload_dir = tempfile::Builder::new()
        .prefix("anywork-http-attachments-")
        .tempdir()
        .map_err(anyhow::Error::from)
        .map_err(ApiError::from)?;
    let mut context = None;
    let mut sources = Vec::new();

    while let Some(mut field) = multipart
        .next_field()
        .await
        .map_err(|_| invalid_multipart())?
    {
        match field.name() {
            Some("context") => {
                if context.is_some() || !sources.is_empty() {
                    return Err(invalid_multipart());
                }
                let text = field.text().await.map_err(|_| invalid_multipart())?;
                context = Some(
                    serde_json::from_str::<StudioAttachmentAdmissionContext>(&text)
                        .map_err(|_| invalid_multipart())?,
                );
            }
            Some("file") => {
                let admission_context = context.clone().ok_or_else(invalid_multipart)?;
                if sources.len() >= MAX_MULTIPART_FILES {
                    return Err(ApiError(StudioError::invalid_argument(
                        "multipart attachment file count exceeds the server limit",
                    )));
                }
                let filename = field
                    .file_name()
                    .and_then(safe_upload_filename)
                    .ok_or_else(invalid_multipart)?;
                let path = upload_dir
                    .path()
                    .join(format!("{:02}-{filename}", sources.len()));
                let source = StudioAttachmentDraftSource::LocalFile {
                    path: path.to_string_lossy().to_string(),
                };
                let mut predicted = sources.clone();
                predicted.push(source.clone());
                state
                    .runtime
                    .preflight_attachment_drafts(&AdmitAttachmentDraftsRequest {
                        context: admission_context,
                        sources: predicted,
                    })
                    .await
                    .map_err(ApiError::from)?;

                let mut file = tokio::fs::File::create(&path)
                    .await
                    .map_err(anyhow::Error::from)
                    .map_err(ApiError::from)?;
                let mut written = 0_usize;
                while let Some(chunk) = field.chunk().await.map_err(|_| invalid_multipart())? {
                    written = written.saturating_add(chunk.len());
                    if written > MAX_MULTIPART_FILE_BYTES {
                        return Err(ApiError(StudioError::invalid_argument(
                            "multipart attachment file exceeds the server limit",
                        )));
                    }
                    file.write_all(&chunk)
                        .await
                        .map_err(anyhow::Error::from)
                        .map_err(ApiError::from)?;
                }
                file.flush()
                    .await
                    .map_err(anyhow::Error::from)
                    .map_err(ApiError::from)?;
                sources.push(source);
            }
            _ => return Err(invalid_multipart()),
        }
    }

    let request = AdmitAttachmentDraftsRequest {
        context: context.ok_or_else(invalid_multipart)?,
        sources,
    };
    Ok(Json(
        state
            .runtime
            .admit_attachment_drafts(request)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(delete, path = "/api/v1/attachments/drafts/{draft_id}", operation_id = "attachment.removeDraft", params(("draft_id" = String, Path)), responses(StudioApiErrors, (status = 204)))]
async fn remove_attachment_draft(
    State(state): State<AppState>,
    Path(draft_id): Path<String>,
) -> Result<StatusCode, ApiError> {
    if !state
        .runtime
        .remove_attachment_draft(draft_id)
        .await
        .map_err(ApiError::from)?
    {
        return Err(ApiError(StudioError::not_found("AttachmentDraft")));
    }
    Ok(StatusCode::NO_CONTENT)
}

#[utoipa::path(get, path = "/api/v1/attachments/drafts/{draft_id}", operation_id = "attachment.readDraft", params(("draft_id" = String, Path)), responses(StudioApiErrors, (status = 200, content_type = "application/octet-stream")))]
async fn read_attachment_draft(
    State(state): State<AppState>,
    Path(draft_id): Path<String>,
) -> Result<impl IntoResponse, ApiError> {
    let bytes = state
        .runtime
        .read_attachment_draft(draft_id)
        .await
        .map_err(ApiError::from)?;
    Ok((
        [(header::CONTENT_TYPE, "application/octet-stream")],
        Bytes::from(bytes),
    ))
}

#[utoipa::path(get, path = "/api/v1/threads/{thread_id}/attachments/{attachment_id}", operation_id = "attachment.readThread", params(("thread_id" = String, Path), ("attachment_id" = String, Path)), responses(StudioApiErrors, (status = 200, content_type = "application/octet-stream")))]
async fn read_thread_attachment(
    State(state): State<AppState>,
    Path((thread_id, attachment_id)): Path<(String, String)>,
) -> Result<impl IntoResponse, ApiError> {
    let bytes = state
        .runtime
        .read_thread_attachment(thread_id, attachment_id)
        .await
        .map_err(ApiError::from)?;
    Ok((
        [(header::CONTENT_TYPE, "application/octet-stream")],
        Bytes::from(bytes),
    ))
}

fn invalid_multipart() -> ApiError {
    ApiError(StudioError::invalid_argument(
        "invalid multipart attachment admission body",
    ))
}

fn safe_upload_filename(filename: &str) -> Option<String> {
    let filename = std::path::Path::new(filename).file_name()?.to_str()?;
    let sanitized = filename
        .chars()
        .take(120)
        .map(|character| {
            if character.is_alphanumeric() || matches!(character, '.' | '-' | '_' | ' ') {
                character
            } else {
                '_'
            }
        })
        .collect::<String>();
    let sanitized = sanitized.trim().trim_matches('.');
    (!sanitized.is_empty()).then(|| sanitized.to_string())
}

#[utoipa::path(put, path = "/api/v1/interactions/{interaction_id}/resolution", operation_id = "interaction.respond", params(("interaction_id" = String, Path)), request_body = ResolveInteractionRequest, responses(StudioApiErrors, (status = 200)))]
async fn resolve_interaction(
    State(state): State<AppState>,
    Path(interaction_id): Path<String>,
    ApiJson(request): ApiJson<ResolveInteractionRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .resolve_interaction(
                request.operation_id,
                request.host_thread_id,
                request.expected_revision,
                interaction_id,
                request.resolution,
            )
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/delegation/models/query", operation_id = "delegation.listModels", request_body = ListDelegationModelsRequest, responses(StudioApiErrors, (status = 200, body = DelegationModelList)))]
async fn list_delegation_models(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<ListDelegationModelsRequest>,
) -> Result<Json<DelegationModelList>, ApiError> {
    Ok(Json(
        state
            .runtime
            .list_delegation_models(request)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/delegation/models/detail", operation_id = "delegation.getModel", request_body = GetDelegationModelRequest, responses(StudioApiErrors, (status = 200, body = DelegationModelDetail)))]
async fn get_delegation_model(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<GetDelegationModelRequest>,
) -> Result<Json<DelegationModelDetail>, ApiError> {
    Ok(Json(
        state
            .runtime
            .get_delegation_model(request)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(get, path = "/api/v1/settings/account-catalog", operation_id = "settings.loadAccountCatalog", responses(StudioApiErrors, (status = 200)))]
async fn account_catalog(State(state): State<AppState>) -> Result<impl IntoResponse, ApiError> {
    let snapshot = state
        .runtime
        .load_account_catalog()
        .map_err(ApiError::from)?;
    Ok(Json(snapshot))
}

#[utoipa::path(get, path = "/api/v1/settings", operation_id = "settings.read", responses(StudioApiErrors, (status = 200, body = SettingsStateResponse)))]
async fn read_settings(
    State(state): State<AppState>,
) -> Result<Json<SettingsStateResponse>, ApiError> {
    Ok(Json(state.runtime.read_settings().map_err(ApiError::from)?))
}

#[utoipa::path(post, path = "/api/v1/settings/reload", operation_id = "settings.reload", request_body = ExpectedRevisionRequest, responses(StudioApiErrors, (status = 200, body = SettingsStateResponse)))]
async fn reload_settings(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<ExpectedRevisionRequest>,
) -> Result<Json<SettingsStateResponse>, ApiError> {
    Ok(Json(
        state
            .runtime
            .reload_settings(request.expected_revision)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(delete, path = "/api/v1/settings/account-models", operation_id = "settings.removeAccountModel", request_body = RemoveAccountModelRequest, responses(StudioApiErrors, (status = 200, body = SettingsCommandReply)))]
async fn remove_account_model(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<RemoveAccountModelRequest>,
) -> Result<Json<SettingsCommandReply>, ApiError> {
    Ok(Json(
        state
            .runtime
            .remove_account_model(request)
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(put, path = "/api/v1/settings/permission", operation_id = "settings.savePermission", request_body = UpdatePermissionSettingsRequest, responses(StudioApiErrors, (status = 200, body = SettingsCommandReply)))]
async fn save_permission_settings(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<UpdatePermissionSettingsRequest>,
) -> Result<Json<SettingsCommandReply>, ApiError> {
    Ok(Json(
        state
            .runtime
            .save_permission_settings(request)
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(put, path = "/api/v1/settings/account-model-enabled", operation_id = "settings.setAccountModelEnabled", request_body = SetAccountModelEnabledRequest, responses(StudioApiErrors, (status = 200, body = SettingsCommandReply)))]
async fn set_account_model_enabled(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<SetAccountModelEnabledRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .set_account_model_enabled(request)
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(put, path = "/api/v1/settings/account-billing-kind", operation_id = "settings.setAccountBillingKind", request_body = SetAccountBillingKindRequest, responses(StudioApiErrors, (status = 200, body = SettingsCommandReply)))]
async fn set_account_billing_kind(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<SetAccountBillingKindRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .set_account_billing_kind(request)
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/accounts", operation_id = "accounts.create", request_body = CreateAccountRequest, responses(StudioApiErrors, (status = 200, body = SettingsCommandReply)))]
async fn create_account(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<CreateAccountRequest>,
) -> Result<Json<SettingsCommandReply>, ApiError> {
    Ok(Json(
        state
            .runtime
            .create_account(request)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(patch, path = "/api/v1/accounts", operation_id = "accounts.patch", request_body = PatchAccountRequest, responses(StudioApiErrors, (status = 200, body = SettingsCommandReply)))]
async fn patch_account(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<PatchAccountRequest>,
) -> Result<Json<SettingsCommandReply>, ApiError> {
    Ok(Json(state.runtime.patch_account(request).await?))
}

#[utoipa::path(put, path = "/api/v1/accounts/model-auto-compact", operation_id = "accounts.setModelAutoCompact", request_body = SetAccountModelAutoCompactRequest, responses(StudioApiErrors, (status = 200, body = SettingsCommandReply)))]
async fn set_account_model_auto_compact(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<SetAccountModelAutoCompactRequest>,
) -> Result<Json<SettingsCommandReply>, ApiError> {
    Ok(Json(state.runtime.set_account_model_auto_compact(request)?))
}

#[utoipa::path(put, path = "/api/v1/accounts/model-connection", operation_id = "accounts.setModelConnection", request_body = SetAccountModelConnectionRequest, responses(StudioApiErrors, (status = 200, body = SettingsCommandReply)))]
async fn set_account_model_connection(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<SetAccountModelConnectionRequest>,
) -> Result<Json<SettingsCommandReply>, ApiError> {
    Ok(Json(state.runtime.set_account_model_connection(request)?))
}

#[utoipa::path(post, path = "/api/v1/accounts/sync-models", operation_id = "accounts.syncModels", request_body = SyncAccountModelsRequest, responses(StudioApiErrors, (status = 200, body = SyncAccountModelsReply)))]
async fn sync_account_models(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<SyncAccountModelsRequest>,
) -> Result<Json<SyncAccountModelsReply>, ApiError> {
    Ok(Json(state.runtime.sync_account_models(request).await?))
}

#[utoipa::path(post, path = "/api/v1/accounts/read", operation_id = "accounts.read", request_body = AccountObservationTarget, responses(StudioApiErrors, (status = 200, body = AccountDomainFrame)))]
async fn read_account_domain(
    State(state): State<AppState>,
    ApiJson(target): ApiJson<AccountObservationTarget>,
) -> Result<Json<AccountDomainFrame>, ApiError> {
    Ok(Json(state.runtime.read_account_domain(&target)?))
}

#[utoipa::path(put, path = "/api/v1/settings/default-account", operation_id = "settings.setDefaultAccount", request_body = SetDefaultAccountRequest, responses(StudioApiErrors, (status = 200, body = SettingsCommandReply)))]
async fn set_default_account(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<SetDefaultAccountRequest>,
) -> Result<Json<SettingsCommandReply>, ApiError> {
    Ok(Json(
        state
            .runtime
            .set_default_account(request)
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(delete, path = "/api/v1/settings/accounts", operation_id = "settings.removeAccount", request_body = RemoveAccountRequest, responses(StudioApiErrors, (status = 200, body = SettingsCommandReply)))]
async fn remove_account(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<RemoveAccountRequest>,
) -> Result<Json<SettingsCommandReply>, ApiError> {
    Ok(Json(
        state
            .runtime
            .remove_account(request)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(put, path = "/api/v1/settings/field", operation_id = "settings.applyField", request_body = UpdateSettingsFieldRequest, responses(StudioApiErrors, (status = 200, body = SettingsCommandReply)))]
async fn apply_settings_field(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<UpdateSettingsFieldRequest>,
) -> Result<Json<SettingsCommandReply>, ApiError> {
    Ok(Json(
        state
            .runtime
            .apply_settings_field(request)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(get, path = "/api/v1/acp-account-catalog", operation_id = "settings.loadAcpAccountCatalog", responses(StudioApiErrors, (status = 200, body = AcpAccountCatalog)))]
async fn acp_account_catalog(
    State(state): State<AppState>,
) -> Result<Json<AcpAccountCatalog>, ApiError> {
    Ok(Json(state.runtime.load_acp_account_catalog()))
}

#[utoipa::path(put, path = "/api/v1/settings/acp-account", operation_id = "settings.saveAcpAccount", request_body = UpdateAcpAccountRequest, responses(StudioApiErrors, (status = 200, body = SettingsCommandReply)))]
async fn save_acp_account(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<UpdateAcpAccountRequest>,
) -> Result<Json<SettingsCommandReply>, ApiError> {
    Ok(Json(
        state
            .runtime
            .save_acp_account(request)
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(delete, path = "/api/v1/settings/acp-account", operation_id = "settings.removeAcpAccount", request_body = RemoveAcpAccountRequest, responses(StudioApiErrors, (status = 200, body = SettingsCommandReply)))]
async fn remove_acp_account(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<RemoveAcpAccountRequest>,
) -> Result<Json<SettingsCommandReply>, ApiError> {
    Ok(Json(
        state
            .runtime
            .remove_acp_account(request)
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(get, path = "/api/v1/runtime/acp-auth", operation_id = "acpAuth.read", responses(StudioApiErrors, (status = 200, body = AcpAuthSnapshot)))]
async fn read_acp_auth(State(state): State<AppState>) -> Result<Json<AcpAuthSnapshot>, ApiError> {
    Ok(Json(state.runtime.read_acp_auth_state()))
}

#[utoipa::path(post, path = "/api/v1/runtime/acp-auth/start", operation_id = "acpAuth.start", request_body = StartAcpAuthRequest, responses(StudioApiErrors, (status = 200, body = AcpAuthCommandReply)))]
async fn start_acp_auth(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<StartAcpAuthRequest>,
) -> Result<Json<AcpAuthCommandReply>, ApiError> {
    Ok(Json(
        state
            .runtime
            .start_acp_auth(request)
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/runtime/acp-auth/cancel", operation_id = "acpAuth.cancel", request_body = CancelAcpAuthRequest, responses(StudioApiErrors, (status = 200, body = AcpAuthCommandReply)))]
async fn cancel_acp_auth(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<CancelAcpAuthRequest>,
) -> Result<Json<AcpAuthCommandReply>, ApiError> {
    Ok(Json(
        state
            .runtime
            .cancel_acp_auth(request)
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(get, path = "/api/v1/runtime/acp-install", operation_id = "acpInstall.read", responses(StudioApiErrors, (status = 200, body = AcpInstallSnapshot)))]
async fn read_acp_install(
    State(state): State<AppState>,
) -> Result<Json<AcpInstallSnapshot>, ApiError> {
    Ok(Json(state.runtime.read_acp_install_state()))
}

#[utoipa::path(post, path = "/api/v1/runtime/acp-install/start", operation_id = "acpInstall.start", request_body = StartAcpInstallRequest, responses(StudioApiErrors, (status = 200, body = AcpInstallCommandReply)))]
async fn start_acp_install(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<StartAcpInstallRequest>,
) -> Result<Json<AcpInstallCommandReply>, ApiError> {
    Ok(Json(
        state
            .runtime
            .start_acp_install(request)
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/runtime/acp-install/cancel", operation_id = "acpInstall.cancel", request_body = CancelAcpInstallRequest, responses(StudioApiErrors, (status = 200, body = AcpInstallCommandReply)))]
async fn cancel_acp_install(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<CancelAcpInstallRequest>,
) -> Result<Json<AcpInstallCommandReply>, ApiError> {
    Ok(Json(
        state
            .runtime
            .cancel_acp_install(request)
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(put, path = "/api/v1/threads/{thread_id}/model-route", operation_id = "thread.setModelRoute", params(("thread_id" = String, Path)), request_body = SetThreadModelRouteRequest, responses(StudioApiErrors, (status = 200, body = ThreadModelRouteCommandReply)))]
async fn set_thread_model_route(
    State(state): State<AppState>,
    Path(thread_id): Path<String>,
    ApiJson(request): ApiJson<SetThreadModelRouteRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .save_thread_model_route(&thread_id, request)
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(get, path = "/api/v1/runtime/account-usage", operation_id = "accountUsage.read", responses(StudioApiErrors, (status = 200)))]
async fn read_account_usage(State(state): State<AppState>) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .read_account_domain(&AccountObservationTarget::Usage)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/runtime/account-usage/{account_id}/check", operation_id = "accountUsage.check", params(("account_id" = String, Path)), responses(StudioApiErrors, (status = 200)))]
async fn check_account_usage(
    State(state): State<AppState>,
    Path(account_id): Path<String>,
) -> Result<impl IntoResponse, ApiError> {
    state.runtime.check_account_usage(&account_id).await?;
    Ok(Json(
        state
            .runtime
            .read_account_domain(&AccountObservationTarget::Usage)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/runtime/persistence/retry", operation_id = "persistence.retry", responses(StudioApiErrors, (status = 200)))]
async fn retry_persistence(State(state): State<AppState>) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .retry_persistence()
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/runtime/threads/{thread_id}/history/retry/{fault_generation}", operation_id = "persistence.retryThreadHistory", params(("thread_id" = String, Path), ("fault_generation" = u64, Path)), responses(StudioApiErrors, (status = 200)))]
async fn retry_thread_history(
    State(state): State<AppState>,
    Path((thread_id, fault_generation)): Path<(String, u64)>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .retry_thread_history(&thread_id, fault_generation)
            .await
            .map_err(ApiError::from)?,
    ))
}

/// 硬故障恢复后的显式继续；与“重试保存”分开，核验代数与水位后才解除准入闩。
#[utoipa::path(post, path = "/api/v1/runtime/threads/{thread_id}/history/resume/{fault_generation}", operation_id = "persistence.resumeThreadHistory", params(("thread_id" = String, Path), ("fault_generation" = u64, Path)), responses(StudioApiErrors, (status = 200)))]
async fn resume_thread_history(
    State(state): State<AppState>,
    Path((thread_id, fault_generation)): Path<(String, u64)>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .resume_thread_history(&thread_id, fault_generation)
            .await
            .map_err(ApiError::from)?,
    ))
}

/// 进程级持久化队列压力与逐 Thread 水位；纯读取，不触发写入、重试或恢复。
#[utoipa::path(get, path = "/api/v1/runtime/persistence/queue", operation_id = "persistence.readQueue", responses(StudioApiErrors, (status = 200)))]
async fn read_persistence_queue(
    State(state): State<AppState>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(state.runtime.persistence_queue_snapshot()))
}

#[utoipa::path(get, path = "/api/v1/runtime/projects/{project_id}/skills", operation_id = "skills.read", params(("project_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = crate::skills_schema::SkillsStateSnapshotSchema)))]
async fn read_skills(
    State(state): State<AppState>,
    Path(project_id): Path<String>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(state.runtime.read_skills_state(&project_id).await))
}

#[utoipa::path(post, path = "/api/v1/runtime/projects/{project_id}/skills/discover", operation_id = "skills.discover", params(("project_id" = String, Path)), responses(StudioApiErrors, (status = 200, body = crate::skills_schema::SkillsStateSnapshotSchema)))]
async fn discover_skills(
    State(state): State<AppState>,
    Path(project_id): Path<String>,
) -> Result<impl IntoResponse, ApiError> {
    let snapshot = state
        .runtime
        .discover_skills(&project_id)
        .await
        .map_err(ApiError::from)?;
    Ok(Json(pl_studio_runtime::StudioSkillsStateSnapshot::from(
        snapshot,
    )))
}

#[utoipa::path(post, path = "/api/v1/runtime/projects/{project_id}/skills/search", operation_id = "skills.search", params(("project_id" = String, Path)), request_body = SearchSkillsRequest, responses(StudioApiErrors, (status = 200, body = crate::skills_schema::SkillSearchResultSchema)))]
async fn search_skills(
    State(state): State<AppState>,
    Path(project_id): Path<String>,
    ApiJson(request): ApiJson<SearchSkillsRequest>,
) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .search_skills(&project_id, &request.query, request.limit.unwrap_or(50))
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(get, path = "/api/v1/runtime/mcp", operation_id = "mcp.read", responses(StudioApiErrors, (status = 200)))]
async fn read_mcp(State(state): State<AppState>) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .read_mcp_state()
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(post, path = "/api/v1/runtime/mcp/reset", operation_id = "mcp.reset", request_body = McpResetRequest, responses(StudioApiErrors, (status = 200)))]
async fn reset_mcp(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<McpResetRequest>,
) -> Result<impl IntoResponse, ApiError> {
    state
        .runtime
        .reset_mcp(request)
        .await
        .map_err(ApiError::from)?;
    Ok(Json(
        state
            .runtime
            .read_mcp_state()
            .await
            .map_err(ApiError::from)?,
    ))
}

#[utoipa::path(get, path = "/api/v1/runtime/lsp", operation_id = "lsp.read", responses(StudioApiErrors, (status = 200)))]
async fn read_lsp(State(state): State<AppState>) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(state.runtime.read_lsp_state().await))
}

#[utoipa::path(post, path = "/api/v1/runtime/projects/{project_id}/lsp/probe", operation_id = "lsp.probe", params(("project_id" = String, Path)), responses(StudioApiErrors, (status = 200)))]
async fn probe_lsp(
    State(state): State<AppState>,
    Path(project_id): Path<String>,
) -> Result<impl IntoResponse, ApiError> {
    state
        .runtime
        .probe_lsp_server(&project_id)
        .await
        .map_err(ApiError::from)?;
    Ok(Json(state.runtime.read_lsp_state().await))
}

#[utoipa::path(post, path = "/api/v1/runtime/projects/{project_id}/lsp/{server_id}/repair", operation_id = "lsp.repair", params(("project_id" = String, Path), ("server_id" = String, Path)), responses(StudioApiErrors, (status = 200)))]
async fn repair_lsp(
    State(state): State<AppState>,
    Path((project_id, server_id)): Path<(String, String)>,
) -> Result<impl IntoResponse, ApiError> {
    state
        .runtime
        .repair_lsp_server(&project_id, &server_id)
        .await
        .map_err(ApiError::from)?;
    Ok(Json(state.runtime.read_lsp_state().await))
}

#[utoipa::path(post, path = "/api/v1/runtime/lsp/reset", operation_id = "lsp.reset", request_body = LspResetRequest, responses(StudioApiErrors, (status = 200)))]
async fn reset_lsp(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<LspResetRequest>,
) -> Result<impl IntoResponse, ApiError> {
    state
        .runtime
        .reset_lsp_request(request)
        .await
        .map_err(ApiError::from)?;
    Ok(Json(state.runtime.read_lsp_state().await))
}

#[utoipa::path(get, path = "/api/v1/runtime/update", operation_id = "update.read", responses(StudioApiErrors, (status = 200)))]
async fn read_update(State(state): State<AppState>) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(state.runtime.read_update_state().await))
}

#[utoipa::path(post, path = "/api/v1/runtime/update/check", operation_id = "update.check", responses(StudioApiErrors, (status = 200)))]
async fn check_update(State(state): State<AppState>) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .check_studio_update(&pl_studio_runtime::StudioUpdateCancellation::new())
            .await
            .map_err(ApiError::from)?,
    ))
}

fn parse_mode(mode: &str) -> Result<ThreadModeId, ApiError> {
    ThreadModeId::from_label(mode.trim()).map_err(|_| {
        ApiError(StudioError::invalid_argument(format!(
            "unsupported Thread mode: {}",
            mode.trim()
        )))
    })
}

#[utoipa::path(get, path = "/api/v1/runtime/recovery", operation_id = "recovery.read", responses(StudioApiErrors, (status = 200)))]
async fn read_recovery(State(state): State<AppState>) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(state.runtime.read_recovery_state()))
}

#[utoipa::path(post, path = "/api/v1/runtime/recovery/retry", operation_id = "recovery.retry", responses(StudioApiErrors, (status = 200)))]
async fn retry_recovery(State(state): State<AppState>) -> Result<impl IntoResponse, ApiError> {
    Ok(Json(
        state
            .runtime
            .retry_recovery()
            .await
            .map_err(ApiError::from)?,
    ))
}

//! Retained command responsibility uses the existing normal-request permit, not a new pool.
use super::{
    tasks::{self, Completion},
    types::EmptyRequest,
};
use crate::{
    AppState,
    error::ApiError,
    routes::{ApiJson, ApiPath as Path, StudioApiErrors},
};
use axum::{Json, extract::State, http::StatusCode};
use futures::FutureExt;
use pl_protocol::products::configuration_calls::{
    ConfigurationCallKind, ConfigurationCallOutcome, ConfigurationCallRequest,
};
use pl_protocol::products::configuration_commands::{
    ConfigurationCommandCallIdentity, ConfigurationCommandOutcome, ConfigurationCommandRequest,
};
use pl_protocol::studio::{
    CleanupRecovery, FeedCloseIssue, FeedCloseOutcome, FeedCloseReport, StudioError,
};
use pl_studio_runtime::{StudioRuntime, configuration::ConfigurationCallResult};
use serde::Deserialize;
use std::sync::{Arc, Mutex};
use tokio::sync::{Notify, OwnedSemaphorePermit, watch};
use utoipa::ToSchema;

struct CommandState {
    closing: bool,
    released: bool,
    task: Option<Completion>,
    permit: Option<OwnedSemaphorePermit>,
    inflight_results: usize,
    join_issue: Option<FeedCloseIssue>,
    owned_result: Option<ConfigurationCallResult>,
}
pub(super) struct CommandOwner {
    identity: ConfigurationCommandCallIdentity,
    request: ConfigurationCallRequest,
    result: watch::Sender<Option<ConfigurationCallOutcome>>,
    state: Mutex<CommandState>,
    results_changed: Notify,
}

/// Held through the concrete handler's typed outcome/Json construction. A cancelled handler
/// drops the same non-cloneable registration; there is no detached result query to abandon.
pub(super) struct CommandResultQuery {
    owner: Arc<CommandOwner>,
    result: watch::Receiver<Option<ConfigurationCallOutcome>>,
}
impl CommandOwner {
    pub(super) fn new(
        request: ConfigurationCallRequest,
        identity: ConfigurationCommandCallIdentity,
        permit: OwnedSemaphorePermit,
    ) -> Arc<Self> {
        let (result, _) = watch::channel(None);
        Arc::new(Self {
            identity,
            request,
            result,
            results_changed: Notify::new(),
            state: Mutex::new(CommandState {
                closing: false,
                released: false,
                task: None,
                permit: Some(permit),
                inflight_results: 0,
                join_issue: None,
                owned_result: None,
            }),
        })
    }
    pub(super) fn operation_id(&self) -> &str {
        self.request.operation_id()
    }
    pub(super) fn call_id(&self) -> &str {
        &self.identity.call_id
    }
    pub(super) fn identity(&self) -> ConfigurationCommandCallIdentity {
        self.identity.clone()
    }
    pub(super) fn require_kind(&self, kind: ConfigurationCallKind) -> Result<(), StudioError> {
        if self.request.kind() == kind {
            Ok(())
        } else {
            Err(StudioError::new(
                pl_protocol::studio::StudioErrorCode::Conflict,
                "Original call belongs to a different Configuration resource kind",
                false,
            ))
        }
    }
    pub(super) fn same_request(&self, request: &ConfigurationCallRequest) -> bool {
        &self.request == request
    }
    pub(super) fn start(self: &Arc<Self>, runtime: StudioRuntime) {
        let owner = self.clone();
        let task = tokio::spawn(async move {
            match std::panic::AssertUnwindSafe(ConfigurationCallResult::run(
                &runtime,
                owner.request.clone(),
            ))
            .catch_unwind()
            .await
            {
                Ok(result) => {
                    let outcome = result.outcome();
                    // Store the actual native capture before publishing the pure wire outcome,
                    // even if requestClose won while the original worker was still in flight.
                    owner
                        .state
                        .lock()
                        .unwrap_or_else(std::sync::PoisonError::into_inner)
                        .owned_result = Some(result);
                    owner.result.send_replace(Some(outcome));
                }
                Err(panic) => {
                    owner
                        .result
                        .send_replace(Some(owner.request.unknown(StudioError::internal())));
                    std::panic::resume_unwind(panic);
                }
            }
        });
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .task = Some(tasks::retain(task));
    }
    pub(super) fn result_query(self: &Arc<Self>) -> Result<CommandResultQuery, StudioError> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.closing || state.released {
            return Err(tasks::cancelled());
        }
        let next = state.inflight_results.checked_add(1).ok_or_else(|| {
            StudioError::new(
                pl_protocol::studio::StudioErrorCode::Overloaded,
                "Configuration result query count is exhausted",
                false,
            )
        })?;
        // Construct before incrementing, under the same guard as the close fence.
        let query = CommandResultQuery {
            owner: self.clone(),
            result: self.result.subscribe(),
        };
        state.inflight_results = next;
        Ok(query)
    }
    pub(super) fn request_close(&self) {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .closing = true;
    }
    pub(super) async fn close(&self) -> Vec<FeedCloseIssue> {
        self.request_close();
        let task = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .task
            .clone();
        if let Some(task) = task
            && task.await.is_err()
        {
            self.state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .join_issue
                .get_or_insert_with(|| {
                    tasks::issue(
                        "commandJoinError",
                        "The original Configuration command task failed to join",
                        CleanupRecovery::Terminal,
                    )
                });
        }
        self.wait_results().await;
        let (result, permit) = {
            let mut state = self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if state.closing
                && state.join_issue.is_none()
                && state.inflight_results == 0
                && state.task.as_ref().is_some_and(tasks::succeeded)
            {
                state.released = true;
                (state.owned_result.take(), state.permit.take())
            } else {
                (None, None)
            }
        };
        drop(result);
        drop(permit);
        self.issues(false)
    }
    async fn wait_results(&self) {
        loop {
            let changed = self.results_changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if self
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .inflight_results
                == 0
            {
                return;
            }
            changed.await;
        }
    }
    pub(super) fn issues(&self, timed_out: bool) -> Vec<FeedCloseIssue> {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.task.as_ref().is_some_and(tasks::failed) && state.join_issue.is_none() {
            state.join_issue = Some(tasks::issue(
                "commandJoinError",
                "The original Configuration command task failed to join",
                CleanupRecovery::Terminal,
            ));
        }
        let mut issues: Vec<_> = state.join_issue.iter().cloned().collect();
        if state
            .task
            .as_ref()
            .is_some_and(|task| !tasks::finished(task))
        {
            issues.push(tasks::issue(
                if timed_out {
                    "deadlineExceeded"
                } else {
                    "commandPending"
                },
                "The original Configuration command still owns work",
                CleanupRecovery::AwaitCompletion,
            ));
        }
        if state.inflight_results != 0 {
            issues.push(tasks::issue(
                if timed_out {
                    "deadlineExceeded"
                } else {
                    "resultQueriesPending"
                },
                "Admitted Configuration call result queries have not finished",
                CleanupRecovery::AwaitCompletion,
            ));
        }
        // A deadline can cancel close just before its release step, and the last query may
        // finish before this snapshot. Zero waiters alone is not proof that close completed.
        if state.closing && !state.released && state.join_issue.is_none() {
            let recovery = if state.inflight_results == 0
                && state.task.as_ref().is_some_and(tasks::succeeded)
            {
                CleanupRecovery::RetryClose
            } else {
                CleanupRecovery::AwaitCompletion
            };
            issues.push(tasks::issue(
                if timed_out {
                    "deadlineExceeded"
                } else {
                    "commandCleanupPending"
                },
                "The original Configuration call has not completed its close gate",
                recovery,
            ));
        }
        issues
    }
    pub(super) fn is_released(&self) -> bool {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .released
    }
}

impl CommandResultQuery {
    pub(super) async fn result(&mut self) -> Result<ConfigurationCallOutcome, StudioError> {
        loop {
            if let Some(value) = self.result.borrow_and_update().clone() {
                return Ok(value);
            }
            self.result
                .changed()
                .await
                .map_err(|_| StudioError::internal())?;
        }
    }
}
impl Drop for CommandResultQuery {
    fn drop(&mut self) {
        let drained = {
            let mut state = self
                .owner
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            // Private construction creates one non-cloneable guard for each increment.
            state.inflight_results -= 1;
            state.inflight_results == 0
        };
        if drained {
            self.owner.results_changed.notify_waiters();
        }
    }
}

#[derive(Deserialize, ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct FindConfigurationCommandRequest {
    operation_id: String,
}

#[utoipa::path(post, path = "/api/v1/products/configuration/commands/begin", operation_id = "configuration.command.begin", request_body = ConfigurationCommandRequest,
    responses(StudioApiErrors, (status = 200, body = ConfigurationCommandCallIdentity)))]
pub(super) async fn begin(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<ConfigurationCommandRequest>,
) -> Result<Json<ConfigurationCommandCallIdentity>, ApiError> {
    if request.operation_id().trim().is_empty() {
        return Err(StudioError::invalid_argument("operationId is required").into());
    }
    let owner = state.configuration.begin_command(
        state.runtime.clone(),
        &state.shutdown,
        &state.normal_requests,
        ConfigurationCallRequest::Configuration(request),
    )?;
    Ok(Json(owner.identity()))
}
#[utoipa::path(post, path = "/api/v1/products/configuration/commands/find", operation_id = "configuration.command.find", request_body = FindConfigurationCommandRequest,
    responses(StudioApiErrors, (status = 200, body = Option<ConfigurationCommandCallIdentity>)))]
pub(super) async fn find(
    State(state): State<AppState>,
    ApiJson(request): ApiJson<FindConfigurationCommandRequest>,
) -> Result<Json<Option<ConfigurationCommandCallIdentity>>, ApiError> {
    // Full typed String domain: no trimming, path encoding restriction, admission or dispatch.
    Ok(Json(
        state
            .configuration
            .find_command(&request.operation_id, ConfigurationCallKind::Configuration)?
            .map(|owner| owner.identity()),
    ))
}
#[utoipa::path(post, path = "/api/v1/configuration-commands/{call_id}/result", operation_id = "configuration.command.result", params(("call_id" = String, Path)), request_body = EmptyRequest,
    responses(StudioApiErrors, (status = 200, body = ConfigurationCommandOutcome)))]
pub(super) async fn result(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<ConfigurationCommandOutcome>, ApiError> {
    let owner = state
        .configuration
        .command(&id, ConfigurationCallKind::Configuration)?;
    let mut query = owner.result_query()?;
    match query.result().await? {
        ConfigurationCallOutcome::Configuration(value) => Ok(Json(value)),
        _ => Err(StudioError::new(
            pl_protocol::studio::StudioErrorCode::Protocol,
            "Original call result has the wrong resource kind",
            false,
        )
        .into()),
    }
}
#[utoipa::path(post, path = "/api/v1/configuration-commands/{call_id}/request-close", operation_id = "configuration.command.requestClose", params(("call_id" = String, Path)), request_body = EmptyRequest,
    responses(StudioApiErrors, (status = 204)))]
pub(super) async fn request_close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<StatusCode, ApiError> {
    state
        .configuration
        .command(&id, ConfigurationCallKind::Configuration)?
        .request_close();
    Ok(StatusCode::NO_CONTENT)
}
#[utoipa::path(post, path = "/api/v1/configuration-commands/{call_id}/close", operation_id = "configuration.command.close", params(("call_id" = String, Path)), request_body = EmptyRequest,
    responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    ApiJson(_): ApiJson<EmptyRequest>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    let issues = state
        .configuration
        .command(&id, ConfigurationCallKind::Configuration)?
        .close()
        .await;
    let report = FeedCloseReport {
        feed_id: id,
        outcome: if issues.is_empty() {
            FeedCloseOutcome::Clean
        } else {
            FeedCloseOutcome::Unresolved { issues }
        },
    };
    state.configuration.reap();
    Ok(Json(report))
}
#[utoipa::path(post, path = "/api/v1/configuration-commands/{call_id}/retry-close", operation_id = "configuration.command.retryClose", params(("call_id" = String, Path)), request_body = EmptyRequest,
    responses(StudioApiErrors, (status = 200, body = FeedCloseReport)))]
pub(super) async fn retry_close(
    State(state): State<AppState>,
    Path(id): Path<String>,
    body: ApiJson<EmptyRequest>,
) -> Result<Json<FeedCloseReport>, ApiError> {
    close(State(state), Path(id), body).await
}

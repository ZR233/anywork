//! Official Feishu HTTP surfaces served on the loopback peer.

use std::collections::HashMap;

use axum::body::{Body, Bytes};
use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, Method, StatusCode, Uri};
use axum::response::{IntoResponse, Response};
use axum::{Form, Json};
use serde::Deserialize;
use serde_json::{Value, json};

use super::state::{InFlightGuard, app_id_ok, credentials_match, unix_millis};
use super::types::{
    CallKind, RegistrationBeginOptions, RegistrationPollScript, TENANT_ACCESS_TOKEN,
    TRUSTED_USER_OPEN_ID, TokenScript, WsDiscoveryScript,
};
use super::wire::{decode_addons, parse_form, validate_required_addons};

use super::guard::{HttpState, auth_ok, kind_blocked, record_reject};

pub(crate) async fn unexpected(
    State(state): State<HttpState>,
    method: Method,
    uri: Uri,
) -> Response {
    let diagnostic = format!("unregistered {} {}", method, uri.path());
    record_reject(
        &state.shared,
        method.as_str(),
        uri.path(),
        None,
        diagnostic.clone(),
    )
    .await;
    (
        StatusCode::NOT_FOUND,
        Json(json!({"code": 404, "msg": diagnostic})),
    )
        .into_response()
}

pub(crate) async fn registration(State(state): State<HttpState>, body: Bytes) -> Response {
    let form = parse_form(&body);
    let action = form.get("action").map(String::as_str).unwrap_or("");
    match action {
        "begin" => registration_begin(&state, &form).await,
        "poll" => registration_poll(&state, &form).await,
        _ => {
            record_reject(
                &state.shared,
                "POST",
                "/oauth/v1/app/registration",
                Some(CallKind::RegistrationBegin),
                format!("unknown action {action}"),
            )
            .await;
            json_error(StatusCode::BAD_REQUEST, "invalid_request", "unknown action")
        }
    }
}

async fn registration_begin(state: &HttpState, form: &HashMap<String, String>) -> Response {
    let path = "/oauth/v1/app/registration";
    if let Some(error) = validate_begin(form) {
        record_reject(
            &state.shared,
            "POST",
            path,
            Some(CallKind::RegistrationBegin),
            error.clone(),
        )
        .await;
        return json_error(StatusCode::BAD_REQUEST, "invalid_request", &error);
    }
    if let Some(reason) = kind_blocked(&state.shared, CallKind::RegistrationBegin).await {
        record_reject(
            &state.shared,
            "POST",
            path,
            Some(CallKind::RegistrationBegin),
            reason.clone(),
        )
        .await;
        return json_error(StatusCode::BAD_REQUEST, "invalid_request", &reason);
    }
    let (device, origin, begin, waiter, begin_in_flight) = {
        let mut inner = state.shared.lock().await;
        inner.registration.generation += 1;
        let device = format!("dc_anywork_{}", inner.registration.generation);
        inner.registration.device_code = Some(device.clone());
        inner.record("POST", path, Some(CallKind::RegistrationBegin), true, None);
        let in_flight = InFlightGuard::enter(&inner.registration.begin_in_flight);
        (
            device,
            inner.origin.clone(),
            inner.registration.begin_options.clone(),
            inner.registration.begin_hang.waiter(),
            in_flight,
        )
    };
    waiter.wait(&state.cancel).await;
    let response = Json(begin_response(&origin, &device, &begin)).into_response();
    let _ = begin_in_flight.current();
    response
}

fn begin_response(
    origin: &str,
    device: &str,
    begin: &RegistrationBeginOptions,
) -> serde_json::Value {
    let complete = begin
        .verification_url
        .clone()
        .unwrap_or_else(|| format!("{origin}/verify?user_code=ANYWORK"));
    json!({
        "device_code": device,
        "verification_uri": format!("{origin}/verify"),
        "verification_uri_complete": complete,
        "user_code": "ANYWORK",
        "interval": begin.interval_seconds,
        "expires_in": begin.expires_in_seconds
    })
}

fn validate_begin(form: &HashMap<String, String>) -> Option<String> {
    if form.get("archetype").map(String::as_str) != Some("PersonalAgent") {
        return Some("archetype must be PersonalAgent".into());
    }
    if form.get("auth_method").map(String::as_str) != Some("client_secret") {
        return Some("auth_method must be client_secret".into());
    }
    if form.get("request_user_info").map(String::as_str) != Some("open_id") {
        return Some("request_user_info must be open_id".into());
    }
    // Official begin does not carry addons; they ride the verification URL.
    // If a client does send them on the form, decode and reject malformed payloads.
    if let Some(encoded) = form.get("addons") {
        return match decode_addons(encoded) {
            Ok(addons) => validate_required_addons(&addons)
                .err()
                .map(|error| error.to_string()),
            Err(error) => Some(error.to_string()),
        };
    }
    None
}

async fn registration_poll(state: &HttpState, form: &HashMap<String, String>) -> Response {
    let path = "/oauth/v1/app/registration";
    let device = form.get("device_code").cloned().unwrap_or_default();
    if device.is_empty() {
        record_reject(
            &state.shared,
            "POST",
            path,
            Some(CallKind::RegistrationPoll),
            "missing device_code".into(),
        )
        .await;
        return json_error(
            StatusCode::BAD_REQUEST,
            "invalid_request",
            "missing device_code",
        );
    }
    if let Some(reason) = kind_blocked(&state.shared, CallKind::RegistrationPoll).await {
        record_reject(
            &state.shared,
            "POST",
            path,
            Some(CallKind::RegistrationPoll),
            reason.clone(),
        )
        .await;
        return json_error(StatusCode::BAD_REQUEST, "invalid_request", &reason);
    }
    let (script, generation, waiter) = {
        let mut inner = state.shared.lock().await;
        let generation = inner.registration.generation;
        let expected = inner.registration.device_code.clone();
        if expected.as_deref() != Some(device.as_str()) {
            inner.record(
                "POST",
                path,
                Some(CallKind::RegistrationPoll),
                false,
                Some("device_code mismatch".into()),
            );
            return json_error(
                StatusCode::BAD_REQUEST,
                "invalid_request",
                "device_code mismatch",
            );
        }
        let script = inner
            .registration
            .script
            .front()
            .cloned()
            .unwrap_or(RegistrationPollScript::Pending);
        let waiter = inner.registration.hang.waiter();
        (script, generation, waiter)
    };
    let poll_in_flight = if matches!(script, RegistrationPollScript::Hang) {
        let in_flight = {
            let inner = state.shared.lock().await;
            InFlightGuard::enter(&inner.registration.poll_in_flight)
        };
        waiter.wait(&state.cancel).await;
        Some(in_flight)
    } else {
        None
    };
    let mut inner = state.shared.lock().await;
    let cancelled = inner.registration.cancelled.contains(&generation);
    let script = inner.next_poll_script();
    inner.polls.push(super::types::PollObservation {
        generation,
        unix_millis: unix_millis(),
        script: script.clone(),
        generation_cancelled: cancelled,
    });
    inner.record("POST", path, Some(CallKind::RegistrationPoll), true, None);
    let response = match script {
        RegistrationPollScript::Pending | RegistrationPollScript::Hang => json_error(
            StatusCode::BAD_REQUEST,
            "authorization_pending",
            "authorization pending",
        ),
        RegistrationPollScript::SlowDown => {
            json_error(StatusCode::BAD_REQUEST, "slow_down", "slow down")
        }
        RegistrationPollScript::Denied => Json(json!({
            "error": "access_denied",
            "error_description": "denied"
        }))
        .into_response(),
        RegistrationPollScript::Expired => Json(json!({
            "error": "expired_token",
            "error_description": "expired"
        }))
        .into_response(),
        RegistrationPollScript::Cancelled => Json(json!({
            "error": "access_denied",
            "error_description": "cancelled"
        }))
        .into_response(),
        RegistrationPollScript::Completed { include_open_id } => {
            let mut body = json!({
                "client_id": inner.options.registered_app_id,
                "client_secret": inner.options.registered_app_secret,
            });
            let brand = inner.registration.tenant_brand;
            if include_open_id {
                let mut user_info = json!({
                    "open_id": TRUSTED_USER_OPEN_ID,
                });
                user_info["tenant_brand"] = json!(brand.map_or("feishu", |value| value.as_wire()));
                body["user_info"] = user_info;
            } else if let Some(brand) = brand {
                body["user_info"] = json!({
                    "tenant_brand": brand.as_wire(),
                });
            }
            Json(body).into_response()
        }
    };
    let _ = poll_in_flight.as_ref().map(InFlightGuard::current);
    response
}

#[derive(Deserialize)]
pub(crate) struct TokenBody {
    grant_type: String,
    client_id: String,
    client_secret: String,
}

pub(crate) async fn tenant_token(
    State(state): State<HttpState>,
    Form(body): Form<TokenBody>,
) -> Response {
    let path = "/oauth/v3/token";
    if body.grant_type != "client_credentials" {
        record_reject(
            &state.shared,
            "POST",
            path,
            Some(CallKind::TenantToken),
            "grant_type rejected".into(),
        )
        .await;
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({"code": 20036, "error": "unsupported_grant_type"})),
        )
            .into_response();
    }
    if !app_id_ok(&body.client_id) {
        record_reject(
            &state.shared,
            "POST",
            path,
            Some(CallKind::TenantToken),
            "client_id prefix rejected".into(),
        )
        .await;
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({"code": 20048, "error": "invalid_client"})),
        )
            .into_response();
    }
    if let Some(reason) = kind_blocked(&state.shared, CallKind::TenantToken).await {
        record_reject(
            &state.shared,
            "POST",
            path,
            Some(CallKind::TenantToken),
            reason.clone(),
        )
        .await;
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({"code": 20130, "error": "invalid_client"})),
        )
            .into_response();
    }
    let (ok, script, waiter) = {
        let mut inner = state.shared.lock().await;
        let ok = credentials_match(&inner, &body.client_id, &body.client_secret);
        inner.token.in_flight += 1;
        inner.token.max_in_flight = inner.token.max_in_flight.max(inner.token.in_flight);
        inner.token.calls += 1;
        (ok, inner.token.script.clone(), inner.token.hang.waiter())
    };
    if matches!(script, TokenScript::Hang) {
        waiter.wait(&state.cancel).await;
    }
    let mut inner = state.shared.lock().await;
    inner.token.in_flight = inner.token.in_flight.saturating_sub(1);
    if !ok {
        inner.record(
            "POST",
            path,
            Some(CallKind::TenantToken),
            false,
            Some("client_id/client_secret mismatch".into()),
        );
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({"code": 20002, "error": "invalid_client"})),
        )
            .into_response();
    }
    inner.record("POST", path, Some(CallKind::TenantToken), true, None);
    let script = inner.token.script.clone();
    match script {
        TokenScript::Success { expire_seconds } => Json(json!({
            "code": 0,
            "access_token": TENANT_ACCESS_TOKEN,
            "expires_in": expire_seconds,
            "token_type": "Bearer"
        }))
        .into_response(),
        TokenScript::Hang => Json(json!({
            "code": 0,
            "access_token": TENANT_ACCESS_TOKEN,
            "expires_in": 7200,
            "token_type": "Bearer"
        }))
        .into_response(),
        TokenScript::AuthError => (
            StatusCode::BAD_REQUEST,
            Json(json!({"code": 20002, "error": "invalid_client"})),
        )
            .into_response(),
        TokenScript::PermissionError => (
            StatusCode::BAD_REQUEST,
            Json(json!({"code": 20069, "error": "invalid_client"})),
        )
            .into_response(),
        TokenScript::RateLimited => (
            StatusCode::TOO_MANY_REQUESTS,
            Json(json!({"error": "rate_limit_exceeded"})),
        )
            .into_response(),
        TokenScript::HttpError { status } => (
            StatusCode::from_u16(status).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR),
            Json(if status == 500 {
                json!({"code": 20050, "error": "server_error"})
            } else {
                json!({"error": "http_failure"})
            }),
        )
            .into_response(),
    }
}

pub(crate) async fn bot_info(State(state): State<HttpState>, headers: HeaderMap) -> Response {
    let path = "/open-apis/bot/v3/info";
    if !auth_ok(
        &state.shared,
        headers.get(axum::http::header::AUTHORIZATION),
    )
    .await
    {
        record_reject(
            &state.shared,
            "GET",
            path,
            Some(CallKind::BotInfo),
            "missing or invalid bearer".into(),
        )
        .await;
        return Json(json!({"code": 99991663, "msg": "unauthorized"})).into_response();
    }
    if let Some(reason) = kind_blocked(&state.shared, CallKind::BotInfo).await {
        record_reject(
            &state.shared,
            "GET",
            path,
            Some(CallKind::BotInfo),
            reason.clone(),
        )
        .await;
        return Json(json!({"code": 99991672, "msg": reason})).into_response();
    }
    let mut inner = state.shared.lock().await;
    inner.record("GET", path, Some(CallKind::BotInfo), true, None);
    Json(json!({
        "code": 0,
        "msg": "ok",
        "bot": {
            "activate_status": 2,
            "app_name": "anywork-fixture-bot",
            "avatar_url": "http://127.0.0.1/avatar.png",
            "ip_white_list": [],
            "open_id": inner.options.bot_open_id
        }
    }))
    .into_response()
}

#[derive(Deserialize)]
pub(crate) struct WsEndpointBody {
    #[serde(rename = "AppID")]
    app_id: String,
    #[serde(rename = "AppSecret")]
    app_secret: String,
}

pub(crate) async fn ws_endpoint(
    State(state): State<HttpState>,
    Json(body): Json<WsEndpointBody>,
) -> Response {
    let path = "/callback/ws/endpoint";
    if !app_id_ok(&body.app_id) {
        record_reject(
            &state.shared,
            "POST",
            path,
            Some(CallKind::WsEndpoint),
            "AppID prefix rejected".into(),
        )
        .await;
        return Json(json!({"code": 514, "msg": "auth failed"})).into_response();
    }
    if let Some(reason) = kind_blocked(&state.shared, CallKind::WsEndpoint).await {
        record_reject(
            &state.shared,
            "POST",
            path,
            Some(CallKind::WsEndpoint),
            reason.clone(),
        )
        .await;
        return Json(json!({"code": 403, "msg": reason})).into_response();
    }
    let mut inner = state.shared.lock().await;
    if !credentials_match(&inner, &body.app_id, &body.app_secret) {
        inner.record(
            "POST",
            path,
            Some(CallKind::WsEndpoint),
            false,
            Some("AppID/AppSecret mismatch".into()),
        );
        return Json(json!({"code": 514, "msg": "auth failed"})).into_response();
    }
    match inner.ws.discovery {
        WsDiscoveryScript::AuthFailed => {
            inner.record(
                "POST",
                path,
                Some(CallKind::WsEndpoint),
                true,
                Some("scripted auth failed".into()),
            );
            Json(json!({"code": 514, "msg": "auth failed"})).into_response()
        }
        WsDiscoveryScript::Forbidden => {
            inner.record(
                "POST",
                path,
                Some(CallKind::WsEndpoint),
                true,
                Some("scripted forbidden".into()),
            );
            Json(json!({"code": 403, "msg": "forbidden"})).into_response()
        }
        WsDiscoveryScript::Success => {
            inner.record("POST", path, Some(CallKind::WsEndpoint), true, None);
            let url = format!(
                "{}/callback/ws/connect?device_id=anywork&service_id=1",
                inner.ws_origin
            );
            Json(json!({
                "code": 0,
                "msg": "ok",
                "data": {
                    "URL": url,
                    "ClientConfig": inner.ws.client_config
                }
            }))
            .into_response()
        }
    }
}

#[derive(Deserialize)]
pub(crate) struct ChatListQuery {
    pub page_size: Option<u32>,
    pub page_token: Option<String>,
    pub user_id_type: Option<String>,
}

pub(crate) async fn chat_list(
    State(state): State<HttpState>,
    headers: HeaderMap,
    Query(query): Query<ChatListQuery>,
) -> Response {
    let path = "/open-apis/im/v1/chats";
    if !auth_ok(
        &state.shared,
        headers.get(axum::http::header::AUTHORIZATION),
    )
    .await
    {
        record_reject(
            &state.shared,
            "GET",
            path,
            Some(CallKind::ChatList),
            "unauthorized".into(),
        )
        .await;
        return Json(json!({"code": 99991663, "msg": "unauthorized"})).into_response();
    }
    if let Some(reason) = kind_blocked(&state.shared, CallKind::ChatList).await {
        record_reject(
            &state.shared,
            "GET",
            path,
            Some(CallKind::ChatList),
            reason.clone(),
        )
        .await;
        return Json(json!({"code": 99991672, "msg": reason})).into_response();
    }
    // The accepted record and the generation waiter share one linearization
    // point, so the operator can observe `ChatList` accepted and then release
    // this request. The catalog is the snapshot of that point, and the guard
    // is dropped before waiting: hanging here must not block control calls,
    // reports or shutdown.
    let (waiter, catalog) = {
        let mut inner = state.shared.lock().await;
        let page_size = query.page_size.unwrap_or(20).clamp(1, 100) as usize;
        let start = match parse_page_token(query.page_token.as_deref()) {
            Ok(start) => start,
            Err(reason) => {
                inner.record(
                    "GET",
                    path,
                    Some(CallKind::ChatList),
                    false,
                    Some(reason.clone()),
                );
                if let Some(last) = inner.calls.last_mut() {
                    last.owned_reject = true;
                }
                return Json(json!({"code": 232001, "msg": reason})).into_response();
            }
        };
        inner.record("GET", path, Some(CallKind::ChatList), true, None);
        let waiter = inner.im.chat_list_hang.waiter();
        let groups = &inner.im.groups;
        let end = (start + page_size).min(groups.len());
        let items: Vec<Value> = groups[start.min(groups.len())..end]
            .iter()
            .map(|group| {
                json!({
                    "chat_id": group.chat_id,
                    "name": group.name,
                    "description": "fixture group",
                    "owner_id": TRUSTED_USER_OPEN_ID,
                    "owner_id_type": query.user_id_type.as_deref().unwrap_or("open_id"),
                    "external": false,
                    "tenant_key": "anywork_fixture_tenant",
                    "chat_status": "normal"
                })
            })
            .collect();
        let has_more = end < groups.len();
        let catalog = Json(json!({
            "code": 0,
            "msg": "success",
            "data": {
                "items": items,
                "page_token": if has_more { Some(end.to_string()) } else { None::<String> },
                "has_more": has_more
            }
        }))
        .into_response();
        (waiter, catalog)
    };
    waiter.wait(&state.cancel).await;
    if state.cancel.is_cancelled() {
        // Peer shutdown ends the wait; a cancelled request never answers with
        // an already-computed catalog.
        return Response::new(Body::empty());
    }
    catalog
}

pub(crate) async fn chat_get(
    State(state): State<HttpState>,
    headers: HeaderMap,
    Path(chat_id): Path<String>,
) -> Response {
    let path = format!("/open-apis/im/v1/chats/{chat_id}");
    if !auth_ok(
        &state.shared,
        headers.get(axum::http::header::AUTHORIZATION),
    )
    .await
    {
        record_reject(
            &state.shared,
            "GET",
            &path,
            Some(CallKind::ChatGet),
            "unauthorized".into(),
        )
        .await;
        return Json(json!({"code": 99991663, "msg": "unauthorized"})).into_response();
    }
    if let Some(reason) = kind_blocked(&state.shared, CallKind::ChatGet).await {
        record_reject(
            &state.shared,
            "GET",
            &path,
            Some(CallKind::ChatGet),
            reason.clone(),
        )
        .await;
        return Json(json!({"code": 99991672, "msg": reason})).into_response();
    }
    let mut inner = state.shared.lock().await;
    let Some(group) = inner.group(&chat_id).cloned() else {
        inner.record(
            "GET",
            &path,
            Some(CallKind::ChatGet),
            false,
            Some("unknown chat".into()),
        );
        return Json(json!({"code": 232006, "msg": "invalid chat_id"})).into_response();
    };
    inner.record("GET", &path, Some(CallKind::ChatGet), true, None);
    Json(json!({
        "code": 0,
        "msg": "success",
        "data": {
            "avatar": "http://127.0.0.1/avatar.png",
            "name": group.name,
            "description": "fixture group",
            "chat_mode": "group",
            "chat_type": "private",
            "user_count": group.member_open_ids.len().to_string(),
            "bot_count": "1",
            "external": false,
            "tenant_key": "anywork_fixture_tenant"
        }
    }))
    .into_response()
}

#[derive(Deserialize)]
pub(crate) struct MembersQuery {
    pub member_id_type: Option<String>,
    pub page_size: Option<u32>,
    pub page_token: Option<String>,
}

pub(crate) async fn chat_members(
    State(state): State<HttpState>,
    headers: HeaderMap,
    Path(chat_id): Path<String>,
    Query(query): Query<MembersQuery>,
) -> Response {
    let path = format!("/open-apis/im/v1/chats/{chat_id}/members");
    if !auth_ok(
        &state.shared,
        headers.get(axum::http::header::AUTHORIZATION),
    )
    .await
    {
        record_reject(
            &state.shared,
            "GET",
            &path,
            Some(CallKind::ChatMembers),
            "unauthorized".into(),
        )
        .await;
        return Json(json!({"code": 99991663, "msg": "unauthorized"})).into_response();
    }
    if let Some(reason) = kind_blocked(&state.shared, CallKind::ChatMembers).await {
        record_reject(
            &state.shared,
            "GET",
            &path,
            Some(CallKind::ChatMembers),
            reason.clone(),
        )
        .await;
        return Json(json!({"code": 99991672, "msg": reason})).into_response();
    }
    let mut inner = state.shared.lock().await;
    let Some(group) = inner.group(&chat_id).cloned() else {
        inner.record(
            "GET",
            &path,
            Some(CallKind::ChatMembers),
            false,
            Some("unknown chat".into()),
        );
        return Json(json!({"code": 232006, "msg": "invalid chat_id"})).into_response();
    };
    inner.record("GET", &path, Some(CallKind::ChatMembers), true, None);
    let id_type = query.member_id_type.unwrap_or_else(|| "open_id".into());
    let _ = query.page_size;
    let items: Vec<Value> = group
        .member_open_ids
        .iter()
        .filter(|id| *id != &inner.options.bot_open_id)
        .map(|id| {
            json!({
                "member_id_type": id_type,
                "member_id": id,
                "name": "fixture-user",
                "tenant_key": "anywork_fixture_tenant"
            })
        })
        .collect();
    Json(json!({
        "code": 0,
        "msg": "success",
        "data": {
            "items": items,
            "page_token": query.page_token,
            "has_more": false,
            "member_total": items.len()
        }
    }))
    .into_response()
}

fn json_error(status: StatusCode, error: &str, description: &str) -> Response {
    (
        status,
        Json(json!({"error": error, "error_description": description})),
    )
        .into_response()
}

pub(crate) fn parse_page_token(token: Option<&str>) -> Result<usize, String> {
    match token {
        None | Some("") => Ok(0),
        Some(value) => value
            .parse::<usize>()
            .map_err(|_| format!("invalid page_token {value}")),
    }
}

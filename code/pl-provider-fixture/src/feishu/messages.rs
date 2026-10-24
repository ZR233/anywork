//! Message history, exact send-wire validation and platform message facts.

use axum::Json;
use axum::body::{Body, Bytes};
use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use serde::Deserialize;
use serde_json::{Value, json};

use super::http::{HttpState, auth_ok, kind_blocked, parse_page_token, record_reject};
use super::media::{ResourceOrigin, ResourceSummary};
use super::state::{Inner, unix_millis};
use super::types::{
    CallKind, HistoryMessage, MessageContentObservation, MessageSendObservation,
    MessageSendOutcome, PostContent, PostElement, REGISTERED_APP_ID, ReceivedPost, SendDisposition,
};

const MAX_MESSAGE_REQUESTS: usize = 512;
const MAX_SEND_BODY_BYTES: usize = 30_000;

#[derive(Deserialize)]
pub(crate) struct MessageListQuery {
    pub container_id_type: Option<String>,
    pub container_id: Option<String>,
    pub start_time: Option<String>,
    pub end_time: Option<String>,
    pub page_size: Option<u32>,
    pub page_token: Option<String>,
    pub sort_type: Option<String>,
}

pub(crate) async fn message_list(
    State(state): State<HttpState>,
    headers: HeaderMap,
    Query(query): Query<MessageListQuery>,
) -> Response {
    let path = "/open-apis/im/v1/messages";
    if !admit_message_request(&state).await {
        return message_limit();
    }
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
            Some(CallKind::MessageList),
            "unauthorized".into(),
        )
        .await;
        return Json(json!({"code": 99991663, "msg": "unauthorized"})).into_response();
    }
    if query.container_id_type.as_deref() != Some("chat") {
        record_reject(
            &state.shared,
            "GET",
            path,
            Some(CallKind::MessageList),
            "container_id_type must be chat".into(),
        )
        .await;
        return Json(json!({"code": 232001, "msg": "invalid container_id_type"})).into_response();
    }
    let Some(chat_id) = query.container_id.clone() else {
        record_reject(
            &state.shared,
            "GET",
            path,
            Some(CallKind::MessageList),
            "missing container_id".into(),
        )
        .await;
        return Json(json!({"code": 232001, "msg": "missing container_id"})).into_response();
    };
    if let Some(reason) = kind_blocked(&state.shared, CallKind::MessageList).await {
        record_reject(
            &state.shared,
            "GET",
            path,
            Some(CallKind::MessageList),
            reason.clone(),
        )
        .await;
        return Json(json!({"code": 99991672, "msg": reason})).into_response();
    }
    let mut inner = state.shared.lock().await;
    if !inner.is_known_chat(&chat_id) {
        inner.record(
            "GET",
            path,
            Some(CallKind::MessageList),
            false,
            Some("unknown chat".into()),
        );
        return Json(json!({"code": 232006, "msg": "invalid chat_id"})).into_response();
    }
    if inner
        .group(&chat_id)
        .is_some_and(|group| !group.history_allowed)
    {
        inner.record("GET", path, Some(CallKind::MessageList), true, None);
        return (
            StatusCode::BAD_REQUEST,
            Json(json!({
                "code": 230027,
                "msg": "no permission to get history"
            })),
        )
            .into_response();
    }
    inner.record("GET", path, Some(CallKind::MessageList), true, None);
    let page_size = query.page_size.unwrap_or(20).clamp(1, 50) as usize;
    let mut items: Vec<Value> = inner
        .im
        .history
        .iter()
        .filter(|item| item.chat_id == chat_id)
        .filter(|item| {
            time_in_range(
                &item.create_time_ms,
                query.start_time.as_deref(),
                query.end_time.as_deref(),
            )
        })
        .map(history_json)
        .collect();
    if query.sort_type.as_deref() == Some("ByCreateTimeDesc") {
        items.reverse();
    }
    let start = match parse_page_token(query.page_token.as_deref()) {
        Ok(start) => start,
        Err(reason) => {
            if let Some(last) = inner.calls.last_mut() {
                last.accepted = false;
                last.diagnostic = Some(reason.clone());
                last.owned_reject = true;
            }
            return Json(json!({"code": 232001, "msg": reason})).into_response();
        }
    };
    let end = (start + page_size).min(items.len());
    let page = items.get(start..end).unwrap_or(&[]).to_vec();
    let has_more = end < items.len();
    Json(json!({
        "code": 0,
        "msg": "success",
        "data": {
            "has_more": has_more,
            "page_token": if has_more { Some(end.to_string()) } else { None::<String> },
            "items": page
        }
    }))
    .into_response()
}

fn time_in_range(create_ms: &str, start: Option<&str>, end: Option<&str>) -> bool {
    let Ok(ms) = create_ms.parse::<u64>() else {
        return true;
    };
    let seconds = ms / 1000;
    if let Some(start) = start.and_then(|value| value.parse::<u64>().ok())
        && seconds < start
    {
        return false;
    }
    if let Some(end) = end.and_then(|value| value.parse::<u64>().ok())
        && seconds > end
    {
        return false;
    }
    true
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct SendQuery {
    pub receive_id_type: Option<String>,
}

#[derive(Deserialize, serde::Serialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct SendBody {
    pub receive_id: String,
    pub msg_type: String,
    pub content: String,
    pub uuid: Option<String>,
}

pub(crate) async fn message_send(
    State(state): State<HttpState>,
    headers: HeaderMap,
    Query(query): Query<SendQuery>,
    bytes: Bytes,
) -> Response {
    let path = "/open-apis/im/v1/messages";
    if !admit_message_request(&state).await {
        return message_limit();
    }
    if !auth_ok(
        &state.shared,
        headers.get(axum::http::header::AUTHORIZATION),
    )
    .await
    {
        record_reject(
            &state.shared,
            "POST",
            path,
            Some(CallKind::MessageSend),
            "unauthorized".into(),
        )
        .await;
        return Json(json!({"code": 99991663, "msg": "unauthorized"})).into_response();
    }
    // The complete encoded request is budgeted, including escaping, locale
    // wrapper, target and uuid. A decoded Markdown character count is not enough.
    if bytes.len() > MAX_SEND_BODY_BYTES {
        record_reject(
            &state.shared,
            "POST",
            path,
            Some(CallKind::MessageSend),
            "encoded message body exceeds 30000 bytes".into(),
        )
        .await;
        return Json(json!({"code": 230025, "msg": "message body too long"})).into_response();
    }
    let body: SendBody = match serde_json::from_slice(&bytes) {
        Ok(body) => body,
        Err(_) => {
            record_reject(
                &state.shared,
                "POST",
                path,
                Some(CallKind::MessageSend),
                "invalid message body shape".into(),
            )
            .await;
            return Json(json!({"code": 232001, "msg": "invalid message body shape"}))
                .into_response();
        }
    };
    if !headers
        .get(axum::http::header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| {
            value
                .split(';')
                .next()
                .is_some_and(|mime| mime.trim().eq_ignore_ascii_case("application/json"))
        })
    {
        record_reject(
            &state.shared,
            "POST",
            path,
            Some(CallKind::MessageSend),
            "content type must be application/json".into(),
        )
        .await;
        return Json(json!({"code": 232001, "msg": "content type must be application/json"}))
            .into_response();
    }
    if query.receive_id_type.as_deref() != Some("chat_id") {
        record_reject(
            &state.shared,
            "POST",
            path,
            Some(CallKind::MessageSend),
            "receive_id_type must be chat_id".into(),
        )
        .await;
        return Json(json!({"code": 232001, "msg": "receive_id_type must be chat_id"}))
            .into_response();
    }
    if let Some(uuid) = &body.uuid
        && uuid.chars().count() > 50
    {
        record_reject(
            &state.shared,
            "POST",
            path,
            Some(CallKind::MessageSend),
            "uuid longer than 50".into(),
        )
        .await;
        return Json(json!({"code": 232001, "msg": "uuid too long"})).into_response();
    }
    if let Some(reason) = kind_blocked(&state.shared, CallKind::MessageSend).await {
        record_reject(
            &state.shared,
            "POST",
            path,
            Some(CallKind::MessageSend),
            reason.clone(),
        )
        .await;
        return Json(json!({"code": 99991672, "msg": reason})).into_response();
    }
    let (disposition, assigned, observation, waiter) = {
        let mut inner = state.shared.lock().await;
        if !inner.is_known_chat(&body.receive_id) {
            inner.record(
                "POST",
                path,
                Some(CallKind::MessageSend),
                false,
                Some("unknown receive_id".into()),
            );
            return Json(json!({"code": 232006, "msg": "invalid receive_id"})).into_response();
        }
        let content = match validate_content(&body, &inner) {
            Ok(content) => content,
            Err(reason) => {
                inner.record(
                    "POST",
                    path,
                    Some(CallKind::MessageSend),
                    false,
                    Some(reason.into()),
                );
                return Json(json!({"code": 232001, "msg": reason})).into_response();
            }
        };
        if inner.closing {
            return message_limit();
        }
        inner.im.send_seq += 1;
        let assigned = format!("om_anywork_send_{}", inner.im.send_seq);
        // A step belongs to the request at entry, not whichever request happens
        // to finish first after a hang. uuid stays a wire fact, not fake dedup.
        let disposition = inner.next_send();
        let raw = match serde_json::to_value(&body) {
            Ok(raw) => raw,
            Err(_) => {
                return Json(json!({"code": 500, "msg": "message encoding failed"}))
                    .into_response();
            }
        };
        let call_index = inner.calls.len();
        inner.record("POST", path, Some(CallKind::MessageSend), true, None);
        if let Some(last) = inner.calls.last_mut() {
            last.send_body = Some(raw);
            last.assigned_message_id = Some(assigned.clone());
            last.uuid = body.uuid.clone();
        }
        let observation = inner.im.sends.len();
        inner.im.sends.push(MessageSendObservation {
            call_index,
            request_body_bytes: bytes.len(),
            receive_id: body.receive_id.clone(),
            uuid: body.uuid.clone(),
            message_id: assigned.clone(),
            content,
            disposition: disposition.clone(),
            outcome: MessageSendOutcome::Waiting,
        });
        (disposition, assigned, observation, inner.im.hang.waiter())
    };
    if matches!(disposition, SendDisposition::Hang) {
        waiter.wait(&state.cancel).await;
    }
    let stored = {
        let mut inner = state.shared.lock().await;
        if inner.closing || state.cancel.is_cancelled() {
            inner.im.sends[observation].outcome = MessageSendOutcome::Cancelled;
            return Response::new(Body::empty());
        }
        if let SendDisposition::Reject { code, msg } = &disposition {
            inner.im.sends[observation].outcome = MessageSendOutcome::Rejected;
            return Json(json!({"code": code, "msg": msg})).into_response();
        }
        if let MessageContentObservation::File(resource) = &inner.im.sends[observation].content {
            let key = resource.file_key.clone();
            if let Some(resource) = inner.media.resources.get_mut(&key) {
                resource.messages.insert(assigned.clone());
            }
        }
        let stored = HistoryMessage {
            message_id: assigned.clone(),
            chat_id: body.receive_id.clone(),
            msg_type: body.msg_type.clone(),
            content: received_content(&inner.im.sends[observation].content),
            create_time_ms: unix_millis().to_string(),
            sender_id: REGISTERED_APP_ID.into(),
            sender_type: "app".into(),
            sender_id_type: "app_id".into(),
        };
        inner.im.history.push(stored.clone());
        inner.im.sends[observation].outcome =
            if matches!(disposition, SendDisposition::AcceptThenDrop) {
                MessageSendOutcome::StoredResponseDropped
            } else {
                MessageSendOutcome::Stored
            };
        stored
    };
    match disposition {
        SendDisposition::Hang | SendDisposition::Succeed => {
            Json(json!({"code": 0, "msg": "success", "data": history_json(&stored)}))
                .into_response()
        }
        SendDisposition::Reject { code, msg } => {
            Json(json!({"code": code, "msg": msg})).into_response()
        }
        SendDisposition::AcceptThenDrop => {
            state.cancel.cancelled().await;
            Response::new(Body::empty())
        }
    }
}

fn received_content(content: &MessageContentObservation) -> String {
    match content {
        MessageContentObservation::Text { text } => json!({"text": text}).to_string(),
        MessageContentObservation::File(resource) => {
            json!({"file_key": resource.file_key, "file_name": resource.file_name}).to_string()
        }
        MessageContentObservation::Post(post) => {
            // No Markdown renderer/AST belongs in a protocol peer. Keep the
            // original paragraphs in the official content_v2 field; the legacy
            // sample is plain text and makes no platform-layout claim.
            let legacy = post
                .zh_cn
                .content
                .iter()
                .map(|row| {
                    row.iter()
                        .map(|element| match element {
                            PostElement::Markdown { text } => {
                                PostElement::Text { text: text.clone() }
                            }
                            other => other.clone(),
                        })
                        .collect()
                })
                .collect();
            json!(ReceivedPost {
                title: post.zh_cn.title.clone().unwrap_or_default(),
                content: legacy,
                content_v2: Some(post.zh_cn.content.clone()),
            })
            .to_string()
        }
    }
}

fn history_json(message: &HistoryMessage) -> Value {
    json!({
            "message_id": message.message_id,
            "root_id": "",
            "parent_id": "",
            "msg_type": message.msg_type,
            "create_time": message.create_time_ms,
            "update_time": message.create_time_ms,
            "deleted": false,
            "updated": false,
            "chat_id": message.chat_id,
            "sender": {
                "id": message.sender_id,
                "id_type": message.sender_id_type,
                "sender_type": message.sender_type,
                "tenant_key": "anywork_fixture_tenant"
            },
            "body": { "content": message.content }
    })
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct TextContent {
    text: String,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct FileContent {
    file_key: String,
}

fn validate_content(
    body: &SendBody,
    inner: &Inner,
) -> Result<MessageContentObservation, &'static str> {
    match body.msg_type.as_str() {
        "text" => {
            let content: TextContent =
                serde_json::from_str(&body.content).map_err(|_| "invalid text content")?;
            if content.text.is_empty() {
                return Err("empty text");
            }
            Ok(MessageContentObservation::Text { text: content.text })
        }
        "post" => {
            let content: PostContent =
                serde_json::from_str(&body.content).map_err(|_| "invalid post content")?;
            if content.zh_cn.content.is_empty() || content.zh_cn.content.iter().any(Vec::is_empty) {
                return Err("empty post content");
            }
            if content.zh_cn.content.iter().any(|row| {
                row.len() != 1
                    && row
                        .iter()
                        .any(|element| matches!(element, PostElement::Markdown { .. }))
            }) {
                return Err("md must occupy its own paragraph");
            }
            for element in content.zh_cn.content.iter().flatten() {
                match element {
                    PostElement::Markdown { text } | PostElement::Text { text }
                        if !text.is_empty() => {}
                    _ => return Err("send post sample requires nonempty md/text blocks"),
                }
            }
            Ok(MessageContentObservation::Post(content))
        }
        "file" => {
            let content: FileContent =
                serde_json::from_str(&body.content).map_err(|_| "invalid file content")?;
            let resource: &ResourceSummary = &inner
                .media
                .resources
                .get(&content.file_key)
                .filter(|resource| matches!(resource.summary.origin, ResourceOrigin::Upload { .. }))
                .ok_or("file_key must refer to a successful upload by this peer")?
                .summary;
            Ok(MessageContentObservation::File(resource.clone()))
        }
        _ => Err("unsupported send msg_type"),
    }
}

pub(crate) async fn message_read(
    State(state): State<HttpState>,
    headers: HeaderMap,
    Path(message_id): Path<String>,
) -> Response {
    if !admit_message_request(&state).await {
        return message_limit();
    }
    let path = "/open-apis/im/v1/messages/{message_id}";
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
            Some(CallKind::MessageRead),
            "unauthorized".into(),
        )
        .await;
        return Json(json!({"code": 99991663, "msg": "unauthorized"})).into_response();
    }
    let mut inner = state.shared.lock().await;
    if let Some(reason) = inner.kind_forbidden_or_excess(CallKind::MessageRead) {
        inner.record(
            "GET",
            path,
            Some(CallKind::MessageRead),
            false,
            Some(reason),
        );
        return Json(json!({"code": 99991672, "msg": "forbidden read"})).into_response();
    }
    let message = inner
        .im
        .history
        .iter()
        .find(|item| item.message_id == message_id)
        .cloned();
    match message {
        Some(message) => {
            if inner
                .group(&message.chat_id)
                .is_some_and(|group| !group.history_allowed)
            {
                inner.record("GET", path, Some(CallKind::MessageRead), true, None);
                return Json(json!({"code": 230027, "msg": "no permission to get history"}))
                    .into_response();
            }
            inner.record("GET", path, Some(CallKind::MessageRead), true, None);
            Json(json!({"code": 0, "msg": "success", "data": {"items": [history_json(&message)]}}))
                .into_response()
        }
        None => {
            inner.record(
                "GET",
                path,
                Some(CallKind::MessageRead),
                false,
                Some("unknown message id".into()),
            );
            Json(json!({"code": 230001, "msg": "message not found"})).into_response()
        }
    }
}

async fn admit_message_request(state: &HttpState) -> bool {
    let mut inner = state.shared.lock().await;
    if inner.closing || inner.im.request_count >= MAX_MESSAGE_REQUESTS {
        return false;
    }
    inner.im.request_count += 1;
    true
}

fn message_limit() -> Response {
    (
        StatusCode::SERVICE_UNAVAILABLE,
        Json(json!({"code": 99991400, "msg": "peer message request limit or shutdown"})),
    )
        .into_response()
}

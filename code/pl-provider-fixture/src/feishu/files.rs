//! The peer validates real multipart wire fields and requires a previously uploaded key.

use super::{
    guard::{HttpState, headers_authorized, kind_blocked, record_reject},
    http::{SendBody, send_ok},
    types::{CallKind, SendDisposition},
};
use axum::{
    Json,
    body::Body,
    extract::{Multipart, State},
    http::{HeaderMap, Uri},
    response::{IntoResponse, Response},
};
use serde_json::json;
use sha2::{Digest, Sha256};

pub(crate) async fn upload(
    State(state): State<HttpState>,
    uri: Uri,
    headers: HeaderMap,
    mut multipart: Multipart,
) -> Response {
    let image = uri.path().ends_with("/images");
    let kind = if image {
        CallKind::ImageUpload
    } else {
        CallKind::FileUpload
    };
    if !headers_authorized(&state, &headers).await {
        record_reject(
            &state.shared,
            "POST",
            uri.path(),
            Some(kind),
            "unauthorized upload".into(),
        )
        .await;
        return Json(json!({"code":234002,"msg":"unauthorized"})).into_response();
    }
    if let Some(reason) = kind_blocked(&state.shared, kind).await {
        record_reject(
            &state.shared,
            "POST",
            uri.path(),
            Some(kind),
            reason.clone(),
        )
        .await;
        return Json(json!({"code":99991672,"msg":reason})).into_response();
    }
    let mut fields = std::collections::BTreeMap::new();
    let mut binary = None;
    let mut filename = None;
    loop {
        let field = match multipart.next_field().await {
            Ok(Some(field)) => field,
            Ok(None) => break,
            Err(_) => {
                return Json(json!({"code":234001,"msg":"invalid multipart"})).into_response();
            }
        };
        let name = field.name().unwrap_or("").to_string();
        if name == if image { "image" } else { "file" } {
            filename = field.file_name().map(str::to_string);
            binary = field.bytes().await.ok();
        } else {
            fields.insert(name, field.text().await.unwrap_or_default());
        }
    }
    let Some(binary) = binary else {
        return Json(json!({"code":234001,"msg":"missing upload bytes"})).into_response();
    };
    let limit = if image {
        10 * 1024 * 1024
    } else {
        30 * 1024 * 1024
    };
    if binary.is_empty() || binary.len() > limit {
        return Json(json!({"code":234006,"msg":"size limit"})).into_response();
    }
    let valid = if image {
        fields.get("image_type").map(String::as_str) == Some("message")
    } else {
        fields.get("file_type").map(String::as_str) == Some("stream")
            && fields.get("file_name") == filename.as_ref()
    };
    if !valid
        || filename
            .as_ref()
            .is_none_or(|name| name.contains(['/', '\\']))
    {
        return Json(json!({"code":234001,"msg":"invalid form fields or filename"}))
            .into_response();
    }
    let (key, disposition, waiter) = {
        let mut inner = state.shared.lock().await;
        let key = format!(
            "{}_fixture_{}",
            if image { "img" } else { "file" },
            inner.calls.len()
        );
        inner.record("POST", uri.path(), Some(kind), true, None);
        let disposition = inner
            .im
            .upload
            .pop_front()
            .unwrap_or(SendDisposition::Succeed);
        let last = inner.calls.last_mut().unwrap();
        last.request_bytes = binary.len();
        last.send_body = Some(json!({
            "key":key, "filename":filename, "fields":fields,
            "sha256":hex::encode(Sha256::digest(&binary)),
            "uploaded":matches!(disposition, SendDisposition::Succeed | SendDisposition::Hang | SendDisposition::AcceptThenDrop),
        }));
        (key, disposition, inner.im.upload_hang.waiter())
    };
    if matches!(disposition, SendDisposition::Hang) {
        waiter.wait(&state.cancel).await;
        if state.cancel.is_cancelled() {
            return Response::new(Body::empty());
        }
    }
    match disposition {
        SendDisposition::Succeed | SendDisposition::Hang => {
            Json(json!({"code":0,"data":if image {json!({"image_key":key})}else{json!({"file_key":key})}})).into_response()
        }
        SendDisposition::Reject {code,msg} => Json(json!({"code":code,"msg":msg})).into_response(),
        SendDisposition::AcceptThenDrop => {
            state.cancel.cancelled().await;
            Response::new(Body::empty())
        }
    }
}

pub(crate) async fn send(state: &HttpState, body: &SendBody, request_bytes: usize) -> Response {
    let content: serde_json::Value = match serde_json::from_str(&body.content) {
        Ok(value) => value,
        Err(_) => return Json(json!({"code":234001,"msg":"invalid content"})).into_response(),
    };
    let image = body.msg_type == "image";
    let key = content[if image { "image_key" } else { "file_key" }].as_str();
    let (assigned, disposition) = {
        let mut inner = state.shared.lock().await;
        let kind = if image {
            CallKind::ImageUpload
        } else {
            CallKind::FileUpload
        };
        if !inner.is_known_chat(&body.receive_id)
            || key.is_none()
            || !inner.calls.iter().any(|call| {
                call.kind == Some(kind)
                    && call
                        .send_body
                        .as_ref()
                        .is_some_and(|body| body["key"].as_str() == key && body["uploaded"] == true)
            })
        {
            return Json(json!({"code":234001,"msg":"unknown target or uploaded key"}))
                .into_response();
        }
        inner.im.send_seq += 1;
        let assigned = format!("om_anywork_send_{}", inner.im.send_seq);
        inner.record(
            "POST",
            "/open-apis/im/v1/messages",
            Some(CallKind::MessageSend),
            true,
            None,
        );
        let last = inner.calls.last_mut().unwrap();
        last.send_body = Some(serde_json::to_value(body).unwrap());
        last.assigned_message_id = Some(assigned.clone());
        last.uuid = body.uuid.clone();
        last.request_bytes = request_bytes;
        last.msg_type = Some(body.msg_type.clone());
        (assigned, inner.next_send())
    };
    match disposition {
        SendDisposition::Succeed => Json(send_ok(&assigned, body)).into_response(),
        SendDisposition::Reject { code, msg } => {
            Json(json!({"code":code,"msg":msg})).into_response()
        }
        SendDisposition::Hang | SendDisposition::AcceptThenDrop => {
            state.cancel.cancelled().await;
            Response::new(Body::empty())
        }
    }
}

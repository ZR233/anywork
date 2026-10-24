//! Official Multipart extraction with bounded fields, file bytes and retention.

use std::collections::BTreeSet;
use std::time::Duration;

use axum::Json;
use axum::body::Bytes;
use axum::extract::multipart::MultipartRejection;
use axum::extract::{Multipart, State};
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};

use super::http::{begin, error, interrupted_body};
use super::state::{StoredResource, digest, valid_file_name, valid_mime};
use super::{
    FileType, MAX_FILE_BYTES, ResourceKind, ResourceOrigin, ResourceSummary, UploadDisposition,
    UploadObservation, UploadOutcome,
};
use crate::feishu::http::HttpState;
use crate::feishu::types::CallKind;

/// Bounded allowance for framing in the total body cap; the file component's
/// decimal 30 MB limit is checked independently while streaming its chunks.
pub(crate) const MAX_MULTIPART_BYTES: usize = MAX_FILE_BYTES + 65_536;

struct UploadedFile {
    file_type: FileType,
    file_name: String,
    mime_type: String,
    duration: Option<u64>,
    bytes: Bytes,
    sha256: String,
}

pub(crate) async fn upload(
    State(state): State<HttpState>,
    headers: HeaderMap,
    multipart: Result<Multipart, MultipartRejection>,
) -> Response {
    let (call_index, _permit) = match begin(
        &state,
        &headers,
        CallKind::FileUpload,
        "POST",
        "/open-apis/im/v1/files",
    )
    .await
    {
        Ok(admission) => admission,
        Err(failure) => return failure.into_response(),
    };
    let observation = {
        let mut inner = state.shared.lock().await;
        let observation = inner.media.uploads.len();
        inner.media.uploads.push(UploadObservation {
            call_index,
            file_type: None,
            file_name: None,
            byte_len: None,
            sha256: None,
            file_key: None,
            disposition: None,
            outcome: UploadOutcome::Receiving,
        });
        observation
    };
    // Parsing cannot keep graceful shutdown alive: the cancel branch drops
    // Multipart and its partly received bytes, and the permit is RAII-owned.
    let parsed = tokio::select! {
        biased;
        () = state.cancel.cancelled() => Err("peer shutdown"),
        result = tokio::time::timeout(Duration::from_secs(15), parse_multipart(multipart)) => {
            result.unwrap_or(Err("multipart receive timeout"))
        }
    };
    let file = match parsed {
        Ok(file) => file,
        Err(reason) => {
            let mut inner = state.shared.lock().await;
            inner.calls[call_index].diagnostic = Some(reason.into());
            inner.media.uploads[observation].outcome = if state.cancel.is_cancelled() {
                inner.calls[call_index].owned_reject = true;
                UploadOutcome::Cancelled
            } else {
                UploadOutcome::Invalid
            };
            return error(StatusCode::BAD_REQUEST, 234001, reason);
        }
    };
    let (disposition, waiter) = {
        let mut inner = state.shared.lock().await;
        inner.calls[call_index].accepted = true;
        let disposition = inner
            .media
            .upload_script
            .pop_front()
            .unwrap_or(UploadDisposition::Succeed);
        let fact = &mut inner.media.uploads[observation];
        fact.file_type = Some(file.file_type);
        fact.file_name = Some(file.file_name.clone());
        fact.byte_len = Some(file.bytes.len());
        fact.sha256 = Some(file.sha256.clone());
        fact.disposition = Some(disposition.clone());
        fact.outcome = UploadOutcome::Waiting;
        (disposition, inner.media.upload_hang.waiter())
    };
    if matches!(disposition, UploadDisposition::Hang) {
        waiter.wait(&state.cancel).await;
    }
    let mut inner = state.shared.lock().await;
    if inner.closing || state.cancel.is_cancelled() {
        inner.media.uploads[observation].outcome = UploadOutcome::Cancelled;
        return error(StatusCode::SERVICE_UNAVAILABLE, 99991400, "peer shutdown");
    }
    if let UploadDisposition::Reject { code, msg } = disposition {
        inner.media.uploads[observation].outcome = UploadOutcome::Rejected;
        return error(StatusCode::BAD_REQUEST, code, &msg);
    }
    // Monotonic candidate keys skip synthetic registrations, which may use any
    // valid identity. Failed retention does not mint a successful upload fact.
    let key = loop {
        inner.media.upload_seq += 1;
        let key = format!("file_anywork_fixture_upload_{}", inner.media.upload_seq);
        if !inner.media.resources.contains_key(&key) {
            break key;
        }
    };
    let stored = StoredResource {
        summary: ResourceSummary {
            file_key: key.clone(),
            kind: ResourceKind::File,
            file_name: file.file_name,
            mime_type: file.mime_type,
            byte_len: file.bytes.len(),
            sha256: file.sha256,
            origin: ResourceOrigin::Upload {
                file_type: file.file_type,
                duration: file.duration,
            },
        },
        bytes: file.bytes,
        messages: BTreeSet::new(),
    };
    if inner.media.insert(stored).is_err() {
        inner.media.uploads[observation].outcome = UploadOutcome::Rejected;
        return error(
            StatusCode::TOO_MANY_REQUESTS,
            99991400,
            "resource retention limit",
        );
    }
    let fact = &mut inner.media.uploads[observation];
    fact.file_key = Some(key.clone());
    if matches!(disposition, UploadDisposition::AcceptThenDrop) {
        fact.outcome = UploadOutcome::StoredResponseDropped;
        let mut response = Response::new(interrupted_body(Bytes::new()));
        response.headers_mut().insert(
            axum::http::header::CONTENT_TYPE,
            axum::http::HeaderValue::from_static("application/json"),
        );
        response
    } else {
        fact.outcome = UploadOutcome::Stored;
        Json(serde_json::json!({"code": 0, "msg": "success", "data": {"file_key": key}}))
            .into_response()
    }
}

async fn parse_multipart(
    multipart: Result<Multipart, MultipartRejection>,
) -> Result<UploadedFile, &'static str> {
    let mut multipart = multipart.map_err(|_| "invalid multipart boundary or content type")?;
    let mut file_type = None;
    let mut file_name = None;
    let mut duration = None;
    let mut file = None;
    let mut mime_type = None;
    let mut fields = BTreeSet::new();
    while let Some(mut field) = multipart
        .next_field()
        .await
        .map_err(|_| "invalid multipart envelope")?
    {
        let name = field
            .name()
            .ok_or("multipart field missing name")?
            .to_owned();
        if !matches!(
            name.as_str(),
            "file_type" | "file_name" | "file" | "duration"
        ) {
            return Err("unknown multipart field");
        }
        if !fields.insert(name.clone()) {
            return Err("duplicate multipart field");
        }
        let limit = if name == "file" { MAX_FILE_BYTES } else { 1024 };
        let content_type = field
            .content_type()
            .unwrap_or("application/octet-stream")
            .to_owned();
        let mut bytes = Vec::new();
        while let Some(chunk) = field
            .chunk()
            .await
            .map_err(|_| "multipart field truncated or body limit")?
        {
            if chunk.len() > limit - bytes.len() {
                return Err("multipart field size limit");
            }
            bytes.extend_from_slice(&chunk);
        }
        if name == "file" {
            if bytes.is_empty() {
                return Err("empty file");
            }
            if !valid_mime(&content_type) {
                return Err("invalid file MIME type");
            }
            mime_type = Some(content_type);
            file = Some(Bytes::from(bytes));
            continue;
        }
        let value = String::from_utf8(bytes).map_err(|_| "multipart metadata is not UTF-8")?;
        match name.as_str() {
            "file_type" => file_type = Some(FileType::parse(&value).ok_or("invalid file_type")?),
            "file_name" => {
                if !valid_file_name(&value) {
                    return Err("invalid file_name");
                }
                file_name = Some(value);
            }
            "duration" => duration = Some(value.parse::<u64>().map_err(|_| "invalid duration")?),
            _ => return Err("unknown multipart field"),
        }
    }
    let bytes = file.ok_or("missing file")?;
    Ok(UploadedFile {
        file_type: file_type.ok_or("missing file_type")?,
        file_name: file_name.ok_or("missing file_name")?,
        mime_type: mime_type.ok_or("missing file MIME type")?,
        duration,
        sha256: digest(&bytes),
        bytes,
    })
}

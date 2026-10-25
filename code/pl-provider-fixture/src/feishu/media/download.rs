//! Exact message/key/type resource downloads. Never looks up product state.

use axum::body::Body;
use axum::extract::rejection::QueryRejection;
use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, HeaderValue, StatusCode, header};
use axum::response::{IntoResponse, Response};
use serde::Deserialize;

use super::http::{begin, error, interrupted_body};
use super::state::valid_identity;
use super::{
    ResourceDownloadDisposition, ResourceDownloadObservation, ResourceDownloadOutcome,
    ResourceDownloadType,
};
use crate::feishu::guard::HttpState;
use crate::feishu::types::CallKind;

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
pub(crate) struct DownloadQuery {
    #[serde(rename = "type")]
    resource_type: ResourceDownloadType,
}

pub(crate) async fn download(
    State(state): State<HttpState>,
    headers: HeaderMap,
    Path((message_id, file_key)): Path<(String, String)>,
    query: Result<Query<DownloadQuery>, QueryRejection>,
) -> Response {
    let (call_index, _permit) = match begin(
        &state,
        &headers,
        CallKind::ResourceDownload,
        "GET",
        "/open-apis/im/v1/messages/{message_id}/resources/{file_key}",
    )
    .await
    {
        Ok(admission) => admission,
        Err(failure) => return failure.into_response(),
    };
    let resource_type = query.ok().map(|Query(q)| q.resource_type);
    let (observation, bytes, summary, disposition, waiter) = {
        let mut inner = state.shared.lock().await;
        let mapped_key = inner
            .media
            .message_keys
            .get(&(message_id.clone(), file_key.clone()));
        let resource = inner
            .media
            .resources
            .get(mapped_key.unwrap_or(&file_key))
            .filter(|resource| {
                valid_identity(&message_id)
                    && valid_identity(&file_key)
                    && (mapped_key.is_some() || resource.messages.contains(&message_id))
                    && resource_type == Some(resource.summary.kind.download_type())
            })
            .map(|resource| (resource.bytes.clone(), resource.summary.clone()));
        let observation = inner.media.downloads.len();
        inner.media.downloads.push(ResourceDownloadObservation {
            call_index,
            message_id: message_id.chars().take(256).collect(),
            file_key: file_key.chars().take(256).collect(),
            resource_type,
            resource: resource.as_ref().map(|(_, summary)| summary.clone()),
            disposition: None,
            outcome: ResourceDownloadOutcome::Invalid,
            prepared_bytes: 0,
        });
        let Some((bytes, summary)) = resource else {
            inner.calls[call_index].diagnostic = Some("resource message/key/type mismatch".into());
            return error(
                StatusCode::BAD_REQUEST,
                234001,
                "resource message/key/type mismatch",
            );
        };
        inner.calls[call_index].accepted = true;
        let disposition = inner
            .media
            .download_script
            .pop_front()
            .unwrap_or(ResourceDownloadDisposition::Succeed);
        inner.media.downloads[observation].disposition = Some(disposition.clone());
        inner.media.downloads[observation].outcome = ResourceDownloadOutcome::Waiting;
        (
            observation,
            bytes,
            summary,
            disposition,
            inner.media.download_hang.waiter(),
        )
    };
    if matches!(disposition, ResourceDownloadDisposition::Hang) {
        waiter.wait(&state.cancel).await;
    }
    let mut inner = state.shared.lock().await;
    let fact = &mut inner.media.downloads[observation];
    if state.cancel.is_cancelled() {
        fact.outcome = ResourceDownloadOutcome::Cancelled;
        return error(StatusCode::SERVICE_UNAVAILABLE, 99991400, "peer shutdown");
    }
    let (body, prepared, outcome) = match disposition {
        ResourceDownloadDisposition::Succeed | ResourceDownloadDisposition::Hang => {
            let len = bytes.len();
            (
                Body::from(bytes),
                len,
                ResourceDownloadOutcome::ResponsePrepared,
            )
        }
        ResourceDownloadDisposition::Reject { code, msg } => {
            fact.outcome = ResourceDownloadOutcome::Rejected;
            return error(StatusCode::BAD_REQUEST, code, &msg);
        }
        ResourceDownloadDisposition::AcceptThenDrop => (
            interrupted_body(bytes.slice(..0)),
            0,
            ResourceDownloadOutcome::ResponseInterrupted,
        ),
        ResourceDownloadDisposition::Disconnect { after_bytes } => {
            // Always leave at least one byte missing even if the configured
            // prefix is too large, so no full file can masquerade as success.
            let count = after_bytes.min(bytes.len().saturating_sub(1));
            (
                interrupted_body(bytes.slice(..count)),
                count,
                ResourceDownloadOutcome::ResponseInterrupted,
            )
        }
    };
    fact.prepared_bytes = prepared;
    fact.outcome = outcome;
    let disposition = content_disposition(&summary.file_name);
    let mut response = Response::new(body);
    let mime = match HeaderValue::from_str(&summary.mime_type) {
        Ok(mime) => mime,
        Err(_) => {
            return error(
                StatusCode::INTERNAL_SERVER_ERROR,
                500,
                "invalid stored MIME type",
            );
        }
    };
    let attachment = match HeaderValue::from_str(&disposition) {
        Ok(attachment) => attachment,
        Err(_) => {
            return error(
                StatusCode::INTERNAL_SERVER_ERROR,
                500,
                "invalid stored file name",
            );
        }
    };
    response.headers_mut().insert(header::CONTENT_TYPE, mime);
    response
        .headers_mut()
        .insert(header::CONTENT_DISPOSITION, attachment);
    response
}

fn content_disposition(name: &str) -> String {
    let fallback: String = name
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || " ._-".contains(c) {
                c
            } else {
                '_'
            }
        })
        .collect();
    // RFC 5987 percent encoding via the existing URL component, not a parser.
    let encoded: String = url::form_urlencoded::byte_serialize(name.as_bytes()).collect();
    format!(
        "attachment; filename=\"{fallback}\"; filename*=UTF-8''{}",
        encoded.replace('+', "%20")
    )
}

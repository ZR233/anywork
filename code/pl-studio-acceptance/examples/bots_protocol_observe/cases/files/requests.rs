//! Read actual provider requests and reliable attachment endpoints. Native image
//! evidence always decodes the wire block; file evidence verifies physical bytes.

use super::super::Session;
use super::uploads::ThreadUploads;
use crate::http;
use anyhow::{Context, Result, ensure};
use pl_provider_fixture::{RecordedRequest, bots_observe as model};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
};

#[derive(Deserialize)]
struct Request {
    #[serde(default)]
    input: Vec<Item>,
}

#[derive(Deserialize)]
struct Item {
    #[serde(default)]
    role: Option<String>,
    #[serde(default)]
    content: Option<Content>,
    #[serde(default)]
    call_id: Option<String>,
    #[serde(default)]
    output: Option<String>,
}

#[derive(Deserialize)]
#[serde(untagged)]
enum Content {
    Text(String),
    Parts(Vec<Part>),
}

#[derive(Deserialize)]
struct Part {
    #[serde(rename = "type")]
    kind: String,
    #[serde(default)]
    text: Option<String>,
    #[serde(default)]
    image_url: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct FileDescription {
    pub filename: String,
    pub byte_size: u64,
    pub media_type: String,
    pub path: String,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub(super) struct Original {
    pub attachment_id: String,
    pub filename: Option<String>,
    pub modality: pl_protocol::AttachmentModality,
    pub media_type: String,
    pub byte_len: usize,
    pub sha256: String,
}

pub(super) fn execution_requests(session: &Session) -> Vec<RecordedRequest> {
    session
        .model
        .as_ref()
        .map(|fixture| {
            fixture
                .recorded()
                .into_iter()
                .filter(|request| {
                    request.accepted
                        && !request
                            .body
                            .to_string()
                            .contains("Create the session title now")
                })
                .collect()
        })
        .unwrap_or_default()
}

pub(super) async fn wait_executions(session: &Session, count: usize) -> Result<()> {
    http::wait_until(http::PREDICATE_TIMEOUT, || async {
        let model = session.model.as_ref().context("model fixture missing")?;
        ensure!(
            model.live_status().rejected == 0,
            "strict model rejected a request: {:?}",
            model
                .recorded()
                .last()
                .and_then(|request| request.diagnostic.as_ref())
        );
        Ok(execution_requests(session).len() >= count)
    })
    .await
}

pub(super) async fn wait_output(session: &Session, call_id: &str) -> Result<RecordedRequest> {
    http::wait_until(http::PREDICATE_TIMEOUT, || async {
        ensure!(
            session
                .model
                .as_ref()
                .context("model missing")?
                .live_status()
                .rejected
                == 0,
            "strict model rejected a continuation before {call_id}"
        );
        Ok(execution_requests(session)
            .iter()
            .any(|request| tool_output(request, call_id).is_ok()))
    })
    .await
    .with_context(|| format!("actual tool result for {call_id} never reached the provider"))?;
    execution_requests(session)
        .into_iter()
        .find(|request| tool_output(request, call_id).is_ok())
        .context("tool result disappeared from fixture records")
}

pub(super) async fn send_result(
    session: &Session,
    call_id: &str,
) -> Result<pl_protocol::studio::BotSendResult> {
    let request = wait_output(session, call_id).await?;
    let output = tool_output(&request, call_id)?;
    serde_json::from_str(&output).with_context(|| {
        format!("actual tool {call_id} did not return the public typed BotSendResult")
    })
}

pub(super) fn user_texts(request: &RecordedRequest) -> Result<Vec<String>> {
    let request: Request = serde_json::from_value(request.body.clone())?;
    let mut texts = Vec::new();
    for item in request.input {
        if item.role.as_deref() != Some("user") {
            continue;
        }
        match item.content {
            Some(Content::Text(text)) => texts.push(text),
            Some(Content::Parts(parts)) => {
                texts.extend(parts.into_iter().filter_map(|part| part.text))
            }
            None => {}
        }
    }
    Ok(texts)
}

pub(super) fn tool_output(request: &RecordedRequest, call_id: &str) -> Result<String> {
    let request: Request = serde_json::from_value(request.body.clone())?;
    request
        .input
        .into_iter()
        .find(|item| item.call_id.as_deref() == Some(call_id) && item.output.is_some())
        .and_then(|item| item.output)
        .context("actual provider request is missing the expected tool result")
}

pub(super) fn native_images(request: &RecordedRequest) -> Result<Vec<Vec<u8>>> {
    let request: Request = serde_json::from_value(request.body.clone())?;
    let mut images = Vec::new();
    for item in request.input {
        if item.role.as_deref() != Some("user") {
            continue;
        }
        if let Some(Content::Parts(parts)) = item.content {
            for part in parts {
                if part.kind == "input_image" {
                    images.push(model::image_data_url_bytes(
                        part.image_url
                            .as_deref()
                            .context("input_image has no URL")?,
                    )?);
                }
            }
        }
    }
    Ok(images)
}

pub(super) fn files(request: &RecordedRequest) -> Result<Vec<FileDescription>> {
    let mut files = BTreeMap::new();
    for text in user_texts(request)? {
        for line in text.lines() {
            if let Some((_, json)) = line.split_once("permissions: ") {
                let file: FileDescription =
                    serde_json::from_str(json).context("invalid product user-file description")?;
                if let Some(previous) = files.insert(file.path.clone(), file.clone()) {
                    ensure!(
                        previous == file,
                        "one execution path described different user files: {}",
                        file.path
                    );
                }
            }
        }
    }
    Ok(files.into_values().collect())
}

pub(super) fn thread_uploads(workspace: &Path, thread_id: &str) -> Result<ThreadUploads> {
    ensure!(!thread_id.is_empty(), "actual Thread identity is missing");
    // design/17 and the formal pl-tool SessionFiles::new API hash the raw
    // original Thread id exactly once. pl-studio-acceptance has no pl-tool
    // dependency; this one observer boundary follows that public mapping.
    let key = model::sha256(thread_id.as_bytes());
    ThreadUploads::for_thread_key(workspace, &key).with_context(|| {
        format!("canonical SessionFiles/uploads unavailable for Thread {thread_id}")
    })
}

pub(super) fn physical_path(uploads: &ThreadUploads, file: &FileDescription) -> Result<PathBuf> {
    uploads
        .resolve(&file.path)
        .with_context(|| format!("invalid current-Thread execution upload {}", file.path))
}

pub(super) fn verify_file(
    uploads: &ThreadUploads,
    file: &FileDescription,
    original: &Original,
) -> Result<PathBuf> {
    let path = physical_path(uploads, file)?;
    let bytes = std::fs::read(&path)?;
    let filename = original
        .filename
        .as_deref()
        .context("reliable user attachment lost its display filename")?;
    ensure!(
        bytes.len() == original.byte_len
            && model::sha256(&bytes) == original.sha256
            && file.byte_size == original.byte_len as u64
            && file.filename == filename
            && file.media_type == original.media_type,
        "execution bytes/description differ from reliable original for {}",
        file.filename
    );
    Ok(path)
}

pub(super) async fn originals(session: &Session, thread_id: &str) -> Result<Vec<Original>> {
    let timeline = session.http()?.timeline(thread_id).await?;
    let mut originals = BTreeMap::new();
    for item in timeline {
        if let pl_protocol::ThreadItemState::Text(text) = item.preview.state() {
            if text.channel() != pl_protocol::ThreadTextChannel::User {
                continue;
            }
            for attachment in text.attachments() {
                let bytes = session
                    .http()?
                    .attachment_bytes(thread_id, &attachment.id)
                    .await?;
                ensure!(
                    attachment.byte_size == bytes.len() as u64,
                    "reliable attachment length changed"
                );
                originals.insert(
                    attachment.id.clone(),
                    Original {
                        attachment_id: attachment.id.clone(),
                        filename: attachment.filename.clone(),
                        modality: attachment.modality,
                        media_type: attachment.media_type.clone(),
                        byte_len: bytes.len(),
                        sha256: model::sha256(&bytes),
                    },
                );
            }
        }
    }
    Ok(originals.into_values().collect())
}

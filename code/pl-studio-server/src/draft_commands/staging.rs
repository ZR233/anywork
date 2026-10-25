//! Existing multipart ordering, limits, filename and native preflight rules, on the owned body.
use super::upload::Upload;
use anyhow::Result;
use axum::extract::Multipart;
use pl_protocol::studio::{
    AdmitAttachmentDraftsRequest, StudioAttachmentAdmissionContext, StudioAttachmentDraftSource,
    StudioError,
};
use pl_studio_runtime::StudioRuntime;
use tokio::io::AsyncWriteExt;

pub(super) const MAX_BODY_BYTES: usize = 200 * 1024 * 1024;
const MAX_FILE_BYTES: usize = 50 * 1024 * 1024;
const MAX_FILES: usize = 16;

pub(super) async fn stage(
    owner: &Upload,
    runtime: &StudioRuntime,
    mut multipart: Multipart,
) -> Result<AdmitAttachmentDraftsRequest> {
    owner.install_directory(
        tempfile::Builder::new()
            .prefix("anywork-http-attachments-")
            .tempdir()?,
    );
    let mut context = None;
    let mut sources = Vec::new();
    while let Some(mut field) = multipart.next_field().await.map_err(|_| invalid())? {
        match field.name() {
            Some("context") => {
                if context.is_some() || !sources.is_empty() {
                    return Err(invalid().into());
                }
                let text = field.text().await.map_err(|_| invalid())?;
                context = Some(
                    serde_json::from_str::<StudioAttachmentAdmissionContext>(&text)
                        .map_err(|_| invalid())?,
                );
            }
            Some("file") => {
                let admission_context = context.clone().ok_or_else(invalid)?;
                if sources.len() >= MAX_FILES {
                    return Err(StudioError::invalid_argument(
                        "multipart attachment file count exceeds the server limit",
                    )
                    .into());
                }
                let filename = field
                    .file_name()
                    .and_then(safe_upload_filename)
                    .ok_or_else(invalid)?;
                let path = owner
                    .directory()?
                    .join(format!("{:02}-{filename}", sources.len()));
                let source = StudioAttachmentDraftSource::LocalFile {
                    path: path.to_string_lossy().to_string(),
                };
                let mut predicted = sources.clone();
                predicted.push(source.clone());
                runtime
                    .preflight_attachment_drafts(&AdmitAttachmentDraftsRequest {
                        context: admission_context,
                        sources: predicted,
                    })
                    .await?;
                let mut file = tokio::fs::File::create(path).await?;
                let copied = async {
                    let mut written = 0_usize;
                    while let Some(chunk) = field.chunk().await.map_err(|_| invalid())? {
                        written = written.saturating_add(chunk.len());
                        if written > MAX_FILE_BYTES {
                            return Err(StudioError::invalid_argument(
                                "multipart attachment file exceeds the server limit",
                            )
                            .into());
                        }
                        file.write_all(&chunk).await?;
                    }
                    Ok::<_, anyhow::Error>(())
                }
                .await;
                // Tokio File can buffer a write before the blocking syscall has finished. Even
                // a body/limit error joins that original write before host cleanup may remove it.
                let flushed = file.flush().await;
                copied?;
                flushed?;
                sources.push(source);
            }
            _ => return Err(invalid().into()),
        }
    }
    Ok(AdmitAttachmentDraftsRequest {
        context: context.ok_or_else(invalid)?,
        sources,
    })
}

fn invalid() -> StudioError {
    StudioError::invalid_argument("invalid multipart attachment admission body")
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

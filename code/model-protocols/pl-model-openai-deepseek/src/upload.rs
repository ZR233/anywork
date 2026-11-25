//! DeepSeek Files 与独立搜索协议。

use pl_model_wire::files::{FileUploadFailure, UploadFailureOutcome};

pub async fn upload_file(
    request: pl_model_wire::files::FileUploadRequest<'_>,
) -> Result<Option<pl_model_wire::files::UploadedFile>, FileUploadFailure> {
    use pl_model_wire::protocol::WireApi;
    use pl_model_wire::provider_error::ErrorPolicyBinding;
    use pl_model_wire::transport;
    use pl_protocol::{
        ProviderFailure, ProviderFailureKind, ProviderFailureStage, RetryDisposition,
    };
    let part = reqwest::multipart::Part::bytes(request.bytes.to_vec())
        .file_name(
            request
                .input
                .filename
                .clone()
                .unwrap_or_else(|| "attachment".into()),
        )
        .mime_str(&request.input.media_type)
        .map_err(|error| FileUploadFailure {
            source: transport::reqwest_error_to_pure(error),
            outcome: UploadFailureOutcome::Rejected,
        })?;
    // The Files endpoint chooses the PDF parser when it starts reading the file part.
    let purpose = if request.input.media_type == "application/pdf" {
        "text_recognition"
    } else {
        "user_data"
    };
    let form = reqwest::multipart::Form::new()
        .text("purpose", purpose)
        .part("file", part)
        .text("expires_after[anchor]", "created_at")
        .text("expires_after[seconds]", "86400");
    let headers = transport::headers(
        request.endpoint.bearer_token.as_deref(),
        request.endpoint.http_headers.as_ref(),
        request.model_headers,
    )
    .map_err(|source| FileUploadFailure {
        source,
        outcome: UploadFailureOutcome::Rejected,
    })?;
    let diagnostics = transport::RequestDiagnostics::from_headers(&headers);
    let upload = request
        .client
        .post(format!(
            "{}/files",
            request.endpoint.base_url.trim_end_matches('/')
        ))
        .headers(headers)
        .multipart(form)
        .timeout(std::time::Duration::from_secs(300))
        .build()
        .map_err(|error| FileUploadFailure {
            source: attachment_error(error, &diagnostics),
            outcome: UploadFailureOutcome::Rejected,
        })?;
    let response = request
        .client
        .execute(upload)
        .await
        .map_err(|error| FileUploadFailure {
            source: attachment_error(error, &diagnostics),
            outcome: UploadFailureOutcome::Unknown,
        })?;
    let headers_received = pl_model_wire::provider_error::ErrorObservedAt::now();
    let status = response.status();
    if !status.is_success() {
        let rejected = transport::read_response_error(
            response,
            Some(ErrorPolicyBinding {
                policy: crate::adapter::ADAPTER.error_policy,
                wire_api: WireApi::Responses,
                endpoint: Some(request.endpoint),
            }),
            ProviderFailureStage::Attachment,
            Some(&diagnostics),
            headers_received,
        )
        .await;
        if rejected.body_complete && matches!(status.as_u16(), 404 | 405 | 501) {
            return Ok(None);
        }
        // DeepSeek documents these statuses as request, authorization, balance or rate
        // rejections. A server fault never establishes that a file was not created.
        let outcome = if rejected.body_complete
            && matches!(status.as_u16(), 400 | 401 | 402 | 403 | 413 | 422 | 429)
        {
            UploadFailureOutcome::Rejected
        } else {
            UploadFailureOutcome::Unknown
        };
        return Err(FileUploadFailure {
            source: rejected.failure.into(),
            outcome,
        });
    }
    #[derive(serde::Deserialize)]
    struct File {
        id: String,
        expires_at: Option<i64>,
    }
    let file: File = response.json().await.map_err(|error| FileUploadFailure {
        source: attachment_error(error, &diagnostics),
        outcome: UploadFailureOutcome::Unknown,
    })?;
    if file.id.is_empty() {
        let mut failure = ProviderFailure::new(
            ProviderFailureKind::Protocol,
            "upload response has no file id",
            RetryDisposition::Permanent,
        );
        failure.context.stage = ProviderFailureStage::Attachment;
        return Err(FileUploadFailure {
            source: failure.into(),
            outcome: UploadFailureOutcome::Unknown,
        });
    }
    Ok(Some(pl_model_wire::files::UploadedFile {
        id: file.id,
        expires_at: file.expires_at.unwrap_or(request.now.saturating_add(86400)),
    }))
}

fn attachment_error(
    cause: reqwest::Error,
    diagnostics: &pl_model_wire::transport::RequestDiagnostics,
) -> pl_protocol::PureError {
    let mut error = pl_model_wire::transport::reqwest_error_to_pure(cause);
    if let pl_protocol::PureError::Provider(failure) = &mut error {
        failure.context.stage = pl_protocol::ProviderFailureStage::Attachment;
    }
    diagnostics.redact_error(&mut error);
    error
}

pub static FILE_UPLOAD: pl_model_wire::files::FileUploadService =
    pl_model_wire::files::FileUploadService {
        id: pl_model_wire::protocol::FileUploadCapability::from_static("deep_seek"),
        cache_revision: "deepseek:files-v2:86400",
        upload: |request| Box::pin(upload_file(request)),
    };

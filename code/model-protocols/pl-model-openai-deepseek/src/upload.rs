//! DeepSeek Files 与独立搜索协议。

pub async fn upload_file(
    request: pl_model_openai_wire::files::FileUploadRequest<'_>,
) -> pl_protocol::Result<Option<pl_model_openai_wire::files::UploadedFile>> {
    use pl_model_openai_wire::transport;
    let part = reqwest::multipart::Part::bytes(request.bytes.to_vec())
        .file_name(
            request
                .input
                .filename
                .clone()
                .unwrap_or_else(|| "attachment".into()),
        )
        .mime_str(&request.input.media_type)
        .map_err(transport::reqwest_error_to_pure)?;
    // DeepSeek rejects PDFs uploaded with user_data. Its parsed documents
    // still use the standard Responses input_file.file_id representation.
    let purpose = if request.input.media_type == "application/pdf" {
        "text_recognition"
    } else {
        "user_data"
    };
    let form = reqwest::multipart::Form::new()
        .part("file", part)
        .text("purpose", purpose)
        .text("expires_after[anchor]", "created_at")
        .text("expires_after[seconds]", "86400");
    let headers = transport::headers(
        request.endpoint.bearer_token.as_deref(),
        request.endpoint.http_headers.as_ref(),
        request.model_headers,
    )?;
    let response = request
        .client
        .post(format!(
            "{}/files",
            request.endpoint.base_url.trim_end_matches('/')
        ))
        .headers(headers)
        .multipart(form)
        .timeout(std::time::Duration::from_secs(300))
        .send()
        .await
        .map_err(transport::reqwest_error_to_pure)?;
    if matches!(response.status().as_u16(), 404 | 405 | 501) {
        return Ok(None);
    }
    let response = transport::checked(response).await?;
    #[derive(serde::Deserialize)]
    struct File {
        id: String,
        expires_at: Option<i64>,
    }
    let file: File = response
        .json()
        .await
        .map_err(transport::reqwest_error_to_pure)?;
    if file.id.is_empty() {
        return Err(pl_protocol::PureError::Protocol(
            "upload response has no file id".into(),
        ));
    }
    Ok(Some(pl_model_openai_wire::files::UploadedFile {
        id: file.id,
        expires_at: file.expires_at.unwrap_or(request.now.saturating_add(86400)),
    }))
}

pub static FILE_UPLOAD: pl_model_openai_wire::files::FileUploadService =
    pl_model_openai_wire::files::FileUploadService {
        id: pl_model_openai_wire::protocol::FileUploadCapability::from_static("deep_seek"),
        cache_revision: "deepseek:files-v2:86400",
        upload: |request| Box::pin(upload_file(request)),
    };

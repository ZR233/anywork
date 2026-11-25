//! Endpoint-owned attachment preparation. Durable history never contains upload handles.
use base64::{Engine, engine::general_purpose::STANDARD};
use futures::StreamExt;
use pl_model_wire::files::UploadFailureOutcome;
use pl_protocol::{PureError, Result};
use sha2::{Digest, Sha256};
use std::{collections::HashMap, sync::Arc};

use super::{
    ModelSession,
    provider_error::{reqwest_body_error_to_pure, reqwest_error_to_pure},
    transport,
};
use crate::completion::{
    AttachmentInput, AttachmentRepresentation, AttachmentSource, CompletionRequest,
    ResolvedAttachment,
};
use crate::model::{ModelDefinition, ModelModality};
use crate::protocol::ProtocolEndpoint;

pub(super) enum UploadState {
    Pending,
    Ready { id: String, expires_at: i64 },
    Unsupported,
}

#[derive(Debug)]
pub(super) struct AttachmentPreparationError {
    pub source: PureError,
    pub replay_safe: bool,
}

impl AttachmentPreparationError {
    fn before_upload(source: PureError) -> Self {
        Self {
            source,
            replay_safe: true,
        }
    }
}

pub(super) struct AttachmentBackend<'a> {
    pub upload: Option<&'static pl_model_wire::files::FileUploadService>,
    pub endpoint: &'a ProtocolEndpoint,
    pub model: &'a ModelDefinition,
    pub client: &'a reqwest::Client,
    pub session: &'a ModelSession,
    pub fingerprint: u64,
    pub now: i64,
    pub cancellation: tokio_util::sync::CancellationToken,
}

impl AttachmentBackend<'_> {
    pub async fn prepare(
        &self,
        request: &mut CompletionRequest,
    ) -> std::result::Result<(), AttachmentPreparationError> {
        self.prepare_inner(request).await.map_err(|mut error| {
            if let PureError::Provider(failure) = &mut error.source {
                failure.context.stage = pl_protocol::ProviderFailureStage::Attachment;
                failure.context.recovery = pl_protocol::ProviderRecovery::None;
            }
            error
        })
    }

    async fn materialize_batch(&self, request: &CompletionRequest) -> Result<Vec<Arc<[u8]>>> {
        let mut materialized = Vec::new();
        let mut identities = std::collections::HashSet::new();
        let mut totals = HashMap::new();
        // Validate the entire batch before creating any remote upload.
        for attachment in &request.attachments {
            if !identities.insert(&attachment.attachment_id) {
                return Err(PureError::ConfigError(
                    "duplicate attachment identity".into(),
                ));
            }
            let modality = match attachment.modality {
                crate::completion::AttachmentModality::Image => ModelModality::Image,
                crate::completion::AttachmentModality::Video => ModelModality::Video,
                crate::completion::AttachmentModality::File => ModelModality::File,
            };
            let capability = self
                .model
                .extra
                .capabilities
                .input_capability(modality)
                .ok_or_else(|| PureError::ConfigError("unsupported attachment modality".into()))?;
            let limits = &capability.limits;
            if !capability.supports_source(crate::model::ModelInputSource::Local) {
                return Err(PureError::ConfigError(
                    "model cannot replay retained attachment content".into(),
                ));
            }
            if let AttachmentSource::Resource { reference, .. } = &attachment.source
                && (reference.byte_len() > limits.max_bytes.unwrap_or(32 * 1024 * 1024)
                    || reference.media_type() != attachment.media_type)
            {
                return Err(PureError::ConfigError(
                    "resource metadata violates attachment limits".into(),
                ));
            }
            let maximum = limits.max_bytes.unwrap_or(32 * 1024 * 1024);
            let bytes = self.materialize(attachment, maximum).await?;
            if bytes.len() as u64 > maximum
                || (!limits.media_types.is_empty()
                    && !limits.media_types.contains(&attachment.media_type))
            {
                return Err(PureError::ConfigError(
                    "attachment violates model size or media type limits".into(),
                ));
            }
            if modality == ModelModality::Image {
                let reader =
                    image::ImageReader::new(std::io::Cursor::new(&*bytes)).with_guessed_format()?;
                if reader
                    .format()
                    .is_none_or(|format| format.to_mime_type() != attachment.media_type)
                {
                    return Err(PureError::ConfigError(
                        "attachment MIME does not match image bytes".into(),
                    ));
                }
                let (width, height) = reader
                    .into_dimensions()
                    .map_err(|error| PureError::ConfigError(error.to_string()))?;
                if limits.max_width.is_some_and(|max| width > max)
                    || limits.max_height.is_some_and(|max| height > max)
                {
                    return Err(PureError::ConfigError(
                        "attachment image dimensions exceed model limits".into(),
                    ));
                }
            }
            let (count, total) = totals.entry(attachment.modality).or_insert((0_u64, 0_u64));
            let occurrences = request.input.iter().map(|item| match item {
                crate::completion::ModelContextItem::ToolMedia { items } => items.iter().filter(|item| item.attachment.id == attachment.attachment_id).count(),
                _ => item.as_message().map_or(0, |message| message.content.parts.iter().filter(|part| matches!(part,
                    crate::completion::ContentPart::Attachment { attachment_id, .. } if attachment_id == &attachment.attachment_id)).count()),
            }).sum::<usize>() as u64;
            if occurrences == 0 {
                return Err(PureError::ConfigError(
                    "unreferenced attachment input".into(),
                ));
            }
            *count = count
                .checked_add(occurrences)
                .ok_or_else(|| PureError::ConfigError("attachment count overflow".into()))?;
            *total = total
                .checked_add(
                    (bytes.len() as u64)
                        .checked_mul(occurrences)
                        .ok_or_else(|| PureError::ConfigError("attachment size overflow".into()))?,
                )
                .ok_or_else(|| PureError::ConfigError("attachment size overflow".into()))?;
            if limits.max_count.is_some_and(|max| *count > u64::from(max))
                || limits.max_total_bytes.is_some_and(|max| *total > max)
            {
                return Err(PureError::ConfigError(
                    "attachment batch exceeds model limits".into(),
                ));
            }
            materialized.push(bytes);
        }
        Ok(materialized)
    }

    async fn prepare_inner(
        &self,
        request: &mut CompletionRequest,
    ) -> std::result::Result<(), AttachmentPreparationError> {
        if request.attachments.is_empty() {
            return Ok(());
        }
        let materialized = self
            .materialize_batch(request)
            .await
            .map_err(AttachmentPreparationError::before_upload)?;
        request.prepared_content.clear();
        for (attachment, bytes) in request.attachments.iter_mut().zip(materialized) {
            let remote_url = match &attachment.source {
                AttachmentSource::Url { url } => Some(url.clone()),
                _ => None,
            };
            let mut sources = vec![AttachmentRepresentation::DataUrl {
                base64: STANDARD.encode(&bytes),
            }];
            if let Some(url) = remote_url {
                sources.push(AttachmentRepresentation::RemoteUrl { url });
            } else if self.upload.is_some()
                && self.model.extra.binding.transport.protocol
                    == crate::protocol::WireApi::Responses
                && let Some(id) = self.upload(attachment, &bytes).await?
            {
                sources.push(AttachmentRepresentation::ProviderFile { file_id: id });
            }
            attachment.source = AttachmentSource::Bytes { bytes };
            request.prepared_content.push(ResolvedAttachment {
                attachment_id: attachment.attachment_id.clone(),
                modality: attachment.modality,
                media_type: attachment.media_type.clone(),
                filename: attachment.filename.clone(),
                sources,
            });
        }
        Ok(())
    }

    async fn materialize(&self, input: &AttachmentInput, maximum: u64) -> Result<Arc<[u8]>> {
        match &input.source {
            AttachmentSource::Bytes { bytes } => Ok(bytes.clone()),
            AttachmentSource::Base64 { base64 } => {
                if base64.len() as u64
                    > maximum
                        .saturating_add(2)
                        .saturating_div(3)
                        .saturating_mul(4)
                {
                    return Err(PureError::ConfigError(
                        "encoded attachment exceeds model limits".into(),
                    ));
                }
                STANDARD
                    .decode(base64)
                    .map(Arc::from)
                    .map_err(|_| PureError::ConfigError("invalid attachment Base64".into()))
            }
            AttachmentSource::Resource { reference, access } => access
                .read(reference, self.cancellation.clone())
                .await
                .map_err(|error| PureError::Io(std::io::Error::other(error))),
            AttachmentSource::Url { url } => {
                let url = reqwest::Url::parse(url)
                    .map_err(|_| PureError::ConfigError("invalid attachment URL".into()))?;
                if !matches!(url.scheme(), "http" | "https")
                    || !url.username().is_empty()
                    || url.password().is_some()
                {
                    return Err(PureError::ConfigError(
                        "attachment URL must be HTTP(S) without credentials".into(),
                    ));
                }
                let response = transport::checked(
                    self.client
                        .get(url)
                        .timeout(super::transport_policy::FINITE_REQUEST_TIMEOUT)
                        .send()
                        .await
                        .map_err(reqwest_error_to_pure)?,
                )
                .await?;
                let mut stream = response.bytes_stream();
                let mut bytes = Vec::new();
                while let Some(chunk) = stream.next().await {
                    let chunk = chunk.map_err(reqwest_body_error_to_pure)?;
                    if (bytes.len() as u64).saturating_add(chunk.len() as u64) > maximum {
                        return Err(PureError::ConfigError(
                            "downloaded attachment exceeds model limits".into(),
                        ));
                    }
                    bytes.extend_from_slice(&chunk);
                }
                Ok(bytes.into())
            }
        }
    }

    async fn upload(
        &self,
        input: &AttachmentInput,
        bytes: &[u8],
    ) -> std::result::Result<Option<String>, AttachmentPreparationError> {
        let service = self.upload.ok_or_else(|| {
            AttachmentPreparationError::before_upload(PureError::ConfigError(
                "endpoint declares file upload without a protocol implementation".into(),
            ))
        })?;
        let key = (
            self.fingerprint,
            format!(
                "{}:{}",
                service.cache_revision,
                hex::encode(Sha256::digest(bytes))
            ),
        );
        {
            let mut cache = self.session.uploaded_files.lock().await;
            match cache.get(&key) {
                Some(UploadState::Ready { id, expires_at }) if *expires_at > self.now.saturating_add(60) => return Ok(Some(id.clone())),
                Some(UploadState::Unsupported) => return Ok(None),
                Some(UploadState::Pending) => return Err(AttachmentPreparationError {
                    source: PureError::HttpError("previous attachment upload outcome is unknown; start a new model session before uploading again".into()),
                    replay_safe: false,
                }),
                _ => {}
            }
            cache.insert(key.clone(), UploadState::Pending);
        }
        let uploaded = (service.upload)(pl_model_wire::files::FileUploadRequest {
            client: self.client,
            endpoint: self.endpoint,
            model_headers: &self.model.extra.binding.request.headers,
            input,
            bytes,
            now: self.now,
        })
        .await;
        let uploaded = match uploaded {
            Ok(Some(uploaded)) => uploaded,
            Ok(None) => {
                self.session
                    .uploaded_files
                    .lock()
                    .await
                    .insert(key, UploadState::Unsupported);
                return Ok(None);
            }
            Err(error) => {
                let replay_safe = matches!(error.outcome, UploadFailureOutcome::Rejected);
                if replay_safe {
                    self.session.uploaded_files.lock().await.remove(&key);
                }
                return Err(AttachmentPreparationError {
                    source: error.source,
                    replay_safe,
                });
            }
        };
        self.session.uploaded_files.lock().await.insert(
            key,
            UploadState::Ready {
                id: uploaded.id.clone(),
                expires_at: uploaded.expires_at,
            },
        );
        Ok(Some(uploaded.id))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::completion::AttachmentModality;
    use pl_model_wire::files::{FileUploadFailure, FileUploadService};
    use pl_protocol::{ProviderFailure, ProviderFailureKind, RetryDisposition};
    use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
    use serde_json::json;

    const FILE: &[u8] = b"fixture attachment";
    static LOOPBACK_UPLOAD: FileUploadService = FileUploadService {
        id: pl_model_wire::protocol::FileUploadCapability::from_static("loopback-upload"),
        cache_revision: "loopback",
        upload: |request| {
            Box::pin(async move {
                // The fixture owns submission outcome. The Runtime only consumes the typed result.
                let mut body = b"--fixture\r\nContent-Disposition: form-data; name=\"purpose\"\r\n\r\nuser_data\r\n--fixture\r\nContent-Disposition: form-data; name=\"file\"; filename=\"fixture.txt\"\r\nContent-Type: text/plain\r\n\r\n".to_vec();
                body.extend_from_slice(request.bytes);
                body.extend_from_slice(b"\r\n--fixture--\r\n");
                let response = request
                    .client
                    .post(format!("{}/files", request.endpoint.base_url))
                    .header("content-type", "multipart/form-data; boundary=fixture")
                    .body(body)
                    .send()
                    .await
                    .unwrap();
                let status = response.status().as_u16();
                if status == 200 {
                    let record: serde_json::Value = response.json().await.unwrap();
                    return Ok(Some(pl_model_wire::files::UploadedFile {
                        id: record["id"].as_str().unwrap().into(),
                        expires_at: request.now + 3600,
                    }));
                }
                let (kind, outcome) = match status {
                    429 => (
                        ProviderFailureKind::RateLimit,
                        UploadFailureOutcome::Rejected,
                    ),
                    503 => (
                        ProviderFailureKind::ServiceBusy,
                        UploadFailureOutcome::Unknown,
                    ),
                    _ => panic!("unexpected fixture response {status}"),
                };
                let mut failure = ProviderFailure::new(
                    kind,
                    "upload refused by fixture",
                    RetryDisposition::Retryable {
                        retry_after_ms: Some(0),
                    },
                )
                .with_retry_deadline(std::time::Instant::now());
                failure.http_status = Some(status);
                Err(FileUploadFailure {
                    source: failure.into(),
                    outcome,
                })
            })
        },
    };

    fn file_response(reply: Reply) -> Step {
        Step::exact(
            Protocol::Files,
            json!({"purpose":"user_data", "file":{
                "filename":"fixture.txt", "mime_type":"text/plain", "sha256":hex::encode(Sha256::digest(FILE)), "purpose_precedes_file":true,
            }}),
            reply,
        )
    }

    fn attachment_runtime(fixture: &FixtureServer) -> crate::runtime::ModelRuntime {
        use crate::model::{
            MediaRepresentation, MediaWireFormat, ModelInputCapability, ModelInputSource,
            ModelMediaInputProfile, ModelTransportProfile,
        };
        let mut endpoint = pl_model_openai::endpoint::endpoint(Some(fixture.base_url()));
        endpoint.service_capabilities.files = LOOPBACK_UPLOAD.id.clone();
        let mut model = ModelDefinition::compatible("model");
        model
            .extra
            .capabilities
            .input
            .push(ModelInputCapability::media(
                ModelModality::File,
                vec![ModelInputSource::Local],
            ));
        model
            .extra
            .binding
            .set_transport(ModelTransportProfile::responses_http());
        model.extra.binding.request.media = vec![ModelMediaInputProfile {
            modality: ModelModality::File,
            wire: MediaWireFormat::ResponsesInputFile,
            first_send: vec![MediaRepresentation::ProviderFile],
            replay: vec![MediaRepresentation::ProviderFile],
        }];
        crate::runtime::ModelRuntime::bind(
            "fixture",
            endpoint,
            model,
            &pl_model_openai_wire::OPENAI_WIRE_CODEC,
            pl_model_openai::adapter::ADAPTER.error_policy,
            Some(&LOOPBACK_UPLOAD),
        )
        .unwrap()
    }

    fn attachment_request(prompt: &str) -> CompletionRequest {
        use crate::completion::{ContentPart, Message, MessageContent, MessageRole};
        CompletionRequest::builder()
            .messages(vec![Message {
                role: MessageRole::User,
                content: MessageContent::new(vec![
                    ContentPart::Text {
                        text: prompt.into(),
                    },
                    ContentPart::Attachment {
                        attachment_id: "file".into(),
                        modality: AttachmentModality::File,
                        media_type: "text/plain".into(),
                        filename: Some("fixture.txt".into()),
                    },
                ]),
                presentation: Default::default(),
                reasoning_content: None,
                tool_calls: None,
                tool_result: None,
                metadata: Default::default(),
            }])
            .attachments(vec![AttachmentInput {
                attachment_id: "file".into(),
                modality: AttachmentModality::File,
                media_type: "text/plain".into(),
                filename: Some("fixture.txt".into()),
                source: AttachmentSource::Bytes {
                    bytes: Arc::from(FILE),
                },
            }])
            .build()
    }

    #[tokio::test]
    async fn unknown_upload_outcome_keeps_pending_and_refuses_a_second_post() {
        use crate::runtime::{
            ModelInvocationContext, ModelRecoveryStopReason, invocation::InvocationReport,
        };
        let fixture = FixtureServer::start(vec![file_response(Reply::HttpError {
            status: 503,
            code: "server_error".into(),
            message: "unknown upload outcome".into(),
        })])
        .await
        .unwrap();
        let runtime = attachment_runtime(&fixture);
        let session = ModelSession::default();
        let mut report = InvocationReport::default();
        let error = runtime
            .complete_with_report(
                attachment_request("inspect"),
                ModelInvocationContext::in_memory(session.clone()),
                &mut report,
            )
            .await
            .unwrap_err();
        let upstream = error.source.provider_failure_ref().unwrap();
        assert_eq!(upstream.kind, ProviderFailureKind::ServiceBusy);
        assert!(upstream.retry.is_retryable());
        assert_eq!(report.stop, Some(ModelRecoveryStopReason::SideEffects));
        assert!(
            runtime
                .complete(
                    attachment_request("inspect"),
                    ModelInvocationContext::in_memory(session.clone())
                )
                .await
                .is_err()
        );
        session.close().await.unwrap();
        assert_eq!(fixture.finish().await.unwrap().len(), 1);
    }

    #[tokio::test]
    async fn rejected_upload_shares_the_inference_retry_budget_and_keeps_the_ready_file() {
        use crate::runtime::{
            ModelInvocationContext, ModelRecoveryStopReason, invocation::InvocationReport,
        };
        let mut steps = (0..4)
            .map(|_| {
                file_response(Reply::HttpError {
                    status: 429,
                    code: "rate_limit_exceeded".into(),
                    message: "confirmed rejection".into(),
                })
            })
            .collect::<Vec<_>>();
        steps.push(file_response(Reply::Json(json!({"id":"file-once"}))));
        for index in 5..7 {
            steps.push(Step::prompt(Protocol::ResponsesHttp, "inspect", index, Reply::Sse(vec![json!({
                "type":"error", "error":{"code":"upstream_error", "message":"retryable", "retry_after_ms":0},
            })])));
        }
        steps.push(Step::prompt(
            Protocol::ResponsesHttp,
            "next",
            7,
            Reply::Sse(responses_text("complete", "success", "model")),
        ));
        let fixture = FixtureServer::start(steps).await.unwrap();
        let runtime = attachment_runtime(&fixture);
        let session = ModelSession::default();
        let mut report = InvocationReport::default();
        let error = runtime
            .complete_with_report(
                attachment_request("inspect"),
                ModelInvocationContext::in_memory(session.clone()),
                &mut report,
            )
            .await
            .unwrap_err();
        assert!(
            error
                .source
                .provider_failure_ref()
                .unwrap()
                .retry
                .is_retryable()
        );
        assert_eq!(report.stop, Some(ModelRecoveryStopReason::BudgetExhausted));
        assert_eq!(report.retry, Some(5));
        let response = runtime
            .complete(
                attachment_request("next"),
                ModelInvocationContext::in_memory(session.clone()),
            )
            .await
            .unwrap();
        assert_eq!(response.content.as_deref(), Some("complete"));
        assert_eq!(response.orchestration.transport_attempts, 1);
        session.close().await.unwrap();
        let seen = fixture.finish().await.unwrap();
        assert_eq!(seen.len(), 8);
        assert_eq!(
            seen.iter()
                .filter(|request| request.path.ends_with("/files"))
                .count(),
            5
        );
        for request in &seen[5..] {
            assert_eq!(
                request.body["input"][0]["content"][1]["file_id"],
                "file-once"
            );
        }
    }

    static INCOMPLETE_UPLOAD: FileUploadService = FileUploadService {
        id: pl_model_wire::protocol::FileUploadCapability::from_static("incomplete-upload"),
        cache_revision: "fixture",
        upload: |_| {
            Box::pin(async {
                let mut failure = ProviderFailure::new(
                    ProviderFailureKind::Transport,
                    "response body closed",
                    RetryDisposition::Retryable {
                        retry_after_ms: None,
                    },
                );
                failure.http_status = Some(200);
                Err(FileUploadFailure {
                    source: failure.into(),
                    outcome: UploadFailureOutcome::Unknown,
                })
            })
        },
    };

    #[tokio::test]
    async fn successful_upload_status_with_incomplete_body_keeps_the_pending_identity() {
        let bytes: Arc<[u8]> = Arc::from(b"file contents".as_slice());
        let model = ModelDefinition::compatible("fixture");
        let endpoint =
            pl_model_openai::endpoint::compatible_endpoint("fixture", "http://127.0.0.1");
        let client = reqwest::Client::new();
        let session = ModelSession::default();
        let input = AttachmentInput {
            attachment_id: "file-1".into(),
            modality: AttachmentModality::File,
            media_type: "text/plain".into(),
            filename: None,
            source: AttachmentSource::Bytes {
                bytes: bytes.clone(),
            },
        };
        let backend = AttachmentBackend {
            upload: Some(&INCOMPLETE_UPLOAD),
            endpoint: &endpoint,
            model: &model,
            client: &client,
            session: &session,
            fingerprint: 1,
            now: 0,
            cancellation: Default::default(),
        };

        let error = backend.upload(&input, &bytes).await.unwrap_err();
        let failure = error.source.provider_failure_ref().unwrap();
        assert_eq!(failure.http_status, Some(200));
        assert_eq!(
            failure.retry,
            RetryDisposition::Retryable {
                retry_after_ms: None
            }
        );
        assert!(!error.replay_safe);
        let repeated = backend.upload(&input, &bytes).await.unwrap_err();
        assert!(
            matches!(repeated.source, PureError::HttpError(message) if message.contains("outcome is unknown"))
        );
    }
}

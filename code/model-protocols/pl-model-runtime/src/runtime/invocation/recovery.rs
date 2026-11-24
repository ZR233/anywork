//! Shared retry budget, replay safety, fallback and terminal accounting.
use super::OpenAiTransport;
use super::timing::InferenceTimer;
use crate::completion::{CompletionFailure, CompletionRequest, CompletionResponse};
use crate::runtime::transport_policy::{
    MODEL_MAX_RETRIES, RESPONSES_WEBSOCKET_MAX_RETRIES, model_request_retry_delay,
};
use crate::runtime::{ModelInvocationContext, ModelRuntime};
use pl_protocol::PureError;

impl ModelRuntime {
    pub(super) async fn complete_inner(
        &self,
        request: CompletionRequest,
        context: ModelInvocationContext,
        mut current: Option<&mut crate::runtime::current::CurrentProducer>,
    ) -> std::result::Result<CompletionResponse, CompletionFailure> {
        crate::runtime::context::validate(
            self.model.extra.binding.transport.protocol,
            &request.input,
        )?;
        let admission = async {
            if let Some(cancellation) = &context.cancellation {
                tokio::select! {
                    biased;
                    _ = cancellation.cancelled() => Err(CompletionFailure::cancelled(
                        PureError::LlmError("model invocation cancelled before admission".into()),
                        Box::default(),
                    )),
                    lease = context.session.admit() => lease.map_err(CompletionFailure::from),
                }
            } else {
                context
                    .session
                    .admit()
                    .await
                    .map_err(CompletionFailure::from)
            }
        };
        let _session_lease = if let Some(current) = current.as_deref_mut() {
            current.wait(admission, None).await?
        } else {
            admission.await?
        };
        let mut request = crate::runtime::context::project_request(
            &self.endpoint,
            &self.model,
            &self.account_id,
            request,
        )?;
        let original_trace = context.trace.clone();
        let retry_jitter_key = original_trace
            .as_ref()
            .map(|trace| trace.inference_id.as_str())
            .unwrap_or(self.model.base.slug.as_str())
            .to_string();
        let mut attempt_number = 0_u32;
        let mut transport_attempts = 0_u64;
        let mut attachments_prepared = false;
        let transport_metrics_before = context.session.orchestration_snapshot();
        let mut http_fallbacks = 0_u64;
        let mut refreshed_attachments = false;
        let mut last_model_observation = None;
        // This generation remains the last actually attempted request throughout retry
        // preparation/backoff. A cancellation must not replace its facts with an unsent attempt.
        let mut retry_failure: Option<CompletionFailure> = None;

        loop {
            if context
                .cancellation
                .as_ref()
                .is_some_and(|token| token.is_cancelled())
            {
                context.close_live_usage();
                let mut cancelled = retry_failure.take().unwrap_or_else(|| {
                    CompletionFailure::cancelled(
                        PureError::LlmError("model invocation cancelled".into()),
                        Box::default(),
                    )
                    .with_optional_model_observation(last_model_observation)
                });
                cancelled.source =
                    Box::new(PureError::LlmError("model invocation cancelled".into()));
                cancelled.cancelled = true;
                return Err(cancelled);
            }
            let transport = self.active_transport(&context.session, &context.purpose);
            let max_retries = MODEL_MAX_RETRIES;
            let preparation = if attachments_prepared {
                Ok(())
            } else {
                let preparation = self.prepare_attachments(&mut request, &context);
                if let Some(current) = current.as_deref_mut() {
                    current.wait(preparation, None).await
                } else {
                    preparation.await
                }
            };
            let attempted_stream = preparation.is_ok();
            let mut attempt_request = request.clone();
            if attempt_number > 0 {
                for media in &mut attempt_request.prepared_content {
                    media.sources.retain(|source| {
                        !matches!(
                            source,
                            crate::completion::AttachmentRepresentation::RemoteUrl { .. }
                        )
                    });
                }
            }
            let mut trace = original_trace.clone();
            if attempt_number > 0
                && let Some(trace) = trace.as_mut()
            {
                let original_inference_id = original_trace
                    .as_ref()
                    .map(|trace| trace.inference_id.as_str())
                    .unwrap_or(trace.inference_id.as_str());
                let transport = transport.trace_label();
                trace.inference_id =
                    format!("{original_inference_id}-{transport}-retry-{attempt_number}");
            }
            let request_started_at = self.clock.unix_seconds()?;
            let (result, retry_allowed, inference_timer) = match preparation {
                Ok(()) => {
                    drop(retry_failure.take());
                    attachments_prepared = true;
                    transport_attempts += 1;
                    let inference_timer = InferenceTimer::start();
                    let (result, retry_allowed) = self
                        .run_stream_attempt(
                            attempt_request,
                            &context,
                            trace,
                            &inference_timer,
                            current.as_deref_mut(),
                            (transport_attempts - 1) as u32,
                        )
                        .await;
                    (result, retry_allowed, Some(inference_timer))
                }
                Err(error) if error.is_cancelled() && retry_failure.is_some() => {
                    let mut previous = retry_failure.take().expect("checked previous attempt");
                    previous.source = error.source;
                    previous.cancelled = true;
                    return Err(previous);
                }
                Err(error) => (Err(error), true, None),
            };
            let mut error = match result {
                Ok(mut response) => {
                    let transport_metrics_after = context.session.orchestration_snapshot();
                    response.orchestration.transport_attempts = transport_attempts;
                    response.orchestration.continuation_attempts = transport_metrics_after
                        .continuation_attempts
                        .saturating_sub(transport_metrics_before.continuation_attempts);
                    response.orchestration.continuation_used = transport_metrics_after
                        .continuation_used
                        .saturating_sub(transport_metrics_before.continuation_used);
                    response.orchestration.continuation_invalid = transport_metrics_after
                        .continuation_invalid
                        .saturating_sub(transport_metrics_before.continuation_invalid);
                    response.orchestration.http_fallbacks = http_fallbacks;
                    response.timing = inference_timer.and_then(|timer| timer.finish());
                    response.accounting = self.model.extra.pricing.account(
                        response.accounting.usage,
                        self.pricing_mode,
                        request_started_at,
                    );
                    return Ok(response);
                }
                Err(mut error) => {
                    error.timing = inference_timer.and_then(|timer| timer.finish());
                    // 失败/取消的尝试不产生任何可确认的速度：在把它交给任何终态发布者或重试
                    // 换代之前，先整组撤销 live 用量与耗时，已收到的内容与回执不受影响。
                    context.close_live_usage();
                    error.accounting = Box::new(self.model.extra.pricing.account(
                        error.accounting.usage,
                        self.pricing_mode,
                        request_started_at,
                    ));
                    error
                }
            };
            last_model_observation = error
                .model_observation()
                .cloned()
                .or(last_model_observation);
            if error.is_cancelled() {
                return Err(error);
            }
            if !retry_allowed {
                if transport == OpenAiTransport::ResponsesWebSocket
                    && error.is_transient_model_transport()
                    && self.supports_http_fallback()
                {
                    let connection_key = self.connection_fingerprint();
                    let activation = context
                        .session
                        .activate_responses_http_fallback(connection_key);
                    let activated = if let Some(current) = current.as_deref_mut() {
                        current.wait(activation, None).await
                    } else {
                        activation.await
                    };
                    let (provider_code, http_status) =
                        error.transient_model_metadata().unwrap_or((None, None));
                    tracing::warn!(
                        provider = %self.endpoint.name,
                        from_transport = transport.label(),
                        fallback_transport = OpenAiTransport::Http.label(),
                        fallback_reason = "partialStreamFailure",
                        fallback_scope = "nextTurn",
                        fallback_activated = activated,
                        provider_code,
                        http_status,
                        error_bytes = error.to_string().len(),
                        "Responses WebSocket 已产生事件后失败，当前请求不重放，后续请求切换到 HTTP"
                    );
                }
                return Err(error);
            }
            let recovery = error
                .source
                .provider_failure_ref()
                .map(|failure| failure.context.recovery)
                .unwrap_or_default();
            if recovery == pl_protocol::ProviderRecovery::HttpFallback
                && transport == OpenAiTransport::ResponsesWebSocket
                && self.supports_http_fallback()
                && attempt_number < max_retries
            {
                let activation = context
                    .session
                    .activate_responses_http_fallback(self.connection_fingerprint());
                let activated = if let Some(current) = current.as_deref_mut() {
                    current.wait(activation, None).await
                } else {
                    activation.await
                };
                if activated {
                    http_fallbacks += 1;
                }
                attempt_number += 1;
                if let Err(cause) = context.begin_retry(&mut error) {
                    return Err(error.with_source(cause));
                }
                retry_failure = Some(error);
                continue;
            }
            if recovery == pl_protocol::ProviderRecovery::RefreshAttachments
                && !refreshed_attachments
                && attempt_number < max_retries
                && request.prepared_content.iter().any(|part| {
                    part.sources.iter().any(|source| {
                        matches!(
                            source,
                            crate::completion::AttachmentRepresentation::ProviderFile { .. }
                        )
                    })
                })
            {
                attempt_number += 1;
                if let Err(cause) = context.begin_retry(&mut error) {
                    return Err(error.with_source(cause));
                }
                let locking = context.session.uploaded_files.lock();
                let mut files = if let Some(current) = current.as_deref_mut() {
                    current.wait(locking, None).await
                } else {
                    locking.await
                };
                files.retain(|(fingerprint, _), _| *fingerprint != self.connection_fingerprint());
                drop(files);
                attachments_prepared = false;
                refreshed_attachments = true;
                retry_failure = Some(error);
                continue;
            }
            if !error.is_transient_model_transport() {
                return Err(error);
            }

            if attempt_number >= max_retries {
                if let Some(progress) = &context.progress {
                    progress.finish_recovery(pl_core::model::ModelRecoveryPhase::Exhausted);
                }
                return Err(error);
            }
            // WS 重连一次仍失败后切换 HTTP；切换不重置逻辑请求的总预算。
            if transport == OpenAiTransport::ResponsesWebSocket
                && attempted_stream
                && attempt_number >= RESPONSES_WEBSOCKET_MAX_RETRIES
                && self.supports_http_fallback()
            {
                let activation = context
                    .session
                    .activate_responses_http_fallback(self.connection_fingerprint());
                let activated = if let Some(current) = current.as_deref_mut() {
                    current.wait(activation, None).await
                } else {
                    activation.await
                };
                if activated {
                    http_fallbacks = http_fallbacks.saturating_add(1);
                }
            }
            attempt_number += 1;
            if let Err(cause) = context.begin_retry(&mut error) {
                return Err(error.with_source(cause));
            }
            let delay = model_request_retry_delay(
                attempt_number,
                error.retry_after_ms(),
                &retry_jitter_key,
            );
            let (provider_code, http_status) =
                error.transient_model_metadata().unwrap_or((None, None));
            tracing::warn!(
                provider = %self.endpoint.name,
                transport = transport.label(),
                retry_number = attempt_number,
                max_retries,
                delay_ms = delay.as_millis(),
                provider_code,
                http_status,
                error_bytes = error.to_string().len(),
                "模型连接中断，将在统一预算内重试当前请求"
            );
            let backoff = async {
                if let Some(token) = &context.cancellation {
                    tokio::select! {
                        _ = tokio::time::sleep(delay) => {},
                        _ = token.cancelled() => {},
                    }
                } else {
                    tokio::time::sleep(delay).await;
                }
            };
            if let Some(current) = current.as_deref_mut() {
                current.wait(backoff, None).await;
            } else {
                backoff.await;
            }
            retry_failure = Some(error);
        }
    }
}

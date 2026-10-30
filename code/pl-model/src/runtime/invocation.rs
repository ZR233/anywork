use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use futures::StreamExt;
use pl_protocol::trace::{AgentEventSender, TraceEventSink};
use pl_protocol::{InferenceModelObservation, InferenceTiming, PureError, Result};

use super::{ModelSession, responses_websocket, wire_capture};

use crate::completion::stream::{CompletionEventStream, StreamCollectContext};
use crate::completion::{
    CompletionFailure, CompletionRequest, CompletionResponse, CompletionTraceContext,
};
use crate::model::capabilities::ModelCapabilities;
use crate::model::info::ModelInfo;
use crate::protocol::{ConnectionMode, ProtocolEndpoint, WireApi};
use crate::protocol::{ProtocolAdaptation, ProtocolAdapter};
use crate::runtime::openai::OpenAiRequestBody;
use crate::runtime::transport_policy::{
    MODEL_MAX_RETRIES, RESPONSES_WEBSOCKET_IDLE_TIMEOUT, RESPONSES_WEBSOCKET_MAX_RETRIES,
    model_request_retry_delay,
};

struct OpenedCompletionStream {
    events: CompletionEventStream,
    sent_model: String,
    idle_timeout: Option<Duration>,
}
/// 单次模型调用的运行期上下文。
///
/// 连接 continuation 属于 [`ModelSession`]；trace、事件输出和 prompt cache key
/// 只在当前调用内有效，不进入 canonical completion request。
#[derive(Debug, Clone)]
pub struct ModelInvocationContext {
    session: ModelSession,
    event_tx: AgentEventSender,
    trace: Option<CompletionTraceContext>,
    trace_sink: Option<Arc<dyn TraceEventSink>>,
    cancellation: Option<tokio_util::sync::CancellationToken>,
    prompt_cache_key: Option<String>,
    progress: Option<pl_core::model::ModelProgressSender>,
}

impl ModelInvocationContext {
    /// Binds core request identities for wire diagnostics without a parallel event sink.
    pub fn with_trace_metadata(mut self, trace: CompletionTraceContext) -> Self {
        self.trace = Some(trace);
        self
    }

    pub(super) fn with_progress(
        mut self,
        progress: Option<pl_core::model::ModelProgressSender>,
    ) -> Self {
        self.progress = progress;
        self
    }

    /// Withdraws this generation's live usage and response time as one group.
    ///
    /// Used by every outer failure, cancellation and exhausted-retry path that never produced a
    /// `Failed` event, so no published snapshot can pair pre-failure tokens with a failure clock.
    fn close_live_usage(&self) {
        if let Some(progress) = &self.progress {
            progress.close_live_usage();
        }
    }

    pub(super) fn prompt_cache_key(&self) -> Option<String> {
        self.prompt_cache_key.clone()
    }

    pub(super) fn with_session(mut self, session: ModelSession) -> Self {
        self.session = session;
        self
    }

    pub fn new(session: ModelSession) -> Self {
        let (event_tx, _) = tokio::sync::broadcast::channel(16);
        Self {
            session,
            event_tx,
            trace: None,
            trace_sink: None,
            cancellation: None,
            prompt_cache_key: None,
            progress: None,
        }
    }

    /// Attaches an event consumer when the host needs streaming projections.
    pub fn with_events(mut self, event_tx: AgentEventSender) -> Self {
        self.event_tx = event_tx;
        self
    }

    pub fn with_trace(
        mut self,
        trace: CompletionTraceContext,
        sink: Arc<dyn TraceEventSink>,
    ) -> Self {
        self.trace = Some(trace);
        self.trace_sink = Some(sink);
        self
    }

    pub fn with_cancellation(
        mut self,
        cancellation: Option<tokio_util::sync::CancellationToken>,
    ) -> Self {
        self.cancellation = cancellation;
        self
    }

    pub fn with_prompt_cache_key(mut self, prompt_cache_key: Option<String>) -> Self {
        self.prompt_cache_key = prompt_cache_key;
        self
    }
    fn begin_retry(&self, error: &mut CompletionFailure) -> Result<()> {
        let sender = self
            .progress
            .as_ref()
            .expect("invocation owns its observation");
        let message = error.to_string();
        sender
            .charge_output(
                sender
                    .charged_output()
                    .saturating_add(message.len() as u64)
                    .saturating_add(256),
            )
            .map_err(|error| PureError::MemoryError(error.to_string()))?;
        sender
            .begin_recovery(MODEL_MAX_RETRIES, Arc::from(message))
            .map_err(|error| PureError::Protocol(error.to_string()))?;
        // These parts now belong solely to the retained failed generation. A
        // cancellation/refresh failure before the next send must not relabel
        // them as that unsent generation's current presentation.
        error.presentation_items.clear();
        Ok(())
    }
}

impl Default for ModelInvocationContext {
    fn default() -> Self {
        Self::new(ModelSession::default())
    }
}

#[derive(Clone)]
pub(crate) struct InvocationRunner {
    account_id: String,
    endpoint: ProtocolEndpoint,
    pub(super) http_client: reqwest::Client,
    model: ModelInfo,
    native_body: serde_json::Map<String, serde_json::Value>,
    purpose: InvocationPurpose,
    pub(crate) clock: Arc<dyn super::InferenceClock>,
    pub(crate) pricing_mode: pl_protocol::PricingMode,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum InvocationPurpose {
    Completion,
    RemoteCompaction,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum OpenAiTransport {
    ResponsesWebSocket,
    Http,
}

impl OpenAiTransport {
    fn label(self) -> &'static str {
        match self {
            Self::ResponsesWebSocket => "WebSocket",
            Self::Http => "HTTP",
        }
    }

    fn trace_label(self) -> &'static str {
        match self {
            Self::ResponsesWebSocket => "ws",
            Self::Http => "http",
        }
    }
}

#[derive(Debug, Clone)]
struct InferenceTimer {
    started_at: tokio::time::Instant,
    observation: Arc<Mutex<TimingObservation>>,
}

#[derive(Debug, Default)]
struct TimingObservation {
    first_output: Option<(u64, pl_protocol::FirstOutputSource)>,
    terminal_millis: Option<u64>,
}

impl InferenceTimer {
    fn start() -> Self {
        Self {
            started_at: tokio::time::Instant::now(),
            observation: Arc::new(Mutex::new(TimingObservation::default())),
        }
    }

    fn observe(&self, event: &crate::completion::stream::event::ModelStreamEvent) {
        // Time and provenance publish as one observation, including across cloned stream owners.
        let mut observation = self
            .observation
            .lock()
            .expect("timing observation poisoned");
        if observation.terminal_millis.is_some() {
            return;
        }
        if matches!(
            event,
            crate::completion::stream::event::ModelStreamEvent::Completed { .. }
                | crate::completion::stream::event::ModelStreamEvent::Failed { .. }
        ) {
            observation.terminal_millis = Some(duration_millis(self.started_at.elapsed()));
            return;
        }
        if observation.first_output.is_none()
            && let Some(source) = event.first_output_source()
        {
            observation.first_output = Some((duration_millis(self.started_at.elapsed()), source));
        }
    }

    /// 本 attempt 起点到当前时刻（已到终态则到终态）的单调总响应耗时。
    fn response_millis(&self) -> u64 {
        self.observation
            .lock()
            .expect("timing observation poisoned")
            .terminal_millis
            .unwrap_or_else(|| duration_millis(self.started_at.elapsed()))
    }

    /// Freeze non-event termination before failure projection, tracing or retry backoff.
    fn mark_terminal(&self) {
        self.observation
            .lock()
            .expect("timing observation poisoned")
            .terminal_millis
            .get_or_insert_with(|| duration_millis(self.started_at.elapsed()));
    }

    /// 归一化终态到达后的耗时事实；未观察到首内容只让首字相关字段保持未知。
    ///
    /// 总响应耗时始终是消费方确认的终态边界，因此它不依赖首字；仅当首字晚于已记录的终态值
    /// 这类不一致边界出现时，才把首字整组视为未知，而不是伪造负的首字后耗时。
    fn finish(&self) -> Option<InferenceTiming> {
        let observation = self
            .observation
            .lock()
            .expect("timing observation poisoned");
        let response_millis = observation.terminal_millis?;
        let (ttft_millis, decode_millis, first_output_source) = match observation.first_output {
            Some((first, source)) if first <= response_millis => {
                (Some(first), Some(response_millis - first), source)
            }
            _ => (None, None, pl_protocol::FirstOutputSource::Unobserved),
        };
        Some(InferenceTiming {
            first_output_source,
            ttft_millis,
            decode_millis,
            response_millis,
        })
    }
}

impl std::fmt::Debug for InvocationRunner {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter
            .debug_struct("InvocationRunner")
            .field("account", &self.account_id)
            .field("model", &self.model.model_id)
            .field("transport", &self.model.binding.transport)
            .field("pricing_mode", &self.pricing_mode)
            .finish_non_exhaustive()
    }
}

impl InvocationRunner {
    /// 使用已解析 endpoint 与单个模型构造运行时。
    /// 使用稳定 Provider 实例 ID、已解析 endpoint 与单个模型构造运行时。
    pub fn new_with_account_id(
        account_id: impl Into<String>,
        endpoint: ProtocolEndpoint,
        model: ModelInfo,
    ) -> Result<Self> {
        model
            .validate()
            .map_err(|error| PureError::ConfigError(error.to_string()))?;
        let account_id = account_id.into();
        if account_id.trim().is_empty() {
            return Err(PureError::ConfigError(
                "account id cannot be empty".to_string(),
            ));
        }
        let http_client = reqwest::Client::builder()
            .retry(reqwest::retry::never())
            .connect_timeout(super::transport_policy::HTTP_CONNECT_TIMEOUT)
            .read_timeout(super::transport_policy::HTTP_READ_IDLE_TIMEOUT)
            .build()
            .map_err(|e| PureError::HttpError(e.to_string()))?;

        Ok(Self {
            account_id,
            endpoint,
            http_client,
            model,
            native_body: Default::default(),
            purpose: InvocationPurpose::Completion,
            clock: Arc::new(super::clock::SystemInferenceClock),
            pricing_mode: pl_protocol::PricingMode::Catalog,
        })
    }

    pub(super) fn resolve_base_url(&self) -> String {
        self.endpoint
            .base_url
            .clone()
            .trim_end_matches('/')
            .to_string()
    }
    pub fn endpoint(&self) -> &ProtocolEndpoint {
        &self.endpoint
    }

    pub(crate) fn with_native_body(
        &self,
        body: serde_json::Map<String, serde_json::Value>,
    ) -> Self {
        let mut runner = self.clone();
        runner.native_body = body;
        runner
    }

    pub(super) fn for_compaction(
        &self,
        headers: HashMap<String, String>,
        body: serde_json::Map<String, serde_json::Value>,
    ) -> Self {
        let mut runner = self.with_native_body(body);
        runner.model.binding.transport.default_connection_mode = ConnectionMode::Http;
        runner.model.binding.request.headers = headers;
        runner.purpose = InvocationPurpose::RemoteCompaction;
        runner
    }

    pub fn account_id(&self) -> &str {
        &self.account_id
    }

    pub async fn complete(
        &self,
        request: CompletionRequest,
        mut context: ModelInvocationContext,
    ) -> std::result::Result<CompletionResponse, CompletionFailure> {
        let progress = context
            .progress
            .get_or_insert_with(|| {
                pl_core::model::ModelProgressSender::detached(
                    crate::completion::stream::MAX_COMPLETION_OUTPUT_BYTES as u64,
                )
            })
            .clone();
        // A Thread-owned channel is initialized with its stable turn/attempt live marker. Do not
        // replace it with a default snapshot here: doing so would erase the identity before the
        // first provider event and make a reused invocation look like an unowned observation.
        let caller_cancellation = context.cancellation.take().unwrap_or_default();
        let closing = context.session.closing_token();
        let cancellation = tokio_util::sync::CancellationToken::new();
        context.cancellation = Some(cancellation.clone());
        let invocation = self.complete_inner(request, context);
        tokio::pin!(invocation);
        // Cancellation is cooperative: await the same invocation so its partial
        // accounting and transport guards finish before releasing admission.
        let mut result = tokio::select! {
            biased;
            _ = caller_cancellation.cancelled() => {
                cancellation.cancel();
                invocation.await
            }
            _ = closing.cancelled() => {
                cancellation.cancel();
                invocation.await
            }
            result = &mut invocation => result,
        };
        match &mut result {
            Ok(response) => {
                progress.finish_recovery(pl_core::model::ModelRecoveryPhase::Recovered);
                response.observation = progress.latest().observation().clone();
            }
            Err(error) => {
                let phase = if error.is_cancelled() {
                    pl_core::model::ModelRecoveryPhase::Cancelled
                } else if progress
                    .latest()
                    .observation()
                    .recovery
                    .is_some_and(|status| {
                        status.phase == pl_core::model::ModelRecoveryPhase::Exhausted
                    })
                {
                    pl_core::model::ModelRecoveryPhase::Exhausted
                } else {
                    pl_core::model::ModelRecoveryPhase::Failed
                };
                progress.finish_recovery(phase);
                let latest = progress.latest();
                error.partial_progress = (!latest.is_empty()).then_some(Box::new(latest));
            }
        }
        result
    }

    async fn complete_inner(
        &self,
        request: CompletionRequest,
        context: ModelInvocationContext,
    ) -> std::result::Result<CompletionResponse, CompletionFailure> {
        super::context::validate(self.model.binding.transport.protocol, &request.input)?;
        let _session_lease = if let Some(cancellation) = &context.cancellation {
            tokio::select! {
                biased;
                _ = cancellation.cancelled() => return Err(CompletionFailure::cancelled(
                    PureError::LlmError("model invocation cancelled before admission".into()),
                    Box::default(),
                )),
                lease = context.session.admit() => lease?,
            }
        } else {
            context.session.admit().await?
        };
        let mut request = super::context::project_request(
            &self.endpoint,
            &self.model,
            &self.account_id,
            request,
        )?;
        let original_trace = context.trace.clone();
        let retry_jitter_key = original_trace
            .as_ref()
            .map(|trace| trace.inference_id.as_str())
            .unwrap_or(self.model.model_id.as_str())
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
            let transport = self.active_transport(&context.session);
            let max_retries = MODEL_MAX_RETRIES;
            let preparation = if attachments_prepared {
                Ok(())
            } else {
                self.prepare_attachments(&mut request, &context).await
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
                        .run_stream_attempt(attempt_request, &context, trace, &inference_timer)
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
                    response.accounting = self.model.pricing.account(
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
                    error.accounting = Box::new(self.model.pricing.account(
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
                    let activated = context
                        .session
                        .activate_responses_http_fallback(connection_key)
                        .await;
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
                if context
                    .session
                    .activate_responses_http_fallback(self.connection_fingerprint())
                    .await
                {
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
                context
                    .session
                    .uploaded_files
                    .lock()
                    .await
                    .retain(|(fingerprint, _), _| *fingerprint != self.connection_fingerprint());
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
                let activated = context
                    .session
                    .activate_responses_http_fallback(self.connection_fingerprint())
                    .await;
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
            if let Some(token) = &context.cancellation {
                tokio::select! {
                    _ = tokio::time::sleep(delay) => {},
                    _ = token.cancelled() => {},
                }
            } else {
                tokio::time::sleep(delay).await;
            }
            retry_failure = Some(error);
        }
    }

    async fn prepare_attachments(
        &self,
        request: &mut CompletionRequest,
        context: &ModelInvocationContext,
    ) -> std::result::Result<(), CompletionFailure> {
        let mut candidate = request.clone();
        let prepare = async {
            super::attachments::AttachmentBackend {
                endpoint: &self.endpoint,
                model: &self.model,
                client: &self.http_client,
                session: &context.session,
                fingerprint: self.connection_fingerprint(),
                now: self.clock.unix_seconds()?,
                cancellation: context.cancellation.clone().unwrap_or_default(),
            }
            .prepare(&mut candidate)
            .await
        };
        if let Some(token) = &context.cancellation {
            tokio::select! {
                biased;
                _ = token.cancelled() => return Err(CompletionFailure::cancelled(
                    PureError::LlmError("attachment preparation cancelled".into()), Box::default())),
                result = prepare => result?,
            }
        } else {
            prepare.await?;
        }
        *request = candidate;
        Ok(())
    }

    /// 收集一次尝试；本地工具仅在成功返回后执行，托管工具和已报告使用量的响应不能重放。
    async fn run_stream_attempt(
        &self,
        request: CompletionRequest,
        context: &ModelInvocationContext,
        trace: Option<CompletionTraceContext>,
        inference_timer: &InferenceTimer,
    ) -> (
        std::result::Result<CompletionResponse, CompletionFailure>,
        bool,
    ) {
        let has_hosted_tools = request.tools.iter().any(|tool| match tool {
            pl_protocol::ToolSpec::Function { .. } | pl_protocol::ToolSpec::Custom { .. } => false,
            pl_protocol::ToolSpec::ProgrammaticToolCalling
            | pl_protocol::ToolSpec::WebSearch { .. } => true,
        });
        let is_compaction = self.purpose == InvocationPurpose::RemoteCompaction;
        let (body, mut model_observation) =
            match self.prepare_request_body(request, context.prompt_cache_key.as_deref()) {
                Ok(prepared) => prepared,
                Err(error) => return (Err(error.into()), true),
            };
        let opening = self.stream_events(body, context.session.clone(), trace.clone());
        tokio::pin!(opening);
        let opened = match context.cancellation.as_ref() {
            Some(token) => tokio::select! {
                result = &mut opening => result,
                _ = token.cancelled() => {
                    inference_timer.mark_terminal();
                    return (Err(CompletionFailure::cancelled(
                        PureError::LlmError("model invocation cancelled".into()),
                        Box::default(),
                    ).with_model_observation(model_observation.clone())), false);
                },
            },
            None => opening.await,
        };
        match opened {
            Ok(opened) => {
                model_observation.sent_model = opened.sent_model;
                let replay_unsafe = Arc::new(AtomicBool::new(false));
                let tracked_stream: CompletionEventStream = opened
                    .events
                    .map({
                        let replay_unsafe = Arc::clone(&replay_unsafe);
                        let inference_timer = inference_timer.clone();
                        let mut progress = super::thread_model::progress::ProgressProjection::new(context.progress.clone());
                        move |event| {
                            if let Ok(event) = &event
                                && (has_hosted_tools
                                    || (is_compaction && matches!(event,
                                        crate::completion::stream::event::ModelStreamEvent::ResponsesContextItem { .. }))
                                    || matches!(event,
                                    crate::completion::stream::event::ModelStreamEvent::Usage(_)
                                    | crate::completion::stream::event::ModelStreamEvent::Completed { .. }))
                            {
                                replay_unsafe.store(true, Ordering::Release);
                            }
                            if let Ok(event) = &event {
                                inference_timer.observe(event);
                                // 终态事件先撤销 live 用量，再考虑发布耗时：失败尝试绝不能
                                // 先发布一个「失败前的词元 + 失败时钟」的完整 pair。
                                progress.observe(event)?;
                                progress.observe_response_millis(inference_timer.response_millis());
                            } else {
                                // 传输层直接以错误结束这次流，没有经过 Failed 事件。
                                inference_timer.mark_terminal();
                                progress.close_live_usage();
                            }
                            event
                        }
                    })
                    .boxed();
                let on_stream_end = || inference_timer.mark_terminal();
                let result =
                    crate::completion::stream::collect_completion_event_stream_with_idle_timeout(
                        tracked_stream,
                        StreamCollectContext {
                            event_tx: &context.event_tx,
                            trace,
                            trace_sink: context.trace_sink.clone(),
                            cancellation: context.cancellation.clone(),
                            model_observation: Some(model_observation),
                            on_stream_end: &on_stream_end,
                        },
                        opened.idle_timeout,
                    )
                    .await;
                let retry_allowed = !replay_unsafe.load(Ordering::Acquire);
                (result, retry_allowed)
            }
            Err(error) => {
                inference_timer.mark_terminal();
                (
                    Err(CompletionFailure::from(error).with_model_observation(model_observation)),
                    true,
                )
            }
        }
    }

    fn prepare_request_body(
        &self,
        request: CompletionRequest,
        prompt_cache_key: Option<&str>,
    ) -> Result<(OpenAiRequestBody, InferenceModelObservation)> {
        let request = super::context::project_request(
            &self.endpoint,
            &self.model,
            &self.account_id,
            request,
        )?;
        let mut body = self.protocol().build_request(
            self.model.binding.transport.protocol,
            &request,
            &self.model,
            prompt_cache_key,
            self.endpoint.chatgpt_session.is_some(),
        )?;
        let original = self.endpoint.chatgpt_session.as_ref().map(|_| body.clone());
        body.apply_native_options(&self.native_body);
        body.reject_reserved_instruction_channel()?;
        if let Some(original) = &original {
            body.validate_chatgpt(original)?;
        }
        if self.purpose == InvocationPurpose::RemoteCompaction {
            body.prepare_compaction();
        }
        let sent_model = body.sent_model()?;
        Ok((
            body,
            InferenceModelObservation {
                configured_model: self.model.model_id.clone(),
                sent_model,
                reported_model: None,
            },
        ))
    }

    fn active_transport(&self, session: &ModelSession) -> OpenAiTransport {
        let transport = &self.model.binding.transport;
        let connection_key = self.connection_fingerprint();
        if transport.protocol == WireApi::Responses
            && transport.default_connection_mode == ConnectionMode::WebSocket
            && !session.uses_responses_http_fallback(connection_key)
        {
            return OpenAiTransport::ResponsesWebSocket;
        }
        OpenAiTransport::Http
    }

    /// The selected vendor protocol adapter for this route.
    fn protocol(&self) -> ProtocolAdapter {
        ProtocolAdapter::of(self.endpoint.protocol)
    }

    fn supports_http_fallback(&self) -> bool {
        self.model
            .binding
            .transport
            .supported_connection_modes
            .contains(&ConnectionMode::Http)
    }

    fn stream_events(
        &self,
        body: OpenAiRequestBody,
        session: ModelSession,
        trace: Option<CompletionTraceContext>,
    ) -> impl std::future::Future<Output = Result<OpenedCompletionStream>> + Send {
        let http_client = self.http_client.clone();
        let api_base = self.resolve_base_url();
        let endpoint = self.endpoint.clone();
        let model_info = self.model.clone();
        let protocol = self.protocol();
        let wire_api = model_info.binding.transport.protocol;
        let connection_key = self.connection_fingerprint();
        let transport = self.active_transport(&session);
        async move {
            let expected_sent_model = body.sent_model()?;
            if endpoint.chatgpt_session.is_some()
                && (transport != OpenAiTransport::Http || wire_api != WireApi::Responses)
            {
                return Err(PureError::ConfigError(
                    crate::protocol::chatgpt::ChatGptAuthError::UnsupportedResource.to_string(),
                ));
            }
            let token = endpoint.resolve_bearer_token().await?;
            if transport == OpenAiTransport::ResponsesWebSocket {
                let OpenAiRequestBody::Responses(body) = body else {
                    return Err(PureError::ConfigError(
                        "web_socket connection mode requires the Responses API".to_string(),
                    ));
                };
                let raw_stream = responses_websocket::stream_responses(
                    responses_websocket::StreamResponsesInput {
                        api_base,
                        token,
                        provider_headers: endpoint.http_headers.as_ref(),
                        model_headers: &model_info.binding.request.headers,
                        connection_key,
                        model_session: session,
                        body,
                        expected_sent_model,
                        trace: trace.clone(),
                    },
                )
                .await?;
                return Ok(OpenedCompletionStream {
                    events: protocol.decode_stream(wire_api, raw_stream.stream, trace),
                    sent_model: raw_stream.sent_model,
                    idle_timeout: Some(RESPONSES_WEBSOCKET_IDLE_TIMEOUT),
                });
            }
            let capture = wire_capture::capture_http(&body, trace.as_ref()).await?;
            let headers =
                endpoint.request_headers(token.as_deref(), &model_info.binding.request.headers)?;
            let request = match body {
                OpenAiRequestBody::Responses(body) => http_client
                    .post(format!("{api_base}/responses"))
                    .json(&body),
                OpenAiRequestBody::Chat(body) => http_client
                    .post(format!("{api_base}/chat/completions"))
                    .json(&body),
            };
            // Resource and credential validation above must complete before granting this
            // narrow official-session exception. Other routes keep strict media validation.
            let content_type_policy = if endpoint.chatgpt_session.is_some() {
                super::transport::SseContentTypePolicy::AllowMissingForChatGpt
            } else {
                super::transport::SseContentTypePolicy::Required
            };
            let stream = match super::transport::sse(
                request
                    .headers(headers)
                    .header("accept", "text/event-stream"),
                content_type_policy,
            )
            .await
            {
                Ok(stream) => {
                    if let Some(capture) = &capture {
                        capture.record_stage("streamOpened").await?;
                    }
                    stream
                }
                Err(error) => {
                    if let Some(capture) = &capture {
                        capture.record_stage("streamOpenFailed").await?;
                    }
                    return Err(error);
                }
            };

            let raw_stream = stream;
            let raw_stream = wire_capture::observe_http_stream(raw_stream, capture);
            let raw_stream = if model_info.binding.transport.protocol == WireApi::Responses {
                // HTTP has no continuation lease; close the body after the terminal response.
                // WebSocket sources must still be fully drained so their lease can commit.
                futures::stream::unfold((raw_stream, false), |(mut stream, ended)| async move {
                    if ended {
                        return None;
                    }
                    let event = stream.next().await?;
                    let ended = event.as_ref().is_ok_and(|event| {
                        matches!(
                            event.kind.as_str(),
                            "response.completed" | "response.failed" | "response.incomplete"
                        )
                    });
                    Some((event, (stream, ended)))
                })
                .boxed()
            } else {
                raw_stream
            };
            Ok(OpenedCompletionStream {
                events: protocol.decode_stream(wire_api, raw_stream, trace),
                sent_model: expected_sent_model,
                idle_timeout: None,
            })
        }
    }

    pub fn model(&self) -> &ModelInfo {
        &self.model
    }

    pub fn effective_model_capabilities(&self) -> ModelCapabilities {
        self.model
            .capabilities
            .clone()
            .with_native_custom_tools(self.endpoint.uses_native_custom_tools())
    }

    pub fn connection_fingerprint(&self) -> u64 {
        use std::hash::{DefaultHasher, Hash, Hasher};

        let model_info = &self.model;
        let mut hasher = DefaultHasher::new();
        self.endpoint.connection_fingerprint().hash(&mut hasher);
        model_info.model_id.hash(&mut hasher);
        model_info.binding.transport.protocol.hash(&mut hasher);
        model_info
            .binding
            .transport
            .default_connection_mode
            .hash(&mut hasher);
        model_info
            .binding
            .transport
            .supported_connection_modes
            .hash(&mut hasher);
        let mut headers = model_info
            .binding
            .request
            .headers
            .iter()
            .collect::<Vec<_>>();
        headers.sort_by(|left, right| left.0.cmp(right.0));
        for (name, value) in headers {
            name.hash(&mut hasher);
            value.hash(&mut hasher);
        }
        let fingerprint = hasher.finish();
        if fingerprint == 0 { 1 } else { fingerprint }
    }
}

fn duration_millis(duration: Duration) -> u64 {
    u64::try_from(duration.as_millis()).unwrap_or(u64::MAX)
}

#[cfg(test)]
#[path = "invocation_chatgpt_tests.rs"]
mod chatgpt_tests;

#[cfg(test)]
mod timing_tests {
    use super::InferenceTimer;
    use crate::completion::stream::event::{ModelStreamEvent, ToolInputDeltaPayload};
    use futures::{StreamExt, stream};
    use pl_protocol::FirstOutputSource;
    use std::time::Duration;

    fn tool_event(ready: bool, text: Option<&str>) -> ModelStreamEvent {
        let payload = text.map(|text| ToolInputDeltaPayload::FunctionArguments(text.into()));
        if ready {
            ModelStreamEvent::ToolCallReady {
                stream_id: None,
                item_id: "tool".into(),
                call_id: None,
                name: Some("query".into()),
                payload,
            }
        } else {
            ModelStreamEvent::ToolInputCompleted {
                stream_id: None,
                item_id: "tool".into(),
                call_id: None,
                name: Some("query".into()),
                payload,
            }
        }
    }

    #[test]
    fn complete_tool_input_observes_once_and_keeps_time_and_source_paired() {
        for ready in [false, true] {
            let timer = InferenceTimer::start();
            assert_eq!(timer.finish(), None);
            timer.observe(&tool_event(ready, Some("{\"q\":1}")));
            let first = timer.observation.lock().unwrap().first_output;
            timer
                .clone()
                .observe(&tool_event(!ready, Some("{\"q\":1}")));
            timer.observe(&ModelStreamEvent::ReasoningRawDelta {
                id: "reasoning".into(),
                content_index: 0,
                delta: "later".into(),
                provider: None,
            });
            assert_eq!(timer.observation.lock().unwrap().first_output, first);
            timer.observe(&ModelStreamEvent::Completed { response_id: None });
            let timing = timer.finish().unwrap();
            assert_eq!(
                timing.first_output_source,
                FirstOutputSource::CompletedToolInput
            );
            assert_eq!(timing.ttft_millis, first.map(|(millis, _)| millis));
            assert_eq!(
                timing.ttft_millis.unwrap() + timing.decode_millis.unwrap(),
                timing.response_millis
            );
            timer.observe(&tool_event(ready, Some("ignored after terminal")));
            assert_eq!(timer.finish(), Some(timing));
        }
    }

    #[test]
    fn incremental_input_wins_over_completion_and_metadata_never_starts_output() {
        let timer = InferenceTimer::start();
        for ready in [false, true] {
            timer.observe(&tool_event(ready, None));
            timer.observe(&tool_event(ready, Some("")));
        }
        timer.observe(&ModelStreamEvent::text_completed(
            "text".into(),
            pl_protocol::trace::TraceTextChannel::Final,
            None,
            None,
        ));
        timer.observe(&ModelStreamEvent::ReasoningRawDelta {
            id: "reasoning".into(),
            content_index: 0,
            delta: String::new(),
            provider: None,
        });
        assert_eq!(timer.observation.lock().unwrap().first_output, None);
        timer.observe(&ModelStreamEvent::ToolInputDelta {
            stream_id: None,
            item_id: "tool".into(),
            call_id: None,
            name: None,
            payload_delta: ToolInputDeltaPayload::CustomInput("query".into()),
        });
        timer.observe(&tool_event(true, Some("query")));
        timer.observe(&ModelStreamEvent::Completed { response_id: None });
        assert_eq!(
            timer.finish().unwrap().first_output_source,
            FirstOutputSource::Incremental
        );

        let empty = InferenceTimer::start();
        empty.observe(&ModelStreamEvent::Completed { response_id: None });
        let timing = empty.finish().unwrap();
        assert_eq!(timing.first_output_source, FirstOutputSource::Unobserved);
        assert_eq!((timing.ttft_millis, timing.decode_millis), (None, None));
    }

    #[tokio::test]
    async fn non_event_stream_end_preserves_content_timing_and_freezes_once() {
        use crate::completion::stream::{
            CompletionEventStream, StreamCollectContext,
            collect_completion_event_stream_with_idle_timeout,
        };
        use pl_protocol::{PureError, trace::TraceTextChannel};
        use tokio_util::sync::CancellationToken;

        for ending in ["error", "eof", "timeout", "cancel"] {
            let mut timer = InferenceTimer::start();
            let cancellation = CancellationToken::new();
            let tail: CompletionEventStream = match ending {
                "error" => stream::once(async {
                    Err(PureError::Protocol("direct transport failure".into()))
                })
                .boxed(),
                "eof" => stream::empty().boxed(),
                _ => stream::pending().boxed(),
            };
            let events = stream::iter([
                Ok(ModelStreamEvent::text_started(
                    "text".into(),
                    TraceTextChannel::Final,
                    None,
                )),
                Ok(ModelStreamEvent::text_delta(
                    "text".into(),
                    TraceTextChannel::Final,
                    "observed content".into(),
                    None,
                )),
            ])
            .chain(tail)
            .inspect({
                let timer = timer.clone();
                let cancellation = cancellation.clone();
                move |event| {
                    if let Ok(event) = event {
                        timer.observe(event);
                        if ending == "cancel" && event.first_output_source().is_some() {
                            cancellation.cancel();
                        }
                    }
                }
            })
            .boxed();
            let (event_tx, _receiver) = tokio::sync::broadcast::channel(16);
            let on_stream_end = || timer.mark_terminal();
            let failure = collect_completion_event_stream_with_idle_timeout(
                events,
                StreamCollectContext {
                    event_tx: &event_tx,
                    trace: None,
                    trace_sink: None,
                    cancellation: Some(cancellation),
                    model_observation: None,
                    on_stream_end: &on_stream_end,
                },
                Some(Duration::from_millis(1)),
            )
            .await
            .expect_err("the stream has no terminal event");
            assert_eq!(failure.is_cancelled(), ending == "cancel", "{ending}");
            if ending == "error" {
                assert!(failure.to_string().contains("direct transport failure"));
            } else if ending == "eof" {
                assert!(failure.to_string().contains("ended before completion"));
            } else if ending == "timeout" {
                assert!(failure.to_string().contains("idle timeout"));
            }
            let timing = timer.finish().expect("actual collector end must be timed");
            assert_eq!(timing.first_output_source, FirstOutputSource::Incremental);
            assert_eq!(
                timing.ttft_millis.unwrap() + timing.decode_millis.unwrap(),
                timing.response_millis,
                "{ending}"
            );
            // Deterministically make a later observation differ, without a machine-speed bound.
            timer.started_at -= Duration::from_secs(1);
            timer.mark_terminal();
            assert_eq!(timer.finish(), Some(timing), "{ending}");
        }
    }

    #[tokio::test]
    async fn cancellation_at_ready_retry_deadline_keeps_last_attempt_without_sending_again() {
        use super::{InvocationRunner, ModelInvocationContext, ModelSession};
        use crate::{
            completion::{CompletionRequest, Message, MessageContent, MessageRole},
            model::{ModelInfo, ModelTransportProfile},
            protocol::ProtocolEndpoint,
        };
        use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step, responses_text};
        use std::future::{Future, poll_fn};
        use std::task::Poll;
        use tokio_util::sync::CancellationToken;

        let mut events = responses_text("observed output", "failed-attempt", "retry-model");
        events.pop();
        events.push(serde_json::json!({
            "type": "error", "error": {
                "code": "server_error", "message": "retry later", "retry_after_ms": 30000
            }
        }));
        let fixture = FixtureServer::start(vec![Step::prompt(
            Protocol::ResponsesWebSocket,
            "cancel at retry boundary",
            0,
            Reply::WebSocket(events),
        )])
        .await
        .unwrap();
        let mut model = ModelInfo::compatible("retry-model");
        model
            .binding
            .set_transport(ModelTransportProfile::responses_websocket());
        let runner = InvocationRunner::new_with_account_id(
            "fixture",
            ProtocolEndpoint::compatible("fixture", fixture.base_url()),
            model,
        )
        .unwrap();
        let session = ModelSession::default();
        let cancellation = CancellationToken::new();
        let progress = pl_core::model::ModelProgressSender::detached(1024 * 1024);
        let invocation = runner.complete_inner(
            CompletionRequest::builder()
                .messages(vec![Message {
                    role: MessageRole::User,
                    content: MessageContent::text("cancel at retry boundary"),
                    presentation: Default::default(),
                    reasoning_content: None,
                    tool_calls: None,
                    tool_result: None,
                    metadata: Default::default(),
                }])
                .build(),
            ModelInvocationContext::new(session.clone())
                .with_progress(Some(progress.clone()))
                .with_cancellation(Some(cancellation.clone())),
        );
        tokio::pin!(invocation);
        tokio::time::timeout(
            Duration::from_secs(10),
            poll_fn(|cx| {
                assert!(invocation.as_mut().poll(cx).is_pending());
                if progress.latest().observation().generation == 1 {
                    Poll::Ready(())
                } else {
                    Poll::Pending
                }
            }),
        )
        .await
        .unwrap();
        // Own and stop polling the invocation while both readiness conditions are established.
        // Neither the wall clock nor a scheduler race decides when the second request is sent.
        tokio::time::pause();
        tokio::time::advance(Duration::from_secs(31)).await;
        cancellation.cancel();
        let failure = invocation.await.unwrap_err();
        tokio::time::resume();
        assert!(failure.is_cancelled());
        let timing = failure.timing.expect("last finished attempt remains timed");
        assert_eq!(timing.first_output_source, FirstOutputSource::Incremental);
        assert_eq!(
            timing.ttft_millis.unwrap() + timing.decode_millis.unwrap(),
            timing.response_millis
        );
        assert!(
            timing.response_millis < 30_000,
            "backoff is not response time"
        );
        assert_eq!(fixture.recorded().len(), 1, "no second request was sent");
        session.close().await.unwrap();
        assert_eq!(fixture.finish().await.unwrap().len(), 1);
    }
}

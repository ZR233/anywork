//! Shared retry budget, replay safety, fallback and terminal accounting.
use super::OpenAiTransport;
use super::timing::InferenceTimer;
use crate::completion::{
    CompletionFailure, CompletionRequest, CompletionResponse, InferenceAttemptMetadata,
    InferenceAttemptOutcome, InferenceBillingRecord,
};
use crate::runtime::billing::{
    ModelRecoveryStopReason, ModelSubAttemptReceipt, model_sub_attempt_id,
};
use crate::runtime::transport_policy::{
    MODEL_MAX_RETRIES, RESPONSES_WEBSOCKET_MAX_RETRIES, model_request_retry_delay,
};
use crate::runtime::{ModelInvocationContext, ModelRuntime};
use pl_core::model::{ModelContextRecovery, ModelRecoveryPhase};
use pl_protocol::{
    ProviderFailureKind, ProviderFailureStage, ProviderRecovery, PureError, RetryDisposition,
};
use std::sync::atomic::{AtomicU64, Ordering};
use tokio::time::Instant;

type Outcome = std::result::Result<CompletionResponse, CompletionFailure>;

#[derive(Default)]
pub(crate) struct InvocationReport {
    pub(crate) stop: Option<ModelRecoveryStopReason>,
    pub(crate) recovery: Option<ModelContextRecovery>,
    pub(crate) settlements: Vec<pl_core::context::OpaquePayload>,
    pub(crate) retry: Option<u32>,
    pub(crate) usage_is_terminal: bool,
}

impl ModelRuntime {
    pub(super) async fn complete_inner(
        &self,
        request: CompletionRequest,
        context: ModelInvocationContext,
        settlement: &crate::runtime::invocation_context::BoundSettlement,
        mut current: Option<&mut crate::runtime::current::CurrentProducer>,
        report: &mut InvocationReport,
    ) -> Outcome {
        self.validate_context(&request.input)?;
        let cancellation = context
            .cancellation
            .as_ref()
            .expect("complete installs cancellation");
        let admission = async {
            tokio::select! {
                biased;
                () = cancellation.cancelled() => Err(cancelled()),
                lease = context.session.admit() => lease.map_err(CompletionFailure::from),
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
            self.codec,
            request,
        )?;
        let original_trace = context.trace.as_ref();
        static DETACHED_SEQUENCE: AtomicU64 = AtomicU64::new(0);
        let detached_id = || {
            format!(
                "detached:{}:{}",
                std::process::id(),
                DETACHED_SEQUENCE.fetch_add(1, Ordering::Relaxed)
            )
        };
        let detached;
        let identity = match original_trace {
            Some(trace) => trace,
            None => {
                let id = detached_id();
                detached = crate::completion::CompletionTraceContext {
                    session_id: String::new(),
                    turn_id: id.clone(),
                    inference_id: id,
                };
                &detached
            }
        };
        let input_bytes = serde_json::to_vec(&request.input)
            .map_err(PureError::from)?
            .len();
        let original_id = identity.inference_id.as_str();
        let (logical_id, mut retry, earliest_send) = match context
            .members
            .as_ref()
            .and_then(|members| members.context_recovery())
        {
            Some(grant) => {
                let trace = original_trace.expect("thread recovery has an owner identity");
                grant.consume(&trace.session_id, &trace.turn_id, input_bytes, self.connection_fingerprint())
                    .filter(|(_, retry, _)| *retry <= MODEL_MAX_RETRIES)
                    .ok_or_else(|| CompletionFailure::from(PureError::Protocol("context recovery input did not shrink or the grant is no longer available".into())))?
            }
            None => (original_id, 0, None),
        };
        if let Some(deadline) = earliest_send {
            let wait = wait_for_retry(Instant::from_std(deadline), cancellation);
            if let Some(current) = current.as_deref_mut() {
                current.wait(wait, None).await;
            } else {
                wait.await;
            }
        }
        let mut sent = 0_u32;
        let mut websocket_failures = 0_u32;
        let mut attachments_prepared = false;
        let mut refreshed_attachments = false;
        let started_metrics = context.session.orchestration_snapshot();
        let mut http_fallbacks = 0_u64;
        let mut previous: Option<CompletionFailure> = None;
        let mut attachment_repair = None;
        let mut pending_reconnect: Option<(std::time::Instant, u32, Option<String>)> = None;
        'recovery: loop {
            if cancellation.is_cancelled() {
                report.stop = Some(ModelRecoveryStopReason::Cancelled);
                let mut error = match previous.take() {
                    Some(error) => preserve_recovery_failure(attachment_repair.take(), error),
                    None => attachment_repair.take().unwrap_or_else(cancelled),
                };
                error.cancelled = true;
                return Err(error);
            }
            let prepared = if !attachments_prepared && !request.attachments.is_empty() {
                if (previous.is_some() || attachment_repair.is_some())
                    && let Some(progress) = &context.progress
                {
                    progress.finish_recovery(ModelRecoveryPhase::Repairing);
                }
                let preparation = self.prepare_attachments(&mut request, &context);
                if let Some(current) = current.as_deref_mut() {
                    current.wait(preparation, None).await
                } else {
                    preparation.await
                }
            } else {
                Ok(())
            };
            let transport = self.active_transport(&context.session, &context.purpose);
            let preparation_failed = prepared.is_err();
            let (mut error, replay_safe) = match prepared {
                Err((error, replay_safe)) => {
                    if error.is_cancelled()
                        || (replay_safe && error.source.provider_failure_ref().is_none())
                    {
                        report.stop = Some(if error.is_cancelled() {
                            ModelRecoveryStopReason::Cancelled
                        } else {
                            ModelRecoveryStopReason::RepairFailed
                        });
                        return Err(preserve_recovery_failure(
                            attachment_repair.take().or_else(|| previous.take()),
                            error,
                        ));
                    }
                    // Preparation has no inference output or usage to settle. The typed failure
                    // still consumes the same retry budget and follows the same deadline policy.
                    report.retry = Some(retry);
                    (error, replay_safe)
                }
                Ok(()) => {
                    attachments_prepared = true;
                    if cancellation.is_cancelled() {
                        continue 'recovery;
                    }
                    let mut trace = original_trace.cloned();
                    if retry > 0
                        && let Some(trace) = trace.as_mut()
                    {
                        trace.inference_id =
                            format!("{logical_id}-{}-retry-{retry}", transport.trace_label());
                    }
                    let request_started_at = match self.clock.unix_seconds() {
                        Ok(at) => at,
                        Err(local) => {
                            report.stop = Some(ModelRecoveryStopReason::RepairFailed);
                            return Err(preserve_recovery_failure(
                                attachment_repair.take().or_else(|| previous.take()),
                                local.into(),
                            ));
                        }
                    };
                    let inference_timer = InferenceTimer::start();
                    let generation = sent;
                    let mut reconnected_emitted = false;
                    let reconnect_arg = pending_reconnect.as_ref().map(|(at, retry, fallback)| {
                        (
                            pl_core::model::ModelConnectionFact {
                                generation,
                                kind: pl_core::model::ModelConnectionEventKind::Reconnected,
                                transport: transport.trace_label().to_owned(),
                                fallback_transport: fallback.clone(),
                                retry: *retry,
                                max_retries: MODEL_MAX_RETRIES,
                                recoverable: true,
                                reason: None,
                                duration_ms: None,
                            },
                            *at,
                            &mut reconnected_emitted,
                        )
                    });
                    let super::attempt::StreamAttempt {
                        mut result,
                        replay_safe,
                        started,
                    } = self
                        .run_stream_attempt(
                            request.clone(),
                            &context,
                            super::attempt::StreamAttemptExecution {
                                trace,
                                inference_timer: &inference_timer,
                                current: current.as_deref_mut(),
                                generation,
                                pending_reconnect: reconnect_arg,
                            },
                        )
                        .await;
                    if reconnected_emitted {
                        pending_reconnect = None;
                    }
                    if !started {
                        let local = result.expect_err("a transport attempt did not start");
                        report.stop = Some(if local.is_cancelled() {
                            ModelRecoveryStopReason::Cancelled
                        } else {
                            ModelRecoveryStopReason::RepairFailed
                        });
                        return Err(preserve_recovery_failure(
                            attachment_repair.take().or_else(|| previous.take()),
                            local,
                        ));
                    }
                    attachment_repair = None;
                    sent += 1;
                    let timing = inference_timer.finish();
                    report.retry = Some(retry);
                    report.usage_is_terminal = usage_is_terminal(&result);
                    let usage = match &result {
                        Ok(response) => response.accounting.usage.clone(),
                        Err(error) => error.accounting.usage.clone(),
                    };
                    let accounting = self.model.extra.pricing.account(
                        usage,
                        self.pricing_mode,
                        request_started_at,
                    );
                    match &mut result {
                        Ok(response) => {
                            let metrics = context.session.orchestration_snapshot();
                            response.orchestration.transport_attempts = u64::from(sent);
                            response.orchestration.continuation_attempts = metrics
                                .continuation_attempts
                                .saturating_sub(started_metrics.continuation_attempts);
                            response.orchestration.continuation_used = metrics
                                .continuation_used
                                .saturating_sub(started_metrics.continuation_used);
                            response.orchestration.continuation_invalid = metrics
                                .continuation_invalid
                                .saturating_sub(started_metrics.continuation_invalid);
                            response.orchestration.http_fallbacks = http_fallbacks;
                            response.timing = timing;
                            response.accounting = accounting;
                        }
                        Err(error) => {
                            context.close_live_usage();
                            error.timing = timing.map(Box::new);
                            *error.accounting = accounting;
                        }
                    }
                    let receipt = self.sub_attempt_receipt(
                        &request,
                        &result,
                        &context,
                        identity,
                        settlement.turn_id(),
                        logical_id,
                        generation,
                        retry,
                        request_started_at,
                    );
                    let payload = receipt.encode().map_err(PureError::from)?;
                    if let Some(current) = current.as_deref_mut() {
                        current.settle(payload.clone());
                    }
                    report.settlements.push(payload.clone());
                    let saving = settlement.settle(generation, payload);
                    let saved = if let Some(current) = current.as_deref_mut() {
                        current.wait(saving, None).await
                    } else {
                        saving.await
                    };
                    if let Err(local) = saved {
                        report.stop = Some(ModelRecoveryStopReason::SaveFailed);
                        let primary = match result {
                            Err(error) => error,
                            Ok(response) => {
                                let mut failure = CompletionFailure::new(
                                    PureError::LlmError(
                                        "model response settlement could not be saved".into(),
                                    ),
                                    Box::new(response.accounting),
                                )
                                .with_optional_model_observation(response.model_observation);
                                failure.timing = response.timing.map(Box::new);
                                failure.usage_is_terminal = response.usage_is_terminal;
                                failure.presentation_items = response.presentation_items;
                                failure
                            }
                        };
                        return Err(primary
                            .with_recovery_error(PureError::Io(std::io::Error::other(local))));
                    }
                    match result {
                        Ok(response) => return Ok(response),
                        Err(error) => (error, replay_safe),
                    }
                }
            };
            if error.is_cancelled() || cancellation.is_cancelled() {
                error.cancelled = true;
                report.stop = Some(ModelRecoveryStopReason::Cancelled);
                return Err(preserve_recovery_failure(attachment_repair.take(), error));
            }
            if !replay_safe {
                report.stop = Some(ModelRecoveryStopReason::SideEffects);
                if !preparation_failed
                    && error
                        .source
                        .provider_failure_ref()
                        .is_some_and(|failure| failure.kind == ProviderFailureKind::Transport)
                {
                    // A hosted side effect forbids replaying this request, but a broken
                    // WebSocket still needs a durable boundary and next-turn HTTP fallback.
                    let mut fallback_transport = None;
                    if transport == OpenAiTransport::ResponsesWebSocket
                        && self.supports_http_fallback()
                    {
                        let activate = context
                            .session
                            .activate_responses_http_fallback(self.connection_fingerprint());
                        let activated = if let Some(current) = current.as_deref_mut() {
                            current.wait(activate, None).await
                        } else {
                            activate.await
                        };
                        if activated {
                            fallback_transport =
                                Some(OpenAiTransport::Http.trace_label().to_owned());
                        }
                    }
                    if pending_reconnect.is_none() {
                        let fact = pl_core::model::ModelConnectionFact {
                            generation: context.current_generation(),
                            kind: pl_core::model::ModelConnectionEventKind::Disconnected,
                            transport: transport.trace_label().to_owned(),
                            fallback_transport,
                            retry,
                            max_retries: MODEL_MAX_RETRIES,
                            recoverable: false,
                            reason: Some(error.to_string()),
                            duration_ms: None,
                        };
                        match context.admit_connection(fact, current.as_deref_mut()).await {
                            Ok(()) | Err(pl_core::model::ModelMemberError::Closed) => {}
                            Err(pl_core::model::ModelMemberError::Cancelled) => {
                                error.cancelled = true;
                                report.stop = Some(ModelRecoveryStopReason::Cancelled);
                            }
                            Err(cause) => {
                                report.stop = Some(ModelRecoveryStopReason::SaveFailed);
                                error = error
                                    .with_recovery_error(PureError::LlmError(cause.to_string()));
                            }
                        }
                    }
                }
                return Err(preserve_recovery_failure(attachment_repair.take(), error));
            }
            let Some(failure) = error.source.provider_failure_ref() else {
                return Err(error);
            };
            if failure.retry == RetryDisposition::WaitUnrepresentable
                || (failure.retry.retry_after_ms().is_some() && failure.retry_deadline().is_none())
            {
                report.stop = Some(ModelRecoveryStopReason::WaitUnrepresentable);
                return Err(preserve_recovery_failure(attachment_repair.take(), error));
            }
            if !preparation_failed && failure.kind == ProviderFailureKind::ContextLimit {
                if retry < MODEL_MAX_RETRIES
                    && let Some(trace) = original_trace
                    && context.members.is_some()
                {
                    report.recovery = Some(ModelContextRecovery::new(
                        trace.session_id.clone(),
                        trace.turn_id.clone(),
                        trace.inference_id.clone(),
                        retry + 1,
                        input_bytes,
                        self.connection_fingerprint(),
                        failure.retry_deadline(),
                    ));
                    report.stop = Some(ModelRecoveryStopReason::ContextCompactionRequired);
                } else if retry >= MODEL_MAX_RETRIES {
                    report.stop = Some(ModelRecoveryStopReason::BudgetExhausted);
                }
                return Err(error);
            }
            let recovery = failure.context.recovery;
            let can_fallback = !preparation_failed
                && transport == OpenAiTransport::ResponsesWebSocket
                && self.supports_http_fallback();
            let retryable = match recovery {
                ProviderRecovery::HttpFallback => can_fallback,
                ProviderRecovery::RefreshAttachments => !refreshed_attachments,
                ProviderRecovery::FullContext => transport == OpenAiTransport::ResponsesWebSocket,
                ProviderRecovery::None => failure.retry.is_retryable(),
            };
            if !retryable {
                report.stop = Some(if attachment_repair.is_some() {
                    ModelRecoveryStopReason::RepairFailed
                } else {
                    ModelRecoveryStopReason::PermanentFailure
                });
                return Err(preserve_recovery_failure(attachment_repair.take(), error));
            }
            if retry >= MODEL_MAX_RETRIES {
                report.stop = Some(ModelRecoveryStopReason::BudgetExhausted);
                if let Some(progress) = &context.progress {
                    progress.finish_recovery(pl_core::model::ModelRecoveryPhase::Exhausted);
                }
                return Err(preserve_recovery_failure(attachment_repair.take(), error));
            }
            retry += 1;
            let now = Instant::now();
            let deadline = failure
                .retry_deadline()
                .map(Instant::from_std)
                .unwrap_or_else(|| now + model_request_retry_delay(retry, logical_id));
            let is_connection_failure = failure.kind == ProviderFailureKind::Transport;
            if can_fallback && is_connection_failure {
                websocket_failures += 1;
            }
            let recovery = if can_fallback
                && recovery == ProviderRecovery::None
                && is_connection_failure
                && websocket_failures > RESPONSES_WEBSOCKET_MAX_RETRIES
            {
                ProviderRecovery::HttpFallback
            } else {
                recovery
            };
            let phase = if matches!(
                recovery,
                ProviderRecovery::HttpFallback | ProviderRecovery::RefreshAttachments
            ) {
                ModelRecoveryPhase::Repairing
            } else {
                ModelRecoveryPhase::Waiting
            };
            let decision = crate::runtime::ModelRecoveryDecision {
                failure_kind: failure.kind,
                provider_failure: Some(failure.clone()),
                recovery,
                retry,
                max_retries: MODEL_MAX_RETRIES,
                effective_wait_millis: u64::try_from(
                    deadline.saturating_duration_since(now).as_millis(),
                )
                .unwrap_or(u64::MAX),
            };
            if let Err(local) = context.begin_retry(&mut error, decision, phase, preparation_failed)
            {
                report.stop = Some(ModelRecoveryStopReason::RepairFailed);
                return Err(preserve_recovery_failure(
                    attachment_repair.take(),
                    error.with_recovery_error(local),
                ));
            }
            match recovery {
                ProviderRecovery::RefreshAttachments => {
                    let refresh = self.expire_rejected_attachment(&request, &context);
                    let refreshed = if let Some(current) = current.as_deref_mut() {
                        current.wait(refresh, None).await
                    } else {
                        refresh.await
                    };
                    if !refreshed {
                        report.stop = Some(ModelRecoveryStopReason::RepairFailed);
                        return Err(error);
                    }
                    attachments_prepared = false;
                    refreshed_attachments = true;
                }
                ProviderRecovery::HttpFallback => {
                    let activate = context
                        .session
                        .activate_responses_http_fallback(self.connection_fingerprint());
                    let activated = if let Some(current) = current.as_deref_mut() {
                        current.wait(activate, None).await
                    } else {
                        activate.await
                    };
                    http_fallbacks += u64::from(activated);
                }
                ProviderRecovery::FullContext | ProviderRecovery::None => {}
            }
            if is_connection_failure && !preparation_failed {
                let fallback = (recovery == ProviderRecovery::HttpFallback)
                    .then(|| OpenAiTransport::Http.trace_label().to_owned());
                if let Some((_, pending_retry, pending_fallback)) = pending_reconnect.as_mut() {
                    *pending_retry = retry;
                    if fallback.is_some() {
                        *pending_fallback = fallback;
                    }
                } else {
                    let fact = pl_core::model::ModelConnectionFact {
                        generation: context.current_generation(),
                        kind: pl_core::model::ModelConnectionEventKind::Disconnected,
                        transport: transport.trace_label().to_owned(),
                        fallback_transport: fallback.clone(),
                        retry,
                        max_retries: MODEL_MAX_RETRIES,
                        recoverable: true,
                        reason: Some(error.to_string()),
                        duration_ms: None,
                    };
                    match context.admit_connection(fact, current.as_deref_mut()).await {
                        Ok(()) => {
                            pending_reconnect = Some((std::time::Instant::now(), retry, fallback))
                        }
                        Err(pl_core::model::ModelMemberError::Cancelled) => {
                            error.cancelled = true;
                            report.stop = Some(ModelRecoveryStopReason::Cancelled);
                            return Err(error);
                        }
                        Err(pl_core::model::ModelMemberError::Closed) => {}
                        Err(cause) => {
                            report.stop = Some(ModelRecoveryStopReason::SaveFailed);
                            return Err(
                                error.with_recovery_error(PureError::LlmError(cause.to_string()))
                            );
                        }
                    }
                }
            }
            if let Some(progress) = &context.progress {
                progress.finish_recovery(ModelRecoveryPhase::Waiting);
            }
            let backoff = wait_for_retry(deadline, cancellation);
            if let Some(current) = current.as_deref_mut() {
                current.wait(backoff, None).await;
            } else {
                backoff.await;
            }
            if recovery == ProviderRecovery::RefreshAttachments {
                attachment_repair = Some(error);
                previous = None;
            } else {
                previous = Some(error);
            }
        }
    }

    #[allow(clippy::too_many_arguments)]
    fn sub_attempt_receipt(
        &self,
        request: &CompletionRequest,
        result: &Outcome,
        context: &ModelInvocationContext,
        trace: &crate::completion::CompletionTraceContext,
        turn_id: Option<&str>,
        logical_id: &str,
        generation: u32,
        retry: u32,
        recorded_at: i64,
    ) -> ModelSubAttemptReceipt {
        let (
            outcome,
            provider_failure,
            message,
            accounting,
            model_observation,
            timing,
            mut orchestration,
        ) = match result {
            Ok(response) => (
                InferenceAttemptOutcome::Succeeded,
                None,
                None,
                response.accounting.clone(),
                response.model_observation.clone(),
                response.timing,
                response.orchestration.clone(),
            ),
            Err(error) => (
                if error.is_cancelled() {
                    InferenceAttemptOutcome::Cancelled
                } else {
                    InferenceAttemptOutcome::Failed
                },
                error.source.provider_failure_ref().cloned(),
                Some(error.to_string()),
                (*error.accounting).clone(),
                error.model_observation().cloned(),
                error.timing.as_deref().copied(),
                Default::default(),
            ),
        };
        orchestration.transport_attempts = 1;
        let stage = provider_failure
            .as_ref()
            .map_or(ProviderFailureStage::Stream, |failure| {
                failure.context.stage
            });
        ModelSubAttemptReceipt {
            turn_id: turn_id.map(str::to_owned),
            attempt_id: trace.inference_id.clone(),
            logical_request_id: logical_id.to_owned(),
            generation,
            retry,
            provider_failure,
            message,
            billing: InferenceBillingRecord {
                attempt: Some(InferenceAttemptMetadata {
                    logical_request_id: logical_id.to_owned(),
                    core_attempt_id: trace.inference_id.clone(),
                    generation,
                    stage,
                    outcome,
                    usage_is_terminal: usage_is_terminal(result),
                }),
                inference_id: model_sub_attempt_id(&trace.inference_id, generation),
                purpose: Some(context.billing_purpose.to_owned()),
                account_id: self.account_id.clone(),
                account_display_name: None,
                model_id: Some(self.model.base.slug.clone()),
                model_observation,
                effort: request
                    .reasoning
                    .as_ref()
                    .and_then(|reasoning| reasoning.effort.clone()),
                requested_service_tier: Some(crate::runtime::thread_model::requested_service_tier(
                    self, request,
                )),
                context_window: self.context().context_window,
                accounting,
                prompt_generation: context
                    .billing_prompt
                    .as_ref()
                    .map(|prompt| prompt.generation),
                prompt_cache_policy: context
                    .billing_prompt
                    .as_ref()
                    .map(|prompt| prompt.prompt_cache_policy.clone()),
                prefix_changed_reason: context
                    .billing_prompt
                    .as_ref()
                    .map(|prompt| prompt.prefix_changed_reason),
                orchestration,
                timing,
                recorded_at,
            },
        }
    }

    async fn expire_rejected_attachment(
        &self,
        request: &CompletionRequest,
        context: &ModelInvocationContext,
    ) -> bool {
        use crate::completion::AttachmentRepresentation;
        let mut ids = request
            .prepared_content
            .iter()
            .flat_map(|part| &part.sources)
            .filter_map(|source| match source {
                AttachmentRepresentation::ProviderFile { file_id } => Some(file_id),
                _ => None,
            });
        let Some(id) = ids.next() else {
            return false;
        };
        if ids.any(|other| other != id) {
            return false;
        }
        let fingerprint = self.connection_fingerprint();
        let mut files = context.session.uploaded_files.lock().await;
        let before = files.len();
        files.retain(|(owner, _), state| {
            *owner != fingerprint || !matches!(state, crate::runtime::attachments::UploadState::Ready { id: cached, .. } if cached == id)
        });
        files.len() != before
    }
}

fn cancelled() -> CompletionFailure {
    CompletionFailure::cancelled(
        PureError::LlmError("model invocation cancelled".into()),
        Box::default(),
    )
}

fn usage_is_terminal(result: &Outcome) -> bool {
    match result {
        Ok(response) => response.usage_is_terminal,
        Err(error) => error.usage_is_terminal,
    }
}

fn preserve_recovery_failure(
    primary: Option<CompletionFailure>,
    error: CompletionFailure,
) -> CompletionFailure {
    let Some(mut primary) = primary else {
        return error;
    };
    primary.cancelled = error.is_cancelled();
    primary.recovery_error = error.recovery_error.or(Some(error.source));
    primary
}

async fn wait_for_retry(deadline: Instant, cancellation: &tokio_util::sync::CancellationToken) {
    tokio::select! {
        biased;
        () = cancellation.cancelled() => (),
        () = tokio::time::sleep_until(deadline) => (),
    }
}

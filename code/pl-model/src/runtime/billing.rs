//! 从已提交的模型 attempt 事实构造稳定的计费记录。
//!
//! `pl-core` 只负责保存 opaque attempt 事实；模型 receipt 的解释属于本 crate。把这段解码
//! 放在模型边界，Studio、其它宿主和历史查询都能复用同一套语义，而无需复制 provider
//! receipt 解析或读取存储表。

use pl_core::model::ModelUsage;
use pl_core::thread::{AttemptOutcome, journal::AttemptUpdate};
use pl_protocol::{InferenceAccounting, InferenceBillingRecord};

use super::ModelCallBinding;
use pl_core::context::{ContextContent, OpaquePayload};
use pl_core::model::{
    ModelError, ModelFailureKind, ModelStepOutput, ModelToolCall, ModelUsageBinding,
};
use serde::Deserialize;

// These projections intentionally skip replay, raw provider output, presentation and progress.
#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct BillingRequest {
    binding: ModelCallBinding,
    reasoning: Option<crate::completion::ReasoningConfig>,
    prompt: Option<super::ThreadPromptSnapshot>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct BillingFacts {
    content: Option<String>,
    accounting: InferenceAccounting,
    model_observation: Option<pl_protocol::InferenceModelObservation>,
    timing: Option<pl_protocol::InferenceTiming>,
    #[serde(default)]
    orchestration: pl_protocol::InferenceOrchestrationMetrics,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct BillingFailure {
    binding: ModelCallBinding,
    accounting: InferenceAccounting,
    model_observation: Option<pl_protocol::InferenceModelObservation>,
    timing: Option<pl_protocol::InferenceTiming>,
    #[serde(default)]
    orchestration: pl_protocol::InferenceOrchestrationMetrics,
}

#[derive(Deserialize)]
struct BillingResponse {
    binding: ModelCallBinding,
    response: BillingFacts,
}

#[derive(Deserialize)]
struct BillingFrame {
    receipt: BillingResponse,
    bindings: Vec<ModelToolCall>,
}

#[derive(Debug, thiserror::Error)]
enum BillingAssociationError {
    #[error("response receipt differs from its visible text")]
    VisibleText,
    #[error("response receipt differs from its tool bindings")]
    ToolBindings,
    #[error("terminal model binding differs from the request's frozen {field}")]
    FrozenBinding { field: &'static str },
    #[error("model binding differs from the admitted usage binding's {field}")]
    UsageBinding { field: &'static str },
}

fn invalid(source: impl std::error::Error + Send + Sync + 'static) -> ModelError {
    super::thread_model::failure(ModelFailureKind::UnsupportedContent, source)
}

fn decode<T: serde::de::DeserializeOwned>(
    payload: &OpaquePayload,
    format: &str,
    version: u32,
) -> Result<T, ModelError> {
    if payload.format() != format || payload.version() != version {
        return Err(invalid(std::io::Error::other(
            "unsupported model billing receipt",
        )));
    }
    serde_json::from_str(payload.content()).map_err(invalid)
}

fn response_facts(output: &ModelStepOutput) -> Result<Option<BillingResponse>, ModelError> {
    let mut frames = output.content.iter().filter_map(|content| match content {
        ContextContent::Opaque { payload } if payload.format() == "pl.model.assistant" => {
            Some(payload)
        }
        _ => None,
    });
    let Some(payload) = frames.next() else {
        return Ok(None);
    };
    if frames.next().is_some() {
        return Err(invalid(std::io::Error::other(
            "repeated model billing receipt",
        )));
    }
    let frame: BillingFrame = decode(
        payload,
        "pl.model.assistant",
        super::thread_model::FRAME_VERSION,
    )?;
    let visible = output.content.iter().filter_map(|content| match content {
        ContextContent::Text { text } => Some(text.as_ref()),
        ContextContent::Opaque { .. } | ContextContent::Resource { .. } => None,
    });
    if !visible.eq(frame.receipt.response.content.as_deref()) {
        return Err(invalid(BillingAssociationError::VisibleText));
    }
    if frame.bindings != output.tool_calls {
        return Err(invalid(BillingAssociationError::ToolBindings));
    }
    Ok(Some(frame.receipt))
}

fn validate_binding(
    request: Option<&BillingRequest>,
    terminal: Option<&ModelCallBinding>,
    usage: Option<&ModelUsageBinding>,
) -> Result<(), ModelError> {
    let Some(terminal) = terminal else {
        return Ok(());
    };
    if let Some(request) = request {
        let request = &request.binding;
        for (field, matches) in [
            ("account", request.account_id == terminal.account_id),
            ("model", request.model_id == terminal.model_id),
            ("protocol", request.protocol == terminal.protocol),
            ("wire API", request.wire_api == terminal.wire_api),
            ("isolation", request.isolation == terminal.isolation),
            ("purpose", request.purpose == terminal.purpose),
            (
                "context window",
                request.context_window == terminal.context_window,
            ),
            (
                "maximum context window",
                request.max_context_window == terminal.max_context_window,
            ),
            (
                "automatic compaction limit",
                request.auto_compact_limit == terminal.auto_compact_limit,
            ),
        ] {
            if !matches {
                return Err(invalid(BillingAssociationError::FrozenBinding { field }));
            }
        }
    }
    if let Some(usage) = usage {
        for (field, matches) in [
            (
                "route",
                usage
                    .route_identity
                    .as_ref()
                    .is_none_or(|route| *route == terminal.route_identity()),
            ),
            ("model", usage.model == terminal.model_id),
            (
                "context window",
                usage.context_window == terminal.context_window,
            ),
            (
                "maximum context window",
                usage.max_context_window == terminal.max_context_window,
            ),
            (
                "automatic compaction limit",
                usage.auto_compact_limit == terminal.auto_compact_limit,
            ),
        ] {
            if !matches {
                return Err(invalid(BillingAssociationError::UsageBinding { field }));
            }
        }
    }
    Ok(())
}

/// 从一个已终态的模型 attempt 事实读取完整 billing 记录。
///
/// 请求 receipt 提供绑定、上下文窗口和 prompt cache 诊断；响应或失败 receipt 提供真实
/// provider 用量、模型观测、时延和编排数据。运行中返回 `None`；中断保留冻结绑定和未知用量，
/// 不从当前配置猜测历史信息，也不反序列化完整响应或展示内容。
///
/// # Errors
/// 返回 receipt 格式、版本或内容损坏错误。调用方应把这类错误作为历史数据损坏处理，不能
/// 用零用量替代。
pub fn model_attempt_billing(
    attempt: &AttemptUpdate,
    recorded_at: i64,
) -> Result<Option<InferenceBillingRecord>, crate::runtime::ModelError> {
    let output = match &attempt.outcome {
        AttemptOutcome::Running => return Ok(None),
        AttemptOutcome::Interrupted => None,
        AttemptOutcome::Committed(output) | AttemptOutcome::Rejected { output, .. } => {
            Some(Ok(output))
        }
        AttemptOutcome::Failed(error) => Some(Err(error.as_ref())),
        AttemptOutcome::Cancelled { result } => {
            Some(result.as_ref().map_err(std::sync::Arc::as_ref))
        }
    };
    let request = attempt
        .request_metadata
        .as_ref()
        .map(|payload| {
            decode::<BillingRequest>(
                payload,
                "pl.model.prepared-request",
                super::thread_model::REQUEST_RECEIPT_VERSION,
            )
        })
        .transpose()?;
    let (binding, accounting, model_observation, timing, orchestration) = match output {
        Some(Ok(output)) => match response_facts(output)? {
            Some(receipt) => (
                Some(receipt.binding),
                receipt.response.accounting,
                receipt.response.model_observation,
                receipt.response.timing,
                receipt.response.orchestration,
            ),
            None => (
                request.as_ref().map(|request| request.binding.clone()),
                unknown(&output.usage),
                None,
                None,
                Default::default(),
            ),
        },
        Some(Err(error)) => match error
            .details
            .as_ref()
            .map(|payload| {
                decode::<BillingFailure>(
                    payload,
                    "pl.model.failure",
                    super::thread_model::FAILURE_RECEIPT_VERSION,
                )
            })
            .transpose()?
        {
            Some(receipt) => (
                Some(receipt.binding),
                receipt.accounting,
                receipt.model_observation,
                receipt.timing,
                receipt.orchestration,
            ),
            None => (
                request.as_ref().map(|request| request.binding.clone()),
                unknown(&error.usage),
                None,
                None,
                Default::default(),
            ),
        },
        None => (
            request.as_ref().map(|request| request.binding.clone()),
            unknown(&ModelUsage::default()),
            None,
            None,
            Default::default(),
        ),
    };
    validate_binding(
        request.as_ref(),
        binding.as_ref(),
        attempt.usage_binding.as_ref(),
    )?;
    // The configured `model_id` is a frozen routing fact. The sent alias and the vendor's
    // reported name stay diagnostics inside `model_observation`; they never substitute it.
    let account_id = binding
        .as_ref()
        .map_or_else(String::new, |binding| binding.account_id.clone());
    let model_id = binding
        .as_ref()
        .map(|binding| binding.model_id.clone())
        .filter(|model_id| !model_id.is_empty())
        .or_else(|| {
            attempt
                .usage_binding
                .as_ref()
                .map(|binding| binding.model.clone())
        });
    Ok(Some(InferenceBillingRecord {
        inference_id: attempt.attempt_id.clone(),
        purpose: binding.as_ref().map(|binding| binding.purpose.clone()),
        account_id,
        account_display_name: None,
        model_id,
        model_observation,
        effort: request
            .as_ref()
            .and_then(|request| request.reasoning.as_ref())
            .and_then(|reasoning| reasoning.effort.clone()),
        context_window: binding
            .as_ref()
            .and_then(|binding| binding.context_window)
            .or_else(|| {
                attempt
                    .usage_binding
                    .as_ref()
                    .and_then(|binding| binding.context_window)
            }),
        accounting,
        prompt_generation: request
            .as_ref()
            .and_then(|request| request.prompt.as_ref())
            .map(|prompt| prompt.generation),
        prompt_cache_policy: request
            .as_ref()
            .and_then(|request| request.prompt.as_ref())
            .map(|prompt| prompt.prompt_cache_policy.clone()),
        prefix_changed_reason: request
            .as_ref()
            .and_then(|request| request.prompt.as_ref())
            .map(|prompt| prompt.prefix_changed_reason),
        orchestration,
        timing,
        recorded_at,
    }))
}

fn unknown(usage: &ModelUsage) -> InferenceAccounting {
    InferenceAccounting {
        usage: crate::model::usage::usage_report(usage),
        ..Default::default()
    }
}

#[cfg(test)]
mod tests {
    use super::model_attempt_billing;
    use pl_core::context::{ContextContent, OpaquePayload};
    use pl_core::model::{ModelError, ModelFailureKind, ModelStepOutput, ModelUsage};
    use pl_core::thread::{AttemptOutcome, journal::AttemptUpdate};
    use serde_json::json;

    fn attempt(outcome: AttemptOutcome) -> AttemptUpdate {
        AttemptUpdate {
            request_metadata: Some(
                OpaquePayload::new(
                    "pl.model.prepared-request",
                    2,
                    json!({
                        "binding": binding(), "reasoning": null, "prompt": null
                    })
                    .to_string(),
                )
                .unwrap(),
            ),
            usage_binding: None,
            tool_projection: None,
            turn_id: "turn".into(),
            attempt_id: "attempt".into(),
            retry_of: None,
            input_revision: 1,
            tools: Default::default(),
            outcome,
            input_estimate: None,
        }
    }

    fn binding() -> serde_json::Value {
        json!({
            "accountId":"account", "modelId":"frozen-model", "protocol":crate::protocol::ProtocolKind::OpenAi,
            "wireApi":crate::protocol::WireApi::Responses, "isolation":"frozen-route", "purpose":"turn",
            "contextWindow": 16000
        })
    }

    fn bound_output(binding: serde_json::Value) -> ModelStepOutput {
        let tools = vec![pl_core::model::ModelToolCall {
            presentation_contract: None,
            call_id: "call".into(),
            tool_id: "query".into(),
            arguments: OpaquePayload::new("json", 1, "{\"q\":1}").unwrap(),
            rejection: None,
        }];
        ModelStepOutput {
            attempt_id: "attempt".into(),
            base_context_revision: 1,
            content: vec![
                ContextContent::Text {
                    text: "answer".into(),
                },
                ContextContent::Opaque {
                    payload: OpaquePayload::new(
                        "pl.model.assistant",
                        super::super::thread_model::FRAME_VERSION,
                        json!({
                            "receipt": {
                                "binding": binding,
                                "response": {
                                    "content": "answer",
                                    "accounting": pl_protocol::InferenceAccounting::default(),
                                    "modelObservation": {
                                        "configuredModel":"frozen-model",
                                        "sentModel":"wire-alias",
                                        "reportedModel":"vendor-snapshot"
                                    }
                                }
                            },
                            "bindings": tools
                        })
                        .to_string(),
                    )
                    .unwrap(),
                },
            ],
            tool_calls: tools,
            private_context: None,
            usage: Default::default(),
        }
    }

    fn bound_failure(binding: serde_json::Value) -> std::sync::Arc<ModelError> {
        std::sync::Arc::new(ModelError {
            kind: ModelFailureKind::Unavailable,
            usage: Box::default(),
            source: None,
            details: Some(Box::new(
                OpaquePayload::new(
                    "pl.model.failure",
                    super::super::thread_model::FAILURE_RECEIPT_VERSION,
                    json!({
                        "binding": binding,
                        "accounting": pl_protocol::InferenceAccounting::default()
                    })
                    .to_string(),
                )
                .unwrap(),
            )),
        })
    }

    fn assert_association_error(attempt: &AttemptUpdate) {
        let error = model_attempt_billing(attempt, 42)
            .expect_err("conflicting facts must not produce a bill");
        assert_eq!(error.kind, ModelFailureKind::UnsupportedContent);
    }

    #[test]
    fn response_billing_rejects_tool_binding_mismatch() {
        let output = bound_output(binding());
        let valid = model_attempt_billing(&attempt(AttemptOutcome::Committed(output.clone())), 42)
            .unwrap()
            .unwrap();
        assert_eq!(valid.model_id.as_deref(), Some("frozen-model"));
        let observation = valid.model_observation.unwrap();
        assert_ne!(observation.sent_model, observation.reported_model.unwrap());
        let mut mismatched = output;
        mismatched.tool_calls[0].arguments = OpaquePayload::new("json", 1, "{\"q\":2}").unwrap();
        assert_association_error(&attempt(AttemptOutcome::Committed(mismatched)));
    }

    #[test]
    fn response_billing_rejects_visible_text_mismatch() {
        let mut output = bound_output(binding());
        output.content[0] = ContextContent::Text {
            text: "different answer".into(),
        };
        assert_association_error(&attempt(AttemptOutcome::Committed(output)));
    }

    #[test]
    fn terminal_billing_rejects_conflicting_frozen_bindings() {
        for (field, conflicting) in [
            ("accountId", json!("other-account")),
            ("modelId", json!("other-model")),
            ("protocol", json!(crate::protocol::ProtocolKind::DeepSeek)),
            ("wireApi", json!(crate::protocol::WireApi::ChatCompletions)),
            ("isolation", json!("other-route")),
            ("purpose", json!("title")),
            ("contextWindow", json!(32000)),
            ("maxContextWindow", json!(64000)),
            ("autoCompactLimit", json!(12000)),
        ] {
            let mut conflicting_binding = binding();
            conflicting_binding[field] = conflicting;
            let output = bound_output(conflicting_binding.clone());
            let error = bound_failure(conflicting_binding);
            for outcome in [
                AttemptOutcome::Committed(output.clone()),
                AttemptOutcome::Rejected {
                    output: output.clone(),
                    reason: pl_core::thread::ModelOutputViolation::ToolPermissionRevoked,
                },
                AttemptOutcome::Failed(error.clone()),
                AttemptOutcome::Cancelled { result: Ok(output) },
                AttemptOutcome::Cancelled { result: Err(error) },
            ] {
                assert_association_error(&attempt(outcome));
            }
        }
    }

    #[test]
    fn billing_rejects_conflicting_admitted_usage_binding() {
        let binding: super::ModelCallBinding = serde_json::from_value(binding()).unwrap();
        let usage = pl_core::model::ModelUsageBinding {
            route_identity: Some(binding.route_identity()),
            model: binding.model_id.clone(),
            context_window: binding.context_window,
            max_context_window: binding.max_context_window,
            auto_compact_limit: binding.auto_compact_limit,
        };
        let mut valid = attempt(AttemptOutcome::Interrupted);
        valid.usage_binding = Some(usage.clone());
        let record = model_attempt_billing(&valid, 42).unwrap().unwrap();
        assert_eq!(record.accounting.usage, Default::default());
        for field in ["route", "model", "context", "max", "limit"] {
            let mut invalid = valid.clone();
            let usage = invalid.usage_binding.as_mut().unwrap();
            match field {
                "route" => usage.route_identity = Some("other-route".into()),
                "model" => usage.model = "other-model".into(),
                "context" => usage.context_window = Some(32000),
                "max" => usage.max_context_window = Some(64000),
                "limit" => usage.auto_compact_limit = Some(12000),
                _ => unreachable!(),
            }
            assert_association_error(&invalid);
        }
    }

    #[test]
    fn terminal_fallback_usage_preserves_missing_zero_and_reported_totals() {
        for usage in [
            ModelUsage {
                total_tokens: Some(19),
                ..Default::default()
            },
            ModelUsage {
                input_tokens: Some(2),
                output_tokens: Some(3),
                cache_read_tokens: Some(1),
                cache_write_tokens: Some(1),
                reasoning_tokens: Some(2),
                total_tokens: Some(99),
            },
            ModelUsage {
                input_tokens: Some(0),
                output_tokens: Some(0),
                total_tokens: Some(0),
                cache_read_tokens: Some(0),
                ..Default::default()
            },
            ModelUsage {
                input_tokens: Some(2),
                output_tokens: Some(3),
                ..Default::default()
            },
        ] {
            let output = ModelStepOutput {
                attempt_id: "attempt".into(),
                base_context_revision: 1,
                content: vec![],
                tool_calls: vec![],
                private_context: None,
                usage: usage.clone(),
            };
            let error = std::sync::Arc::new(ModelError {
                kind: ModelFailureKind::Unavailable,
                details: None,
                usage: Box::new(usage.clone()),
                source: None,
            });
            for outcome in [
                AttemptOutcome::Committed(output.clone()),
                AttemptOutcome::Rejected {
                    output: output.clone(),
                    reason: pl_core::thread::ModelOutputViolation::ToolPermissionRevoked,
                },
                AttemptOutcome::Failed(error.clone()),
                AttemptOutcome::Cancelled { result: Err(error) },
                AttemptOutcome::Cancelled { result: Ok(output) },
            ] {
                let record = model_attempt_billing(&attempt(outcome), 42)
                    .unwrap()
                    .unwrap();
                assert_eq!(
                    crate::model::usage::model_usage(&record.accounting.usage),
                    usage
                );
                assert_eq!(record.model_id.as_deref(), Some("frozen-model"));
                assert_eq!(record.account_id, "account");
            }
        }
        let interrupted = model_attempt_billing(&attempt(AttemptOutcome::Interrupted), 42)
            .unwrap()
            .unwrap();
        assert_eq!(interrupted.model_id.as_deref(), Some("frozen-model"));
        assert_eq!(interrupted.context_window, Some(16000));
        assert_eq!(interrupted.accounting.usage, Default::default());
    }

    #[test]
    fn lightweight_receipts_keep_terminal_accounting_and_timing() {
        let accounting = pl_protocol::InferenceAccounting {
            usage: pl_protocol::UsageReport {
                total_tokens: Some(47),
                ..Default::default()
            },
            ..Default::default()
        };
        let timing = pl_protocol::InferenceTiming {
            first_output_source: pl_protocol::FirstOutputSource::CompletedToolInput,
            ttft_millis: Some(12),
            decode_millis: Some(0),
            response_millis: 12,
        };
        let facts = json!({
            "accounting": accounting, "timing": timing, "modelObservation": null,
            "orchestration": {"transportAttempts": 2},
            "presentationItems": [], "replay": null, "content": null,
            "model": "frozen-model"
        });
        let output = ModelStepOutput {
            attempt_id: "attempt".into(),
            base_context_revision: 1,
            tool_calls: vec![],
            private_context: None,
            usage: Default::default(),
            content: vec![ContextContent::Opaque {
                payload: OpaquePayload::new(
                    "pl.model.assistant",
                    super::super::thread_model::FRAME_VERSION,
                    json!({"receipt": {"binding": binding(), "response": facts}, "bindings":[]})
                        .to_string(),
                )
                .unwrap(),
            }],
        };
        let mut failure = facts.clone();
        failure["binding"] = binding();
        let error = std::sync::Arc::new(ModelError {
            kind: ModelFailureKind::Unavailable,
            usage: Box::default(),
            source: None,
            details: Some(Box::new(
                OpaquePayload::new(
                    "pl.model.failure",
                    super::super::thread_model::FAILURE_RECEIPT_VERSION,
                    failure.to_string(),
                )
                .unwrap(),
            )),
        });
        for outcome in [
            AttemptOutcome::Committed(output),
            AttemptOutcome::Failed(error.clone()),
            AttemptOutcome::Cancelled { result: Err(error) },
        ] {
            let record = model_attempt_billing(&attempt(outcome), 42)
                .unwrap()
                .unwrap();
            assert_eq!(record.accounting, accounting);
            assert_eq!(record.timing, Some(timing));
            assert_eq!(record.orchestration.transport_attempts, 2);
        }
    }

    #[test]
    fn running_attempts_do_not_look_like_completed_billing() {
        let attempt = AttemptUpdate {
            request_metadata: None,
            usage_binding: None,
            tool_projection: None,
            turn_id: "turn".into(),
            attempt_id: "attempt".into(),
            retry_of: None,
            input_revision: 1,
            tools: Default::default(),
            outcome: AttemptOutcome::Running,
            input_estimate: None,
        };
        assert_eq!(
            model_attempt_billing(&attempt, 42).expect("running is valid"),
            None
        );
    }
}
